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

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(
            for: Project.self, Message.self,
            configurations: config
        )
        modelContext = modelContainer.mainContext

        viewModel = SidebarViewModel()
    }

    override func tearDown() async throws {
        viewModel = nil
        modelContext = nil
        modelContainer = nil
    }

    // MARK: - Create Project

    func testCreateProjectInsertsIntoSwiftData() throws {
        // Arrange
        viewModel.newProjectName = "My Project"

        // Act
        viewModel.createProject(context: modelContext)

        // Assert — project persisted
        let descriptor = FetchDescriptor<Project>()
        let projects = try modelContext.fetch(descriptor)

        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "My Project")
    }

    func testCreateProjectSetsSelectedProject() {
        // Arrange
        viewModel.newProjectName = "My Project"

        // Act
        viewModel.createProject(context: modelContext)

        // Assert
        XCTAssertNotNil(viewModel.selectedProject)
        XCTAssertEqual(viewModel.selectedProject?.name, "My Project")
    }

    func testCreateProjectClearsNameAndDismissesSheet() {
        // Arrange
        viewModel.newProjectName = "My Project"
        viewModel.isCreatingProject = true

        // Act
        viewModel.createProject(context: modelContext)

        // Assert
        XCTAssertTrue(viewModel.newProjectName.isEmpty)
        XCTAssertFalse(viewModel.isCreatingProject)
    }

    func testCreateProjectEmptyNameShowsError() {
        // Arrange — empty name
        viewModel.newProjectName = ""

        // Act
        viewModel.createProject(context: modelContext)

        // Assert
        XCTAssertEqual(viewModel.errorMessage, "Project name cannot be empty")

        // No project should have been created
        let descriptor = FetchDescriptor<Project>()
        let projects = try? modelContext.fetch(descriptor)
        XCTAssertEqual(projects?.count ?? 0, 0)

        // selectedProject should remain nil
        XCTAssertNil(viewModel.selectedProject)
    }

    func testCreateProjectWhitespaceNameShowsError() {
        // Arrange
        viewModel.newProjectName = "   \n  \t  "

        // Act
        viewModel.createProject(context: modelContext)

        // Assert
        XCTAssertEqual(viewModel.errorMessage, "Project name cannot be empty")
    }

    // MARK: - Conversation Key Generation

    func testConversationKeyGeneration() {
        // Arrange
        viewModel.newProjectName = "My Project"

        // Act
        viewModel.createProject(context: modelContext)

        // Assert
        XCTAssertEqual(viewModel.selectedProject?.conversationKey, "my-project")
    }

    func testConversationKeyStripsSpecialCharacters() {
        // Arrange
        viewModel.newProjectName = "Hello! @World #2024"

        // Act
        viewModel.createProject(context: modelContext)

        // Assert — only lowercase alphanumeric and hyphens
        XCTAssertEqual(viewModel.selectedProject?.conversationKey, "hello-world-2024")
    }

    func testConversationKeyHandlesMixedCase() {
        // Arrange
        viewModel.newProjectName = "UPPERCASE Project"

        // Act
        viewModel.createProject(context: modelContext)

        // Assert
        XCTAssertEqual(viewModel.selectedProject?.conversationKey, "uppercase-project")
    }

    func testConversationKeyHandlesMultipleHyphens() {
        // Arrange
        viewModel.newProjectName = "A   B   C"

        // Act
        viewModel.createProject(context: modelContext)

        // Assert
        XCTAssertEqual(viewModel.selectedProject?.conversationKey, "a---b---c")
    }

    // MARK: - Delete Project

    func testDeleteProjectRemovesFromSwiftData() throws {
        // Arrange
        viewModel.newProjectName = "Delete Me"
        viewModel.createProject(context: modelContext)

        let project = viewModel.selectedProject!
        viewModel.requestDelete(project)

        // Act
        viewModel.confirmDelete(context: modelContext)

        // Assert — project removed
        let descriptor = FetchDescriptor<Project>()
        let projects = try modelContext.fetch(descriptor)
        XCTAssertTrue(projects.isEmpty)
        XCTAssertNil(viewModel.selectedProject)
        XCTAssertFalse(viewModel.showDeleteConfirmation)
    }

    func testDeleteProjectClearsSelectionIfMatches() {
        // Arrange
        viewModel.newProjectName = "Target"
        viewModel.createProject(context: modelContext)

        let project = viewModel.selectedProject!
        viewModel.requestDelete(project)

        // Act
        viewModel.confirmDelete(context: modelContext)

        // Assert
        XCTAssertNil(viewModel.selectedProject)
    }

    func testDeleteProjectDoesNotClearSelectionIfDifferent() throws {
        // Arrange — create two projects, select the second
        viewModel.newProjectName = "First"
        viewModel.createProject(context: modelContext)

        viewModel.newProjectName = "Second"
        viewModel.createProject(context: modelContext)
        let secondProject = viewModel.selectedProject!

        // Now delete the first project
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.name == "First" }
        )
        let projects = try modelContext.fetch(descriptor)
        let firstProject = projects[0]

        viewModel.requestDelete(firstProject)
        viewModel.confirmDelete(context: modelContext)

        // Assert — selection unchanged (still "Second")
        XCTAssertEqual(viewModel.selectedProject?.name, "Second")
    }

    func testRequestDeleteShowsConfirmation() {
        // Arrange
        viewModel.newProjectName = "Temp"
        viewModel.createProject(context: modelContext)
        let project = viewModel.selectedProject!

        // Act
        viewModel.requestDelete(project)

        // Assert
        XCTAssertTrue(viewModel.showDeleteConfirmation)
    }

    func testCancelDeleteHidesConfirmation() {
        // Arrange
        viewModel.newProjectName = "Temp"
        viewModel.createProject(context: modelContext)

        viewModel.requestDelete(viewModel.selectedProject!)

        // Act
        viewModel.cancelDelete()

        // Assert
        XCTAssertFalse(viewModel.showDeleteConfirmation)
        // Project still exists
        XCTAssertNotNil(viewModel.selectedProject)
    }

    func testConfirmDeleteWithoutPendingDoesNothing() throws {
        // Act — no pending deletion set
        viewModel.confirmDelete(context: modelContext)

        // Assert — no crash, state unchanged
        XCTAssertFalse(viewModel.showDeleteConfirmation)
        XCTAssertNil(viewModel.selectedProject)
    }

    // MARK: - Error Handling

    func testClearError() {
        // Arrange
        viewModel.newProjectName = ""
        viewModel.createProject(context: modelContext)
        XCTAssertNotNil(viewModel.errorMessage)

        // Act
        viewModel.clearError()

        // Assert
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - Multiple Projects

    func testMultipleProjectsCreated() throws {
        // Arrange
        viewModel.newProjectName = "Alpha"
        viewModel.createProject(context: modelContext)

        viewModel.newProjectName = "Beta"
        viewModel.createProject(context: modelContext)

        viewModel.newProjectName = "Gamma"
        viewModel.createProject(context: modelContext)

        // Assert
        let descriptor = FetchDescriptor<Project>()
        let projects = try modelContext.fetch(descriptor)

        XCTAssertEqual(projects.count, 3)
        // Last created should be selected
        XCTAssertEqual(viewModel.selectedProject?.name, "Gamma")
    }

    func testCreateProjectPreservesExistingProjects() throws {
        // Arrange
        viewModel.newProjectName = "Existing"
        viewModel.createProject(context: modelContext)

        // Act
        viewModel.newProjectName = "New"
        viewModel.createProject(context: modelContext)

        // Assert — both exist
        let descriptor = FetchDescriptor<Project>()
        let projects = try modelContext.fetch(descriptor)
        XCTAssertEqual(projects.count, 2)
    }

    // MARK: - Deletion Clears Error

    func testDeleteProjectClearsError() {
        // Arrange — trigger an error first
        viewModel.newProjectName = ""
        viewModel.createProject(context: modelContext)
        XCTAssertNotNil(viewModel.errorMessage)

        // Create a valid project to delete
        viewModel.newProjectName = "Delete Me"
        viewModel.createProject(context: modelContext)

        // Act
        viewModel.requestDelete(viewModel.selectedProject!)
        viewModel.confirmDelete(context: modelContext)

        // Assert — error was cleared by the create, and deletion succeeded
        XCTAssertNil(viewModel.errorMessage)
    }
}
