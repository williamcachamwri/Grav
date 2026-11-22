import SwiftUI

/// Top telemetry header bar inside Grav's expanded Notch HUD.
public struct ExpandedNotchHeaderView: View {
    public var store: AntigravityTelemetryStore
    public var preferences: PreferencesStore
    public var onOpenSettings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        store: AntigravityTelemetryStore,
        preferences: PreferencesStore,
        onOpenSettings: @escaping () -> Void
    ) {
        self.store = store
        self.preferences = preferences
        self.onOpenSettings = onOpenSettings
    }

    private var stateLabel: String {
        if store.isPaused {
            return "Paused"
        }
        return store.state.label
    }

    private var stateDotColor: Color {
        NotchTelemetryHelpers.color(for: store.state, isPaused: store.isPaused)
    }

    private var isActivelyStreaming: Bool {
        !store.isPaused && store.state.isActive
    }

    public var body: some View {
        HStack(spacing: GravSpacing.sm) {
            leftCluster
            Spacer(minLength: GravSpacing.sm)
            rightCluster
        }
        .frame(height: 28)
    }

    // MARK: - Left Cluster

    private var leftCluster: some View {
        HStack(spacing: GravSpacing.sm) {
            Button {
                store.activateAntigravityApp()
            } label: {
                ZStack {
                    OpticalBreathingRing(
                        isActive: isActivelyStreaming,
                        tint: GravPalette.glacialCyan,
                        diameter: 23,
                        lineWidth: 0.9
                    )
                    AntigravityLogoView(icon: store.antigravityIcon, size: 18)
                }
                .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Focus Antigravity")
            .accessibilityLabel("Open Antigravity")

            sessionSwitcherMenu

            HStack(spacing: 4) {
                NotchSemanticDot(
                    color: stateDotColor,
                    size: 6,
                    isPulsing: isActivelyStreaming
                )
                Text(stateLabel)
                    .font(GravTypography.caption)
                    .foregroundStyle(isActivelyStreaming ? GravPalette.inkPrimary : GravPalette.inkTertiary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Telemetry state: \(stateLabel)")
        }
    }

    private var sessionSwitcherMenu: some View {
        Menu {
            if store.sessions.isEmpty {
                Text("No active Antigravity sessions")
            } else {
                ForEach(store.sessions) { session in
                    Button {
                        store.selectSession(session)
                    } label: {
                        HStack {
                            Text(session.title)
                            if session.id == store.activeSession?.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(store.activeSession?.title ?? "No Session")
                    .font(GravTypography.caption)
                    .foregroundStyle(
                        store.activeSession != nil ? GravPalette.inkPrimary : GravPalette.inkTertiary
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 142, alignment: .leading)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(GravPalette.inkTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .notchGlassSurface(.subtle, cornerRadius: GravRadius.controlS)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: true, vertical: false)
        .help("Switch Antigravity conversation session")
        .accessibilityLabel("Active session: \(store.activeSession?.title ?? "None")")
    }

    // MARK: - Right Cluster

    private var rightCluster: some View {
        HStack(spacing: GravSpacing.xs) {
            tokenMetricsReadout

            pinNotchButton

            settingsButton
        }
    }

    private var tokenMetricsReadout: some View {
        let metrics = store.tokenMetrics
        let inputText = TokenMetrics.formatCompact(metrics.inputTokens)
        let cacheText = TokenMetrics.formatCompact(metrics.cacheReadTokens)
        let outputText = TokenMetrics.formatCompact(metrics.outputTokens)

        return HStack(spacing: 3) {
            tokenSegment(value: inputText, color: GravPalette.inkSecondary)
            Text("/")
                .font(GravTypography.monoMicro)
                .foregroundStyle(GravPalette.inkQuaternary)
            tokenSegment(value: cacheText, color: GravPalette.inkTertiary)
            Text("/")
                .font(GravTypography.monoMicro)
                .foregroundStyle(GravPalette.inkQuaternary)
            tokenSegment(value: outputText, color: GravPalette.glacialCyan.opacity(0.92))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .notchGlassSurface(.subtle, cornerRadius: GravRadius.controlXS)
        .help(
            "Tokens (in / cache / out): \(metrics.inputTokens.formatted()) / \(metrics.cacheReadTokens.formatted()) / \(metrics.outputTokens.formatted())"
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Tokens: \(inputText) input, \(cacheText) cached, \(outputText) output"
        )
    }

    private func tokenSegment(value: String, color: Color) -> some View {
        Text(value)
            .font(GravTypography.monoMicro)
            .monospacedDigit()
            .foregroundStyle(color)
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : GravMotion.numericTick, value: value)
    }

    private var pinNotchButton: some View {
        Button {
            preferences.isNotchPinned.toggle()
        } label: {
            Image(systemName: preferences.isNotchPinned ? "pin.fill" : "pin")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(
                    preferences.isNotchPinned ? GravPalette.glacialTeal : GravPalette.inkTertiary
                )
                .frame(width: 24, height: 24)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
        }
        .buttonStyle(NotchChromeButtonStyle(isActive: preferences.isNotchPinned, cornerRadius: GravRadius.controlXS))
        .help(preferences.isNotchPinned ? "Unpin Notch HUD" : "Pin Notch HUD Open")
        .accessibilityLabel(preferences.isNotchPinned ? "Unpin Notch" : "Pin Notch Open")
    }

    private var settingsButton: some View {
        Button {
            onOpenSettings()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(GravPalette.inkTertiary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(NotchChromeButtonStyle(cornerRadius: GravRadius.controlXS))
        .help("Grav Settings")
        .accessibilityLabel("Open Grav Settings")
    }
}
