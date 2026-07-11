import XCTest
@testable import HermesDesktop

// MARK: - SendAwareTextViewTests
//
// Drives `SendAwareTextView.keyDown` directly with a synthesized `NSEvent`
// — the exact regression InputBar hit (2026-07-12): plain Enter must call
// `onPlainReturn` and swallow the keystroke (no newline inserted);
// Shift+Enter must always insert a newline, regardless of `onPlainReturn`.

@MainActor
final class SendAwareTextViewTests: XCTestCase {

    private func returnEvent(shift: Bool = false) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: shift ? [.shift] : [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        )!
    }

    // MARK: - InputBar's configuration (interceptsPlainReturn = true)

    func testPlainReturnCallsHandlerAndSwallowsTheKeystroke() {
        let textView = SendAwareTextView()
        var called = false
        textView.onPlainReturn = { called = true }
        textView.interceptsPlainReturn = true

        textView.keyDown(with: returnEvent())

        XCTAssertTrue(called, "plain Enter must call onPlainReturn")
        XCTAssertEqual(textView.string, "", "plain Enter must not insert a newline when interception is on")
    }

    func testShiftReturnInsertsNewlineAndDoesNotCallHandler() {
        let textView = SendAwareTextView()
        var called = false
        textView.onPlainReturn = { called = true }
        textView.interceptsPlainReturn = true

        textView.keyDown(with: returnEvent(shift: true))

        XCTAssertFalse(called, "Shift+Enter must not call onPlainReturn")
        XCTAssertEqual(textView.string, "\n", "Shift+Enter must insert a newline at the cursor")
    }

    // MARK: - ProjectView's instructions field configuration (interceptsPlainReturn = false, the default)

    func testPlainReturnWithInterceptionOffInsertsNewline() {
        let textView = SendAwareTextView()
        // interceptsPlainReturn defaults to false — matches the
        // instructions field, which still assigns a non-nil onPlainReturn
        // closure via GrowingTextEditor's wiring but must never swallow Enter.
        textView.onPlainReturn = { XCTFail("must not be called when interception is off") }

        textView.keyDown(with: returnEvent())

        XCTAssertEqual(textView.string, "\n", "without interception, plain Enter must behave like any other key")
    }

    func testShiftReturnWithInterceptionOffInsertsNewline() {
        let textView = SendAwareTextView()

        textView.keyDown(with: returnEvent(shift: true))

        XCTAssertEqual(textView.string, "\n")
    }

    // MARK: - Defensive: interception on but no handler assigned

    func testPlainReturnWithInterceptionOnButNoHandlerSwallowsWithoutCrashing() {
        let textView = SendAwareTextView()
        textView.interceptsPlainReturn = true
        // onPlainReturn intentionally left nil.

        textView.keyDown(with: returnEvent())

        XCTAssertEqual(textView.string, "", "still swallowed — interceptsPlainReturn is what gates this, not onPlainReturn's nil-ness")
    }
}
