import NotchKit
import SwiftUI

/// Collapsed 120Hz Dynamic Island / Notch pill surface.
///
/// - On notched MacBooks (`hasPhysicalNotch == true`): uses `NotchCutoutLayout` to flank the hardware
///   camera cutout with the 3D Grav badge + live harmonic wave on the left and real-time telemetry
///   + jewel timer/diff capsule on the right.
/// - On standalone / external displays (`hasPhysicalNotch == false`): renders a unified, full-width
///   Dynamic Island layout with zero artificial center dead zone.
public struct CollapsedNotchView: View {
    public var store: AntigravityTelemetryStore
    public var presenter: NotchPresenter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(store: AntigravityTelemetryStore, presenter: NotchPresenter) {
        self.store = store
        self.presenter = presenter
    }

    private var effectiveState: TelemetryState {
        store.isPaused ? .idle : store.state
    }

    private var activeTint: Color {
        NotchTelemetryHelpers.color(for: effectiveState, isPaused: store.isPaused)
    }

    public var body: some View {
        let hasPhysicalNotch = presenter.geometry.hasPhysicalNotch
        let pillHeight = presenter.geometry.collapsedHeight

        Group {
            if hasPhysicalNotch {
                NotchCutoutLayout(
                    cutoutWidth: presenter.geometry.notchWidth,
                    gutterWidth: presenter.collapsedGutterWidth,
                    pillHeight: pillHeight,
                    edgeInset: 12,
                    alignment: .center
                ) {
                    leadingWing(compact: true)
                } trailing: {
                    trailingWing(compact: true)
                }
            } else {
                // Standalone Dynamic Island layout: cohesive, balanced, zero center void
                HStack(spacing: 8) {
                    leadingWing(compact: false)
                    Spacer(minLength: 6)
                    trailingWing(compact: false)
                }
                .padding(.horizontal, 13)
                .frame(width: presenter.collapsedSurfaceWidth, height: pillHeight)
            }
        }
        .frame(height: pillHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityStatusLabel)
    }

    // MARK: - Leading Wing (3D Brand Mark + Live Harmonic Signal)

    private func leadingWing(compact: Bool) -> some View {
        HStack(spacing: 6) {
            Button {
                store.activateAntigravityApp()
            } label: {
                ZStack {
                    if effectiveState.isActive && !reduceMotion {
                        RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                            .strokeBorder(activeTint.opacity(0.55), lineWidth: 0.8)
                            .frame(width: 21, height: 21)
                    }

                    GravAppIconTile(size: 17)
                        .opacity(store.isPaused ? 0.55 : 1.0)
                }
                .frame(width: 21, height: 21)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Antigravity")

            leadingSignalPill(compact: compact)
        }
        .animation(reduceMotion ? nil : GravMotionSpec.morph.animation, value: effectiveState)
        .animation(reduceMotion ? nil : GravMotionSpec.settle.animation, value: store.isPaused)
    }

    @ViewBuilder
    private func leadingSignalPill(compact: Bool) -> some View {
        if store.isPaused {
            HStack(spacing: 3.5) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(GravPalette.inkTertiary)
                if !compact {
                    Text("Paused")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(GravPalette.inkTertiary)
                }
            }
            .padding(.horizontal, 5.5)
            .frame(height: 17)
            .background(Capsule(style: .continuous).fill(Color.white.opacity(0.06)))
        } else {
            switch effectiveState {
            case .thinking:
                HStack(spacing: 4) {
                    NotchBars(thinkingWaveStyle)
                }
                .padding(.horizontal, 5.5)
                .frame(height: 17)
                .background(
                    Capsule(style: .continuous)
                        .fill(GravPalette.thinking.opacity(0.14))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(GravPalette.thinking.opacity(0.28), lineWidth: 0.5)
                        )
                )
                .transition(signalTransition)

            case let .editing(event):
                let color = NotchTelemetryHelpers.color(for: event.kind)
                let symbol = event.kind == .delete ? "trash.fill" : (event.kind == .create ? "plus" : "pencil.line")
                HStack(spacing: 3.5) {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(color)
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                }
                .frame(width: 18, height: 17)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(color.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(color.opacity(0.30), lineWidth: 0.5)
                        )
                )
                .transition(signalTransition)

            case .runningCommand:
                HStack(spacing: 4) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(GravPalette.glacialCyan)
                    NotchBars(commandWaveStyle)
                }
                .padding(.horizontal, 5.5)
                .frame(height: 17)
                .background(
                    Capsule(style: .continuous)
                        .fill(GravPalette.glacialCyan.opacity(0.13))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(GravPalette.glacialCyan.opacity(0.26), lineWidth: 0.5)
                        )
                )
                .transition(signalTransition)

            case .idle:
                if !compact {
                    Text("Grav")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .tracking(-0.2)
                        .foregroundStyle(Color.white.opacity(0.86))
                        .transition(.opacity)
                }
            }
        }
    }

    // MARK: - Trailing Wing (Live Stream Title + Jewel Metric Capsule)

    @ViewBuilder
    private func trailingWing(compact: Bool) -> some View {
        ZStack(alignment: .trailing) {
            switch effectiveState {
            case .thinking:
                thinkingTrailingSignal(compact: compact)
                    .id("collapsed-thinking")
                    .transition(signalTransition)

            case let .editing(event):
                editingTrailingSignal(for: event)
                    .id("collapsed-edit-\(event.id)")
                    .transition(signalTransition)

            case let .runningCommand(command):
                commandTrailingSignal(for: command, compact: compact)
                    .id("collapsed-cmd-\(command.id)")
                    .transition(signalTransition)

            case .idle:
                idleTrailingSignal(compact: compact)
                    .id("collapsed-idle")
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : GravMotionSpec.morph.animation, value: effectiveState)
    }

    private func thinkingTrailingSignal(compact: Bool) -> some View {
        HStack(spacing: 6) {
            if !compact {
                let snippet = cleanThinkingSnippet
                Text(snippet)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(-0.15)
                    .foregroundStyle(Color.white.opacity(0.84))
                    .lineLimit(1)
                    .mask(trailingEdgeFadeMask)
            } else {
                Text("Thinking")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(-0.15)
                    .foregroundStyle(GravPalette.thinking.opacity(0.95))
                    .lineLimit(1)
            }

            metricCapsule(tint: GravPalette.thinking) {
                ActiveElapsedTimerText(
                    startDate: store.currentThinking?.startedAt ?? Date(),
                    endDate: nil,
                    isActive: true,
                    font: .system(size: 10, weight: .semibold, design: .monospaced),
                    color: GravPalette.thinking
                )
            }
        }
    }

    private var cleanThinkingSnippet: String {
        guard let raw = store.currentThinking?.text else { return "Reasoning…" }
        let single = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return single.isEmpty ? "Reasoning…" : single
    }

    private func editingTrailingSignal(for event: FileChangeEvent) -> some View {
        HStack(spacing: 5) {
            Text(event.basename)
                .font(.system(size: 11, weight: .medium))
                .tracking(-0.15)
                .foregroundStyle(Color.white.opacity(0.90))
                .lineLimit(1)
                .truncationMode(.middle)

            if event.kind == .delete {
                metricCapsule(tint: GravPalette.coral) {
                    Text("DEL")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(GravPalette.coral)
                }
            } else {
                HStack(spacing: 3) {
                    if event.addedLines > 0 || event.removedLines == 0 {
                        Text("+\(event.addedLines)")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(GravPalette.emerald)
                            .contentTransition(reduceMotion ? .identity : .numericText())
                    }
                    if event.removedLines > 0 {
                        Text("-\(event.removedLines)")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(GravPalette.coral)
                            .contentTransition(reduceMotion ? .identity : .numericText())
                    }
                }
                .padding(.horizontal, 5.5)
                .frame(height: 17)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                        )
                )
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func commandTrailingSignal(for command: CommandExecutionEvent, compact: Bool) -> some View {
        HStack(spacing: 5.5) {
            Text(command.displayTitle)
                .font(.system(size: 11, weight: .medium))
                .tracking(-0.15)
                .foregroundStyle(Color.white.opacity(0.88))
                .lineLimit(1)
                .mask(trailingEdgeFadeMask)

            if !compact {
                metricCapsule(tint: GravPalette.glacialCyan) {
                    ActiveElapsedTimerText(
                        startDate: command.startedAt,
                        endDate: command.completedAt,
                        isActive: command.status == .running,
                        font: .system(size: 9.5, weight: .semibold, design: .monospaced),
                        color: Color.white.opacity(0.82)
                    )
                }
            }
        }
    }

    private func idleTrailingSignal(compact: Bool) -> some View {
        HStack(spacing: 5) {
            if !compact && store.tokenMetrics.totalTokens > 0 {
                Text(TokenMetrics.formatCompact(store.tokenMetrics.totalTokens))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.46))
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }

            Circle()
                .fill(store.connectionStatus.isAppRunning ? GravPalette.emerald.opacity(0.78) : GravPalette.idleDot)
                .frame(width: 5.5, height: 5.5)
        }
        .padding(.trailing, 2)
    }

    // MARK: - Shared Micro-Components

    private func metricCapsule<Content: View>(tint: Color, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 6)
            .frame(height: 17)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.13))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(tint.opacity(0.26), lineWidth: 0.5)
                    )
            )
            .fixedSize(horizontal: true, vertical: false)
    }

    private var trailingEdgeFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0.0),
                .init(color: .black, location: 0.84),
                .init(color: .clear, location: 1.0),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var signalTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.90)).combined(with: .offset(y: 4)),
            removal: .opacity.combined(with: .scale(scale: 0.94)).combined(with: .offset(y: -4))
        )
    }

    private var thinkingWaveStyle: NotchBarsStyle {
        if reduceMotion {
            return .steady([0.4, 0.85, 0.55, 0.95], barWidth: 1.8, spacing: 1.8, height: 10, tint: GravPalette.thinking)
        }
        return .wave(
            count: 4,
            low: 0.25,
            high: 1.0,
            barWidth: 1.8,
            spacing: 1.8,
            height: 10,
            period: 0.68,
            stagger: 0.12,
            tint: GravPalette.thinking
        )
    }

    private var commandWaveStyle: NotchBarsStyle {
        if reduceMotion {
            return .steady([0.5, 0.9, 0.6], barWidth: 1.8, spacing: 1.8, height: 9.5, tint: GravPalette.glacialCyan)
        }
        return .wave(
            count: 3,
            low: 0.28,
            high: 1.0,
            barWidth: 1.8,
            spacing: 1.8,
            height: 9.5,
            period: 0.54,
            stagger: 0.11,
            tint: GravPalette.glacialCyan
        )
    }

    private var accessibilityStatusLabel: String {
        if store.isPaused {
            return "Grav telemetry paused"
        }
        switch effectiveState {
        case .idle:
            return "Grav idle"
        case .thinking:
            return "Antigravity thinking"
        case let .editing(event):
            return event.kind == .delete
                ? "Deleting \(event.basename)"
                : "Editing \(event.basename), +\(event.addedLines) -\(event.removedLines)"
        case let .runningCommand(command):
            return "Running \(command.displayTitle)"
        }
    }
}
