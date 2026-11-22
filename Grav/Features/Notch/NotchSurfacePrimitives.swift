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
    /// Returns a compact parent path relative to home (`~/...`) suitable for narrow telemetry rows.
    static func compactParentPath(for fullPath: String) -> String {
        let url = URL(fileURLWithPath: fullPath)
        let parent = url.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let normalized: String
        if parent.hasPrefix(home) {
            normalized = "~" + parent.dropFirst(home.count)
        } else {
            normalized = parent
        }
        let components = normalized.split(separator: "/").map(String.init)
        if components.count <= 3 {
            return normalized
        }
        return "…/" + components.suffix(2).joined(separator: "/")
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
        case .thinking:
            return GravPalette.thinking
        case let .editing(event):
            return event.kind == .delete ? GravPalette.coral : GravPalette.fileEdit
        case .runningCommand:
            return GravPalette.glacialCyan
        }
    }
}
