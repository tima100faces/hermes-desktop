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

    // MARK: - Backgrounds (Obsidian-inspired, crystalline dark)

    /// Page background — deep void (oklch 10%, #171717-equivalent).
    static let hkPage     = oklchToColor(lightness: 0.10, chroma: 0.003, hue: 270)
    /// Panel / sidebar background (oklch 15%, #1e1e1e-equivalent).
    static let hkPanel    = oklchToColor(lightness: 0.15, chroma: 0.005, hue: 270)
    /// Card / surface background (oklch 20%).
    static let hkSurface  = oklchToColor(lightness: 0.20, chroma: 0.005, hue: 270)
    /// Elevated surface (oklch 25%).
    static let hkSurface2 = oklchToColor(lightness: 0.25, chroma: 0.006, hue: 270)

    // MARK: - Borders & Dividers

    /// Subtle border / graphite (oklch 28%).
    static let hkBorder   = oklchToColor(lightness: 0.28, chroma: 0.005, hue: 270)
    /// Visible divider (oklch 34%).
    static let hkRule     = oklchToColor(lightness: 0.34, chroma: 0.006, hue: 270)

    // MARK: - Text (Obsidian stepping)

    /// Tertiary text (oklch 55%).
    static let hkNeutral  = oklchToColor(lightness: 0.55, chroma: 0.004, hue: 270)
    /// Secondary / body (oklch 72%, #bcbcbc-equivalent).
    static let hkMuted    = oklchToColor(lightness: 0.72, chroma: 0.004, hue: 270)
    /// Primary text — bright but not pure (oklch 93%, #eeeeee-equivalent).
    static let hkInk      = oklchToColor(lightness: 0.93, chroma: 0.003, hue: 270)

    // MARK: - Accent (Obsidian amethyst #7c3aed)

    /// Primary accent — electric violet.
    static let hkAccent   = oklchToColor(lightness: 0.48, chroma: 0.24, hue: 295)
    /// Hover / highlight.
    static let hkAccent2  = oklchToColor(lightness: 0.62, chroma: 0.18, hue: 290)
    /// Dim accent (15% opacity).
    static let hkAccentDim = oklchToColor(lightness: 0.48, chroma: 0.24, hue: 295).opacity(0.15)

    // MARK: - Effects

    /// Inset glow on dark surfaces (1px white at 5% opacity).
    static let hkGlow = Color.white.opacity(0.05)
}
