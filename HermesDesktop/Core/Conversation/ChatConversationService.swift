import Foundation
import SwiftData

// MARK: - ChatConversationService

/// `ConversationService` backed by a `Chat` — the new Sessions API path.
///
/// Message bodies aren't cached locally: the server is authoritative, and
/// `loadMessages` re-fetches on every open. Only the owning `Chat` row's
/// metadata (title, `lastActiveAt`) is persisted in SwiftData.
@MainActor
public final class ChatConversationService: ConversationService {

    private let sessionsAPI: SessionsAPIProtocol
    private let chat: Chat

    /// The Sessions API has no per-turn identifier — always `nil`.
    public let currentTurnId: String? = nil

    /// Force-terminates the in-flight `chat/stream` call — set by `send`,
    /// invoked by `stop` (no server-side stop endpoint to call instead).
    private var cancelCurrentStream: (@Sendable () -> Void)?

    public init(sessionsAPI: SessionsAPIProtocol, chat: Chat) {
        self.sessionsAPI = sessionsAPI
        self.chat = chat
    }

    public func loadMessages(context: ModelContext) async -> [Message] {
        guard let remote = try? await sessionsAPI.getMessages(sessionId: chat.sessionId) else {
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

    public func send(input: String) async throws -> AsyncStream<RunEvent> {
        let (stream, cancel) = try await sessionsAPI.streamChat(sessionId: chat.sessionId, input: input)
        cancelCurrentStream = cancel
        return stream
    }

    public func stop() async {
        // No documented stop endpoint for chat/stream — force-terminate the
        // stream locally instead.
        cancelCurrentStream?()
        cancelCurrentStream = nil
    }

    public func autoTitleIfNeeded(from firstMessageText: String, context: ModelContext) async {
        guard !chat.hasAutoTitled else { return }
        let title = String(firstMessageText.prefix(40))
        chat.hasAutoTitled = true
        do {
            _ = try await sessionsAPI.renameSession(id: chat.sessionId, title: title)
            chat.title = title
            try? context.save()
        } catch {
            // Cosmetic failure — allow a later message to retry.
            chat.hasAutoTitled = false
        }
    }
}
