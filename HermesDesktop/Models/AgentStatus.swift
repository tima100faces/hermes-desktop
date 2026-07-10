import Foundation

// MARK: - AgentState

/// The lifecycle state of a subagent or run.
enum AgentState: String, Codable, Sendable {
    /// The agent is actively processing.
    case running
    /// The agent finished successfully.
    case completed
    /// The agent encountered an error.
    case failed
    /// The agent was stopped by the user.
    case stopped
}

// MARK: - AgentStatus

/// Current status of a subagent displayed inline in the chat.
///
/// Not stored in SwiftData — used ephemerally to drive status badges
/// and progress indicators.
struct AgentStatus: Identifiable, Equatable, Sendable {
    /// The Hermes run ID for this agent.
    let id: String

    /// Human-readable display name (e.g. "Code Review Agent").
    let name: String

    /// Current lifecycle state.
    let state: AgentState

    /// What the agent is doing right now (e.g. "Reviewing file...", "Running tests...").
    let progress: String?
}
