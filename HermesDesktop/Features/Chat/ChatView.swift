// MARK: - ChatView
//
// Primary chat screen — message list with streaming, input bar,
// agent status indicators, and auto-scroll.

import SwiftUI
import SwiftData

// MARK: - ChatView

/// Main chat screen for conversing with Hermes.
///
/// Displays a scrollable message list (``MessageBubble`` for sent/received
/// messages, ``StreamingText`` for in-flight agent responses), inline agent
/// status indicators, error messages, and a bottom input bar.
struct ChatView: View {

    // MARK: Properties

    @State private var viewModel: ChatViewModel
    @Environment(\.modelContext) private var modelContext

    // MARK: Initializer

    init(project: Project, runsAPI: RunsAPIProtocol) {
        _viewModel = State(initialValue: ChatViewModel(runsAPI: runsAPI, project: project))
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            // Empty state when there are no messages and nothing is streaming.
            if viewModel.messages.isEmpty
                && !viewModel.isStreaming
                && viewModel.agentStatuses.isEmpty
                && viewModel.errorMessage == nil
            {
                emptyState
            } else {
                messageList
            }
        }
        .background(Color.hkPaper)
        .onAppear {
            viewModel.loadMessages(context: modelContext)
        }
    }

    // MARK: - Empty State

    /// Placeholder shown when the conversation has no messages yet.
    private var emptyState: some View {
        VStack(spacing: Space.md) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(Color.hkNeutral)

            Text("Start a conversation")
                .font(.hkTitle)
                .foregroundStyle(Color.hkMuted)

            Text("Type a message below to begin chatting with Hermes.")
                .font(.hkBody)
                .foregroundStyle(Color.hkNeutral)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.xl)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            inputBarOverlay
        }
    }

    // MARK: - Message List

    /// Scrollable list of messages with streaming content and agent indicators.
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.sm) {
                    // Existing messages
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    // Streaming content
                    if viewModel.isStreaming && !viewModel.streamingContent.isEmpty {
                        HStack {
                            StreamingText(
                                text: viewModel.streamingContent,
                                isActive: viewModel.isStreaming
                            )
                            .padding(.horizontal, Space.md)
                            .padding(.vertical, Space.sm)
                            .background(Color.hkSurface)
                            .clipShape(BubbleShape(isUser: false))
                            Spacer(minLength: 60)
                        }
                        .padding(.horizontal, Space.sm)
                        .id("streaming")
                    }

                    // Agent statuses
                    ForEach(viewModel.agentStatuses) { status in
                        AgentStatusRow(status: status)
                    }

                    // Error
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.hkCaption)
                            .foregroundStyle(Color.red)
                            .padding(.horizontal, Space.md)
                    }
                }
                .padding(.vertical, Space.sm)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.hkPaper)
            .onChange(of: viewModel.streamingContent) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.agentStatuses.count) { _, _ in
                if let lastStatus = viewModel.agentStatuses.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(lastStatus.id, anchor: .bottom)
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            inputBarOverlay
        }
    }

    // MARK: - Input Bar Overlay

    /// Shared input bar attached to the bottom of the view.
    @ViewBuilder
    private var inputBarOverlay: some View {
        InputBar(
            text: $viewModel.inputText,
            isStreaming: viewModel.isStreaming,
            onSend: { sendMessage() },
            onStop: { stopStreaming() }
        )
    }

    // MARK: - Actions

    private func sendMessage() {
        guard !viewModel.inputText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else { return }

        Task { await viewModel.sendMessage(context: modelContext) }
    }

    private func stopStreaming() {
        Task { viewModel.stopStreaming(context: modelContext) }
    }
}

// MARK: - InputBar

/// Bottom input bar with a vertically-expanding text field and send / stop button.
///
/// - Enter sends the message.
/// - Shift+Enter inserts a newline.
/// - The text field expands from 1 to 5 lines as content grows.
/// - Focus is automatically set on appear.
struct InputBar: View {

    // MARK: Properties

    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    @FocusState private var isFocused: Bool

    // MARK: Body

    var body: some View {
        HStack(alignment: .bottom, spacing: Space.sm) {
            TextField("Message", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.hkBody)
                .padding(.horizontal, Space.md)
                .padding(.vertical, Space.sm)
                .background(Color.hkSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .focused($isFocused)
                .onSubmit { onSend() }
                .lineLimit(1...5)
                .submitLabel(.send)

            if isStreaming {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.title3)
                        .foregroundStyle(Color.hkAccent)
                }
                .buttonStyle(.plain)
                .help("Stop streaming")
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            text.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Color.hkNeutral
                                : Color.hkAccent
                        )
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("Send message")
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(Color.hkPaper2)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.hkRule)
                .frame(height: 1)
        }
        .onAppear {
            isFocused = true
        }
    }
}

// MARK: - AgentStatusRow

/// Small inline indicator showing a sub-agent's name and lifecycle state.
///
/// Displays a coloured dot (accent when running, muted otherwise) alongside
/// the agent name and an optional progress message.
struct AgentStatusRow: View {

    // MARK: Properties

    let status: AgentStatus

    // MARK: Body

    var body: some View {
        HStack(spacing: Space.xs) {
            Circle()
                .fill(status.state == .running ? Color.hkAccent : Color.hkMuted)
                .frame(width: 8, height: 8)

            Text(status.name)
                .font(.hkCaption)
                .foregroundStyle(Color.hkMuted)

            if let progress = status.progress {
                Text(progress)
                    .font(.hkCaption)
                    .foregroundStyle(Color.hkMuted)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, Space.md)
    }
}

// MARK: - Preview

#Preview("Chat View") {
    Text("ChatView — open in app with a configured project to test")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
}
