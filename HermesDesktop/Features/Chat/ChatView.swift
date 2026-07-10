// MARK: - ChatView
//
// Primary chat screen — message list with streaming, input bar,
// agent status indicators, and auto-scroll.

import SwiftUI
import SwiftData

// MARK: - ChatView

struct ChatView: View {

    @State private var viewModel: ChatViewModel
    @Environment(\.modelContext) private var modelContext

    init(project: Project, runsAPI: RunsAPIProtocol) {
        _viewModel = State(initialValue: ChatViewModel(runsAPI: runsAPI, project: project))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.sm) {
                    if viewModel.messages.isEmpty && !viewModel.isStreaming {
                        emptyStateContent
                    } else {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }

                    if viewModel.isStreaming && !viewModel.streamingContent.isEmpty {
                        HStack {
                            StreamingText(
                                text: viewModel.streamingContent,
                                isActive: viewModel.isStreaming
                            )
                            .padding(.horizontal, Space.lg)
                            .padding(.vertical, Space.sm)
                            .background(Color.hkSurface2)
                            .clipShape(BubbleShape(isUser: false))
                            Spacer(minLength: 60)
                        }
                        .padding(.horizontal, Space.sm)
                        .id("streaming")
                    }

                    ForEach(viewModel.agentStatuses) { status in
                        AgentStatusRow(status: status)
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.hkCaption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, Space.md)
                    }
                }
                .padding(.vertical, Space.sm)
            }
            .background(Color.hkPaper)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.streamingContent) { _, _ in
                proxy.scrollTo("streaming", anchor: .bottom)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: viewModel.agentStatuses.count) { _, _ in
                if let lastStatus = viewModel.agentStatuses.last {
                    proxy.scrollTo(lastStatus.id, anchor: .bottom)
                }
            }
            .safeAreaInset(edge: .bottom) {
                InputBar(
                    text: $viewModel.inputText,
                    isStreaming: viewModel.isStreaming,
                    onSend: { sendMessage() },
                    onStop: { stopStreaming() }
                )
            }
        }
        .background(Color.hkPaper)
        .onAppear {
            viewModel.loadMessages(context: modelContext)
        }
    }

    // MARK: - Empty State

    private var emptyStateContent: some View {
        VStack(spacing: Space.md) {
            Spacer().frame(height: 120)
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(Color.hkNeutral)
                .frame(maxWidth: .infinity)
            Text("Start a conversation")
                .font(.hkTitle)
                .foregroundStyle(Color.hkMuted)
                .frame(maxWidth: .infinity)
            Text("Type a message below to begin chatting with Hermes.")
                .font(.hkBody)
                .foregroundStyle(Color.hkNeutral)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Space.xl)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
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

struct InputBar: View {

    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: Space.sm) {
            TextField("Message", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.hkBody)
                .foregroundStyle(Color.hkInk)
                .padding(.horizontal, Space.md)
                .padding(.vertical, Space.sm)
                .background(Color.hkSurface2)
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
        .onAppear { isFocused = true }
    }
}

// MARK: - AgentStatusRow

struct AgentStatusRow: View {

    let status: AgentStatus

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

#Preview("Chat View") {
    Text("ChatView — open in app with a configured project to test")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
}
