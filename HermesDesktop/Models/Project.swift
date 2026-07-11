import Foundation
import SwiftData

// MARK: - Project

/// A named group of Sessions-backed chats that share instructions and a
/// long-lived `X-Hermes-Session-Key`.
///
/// Chats are created only inside a project (existing chats are never moved
/// in) — deleting a project cascades to delete its chats locally; the
/// caller is responsible for deleting their server-side sessions first
/// (see `ProjectSidebarViewModel`).
@Model
public final class Project {
    /// Display name, editable on the project's page.
    var name: String

    /// System-message text sent with every message in every chat of this
    /// project. May be empty — an empty project sends no `instructions`
    /// field at all (see `SessionsConversationService`).
    var instructions: String

    /// Long-lived key sent as `X-Hermes-Session-Key` on every chat request
    /// in this project. Generated once at creation, never changes.
    @Attribute(.unique) var sessionKey: String

    /// When the project was created.
    var createdAt: Date

    /// This project's chats. Cascading delete removes them locally when the
    /// project is deleted — their server-side sessions must be deleted
    /// separately first (no server-side cascade for `X-Hermes-Session-Key`).
    @Relationship(deleteRule: .cascade) var chats: [Chat]

    init(name: String) {
        self.name = name
        self.instructions = ""
        self.sessionKey = "hermes-desktop:project:\(UUID().uuidString)"
        self.createdAt = Date()
        self.chats = []
    }
}
