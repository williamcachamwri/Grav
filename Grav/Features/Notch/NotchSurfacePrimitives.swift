import AppKit
import SwiftUI

/// Elevation steps for calm dark Liquid Glass surfaces inside the Notch HUD.
enum NotchSurfaceElevation {
    case subtle
    case base
    case elevated

    var fillColor: Color {
        switch self {
        case .subtle:
            return GravPalette.cardFillSubtle
        case .base:
            return GravPalette.cardFillBase
        case .elevated:
            return GravPalette.cardFillElevated
        }
    }
}

/// Applies a calm dark surface with continuous corner geometry and a whisper-quiet 0.5pt hairline.
struct NotchGlassSurfaceModifier: ViewModifier {
    var elevation: NotchSurfaceElevation
    var cornerRadius: CGFloat
    var showSpecularStroke: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle.grav(cornerRadius)
                    .fill(elevation.fillColor)
            )
            .overlay {
                if showSpecularStroke {
                    RoundedRectangle.grav(cornerRadius)
                        .strokeBorder(GravPalette.specularStroke, lineWidth: 0.5)
                }
            }
    }
}

extension View {
    func notchGlassSurface(
        _ elevation: NotchSurfaceElevation = .subtle,
        cornerRadius: CGFloat = GravRadius.controlM,
        stroke: Bool = true
    ) -> some View {
        modifier(
            NotchGlassSurfaceModifier(
                elevation: elevation,
                cornerRadius: cornerRadius,
                showSpecularStroke: stroke
            )
        )
    }
}

/// Crisp 5.5pt semantic telemetry dot with optional quiet optical pulse strictly while active.
struct NotchSemanticDot: View {
    var color: Color
    var size: CGFloat = 5.5
    var isPulsing: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseExpanded: Bool = false

    var body: some View {
        ZStack {
            if isPulsing && !reduceMotion {
                Circle()
                    .strokeBorder(color.opacity(pulseExpanded ? 0.0 : 0.42), lineWidth: 0.9)
                    .frame(width: size * 2.0, height: size * 2.0)
                    .scaleEffect(pulseExpanded ? 1.25 : 0.70)
                    .onAppear { startPulse() }
                    .onDisappear { stopPulse() }
            }

            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .frame(width: size + 4, height: size + 4)
        .onChange(of: isPulsing) { _, active in
            if active && !reduceMotion {
                startPulse()
            } else {
                stopPulse()
            }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced || !isPulsing {
                stopPulse()
            } else {
                startPulse()
            }
        }
        .accessibilityHidden(true)
    }

    private func startPulse() {
        pulseExpanded = false
        withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
            pulseExpanded = true
        }
    }

    private func stopPulse() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            pulseExpanded = false
        }
    }
}

/// Borderless ghost chrome button for compact Notch HUD controls:
/// completely invisible at rest, illuminating smoothly with a calm frosted pill on hover or active state.
struct NotchChromeButtonStyle: ButtonStyle {
    var isActive: Bool = false
    var cornerRadius: CGFloat = 6.5

    @State private var isHovered: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle.grav(cornerRadius)
                    .fill(backgroundFill(isPressed: configuration.isPressed))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(GravMotion.subtleFade, value: isHovered)
            .animation(GravMotion.subtleFade, value: configuration.isPressed)
            .onHover { hovering in
                isHovered = hovering
            }
    }

    private func backgroundFill(isPressed: Bool) -> Color {
        if isPressed {
            return Color.white.opacity(0.13)
        }
        if isActive {
            return Color.white.opacity(0.10)
        }
        if isHovered {
            return Color.white.opacity(0.075)
        }
        return Color.clear
    }
}

/// Formatting and clipboard utilities shared across Notch HUD views.
enum NotchTelemetryHelpers {
    /// Returns the full home-relative parent directory path (`~/Grav/Grav/Core/Telemetry`)
    /// so users see the complete path without artificial mid-path truncation.
    static func compactParentPath(for fullPath: String) -> String {
        let url = URL(fileURLWithPath: fullPath)
        let parent = url.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if parent.hasPrefix(home) {
            return "~" + parent.dropFirst(home.count)
        }
        return parent
    }

    /// Formats a `FileChangeEvent` into a clean unified-style diff string for clipboard export.
    static func formatUnifiedDiff(for event: FileChangeEvent) -> String {
        var output: [String] = [
            "--- \(event.path)",
            "+++ \(event.path) (\(event.kind.rawValue), +\(event.addedLines) -\(event.removedLines))",
        ]
        for (hunkIndex, hunk) in event.diffHunks.enumerated() {
            output.append("@@ hunk \(hunkIndex + 1) (+\(hunk.addedCount) -\(hunk.removedCount)) @@")
            for line in hunk.lines {
                let prefix: String
                switch line.kind {
                case .added: prefix = "+"
                case .removed: prefix = "-"
                case .context: prefix = " "
                }
                output.append("\(prefix)\(line.text)")
            }
        }
        return output.joined(separator: "\n")
    }

    /// Copies text cleanly to the general macOS pasteboard.
    @MainActor
    static func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Semantic telemetry color for a given `FileChangeKind`.
    static func color(for kind: FileChangeKind) -> Color {
        switch kind {
        case .create:
            return GravPalette.emerald
        case .edit, .overwrite:
            return GravPalette.fileEdit
        case .delete:
            return GravPalette.coral
        }
    }

    /// Semantic telemetry color for a given `CommandStatus`.
    static func color(for status: CommandStatus) -> Color {
        switch status {
        case .running:
            return GravPalette.glacialCyan
        case .succeeded:
            return GravPalette.emerald
        case .failed:
            return GravPalette.coral
        }
    }

    /// Semantic telemetry color for high-level `TelemetryState`.
    static func color(for state: TelemetryState, isPaused: Bool) -> Color {
        if isPaused {
            return GravPalette.idleDot
        }
        switch state {
        case .idle:
            return GravPalette.idleDot
        case .working:
            return Color.white.opacity(0.84)
        case .compacting:
            return GravPalette.prismViolet
        case .thinking, .inspecting:
            return GravPalette.thinking
        case .replying:
            return GravPalette.emerald
        case let .editing(event):
            return event.kind == .delete ? GravPalette.coral : GravPalette.fileEdit
        case .runningCommand:
            return GravPalette.glacialCyan
        }
    }
}

/// Optical specular shimmer text matching Antigravity's exact `Working`, `Compacting`,
/// and `Thinking for Ns` status sweep — pure luminance wave across crisp SF Pro glyphs,
/// zero neon glow or AI-slop haze.
struct NotchShimmerText: View {
    var text: String
    var font: Font = .system(size: 11.5, weight: .medium)
    var tracking: CGFloat = -0.15
    var baseOpacity: Double = 0.44
    var peakOpacity: Double = 0.96
    var period: Double = 1.75
    var turboMode: Bool = false
    var turboTheme: SuperSaiyanAuraTheme = .superSaiyan
    var reduceMotion: Bool = false

    var body: some View {
        let baseColor = turboMode
            ? turboTheme.innerColor.opacity(max(baseOpacity, 0.60))
            : Color.white.opacity(baseOpacity)
        let effectivePeriod = turboMode ? max(1.05, period * 0.66) : period

        if reduceMotion {
            Text(text)
                .font(font)
                .tracking(tracking)
                .foregroundStyle(turboMode ? turboTheme.innerColor : Color.white.opacity(0.78))
                .lineLimit(1)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let rawPhase = (t.truncatingRemainder(dividingBy: effectivePeriod)) / effectivePeriod
                let phase = rawPhase < 0 ? rawPhase + 1.0 : rawPhase
                // Sweep highlight smoothly from -0.35 to 1.35 across the glyph width
                let center = -0.35 + phase * 1.70
                let bandHalfWidth = turboMode ? 0.30 : 0.24

                Text(text)
                    .font(font)
                    .tracking(tracking)
                    .foregroundStyle(baseColor)
                    .lineLimit(1)
                    .overlay {
                        LinearGradient(
                            stops: turboMode
                                ? [
                                    .init(color: .clear, location: max(0, min(1, center - bandHalfWidth))),
                                    .init(color: turboTheme.outerColor.opacity(0.95), location: max(0, min(1, center - bandHalfWidth * 0.48))),
                                    .init(color: turboTheme.coreColor, location: max(0, min(1, center))),
                                    .init(color: turboTheme.primaryColor.opacity(0.96), location: max(0, min(1, center + bandHalfWidth * 0.48))),
                                    .init(color: .clear, location: max(0, min(1, center + bandHalfWidth))),
                                ]
                                : [
                                    .init(color: .clear, location: max(0, min(1, center - bandHalfWidth))),
                                    .init(color: Color.white.opacity(peakOpacity), location: max(0, min(1, center))),
                                    .init(color: .clear, location: max(0, min(1, center + bandHalfWidth))),
                                ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .mask(
                            Text(text)
                                .font(font)
                                .tracking(tracking)
                                .lineLimit(1)
                        )
                    }
            }
        }
    }
}

/// Live ticking `"Thinking for 3s"` shimmer label matching Antigravity's native thinking indicator.
struct NotchThinkingShimmerLabel: View {
    var startDate: Date
    var compact: Bool = false
    var font: Font = .system(size: 11.5, weight: .medium)
    var turboMode: Bool = false
    var turboTheme: SuperSaiyanAuraTheme = .superSaiyan
    var reduceMotion: Bool = false

    var body: some View {
        TimelineView(.periodic(from: startDate, by: 1.0)) { context in
            let elapsed = max(0, Int(context.date.timeIntervalSince(startDate)))
            let durationString: String = {
                if elapsed < 60 {
                    return "\(elapsed)s"
                }
                let mins = elapsed / 60
                let secs = elapsed % 60
                return secs == 0 ? "\(mins)m" : "\(mins)m \(secs)s"
            }()
            let label = compact ? "Thinking \(durationString)" : "Thinking for \(durationString)"
            NotchShimmerText(
                text: label,
                font: font,
                tracking: -0.15,
                baseOpacity: 0.46,
                peakOpacity: 0.96,
                period: 1.85,
                turboMode: turboMode,
                turboTheme: turboTheme,
                reduceMotion: reduceMotion
            )
            .monospacedDigit()
        }
    }
}

/// Seamless `"Working"` (0–1s) -> `"Thinking for Ns"` (2s+) shimmer label matching Antigravity's
/// exact real-time cadence between tool steps and deep reasoning turns.
struct NotchWorkingThinkingShimmerLabel: View {
    var startDate: Date
    var compact: Bool = false
    var font: Font = .system(size: 11.5, weight: .medium)
    var turboMode: Bool = false
    var turboTheme: SuperSaiyanAuraTheme = .superSaiyan
    var reduceMotion: Bool = false

    var body: some View {
        TimelineView(.periodic(from: startDate, by: 1.0)) { context in
            let elapsed = max(0, Int(context.date.timeIntervalSince(startDate)))
            let label: String = {
                if elapsed < 2 {
                    return "Working"
                }
                let durationString: String
                if elapsed < 60 {
                    durationString = "\(elapsed)s"
                } else {
                    let mins = elapsed / 60
                    let secs = elapsed % 60
                    durationString = secs == 0 ? "\(mins)m" : "\(mins)m \(secs)s"
                }
                return compact ? "Thinking \(durationString)" : "Thinking for \(durationString)"
            }()
            NotchShimmerText(
                text: label,
                font: font,
                tracking: -0.15,
                baseOpacity: 0.46,
                peakOpacity: 0.96,
                period: 1.80,
                turboMode: turboMode,
                turboTheme: turboTheme,
                reduceMotion: reduceMotion
            )
            .monospacedDigit()
        }
    }
}

/// Forged-Ember thermal filament rendered strictly while Antigravity is running in Turbo Mode.
/// Zero fuzzy neon halo — pure surgical `1.2pt` traveling optical energy edge.
struct TurboThermalRimView: View {
    var isActive: Bool
    var reduceMotion: Bool = false

    var body: some View {
        let baseOpacity = isActive ? 0.92 : 0.42

        if reduceMotion {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            GravPalette.turboCrimson.opacity(0.65),
                            GravPalette.turboEmber,
                            GravPalette.turboWhiteHot,
                            GravPalette.turboEmber,
                            GravPalette.turboCrimson.opacity(0.65),
                            Color.clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1.2)
                .opacity(baseOpacity)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let period = isActive ? 1.85 : 3.6
                let raw = (t.truncatingRemainder(dividingBy: period)) / period
                let phase = raw < 0 ? raw + 1.0 : raw
                // Ping-pong smooth sinusoidal travel across the filament
                let center = 0.14 + 0.72 * (0.5 - 0.5 * cos(phase * .pi * 2.0))
                let spread = isActive ? 0.28 : 0.22

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: max(0, center - spread * 1.4)),
                                .init(color: GravPalette.turboCrimson.opacity(0.75), location: max(0, center - spread * 0.85)),
                                .init(color: GravPalette.turboEmber, location: max(0, center - spread * 0.35)),
                                .init(color: isActive ? Color.white.opacity(0.95) : GravPalette.turboWhiteHot, location: center),
                                .init(color: GravPalette.turboEmber, location: min(1, center + spread * 0.35)),
                                .init(color: GravPalette.turboCrimson.opacity(0.75), location: min(1, center + spread * 0.85)),
                                .init(color: .clear, location: min(1, center + spread * 1.4)),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: isActive ? 1.4 : 1.0)
                    .opacity(baseOpacity)
            }
        }
    }
}
