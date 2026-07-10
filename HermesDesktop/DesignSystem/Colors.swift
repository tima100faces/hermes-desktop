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

    // MARK: - Backgrounds

    /// Darkest background (oklch 12% 0.008 270).
    static let hkPaper   = oklchToColor(lightness: 0.12, chroma: 0.008, hue: 270)
    /// Alt background (oklch 14% 0.010 270).
    static let hkPaper2  = oklchToColor(lightness: 0.14, chroma: 0.010, hue: 270)

    // MARK: - Surfaces

    /// Card / surface background (oklch 18% 0.012 270).
    static let hkSurface  = oklchToColor(lightness: 0.18, chroma: 0.012, hue: 270)
    /// Elevated surface (oklch 22% 0.014 270).
    static let hkSurface2 = oklchToColor(lightness: 0.22, chroma: 0.014, hue: 270)

    // MARK: - Borders & Rules

    /// Border / divider rule (oklch 28% 0.015 270).
    static let hkRule     = oklchToColor(lightness: 0.28, chroma: 0.015, hue: 270)

    // MARK: - Text

    /// Muted / secondary text (oklch 50% 0.012 270).
    static let hkNeutral  = oklchToColor(lightness: 0.50, chroma: 0.012, hue: 270)
    /// Secondary text (oklch 65% 0.008 270).
    static let hkMuted    = oklchToColor(lightness: 0.65, chroma: 0.008, hue: 270)
    /// Primary text (oklch 93% 0.005 270).
    static let hkInk      = oklchToColor(lightness: 0.93, chroma: 0.005, hue: 270)

    // MARK: - Accents

    /// Primary accent (oklch 58% 0.22 285).
    static let hkAccent   = oklchToColor(lightness: 0.58, chroma: 0.22, hue: 285)
    /// Hover / highlight accent (oklch 72% 0.18 285).
    static let hkAccent2  = oklchToColor(lightness: 0.72, chroma: 0.18, hue: 285)
}
