import Foundation
import SwiftData

// MARK: - Chat

/// A conversation in Hermes Desktop — the single conversation entity.
///
/// Backed by one of two transports, distinguished by which identifier is
/// set (never both, never neither):
/// - `sessionId` — the Hermes Sessions API (`POST /api/sessions`).
/// - `conversationKey` — the older Runs API `conversation` param. Only
///   ever present on chats migrated from the pre-unification `Topic`
///   entity; new chats are always Sessions-backed.
///
/// `ConversationService` (`Core/Conversation/`) hides this distinction from
/// the rest of the app — `RunsConversationService` / `SessionsConversationService`
/// pick the transport based on which identifier is set.
@Model
public final class Chat {
    /// Server-side Hermes session id (`POST /api/sessions` response).
    /// `nil` for chats migrated from the old Runs API `Topic` entity.
    @Attribute(.unique) var sessionId: String?

    /// The `conversation` parameter for the Runs API. Only set on chats
    /// migrated from the old `Topic` entity — never assigned to new chats.
    @Attribute(.unique) var conversationKey: String?

    /// Display title for the sidebar.
    var title: String

    /// When the chat was first created.
    var createdAt: Date

    /// Last activity timestamp — updated whenever a message is sent or received.
    var lastActiveAt: Date

    /// Whether the server-side title has been set yet (first-message
    /// auto-title). Always `true` for Runs-backed chats — their titles are
    /// user-set only, never auto-titled.
    var hasAutoTitled: Bool

    /// Shown in the sidebar's "Pinned" section, above the regular
    /// chat list. Every migrated `Topic` becomes pinned; new chats start
    /// unpinned.
    var isPinned: Bool

    /// The project this chat belongs to, if any. `nil` for the vast
    /// majority of chats (outside any project) and always `nil` for
    /// Runs-backed chats — projects are Sessions-only. Chats are only ever
    /// created inside a project; existing chats are never moved in.
    var project: Project?

    /// Messages belonging to this chat. Cascading delete removes all messages
    /// when the chat is deleted. For Sessions-backed chats this is left
    /// empty in practice — chat history is re-fetched from the server on
    /// open rather than cached locally.
    @Relationship(deleteRule: .cascade) var messages: [Message]

    /// Creates a Sessions API-backed chat.
    init(sessionId: String, title: String) {
        self.sessionId = sessionId
        self.conversationKey = nil
        self.title = title
        self.createdAt = Date()
        self.lastActiveAt = Date()
        self.hasAutoTitled = false
        self.isPinned = false
        self.project = nil
        self.messages = []
    }

    /// Creates a Runs API-backed chat — used only by the migration that
    /// folds old `Topic` records into this unified model.
    init(conversationKey: String, title: String, isPinned: Bool) {
        self.sessionId = nil
        self.conversationKey = conversationKey
        self.title = title
        self.createdAt = Date()
        self.lastActiveAt = Date()
        self.hasAutoTitled = true
        self.isPinned = isPinned
        self.project = nil
        self.messages = []
    }
}
