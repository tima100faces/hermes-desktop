import XCTest
import SwiftData
@testable import HermesDesktop

// MARK: - ProjectSidebarViewModelTests
//
// `MockSessionsAPI` is defined in `SidebarViewModelTests.swift` and shared
// across the test target.

@MainActor
final class ProjectSidebarViewModelTests: XCTestCase {

    // MARK: Fixtures

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var mockSessionsAPI: MockSessionsAPI!
    var viewModel: ProjectSidebarViewModel!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(
            for: Chat.self, Message.self, Project.self,
            configurations: config
        )
        modelContext = modelContainer.mainContext

        mockSessionsAPI = MockSessionsAPI()
        viewModel = ProjectSidebarViewModel(sessionsAPI: mockSessionsAPI)
    }

    override func tearDown() async throws {
        viewModel = nil
        mockSessionsAPI = nil
        modelContext = nil
        modelContainer = nil
    }

    // MARK: - Create

    func testCreateProjectInsertsWithDefaultName() throws {
        // Act
        let project = viewModel.createProject(context: modelContext)

        // Assert
        XCTAssertEqual(project.name, "New project")
        let fetched = try modelContext.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(fetched, [project])
    }

    // MARK: - Delete — Happy Path

    func testConfirmDeleteRemovesServerSessionsAndProject() async throws {
        // Arrange — a project with two chats
        let project = Project(name: "Delete Me")
        let chatA = Chat(sessionId: "session-a", title: "A")
        let chatB = Chat(sessionId: "session-b", title: "B")
        chatA.project = project
        chatB.project = project
        modelContext.insert(project)
        try modelContext.save()
        viewModel.requestDelete(project)

        // Act
        let deleted = await viewModel.confirmDelete(context: modelContext)

        // Assert
        XCTAssertEqual(deleted, project)
        let deletedIds = await mockSessionsAPI.deletedSessionIds
        XCTAssertEqual(Set(deletedIds), ["session-a", "session-b"])

        let remainingProjects = try modelContext.fetch(FetchDescriptor<Project>())
        XCTAssertTrue(remainingProjects.isEmpty)
        let remainingChats = try modelContext.fetch(FetchDescriptor<Chat>())
        XCTAssertTrue(remainingChats.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testConfirmDeleteWithNoChatsDeletesProjectDirectly() async throws {
        // Arrange
        let project = Project(name: "Empty")
        modelContext.insert(project)
        try modelContext.save()
        viewModel.requestDelete(project)

        // Act
        let deleted = await viewModel.confirmDelete(context: modelContext)

        // Assert
        XCTAssertEqual(deleted, project)
        let remaining = try modelContext.fetch(FetchDescriptor<Project>())
        XCTAssertTrue(remaining.isEmpty)
    }

    // MARK: - Delete — Partial Failure

    func testConfirmDeleteStopsOnFailureKeepsProjectAndChats() async throws {
        // Arrange — one chat's server delete will fail with a generic error
        let project = Project(name: "Partial Failure")
        let chatA = Chat(sessionId: "session-a", title: "A")
        chatA.project = project
        modelContext.insert(project)
        try modelContext.save()
        await mockSessionsAPI.setDeleteSessionError(
            forId: "session-a",
            error: NSError(domain: "mock", code: -1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        )
        viewModel.requestDelete(project)

        // Act
        let deleted = await viewModel.confirmDelete(context: modelContext)

        // Assert — nothing deleted, error surfaced
        XCTAssertNil(deleted)
        XCTAssertNotNil(viewModel.errorMessage)
        let remainingProjects = try modelContext.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(remainingProjects, [project])
        let remainingChats = try modelContext.fetch(FetchDescriptor<Chat>())
        XCTAssertEqual(remainingChats, [chatA])
    }

    func testConfirmDeleteTreatsNotFoundAsAlreadyGoneAndFinishes() async throws {
        // Arrange — chatA's session is already gone server-side (404);
        // chatB's still needs deleting.
        let project = Project(name: "Retry")
        let chatA = Chat(sessionId: "session-a", title: "A")
        let chatB = Chat(sessionId: "session-b", title: "B")
        chatA.project = project
        chatB.project = project
        modelContext.insert(project)
        try modelContext.save()
        await mockSessionsAPI.setDeleteSessionError(forId: "session-a", error: APIError.notFound)
        viewModel.requestDelete(project)

        // Act
        let deleted = await viewModel.confirmDelete(context: modelContext)

        // Assert — treated as success, project fully deleted
        XCTAssertEqual(deleted, project)
        XCTAssertNil(viewModel.errorMessage)
        let deletedIds = await mockSessionsAPI.deletedSessionIds
        XCTAssertEqual(deletedIds, ["session-b"])
        let remaining = try modelContext.fetch(FetchDescriptor<Project>())
        XCTAssertTrue(remaining.isEmpty)
    }

    func testRetryAfterPartialFailureFinishesTheJob() async throws {
        // Arrange — first attempt fails on chatA
        let project = Project(name: "Retry Full")
        let chatA = Chat(sessionId: "session-a", title: "A")
        let chatB = Chat(sessionId: "session-b", title: "B")
        chatA.project = project
        chatB.project = project
        modelContext.insert(project)
        try modelContext.save()
        await mockSessionsAPI.setDeleteSessionError(
            forId: "session-a",
            error: NSError(domain: "mock", code: -1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        )
        viewModel.requestDelete(project)
        let firstAttempt = await viewModel.confirmDelete(context: modelContext)
        XCTAssertNil(firstAttempt)

        // Chat B's session was already deleted on the first pass; deleting
        // it again on retry should look like "not found" from the server.
        await mockSessionsAPI.clearDeleteSessionError(forId: "session-a")
        await mockSessionsAPI.setDeleteSessionError(forId: "session-b", error: APIError.notFound)

        // Act — retry (requestDelete again, as the row's "…" menu would)
        viewModel.requestDelete(project)
        let secondAttempt = await viewModel.confirmDelete(context: modelContext)

        // Assert
        XCTAssertEqual(secondAttempt, project)
        XCTAssertNil(viewModel.errorMessage)
        let remaining = try modelContext.fetch(FetchDescriptor<Project>())
        XCTAssertTrue(remaining.isEmpty)
    }

    // MARK: - Cancel / No-op

    func testCancelDeleteHidesConfirmation() {
        // Arrange
        let project = Project(name: "Temp")
        modelContext.insert(project)
        viewModel.requestDelete(project)

        // Act
        viewModel.cancelDelete()

        // Assert
        XCTAssertFalse(viewModel.showDeleteConfirmation)
    }

    func testConfirmDeleteWithoutPendingDoesNothing() async throws {
        // Act — no pending deletion set
        let deleted = await viewModel.confirmDelete(context: modelContext)

        // Assert
        XCTAssertNil(deleted)
    }

    // MARK: - Pending Deletion Chat Count

    func testPendingDeletionChatCount() {
        // Arrange
        let project = Project(name: "Counted")
        let chatA = Chat(sessionId: "session-a", title: "A")
        let chatB = Chat(sessionId: "session-b", title: "B")
        chatA.project = project
        chatB.project = project
        modelContext.insert(project)

        // Before requesting deletion
        XCTAssertEqual(viewModel.pendingDeletionChatCount, 0)

        // Act
        viewModel.requestDelete(project)

        // Assert
        XCTAssertEqual(viewModel.pendingDeletionChatCount, 2)
    }

    // MARK: - Error Handling

    func testClearError() async throws {
        // Arrange
        let project = Project(name: "Errored")
        let chatA = Chat(sessionId: "session-a", title: "A")
        chatA.project = project
        modelContext.insert(project)
        try modelContext.save()
        await mockSessionsAPI.setDeleteSessionError(
            forId: "session-a",
            error: NSError(domain: "mock", code: -1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        )
        viewModel.requestDelete(project)
        _ = await viewModel.confirmDelete(context: modelContext)
        XCTAssertNotNil(viewModel.errorMessage)

        // Act
        viewModel.clearError()

        // Assert
        XCTAssertNil(viewModel.errorMessage)
    }
}
