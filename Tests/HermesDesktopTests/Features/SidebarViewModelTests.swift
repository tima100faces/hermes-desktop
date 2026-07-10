import XCTest
import SwiftData
@testable import HermesDesktop

// MARK: - MockSessionsAPI

/// Controlled mock of the Hermes Sessions API for `ChatSidebarViewModel` tests.
actor MockSessionsAPI: SessionsAPIProtocol {

    var createSessionResult: Result<SessionInfo, Error> = .success(SessionInfo(id: "session-1", title: nil))
    var renameSessionResult: Result<SessionInfo, Error> = .success(SessionInfo(id: "session-1", title: "Renamed"))
    var deleteSessionError: Error?

    private(set) var deletedSessionIds: [String] = []
    private(set) var renamedSessionIds: [String] = []

    func createSession() async throws -> SessionInfo {
        try createSessionResult.get()
    }

    func getSession(id: String) async throws -> SessionInfo {
        SessionInfo(id: id, title: nil)
    }

    func renameSession(id: String, title: String) async throws -> SessionInfo {
        renamedSessionIds.append(id)
        return try renameSessionResult.get()
    }

    func deleteSession(id: String) async throws {
        if let error = deleteSessionError { throw error }
        deletedSessionIds.append(id)
    }

    func getMessages(sessionId: String) async throws -> [SessionMessage] { [] }

    func streamChat(sessionId: String, input: String) async throws -> (stream: AsyncStream<RunEvent>, cancel: @Sendable () -> Void) {
        (AsyncStream { $0.finish() }, {})
    }

    // MARK: Test Helpers

    func setCreateSessionToFail() {
        createSessionResult = .failure(
            NSError(domain: "mock", code: -1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        )
    }

    func setRenameSessionToFail() {
        renameSessionResult = .failure(
            NSError(domain: "mock", code: -1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        )
    }
}

// MARK: - SidebarViewModelTests

@MainActor
final class SidebarViewModelTests: XCTestCase {

    // MARK: Fixtures

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var mockSessionsAPI: MockSessionsAPI!
    var viewModel: ChatSidebarViewModel!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(
            for: Chat.self, Message.self,
            configurations: config
        )
        modelContext = modelContainer.mainContext

        mockSessionsAPI = MockSessionsAPI()
        viewModel = ChatSidebarViewModel(sessionsAPI: mockSessionsAPI)
    }

    override func tearDown() async throws {
        viewModel = nil
        mockSessionsAPI = nil
        modelContext = nil
        modelContainer = nil
    }

    // MARK: - Create Chat

    func testCreateChatInsertsSessionsBackedChat() async throws {
        // Act
        let chat = await viewModel.createChat(context: modelContext)

        // Assert — chat persisted, Sessions-backed, unpinned
        let descriptor = FetchDescriptor<Chat>()
        let chats = try modelContext.fetch(descriptor)

        XCTAssertEqual(chats.count, 1)
        XCTAssertEqual(chat?.sessionId, "session-1")
        XCTAssertNil(chat?.conversationKey)
        XCTAssertFalse(chat?.isPinned ?? true)
    }

    func testCreateChatFailureSetsErrorAndReturnsNil() async throws {
        // Arrange
        await mockSessionsAPI.setCreateSessionToFail()

        // Act
        let chat = await viewModel.createChat(context: modelContext)

        // Assert
        XCTAssertNil(chat)
        XCTAssertNotNil(viewModel.errorMessage)

        let descriptor = FetchDescriptor<Chat>()
        let chats = try modelContext.fetch(descriptor)
        XCTAssertTrue(chats.isEmpty)
    }

    // MARK: - Toggle Pin

    func testTogglePinFlipsIsPinned() {
        // Arrange — a pinned, Runs-backed chat (as migrated from Topic)
        let chat = Chat(conversationKey: "legacy", title: "Legacy", isPinned: true)
        modelContext.insert(chat)

        // Act
        viewModel.togglePin(chat, context: modelContext)

        // Assert
        XCTAssertFalse(chat.isPinned)

        // Act again — toggles back
        viewModel.togglePin(chat, context: modelContext)
        XCTAssertTrue(chat.isPinned)
    }

    func testTogglePinWorksForSessionsBackedChat() {
        // Arrange — a regular, unpinned Sessions-backed chat
        let chat = Chat(sessionId: "session-2", title: "Regular")
        modelContext.insert(chat)

        // Act
        viewModel.togglePin(chat, context: modelContext)

        // Assert
        XCTAssertTrue(chat.isPinned)
    }

    // MARK: - Rename

    func testRenameSessionsBackedChatCallsServerAndUpdatesTitle() async throws {
        // Arrange
        let chat = Chat(sessionId: "session-1", title: "Old Title")
        modelContext.insert(chat)
        viewModel.requestRename(chat)
        viewModel.renameChatName = "New Title"

        // Act
        await viewModel.confirmRename(context: modelContext)

        // Assert — server called, title + auto-title flag updated locally
        let renamedIds = await mockSessionsAPI.renamedSessionIds
        XCTAssertEqual(renamedIds, ["session-1"])
        XCTAssertEqual(chat.title, "New Title")
        XCTAssertTrue(chat.hasAutoTitled)
        XCTAssertFalse(viewModel.isRenamingChat)
    }

    func testRenameRunsBackedChatIsLocalOnly() async throws {
        // Arrange — a pinned, Runs-backed chat (no sessionId)
        let chat = Chat(conversationKey: "legacy", title: "Old Title", isPinned: true)
        modelContext.insert(chat)
        viewModel.requestRename(chat)
        viewModel.renameChatName = "New Title"

        // Act
        await viewModel.confirmRename(context: modelContext)

        // Assert — no server call, title updated locally
        let renamedIds = await mockSessionsAPI.renamedSessionIds
        XCTAssertTrue(renamedIds.isEmpty)
        XCTAssertEqual(chat.title, "New Title")
        XCTAssertFalse(viewModel.isRenamingChat)
    }

    func testRenameEmptyNameShowsError() async throws {
        // Arrange
        let chat = Chat(sessionId: "session-1", title: "Old Title")
        modelContext.insert(chat)
        viewModel.requestRename(chat)
        viewModel.renameChatName = "   "

        // Act
        await viewModel.confirmRename(context: modelContext)

        // Assert
        XCTAssertEqual(viewModel.errorMessage, "Название чата не может быть пустым")
        XCTAssertEqual(chat.title, "Old Title")
        XCTAssertTrue(viewModel.isRenamingChat)
    }

    func testRenameServerFailureKeepsSheetOpenWithError() async throws {
        // Arrange
        await mockSessionsAPI.setRenameSessionToFail()
        let chat = Chat(sessionId: "session-1", title: "Old Title")
        modelContext.insert(chat)
        viewModel.requestRename(chat)
        viewModel.renameChatName = "New Title"

        // Act
        await viewModel.confirmRename(context: modelContext)

        // Assert — title unchanged, error surfaced, sheet stays open
        XCTAssertEqual(chat.title, "Old Title")
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.isRenamingChat)
    }

    func testCancelRenameClearsState() {
        // Arrange
        let chat = Chat(sessionId: "session-1", title: "Old Title")
        modelContext.insert(chat)
        viewModel.requestRename(chat)

        // Act
        viewModel.cancelRename()

        // Assert
        XCTAssertFalse(viewModel.isRenamingChat)
        XCTAssertTrue(viewModel.renameChatName.isEmpty)
    }

    // MARK: - Delete

    func testDeleteSessionsBackedChatCallsServerAndRemoves() async throws {
        // Arrange
        let chat = Chat(sessionId: "session-1", title: "Delete Me")
        modelContext.insert(chat)
        try modelContext.save()
        viewModel.requestDelete(chat)

        // Act
        let deleted = await viewModel.confirmDelete(context: modelContext)

        // Assert
        let deletedIds = await mockSessionsAPI.deletedSessionIds
        XCTAssertEqual(deletedIds, ["session-1"])
        XCTAssertEqual(deleted, chat)

        let descriptor = FetchDescriptor<Chat>()
        let chats = try modelContext.fetch(descriptor)
        XCTAssertTrue(chats.isEmpty)
        XCTAssertFalse(viewModel.showDeleteConfirmation)
    }

    func testDeleteRunsBackedChatIsLocalOnly() async throws {
        // Arrange — a pinned, Runs-backed chat (no sessionId)
        let chat = Chat(conversationKey: "legacy", title: "Delete Me", isPinned: true)
        modelContext.insert(chat)
        try modelContext.save()
        viewModel.requestDelete(chat)

        // Act
        let deleted = await viewModel.confirmDelete(context: modelContext)

        // Assert — no server call, still removed locally
        let deletedIds = await mockSessionsAPI.deletedSessionIds
        XCTAssertTrue(deletedIds.isEmpty)
        XCTAssertEqual(deleted, chat)

        let descriptor = FetchDescriptor<Chat>()
        let chats = try modelContext.fetch(descriptor)
        XCTAssertTrue(chats.isEmpty)
    }

    func testCancelDeleteHidesConfirmation() {
        // Arrange
        let chat = Chat(sessionId: "session-1", title: "Temp")
        modelContext.insert(chat)
        viewModel.requestDelete(chat)

        // Act
        viewModel.cancelDelete()

        // Assert
        XCTAssertFalse(viewModel.showDeleteConfirmation)
    }

    func testConfirmDeleteWithoutPendingDoesNothing() async throws {
        // Act — no pending deletion set
        let deleted = await viewModel.confirmDelete(context: modelContext)

        // Assert — no crash, nothing deleted
        XCTAssertNil(deleted)
        XCTAssertFalse(viewModel.showDeleteConfirmation)
    }

    // MARK: - Error Handling

    func testClearError() async throws {
        // Arrange
        await mockSessionsAPI.setCreateSessionToFail()
        _ = await viewModel.createChat(context: modelContext)
        XCTAssertNotNil(viewModel.errorMessage)

        // Act
        viewModel.clearError()

        // Assert
        XCTAssertNil(viewModel.errorMessage)
    }
}
