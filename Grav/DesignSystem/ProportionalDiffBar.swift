import SwiftUI

/// Pure proportional ratio calculator for `+N / -M` micro-diff bars.
public struct ProportionalDiffMetrics: Sendable, Equatable {
    public let added: Int
    public let removed: Int
    public let addedRatio: Double
    public let removedRatio: Double

    public init(added: Int, removed: Int, minimumSegmentRatio: Double = 0.14) {
        let clampedAdded = max(0, added)
        let clampedRemoved = max(0, removed)
        self.added = clampedAdded
        self.removed = clampedRemoved

        let total = clampedAdded + clampedRemoved
        guard total > 0 else {
            self.addedRatio = 0
            self.removedRatio = 0
            return
        }

        if clampedAdded > 0 && clampedRemoved > 0 {
            let rawAdded = Double(clampedAdded) / Double(total)
            let clampedMin = min(max(minimumSegmentRatio, 0.05), 0.45)
            let adjustedAdded = min(max(rawAdded, clampedMin), 1.0 - clampedMin)
            self.addedRatio = adjustedAdded
            self.removedRatio = 1.0 - adjustedAdded
        } else if clampedAdded > 0 {
            self.addedRatio = 1.0
            self.removedRatio = 0.0
        } else {
            self.addedRatio = 0.0
            self.removedRatio = 1.0
        }
    }

    public var total: Int {
        added + removed
    }

    public var isEmpty: Bool {
        total == 0
    }
}

/// Compact horizontal proportional `+N / -M` micro-diff bar in Emerald (`#34D399`)
/// and Coral (`#F87171`) paired with tabular monospaced counters.
public struct ProportionalDiffBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var added: Int
    public var removed: Int
    public var barWidth: CGFloat
    public var barHeight: CGFloat
    public var showCounters: Bool
    public var adaptive: Bool

    public init(
        added: Int,
        removed: Int,
        barWidth: CGFloat = 44,
        barHeight: CGFloat = 4,
        showCounters: Bool = true,
        adaptive: Bool = false
    ) {
        self.added = added
        self.removed = removed
        self.barWidth = barWidth
        self.barHeight = barHeight
        self.showCounters = showCounters
        self.adaptive = adaptive
    }

    public var body: some View {
        let metrics = ProportionalDiffMetrics(added: added, removed: removed)
        let palette = GravAdaptivePalette(colorScheme: adaptive ? colorScheme : .dark)
        let emeraldInk = adaptive ? palette.emeraldText : GravPalette.emerald
        let coralInk = adaptive ? palette.coralText : GravPalette.coral

        HStack(spacing: GravSpacing.xs) {
            if showCounters {
                HStack(spacing: GravSpacing.xxs) {
                    if metrics.added > 0 || metrics.isEmpty {
                        Text("+\(metrics.added)")
                            .font(GravTypography.monoCaption)
                            .monospacedDigit()
                            .foregroundStyle(metrics.added > 0 ? emeraldInk : palette.inkQuaternary)
                            .contentTransition(reduceMotion ? .identity : .numericText())
                    }

                    if metrics.removed > 0 {
                        Text("-\(metrics.removed)")
                            .font(GravTypography.monoCaption)
                            .monospacedDigit()
                            .foregroundStyle(coralInk)
                            .contentTransition(reduceMotion ? .identity : .numericText())
                    }
                }
            }

            diffTrack(metrics: metrics, palette: palette)
                .frame(width: barWidth, height: barHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metrics.added) lines added, \(metrics.removed) lines removed")
    }

    @ViewBuilder
    private func diffTrack(
        metrics: ProportionalDiffMetrics,
        palette: GravAdaptivePalette
    ) -> some View {
        let cornerRadius = barHeight / 2

        if metrics.isEmpty {
            RoundedRectangle.grav(cornerRadius)
                .fill(palette.fillBase)
        } else if metrics.added > 0 && metrics.removed > 0 {
            let gap: CGFloat = 1.5
            let usableWidth = max(0, barWidth - gap)
            let addedWidth = usableWidth * metrics.addedRatio
            let removedWidth = usableWidth * metrics.removedRatio

            HStack(spacing: gap) {
                RoundedRectangle.grav(cornerRadius)
                    .fill(GravPalette.emerald)
                    .frame(width: addedWidth, height: barHeight)

                RoundedRectangle.grav(cornerRadius)
                    .fill(GravPalette.coral)
                    .frame(width: removedWidth, height: barHeight)
            }
            .animation(reduceMotion ? nil : GravMotion.numericTick, value: metrics)
        } else if metrics.added > 0 {
            RoundedRectangle.grav(cornerRadius)
                .fill(GravPalette.emerald)
        } else {
            RoundedRectangle.grav(cornerRadius)
                .fill(GravPalette.coral)
        }
    }
}
