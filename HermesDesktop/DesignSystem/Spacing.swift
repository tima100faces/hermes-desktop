// MARK: - DesignSystem Spacing
//
// 4 px grid system.  Use these constants for all layout margins,
// stack spacing, and padding to maintain visual rhythm.
//
// Usage:
// ```swift
// VStack(spacing: Space.sm) { ... }
//     .padding(Space.md)
// ```

import CoreGraphics

/// 4‑point grid spacing constants for Hermes Desktop.
public enum Space {
    /// 4 pt — micro spacing.
    public static let xs:  CGFloat = 4
    /// 8 pt — tight spacing.
    public static let sm:  CGFloat = 8
    /// 16 pt — default spacing.
    public static let md:  CGFloat = 16
    /// 24 pt — relaxed spacing.
    public static let lg:  CGFloat = 24
    /// 32 pt — generous spacing.
    public static let xl:  CGFloat = 32
    /// 48 pt — section spacing.
    public static let xxl: CGFloat = 48
}
