import SwiftUI
import SwiftData
import Observation

// MARK: - ChatSidebarViewModel

/// ViewModel for the sidebar's single chat list.
///
/// Create always goes through the Sessions API — pinned, Runs-backed chats
/// only ever come from migrated `Topic` data, never from the "+" button.
/// Rename and delete branch on transport: Sessions-backed chats
/// (`sessionId != nil`) round-trip to the server; Runs-backed chats
/// (`conversationKey != nil`) are local-only, same as before unification.
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

    /// Creates a new, empty Sessions-backed chat (`POST /api/sessions`) and
    /// returns it.
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

    // MARK: - Pin

    /// Toggles `isPinned` — purely local, no server round-trip for either
    /// transport.
    func togglePin(_ chat: Chat, context: ModelContext) {
        chat.isPinned.toggle()
        try? context.save()
    }

    // MARK: - Delete

    /// Request deletion — shows confirmation alert first.
    func requestDelete(_ chat: Chat) {
        pendingDeletion = chat
        showDeleteConfirmation = true
    }

    /// Confirm and execute the pending deletion. Sessions-backed chats are
    /// also deleted server-side (`DELETE /api/sessions/{id}`); Runs-backed
    /// chats are local-only.
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
        if let sessionId = chat.sessionId {
            try? await sessionsAPI.deleteSession(id: sessionId)
        }
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

    /// Confirm and apply the pending rename. Sessions-backed chats also
    /// rename server-side (`PATCH /api/sessions/{id}`) and drop their
    /// first-message auto-title; Runs-backed chats are local-only.
    ///
    /// - Parameter context: The SwiftData `ModelContext` to save into.
    func confirmRename(context: ModelContext) async {
        let trimmed = renameChatName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Название чата не может быть пустым"
            return
        }
        guard let chat = pendingRename else { return }

        if let sessionId = chat.sessionId {
            do {
                _ = try await sessionsAPI.renameSession(id: sessionId, title: trimmed)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
            chat.hasAutoTitled = true
        }

        chat.title = trimmed
        try? context.save()

        renameChatName = ""
        pendingRename = nil
        isRenamingChat = false
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
