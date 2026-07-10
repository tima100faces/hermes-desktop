import SwiftUI
import AppKit

// MARK: - GrowingTextEditor
//
// NSTextView-backed replacement for SwiftUI's TextField(axis: .vertical)
// in InputBar. TextField always inserts Shift+Enter's newline at the end
// of the text rather than at the cursor — a SwiftUI limitation
// (docs/UI-SPEC.md §6). NSTextView inserts at the cursor natively, so
// Enter/Shift+Enter is intercepted at the AppKit level instead: plain
// Enter is swallowed and reported via `onPlainReturn`, Shift+Enter falls
// through to the normal insertNewline behavior.
//
// Growth (1–8 lines) isn't automatic like TextField's `.lineLimit` — the
// coordinator measures the laid-out text on every change and reports it
// back through the `height` binding, which the caller applies via
// `.frame(height:)`.

struct GrowingTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    /// Called on plain Enter (no Shift) — Shift+Enter inserts a newline
    /// at the cursor instead and does not call this.
    let onPlainReturn: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = SendAwareTextView()
        textView.delegate = context.coordinator
        textView.onPlainReturn = { context.coordinator.parent.onPlainReturn() }

        textView.isRichText = false
        textView.font = Self.font
        textView.textColor = NSColor(Color.hkInk)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.string = text

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = LineSpacing.body
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes[.paragraphStyle] = paragraphStyle

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        context.coordinator.textView = textView

        // Auto-focus, matching the old TextField's `.onAppear { isFocused = true }`.
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.recalculateHeight()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    fileprivate static let font = NSFont.systemFont(ofSize: 13, weight: .regular)

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextEditor
        weak var textView: NSTextView?

        init(_ parent: GrowingTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            recalculateHeight()
        }

        func recalculateHeight() {
            guard let textView, let layoutManager = textView.layoutManager,
                  let container = textView.textContainer else { return }
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container).height
            let newHeight = min(max(used, parent.minHeight), parent.maxHeight)
            if abs(newHeight - parent.height) > 0.5 {
                parent.height = newHeight
            }
        }
    }
}

// MARK: - SendAwareTextView

/// Intercepts plain Enter to report it via `onPlainReturn` instead of
/// inserting a newline. Shift+Enter is left untouched, so AppKit inserts
/// the newline at the current cursor position as usual.
private final class SendAwareTextView: NSTextView {
    var onPlainReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 36 /* Return */, !event.modifierFlags.contains(.shift) else {
            super.keyDown(with: event)
            return
        }
        onPlainReturn?()
    }
}

// MARK: - Line Height Helpers

extension GrowingTextEditor {
    /// The height of a single line at the editor's font, including the
    /// design system's body line-spacing — used by callers to size the
    /// `minHeight`/`maxHeight` bounds (1–8 lines).
    static var singleLineHeight: CGFloat {
        NSLayoutManager().defaultLineHeight(for: font) + LineSpacing.body
    }
}
