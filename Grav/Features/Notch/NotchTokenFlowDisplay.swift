import SwiftUI

/// Precision industrial-minimal In/Out token telemetry strip for Grav's Notch HUD.
/// Anti-AI-slop design: zero neon halos, zero chunky pill borders — pure tabular Swiss odometers
/// with subtle directional arrow micro-nudges on real token ticks.
public struct NotchTokenFlowDisplay: View {
    public enum Style: Sendable {
        /// Expanded Notch Header readout: clean `↓In · ↑Out` rolling odometers.
        case expandedHeader
        /// Collapsed Notch Pill readout: ultra-crisp `↓In  ↑Out` (or compact `↑Out` when active/tight).
        case collapsedIdle(compact: Bool)
        /// Collapsed Notch Active Streaming readout: `↑Out` live output odometer alongside status label.
        case collapsedStreamingOutput
    }

    public let metrics: TokenMetrics
    public let isStreaming: Bool
    public let style: Style
    public let reduceMotion: Bool

    @State private var inputPulse: Bool = false
    @State private var outputPulse: Bool = false
    @State private var inputPulseTask: Task<Void, Never>?
    @State private var outputPulseTask: Task<Void, Never>?

    public init(
        metrics: TokenMetrics,
        isStreaming: Bool,
        style: Style,
        reduceMotion: Bool
    ) {
        self.metrics = metrics
        self.isStreaming = isStreaming
        self.style = style
        self.reduceMotion = reduceMotion
    }

    private var formattedInput: String {
        TokenMetrics.formatCompact(metrics.inputTokens)
    }

    private var formattedOutput: String {
        TokenMetrics.formatCompact(metrics.outputTokens)
    }

    public var body: some View {
        Group {
            switch style {
            case .expandedHeader:
                expandedHeaderBody
            case let .collapsedIdle(compact):
                collapsedIdleBody(compact: compact)
            case .collapsedStreamingOutput:
                collapsedStreamingBody
            }
        }
        .onChange(of: metrics.inputTokens) { oldVal, newVal in
            guard newVal > oldVal, !reduceMotion else { return }
            triggerInputPulse()
        }
        .onChange(of: metrics.outputTokens) { oldVal, newVal in
            guard newVal > oldVal, !reduceMotion else { return }
            triggerOutputPulse()
        }
        .onDisappear {
            inputPulseTask?.cancel()
            outputPulseTask?.cancel()
        }
    }

    // MARK: - Expanded Header (Clean Kinetic Odometer Pair)

    private var expandedHeaderBody: some View {
        HStack(spacing: 7) {
            odometerPair(
                arrow: "↓",
                value: formattedInput,
                baseColor: Color.white.opacity(0.58),
                activeColor: Color.white.opacity(0.95),
                isPulsing: inputPulse,
                nudgeY: 1.5,
                fontSize: 10.5
            )

            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 2, height: 2)

            odometerPair(
                arrow: "↑",
                value: formattedOutput,
                baseColor: GravPalette.glacialCyan.opacity(0.90),
                activeColor: Color(red: 0.54, green: 0.94, blue: 1.0),
                isPulsing: outputPulse,
                nudgeY: -1.5,
                fontSize: 10.5
            )
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Collapsed Pill Idle (`↓In  ↑Out` Rolling Odometer)

    private func collapsedIdleBody(compact: Bool) -> some View {
        HStack(spacing: compact ? 4 : 6) {
            if !compact {
                odometerPair(
                    arrow: "↓",
                    value: formattedInput,
                    baseColor: Color.white.opacity(0.44),
                    activeColor: Color.white.opacity(0.86),
                    isPulsing: inputPulse,
                    nudgeY: 1.2,
                    fontSize: 10
                )
            }

            odometerPair(
                arrow: "↑",
                value: formattedOutput,
                baseColor: GravPalette.glacialCyan.opacity(compact ? 0.72 : 0.80),
                activeColor: Color(red: 0.56, green: 0.94, blue: 1.0),
                isPulsing: outputPulse,
                nudgeY: -1.2,
                fontSize: 10
            )
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Collapsed Pill Active Streaming Output

    private var collapsedStreamingBody: some View {
        odometerPair(
            arrow: "↑",
            value: formattedOutput,
            baseColor: GravPalette.glacialCyan.opacity(0.86),
            activeColor: Color(red: 0.62, green: 0.96, blue: 1.0),
            isPulsing: outputPulse,
            nudgeY: -1.4,
            fontSize: 10
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Shared Kinetic Odometer Pair

    private func odometerPair(
        arrow: String,
        value: String,
        baseColor: Color,
        activeColor: Color,
        isPulsing: Bool,
        nudgeY: CGFloat,
        fontSize: CGFloat
    ) -> some View {
        let color = isPulsing ? activeColor : baseColor
        return HStack(spacing: 1.5) {
            Text(arrow)
                .font(.system(size: fontSize - 1.5, weight: .semibold))
                .foregroundStyle(color.opacity(isPulsing ? 1.0 : 0.64))
                .offset(y: isPulsing ? nudgeY : 0)

            Text(value)
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(reduceMotion ? .identity : .numericText(countsDown: false))
                .animation(reduceMotion ? nil : .spring(duration: 0.34, bounce: 0.12), value: value)
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.24, bounce: 0.25), value: isPulsing)
    }

    private func triggerInputPulse() {
        inputPulseTask?.cancel()
        inputPulse = true
        inputPulseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            inputPulse = false
        }
    }

    private func triggerOutputPulse() {
        outputPulseTask?.cancel()
        outputPulse = true
        outputPulseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            outputPulse = false
        }
    }
}
