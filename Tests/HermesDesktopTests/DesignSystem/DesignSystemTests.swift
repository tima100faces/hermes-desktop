import XCTest
import SwiftUI
@testable import HermesDesktop

// MARK: - DesignSystemTests

final class DesignSystemTests: XCTestCase {

    // MARK: - Oklch → Color

    func testOklchToColorProducesValidColor() {
        let color = Color.hkPaper
        // The color should not be a clear/empty color — extract components
        // to verify it resolved to something.
        let resolved = color.resolve(in: .init())
        XCTAssertGreaterThan(resolved.red, 0)
        XCTAssertGreaterThanOrEqual(resolved.green, 0)
        XCTAssertGreaterThanOrEqual(resolved.blue, 0)
    }

    func testAccentColor() {
        let paper = Color.hkPaper
        let accent = Color.hkAccent

        let resolvedPaper = paper.resolve(in: .init())
        let resolvedAccent = accent.resolve(in: .init())

        // Accent should have noticeably different RGB values from paper
        let rDiff = abs(resolvedAccent.red - resolvedPaper.red)
        let gDiff = abs(resolvedAccent.green - resolvedPaper.green)
        let bDiff = abs(resolvedAccent.blue - resolvedPaper.blue)
        let totalDiff = rDiff + gDiff + bDiff

        // hkAccent (oklch 58% 0.22 285) should be a visible purple,
        // distinctly different from hkPaper (oklch 12% 0.008 270).
        XCTAssertGreaterThan(totalDiff, 0.3)
    }

    func testAllColorsDefined() {
        let colors: [Color] = [
            .hkPaper,
            .hkPaper2,
            .hkSurface,
            .hkSurface2,
            .hkRule,
            .hkNeutral,
            .hkMuted,
            .hkInk,
            .hkAccent,
            .hkAccent2,
        ]
        XCTAssertEqual(colors.count, 10)

        for (index, color) in colors.enumerated() {
            let resolved = color.resolve(in: .init())
            XCTAssertFalse(
                resolved.red.isNaN || resolved.green.isNaN || resolved.blue.isNaN,
                "Color at index \(index) produced NaN components"
            )
        }
    }
}
