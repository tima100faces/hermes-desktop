import SwiftUI
import SwiftData
import Observation

// MARK: - ChatViewModel

/// ViewModel for the main chat interface.
///
/// Transport-agnostic: talks only to a `ConversationService`, which hides
/// whether the chat on screen is Runs API-backed (pinned, migrated from
/// the old `Topic` entity) or Sessions API-backed. Manages message
/// persistence and real-time agent status badges; all properties are
/// `@Observable`-driven so the SwiftUI view layer reacts automatically.
///
/// ## Responsibilities
/// - Sending user messages and consuming the unified `RunEvent` stream
/// - Persisting messages via the conversation service
/// - Tracking running/completed/failed agent statuses
/// - Partial-message capture on stop / new-message-while-streaming
@MainActor
@Observable
final class ChatViewModel {

    // MARK: - Published State

    /// All messages for the current conversation, in display order.
    var messages: [Message] = []

    /// The current text in the input field (bound to a TextEditor).
    var inputText: String = ""

    /// `true` while an agent run is actively streaming tokens.
    var isStreaming: Bool = false

    /// In-progress assistant content, updated on every `text_delta` event.
    /// The view displays this as a streaming bubble.
    var streamingContent: String = ""

    /// Status badges for subagents shown during a run.
    var agentStatuses: [AgentStatus] = []

    /// Non-nil when the last run produced an error.
    var errorMessage: String?

    // MARK: - Dependencies

    /// The chat this view model is driving, behind a shared interface.
    private let conversationService: ConversationService

    // MARK: - Initialization

    /// Creates a new `ChatViewModel` bound to a conversation.
    ///
    /// - Parameter conversationService: The Runs- or Sessions-backed
    ///   service driving this conversation.
    init(conversationService: ConversationService) {
        self.conversationService = conversationService
    }

    // MARK: - Load Messages

    /// Loads existing messages for the current conversation.
    ///
    /// - Parameter context: The SwiftData `ModelContext` to fetch/save with.
    func loadMessages(context: ModelContext) async {
        messages = await conversationService.loadMessages(context: context)
    }

    // MARK: - Send Message

    /// Sends a user message and begins streaming the assistant's response.
    ///
    /// This method:
    /// 1. Validates that `inputText` is non-empty.
    /// 2. If a run is already streaming, stops it first and saves any partial
    ///    content as an assistant message.
    /// 3. Creates a `Message` with role `.user` and persists it.
    /// 4. Calls `conversationService.send(input:)` to start the turn and
    ///    processes the resulting unified `RunEvent` stream.
    ///
    /// ## Event Handling
    /// | Event | Action |
    /// |---|---|
    /// | `.textDelta` | Append `content` to `streamingContent` |
    /// | `.toolCall` | Create an `AgentStatus(.running)` and append to `agentStatuses` |
    /// | `.toolResult` | Update matching `AgentStatus` to `.completed` with output |
    /// | `.runCompleted` | Persist `streamingContent` as an assistant message, clear state |
    /// | `.runFailed` | Set `errorMessage`, clear streaming state |
    ///
    /// - Parameter context: The SwiftData `ModelContext` for persistence.
    func sendMessage(context: ModelContext) async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // --- Cancel any in-flight run first ---
        if isStreaming {
            await conversationService.stop()
            savePartialContent(context: context)
            streamingContent = ""
            agentStatuses = []
            isStreaming = false
        }

        let text = inputText
        inputText = ""

        // --- Persist user message ---
        let userMsg = Message(content: text, role: .user)
        conversationService.persist(userMsg, context: context)
        messages.append(userMsg)

        if messages.count == 1 {
            await conversationService.autoTitleIfNeeded(from: text, context: context)
        }

        // --- Initialise streaming state ---
        isStreaming = true
        streamingContent = ""
        errorMessage = nil
        agentStatuses = []

        do {
            let stream = try await conversationService.send(input: text)

            for await event in stream {
                switch event.type {
                case .textDelta:
                    if let content = event.content {
                        streamingContent += content
                    }

                case .toolCall:
                    let status = AgentStatus(
                        id: event.id.uuidString,
                        name: event.toolName ?? "Tool",
                        state: .running,
                        progress: event.toolInput
                    )
                    agentStatuses.append(status)

                case .toolResult:
                    if let idx = agentStatuses.firstIndex(where: { $0.name == event.toolName }) {
                        agentStatuses[idx].state = .completed
                        agentStatuses[idx].progress = event.toolOutput
                    }

                case .runCompleted:
                    // Use streamingContent (built from deltas), or fall back to
                    // event.content (output field) if no incremental deltas arrived.
                    let finalContent = streamingContent.isEmpty
                        ? (event.content ?? "")
                        : streamingContent
                    let assistantMsg = Message(
                        content: finalContent,
                        role: .assistant,
                        runId: conversationService.currentTurnId
                    )
                    conversationService.persist(assistantMsg, context: context)
                    messages.append(assistantMsg)
                    streamingContent = ""
                    isStreaming = false
                    return

                case .runFailed:
                    errorMessage = event.error ?? "Run failed"
                    streamingContent = ""
                    isStreaming = false
                    return

                case .reasoningAvailable:
                    // Reasoning chunks: ignored for now, could show in UI later
                    break
                }
            }

            // Stream ended without a terminal event (e.g. server closed connection).
            // Save whatever we have as a partial message.
            if !streamingContent.isEmpty {
                let partialMsg = Message(
                    content: streamingContent,
                    role: .assistant,
                    runId: conversationService.currentTurnId
                )
                conversationService.persist(partialMsg, context: context)
                messages.append(partialMsg)
            }

            streamingContent = ""
            isStreaming = false

        } catch {
            errorMessage = error.localizedDescription
            streamingContent = ""
            isStreaming = false
        }
    }

    // MARK: - Stop Streaming

    /// Cancels the currently active run and saves any partial content.
    ///
    /// - Parameter context: The SwiftData `ModelContext` for persistence.
    func stopStreaming(context: ModelContext) {
        // Fire-and-forget the stop request. For Runs-backed chats this asks
        // the server to cancel the run; for Sessions-backed chats (no
        // server-side stop endpoint) this terminates the local stream so
        // no further events are read —
        // either way `sendMessage`'s `for await` loop ends shortly after.
        Task {
            await conversationService.stop()
        }

        savePartialContent(context: context)

        streamingContent = ""
        agentStatuses = []
        isStreaming = false
    }

    // MARK: - Helpers

    /// Persists the current `streamingContent` as a partial assistant message.
    private func savePartialContent(context: ModelContext) {
        guard !streamingContent.isEmpty else { return }
        let partialMsg = Message(content: streamingContent, role: .assistant)
        conversationService.persist(partialMsg, context: context)
        messages.append(partialMsg)
    }
}
