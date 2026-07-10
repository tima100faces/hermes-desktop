import XCTest
import SwiftUI
@testable import HermesDesktop

// MARK: - DesignSystemTests

final class DesignSystemTests: XCTestCase {

    // MARK: - Oklch → Color

    func testOklchToColorProducesValidColor() {
        let color = Color.hkPage
        // The color should not be a clear/empty color — extract components
        // to verify it resolved to something.
        let resolved = color.resolve(in: .init())
        XCTAssertGreaterThan(resolved.red, 0)
        XCTAssertGreaterThanOrEqual(resolved.green, 0)
        XCTAssertGreaterThanOrEqual(resolved.blue, 0)
    }

    func testAccentColor() {
        let page = Color.hkPage
        let accent = Color.hkAccent

        let resolvedPage = page.resolve(in: .init())
        let resolvedAccent = accent.resolve(in: .init())

        // Accent should have noticeably different RGB values from the page
        // background.
        let rDiff = abs(resolvedAccent.red - resolvedPage.red)
        let gDiff = abs(resolvedAccent.green - resolvedPage.green)
        let bDiff = abs(resolvedAccent.blue - resolvedPage.blue)
        let totalDiff = rDiff + gDiff + bDiff

        // hkAccent (0xB7410E, rust) should be clearly distinguishable from
        // hkPage (0x171717, near-black).
        XCTAssertGreaterThan(totalDiff, 0.3)
    }

    func testAllColorsDefined() {
        let colors: [Color] = [
            .hkPage,
            .hkPanel,
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
