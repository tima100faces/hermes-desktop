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
// `ChatViewModel` never needs to know which transport produced an event.
//
// The low-level byte-stream framing (bytes → lines → SSE frames) is
// shared with `SSEClient` via `SSEFrameParser` — this type only owns the
// Sessions-specific event names and JSON field mapping.
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
    ///   - instructions: Project instructions, sent as the `instructions`
    ///     body field when non-`nil` (verified live against a fresh session,
    ///     2026-07-11: sets `has_system_prompt` and the agent follows it).
    ///     Omitted from the body entirely when `nil` — chats outside a
    ///     project are unaffected.
    ///   - sessionKey: A project's `X-Hermes-Session-Key`, sent as a header
    ///     when non-`nil` (server accepts and echoes it back, verified live
    ///     2026-07-11). Omitted when `nil`.
    /// - Returns: An unbounded `AsyncStream<RunEvent>` that must be consumed,
    ///   plus a `cancel` closure that force-terminates it. There's no
    ///   documented Sessions API stop endpoint, so `ChatConversationService`
    ///   calls `cancel` directly instead of relying on `continuation.onTermination`,
    ///   which only fires once the *consumer* stops iterating.
    public func connect(url: URL, token: String, input: String, instructions: String? = nil, sessionKey: String? = nil) -> (stream: AsyncStream<RunEvent>, cancel: @Sendable () -> Void) {
        let control = StreamControl()
        let stream = AsyncStream<RunEvent>(bufferingPolicy: .unbounded) { continuation in
            control.continuation = continuation
            let task = Task {
                await Self.runStream(
                    url: url,
                    token: token,
                    input: input,
                    instructions: instructions,
                    sessionKey: sessionKey,
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
        instructions: String?,
        sessionKey: String?,
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
        if let sessionKey {
            request.setValue(sessionKey, forHTTPHeaderField: "X-Hermes-Session-Key")
        }

        var body: [String: String] = ["message": input]
        if let instructions {
            body["instructions"] = instructions
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

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

            try await SSEFrameParser.run(bytes: bytes) { frame in
                processFrame(frame, decoder: decoder, continuation: continuation)
            }

        } catch is CancellationError {
            Logger.sessionSSE.debug("chat/stream cancelled")
        } catch {
            Logger.sessionSSE.error("chat/stream error: \(error.localizedDescription)")
        }

        continuation.finish()
    }

    // MARK: - Process Frame

    /// Maps one `SSEFrame` to a `RunEvent` and yields it.
    ///
    /// - Returns: `true` if this was a terminal event (`run.completed` /
    ///   `run.failed`) — the caller should stop reading further bytes.
    private static func processFrame(
        _ frame: SSEFrame,
        decoder: JSONDecoder,
        continuation: AsyncStream<RunEvent>.Continuation
    ) -> Bool {
        guard let runEvent = mapToRunEvent(frame, decoder: decoder) else {
            Logger.sessionSSE.warning("Failed to map chat/stream event to RunEvent, skipping")
            return false
        }

        continuation.yield(runEvent)

        guard runEvent.type == .runCompleted || runEvent.type == .runFailed else {
            return false
        }
        continuation.finish()
        return true
    }

    // MARK: - Event Mapping (Sessions dialect)

    /// Maps a Sessions API SSE event name to the shared `RunEventType`.
    ///
    /// Verified against a live `chat/stream` call (2026-07-11): the server
    /// also sends `run.started`, `message.started`, `tool.progress`
    /// (reasoning/"_thinking" updates), `assistant.completed`, and a final
    /// `done` after `run.completed` — all intentionally unmapped (`nil`)
    /// since `run.completed` alone is enough to end a turn, matching how
    /// the Runs dialect already ignores its `reasoning.available` event.
    /// A `run.failed` case is included defensively, mirroring the Runs
    /// dialect, but wasn't produced by any verified call.
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
        _ frame: SSEFrame,
        decoder: JSONDecoder
    ) -> RunEvent? {
        let eventField: String
        if let sseEvent = frame.event {
            eventField = sseEvent
        } else if let dataStr = frame.data, let data = dataStr.data(using: .utf8),
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
            guard let dataField = frame.data, !dataField.isEmpty,
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
            // `tool.started` carries a human-readable one-liner in `preview`
            // (e.g. "echo hello-from-test") — there's no plain-string
            // "tool_input" field; the raw arguments come as a nested `args`
            // object, not worth decoding just for a status-line display.
            toolInput: payload?.preview,
            // `tool.completed` doesn't carry the result — the actual output
            // only appears later, nested in `run.completed`'s `messages`
            // array. Left `nil` here; the status still flips to `.completed`
            // (see `RunEventType.toolResult`), just without a progress line.
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
/// payloads. Verified against a live `chat/stream` call (2026-07-11):
/// `assistant.delta` carries `delta`, `assistant.completed`/`run.completed`
/// carry `content`, `tool.started` carries `tool_name` + a human-readable
/// `preview` (the actual arguments come as a nested `args` object, not
/// decoded here), and `tool.completed` carries only `tool_name` (`preview`/
/// `args` are `null` — the result itself only shows up later, nested in
/// `run.completed`'s `messages` array).
private struct SessionEventPayload: Decodable, Sendable {
    let event: String?
    let content: String?
    let delta: String?
    let output: String?
    let text: String?
    let toolName: String?
    let preview: String?
    let toolOutput: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case event
        case content
        case delta
        case output
        case text
        case toolName = "tool_name"
        case preview
        case toolOutput = "tool_output"
        case error
    }
}
