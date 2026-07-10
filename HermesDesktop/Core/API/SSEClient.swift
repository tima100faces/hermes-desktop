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
/// terminates on `run_completed`, `run_failed`, connection end, or cancellation.
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
    ///   - A `run_completed` or `run_failed` event is received
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

            // Accumulates lines that belong to the current (incomplete) event block.
            var currentEventLines: [String] = []

            for try await line in bytes.lines {
                guard !Task.isCancelled else { break }

                if line.isEmpty {
                    guard !currentEventLines.isEmpty else { continue }

                    let eventBlock = currentEventLines.joined(separator: "\n")
                    currentEventLines.removeAll(keepingCapacity: true)

                    processEventBlock(eventBlock, decoder: decoder, continuation: continuation)

                    // If the stream has finished (terminal event), stop reading.
                    if Task.isCancelled {
                        break
                    }
                } else {
                    currentEventLines.append(line)
                }
            }

            // Flush any remaining lines if the stream ended without a trailing blank line.
            if !currentEventLines.isEmpty {
                let eventBlock = currentEventLines.joined(separator: "\n")
                processEventBlock(eventBlock, decoder: decoder, continuation: continuation)
            }

        } catch is CancellationError {
            Logger.sse.debug("SSE stream cancelled")
        } catch {
            Logger.sse.error("SSE stream error: \(error.localizedDescription)")
        }

        continuation.finish()
    }

    // MARK: - Process Event Block

    /// Parses a raw SSE event block and yields the resulting `RunEvent` (if any).
    ///
    /// If the event is a terminal type (`run_completed` or `run_failed`), the
    /// continuation is finished and the caller should stop reading.
    private static func processEventBlock(
        _ block: String,
        decoder: JSONDecoder,
        continuation: AsyncStream<RunEvent>.Continuation
    ) {
        guard !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        guard let parsed = Self.parseSSEEvent(block) else {
            Logger.sse.warning("Failed to parse SSE event block: \(block.prefix(200))")
            return
        }

        guard let runEvent = Self.mapToRunEvent(parsed, decoder: decoder) else {
            Logger.sse.warning("Failed to map SSE event to RunEvent, skipping")
            return
        }

        continuation.yield(runEvent)

        if runEvent.type == .runCompleted || runEvent.type == .runFailed {
            continuation.finish()
        }
    }

    // MARK: - SSE Parsing

    /// A raw SSE message with optional `event` and `data` fields.
    private typealias SSEMessage = (event: String?, data: String?)

    /// Parses a single SSE event block (text between two `\n\n` separators).
    ///
    /// SSE format per line is `field: value`. This extracts the `event` and
    /// `data` fields. Other fields (`id`, `retry`, comments) are ignored.
    ///
    /// - Parameter block: The text of one SSE event (no trailing `\n\n`).
    /// - Returns: An `SSEMessage` tuple, or `nil` if the block is empty.
    private static func parseSSEEvent(_ block: String) -> SSEMessage? {
        var event: String?
        var data: String?

        let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            guard let colonIndex = line.firstIndex(of: ":") else {
                // Lines without a colon are comments (SSE spec says lines
                // starting with ':' are comments, but any line without a
                // colon is similarly ignored).
                continue
            }

            let field = line[line.startIndex ..< colonIndex]
                .trimmingCharacters(in: .whitespaces)

            let valueStart = line.index(after: colonIndex)
            let value = line[valueStart...]
                .trimmingCharacters(in: .whitespaces)

            switch field {
            case "event":
                event = value
            case "data":
                data = value
            default:
                break
            }
        }

        return (event, data)
    }

    // MARK: - Event Mapping

    /// Maps a parsed SSE message to a `RunEvent`.
    ///
    /// The `data:` field (if present) is decoded as JSON. A flexible decoding
    /// strategy handles both snake_case (`tool_name`) and camelCase (`toolName`)
    /// keys, with all fields optional to account for event-type variance.
    ///
    /// - Parameters:
    ///   - message: The parsed SSE fields.
    ///   - decoder: The `JSONDecoder` to use for decoding the data payload.
    /// - Returns: A `RunEvent`, or `nil` if the event type is unknown or data is
    ///   malformed.
    private static func mapToRunEvent(
        _ message: SSEMessage,
        decoder: JSONDecoder
    ) -> RunEvent? {
        // Event type: try SSE "event:" field first, then JSON "event" field
        let eventField: String
        if let sseEvent = message.event {
            eventField = sseEvent
        } else if let dataStr = message.data, let data = dataStr.data(using: .utf8),
                  let envelope = try? decoder.decode(RunEventPayload.self, from: data),
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
            guard let dataField = message.data, !dataField.isEmpty,
                  let data = dataField.data(using: .utf8)
            else {
                return nil
            }
            do {
                return try decoder.decode(RunEventPayload.self, from: data)
            } catch {
                Logger.sse.error("Failed to decode SSE data for event '\(eventField)': \(error.localizedDescription). Data: \(dataField.prefix(500))")
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
