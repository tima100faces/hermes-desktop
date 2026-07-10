import SwiftUI
import SwiftData
import Observation

// MARK: - ChatSidebarViewModel

/// ViewModel for the sidebar's chat list (Sessions API-backed).
///
/// Kept separate from `SidebarViewModel` (topics) since chat CRUD is
/// network-backed (create/rename/delete all round-trip to the Sessions
/// API), unlike topics, which are purely local.
@MainActor
@Observable
final class ChatSidebarViewModel {

    // MARK: Published State

    /// Non-nil when an error should be displayed.
    var errorMessage: String?

    /// Whether the delete confirmation alert is shown.
    var showDeleteConfirmation = false

    /// The chat pending confirmation before deletion.
    private var pendingDeletion: Chat?

    /// Whether the "Rename Chat" sheet is presented.
    var isRenamingChat = false

    /// Text binding for the rename text field.
    var renameChatName = ""

    /// The chat pending a rename.
    private var pendingRename: Chat?

    // MARK: - Dependencies

    private let sessionsAPI: SessionsAPIProtocol

    // MARK: - Initialization

    init(sessionsAPI: SessionsAPIProtocol) {
        self.sessionsAPI = sessionsAPI
    }

    // MARK: - Create

    /// Creates a new, empty chat (`POST /api/sessions`) and returns it.
    ///
    /// - Parameter context: The SwiftData `ModelContext` to insert into.
    /// - Returns: The newly created `Chat`, or `nil` if the request failed.
    func createChat(context: ModelContext) async -> Chat? {
        do {
            let session = try await sessionsAPI.createSession()
            let chat = Chat(sessionId: session.id, title: session.title ?? "Новый чат")
            context.insert(chat)
            try? context.save()
            return chat
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Delete

    /// Request deletion — shows confirmation alert first.
    func requestDelete(_ chat: Chat) {
        pendingDeletion = chat
        showDeleteConfirmation = true
    }

    /// Confirm and execute the pending deletion (`DELETE /api/sessions/{id}`).
    ///
    /// Returns the deleted `Chat` (or `nil` if nothing was pending) so the
    /// caller can clear its selection if it pointed at this chat — passing
    /// an `inout` selection binding across this `async` call isn't possible
    /// under actor isolation.
    ///
    /// - Parameter context: The SwiftData `ModelContext` to delete from.
    @discardableResult
    func confirmDelete(context: ModelContext) async -> Chat? {
        guard let chat = pendingDeletion else { return nil }
        try? await sessionsAPI.deleteSession(id: chat.sessionId)
        context.delete(chat)
        try? context.save()
        pendingDeletion = nil
        showDeleteConfirmation = false
        return chat
    }

    /// Cancel the pending deletion.
    func cancelDelete() {
        pendingDeletion = nil
        showDeleteConfirmation = false
    }

    // MARK: - Rename

    /// Request a rename — shows the rename sheet pre-filled with the
    /// chat's current title.
    func requestRename(_ chat: Chat) {
        pendingRename = chat
        renameChatName = chat.title
        errorMessage = nil
        isRenamingChat = true
    }

    /// Confirm and apply the pending rename (`PATCH /api/sessions/{id}`).
    ///
    /// - Parameter context: The SwiftData `ModelContext` to save into.
    func confirmRename(context: ModelContext) async {
        let trimmed = renameChatName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Название чата не может быть пустым"
            return
        }
        guard let chat = pendingRename else { return }

        do {
            _ = try await sessionsAPI.renameSession(id: chat.sessionId, title: trimmed)
            chat.title = trimmed
            // A manual rename overrides the first-message auto-title.
            chat.hasAutoTitled = true
            try? context.save()

            renameChatName = ""
            pendingRename = nil
            isRenamingChat = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Cancel the pending rename.
    func cancelRename() {
        pendingRename = nil
        renameChatName = ""
        isRenamingChat = false
    }

    /// Dismiss the current error.
    func clearError() {
        errorMessage = nil
    }
}
