import XCTest
import SwiftData
@testable import HermesDesktop

// MARK: - SidebarViewModelTests

@MainActor
final class SidebarViewModelTests: XCTestCase {

    // MARK: Fixtures

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var viewModel: SidebarViewModel!
    var selectedTopic: Topic?

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(
            for: Topic.self, Message.self,
            configurations: config
        )
        modelContext = modelContainer.mainContext

        viewModel = SidebarViewModel()
        selectedTopic = nil
    }

    override func tearDown() async throws {
        viewModel = nil
        modelContext = nil
        modelContainer = nil
        selectedTopic = nil
    }

    // MARK: - Create Topic

    func testCreateTopicInsertsIntoSwiftData() throws {
        // Arrange
        viewModel.newTopicName = "My Topic"

        // Act
        viewModel.createTopic(context: modelContext, selectedTopic: &selectedTopic)

        // Assert — topic persisted
        let descriptor = FetchDescriptor<Topic>()
        let topics = try modelContext.fetch(descriptor)

        XCTAssertEqual(topics.count, 1)
        XCTAssertEqual(topics[0].name, "My Topic")
    }

    func testCreateTopicSetsSelectedTopic() {
        // Arrange
        viewModel.newTopicName = "My Topic"

        // Act
        viewModel.createTopic(context: modelContext, selectedTopic: &selectedTopic)

        // Assert
        XCTAssertNotNil(selectedTopic)
        XCTAssertEqual(selectedTopic?.name, "My Topic")
    }

    func testCreateTopicClearsNameAndDismissesSheet() {
        // Arrange
        viewModel.newTopicName = "My Topic"
        viewModel.isCreatingTopic = true

        // Act
        viewModel.createTopic(context: modelContext, selectedTopic: &selectedTopic)

        // Assert
        XCTAssertTrue(viewModel.newTopicName.isEmpty)
        XCTAssertFalse(viewModel.isCreatingTopic)
    }

    func testCreateTopicEmptyNameShowsError() {
        // Arrange — empty name
        viewModel.newTopicName = ""

        // Act
        viewModel.createTopic(context: modelContext, selectedTopic: &selectedTopic)

        // Assert
        XCTAssertEqual(viewModel.errorMessage, "Название темы не может быть пустым")

        // No topic should have been created
        let descriptor = FetchDescriptor<Topic>()
        let topics = try? modelContext.fetch(descriptor)
        XCTAssertEqual(topics?.count ?? 0, 0)

        // selectedTopic should remain nil
        XCTAssertNil(selectedTopic)
    }

    func testCreateTopicWhitespaceNameShowsError() {
        // Arrange
        viewModel.newTopicName = "   \n  \t  "

        // Act
        viewModel.createTopic(context: modelContext, selectedTopic: &selectedTopic)

        // Assert
        XCTAssertEqual(viewModel.errorMessage, "Название темы не может быть пустым")
    }

    // MARK: - Conversation Key Generation

    func testConversationKeyGeneration() {
        // Arrange
        viewModel.newTopicName = "My Topic"

        // Act
        viewModel.createTopic(context: modelContext, selectedTopic: &selectedTopic)

        // Assert
        XCTAssertEqual(selectedTopic?.conversationKey, "my-topic")
    }

    func testConversationKeyStripsSpecialCharacters() {
        // Arrange
        viewModel.newTopicName = "Hello! @World #2024"

        // Act
        viewModel.createTopic(context: modelContext, selectedTopic: &selectedTopic)

        // Assert — only lowercase alphanumeric and hyphens
        XCTAssertEqual(selectedTopic?.conversationKey, "hello-world-2024")
    }

    func testConversationKeyHandlesMixedCase() {
        // Arrange
        viewModel.newTopicName = "UPPERCASE Topic"

        // Act
        viewModel.createTopic(context: modelContext, selectedTopic: &selectedTopic)

        // Assert
        XCTAssertEqual(selectedTopic?.conversationKey, "uppercase-topic")
    }

    func testConversationKeyHandlesMultipleHyphens() {
        // Arrange
        viewModel.newTopicName = "A   B   C"

        // Act
        viewModel.createTopic(context: modelContext, selectedTopic: &selectedTopic)

        // Assert
        XCTAssertEqual(selectedTopic?.conversationKey, "a---b---c")
    }

    // MARK: - Delete Topic

    func testDeleteTopicRemovesFromSwiftData() throws {
        // Arrange
        viewModel.newTopicName = "Delete Me"
        viewModel.createTopic(context: modelContext, selectedTopic: &selectedTopic)

        let topic = selectedTopic!
        viewModel.requestDelete(topic)

        // Act
        viewModel.confirmDelete(context: modelContext, selectedTopic: &selectedTopic)

        // Assert — topic removed
        let descriptor = FetchDescriptor<Topic>()
        let topics = try modelContext.fetch(descriptor)
        XCTAssertTrue(topics.isEmpty)
        XCTAssertNil(selectedTopic)
        XCTAssertFalse(viewModel.showDeleteConfirmation)
    }

    func testDeleteTopicClearsSelectionIfMatches() {
        // Arrange
        viewModel.newTopicName = "Target"
        viewModel.createTopic(context: modelContext, selectedTopic: &selectedTopic)

        let topic = selectedTopic!
        viewModel.requestDelete(topic)

        // Act
        viewModel.confirmDelete(context: modelContext, selectedTopic: &selectedTopic)

        // Assert
        XCTAssertNil(selectedTopic)
    }

    func testDeleteTopicDoesNotClearSelectionIfDifferent() throws {
        // Arrange — create two topics, select the second
        viewModel.newTopicName = "First"
        viewModel.createTopic(context: modelContext, selectedTopic: &selectedTopic)

        viewModel.newTopicName = "Second"
        viewModel.createTopic(context: modelContext, selectedTopic: &selectedTopic)

        // Now delete the first topic
        let descriptor = FetchDescriptor<Topic>(
            predicate: #Predicate { $0.name == "First" }
        )
        let topics = try modelContext.fetch(descriptor)
        let firstTopic = topics[0]

        viewModel.requestDelete(firstTopic)
        viewModel.confirmDelete(context: modelContext, selectedTopic: &selectedTopic)

        // Assert — selection unchanged (still "Second")
        XCTAssertEqual(selectedTopic?.name, "Second")
    }

    func testRequestDeleteShowsConfirmation() {
        // Arrange
        viewModel.newTopicName = "Temp"
        viewModel.createTopic(context: modelContext, selectedTopic: &selectedTopic)
        let topic = selectedTopic!

        // Act
        viewModel.requestDelete(topic)

        // Assert
        XCTAssertTrue(viewModel.showDeleteConfirmation)
    }

    func testCancelDeleteHidesConfirmation() {
        // Arrange
        viewModel.newTopicName = "Temp"
        viewModel.createTopic(context: modelContext, selectedTopic: &selectedTopic)

        viewModel.requestDelete(selectedTopic!)

        // Act
        viewModel.cancelDelete()

        // Assert
        XCTAssertFalse(viewModel.showDeleteConfirmation)
        // Topic still exists
        XCTAssertNotNil(selectedTopic)
    }

    func testConfirmDeleteWithoutPendingDoesNothing() throws {
        // Act — no pending deletion set
        viewModel.confirmDelete(context: modelContext, selectedTopic: &selectedTopic)

        // Assert — no crash, state unchanged
        XCTAssertFalse(viewModel.showDeleteConfirmation)
        XCTAssertNil(selectedTopic)
    }

    // MARK: - Error Handling

    func testClearError() {
        // Arrange
        viewModel.newTopicName = ""
        viewModel.createTopic(context: modelContext, selectedTopic: &selectedTopic)
        XCTAssertNotNil(viewModel.errorMessage)

        // Act
        viewModel.clearError()

        // Assert
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - Multiple Topics

    func testMultipleTopicsCreated() throws {
        // Arrange
        viewModel.newTopicName = "Alpha"
        viewModel.createTopic(context: modelContext, selectedTopic: &selectedTopic)

        viewModel.newTopicName = "Beta"
        viewModel.createTopic(context: modelContext, selectedTopic: &selectedTopic)

        viewModel.newTopicName = "Gamma"
        viewModel.createTopic(context: modelContext, selectedTopic: &selectedTopic)

        // Assert
        let descriptor = FetchDescriptor<Topic>()
        let topics = try modelContext.fetch(descriptor)

        XCTAssertEqual(topics.count, 3)
        // Last created should be selected
        XCTAssertEqual(selectedTopic?.name, "Gamma")
    }

    func testCreateTopicPreservesExistingTopics() throws {
        // Arrange
        viewModel.newTopicName = "Existing"
        viewModel.createTopic(context: modelContext, selectedTopic: &selectedTopic)

        // Act
        viewModel.newTopicName = "New"
        viewModel.createTopic(context: modelContext, selectedTopic: &selectedTopic)

        // Assert — both exist
        let descriptor = FetchDescriptor<Topic>()
        let topics = try modelContext.fetch(descriptor)
        XCTAssertEqual(topics.count, 2)
    }

    // MARK: - Deletion Clears Error

    func testDeleteTopicClearsError() {
        // Arrange — trigger an error first
        viewModel.newTopicName = ""
        viewModel.createTopic(context: modelContext, selectedTopic: &selectedTopic)
        XCTAssertNotNil(viewModel.errorMessage)

        // Create a valid topic to delete
        viewModel.errorMessage = nil  // clear any residual error state
        viewModel.newTopicName = "Delete Me"
        viewModel.createTopic(context: modelContext, selectedTopic: &selectedTopic)

        // Act
        viewModel.requestDelete(selectedTopic!)
        viewModel.confirmDelete(context: modelContext, selectedTopic: &selectedTopic)

        // Assert — deletion succeeded, no error
        XCTAssertNil(viewModel.errorMessage)
    }
}
