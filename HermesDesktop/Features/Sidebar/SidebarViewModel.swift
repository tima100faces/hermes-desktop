import SwiftUI
import SwiftData
import Observation

// MARK: - SidebarViewModel

/// ViewModel for the sidebar topic list.
///
/// Manages topic selection, creation, and deletion.
/// Runs on `@MainActor` so it can safely drive SwiftUI state.
@MainActor
@Observable
final class SidebarViewModel {

    // MARK: Published State

    /// Whether the "Create Topic" sheet is presented.
    var isCreatingTopic = false

    /// Text binding for the new-topic name text field.
    var newTopicName = ""

    /// Non-nil when an error should be displayed.
    var errorMessage: String?

    /// Whether the delete confirmation alert is shown.
    var showDeleteConfirmation = false

    /// The topic pending confirmation before deletion.
    private var pendingDeletion: Topic?

    /// Whether the "Rename Topic" sheet is presented.
    var isRenamingTopic = false

    /// Text binding for the rename text field.
    var renameTopicName = ""

    /// The topic pending a rename.
    private var pendingRename: Topic?

    // MARK: - Intent(s)

    /// Create a new topic from the current `newTopicName` and select it.
    ///
    /// - Parameters:
    ///   - context: The SwiftData `ModelContext` to insert into.
    ///   - selection: The app's active-conversation state — set to the
    ///     newly created topic on success.
    func createTopic(context: ModelContext, selection: inout ConversationSelection?) {
        let trimmed = newTopicName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Название темы не может быть пустым"
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

        let topic = Topic(name: trimmed, conversationKey: key)
        context.insert(topic)
        try? context.save()

        newTopicName = ""
        isCreatingTopic = false
        selection = .topic(topic)
    }

    /// Request deletion — shows confirmation alert first.
    ///
    /// - Parameter topic: The topic to delete.
    func requestDelete(_ topic: Topic) {
        pendingDeletion = topic
        showDeleteConfirmation = true
    }

    /// Confirm and execute the pending deletion.
    ///
    /// - Parameters:
    ///   - context: The SwiftData `ModelContext` to delete from.
    ///   - selection: The app's active-conversation state — cleared if it
    ///     pointed at the deleted topic.
    func confirmDelete(context: ModelContext, selection: inout ConversationSelection?) {
        guard let topic = pendingDeletion else { return }
        context.delete(topic)
        try? context.save()
        if case .topic(let selected) = selection, selected == topic {
            selection = nil
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
    /// topic's current name.
    ///
    /// - Parameter topic: The topic to rename.
    func requestRename(_ topic: Topic) {
        pendingRename = topic
        renameTopicName = topic.name
        errorMessage = nil
        isRenamingTopic = true
    }

    /// Confirm and apply the pending rename.
    ///
    /// - Parameter context: The SwiftData `ModelContext` to save into.
    func confirmRename(context: ModelContext) {
        let trimmed = renameTopicName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Название темы не может быть пустым"
            return
        }
        pendingRename?.name = trimmed
        try? context.save()

        renameTopicName = ""
        pendingRename = nil
        isRenamingTopic = false
    }

    /// Cancel the pending rename.
    func cancelRename() {
        pendingRename = nil
        renameTopicName = ""
        isRenamingTopic = false
    }

    /// Dismiss the current error.
    func clearError() {
        errorMessage = nil
    }
}
