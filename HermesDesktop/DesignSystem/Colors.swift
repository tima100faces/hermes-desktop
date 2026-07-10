// MARK: - DesignSystem Colors
//
// Hallmark dark-theme tokens → SwiftUI Color.
//
// All values are literal sRGB hex from docs/UI-SPEC.md §2.
// The previous oklch→sRGB conversion contained a math bug (missing LMS
// cube + second matrix), which rendered every neutral ~3× lighter than
// intended. Do NOT reintroduce runtime color math — literal hex only.
//
// RULE: components NEVER hardcode colors. Only these tokens.

import SwiftUI

// MARK: - Hex Initializer

extension Color {
    /// Creates an sRGB color from a 24-bit hex value,
    /// e.g. `Color(hk: 0x171717)`.
    init(hk hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

// MARK: - Hallmark Color Tokens

public extension Color {

    // MARK: - Backgrounds (Obsidian-inspired, crystalline dark)

    /// Page background — deep void.
    static let hkPage     = Color(hk: 0x171717)
    /// Sidebar background.
    static let hkPanel    = Color(hk: 0x1A1A1A)
    /// Card / surface background (user message, input, status cards).
    static let hkSurface  = Color(hk: 0x1E1E1E)
    /// Elevated surface (disabled send button, hover surfaces).
    static let hkSurface2 = Color(hk: 0x262626)
    /// Code block background — darker than the page.
    static let hkCodeBg   = Color(hk: 0x121212)

    // MARK: - Borders & Dividers

    /// Subtle border.
    static let hkBorder   = Color(hk: 0x2E2E2E)
    /// Visible divider / graphite.
    static let hkRule     = Color(hk: 0x3F3F3F)

    // MARK: - Text (Obsidian stepping)

    /// Tertiary text — timestamps, placeholders, metadata.
    static let hkNeutral  = Color(hk: 0xA3A3A3)
    /// Secondary text — body in code blocks, inactive labels.
    static let hkMuted    = Color(hk: 0xBCBCBC)
    /// Primary text — bright but not pure white.
    static let hkInk      = Color(hk: 0xEEEEEE)

    // MARK: - Accent (Rust — Ржавчик's signature)
    //
    // Two-tone accent pair, mirroring Obsidian's Amethyst/Lavender logic:
    //   hkAccent  — dark rust, for FILLS (send button, selection bar)
    //   hkAccent2 — light rust, for TEXT (links, active labels, hovers)
    // Dark rust is too dim to be readable as small text on hkPage —
    // always use hkAccent2 for accent-colored text.

    /// Primary accent — rust. Fills only (buttons, selection bar).
    static let hkAccent   = Color(hk: 0xB7410E)
    /// Light rust — links, active-state text, hovers, code keywords.
    static let hkAccent2  = Color(hk: 0xD97E52)
    /// Dim accent — selection / badge backgrounds (rust at 16%).
    static let hkAccentDim = Color(hk: 0xB7410E, opacity: 0.16)

    // MARK: - Semantic

    /// Success — online dots, completed subagents.
    static let hkSuccess  = Color(hk: 0x4ADE80)
    /// Warning — text only, never as a fill (too close to rust).
    static let hkWarning  = Color(hk: 0xFACC15)
    /// Error.
    static let hkError    = Color(hk: 0xF87171)

    // MARK: - Effects
    //
    // Elevation via internal luminescence, never drop shadows.

    /// Inset glow on dark surfaces (1px white at 5% opacity).
    static let hkGlow = Color.white.opacity(0.05)
    /// Stronger inset glow — input field, focused elements (white at 8%).
    static let hkGlowStrong = Color.white.opacity(0.08)
    /// Hover wash for ghost icon buttons (white at 4%).
    static let hkHover = Color.white.opacity(0.04)
}
