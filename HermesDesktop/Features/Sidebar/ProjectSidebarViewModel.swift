import SwiftUI
import SwiftData
import Observation

// MARK: - ProjectSidebarViewModel

/// ViewModel for the sidebar's Projects section — project-level create and
/// delete. Renaming and instructions editing happen inline on `ProjectView`
/// directly (bound to the `@Model` object), not here.
@MainActor
@Observable
final class ProjectSidebarViewModel {

    // MARK: Published State

    /// Non-nil when a delete failure should be surfaced to the user.
    var errorMessage: String?

    /// Whether the delete confirmation alert is shown.
    var showDeleteConfirmation = false

    /// The project pending confirmation before deletion.
    private(set) var pendingDeletion: Project?

    /// Chat count for the pending deletion, for the confirmation alert's
    /// "will delete N chats" message. `0` when nothing is pending.
    var pendingDeletionChatCount: Int {
        pendingDeletion?.chats.count ?? 0
    }

    // MARK: - Dependencies

    private let sessionsAPI: SessionsAPIProtocol

    // MARK: - Initialization

    init(sessionsAPI: SessionsAPIProtocol) {
        self.sessionsAPI = sessionsAPI
    }

    // MARK: - Create

    /// Creates a new, empty project with a default name — fully local, no
    /// server round-trip (unlike chat creation).
    func createProject(context: ModelContext) -> Project {
        let project = Project(name: "New project")
        context.insert(project)
        try? context.save()
        return project
    }

    // MARK: - Delete

    /// Request deletion — shows confirmation alert first.
    func requestDelete(_ project: Project) {
        pendingDeletion = project
        showDeleteConfirmation = true
    }

    /// Confirm and execute the pending deletion.
    ///
    /// Deletes each chat's server-side session first (sorted by
    /// `createdAt` for deterministic retries). A session that's already
    /// gone (`APIError.notFound`) is treated as success and skipped — this
    /// is what makes a retry after a partial failure converge. Any other
    /// failure stops immediately: the project and its chats are **not**
    /// deleted, `errorMessage` is set, and `pendingDeletion` stays set so
    /// the next "Delete" click retries the same project, picking up only
    /// where it left off.
    ///
    /// - Parameter context: The SwiftData `ModelContext` to delete from.
    /// - Returns: The deleted `Project` on success, or `nil` if nothing was
    ///   pending or the deletion stopped on a failure.
    @discardableResult
    func confirmDelete(context: ModelContext) async -> Project? {
        errorMessage = nil
        guard let project = pendingDeletion else { return nil }

        let chatsByAge = project.chats.sorted { $0.createdAt < $1.createdAt }
        for chat in chatsByAge {
            guard let sessionId = chat.sessionId else { continue }
            do {
                try await sessionsAPI.deleteSession(id: sessionId)
            } catch APIError.notFound {
                continue
            } catch {
                errorMessage = error.localizedDescription
                return nil
            }
        }

        context.delete(project)
        try? context.save()
        pendingDeletion = nil
        showDeleteConfirmation = false
        return project
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
