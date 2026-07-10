// MARK: - StreamingText
//
// Animated text view that displays tokens as they arrive from SSE streaming.
//
// Shows the streaming content via MarkdownRenderer with a blinking cursor
// appended while `isActive` is true. The cursor is a 2 pt-wide accent-colored
// vertical bar that fades in/out in a continuous loop using PhaseAnimator
// (macOS 14+ / iOS 17+).
//
// When `isActive` transitions to false, the cursor fades out and disappears.

import SwiftUI

// MARK: - StreamingText

struct StreamingText: View {
    /// The text content received so far (incremental updates).
    let text: String

    /// Whether the stream is still active (cursor visible).
    let isActive: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            MarkdownRenderer(text: text)

            if isActive {
                cursorView
            }
        }
    }

    // MARK: - Cursor

    /// A blinking vertical bar cursor that loops opacity 0 → 1 → 0.
    @ViewBuilder
    private var cursorView: some View {
        PhaseAnimator([0.0, 1.0], trigger: isActive) { phase in
            Rectangle()
                .fill(Color.hkAccent)
                .frame(width: 2, height: 16)
                .opacity(phase)
                .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
        } animation: { _ in
            .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
        }
    }
}

// MARK: - Previews

#Preview("Streaming Active") {
    StreamingText(
        text: "I'm generating a response for you. ",
        isActive: true
    )
    .padding()
    .background(Color.hkPage)
    .frame(width: 400)
}

#Preview("Streaming Complete") {
    StreamingText(
        text: "I'm generating a response for you. Here is the complete answer with **formatting** and `code`.",
        isActive: false
    )
    .padding()
    .background(Color.hkPage)
    .frame(width: 400)
}

#Preview("Long Streaming Content") {
    ScrollView {
        StreamingText(
            text: """
            Here's a detailed explanation of how the algorithm works:

            ```python
            def fibonacci(n: int) -> int:
                if n <= 1:
                    return n
                return fibonacci(n - 1) + fibonacci(n - 2)
            ```

            This is a recursive implementation. Note that it has **O(2^n)** time complexity, so for large values of `n` you'd want to use an iterative or memoized approach instead.
            """,
            isActive: true
        )
    }
    .padding()
    .background(Color.hkPage)
    .frame(width: 400, height: 300)
}
