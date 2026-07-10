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
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.hkBorder, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
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
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .padding(.horizontal, Space.md)
                    }
                }
                .padding(.vertical, Space.sm)
            }
            .background(Color.hkPage)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.streamingContent) { _, _ in
                proxy.scrollTo("streaming", anchor: .bottom)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
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
        .background(Color.hkPage)
        .onAppear {
            viewModel.loadMessages(context: modelContext)
        }
    }

    private var emptyStateContent: some View {
        VStack(spacing: Space.md) {
            Spacer().frame(height: 120)
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(Color.hkNeutral)
                .frame(maxWidth: .infinity)
            Text("Start a conversation")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.hkMuted)
                .frame(maxWidth: .infinity)
            Text("Type a message below to begin chatting with Hermes.")
                .font(.system(size: 13))
                .foregroundStyle(Color.hkNeutral)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Space.xl)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private func sendMessage() {
        guard !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
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
        VStack(spacing: 0) {
            Rectangle().fill(Color.hkBorder).frame(height: 1)

            HStack(alignment: .bottom, spacing: Space.sm) {
                TextField("Message", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.hkInk)
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.sm)
                    .background(Color.hkSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.hkBorder, lineWidth: 1)
                    )
                    .focused($isFocused)
                    .onSubmit { onSend() }
                    .lineLimit(1...5)

                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.hkAccent)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .background(Color.hkAccentDim)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .background(
                        text.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color.hkSurface2 : Color.hkAccent
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
        }
        .background(Color.hkPanel)
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
                .font(.system(size: 12))
                .foregroundStyle(Color.hkMuted)
            if let progress = status.progress {
                Text(progress)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.hkMuted)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, Space.md)
    }
}
