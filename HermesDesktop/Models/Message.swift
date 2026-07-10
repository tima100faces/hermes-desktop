import Foundation
import SwiftData

// MARK: - Message

/// A single message in a conversation.
///
/// Stores the Markdown body, role (user / assistant / tool), and an optional
/// reference to the Hermes run that produced it.
@Model
public final class Message {
    /// Message body in Markdown format.
    var content: String

    /// Role as a raw string: "user", "assistant", or "tool".
    var role: String

    /// When the message was created.
    var timestamp: Date

    /// The Hermes run ID that produced this message (nil for user messages).
    var runId: String?

    /// The topic this message belongs to.
    var topic: Topic?

    // MARK: - Role

    /// Semantic role of a message sender.
    enum Role: String, Codable, Sendable {
        case user
        case assistant
        case tool
    }

    init(content: String, role: Role, runId: String? = nil) {
        self.content = content
        self.role = role.rawValue
        self.timestamp = Date()
        self.runId = runId
    }
}
