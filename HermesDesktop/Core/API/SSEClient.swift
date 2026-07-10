import Foundation
import OSLog

// MARK: - Logger

private extension Logger {
    /// Logger for SSE stream events and errors.
    static let sse = Logger(subsystem: "com.hermes-desktop", category: "sse")
}

// MARK: - SSEClient

/// Parses Server-Sent Events from the Hermes Runs API into an `AsyncStream<RunEvent>`.
///
/// Usage:
/// ```swift
/// let client = SSEClient()
/// for await event in client.connect(url: streamURL, token: apiKey) {
///     switch event.type {
///     case .textDelta:  print(event.content ?? "")
///     case .runCompleted: print("Done")
///     default: break
///     }
/// }
/// ```
///
/// ## Concurrency
/// `SSEClient` is an `actor` — callers from any isolation domain are safe.
/// Each `connect(...)` call spawns its own detached `Task` that reads the byte
/// stream, parses SSE frames, and yields `RunEvent` values. The stream
/// terminates on `run.completed`, `run.failed`, connection end, or cancellation.
public actor SSEClient {

    // MARK: - Properties

    private let session: URLSession
    private let decoder: JSONDecoder

    // MARK: - Initialization

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    /// Creates an SSEClient with a custom URLSession (for testing).
    public init(session: URLSession) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    // MARK: - Connect

    /// Opens an SSE connection and returns an `AsyncStream` of `RunEvent` values.
    ///
    /// The returned stream finishes when:
    ///   - A `run.completed` or `run.failed` event is received
    ///   - The underlying HTTP connection drops
    ///   - The calling task (or the stream consumer) cancels the work
    ///
    /// - Parameters:
    ///   - url: The full Hermes Runs SSE endpoint URL.
    ///   - token: A Bearer token for authentication.
    /// - Returns: An unbounded `AsyncStream<RunEvent>` that must be consumed.
    internal func connect(url: URL, token: String) -> AsyncStream<RunEvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                await Self.runStream(
                    url: url,
                    token: token,
                    session: session,
                    decoder: decoder,
                    continuation: continuation
                )
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Stream Runner (non-isolated)

    /// Reads the SSE byte stream, parses events, and yields them to the continuation.
    ///
    /// Designed as a `static` function so it can be called from the non-isolated
    /// `Task` closure created inside `connect(...)` without crossing actor boundaries.
    ///
    /// Splits the raw byte stream into lines manually instead of using
    /// `URLSession.AsyncBytes.lines` — on this platform that sequence does not
    /// reliably yield empty lines for blank-line event delimiters, which
    /// silently merged every event of a run into a single garbled one (only
    /// the last `event:`/`data:` value of the whole run ever got parsed).
    /// Event framing here follows the SSE dispatch algorithm (WHATWG HTML
    /// §9.2.6): multiple `data:` lines accumulate (joined with `\n`, not
    /// overwritten) and a block dispatches only on a blank line.
    private static func runStream(
        url: URL,
        token: String,
        session: URLSession,
        decoder: JSONDecoder,
        continuation: AsyncStream<RunEvent>.Continuation
    ) async {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        do {
            let (bytes, response) = try await session.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.sse.error("Non-HTTP response received from SSE endpoint")
                continuation.finish()
                return
            }

            guard (200 ... 299).contains(httpResponse.statusCode) else {
                Logger.sse.error("SSE endpoint returned HTTP \(httpResponse.statusCode)")
                continuation.finish()
                return
            }

            // Per-event field accumulators (SSE dispatch algorithm).
            var eventType: String?
            var dataLines: [String] = []
            var lineBytes: [UInt8] = []
            var stopped = false

            func dispatchPendingEvent() {
                guard eventType != nil || !dataLines.isEmpty else { return }
                let data = dataLines.isEmpty ? nil : dataLines.joined(separator: "\n")
                let event = eventType
                eventType = nil
                dataLines.removeAll(keepingCapacity: true)
                if processEvent(event: event, data: data, decoder: decoder, continuation: continuation) {
                    stopped = true
                }
            }

            func consume(line: String) {
                if line.isEmpty {
                    dispatchPendingEvent()
                    return
                }
                // Comment lines start with ':' per spec — ignored (servers
                // use these for keep-alive pings on long-running streams).
                if line.hasPrefix(":") {
                    return
                }
                guard let colonIndex = line.firstIndex(of: ":") else {
                    return
                }

                let field = line[line.startIndex ..< colonIndex]
                    .trimmingCharacters(in: .whitespaces)

                var value = line[line.index(after: colonIndex)...]
                // Per spec, strip at most one leading space — not full
                // trimming, which could corrupt intentional content.
                if value.first == " " {
                    value = value.dropFirst()
                }

                switch field {
                case "event":
                    eventType = String(value)
                case "data":
                    dataLines.append(String(value))
                default:
                    break
                }
            }

            for try await byte in bytes {
                guard !Task.isCancelled, !stopped else { break }

                if byte == 0x0A {
                    // Strip a trailing \r so CRLF and LF line endings both work.
                    if lineBytes.last == 0x0D {
                        lineBytes.removeLast()
                    }
                    let line = String(decoding: lineBytes, as: UTF8.self)
                    lineBytes.removeAll(keepingCapacity: true)
                    consume(line: line)
                    if stopped { break }
                } else {
                    lineBytes.append(byte)
                }
            }

            if !stopped {
                // Flush a trailing partial line with no terminating LF, then
                // any event left pending by a missing final blank line.
                if !lineBytes.isEmpty {
                    consume(line: String(decoding: lineBytes, as: UTF8.self))
                }
                dispatchPendingEvent()
            }

        } catch is CancellationError {
            Logger.sse.debug("SSE stream cancelled")
        } catch {
            Logger.sse.error("SSE stream error: \(error.localizedDescription)")
        }

        continuation.finish()
    }

    // MARK: - Event Mapping

    /// Maps one accumulated SSE event's fields to a `RunEvent` and yields it.
    ///
    /// - Returns: `true` if this was a terminal event (`run.completed` /
    ///   `run.failed`) — the caller should stop reading further bytes.
    private static func processEvent(
        event: String?,
        data: String?,
        decoder: JSONDecoder,
        continuation: AsyncStream<RunEvent>.Continuation
    ) -> Bool {
        guard let runEvent = Self.mapToRunEvent(event: event, data: data, decoder: decoder) else {
            Logger.sse.warning("Failed to map SSE event to RunEvent, skipping (event: \(event ?? "nil"))")
            return false
        }

        continuation.yield(runEvent)

        guard runEvent.type == .runCompleted || runEvent.type == .runFailed else {
            return false
        }
        continuation.finish()
        return true
    }

    /// Maps a parsed SSE message to a `RunEvent`.
    ///
    /// The `data:` field (if present) is decoded as JSON. A flexible decoding
    /// strategy handles both snake_case (`tool_name`) and camelCase (`toolName`)
    /// keys, with all fields optional to account for event-type variance.
    ///
    /// - Parameters:
    ///   - event: The accumulated `event:` field, if any.
    ///   - data: The accumulated `data:` field (multiple `data:` lines already
    ///     joined with `\n`), if any.
    ///   - decoder: The `JSONDecoder` to use for decoding the data payload.
    /// - Returns: A `RunEvent`, or `nil` if the event type is unknown or data is
    ///   malformed.
    private static func mapToRunEvent(
        event: String?,
        data: String?,
        decoder: JSONDecoder
    ) -> RunEvent? {
        // Event type: try SSE "event:" field first, then JSON "event" field
        let eventField: String
        if let sseEvent = event {
            eventField = sseEvent
        } else if let dataStr = data, let jsonData = dataStr.data(using: .utf8),
                  let envelope = try? decoder.decode(RunEventPayload.self, from: jsonData),
                  let jsonEvent = envelope.event {
            eventField = jsonEvent
        } else {
            Logger.sse.warning("SSE event missing 'event' field (both SSE header and JSON)")
            return nil
        }

        guard let eventType = RunEventType(rawValue: eventField) else {
            Logger.sse.warning("Ignoring unknown SSE event type: \(eventField)")
            return nil
        }

        let payload: RunEventPayload? = {
            guard let data, !data.isEmpty, let jsonData = data.data(using: .utf8) else {
                return nil
            }
            do {
                return try decoder.decode(RunEventPayload.self, from: jsonData)
            } catch {
                Logger.sse.error("Failed to decode SSE data for event '\(eventField)': \(error.localizedDescription). Data: \(data.prefix(500))")
                return nil
            }
        }()

        // Map API fields: "message.delta" uses "delta", "run.completed" uses "output",
        // "reasoning.available" uses "text". Unify into RunEvent.content.
        let unifiedContent = payload?.delta ?? payload?.output ?? payload?.text ?? payload?.content

        return RunEvent(
            type: eventType,
            content: unifiedContent,
            toolName: payload?.toolName,
            toolInput: payload?.toolInput,
            toolOutput: payload?.toolOutput,
            error: payload?.error
        )
    }
}

// MARK: - RunEventPayload

/// Flexible decoding structure for SSE `data:` field JSON payloads.
///
/// All properties are optional because different `RunEventType` values carry
/// different combinations of fields. A single `text_delta` event has
/// `content` but no tool fields; a `tool_call` has `toolName` + `toolInput`
/// but no `content`.
private struct RunEventPayload: Decodable, Sendable {
    let event: String?
    let content: String?
    let delta: String?
    let output: String?
    let text: String?
    let toolName: String?
    let toolInput: String?
    let toolOutput: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case event
        case content
        case delta
        case output
        case text
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case toolOutput = "tool_output"
        case error
    }
}
