import Foundation
import OSLog

// MARK: - Logger

private extension Logger {
    /// Logger for Sessions API chat-stream events and errors.
    static let sessionSSE = Logger(subsystem: "com.hermes-desktop", category: "session-sse")
}

// MARK: - SessionSSEClient
//
// Streams `POST /api/sessions/{id}/chat/stream` and translates the
// Sessions API's SSE dialect (`assistant.delta`, `tool.started`,
// `tool.completed`, `run.completed`) into the same `RunEvent`/
// `RunEventType` shape the Runs API dialect uses in `SSEClient`, so
// `ChatViewModel` never needs to know which transport produced an event
// (docs/task-topics-and-chats.md §Этап 2).
//
// The low-level byte-stream framing here is intentionally a separate,
// small duplicate of `SSEClient`'s (rather than a shared refactor) to
// avoid any risk of regressing the already-working Runs API streaming
// path used by existing Topics.
//
// NOTE: the exact JSON field names the Sessions dialect uses for tool
// events are inferred (reusing the Runs dialect's field names), not
// verified against a live `chat/stream` call — see the Stage 2 report.
public actor SessionSSEClient {

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

    /// Creates a `SessionSSEClient` with a custom `URLSession` (for testing).
    public init(session: URLSession) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    // MARK: - Connect

    /// Opens the chat-stream SSE connection and returns an `AsyncStream` of
    /// unified `RunEvent` values.
    ///
    /// - Parameters:
    ///   - url: The full `.../chat/stream` endpoint URL.
    ///   - token: A Bearer token for authentication.
    ///   - input: The user's message text — sent as the JSON body.
    /// - Returns: An unbounded `AsyncStream<RunEvent>` that must be consumed,
    ///   plus a `cancel` closure that force-terminates it. There's no
    ///   documented Sessions API stop endpoint, so `ChatConversationService`
    ///   calls `cancel` directly instead of relying on `continuation.onTermination`,
    ///   which only fires once the *consumer* stops iterating.
    public func connect(url: URL, token: String, input: String) -> (stream: AsyncStream<RunEvent>, cancel: @Sendable () -> Void) {
        let control = StreamControl()
        let stream = AsyncStream<RunEvent>(bufferingPolicy: .unbounded) { continuation in
            control.continuation = continuation
            let task = Task {
                await Self.runStream(
                    url: url,
                    token: token,
                    input: input,
                    session: session,
                    decoder: decoder,
                    continuation: continuation
                )
            }
            control.task = task

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
        return (stream, { control.cancel() })
    }

    // MARK: - Stream Runner (non-isolated)

    private static func runStream(
        url: URL,
        token: String,
        input: String,
        session: URLSession,
        decoder: JSONDecoder,
        continuation: AsyncStream<RunEvent>.Continuation
    ) async {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["message": input])

        do {
            let (bytes, response) = try await session.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.sessionSSE.error("Non-HTTP response received from chat/stream endpoint")
                continuation.finish()
                return
            }

            guard (200 ... 299).contains(httpResponse.statusCode) else {
                Logger.sessionSSE.error("chat/stream endpoint returned HTTP \(httpResponse.statusCode)")
                continuation.finish()
                return
            }

            var currentEventLines: [String] = []

            for try await line in bytes.lines {
                guard !Task.isCancelled else { break }

                if line.isEmpty {
                    guard !currentEventLines.isEmpty else { continue }

                    let eventBlock = currentEventLines.joined(separator: "\n")
                    currentEventLines.removeAll(keepingCapacity: true)

                    processEventBlock(eventBlock, decoder: decoder, continuation: continuation)

                    if Task.isCancelled {
                        break
                    }
                } else {
                    currentEventLines.append(line)
                }
            }

            if !currentEventLines.isEmpty {
                let eventBlock = currentEventLines.joined(separator: "\n")
                processEventBlock(eventBlock, decoder: decoder, continuation: continuation)
            }

        } catch is CancellationError {
            Logger.sessionSSE.debug("chat/stream cancelled")
        } catch {
            Logger.sessionSSE.error("chat/stream error: \(error.localizedDescription)")
        }

        continuation.finish()
    }

    // MARK: - Process Event Block

    private static func processEventBlock(
        _ block: String,
        decoder: JSONDecoder,
        continuation: AsyncStream<RunEvent>.Continuation
    ) {
        guard !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        guard let parsed = parseSSEEvent(block) else {
            Logger.sessionSSE.warning("Failed to parse chat/stream event block: \(block.prefix(200))")
            return
        }

        guard let runEvent = mapToRunEvent(parsed, decoder: decoder) else {
            Logger.sessionSSE.warning("Failed to map chat/stream event to RunEvent, skipping")
            return
        }

        continuation.yield(runEvent)

        if runEvent.type == .runCompleted || runEvent.type == .runFailed {
            continuation.finish()
        }
    }

    // MARK: - SSE Parsing

    private typealias SSEMessage = (event: String?, data: String?)

    private static func parseSSEEvent(_ block: String) -> SSEMessage? {
        var event: String?
        var data: String?

        let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }

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

    // MARK: - Event Mapping (Sessions dialect)

    /// Maps a Sessions API SSE event name to the shared `RunEventType`.
    ///
    /// `docs/task-topics-and-chats.md` names four events for one agent
    /// turn: `assistant.delta`, `tool.started`, `tool.completed`,
    /// `run.completed`. A `run.failed` case is included defensively,
    /// mirroring the Runs dialect, but is unverified against the live
    /// server.
    private static func sessionEventType(for raw: String) -> RunEventType? {
        switch raw {
        case "assistant.delta": return .textDelta
        case "tool.started": return .toolCall
        case "tool.completed": return .toolResult
        case "run.completed": return .runCompleted
        case "run.failed": return .runFailed
        default: return nil
        }
    }

    private static func mapToRunEvent(
        _ message: SSEMessage,
        decoder: JSONDecoder
    ) -> RunEvent? {
        let eventField: String
        if let sseEvent = message.event {
            eventField = sseEvent
        } else if let dataStr = message.data, let data = dataStr.data(using: .utf8),
                  let envelope = try? decoder.decode(SessionEventPayload.self, from: data),
                  let jsonEvent = envelope.event {
            eventField = jsonEvent
        } else {
            Logger.sessionSSE.warning("chat/stream event missing 'event' field (both SSE header and JSON)")
            return nil
        }

        guard let eventType = sessionEventType(for: eventField) else {
            Logger.sessionSSE.warning("Ignoring unknown chat/stream event type: \(eventField)")
            return nil
        }

        let payload: SessionEventPayload? = {
            guard let dataField = message.data, !dataField.isEmpty,
                  let data = dataField.data(using: .utf8)
            else {
                return nil
            }
            do {
                return try decoder.decode(SessionEventPayload.self, from: data)
            } catch {
                Logger.sessionSSE.error("Failed to decode chat/stream data for event '\(eventField)': \(error.localizedDescription). Data: \(dataField.prefix(500))")
                return nil
            }
        }()

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

// MARK: - StreamControl

/// Holds the in-flight `Task` and `Continuation` for one `connect(...)` call
/// so `cancel()` can force-terminate the stream from outside — there's no
/// Sessions API stop endpoint to fall back on. Access is externally
/// serialized (set once at stream creation, read only from `cancel()`
/// afterwards), so the `@unchecked Sendable` is safe in practice.
private final class StreamControl: @unchecked Sendable {
    var continuation: AsyncStream<RunEvent>.Continuation?
    var task: Task<Void, Never>?

    func cancel() {
        task?.cancel()
        continuation?.finish()
    }
}

// MARK: - SessionEventPayload

/// Flexible decoding structure for Sessions API chat-stream `data:` JSON
/// payloads. Field names mirror the Runs API dialect's payload shape
/// (`RunEventPayload` in `SSEClient.swift`) — a reasonable inference given
/// both APIs likely share the same underlying agent/tool execution code,
/// but not verified against a live `chat/stream` response.
private struct SessionEventPayload: Decodable, Sendable {
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
