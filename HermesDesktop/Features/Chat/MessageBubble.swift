// MARK: - MessageBubble
//
// A chat bubble that displays a single Message with role-specific styling:
//   • User    → right-aligned, hkAccent background, white text
//   • Assistant → left-aligned, hkSurface background, hkInk text
//   • Tool   → centered, small italic text in hkMuted
//
// Timestamp is shown below the bubble in hkMuted / hkCaption.
// BubbleShape provides asymmetric corner rounding (iMessage style).

import SwiftUI

// MARK: - MessageBubble

struct MessageBubble: View {
    let message: Message

    private var isUser: Bool {
        message.role == Message.Role.user.rawValue
    }

    private var isAssistant: Bool {
        message.role == Message.Role.assistant.rawValue
    }

    private var isTool: Bool {
        message.role == Message.Role.tool.rawValue
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Space.sm) {
            if isUser {
                Spacer(minLength: 60)
            }

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
            .frame(maxWidth: 420, alignment: isUser ? .trailing : .leading)

            if isAssistant {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal, Space.sm)
    }

    // MARK: - Tool Bubble

    @ViewBuilder
    private var toolBubble: some View {
        Text(message.content)
            .font(.hkCaption)
            .foregroundStyle(Color.hkMuted)
            .italic()
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Chat Bubble (User / Assistant)

    @ViewBuilder
    private var chatBubble: some View {
        Text(message.content)
            .font(.hkBody)
            .foregroundStyle(isUser ? .white : Color.hkInk)
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .background(isUser ? Color.hkAccent : Color.hkSurface)
            .clipShape(BubbleShape(isUser: isUser))
    }
}

// MARK: - BubbleShape

/// Asymmetric rounded-corner shape matching iMessage bubble style.
///
/// - User bubbles: rounded on all corners **except** the bottom-right,
///   which is left straight (the "tail" corner closest to the edge).
/// - Assistant bubbles: rounded on all corners **except** the bottom-left.
struct BubbleShape: Shape {
    let isUser: Bool

    /// Corner radius applied to the rounded corners.
    private let radius: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let r = min(radius, rect.width / 2, rect.height / 2)

        // Determine which corner is the "straight" (tail) corner.
        // User → bottom-right is straight. Assistant → bottom-left is straight.
        let straightBottomLeft  = !isUser
        let straightBottomRight = isUser

        // Top-left corner
        if straightBottomLeft {
            // Bottom-left is straight, so the left edge runs straight down.
            // Top-left still gets its rounding.
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addArc(
                center: CGPoint(x: rect.minX + r, y: rect.minY + r),
                radius: r,
                startAngle: Angle(degrees: 180),
                endAngle: Angle(degrees: 270),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        } else {
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.minX + r, y: rect.minY + r),
                radius: r,
                startAngle: Angle(degrees: 180),
                endAngle: Angle(degrees: 270),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }

        // Bottom-left corner
        if straightBottomLeft {
            // Straight (right angle)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
            path.addArc(
                center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                radius: r,
                startAngle: Angle(degrees: 90),
                endAngle: Angle(degrees: 180),
                clockwise: false
            )
        }

        // Bottom-right corner
        if straightBottomRight {
            // Straight (right angle) — just draw the bottom edge
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
            path.addArc(
                center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                radius: r,
                startAngle: Angle(degrees: 0),
                endAngle: Angle(degrees: 90),
                clockwise: false
            )
        }

        // Top-right corner
        if straightBottomRight {
            // Bottom-right is straight, so right edge runs straight up.
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r))
            path.addArc(
                center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                radius: r,
                startAngle: Angle(degrees: 270),
                endAngle: Angle(degrees: 360),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addArc(
                center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                radius: r,
                startAngle: Angle(degrees: 270),
                endAngle: Angle(degrees: 360),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r))
            path.addArc(
                center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                radius: r,
                startAngle: Angle(degrees: 0),
                endAngle: Angle(degrees: 90),
                clockwise: false
            )
        }

        path.closeSubpath()
        return path
    }
}

// MARK: - Previews

#Preview("User Message") {
    let msg = Message(content: "Hello! Can you help me with SwiftUI?", role: .user)
    MessageBubble(message: msg)
        .padding()
        .background(Color.hkPaper)
        .frame(width: 480)
}

#Preview("Assistant Message") {
    let msg = Message(content: "Of course! I'd be happy to help you with SwiftUI. What would you like to know?", role: .assistant)
    MessageBubble(message: msg)
        .padding()
        .background(Color.hkPaper)
        .frame(width: 480)
}

#Preview("Tool Message") {
    let msg = Message(content: "Used 1,024 tokens · completed in 2.3s", role: .tool)
    MessageBubble(message: msg)
        .padding()
        .background(Color.hkPaper)
        .frame(width: 480)
}

#Preview("Message Conversation") {
    VStack(spacing: Space.sm) {
        MessageBubble(message: Message(content: "What's the capital of France?", role: .user))
        MessageBubble(message: Message(content: "The capital of France is **Paris**. It has been the capital since the 10th century and is one of the world's major cultural and economic centers.", role: .assistant))
        MessageBubble(message: Message(content: "Completed in 1.8s", role: .tool))
    }
    .padding()
    .background(Color.hkPaper)
    .frame(width: 480)
}
