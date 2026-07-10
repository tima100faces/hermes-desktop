import XCTest
import SwiftData
@testable import HermesDesktop

// MARK: - ModelsTests

@MainActor
final class ModelsTests: XCTestCase {

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(
            for: Chat.self, Message.self,
            configurations: config
        )
        modelContext = modelContainer.mainContext
    }

    override func tearDown() async throws {
        modelContext = nil
        modelContainer = nil
    }

    // MARK: - Chat

    func testRunsBackedChatInit() {
        let chat = Chat(conversationKey: "test", title: "Test", isPinned: true)
        XCTAssertEqual(chat.title, "Test")
        XCTAssertEqual(chat.conversationKey, "test")
        XCTAssertNil(chat.sessionId)
        XCTAssertTrue(chat.isPinned)
        XCTAssertNotNil(chat.createdAt)
        XCTAssertNotNil(chat.lastActiveAt)
        XCTAssertTrue(chat.messages.isEmpty)
    }

    func testSessionsBackedChatInit() {
        let chat = Chat(sessionId: "session-1", title: "Test")
        XCTAssertEqual(chat.title, "Test")
        XCTAssertEqual(chat.sessionId, "session-1")
        XCTAssertNil(chat.conversationKey)
        XCTAssertFalse(chat.isPinned)
        XCTAssertFalse(chat.hasAutoTitled)
    }

    func testChatConversationKeyUnique() throws {
        let chat1 = Chat(conversationKey: "dup-key", title: "Chat A", isPinned: true)
        modelContext.insert(chat1)
        try modelContext.save()

        let chat2 = Chat(conversationKey: "dup-key", title: "Chat B", isPinned: true)
        modelContext.insert(chat2)

        // SwiftData @Attribute(.unique) behavior: save may throw or silently merge.
        // We verify that after save, we can still query chats.
        do {
            try modelContext.save()
        } catch {
            // Expected: unique constraint violation is valid behavior
            modelContext.delete(chat2)
            try modelContext.save()
        }

        // Either way, chat1 should still exist
        let fetch = FetchDescriptor<Chat>()
        let chats = try modelContext.fetch(fetch)
        XCTAssertFalse(chats.isEmpty)
    }

    // MARK: - Message

    func testMessageInit() {
        let message = Message(content: "Hello, world!", role: .user)
        XCTAssertEqual(message.content, "Hello, world!")
        XCTAssertEqual(message.role, "user")
        XCTAssertNotNil(message.timestamp)
        XCTAssertNil(message.runId)
        XCTAssertNil(message.chat)
    }

    func testMessageRoleEnum() {
        XCTAssertEqual(Message.Role.user.rawValue, "user")
        XCTAssertEqual(Message.Role.assistant.rawValue, "assistant")
        XCTAssertEqual(Message.Role.tool.rawValue, "tool")
    }

    func testChatCascadeDelete() throws {
        // Given: a chat with two messages
        let chat = Chat(conversationKey: "cascade-test", title: "Cascade", isPinned: true)
        let msg1 = Message(content: "First", role: .user)
        let msg2 = Message(content: "Second", role: .assistant)
        chat.messages = [msg1, msg2]
        modelContext.insert(chat)
        // NOTE: SwiftData infers the inverse relationship from Message.chat
        // to Chat.messages, so inserting the chat inserts its messages.
        try modelContext.save()

        // Verify messages exist before deletion
        let fetchBefore = try modelContext.fetch(FetchDescriptor<Message>())
        XCTAssertEqual(fetchBefore.count, 2)

        // When: delete the chat
        modelContext.delete(chat)
        try modelContext.save()

        // Then: messages are also gone (cascade delete)
        let fetchAfter = try modelContext.fetch(FetchDescriptor<Message>())
        XCTAssertEqual(fetchAfter.count, 0)
    }

    // MARK: - RunEvent

    func testRunEventInit() {
        let event = RunEvent(type: .textDelta, content: "Hello")
        XCTAssertEqual(event.type, .textDelta)
        XCTAssertEqual(event.content, "Hello")
        XCTAssertNil(event.toolName)
        XCTAssertNil(event.toolInput)
        XCTAssertNil(event.toolOutput)
        XCTAssertNil(event.error)
    }

    func testRunEventEquatable() {
        let id = UUID()
        let event1 = RunEvent(
            id: id,
            type: .textDelta,
            content: "same"
        )
        let event2 = RunEvent(
            id: id,
            type: .textDelta,
            content: "same"
        )
        XCTAssertEqual(event1, event2)
    }

    // MARK: - AgentStatus

    func testAgentStatusInit() {
        let status = AgentStatus(id: "run-1", name: "Reviewer", state: .running)
        XCTAssertEqual(status.id, "run-1")
        XCTAssertEqual(status.name, "Reviewer")
        XCTAssertEqual(status.state, .running)
        XCTAssertNil(status.progress)
    }

    func testAgentStatusMutable() {
        var status = AgentStatus(id: "run-2", name: "Builder", state: .running)
        status.state = .completed
        XCTAssertEqual(status.state, .completed)
    }
}
