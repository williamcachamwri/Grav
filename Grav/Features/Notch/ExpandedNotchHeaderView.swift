import SwiftUI

/// Top telemetry header bar inside Grav's expanded Notch HUD.
/// Designed with strict layout priority so the conversation selector never crushes the
/// right-hand token telemetry pill or action controls.
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
        HStack(spacing: 8) {
            leftCluster
            Spacer(minLength: 8)
            rightCluster
                .layoutPriority(1)
        }
        .frame(height: 26)
    }

    // MARK: - Left Cluster

    private var leftCluster: some View {
        HStack(spacing: 7) {
            Button {
                store.activateAntigravityApp()
            } label: {
                ZStack {
                    if isActivelyStreaming && !reduceMotion {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(stateDotColor.opacity(0.55), lineWidth: 0.8)
                            .frame(width: 23, height: 23)
                    }
                    GravAppIconTile(size: 19)
                }
                .frame(width: 23, height: 23)
            }
            .buttonStyle(.plain)
            .help("Focus Antigravity")
            .accessibilityLabel("Open Antigravity")

            sessionSwitcherMenu

            liveStatusCapsule
        }
    }

    private var cleanActiveSessionTitle: String {
        guard let raw = store.activeSession?.title else { return "No Session" }
        let cleaned = raw
            .replacingOccurrences(of: "<USER_REQUEST>", with: "")
            .replacingOccurrences(of: "</USER_REQUEST>", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Active Session" : cleaned
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
            HStack(spacing: 4.5) {
                Text(cleanActiveSessionTitle)
                    .font(.system(size: 11.5, weight: .medium))
                    .tracking(-0.15)
                    .foregroundStyle(
                        store.activeSession != nil ? Color.white.opacity(0.92) : GravPalette.inkTertiary
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 164, alignment: .leading)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(GravPalette.inkTertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.055))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.11), lineWidth: 0.5)
                    )
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Switch Antigravity conversation session")
        .accessibilityLabel("Active session: \(cleanActiveSessionTitle)")
    }

    private var liveStatusCapsule: some View {
        HStack(spacing: 4.5) {
            NotchSemanticDot(
                color: stateDotColor,
                size: 5.5,
                isPulsing: isActivelyStreaming
            )
            Text(stateLabel)
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(-0.1)
                .foregroundStyle(isActivelyStreaming ? Color.white.opacity(0.95) : GravPalette.inkTertiary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(
            Capsule(style: .continuous)
                .fill(isActivelyStreaming ? stateDotColor.opacity(0.12) : Color.white.opacity(0.04))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isActivelyStreaming ? stateDotColor.opacity(0.25) : Color.white.opacity(0.08),
                            lineWidth: 0.5
                        )
                )
        )
        .fixedSize(horizontal: true, vertical: false)
        .animation(reduceMotion ? nil : GravMotionSpec.settle.animation, value: stateLabel)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Telemetry state: \(stateLabel)")
    }

    // MARK: - Right Cluster

    private var rightCluster: some View {
        HStack(spacing: 5) {
            tokenMetricsReadout

            pinNotchButton

            settingsButton
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var tokenMetricsReadout: some View {
        let metrics = store.tokenMetrics
        let inputText = TokenMetrics.formatCompact(metrics.inputTokens)
        let cacheText = TokenMetrics.formatCompact(metrics.cacheReadTokens)
        let outputText = TokenMetrics.formatCompact(metrics.outputTokens)

        return HStack(spacing: 4) {
            tokenSegment(prefix: "↓", value: inputText, color: Color.white.opacity(0.78))
            Text("·")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.24))
            tokenSegment(prefix: "⚡", value: cacheText, color: Color.white.opacity(0.54))
            Text("·")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.24))
            tokenSegment(prefix: "↑", value: outputText, color: GravPalette.glacialCyan)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                )
        )
        .fixedSize(horizontal: true, vertical: false)
        .help(
            "Tokens (in / cache / out): \(metrics.inputTokens.formatted()) / \(metrics.cacheReadTokens.formatted()) / \(metrics.outputTokens.formatted())"
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Tokens: \(inputText) input, \(cacheText) cached, \(outputText) output"
        )
    }

    private func tokenSegment(prefix: String, value: String, color: Color) -> some View {
        HStack(spacing: 1.5) {
            Text(prefix)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(color.opacity(0.65))
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : GravMotion.numericTick, value: value)
        }
    }

    private var pinNotchButton: some View {
        Button {
            preferences.isNotchPinned.toggle()
        } label: {
            Image(systemName: preferences.isNotchPinned ? "pin.fill" : "pin")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(
                    preferences.isNotchPinned ? GravPalette.glacialCyan : Color.white.opacity(0.62)
                )
                .frame(width: 22, height: 22)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
        }
        .buttonStyle(NotchChromeButtonStyle(isActive: preferences.isNotchPinned, cornerRadius: 6.5))
        .help(preferences.isNotchPinned ? "Unpin Notch HUD" : "Pin Notch HUD Open")
        .accessibilityLabel(preferences.isNotchPinned ? "Unpin Notch" : "Pin Notch Open")
    }

    private var settingsButton: some View {
        Button {
            onOpenSettings()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.62))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(NotchChromeButtonStyle(cornerRadius: 6.5))
        .help("Grav Settings")
        .accessibilityLabel("Open Grav Settings")
    }
}
