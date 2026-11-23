import AppKit
import QuartzCore
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
/// The pulse ring is driven 100% by CoreAnimation on GPU (0.0% CPU, native 120Hz ProMotion).
struct NotchSemanticDot: View {
    var color: Color
    var size: CGFloat = 5.5
    var isPulsing: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if isPulsing && !reduceMotion {
                SemanticPulseRingCALayerView(color: NSColor(color), diameter: size * 2.0)
                    .frame(width: size * 2.0, height: size * 2.0)
            }

            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .frame(width: size + 4, height: size + 4)
        .accessibilityHidden(true)
    }
}

private struct SemanticPulseRingCALayerView: NSViewRepresentable {
    let color: NSColor
    let diameter: CGFloat

    final class PulseHostView: NSView {
        private let ringLayer = CAShapeLayer()
        private var currentColor: NSColor = .white
        private var currentDiameter: CGFloat = 11

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layerContentsRedrawPolicy = .never
            layer?.masksToBounds = false
            ringLayer.fillColor = nil
            ringLayer.lineWidth = 0.9
            layer?.addSublayer(ringLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            updateGeometry()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                ensureAnimation()
            } else {
                ringLayer.removeAllAnimations()
            }
        }

        func configure(color: NSColor, diameter: CGFloat) {
            currentColor = color
            currentDiameter = diameter
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            ringLayer.strokeColor = color.cgColor
            updateGeometry()
            CATransaction.commit()
            if window != nil {
                ensureAnimation()
            }
        }

        private func updateGeometry() {
            let inset: CGFloat = 0.45
            let rect = CGRect(
                x: inset,
                y: inset,
                width: max(1, currentDiameter - inset * 2),
                height: max(1, currentDiameter - inset * 2)
            )
            ringLayer.bounds = CGRect(origin: .zero, size: CGSize(width: currentDiameter, height: currentDiameter))
            ringLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            ringLayer.path = CGPath(ellipseIn: rect, transform: nil)
        }

        private func ensureAnimation() {
            guard ringLayer.animation(forKey: "semanticPulse") == nil else { return }
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.70
            scale.toValue = 1.25

            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 0.42
            opacity.toValue = 0.0

            let group = CAAnimationGroup()
            group.animations = [scale, opacity]
            group.duration = 1.5
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.repeatCount = .infinity
            group.isRemovedOnCompletion = false
            ringLayer.add(group, forKey: "semanticPulse")
        }
    }

    func makeNSView(context: Context) -> PulseHostView {
        let view = PulseHostView(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        view.configure(color: color, diameter: diameter)
        return view
    }

    func updateNSView(_ nsView: PulseHostView, context: Context) {
        nsView.configure(color: color, diameter: diameter)
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
    private static let cachedHomeDirectoryPath: String = {
        FileManager.default.homeDirectoryForCurrentUser.path
    }()

    /// Returns the full home-relative parent directory path (`~/Grav/Grav/Core/Telemetry`)
    /// so users see the complete path without artificial mid-path truncation.
    static func compactParentPath(for fullPath: String) -> String {
        let parent: String
        if let lastSlash = fullPath.lastIndex(of: "/") {
            parent = lastSlash == fullPath.startIndex ? "/" : String(fullPath[..<lastSlash])
        } else {
            parent = ""
        }
        let home = cachedHomeDirectoryPath
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

    /// Semantic telemetry color for a given `ToolExecutionStatus`.
    static func color(for status: ToolExecutionStatus) -> Color {
        switch status {
        case .running:
            return GravPalette.glacialCyan
        case .succeeded:
            return GravPalette.emerald
        case .failed:
            return GravPalette.coral
        case .waiting:
            return GravPalette.fileEdit
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
        case .waitingForInput:
            return GravPalette.fileEdit
        case .toolActivity:
            return GravPalette.glacialCyan
        }
    }
}

/// Optical specular shimmer text matching Antigravity's exact `Working`, `Compacting`,
/// and `Thinking for Ns` status sweep — pure luminance wave across crisp SF Pro glyphs,
/// interpolated 100% by CoreAnimation `CAGradientLayer` on GPU (native 120Hz ProMotion, 0.0% CPU).
struct NotchShimmerText: View {
    var text: String
    var font: Font = .system(size: 11.5, weight: .medium)
    var tracking: CGFloat = -0.15
    var baseOpacity: Double = 0.44
    var peakOpacity: Double = 0.96
    var period: Double = 1.75
    var reduceMotion: Bool = false

    var body: some View {
        let baseColor = Color.white.opacity(baseOpacity)

        if reduceMotion {
            Text(text)
                .font(font)
                .tracking(tracking)
                .foregroundStyle(Color.white.opacity(0.78))
                .lineLimit(1)
        } else {
            Text(text)
                .font(font)
                .tracking(tracking)
                .foregroundStyle(baseColor)
                .lineLimit(1)
                .overlay {
                    ShimmerSweepCALayerView(peakOpacity: peakOpacity, period: period)
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

private struct ShimmerSweepCALayerView: NSViewRepresentable {
    let peakOpacity: Double
    let period: Double

    final class ShimmerHostView: NSView {
        private let gradientLayer = CAGradientLayer()
        private var appliedPeakOpacity: Double = -1
        private var appliedPeriod: Double = -1

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layerContentsRedrawPolicy = .never
            gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
            gradientLayer.locations = [-0.59, -0.35, -0.11] as [NSNumber]
            gradientLayer.actions = ["bounds": NSNull(), "position": NSNull(), "frame": NSNull()]
            layer?.addSublayer(gradientLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            gradientLayer.frame = bounds
            CATransaction.commit()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                ensureAnimation(forceRestart: false)
            } else {
                gradientLayer.removeAllAnimations()
            }
        }

        func configure(peakOpacity: Double, period: Double) {
            let needsColorUpdate = abs(appliedPeakOpacity - peakOpacity) > 0.001
            let needsPeriodUpdate = abs(appliedPeriod - period) > 0.001
            guard needsColorUpdate || needsPeriodUpdate || gradientLayer.animation(forKey: "shimmerSweep") == nil else {
                return
            }
            appliedPeakOpacity = peakOpacity
            appliedPeriod = period

            if needsColorUpdate {
                let clear = NSColor.white.withAlphaComponent(0.0).cgColor
                let peak = NSColor.white.withAlphaComponent(peakOpacity).cgColor
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                gradientLayer.colors = [clear, peak, clear]
                CATransaction.commit()
            }
            if window != nil {
                ensureAnimation(forceRestart: needsPeriodUpdate)
            }
        }

        private func ensureAnimation(forceRestart: Bool) {
            if !forceRestart, gradientLayer.animation(forKey: "shimmerSweep") != nil {
                return
            }
            gradientLayer.removeAnimation(forKey: "shimmerSweep")
            let anim = CABasicAnimation(keyPath: "locations")
            // Exact sweep from center = -0.35 to center = 1.35 with bandHalfWidth = 0.24
            anim.fromValue = [-0.59, -0.35, -0.11] as [NSNumber]
            anim.toValue = [1.11, 1.35, 1.59] as [NSNumber]
            anim.duration = max(0.3, appliedPeriod)
            anim.repeatCount = .infinity
            anim.isRemovedOnCompletion = false
            gradientLayer.add(anim, forKey: "shimmerSweep")
        }
    }

    func makeNSView(context: Context) -> ShimmerHostView {
        let view = ShimmerHostView(frame: .zero)
        view.configure(peakOpacity: peakOpacity, period: period)
        return view
    }

    func updateNSView(_ nsView: ShimmerHostView, context: Context) {
        nsView.configure(peakOpacity: peakOpacity, period: period)
    }
}

/// Live ticking `"Thinking for 3s"` shimmer label matching Antigravity's native thinking indicator.
struct NotchThinkingShimmerLabel: View {
    var startDate: Date
    var compact: Bool = false
    var font: Font = .system(size: 11.5, weight: .medium)
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
                reduceMotion: reduceMotion
            )
            .monospacedDigit()
        }
    }
}
