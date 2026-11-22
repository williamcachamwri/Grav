import NotchKit
import SwiftUI

/// Collapsed 120Hz Dynamic Island / Notch pill surface.
///
/// Strict industrial minimalism — zero translucent badge spam, zero outer icon halos:
/// - On physical-notch MacBooks (`hasPhysicalNotch == true`): flanks the camera housing with the
///   exact Grav app icon + bare harmonic waveform on the left and a single clean telemetry readout
///   on the right.
/// - On standalone displays (`hasPhysicalNotch == false`): renders one cohesive, balanced Dynamic
///   Island pill with zero artificial center gap.
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

    public var body: some View {
        let hasPhysicalNotch = presenter.geometry.hasPhysicalNotch
        let pillHeight = presenter.geometry.collapsedHeight

        Group {
            if hasPhysicalNotch {
                NotchCutoutLayout(
                    cutoutWidth: presenter.geometry.notchWidth,
                    gutterWidth: presenter.collapsedGutterWidth,
                    pillHeight: pillHeight,
                    edgeInset: 11,
                    alignment: .center
                ) {
                    leadingWing(compact: true)
                } trailing: {
                    trailingWing(compact: true)
                }
            } else {
                HStack(spacing: 10) {
                    leadingWing(compact: false)
                    Spacer(minLength: 6)
                    trailingWing(compact: false)
                }
                .padding(.horizontal, 12)
                .frame(width: presenter.collapsedSurfaceWidth, height: pillHeight)
            }
        }
        .frame(height: pillHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityStatusLabel)
    }

    private var islandSpring: Animation {
        .spring(duration: 0.34, bounce: 0.14)
    }

    // MARK: - Leading Wing (Pure Grav Logo + Bare Optical Activity Cue)

    private func leadingWing(compact: Bool) -> some View {
        HStack(spacing: 7) {
            Button {
                store.activateAntigravityApp()
            } label: {
                GravAppIconTile(size: compact ? 18 : 19)
                    .opacity(store.isPaused ? 0.42 : 1.0)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Antigravity")

            leadingActivityCue(compact: compact)
        }
        .animation(reduceMotion ? nil : islandSpring, value: effectiveState)
        .animation(reduceMotion ? nil : GravMotion.subtleFade, value: store.isPaused)
    }

    @ViewBuilder
    private func leadingActivityCue(compact: Bool) -> some View {
        if store.isPaused {
            Image(systemName: "pause.fill")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.38))
                .transition(.opacity)
        } else {
            switch effectiveState {
            case .thinking:
                NotchBars(thinkingWaveStyle)
                    .transition(signalTransition)

            case let .editing(event):
                let color = NotchTelemetryHelpers.color(for: event.kind)
                let symbol = event.kind == .delete ? "trash" : (event.kind == .create ? "plus" : "pencil")
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    .transition(signalTransition)

            case .runningCommand:
                NotchBars(commandWaveStyle)
                    .transition(signalTransition)

            case .idle:
                if !compact {
                    Text("Grav")
                        .font(.system(size: 11.5, weight: .medium))
                        .tracking(-0.2)
                        .foregroundStyle(Color.white.opacity(0.78))
                        .transition(.opacity)
                }
            }
        }
    }

    // MARK: - Trailing Wing (Single Crisp Primary Telemetry Signal)

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
        .animation(reduceMotion ? nil : islandSpring, value: effectiveState)
    }

    private func thinkingTrailingSignal(compact: Bool) -> some View {
        HStack(spacing: 6) {
            if !compact {
                Text(cleanThinkingSnippet)
                    .font(.system(size: 11.5, weight: .medium))
                    .tracking(-0.15)
                    .foregroundStyle(Color.white.opacity(0.84))
                    .lineLimit(1)
                    .mask(trailingEdgeFadeMask)
            } else {
                Text("Thinking")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(-0.15)
                    .foregroundStyle(Color.white.opacity(0.86))
                    .lineLimit(1)
            }

            ActiveElapsedTimerText(
                startDate: store.currentThinking?.startedAt ?? Date(),
                endDate: nil,
                isActive: true,
                font: .system(size: 10.5, weight: .medium, design: .monospaced),
                color: GravPalette.thinking
            )
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var cleanThinkingSnippet: String {
        guard let raw = store.currentThinking?.text else { return "Thinking" }
        let single = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return single.isEmpty ? "Thinking" : single
    }

    private func editingTrailingSignal(for event: FileChangeEvent) -> some View {
        HStack(spacing: 6) {
            Text(event.basename)
                .font(.system(size: 11.5, weight: .medium))
                .tracking(-0.15)
                .foregroundStyle(Color.white.opacity(0.90))
                .lineLimit(1)
                .truncationMode(.middle)

            if event.kind == .delete {
                Text("DEL")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(GravPalette.coral)
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                HStack(spacing: 3.5) {
                    if event.addedLines > 0 || event.removedLines == 0 {
                        Text("+\(event.addedLines)")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(GravPalette.emerald)
                            .contentTransition(reduceMotion ? .identity : .numericText())
                    }
                    if event.removedLines > 0 {
                        Text("-\(event.removedLines)")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(GravPalette.coral)
                            .contentTransition(reduceMotion ? .identity : .numericText())
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func commandTrailingSignal(for command: CommandExecutionEvent, compact: Bool) -> some View {
        HStack(spacing: 6) {
            Text(command.displayTitle)
                .font(.system(size: 11.5, weight: .medium))
                .tracking(-0.15)
                .foregroundStyle(Color.white.opacity(0.88))
                .lineLimit(1)
                .mask(trailingEdgeFadeMask)

            if !compact {
                ActiveElapsedTimerText(
                    startDate: command.startedAt,
                    endDate: command.completedAt,
                    isActive: command.status == .running,
                    font: .system(size: 10.5, weight: .medium, design: .monospaced),
                    color: Color.white.opacity(0.48)
                )
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func idleTrailingSignal(compact: Bool) -> some View {
        HStack(spacing: 6) {
            if !compact && store.tokenMetrics.totalTokens > 0 {
                Text(TokenMetrics.formatCompact(store.tokenMetrics.totalTokens))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.40))
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }

            Circle()
                .fill(store.connectionStatus.isAppRunning ? GravPalette.emerald.opacity(0.82) : GravPalette.idleDot)
                .frame(width: 5, height: 5)
        }
        .padding(.trailing, 1)
    }

    // MARK: - Subtle Masks, Transitions & Bare Harmonic Waveforms

    private var trailingEdgeFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0.0),
                .init(color: .black, location: 0.85),
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
            insertion: .opacity.combined(with: .offset(y: 3)),
            removal: .opacity.combined(with: .offset(y: -3))
        )
    }

    private var thinkingWaveStyle: NotchBarsStyle {
        if reduceMotion {
            return .steady([0.38, 0.85, 0.55, 0.92], barWidth: 1.6, spacing: 1.7, height: 10, tint: GravPalette.thinking)
        }
        return .wave(
            count: 4,
            low: 0.24,
            high: 1.0,
            barWidth: 1.6,
            spacing: 1.7,
            height: 10,
            period: 0.72,
            stagger: 0.13,
            tint: GravPalette.thinking
        )
    }

    private var commandWaveStyle: NotchBarsStyle {
        if reduceMotion {
            return .steady([0.45, 0.9, 0.55], barWidth: 1.6, spacing: 1.7, height: 9.5, tint: Color.white.opacity(0.85))
        }
        return .wave(
            count: 3,
            low: 0.26,
            high: 1.0,
            barWidth: 1.6,
            spacing: 1.7,
            height: 9.5,
            period: 0.56,
            stagger: 0.12,
            tint: Color.white.opacity(0.85)
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
