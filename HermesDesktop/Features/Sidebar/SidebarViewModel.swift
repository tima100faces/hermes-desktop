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

    /// Whether the "Rename Project" sheet is presented.
    var isRenamingProject = false

    /// Text binding for the rename text field.
    var renameProjectName = ""

    /// The project pending a rename.
    private var pendingRename: Project?

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

    /// Request a rename — shows the rename sheet pre-filled with the
    /// project's current name.
    ///
    /// - Parameter project: The project to rename.
    func requestRename(_ project: Project) {
        pendingRename = project
        renameProjectName = project.name
        errorMessage = nil
        isRenamingProject = true
    }

    /// Confirm and apply the pending rename.
    ///
    /// - Parameter context: The SwiftData `ModelContext` to save into.
    func confirmRename(context: ModelContext) {
        let trimmed = renameProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Project name cannot be empty"
            return
        }
        pendingRename?.name = trimmed
        try? context.save()

        renameProjectName = ""
        pendingRename = nil
        isRenamingProject = false
    }

    /// Cancel the pending rename.
    func cancelRename() {
        pendingRename = nil
        renameProjectName = ""
        isRenamingProject = false
    }

    /// Dismiss the current error.
    func clearError() {
        errorMessage = nil
    }
}
