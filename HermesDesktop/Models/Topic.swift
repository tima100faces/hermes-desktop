import Foundation
import SwiftData

// MARK: - Topic

/// A conversation topic in Hermes Desktop.
///
/// Maps to a Hermes "conversation" param in the Runs API.
/// Each topic owns its messages with cascade delete.
@Model
public final class Topic {
    /// Display name for the sidebar.
    var name: String

    /// Unique key used as the `conversation` parameter in Hermes Runs API.
    @Attribute(.unique) var conversationKey: String

    /// When the topic was first created.
    var createdAt: Date

    /// Last activity timestamp — updated whenever a message is sent or received.
    var lastActiveAt: Date

    /// Messages belonging to this topic. Cascading delete removes all messages
    /// when the topic is deleted.
    @Relationship(deleteRule: .cascade) var messages: [Message]

    init(name: String, conversationKey: String) {
        self.name = name
        self.conversationKey = conversationKey
        self.createdAt = Date()
        self.lastActiveAt = Date()
        self.messages = []
    }
}
