// MARK: - MessageBubble
//
// A chat bubble that displays a single Message with role-specific styling:
//   • User    → right-aligned, hkAccent background, white text
//   • Assistant → left-aligned, hkSurface2 background, hkInk text
//   • Tool   → centered, small italic text in hkMuted

import SwiftUI

struct MessageBubble: View {
    let message: Message

    private var isUser: Bool { message.role == Message.Role.user.rawValue }
    private var isAssistant: Bool { message.role == Message.Role.assistant.rawValue }
    private var isTool: Bool { message.role == Message.Role.tool.rawValue }

    var body: some View {
        HStack(alignment: .bottom, spacing: Space.sm) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: Space.xs) {
                if isTool {
                    toolBubble
                } else {
                    chatBubble
                }
                Text(message.timestamp, style: .time)
                    .font(.hkCaption)
                    .foregroundStyle(Color.hkMuted)
            }
            .frame(maxWidth: 560, alignment: isUser ? .trailing : .leading)

            if isAssistant { Spacer(minLength: 60) }
        }
        .padding(.horizontal, Space.sm)
    }

    // MARK: - Tool Bubble

    private var toolBubble: some View {
        Text(message.content)
            .font(.hkCaption)
            .foregroundStyle(Color.hkMuted)
            .italic()
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Chat Bubble

    private var chatBubble: some View {
        Text(message.content)
            .font(.hkBody)
            .foregroundStyle(isUser ? .white : Color.hkInk)
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm)
            .background(isUser ? Color.hkAccent : Color.hkSurface2)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
