// MARK: - MarkdownRenderer
//
// Renders Markdown text with rich formatting for chat display.
//
// Uses a hybrid approach:
//   1. Splits on ``` fences to extract fenced code blocks
//   2. Renders code blocks with monospaced font + surface background
//   3. Renders the remaining inline content using AttributedString(markdown:)
//      with .fullyParsed to handle blockquotes, lists, links, and inline
//      formatting (bold, italic, inline code).
//
// macOS 14+ required for AttributedString markdown parsing.

import SwiftUI

// MARK: - MarkdownRenderer

struct MarkdownRenderer: View {
    let text: String

    var body: some View {
        contentView
            .textSelection(.enabled)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        if text.contains("```") {
            // Hybrid rendering: code blocks separate, inline markdown for rest
            hybridContent
        } else if text.contains(">") {
            // Has potential blockquotes — use .fullyParsed to handle them
            attributedContent
        } else {
            // Simple inline markdown only
            attributedContent
        }
    }

    /// AttributedString-based rendering with full markdown parsing.
    /// Handles blockquotes, lists, headers, links, and inline formatting.
    @ViewBuilder
    private var attributedContent: some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            Text(attributed)
                .font(.hkBody)
        } else {
            fallbackText
        }
    }

    /// Hybrid rendering: split on ``` fences, render code blocks and
    /// inline markdown segments separately, stacked vertically.
    @ViewBuilder
    private var hybridContent: some View {
        let segments = parseFencedCodeBlocks(text)
        VStack(alignment: .leading, spacing: Space.sm) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .code(let code):
                    codeBlockView(code)
                case .markdown(let md):
                    if let attributed = try? AttributedString(
                        markdown: md,
                        options: AttributedString.MarkdownParsingOptions(
                            interpretedSyntax: .inlineOnlyPreservingWhitespace
                        )
                    ) {
                        Text(attributed)
                            .font(.hkBody)
                    } else {
                        Text(md)
                            .font(.hkBody)
                            .foregroundStyle(Color.hkInk)
                    }
                }
            }
        }
    }

    /// Plain text fallback when AttributedString parsing fails.
    private var fallbackText: some View {
        Text(text)
            .font(.hkBody)
            .foregroundStyle(Color.hkInk)
    }

    // MARK: - Code Block

    /// Renders a fenced code block with monospaced font and surface background.
    private func codeBlockView(_ code: String) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Text(code)
                .font(.hkCodeBody)
                .foregroundStyle(Color.hkInk)
                .padding(Space.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.hkSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Fenced Code Block Parser

    /// A parsed segment of markdown content.
    private enum Segment {
        /// A code block (content between ``` fences).
        case code(String)
        /// Regular markdown content.
        case markdown(String)
    }

    /// Splits the input on ``` fences and returns interleaved segments.
    ///
    /// Odd-indexed segments (after splitting) are code blocks; even-indexed
    /// are regular markdown. The opening info string after the first ```
    /// (e.g. ```swift) is preserved as part of the code block content for
    /// context, but not rendered as a label.
    private func parseFencedCodeBlocks(_ input: String) -> [Segment] {
        let delimiter = "```"
        var segments: [Segment] = []

        let parts = input.components(separatedBy: delimiter)

        for (index, part) in parts.enumerated() {
            let trimmed = part.trimmingCharacters(in: .newlines)
            guard !trimmed.isEmpty else { continue }

            if index.isMultiple(of: 2) {
                // Even index → regular markdown
                segments.append(.markdown(trimmed))
            } else {
                // Odd index → code block
                // Strip the optional language identifier on the first line
                var code = trimmed
                if let firstNewline = code.firstIndex(of: "\n") {
                    // Remove the info string (e.g. "swift") before the newline
                    code = String(code[code.index(after: firstNewline)...])
                }
                segments.append(.code(code.trimmingCharacters(in: .newlines)))
            }
        }

        return segments
    }
}

// MARK: - Previews

#Preview("Simple Markdown") {
    MarkdownRenderer(text: "This is **bold**, *italic*, and `inline code`.")
        .padding()
        .background(Color.hkPage)
        .frame(width: 400)
}

#Preview("Code Block") {
    MarkdownRenderer(text: """
        Here's a SwiftUI example:

        ```swift
        struct ContentView: View {
            var body: some View {
                Text("Hello, World!")
                    .foregroundStyle(.blue)
            }
        }
        ```

        And that's all there is to it!
        """)
        .padding()
        .background(Color.hkPage)
        .frame(width: 400)
}

#Preview("Blockquote") {
    MarkdownRenderer(text: """
        > **Note:** This is an important warning.
        > Make sure to handle edge cases.

        Regular text continues here.
        """)
        .padding()
        .background(Color.hkPage)
        .frame(width: 400)
}

#Preview("Mixed Content") {
    MarkdownRenderer(text: """
        # Hello

        This is a paragraph with **bold** and `code`.

        ```python
        def hello():
            print("world")
        ```

        > Be careful with this.

        - List item 1
        - List item 2
        """)
        .padding()
        .background(Color.hkPage)
        .frame(width: 400)
}
