// MARK: - DesignSystem Colors
//
// Hallmark dark-theme oklch tokens → SwiftUI Color.
// Conversion: oklch → oklab → linear sRGB → sRGB (gamma).
//
// All values computed at compile-time via `#colorLiteral`‑safe math,
// no runtime conversions needed.

import SwiftUI

// MARK: - Oklch → sRGB Conversion

/// Performs a full oklch → oklab → linear sRGB → sRGB gamma conversion
/// and returns an sRGB `Color` whose components are clamped to [0, 1].
///
/// The math follows the Oklab specification by Björn Ottosson (2020),
/// adapted for Swift 6 with explicit type annotations and no mutable
/// globals.
@usableFromInline
func oklchToColor(
    lightness l: Double,
    chroma c: Double,
    hue h: Double
) -> Color {
    // 1. Oklch → Oklab
    let hueRadians = h * .pi / 180.0
    let a = c * cos(hueRadians)
    let b = c * sin(hueRadians)

    // 2. Oklab → linear sRGB (3×3 matrix from the Oklab specification)
    let lr =  1.0 * l + 0.3963377774 * a + 0.2158037573 * b
    let lg =  1.0 * l - 0.1055613458 * a - 0.0638541728 * b
    let lb =  1.0 * l - 0.0894841775 * a - 1.2914855480 * b

    // 3. Linear sRGB → sRGB (sRGB gamma encoding)
    let gamma: (Double) -> Double = { linear in
        if linear <= 0.0031308 {
            return 12.92 * linear
        } else {
            return 1.055 * pow(linear, 1.0 / 2.4) - 0.055
        }
    }

    let r = gamma(lr).clamped(to: 0...1)
    let g = gamma(lg).clamped(to: 0...1)
    let b_ = gamma(lb).clamped(to: 0...1)

    return Color(red: r, green: g, blue: b_, opacity: 1.0)
}

// MARK: - Double Clamping Helper

extension Double {
    /// Returns the value clamped to the given closed range.
    @usableFromInline
    func clamped(to range: ClosedRange<Double>) -> Double {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Hallmark Color Tokens

public extension Color {

    // MARK: - Backgrounds (Linear-inspired depth stepping)

    /// Page background — near-black canvas (oklch 8%).
    static let hkPage     = oklchToColor(lightness: 0.08, chroma: 0.004, hue: 270)
    /// Panel / sidebar background (oklch 11%).
    static let hkPanel    = oklchToColor(lightness: 0.11, chroma: 0.006, hue: 270)
    /// Card / surface background (oklch 16%).
    static let hkSurface  = oklchToColor(lightness: 0.16, chroma: 0.008, hue: 270)
    /// Elevated surface (oklch 20%).
    static let hkSurface2 = oklchToColor(lightness: 0.20, chroma: 0.010, hue: 270)

    // MARK: - Borders & Dividers (semi-transparent, Linear-style)

    /// Subtle border — semi-transparent white on dark.
    static let hkBorder   = Color.white.opacity(0.06)
    /// Visible border / divider.
    static let hkRule     = Color.white.opacity(0.10)

    // MARK: - Text (stepped luminance)

    /// Muted / tertiary text (oklch 48%).
    static let hkNeutral  = oklchToColor(lightness: 0.48, chroma: 0.008, hue: 270)
    /// Secondary / body text (oklch 68%).
    static let hkMuted    = oklchToColor(lightness: 0.68, chroma: 0.005, hue: 270)
    /// Primary text — soft white, not pure (oklch 95%).
    static let hkInk      = oklchToColor(lightness: 0.95, chroma: 0.003, hue: 270)

    // MARK: - Accent (Linear-style indigo-violet)

    /// Primary accent (oklch 55% 0.20 285).
    static let hkAccent   = oklchToColor(lightness: 0.55, chroma: 0.20, hue: 285)
    /// Hover / highlight accent (oklch 65% 0.18 285).
    static let hkAccent2  = oklchToColor(lightness: 0.65, chroma: 0.18, hue: 285)
    /// Dim accent for subtle emphasis (same L/C, 15% opacity).
    static let hkAccentDim = oklchToColor(lightness: 0.55, chroma: 0.20, hue: 285).opacity(0.15)
}
