import SwiftUI

/// Grav Obsidian Graphite × Electric Sky Azure visual palette, calibrated directly
/// from the Grav app logo (`#16161A` obsidian substrate + `#1A8EFD` / `#34A8FB` / `#A8E4F5` sky azure).
public enum GravPalette {
    // MARK: - Substrates

    /// Deep Hardware Obsidian void backdrop (`#0A0B0F`).
    public static let obsidianVoid = Color(red: 0x0A / 255.0, green: 0x0B / 255.0, blue: 0x0F / 255.0)

    /// Elevated obsidian graphite panel surface (`#14151A`, harmonized with logo `#16161A`).
    public static let obsidianSurface = Color(red: 0x14 / 255.0, green: 0x15 / 255.0, blue: 0x1A / 255.0)

    /// Pure pitch black for seamless hardware bezel continuity inside NotchKit.
    public static let notchBlack = Color.black

    // MARK: - Brand Accents (Calibrated to Grav Logo Electric Sky Azure)

    /// Primary Brand Accent — Electric Azure (`#1A8EFD`, sampled directly from logo).
    public static let glacialTeal = Color(red: 0x1A / 255.0, green: 0x8E / 255.0, blue: 0xFD / 255.0)

    /// Secondary Luminous Sky Cyan (`#5CC8FA`, bridging logo's `#34A8FB` → `#A8E4F5`).
    public static let glacialCyan = Color(red: 0x5C / 255.0, green: 0xC8 / 255.0, blue: 0xFA / 255.0)

    /// Luminous Titanium White (`#F8FAFC`).
    public static let titaniumWhite = Color(red: 0xF8 / 255.0, green: 0xFA / 255.0, blue: 0xFC / 255.0)

    /// Brand directional gradient from Electric Azure to Luminous Sky Cyan.
    public static let brandAccentGradient = LinearGradient(
        colors: [glacialTeal, glacialCyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Semantic Telemetry Accents (Quiet, High-Precision)

    /// Thinking / Active Reasoning — Sky Azure (`#38B6FF`).
    public static let thinking = Color(red: 0x38 / 255.0, green: 0xB6 / 255.0, blue: 0xFF / 255.0)

    /// Context Compaction — Soft Prism Violet (`#C084FC`, harmonized with logo magenta-violet edge).
    public static let prismViolet = Color(red: 0xC0 / 255.0, green: 0x84 / 255.0, blue: 0xFC / 255.0)

    /// File Edit / Create — Warm Solar Amber (`#F59E0B`, harmonized with logo crest).
    public static let fileEdit = Color(red: 0xF5 / 255.0, green: 0x9E / 255.0, blue: 0x0B / 255.0)

    /// Added lines & command success exit 0 — Crisp Emerald (`#34D399`).
    public static let emerald = Color(red: 0x34 / 255.0, green: 0xD3 / 255.0, blue: 0x99 / 255.0)

    /// Removed lines, file delete, destructive shell, & non-zero command exit — Muted Coral (`#F87171`).
    public static let coral = Color(red: 0xF8 / 255.0, green: 0x71 / 255.0, blue: 0x71 / 255.0)

    /// Running command luminous neutral white.
    public static let commandRunning = Color(red: 0xF8 / 255.0, green: 0xFA / 255.0, blue: 0xFC / 255.0)

    /// Idle muted indicator tone.
    public static let idleDot = Color.white.opacity(0.28)

    // MARK: - 4-Step White Ink Ramp (Dark Liquid Glass)

    public static let inkPrimary = Color.white.opacity(0.96)
    public static let inkSecondary = Color.white.opacity(0.76)
    public static let inkTertiary = Color.white.opacity(0.50)
    public static let inkQuaternary = Color.white.opacity(0.30)

    // MARK: - 3-Step Calm Dark Card Fills

    public static let cardFillSubtle = Color.white.opacity(0.04)
    public static let cardFillBase = Color.white.opacity(0.068)
    public static let cardFillElevated = Color.white.opacity(0.10)

    // MARK: - Top-Lit Specular Hairlines

    public static let hairlineTop = Color.white.opacity(0.18)
    public static let hairlineMid = Color.white.opacity(0.08)
    public static let hairlineBottom = Color.white.opacity(0.025)

    public static let specularStroke = LinearGradient(
        stops: [
            .init(color: hairlineTop, location: 0.0),
            .init(color: hairlineMid, location: 0.45),
            .init(color: hairlineBottom, location: 1.0),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}
