import SwiftUI
import SwiftData

// MARK: - ChatView

struct ChatView: View {

    @State private var viewModel: ChatViewModel
    @Environment(\.modelContext) private var modelContext

    private let project: Project

    init(project: Project, runsAPI: RunsAPIProtocol) {
        self.project = project
        _viewModel = State(initialValue: ChatViewModel(runsAPI: runsAPI, project: project))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Space.md) {
                        // Empty projects open as a clean chat — no placeholder
                        // content by design (docs/UI-SPEC.md §3).
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        // "Thinking" — run is active but no tokens arrived yet.
                        if viewModel.isStreaming && viewModel.streamingContent.isEmpty {
                            HStack {
                                ThinkingIndicator()
                                Spacer(minLength: 60)
                            }
                            .padding(.horizontal, Space.md)
                            .id("streaming")
                        }

                        // Streaming assistant content — flat, no bubble,
                        // matching the final assistant message style.
                        if viewModel.isStreaming && !viewModel.streamingContent.isEmpty {
                            HStack(alignment: .top, spacing: Space.sm) {
                                StreamingText(
                                    text: viewModel.streamingContent,
                                    isActive: viewModel.isStreaming
                                )
                                .frame(maxWidth: 580, alignment: .leading)
                                Spacer(minLength: 60)
                            }
                            .padding(.horizontal, Space.md)
                            .id("streaming")
                        }

                        ForEach(viewModel.agentStatuses) { status in
                            AgentStatusRow(status: status)
                        }

                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.hkCaption)
                                .foregroundStyle(Color.hkError)
                                .textSelection(.enabled)
                                .padding(.horizontal, Space.md)
                        }
                    }
                    .padding(.vertical, Space.md)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.isStreaming) { _, streaming in
                    if streaming { proxy.scrollTo("streaming", anchor: .bottom) }
                }
                .onChange(of: viewModel.streamingContent) { _, _ in
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let last = viewModel.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            InputBar(
                text: $viewModel.inputText,
                isStreaming: viewModel.isStreaming,
                onSend: { sendMessage() },
                onStop: { stopStreaming() }
            )
        }
        .background(Color.hkPage)
        .onAppear {
            viewModel.loadMessages(context: modelContext)
        }
    }

    // MARK: - Header

    /// Project title bar with a live subagent badge.
    private var header: some View {
        HStack {
            Text(project.name)
                .font(.hkBody.weight(.medium))
                .foregroundStyle(Color.hkInk)
                .lineLimit(1)

            Spacer()

            if runningAgentCount > 0 {
                Text("\(runningAgentCount) subagent\(runningAgentCount == 1 ? "" : "s")")
                    .font(.hkCaption)
                    .foregroundStyle(Color.hkAccent2)
                    .padding(.horizontal, Space.sm + 2)
                    .padding(.vertical, 2)
                    .background(Color.hkAccentDim)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.top, Space.md)
        .padding(.bottom, Space.sm + 2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    private var runningAgentCount: Int {
        viewModel.agentStatuses.filter { $0.state == .running }.count
    }

    private func sendMessage() {
        guard !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task { await viewModel.sendMessage(context: modelContext) }
    }

    private func stopStreaming() {
        Task { viewModel.stopStreaming(context: modelContext) }
    }
}

// MARK: - ThinkingIndicator
//
// Pulsing rust dot shown while a run is active but no tokens have
// arrived yet — the agent is "thinking" (docs/UI-SPEC.md §3).
//
// NOTE: repeatForever animations must be started via withAnimation
// inside .task — the onAppear + .animation(value:) pattern silently
// fails to start when the state flips during view insertion.

struct ThinkingIndicator: View {

    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Color.hkAccent2)
            .frame(width: 10, height: 10)
            .scaleEffect(pulsing ? 1.25 : 0.75)
            .opacity(pulsing ? 0.45 : 1.0)
            .frame(width: 20, height: 20)
            .padding(.vertical, Space.xs)
            .task {
                withAnimation(
                    .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                ) {
                    pulsing = true
                }
            }
    }
}

// MARK: - InputBar
//
// Single Surface card containing a growing text field (1–8 lines) and
// the send/stop button (docs/UI-SPEC.md §6).
//   Enter        → send
//   Shift+Enter  → newline

struct InputBar: View {

    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    @FocusState private var isFocused: Bool

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Space.sm) {
            TextField("Message", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.hkBody)
                .lineSpacing(LineSpacing.body)
                .foregroundStyle(Color.hkInk)
                .lineLimit(1...8)
                .focused($isFocused)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) {
                        // Shift+Enter → newline. Appends at the end of the
                        // text; cursor-position-aware insertion is a known
                        // limitation (see UI-SPEC.md §6).
                        text += "\n"
                        return .handled
                    }
                    guard !isStreaming, !isEmpty else { return .handled }
                    onSend()
                    return .handled
                }
                .padding(.vertical, 6)

            if isStreaming {
                controlButton(
                    icon: "stop.fill",
                    background: Color.hkAccentDim,
                    foreground: Color.hkAccent2,
                    action: onStop
                )
                .help("Stop")
            } else {
                controlButton(
                    icon: "arrow.up",
                    background: isEmpty ? Color.hkSurface2 : Color.hkAccent,
                    foreground: .white,
                    action: onSend
                )
                .disabled(isEmpty)
                .help("Send")
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(Color.hkSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.hkGlowStrong, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, Space.md)
        .padding(.top, Space.xs)
        .padding(.bottom, Space.md)
        .background(Color.hkPage)
        .onAppear { isFocused = true }
    }

    private func controlButton(
        icon: String,
        background: Color,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - AgentStatusRow
//
// Subagent status rendered as a Surface card in the chat flow
// (docs/UI-SPEC.md §7).

struct AgentStatusRow: View {
    let status: AgentStatus

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                if status.state == .running {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.hkAccent2)
                } else {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.hkSuccess)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(status.name)
                        .font(.hkBody.weight(.medium))
                        .foregroundStyle(Color.hkInk)
                        .lineLimit(1)
                    if let progress = status.progress, !progress.isEmpty {
                        Text(progress)
                            .font(.hkCaption)
                            .foregroundStyle(Color.hkNeutral)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm + 2)
            .background(Color.hkSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.hkGlow, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Spacer(minLength: 60)
        }
        .padding(.horizontal, Space.md)
    }
}
