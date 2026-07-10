import Foundation
import SwiftData

// MARK: - PreUnificationSchema

/// Mirrors the on-disk schema from just before `Topic` and `Chat` were
/// merged into one `Chat` entity (SwiftData entities named "Topic" and
/// "Chat", each with their own `Message` relationship), so
/// `ChatMigrationService` can read old data under its original shape
/// before the live unified `Chat`/`Message` models ever touch the default
/// store.
///
/// Nested under this enum so the type names don't collide with the live
/// `Chat` and `Message` models — SwiftData derives the persisted entity
/// name from the bare type name, not the enum-qualified path, so this
/// still matches what's already on disk.
enum PreUnificationSchema {

    @Model
    final class Topic {
        var name: String
        @Attribute(.unique) var conversationKey: String
        var createdAt: Date
        var lastActiveAt: Date
        @Relationship(deleteRule: .cascade) var messages: [Message]

        init(name: String, conversationKey: String) {
            self.name = name
            self.conversationKey = conversationKey
            self.createdAt = Date()
            self.lastActiveAt = Date()
            self.messages = []
        }
    }

    @Model
    final class Chat {
        @Attribute(.unique) var sessionId: String
        var title: String
        var createdAt: Date
        var lastActiveAt: Date
        var hasAutoTitled: Bool
        @Relationship(deleteRule: .cascade) var messages: [Message]

        init(sessionId: String, title: String) {
            self.sessionId = sessionId
            self.title = title
            self.createdAt = Date()
            self.lastActiveAt = Date()
            self.hasAutoTitled = false
            self.messages = []
        }
    }

    @Model
    final class Message {
        var content: String
        var role: String
        var timestamp: Date
        var runId: String?
        var topic: Topic?
        var chat: Chat?

        init(content: String, role: String, runId: String? = nil) {
            self.content = content
            self.role = role
            self.timestamp = Date()
            self.runId = runId
        }
    }
}
