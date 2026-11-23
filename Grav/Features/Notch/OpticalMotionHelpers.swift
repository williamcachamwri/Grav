import AppKit
import QuartzCore
import SwiftUI

/// Ultra-subtle glacial cyan optical ring rendered exclusively while telemetry is active
/// and Reduce Motion is disabled. Completely absent (zero animation, zero CPU) when idle.
public struct OpticalBreathingRing: View {
    public var isActive: Bool
    public var tint: Color
    public var diameter: CGFloat
    public var lineWidth: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing: Bool = false

    public init(
        isActive: Bool,
        tint: Color = GravPalette.glacialCyan,
        diameter: CGFloat = 20,
        lineWidth: CGFloat = 1.0
    ) {
        self.isActive = isActive
        self.tint = tint
        self.diameter = diameter
        self.lineWidth = lineWidth
    }

    public var body: some View {
        Group {
            if isActive && !reduceMotion {
                Circle()
                    .strokeBorder(tint, lineWidth: lineWidth)
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(isBreathing ? 1.14 : 0.96)
                    .opacity(isBreathing ? 0.12 : 0.42)
                    .onAppear {
                        startBreathing()
                    }
                    .onDisappear {
                        stopBreathing()
                    }
            }
        }
        .onChange(of: isActive) { _, active in
            if active && !reduceMotion {
                startBreathing()
            } else {
                stopBreathing()
            }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced || !isActive {
                stopBreathing()
            } else {
                startBreathing()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func startBreathing() {
        isBreathing = false
        withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
            isBreathing = true
        }
    }

    private func stopBreathing() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isBreathing = false
        }
    }
}

/// Minimal monochrome aerospace arc spinner for running shell commands.
/// Driven 100% by CoreAnimation `CAShapeLayer` on GPU (0.0% CPU, native 120Hz ProMotion).
/// Degrades to a calm static 5pt indicator dot under Reduce Motion or when inactive.
public struct OpticalCommandSpinner: View {
    public var isActive: Bool
    public var size: CGFloat
    public var tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        isActive: Bool,
        size: CGFloat = 10,
        tint: Color = GravPalette.commandRunning
    ) {
        self.isActive = isActive
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        Group {
            if isActive && !reduceMotion {
                OpticalSpinnerCALayerView(tint: NSColor(tint), size: size)
                    .frame(width: size, height: size)
            } else {
                Circle()
                    .fill(isActive ? tint.opacity(0.85) : GravPalette.idleDot)
                    .frame(width: min(5, size * 0.55), height: min(5, size * 0.55))
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct OpticalSpinnerCALayerView: NSViewRepresentable {
    let tint: NSColor
    let size: CGFloat

    final class SpinnerHostView: NSView {
        private let trackLayer = CAShapeLayer()
        private let arcLayer = CAShapeLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layerContentsRedrawPolicy = .never
            trackLayer.fillColor = nil
            trackLayer.lineWidth = 1.35
            arcLayer.fillColor = nil
            arcLayer.lineWidth = 1.35
            arcLayer.lineCap = .round
            arcLayer.strokeStart = 0.0
            arcLayer.strokeEnd = 0.34
            layer?.addSublayer(trackLayer)
            layer?.addSublayer(arcLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                ensureRotation()
            } else {
                arcLayer.removeAllAnimations()
            }
        }

        func configure(tint: NSColor, size: CGFloat) {
            let inset: CGFloat = 0.675
            let rect = CGRect(x: inset, y: inset, width: max(1, size - 1.35), height: max(1, size - 1.35))
            let path = CGPath(ellipseIn: rect, transform: nil)
            let center = CGPoint(x: size * 0.5, y: size * 0.5)
            let boundsRect = CGRect(origin: .zero, size: CGSize(width: size, height: size))

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            trackLayer.strokeColor = tint.withAlphaComponent(0.18).cgColor
            trackLayer.bounds = boundsRect
            trackLayer.position = center
            trackLayer.path = path

            arcLayer.strokeColor = tint.withAlphaComponent(0.92).cgColor
            arcLayer.bounds = boundsRect
            arcLayer.position = center
            arcLayer.path = path
            CATransaction.commit()

            if window != nil {
                ensureRotation()
            }
        }

        private func ensureRotation() {
            guard arcLayer.animation(forKey: "opticalSpin") == nil else { return }
            let anim = CABasicAnimation(keyPath: "transform.rotation.z")
            anim.fromValue = 0.0
            anim.toValue = -Double.pi * 2.0
            anim.duration = 0.85
            anim.repeatCount = .infinity
            anim.isRemovedOnCompletion = false
            arcLayer.add(anim, forKey: "opticalSpin")
        }
    }

    func makeNSView(context: Context) -> SpinnerHostView {
        let view = SpinnerHostView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        view.configure(tint: tint, size: size)
        return view
    }

    func updateNSView(_ nsView: SpinnerHostView, context: Context) {
        nsView.configure(tint: tint, size: size)
    }
}

/// Compact Emerald / Coral proportional micro-diff bar paired with tabular monospaced `+N -M` counters.
public struct NotchProportionalDiffMicroBar: View {
    public var added: Int
    public var removed: Int
    public var isDeleted: Bool
    public var showBar: Bool
    public var barWidth: CGFloat
    public var barHeight: CGFloat

    public init(
        added: Int,
        removed: Int,
        isDeleted: Bool = false,
        showBar: Bool = true,
        barWidth: CGFloat = 34,
        barHeight: CGFloat = 3
    ) {
        self.added = max(0, added)
        self.removed = max(0, removed)
        self.isDeleted = isDeleted
        self.showBar = showBar
        self.barWidth = barWidth
        self.barHeight = barHeight
    }

    private var totalDelta: Int {
        added + removed
    }

    public var body: some View {
        HStack(spacing: 5) {
            if isDeleted && totalDelta == 0 {
                Text("DEL")
                    .font(GravTypography.monoMicro)
                    .foregroundStyle(GravPalette.coral.opacity(0.88))
            } else {
                HStack(spacing: 4) {
                    if isDeleted {
                        Text("DEL")
                            .font(GravTypography.monoMicro)
                            .foregroundStyle(GravPalette.coral.opacity(0.88))
                    }
                    if added > 0 || (!isDeleted && removed == 0) {
                        Text(verbatim: "+\(added)")
                            .font(GravTypography.monoMicro)
                            .monospacedDigit()
                            .foregroundStyle(added > 0 ? GravPalette.emerald : GravPalette.inkQuaternary)
                    }
                    if removed > 0 {
                        Text(verbatim: "-\(removed)")
                            .font(GravTypography.monoMicro)
                            .monospacedDigit()
                            .foregroundStyle(GravPalette.coral)
                    }
                }

                if showBar && totalDelta > 0 {
                    proportionalBar
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var proportionalBar: some View {
        let total = CGFloat(max(1, totalDelta))
        let addedRatio = CGFloat(added) / total
        let removedRatio = CGFloat(removed) / total
        let hasBoth = added > 0 && removed > 0
        let gap: CGFloat = hasBoth ? 1.5 : 0
        let usableWidth = max(0, barWidth - gap)

        return HStack(spacing: gap) {
            if added > 0 {
                RoundedRectangle.grav(barHeight / 2)
                    .fill(GravPalette.emerald)
                    .frame(width: max(2, usableWidth * addedRatio), height: barHeight)
            }
            if removed > 0 {
                RoundedRectangle.grav(barHeight / 2)
                    .fill(GravPalette.coral)
                    .frame(width: max(2, usableWidth * removedRatio), height: barHeight)
            }
        }
        .frame(width: barWidth, height: barHeight, alignment: .leading)
    }

    private var accessibilitySummary: String {
        if isDeleted {
            return removed > 0 ? "Deleted, \(removed) lines removed" : "File deleted"
        }
        return "\(added) lines added, \(removed) lines removed"
    }
}

/// Monospaced elapsed timer (`08s` / `1m 12s`) using numeric transitions.
/// Strictly zero-CPU when idle: only attaches a 1Hz `TimelineView` while `isActive && endDate == nil`.
public struct ActiveElapsedTimerText: View {
    public var startDate: Date
    public var endDate: Date?
    public var isActive: Bool
    public var font: Font
    public var color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        startDate: Date,
        endDate: Date? = nil,
        isActive: Bool,
        font: Font = GravTypography.monoCaption,
        color: Color = GravPalette.inkSecondary
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = isActive
        self.font = font
        self.color = color
    }

    public var body: some View {
        if isActive && endDate == nil {
            TimelineView(.periodic(from: startDate, by: 1.0)) { context in
                let elapsed = max(0, context.date.timeIntervalSince(startDate))
                timerLabel(for: elapsed)
            }
        } else {
            let resolvedEnd = endDate ?? startDate
            let elapsed = max(0, resolvedEnd.timeIntervalSince(startDate))
            timerLabel(for: elapsed)
        }
    }

    private func timerLabel(for elapsed: TimeInterval) -> some View {
        Text(Self.formatDuration(elapsed))
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : GravMotion.numericTick, value: Int(elapsed))
    }

    /// Formats elapsed durations concisely (`08s`, `1m 12s`, `1h 04m`).
    public static func formatDuration(_ seconds: TimeInterval) -> String {
        let clamped = max(0, Int(seconds.rounded(.down)))
        if clamped < 60 {
            return String(format: "%02ds", clamped)
        }
        let minutes = clamped / 60
        let remainderSeconds = clamped % 60
        if minutes < 60 {
            return "\(minutes)m \(String(format: "%02d", remainderSeconds))s"
        }
        let hours = minutes / 60
        let remainderMinutes = minutes % 60
        return "\(hours)h \(String(format: "%02d", remainderMinutes))m"
    }
}
