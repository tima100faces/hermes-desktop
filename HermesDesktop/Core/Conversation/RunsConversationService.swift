import Foundation
import SwiftData

// MARK: - RunsConversationService

/// `ConversationService` backed by a `Chat`'s `conversationKey` — the
/// original Runs API path, unchanged in behavior from before chats and
/// topics were unified. Only ever constructed for a pinned, Runs-backed
/// `Chat` (`conversationKey != nil`).
@MainActor
public final class RunsConversationService: ConversationService {

    private let runsAPI: RunsAPIProtocol
    private let chat: Chat
    private let conversationKey: String

    public private(set) var currentTurnId: String?

    public init(runsAPI: RunsAPIProtocol, chat: Chat) {
        precondition(chat.conversationKey != nil, "RunsConversationService requires a Runs-backed Chat")
        self.runsAPI = runsAPI
        self.chat = chat
        self.conversationKey = chat.conversationKey!
    }

    public func loadMessages(context: ModelContext) async -> [Message] {
        let key = conversationKey
        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate { $0.chat?.conversationKey == key },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    public func persist(_ message: Message, context: ModelContext) {
        message.chat = chat
        chat.lastActiveAt = Date()
        context.insert(message)
        try? context.save()
    }

    public func send(input: String) async throws -> AsyncStream<RunEvent> {
        let response = try await runsAPI.createRun(input: input, conversation: conversationKey)
        currentTurnId = response.runId
        return await runsAPI.streamEvents(runId: response.runId)
    }

    public func stop() async {
        guard let runId = currentTurnId else { return }
        try? await runsAPI.stopRun(runId: runId)
        currentTurnId = nil
    }

    public func autoTitleIfNeeded(from firstMessageText: String, context: ModelContext) async {
        // Runs-backed chat titles are user-set only (Rename sheet) — no server auto-title.
    }
}
