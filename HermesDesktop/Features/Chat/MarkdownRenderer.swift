// MARK: - MarkdownRenderer
//
// Renders Markdown text with rich formatting for chat display.
//
// Uses a hybrid approach:
//   1. Splits on ``` fences to extract fenced code blocks
//   2. Renders code blocks via CodeBlockView (language chip + copy button)
//   3. Renders the remaining inline content using AttributedString(markdown:)
//
// All text is selectable. macOS 14+ required.

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
            hybridContent
        } else {
            attributedContent
        }
    }

    /// AttributedString-based rendering with inline markdown parsing.
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
                .lineSpacing(LineSpacing.body)
                .foregroundStyle(Color.hkInk)
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
                case .code(let language, let body):
                    CodeBlockView(language: language, code: body)
                case .markdown(let md):
                    if let attributed = try? AttributedString(
                        markdown: md,
                        options: AttributedString.MarkdownParsingOptions(
                            interpretedSyntax: .inlineOnlyPreservingWhitespace
                        )
                    ) {
                        Text(attributed)
                            .font(.hkBody)
                            .lineSpacing(LineSpacing.body)
                            .foregroundStyle(Color.hkInk)
                    } else {
                        Text(md)
                            .font(.hkBody)
                            .lineSpacing(LineSpacing.body)
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
            .lineSpacing(LineSpacing.body)
            .foregroundStyle(Color.hkInk)
    }

    // MARK: - Fenced Code Block Parser

    /// A parsed segment of markdown content.
    private enum Segment {
        /// A code block with an optional language identifier.
        case code(language: String?, body: String)
        /// Regular markdown content.
        case markdown(String)
    }

    /// Splits the input on ``` fences and returns interleaved segments.
    ///
    /// Odd-indexed parts (after splitting) are code blocks; even-indexed
    /// are regular markdown. The info string after the opening fence
    /// (e.g. ```swift) is extracted as the language label.
    private func parseFencedCodeBlocks(_ input: String) -> [Segment] {
        let delimiter = "```"
        var segments: [Segment] = []

        let parts = input.components(separatedBy: delimiter)

        for (index, part) in parts.enumerated() {
            if index.isMultiple(of: 2) {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                segments.append(.markdown(trimmed))
            } else {
                var language: String? = nil
                var code = part
                if let firstNewline = code.firstIndex(of: "\n") {
                    let info = String(code[..<firstNewline])
                        .trimmingCharacters(in: .whitespaces)
                    if !info.isEmpty { language = info }
                    code = String(code[code.index(after: firstNewline)...])
                }
                let body = code.trimmingCharacters(in: .newlines)
                guard !body.isEmpty else { continue }
                segments.append(.code(language: language, body: body))
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
            }
        }
        ```

        And that's all there is to it!
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

        - List item 1
        - List item 2
        """)
        .padding()
        .background(Color.hkPage)
        .frame(width: 400)
}
