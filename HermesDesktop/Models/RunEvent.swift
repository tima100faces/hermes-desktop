import Foundation

// MARK: - RunEventType

/// Types of SSE events emitted by the Hermes Runs API.
public enum RunEventType: String, Codable, Sendable {
    /// A text delta (token) in the streaming response. API: "message.delta"
    case textDelta = "message.delta"
    /// The agent called a tool. API: "tool.call"
    case toolCall = "tool.call"
    /// The tool returned a result. API: "tool.result"
    case toolResult = "tool.result"
    /// The run completed successfully. API: "run.completed"
    case runCompleted = "run.completed"
    /// The run failed with an error. API: "run.failed"
    case runFailed = "run.failed"
    /// Reasoning / thinking chunk. API: "reasoning.available"
    case reasoningAvailable = "reasoning.available"
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
