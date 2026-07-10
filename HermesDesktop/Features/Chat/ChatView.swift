import SwiftUI
import SwiftData

// MARK: - ChatView

struct ChatView: View {

    @State private var viewModel: ChatViewModel
    @Environment(\.modelContext) private var modelContext

    /// Whether the bottom of the chat is currently in view — drives the
    /// "scroll to bottom" button. Tracked via a 1pt marker view at the end
    /// of the message list: LazyVStack only mounts children near the
    /// visible viewport, so its onAppear/onDisappear double as a cheap
    /// "am I scrolled to the bottom" signal without a scroll-offset API.
    @State private var isAtBottom = true

    /// Header title — the topic's or chat's display name.
    private let title: String

    init(title: String, conversationService: ConversationService) {
        self.title = title
        _viewModel = State(initialValue: ChatViewModel(conversationService: conversationService))
    }

    var body: some View {
        GeometryReader { geometry in
            chatBody(availableHeight: geometry.size.height)
        }
        .background(Color.hkPage)
        .task {
            await viewModel.loadMessages(context: modelContext)
        }
    }

    /// - Parameter availableHeight: The full chat pane height, used to
    ///   cap the input field's growth at half the pane (docs/UI-SPEC.md §6) —
    ///   matching Claude's desktop app rather than a fixed line count.
    @ViewBuilder
    private func chatBody(availableHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Space.md) {
                        // Empty topics open as a clean chat — no placeholder
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

                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                            .onAppear { isAtBottom = true }
                            .onDisappear { isAtBottom = false }
                    }
                    .padding(.vertical, Space.md)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .overlay(alignment: .bottomTrailing) {
                    if !isAtBottom {
                        ScrollToBottomButton {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                        // Trailing inset centers the button over the
                        // InputBar's send button (outer Space.md + card's
                        // inner Space.md, minus half the width difference
                        // between the two controls: 32pt vs 28pt).
                        .padding(.trailing, Space.md + Space.md - 2)
                        .padding(.bottom, Space.md)
                        .transition(.opacity.animation(.easeOut(duration: 0.12)))
                    }
                }
                .onChange(of: viewModel.isStreaming) { _, streaming in
                    if streaming { proxy.scrollTo("streaming", anchor: .bottom) }
                }
                .onChange(of: viewModel.streamingContent) { _, _ in
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    // A send flips isStreaming in the same synchronous pass
                    // as the message append, so this can race the isStreaming
                    // onChange below and win, leaving the scroll position on
                    // the just-sent bubble with the "thinking" dot off-screen
                    // beneath it. Prefer "streaming" while a run is active.
                    if viewModel.isStreaming {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    } else if let last = viewModel.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            InputBar(
                text: $viewModel.inputText,
                isStreaming: viewModel.isStreaming,
                maxHeight: availableHeight * 0.5,
                onSend: { sendMessage() },
                onStop: { stopStreaming() }
            )
        }
    }

    // MARK: - Header

    /// Topic title bar with a live subagent badge.
    private var header: some View {
        HStack {
            Text(title)
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

// MARK: - ScrollToBottomButton
//
// Floating circular button, bottom-trailing over the message list —
// shown only while scrolled away from the bottom (docs/UI-SPEC.md §3).

struct ScrollToBottomButton: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.hkNeutral)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .background(isHovering ? Color.hkHover : Color.hkSurface)
        .clipShape(Circle())
        .overlay(
            Circle().stroke(Color.hkGlowStrong, lineWidth: 1)
        )
        .onHover { isHovering = $0 }
        .help("Scroll to bottom")
    }
}

// MARK: - InputBar
//
// Single Surface card containing a growing text field (1 line up to
// half the chat pane's height) and the send/stop button
// (docs/UI-SPEC.md §6).
//   Enter        → send
//   Shift+Enter  → newline

struct InputBar: View {

    @Binding var text: String
    let isStreaming: Bool
    /// Half the chat pane's height — matches Claude's desktop app rather
    /// than a fixed line count.
    let maxHeight: CGFloat
    let onSend: () -> Void
    let onStop: () -> Void

    @State private var textHeight: CGFloat = GrowingTextEditor.singleLineHeight

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var editorMaxHeight: CGFloat {
        max(GrowingTextEditor.singleLineHeight, maxHeight)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Space.sm) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Message")
                        .font(.hkBody)
                        .foregroundStyle(Color.hkNeutral)
                        .allowsHitTesting(false)
                }
                GrowingTextEditor(
                    text: $text,
                    height: $textHeight,
                    minHeight: GrowingTextEditor.singleLineHeight,
                    maxHeight: editorMaxHeight,
                    onPlainReturn: {
                        guard !isStreaming, !isEmpty else { return }
                        onSend()
                    }
                )
            }
            .frame(height: textHeight)
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
