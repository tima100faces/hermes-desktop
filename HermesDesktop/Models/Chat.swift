import Foundation
import SwiftData

// MARK: - Chat

/// A free-form chat in Hermes Desktop — a one-off conversation backed by
/// the Hermes Sessions API, as opposed to a `Topic` (a long-running
/// conversation on the older Runs API).
///
/// The list of chats shown in the sidebar is driven entirely by these
/// local records, never by enumerating `GET /api/sessions` — that
/// endpoint also returns Telegram sessions and, for `source=api_server`,
/// sessions created by `Topic`'s Runs API path, which have no reliable
/// way to be told apart from chats server-side.
@Model
public final class Chat {
    /// Server-side Hermes session id (`POST /api/sessions` response).
    @Attribute(.unique) var sessionId: String

    /// Local display title — mirrors the server's `title` once set.
    var title: String

    /// When the chat was first created.
    var createdAt: Date

    /// Last activity timestamp — updated whenever a message is sent or received.
    var lastActiveAt: Date

    /// Whether the server-side title has been set yet (first-message
    /// auto-title, see `docs/task-topics-and-chats.md` §Этап 2).
    var hasAutoTitled: Bool

    /// Messages belonging to this chat. Cascading delete removes all messages
    /// when the chat is deleted. Left empty in practice — chat history is
    /// re-fetched from the server on open rather than cached locally.
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
