// MARK: - DesignSystem Typography
//
// System font scale for Hermes Desktop:
//   Body  → SF Pro  (Font.system)
//   Code  → SF Mono (Font.monospaced)
//   Scale → caption(11), body(13), title(16), heading(20)
//
// Line spacing helpers compute additional interline spacing to
// achieve a target line-height multiplier (1.4× body, 1.2× heading)
// over the macOS default of ~1.23× point size.

import SwiftUI

// MARK: - Font Scale

public extension Font {

    // MARK: Body (SF Pro)

    /// Caption — 11 pt SF Pro.
    static let hkCaption  = Font.system(size: 11, weight: .regular, design: .default)
    /// Body — 13 pt SF Pro.
    static let hkBody     = Font.system(size: 13, weight: .regular, design: .default)
    /// Body (emphasised) — 13 pt SF Pro Semibold.
    static let hkBodyEm   = Font.system(size: 13, weight: .semibold, design: .default)
    /// Title — 16 pt SF Pro.
    static let hkTitle    = Font.system(size: 16, weight: .regular, design: .default)
    /// Title (emphasised) — 16 pt SF Pro Semibold.
    static let hkTitleEm  = Font.system(size: 16, weight: .semibold, design: .default)
    /// Heading — 20 pt SF Pro Semibold.
    static let hkHeading  = Font.system(size: 20, weight: .semibold, design: .default)

    // MARK: Code (SF Mono)

    /// Code caption — 11 pt SF Mono.
    static let hkCodeCaption = Font.system(size: 11, weight: .regular, design: .monospaced)
    /// Code body — 13 pt SF Mono.
    static let hkCodeBody    = Font.system(size: 13, weight: .regular, design: .monospaced)
    /// Code title — 16 pt SF Mono.
    static let hkCodeTitle   = Font.system(size: 16, weight: .regular, design: .monospaced)
}

// MARK: - Line Spacing

/// Line-spacing configuration for Hermes Desktop typography.
///
/// Usage:
/// ```swift
/// Text("Hello")
///     .font(.hkBody)
///     .lineSpacing(LineSpacing.body)
/// ```
public enum LineSpacing {
    /// Body multiplier 1.4× at 13 pt → ~2.2 pt additional spacing.
    public static let body: CGFloat = hkAdditionalSpacing(pointSize: 13, multiplier: 1.4)

    /// Heading multiplier 1.2× at 20 pt → ~−0.6 pt (tighter, slightly
    /// negative to offset the default ~1.23× leading).
    public static let heading: CGFloat = hkAdditionalSpacing(pointSize: 20, multiplier: 1.2)

    /// Caption multiplier 1.4× at 11 pt → ~1.9 pt.
    public static let caption: CGFloat = hkAdditionalSpacing(pointSize: 11, multiplier: 1.4)

    /// Title multiplier 1.3× at 16 pt → ~1.1 pt.
    public static let title: CGFloat = hkAdditionalSpacing(pointSize: 16, multiplier: 1.3)
}

// MARK: - Spacing Computation

/// The macOS default line-height / point-size ratio for system fonts
/// at text sizes (SF Pro, 11–20 pt).
private let kDefaultLineHeightRatio: CGFloat = 1.23

/// Computes the additional `.lineSpacing(_:)` value needed to achieve
/// `multiplier` × `pointSize` total line height, given a default ratio
/// of ~1.23× on macOS.
///
/// Negative results (when the target ratio is below the default, e.g.
/// heading at 1.2×) are returned as zero; SwiftUI ignores negative
/// line spacing values.
///
/// - Parameters:
///   - pointSize: The font's point size.
///   - multiplier: Desired total line-height multiplier (e.g. 1.4).
/// - Returns: Additional spacing to pass to `.lineSpacing(_:)`.
private func hkAdditionalSpacing(pointSize: CGFloat, multiplier: CGFloat) -> CGFloat {
    let natural = pointSize * kDefaultLineHeightRatio
    let target  = pointSize * multiplier
    return max(0, target - natural)
}
