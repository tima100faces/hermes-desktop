import Foundation
import SwiftData

// MARK: - ConversationService
//
// Unifies `Topic` (Runs API) and `Chat` (Sessions API) behind one
// interface so `ChatViewModel` / `ChatView` never need to know which
// transport backs the conversation on screen
// (docs/task-topics-and-chats.md §Этап 2). Event-dialect translation for
// each transport happens in exactly one place: `SSEClient` (Runs) and
// `SessionSSEClient` (Sessions) both yield the same `RunEvent` shape.

/// A single active conversation — either a `Topic` or a `Chat` — exposed
/// through one shape so the chat UI is transport-agnostic.
@MainActor
public protocol ConversationService: AnyObject {

    /// Identifier of the in-flight turn, if the transport has one (the
    /// Runs API's run id). `nil` for Sessions-backed chats, which have no
    /// per-turn identifier — `Message.runId` stays `nil` for those.
    var currentTurnId: String? { get }

    /// Loads existing messages for this conversation.
    ///
    /// Topics read from local SwiftData — the Runs API has no history
    /// endpoint, so local storage has always been the source of truth.
    /// Chats fetch fresh from the server (`GET /api/sessions/{id}/messages`)
    /// since the server is authoritative there; the local cache is
    /// secondary.
    func loadMessages(context: ModelContext) async -> [Message]

    /// Persists a new message against this conversation's owner and bumps
    /// its `lastActiveAt`.
    func persist(_ message: Message, context: ModelContext)

    /// Sends `input` and returns the unified event stream for the turn.
    func send(input: String) async throws -> AsyncStream<RunEvent>

    /// Best-effort cancellation of the in-flight turn. `ChatViewModel`
    /// additionally cancels its own consuming `Task`, since the Sessions
    /// API has no documented stop endpoint — that local cancellation is
    /// what actually stops a chat's stream from being read further.
    func stop() async

    /// Called once, right after the very first user message of a brand
    /// new conversation is persisted, so implementations that support
    /// server-side titles can auto-title from it. Topics ignore this —
    /// their titles are user-set only.
    func autoTitleIfNeeded(from firstMessageText: String, context: ModelContext) async
}
