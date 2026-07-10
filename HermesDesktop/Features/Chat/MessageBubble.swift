import SwiftUI

// MARK: - MessageBubble

struct MessageBubble: View {
    let message: Message

    private var isUser: Bool { message.role == Message.Role.user.rawValue }
    private var isTool: Bool { message.role == Message.Role.tool.rawValue }

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: Space.xs) {
                if isTool {
                    Text(message.content)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.hkNeutral)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if isUser {
                    Text(message.content)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Space.lg)
                        .padding(.vertical, Space.sm)
                        .background(Color.hkAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    Text(message.content)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.hkInk)
                        .padding(.horizontal, Space.lg)
                        .padding(.vertical, Space.sm)
                        .background(Color.hkSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.hkGlow, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Text(message.timestamp, style: .time)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.hkNeutral)
            }
            .frame(maxWidth: 580, alignment: isUser ? .trailing : .leading)

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, Space.sm)
    }
}
