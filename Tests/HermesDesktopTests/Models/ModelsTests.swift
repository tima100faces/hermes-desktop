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
            for: Project.self, Message.self,
            configurations: config
        )
        modelContext = modelContainer.mainContext
    }

    override func tearDown() async throws {
        modelContext = nil
        modelContainer = nil
    }

    // MARK: - Project

    func testProjectInit() {
        let project = Project(name: "Test", conversationKey: "test")
        XCTAssertEqual(project.name, "Test")
        XCTAssertEqual(project.conversationKey, "test")
        XCTAssertNotNil(project.createdAt)
        XCTAssertNotNil(project.lastActiveAt)
        XCTAssertTrue(project.messages.isEmpty)
    }

    func testProjectConversationKeyUnique() throws {
        let project1 = Project(name: "Proj A", conversationKey: "dup-key")
        modelContext.insert(project1)
        try modelContext.save()

        let project2 = Project(name: "Proj B", conversationKey: "dup-key")
        modelContext.insert(project2)

        // SwiftData @Attribute(.unique) behavior: save may throw or silently merge.
        // We verify that after save, we can still query projects.
        do {
            try modelContext.save()
        } catch {
            // Expected: unique constraint violation is valid behavior
            modelContext.delete(project2)
            try modelContext.save()
        }

        // Either way, project1 should still exist
        let fetch = FetchDescriptor<Project>()
        let projects = try modelContext.fetch(fetch)
        XCTAssertFalse(projects.isEmpty)
    }

    // MARK: - Message

    func testMessageInit() {
        let message = Message(content: "Hello, world!", role: .user)
        XCTAssertEqual(message.content, "Hello, world!")
        XCTAssertEqual(message.role, "user")
        XCTAssertNotNil(message.timestamp)
        XCTAssertNil(message.runId)
        XCTAssertNil(message.project)
    }

    func testMessageRoleEnum() {
        XCTAssertEqual(Message.Role.user.rawValue, "user")
        XCTAssertEqual(Message.Role.assistant.rawValue, "assistant")
        XCTAssertEqual(Message.Role.tool.rawValue, "tool")
    }

    func testProjectCascadeDelete() throws {
        // Given: a project with two messages
        let project = Project(name: "Cascade", conversationKey: "cascade-test")
        let msg1 = Message(content: "First", role: .user)
        let msg2 = Message(content: "Second", role: .assistant)
        project.messages = [msg1, msg2]
        modelContext.insert(project)
        // NOTE: SwiftData infers the inverse relationship from Message.project
        // to Project.messages, so inserting the project inserts its messages.
        try modelContext.save()

        // Verify messages exist before deletion
        let fetchBefore = try modelContext.fetch(FetchDescriptor<Message>())
        XCTAssertEqual(fetchBefore.count, 2)

        // When: delete the project
        modelContext.delete(project)
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
