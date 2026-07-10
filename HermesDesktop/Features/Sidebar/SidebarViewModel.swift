import SwiftUI
import SwiftData
import Observation

// MARK: - SidebarViewModel

/// ViewModel for the sidebar project list.
///
/// Manages project selection, creation, and deletion.
/// Runs on `@MainActor` so it can safely drive SwiftUI state.
@MainActor
@Observable
final class SidebarViewModel {

    // MARK: Published State

    /// The currently selected project in the sidebar list.
    var selectedProject: Project?

    /// Whether the "Create Project" sheet is presented.
    var isCreatingProject = false

    /// Text binding for the new-project name text field.
    var newProjectName = ""

    /// Non-nil when an error should be displayed.
    var errorMessage: String?

    /// Whether the delete confirmation alert is shown.
    var showDeleteConfirmation = false

    /// The project pending confirmation before deletion.
    private var pendingDeletion: Project?

    // MARK: - Intent(s)

    /// Create a new project from the current `newProjectName`.
    ///
    /// - Parameter context: The SwiftData `ModelContext` to insert into.
    func createProject(context: ModelContext) {
        let trimmed = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Project name cannot be empty"
            return
        }

        // conversationKey: lowercase, hyphens, strip non-alphanumeric
        let key = trimmed
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(
                of: "[^a-z0-9-]",
                with: "",
                options: .regularExpression
            )

        let project = Project(name: trimmed, conversationKey: key)
        context.insert(project)
        try? context.save()

        newProjectName = ""
        isCreatingProject = false
        selectedProject = project
    }

    /// Request deletion — shows confirmation alert first.
    ///
    /// - Parameter project: The project to delete.
    func requestDelete(_ project: Project) {
        pendingDeletion = project
        showDeleteConfirmation = true
    }

    /// Confirm and execute the pending deletion.
    ///
    /// - Parameter context: The SwiftData `ModelContext` to delete from.
    func confirmDelete(context: ModelContext) {
        guard let project = pendingDeletion else { return }
        context.delete(project)
        try? context.save()
        if selectedProject == project {
            selectedProject = nil
        }
        pendingDeletion = nil
        showDeleteConfirmation = false
    }

    /// Cancel the pending deletion.
    func cancelDelete() {
        pendingDeletion = nil
        showDeleteConfirmation = false
    }

    /// Dismiss the current error.
    func clearError() {
        errorMessage = nil
    }
}
