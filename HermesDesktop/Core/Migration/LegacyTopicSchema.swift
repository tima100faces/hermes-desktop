import Foundation
import SwiftData

// MARK: - LegacyTopicSchema

/// Mirrors the pre-rename on-disk schema (SwiftData entities named
/// "Project" / "Message") so `TopicMigrationService` can read old data
/// under its original shape before the live `Topic`/`Message` models
/// ever touch the default store.
///
/// Nested under this enum so the type names don't collide with the live
/// `Topic` and `Message` models — SwiftData derives the persisted entity
/// name from the bare type name ("Project"), not the enum-qualified path,
/// so this still matches what's already on disk.
enum LegacyTopicSchema {

    @Model
    final class Project {
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
    final class Message {
        var content: String
        var role: String
        var timestamp: Date
        var runId: String?
        var project: Project?

        init(content: String, role: String, runId: String? = nil) {
            self.content = content
            self.role = role
            self.timestamp = Date()
            self.runId = runId
        }
    }
}
