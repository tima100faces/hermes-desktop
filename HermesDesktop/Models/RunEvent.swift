import Foundation

// MARK: - RunEventType

/// Types of SSE events emitted by the Hermes Runs API.
public enum RunEventType: String, Codable, Sendable {
    /// A text delta (token) in the streaming response.
    case textDelta = "text_delta"
    /// The agent called a tool.
    case toolCall = "tool_call"
    /// The tool returned a result.
    case toolResult = "tool_result"
    /// The run completed successfully.
    case runCompleted = "run_completed"
    /// The run failed with an error.
    case runFailed = "run_failed"
}

// MARK: - RunEvent

/// A single SSE event from a Hermes run stream.
///
/// Not stored in SwiftData — used ephemerally during streaming.
public struct RunEvent: Identifiable, Equatable, Sendable {
    public var id: UUID
    let type: RunEventType
    let content: String?
    let toolName: String?
    let toolInput: String?
    let toolOutput: String?
    let error: String?

    public init(
        id: UUID = UUID(),
        type: RunEventType,
        content: String? = nil,
        toolName: String? = nil,
        toolInput: String? = nil,
        toolOutput: String? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.type = type
        self.content = content
        self.toolName = toolName
        self.toolInput = toolInput
        self.toolOutput = toolOutput
        self.error = error
    }
}
