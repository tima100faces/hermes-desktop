import SwiftUI
import AppKit

// MARK: - MessageBubble
//
// Message anatomy (docs/UI-SPEC.md §3):
//   • User      → right-aligned Surface card with inset glow
//   • Assistant → flat markdown on the page background — NO bubble
//   • Tool      → centered italic caption
//
// Timestamps and actions live in a hover-revealed row under the message.
// The whole row (message + action row + gaps) is a single hover zone via
// .contentShape — without it, SwiftUI drops the hover in transparent
// gaps and the buttons vanish before the pointer reaches them.
// All text is selectable.

struct MessageBubble: View {
    let message: Message

    @State private var isHovering = false
    @State private var justCopied = false

    private var isUser: Bool { message.role == Message.Role.user.rawValue }
    private var isTool: Bool { message.role == Message.Role.tool.rawValue }

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: Space.xs) {
                messageContent

                if !isTool {
                    actionRow
                        .opacity(isHovering ? 1 : 0)
                }
            }
            .frame(maxWidth: 580, alignment: isUser ? .trailing : .leading)

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, Space.md)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var messageContent: some View {
        if isTool {
            Text(message.content)
                .font(.hkCaption)
                .foregroundStyle(Color.hkNeutral)
                .italic()
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .center)
        } else if isUser {
            Text(message.content)
                .font(.hkBody)
                .lineSpacing(LineSpacing.body)
                .foregroundStyle(Color.hkInk)
                .textSelection(.enabled)
                .padding(.horizontal, Space.md)
                .padding(.vertical, Space.sm + 2)
                .background(Color.hkSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.hkGlow, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            // Assistant: flat markdown, no bubble.
            MarkdownRenderer(text: message.content)
        }
    }

    // MARK: - Hover Action Row

    private var actionRow: some View {
        HStack(spacing: 2) {
            IconActionButton(
                systemName: justCopied ? "checkmark" : "doc.on.doc",
                help: "Copy"
            ) { copyMessage() }

            Text(message.timestamp, style: .time)
                .font(.hkCaption)
                .foregroundStyle(Color.hkNeutral)
                .padding(.leading, Space.xs)
        }
    }

    private func copyMessage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        justCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            justCopied = false
        }
    }
}

// MARK: - IconActionButton

/// Small 26×26 ghost icon button used in hover action rows.
/// Icon only — no text labels (docs/UI-SPEC.md §5).
struct IconActionButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .foregroundStyle(Color.hkNeutral)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .background(isHovering ? Color.hkHover : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { isHovering = $0 }
        .help(help)
    }
}
