import SwiftUI
import SwiftData
import Observation

// MARK: - ChatViewModel

/// ViewModel for the main chat interface.
///
/// Manages SSE streaming from the Hermes Runs API, message persistence via
/// SwiftData, and real-time agent status badges. All properties are
/// `@Observable`-driven so the SwiftUI view layer reacts automatically.
///
/// ## Responsibilities
/// - Sending user messages and creating agent runs
/// - Consuming the SSE event stream (`text_delta`, `tool_call`, etc.)
/// - Persisting messages via SwiftData (`ModelContext`)
/// - Tracking running/completed/failed agent statuses
/// - Partial-message capture on stop / new-message-while-streaming
@MainActor
@Observable
final class ChatViewModel {

    // MARK: - Published State

    /// All messages for the current project, in display order.
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

    /// The Hermes Runs API client (actor).
    private let runsAPI: RunsAPIProtocol

    /// The project this chat session belongs to.
    private let project: Project

    /// The ID of the currently active run (nil when idle).
    private var currentRunId: String?

    // MARK: - Initialization

    /// Creates a new `ChatViewModel` bound to a project.
    ///
    /// - Parameters:
    ///   - runsAPI: The `RunsAPIProtocol` actor used for create/stream/stop operations.
    ///   - project: The `Project` whose messages are managed.
    init(runsAPI: RunsAPIProtocol, project: Project) {
        self.runsAPI = runsAPI
        self.project = project
    }

    // MARK: - Load Messages

    /// Loads existing messages from SwiftData for the current project.
    ///
    /// Messages are fetched sorted by `timestamp` ascending (oldest first).
    ///
    /// - Parameter context: The SwiftData `ModelContext` to fetch from.
    func loadMessages(context: ModelContext) {
        let key = project.conversationKey
        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate { $0.project?.conversationKey == key },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        if let loaded = try? context.fetch(descriptor) {
            messages = loaded
        }
    }

    // MARK: - Send Message

    /// Sends a user message and begins streaming the assistant's response.
    ///
    /// This method:
    /// 1. Validates that `inputText` is non-empty.
    /// 2. If a run is already streaming, stops it first and saves any partial
    ///    content as an assistant message.
    /// 3. Creates a `Message` with role `.user` and persists it.
    /// 4. Calls `runsAPI.createRun(input:conversation:)` to start a new run.
    /// 5. Calls `runsAPI.streamEvents(runId:)` and processes each event.
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
        if isStreaming, let runId = currentRunId {
            try? await runsAPI.stopRun(runId: runId)
            savePartialContent(context: context)
            streamingContent = ""
            agentStatuses = []
            isStreaming = false
            currentRunId = nil
        }

        let text = inputText
        inputText = ""

        // --- Persist user message ---
        let userMsg = Message(content: text, role: .user)
        userMsg.project = project
        context.insert(userMsg)
        try? context.save()
        messages.append(userMsg)

        // --- Initialise streaming state ---
        isStreaming = true
        streamingContent = ""
        errorMessage = nil
        agentStatuses = []

        let conversation = project.conversationKey

        do {
            print("🔵 [HermesDesktop] Creating run: input=\"\(text.prefix(50))...\" conversation=\(conversation)")
            let response = try await runsAPI.createRun(input: text, conversation: conversation)
            currentRunId = response.runId
            print("🟢 [HermesDesktop] Run created: \(response.runId), status=\(response.status)")

            let stream = await runsAPI.streamEvents(runId: response.runId)
            print("🟡 [HermesDesktop] Streaming started for run \(response.runId)")

            for await event in stream {
                print("📥 [HermesDesktop] Event: type=\(event.type), content=\(event.content?.prefix(30) ?? "nil")")
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
                        runId: response.runId
                    )
                    assistantMsg.project = project
                    context.insert(assistantMsg)
                    try? context.save()
                    messages.append(assistantMsg)
                    streamingContent = ""
                    isStreaming = false
                    currentRunId = nil
                    return

                case .runFailed:
                    errorMessage = event.error ?? "Run failed"
                    streamingContent = ""
                    isStreaming = false
                    currentRunId = nil
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
                    runId: response.runId
                )
                partialMsg.project = project
                context.insert(partialMsg)
                try? context.save()
                messages.append(partialMsg)
            }

            streamingContent = ""
            isStreaming = false
            currentRunId = nil

        } catch {
            print("🔴 [HermesDesktop] Error: \(error)")
            errorMessage = error.localizedDescription
            streamingContent = ""
            isStreaming = false
            currentRunId = nil
        }
    }

    // MARK: - Stop Streaming

    /// Cancels the currently active run and saves any partial content.
    ///
    /// - Parameter context: The SwiftData `ModelContext` for persistence.
    func stopStreaming(context: ModelContext) {
        guard let runId = currentRunId else { return }

        // Fire-and-forget the stop request (we don't need to await the result
        // here — the server will close the SSE stream).
        Task {
            try? await runsAPI.stopRun(runId: runId)
        }

        savePartialContent(context: context)

        streamingContent = ""
        agentStatuses = []
        isStreaming = false
        currentRunId = nil
    }

    // MARK: - Helpers

    /// Persists the current `streamingContent` as a partial assistant message.
    private func savePartialContent(context: ModelContext) {
        guard !streamingContent.isEmpty else { return }
        let partialMsg = Message(content: streamingContent, role: .assistant)
        partialMsg.project = project
        context.insert(partialMsg)
        try? context.save()
        messages.append(partialMsg)
    }
}
