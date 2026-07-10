import Foundation
import SwiftData

// MARK: - TopicConversationService

/// `ConversationService` backed by a `Topic` — the original Runs API path,
/// unchanged in behavior from before Этап 2.
@MainActor
public final class TopicConversationService: ConversationService {

    private let runsAPI: RunsAPIProtocol
    private let topic: Topic

    public private(set) var currentTurnId: String?

    public init(runsAPI: RunsAPIProtocol, topic: Topic) {
        self.runsAPI = runsAPI
        self.topic = topic
    }

    public func loadMessages(context: ModelContext) async -> [Message] {
        let key = topic.conversationKey
        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate { $0.topic?.conversationKey == key },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    public func persist(_ message: Message, context: ModelContext) {
        message.topic = topic
        topic.lastActiveAt = Date()
        context.insert(message)
        try? context.save()
    }

    public func send(input: String) async throws -> AsyncStream<RunEvent> {
        let response = try await runsAPI.createRun(input: input, conversation: topic.conversationKey)
        currentTurnId = response.runId
        return await runsAPI.streamEvents(runId: response.runId)
    }

    public func stop() async {
        guard let runId = currentTurnId else { return }
        try? await runsAPI.stopRun(runId: runId)
        currentTurnId = nil
    }

    public func autoTitleIfNeeded(from firstMessageText: String, context: ModelContext) async {
        // Topic titles are user-set only (Rename sheet) — no server auto-title.
    }
}
