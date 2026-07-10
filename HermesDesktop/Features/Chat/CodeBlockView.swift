import SwiftUI
import AppKit

// MARK: - CodeBlockView
//
// Fenced code block (docs/UI-SPEC.md §4):
//   header strip → language chip (left) + copy icon (right)
//   body         → SF Mono on hkCodeBg (darker than the page)
//   elevation    → 1px inset glow, radius 8, no drop shadows

struct CodeBlockView: View {
    let language: String?
    let code: String

    @State private var justCopied = false
    @State private var isHoveringCopy = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.hkCodeBody)
                    .lineSpacing(LineSpacing.body)
                    .foregroundStyle(Color.hkMuted)
                    .textSelection(.enabled)
                    .padding(Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.hkCodeBg)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.hkGlow, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(language ?? "code")
                .font(.hkCodeCaption)
                .foregroundStyle(Color.hkNeutral)

            Spacer()

            Button(action: copyCode) {
                Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.hkNeutral)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .background(isHoveringCopy ? Color.hkHover : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .onHover { isHoveringCopy = $0 }
            .help("Copy code")
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.xs)
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        justCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            justCopied = false
        }
    }
}

// MARK: - Previews

#Preview("Python") {
    CodeBlockView(
        language: "python",
        code: "radius = max(0, corner_r - thickness)\npath.arc_to(x, y, radius)"
    )
    .padding()
    .background(Color.hkPage)
    .frame(width: 480)
}

#Preview("No language") {
    CodeBlockView(language: nil, code: "make build && make run")
        .padding()
        .background(Color.hkPage)
        .frame(width: 480)
}
