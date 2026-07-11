import Foundation
import SwiftData

// MARK: - SessionsConversationService

/// `ConversationService` backed by a `Chat`'s `sessionId` — the Sessions
/// API path. Only ever constructed for a Sessions-backed `Chat`
/// (`sessionId != nil`).
///
/// Message bodies aren't cached locally: the server is authoritative, and
/// `loadMessages` re-fetches on every open. Only the owning `Chat` row's
/// metadata (title, `lastActiveAt`) is persisted in SwiftData.
@MainActor
public final class SessionsConversationService: ConversationService {

    private let sessionsAPI: SessionsAPIProtocol
    private let chat: Chat
    private let sessionId: String

    /// The Sessions API has no per-turn identifier — always `nil`.
    public let currentTurnId: String? = nil

    /// Force-terminates the in-flight `chat/stream` call — set by `send`,
    /// invoked by `stop` (no server-side stop endpoint to call instead).
    private var cancelCurrentStream: (@Sendable () -> Void)?

    public init(sessionsAPI: SessionsAPIProtocol, chat: Chat) {
        precondition(chat.sessionId != nil, "SessionsConversationService requires a Sessions-backed Chat")
        self.sessionsAPI = sessionsAPI
        self.chat = chat
        self.sessionId = chat.sessionId!
    }

    public func loadMessages(context: ModelContext) async -> [Message] {
        guard let remote = try? await sessionsAPI.getMessages(sessionId: sessionId) else {
            return []
        }
        return remote.compactMap { row in
            guard let role = Message.Role(rawValue: row.role) else { return nil }
            let message = Message(content: row.content, role: role)
            message.timestamp = Date(timeIntervalSince1970: row.timestamp)
            return message
        }
    }

    public func persist(_ message: Message, context: ModelContext) {
        chat.lastActiveAt = Date()
        try? context.save()
    }

    /// Instructions and session key are read from `chat.project` fresh on
    /// every call (not captured at `init`), so editing a project's
    /// instructions mid-conversation takes effect on the very next message —
    /// the expected behavior confirmed with the product owner.
    public func send(input: String) async throws -> AsyncStream<RunEvent> {
        let trimmedInstructions = chat.project?.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructions = (trimmedInstructions?.isEmpty ?? true) ? nil : trimmedInstructions

        let (stream, cancel) = try await sessionsAPI.streamChat(
            sessionId: sessionId,
            input: input,
            instructions: instructions,
            sessionKey: chat.project?.sessionKey
        )
        cancelCurrentStream = cancel
        return stream
    }

    public func stop() async {
        // No documented stop endpoint for chat/stream — force-terminate the
        // stream locally instead.
        cancelCurrentStream?()
        cancelCurrentStream = nil
    }

    /// Client-side auto-title: verified live against `GET /api/sessions/{id}`
    /// after `run.completed` (2026-07-12, see docs/HANDOFF.md) — the server
    /// never generates a `title` itself, it stays `null`. So the chat's
    /// first message becomes the title instead, word-boundary-truncated.
    ///
    /// Only ever touches a chat still titled `Chat.defaultTitle` — checked
    /// here, not just via `hasAutoTitled`, because a manual rename
    /// (`ChatSidebarViewModel.confirmRename`, which also sets
    /// `hasAutoTitled`) could in principle land between this method being
    /// entered and the server round-trip finishing; re-checking the title
    /// itself right before writing it is what actually guarantees a manual
    /// rename always wins.
    public func autoTitleIfNeeded(from firstMessageText: String, context: ModelContext) async {
        guard !chat.hasAutoTitled, chat.title == Chat.defaultTitle else { return }
        guard let title = Self.autoTitle(from: firstMessageText) else { return }

        chat.hasAutoTitled = true
        do {
            _ = try await sessionsAPI.renameSession(id: sessionId, title: title)
            chat.title = title
            try? context.save()
        } catch {
            // Cosmetic failure — allow a later message to retry.
            chat.hasAutoTitled = false
        }
    }

    /// Single-line, word-boundary-truncated title from a chat's first
    /// message: whitespace and newlines collapse to single spaces, then
    /// the result is capped at 40 characters — cut at the last space
    /// within that window (not mid-word) with a trailing "…", or hard-cut
    /// if there's no space to break on. `nil` if there's nothing to title
    /// with (message was pure whitespace).
    static func autoTitle(from text: String) -> String? {
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > 40 else { return collapsed }

        let limit = collapsed.index(collapsed.startIndex, offsetBy: 40)
        let prefix = collapsed[collapsed.startIndex..<limit]
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[prefix.startIndex..<lastSpace]) + "…"
        }
        return String(prefix) + "…"
    }
}
