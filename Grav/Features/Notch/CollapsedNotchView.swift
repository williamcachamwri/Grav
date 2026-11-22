import NotchKit
import SwiftUI

/// Collapsed 120Hz notch pill surface adapting cleanly between physical MacBook notches
/// and standalone external displays via `NotchCutoutLayout`.
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
        let cutoutWidth: CGFloat = hasPhysicalNotch ? presenter.geometry.notchWidth : 0
        let gutterWidth: CGFloat = hasPhysicalNotch
            ? presenter.collapsedGutterWidth
            : presenter.collapsedSurfaceWidth / 2

        NotchCutoutLayout(
            cutoutWidth: cutoutWidth,
            gutterWidth: gutterWidth,
            pillHeight: presenter.geometry.collapsedHeight,
            edgeInset: 13,
            alignment: .center
        ) {
            leadingSlot
        } trailing: {
            trailingSlot
        }
        .frame(height: presenter.geometry.collapsedHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityStatusLabel)
    }

    // MARK: - Leading Slot

    private var leadingSlot: some View {
        HStack(spacing: 6) {
            Button {
                store.activateAntigravityApp()
            } label: {
                ZStack {
                    OpticalBreathingRing(
                        isActive: effectiveState.isActive,
                        tint: GravPalette.glacialCyan,
                        diameter: 21,
                        lineWidth: 1.0
                    )

                    AntigravityLogoView(icon: store.antigravityIcon, size: 16)
                        .opacity(store.isPaused ? 0.55 : 1.0)
                }
                .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Antigravity")

            if let symbol = leadingStatusSymbol {
                Image(systemName: symbol.name)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(symbol.tint)
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : GravMotion.subtleFade, value: effectiveState)
        .animation(reduceMotion ? nil : GravMotion.subtleFade, value: store.isPaused)
    }

    private var leadingStatusSymbol: (name: String, tint: Color)? {
        if store.isPaused {
            return ("pause.fill", GravPalette.inkQuaternary)
        }
        switch effectiveState {
        case .idle:
            return nil
        case .thinking:
            return ("waveform.path.ecg", GravPalette.thinking)
        case let .editing(event):
            if event.kind == .delete {
                return ("trash", GravPalette.coral)
            }
            return ("pencil", GravPalette.fileEdit)
        case .runningCommand:
            return ("terminal", GravPalette.commandRunning)
        }
    }

    // MARK: - Trailing Slot (Highest-Priority Live Signal)

    @ViewBuilder
    private var trailingSlot: some View {
        Group {
            switch effectiveState {
            case .thinking:
                thinkingTrailingSignal
            case let .editing(event):
                editingTrailingSignal(for: event)
            case let .runningCommand(command):
                commandTrailingSignal(for: command)
            case .idle:
                idleTrailingSignal
            }
        }
        .animation(reduceMotion ? nil : GravMotion.subtleFade, value: effectiveState)
    }

    private var thinkingTrailingSignal: some View {
        HStack(spacing: 6) {
            NotchBars(thinkingBarsStyle)

            ActiveElapsedTimerText(
                startDate: store.currentThinking?.startedAt ?? Date(),
                endDate: nil,
                isActive: true,
                font: GravTypography.monoCaption,
                color: GravPalette.inkSecondary
            )
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var thinkingBarsStyle: NotchBarsStyle {
        if reduceMotion {
            return NotchBarsStyle.steady(
                [0.35, 0.72, 0.50, 0.88],
                barWidth: 2,
                spacing: 2,
                height: 11,
                tint: GravPalette.thinking
            )
        }
        return NotchBarsStyle.wave(
            count: 4,
            low: 0.25,
            high: 1.0,
            barWidth: 2,
            spacing: 2,
            height: 11,
            period: 0.72,
            stagger: 0.12,
            tint: GravPalette.thinking
        )
    }

    private func editingTrailingSignal(for event: FileChangeEvent) -> some View {
        HStack(spacing: 4) {
            Text(event.basename)
                .font(GravTypography.monoMicro)
                .foregroundStyle(GravPalette.inkSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if event.kind == .delete {
                Text("DEL")
                    .font(GravTypography.monoMicro)
                    .foregroundStyle(GravPalette.coral.opacity(0.90))
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                HStack(spacing: 3) {
                    if event.addedLines > 0 || event.removedLines == 0 {
                        Text("+\(event.addedLines)")
                            .font(GravTypography.monoMicro)
                            .monospacedDigit()
                            .foregroundStyle(GravPalette.emerald)
                    }
                    if event.removedLines > 0 {
                        Text("-\(event.removedLines)")
                            .font(GravTypography.monoMicro)
                            .monospacedDigit()
                            .foregroundStyle(GravPalette.coral)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func commandTrailingSignal(for command: CommandExecutionEvent) -> some View {
        HStack(spacing: 5) {
            OpticalCommandSpinner(
                isActive: command.status == .running,
                size: 10,
                tint: GravPalette.commandRunning
            )

            Text(command.displayTitle)
                .font(GravTypography.monoMicro)
                .foregroundStyle(GravPalette.inkSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var idleTrailingSignal: some View {
        Circle()
            .fill(GravPalette.idleDot)
            .frame(width: 5, height: 5)
            .padding(.trailing, 2)
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
