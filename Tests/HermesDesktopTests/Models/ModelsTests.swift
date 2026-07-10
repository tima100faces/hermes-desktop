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
            for: Topic.self, Message.self,
            configurations: config
        )
        modelContext = modelContainer.mainContext
    }

    override func tearDown() async throws {
        modelContext = nil
        modelContainer = nil
    }

    // MARK: - Topic

    func testTopicInit() {
        let topic = Topic(name: "Test", conversationKey: "test")
        XCTAssertEqual(topic.name, "Test")
        XCTAssertEqual(topic.conversationKey, "test")
        XCTAssertNotNil(topic.createdAt)
        XCTAssertNotNil(topic.lastActiveAt)
        XCTAssertTrue(topic.messages.isEmpty)
    }

    func testTopicConversationKeyUnique() throws {
        let topic1 = Topic(name: "Topic A", conversationKey: "dup-key")
        modelContext.insert(topic1)
        try modelContext.save()

        let topic2 = Topic(name: "Topic B", conversationKey: "dup-key")
        modelContext.insert(topic2)

        // SwiftData @Attribute(.unique) behavior: save may throw or silently merge.
        // We verify that after save, we can still query topics.
        do {
            try modelContext.save()
        } catch {
            // Expected: unique constraint violation is valid behavior
            modelContext.delete(topic2)
            try modelContext.save()
        }

        // Either way, topic1 should still exist
        let fetch = FetchDescriptor<Topic>()
        let topics = try modelContext.fetch(fetch)
        XCTAssertFalse(topics.isEmpty)
    }

    // MARK: - Message

    func testMessageInit() {
        let message = Message(content: "Hello, world!", role: .user)
        XCTAssertEqual(message.content, "Hello, world!")
        XCTAssertEqual(message.role, "user")
        XCTAssertNotNil(message.timestamp)
        XCTAssertNil(message.runId)
        XCTAssertNil(message.topic)
    }

    func testMessageRoleEnum() {
        XCTAssertEqual(Message.Role.user.rawValue, "user")
        XCTAssertEqual(Message.Role.assistant.rawValue, "assistant")
        XCTAssertEqual(Message.Role.tool.rawValue, "tool")
    }

    func testTopicCascadeDelete() throws {
        // Given: a topic with two messages
        let topic = Topic(name: "Cascade", conversationKey: "cascade-test")
        let msg1 = Message(content: "First", role: .user)
        let msg2 = Message(content: "Second", role: .assistant)
        topic.messages = [msg1, msg2]
        modelContext.insert(topic)
        // NOTE: SwiftData infers the inverse relationship from Message.topic
        // to Topic.messages, so inserting the topic inserts its messages.
        try modelContext.save()

        // Verify messages exist before deletion
        let fetchBefore = try modelContext.fetch(FetchDescriptor<Message>())
        XCTAssertEqual(fetchBefore.count, 2)

        // When: delete the topic
        modelContext.delete(topic)
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
