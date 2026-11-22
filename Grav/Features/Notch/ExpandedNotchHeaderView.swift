import SwiftUI

/// Clean, chrome-minimal header bar for Grav's expanded Notch HUD.
/// Zero nested capsules, zero emojis, zero logo halo clutter — pure Apple × Raycast hierarchy
/// with strict layout priority so long conversation titles never crowd token counters or controls.
public struct ExpandedNotchHeaderView: View {
    public var store: AntigravityTelemetryStore
    public var preferences: PreferencesStore
    public var onOpenSettings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHoveringLogo = false
    @State private var isHoveringSession = false
    @State private var isShowingMetricsPopover = false

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
        store.isPaused ? "Paused" : store.state.label
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
            Spacer(minLength: 10)
            rightCluster
                .layoutPriority(1)
        }
        .frame(height: 26)
    }

    // MARK: - Left Cluster (Pure Grav Logo · Borderless Session Picker · Quiet Status)

    private var leftCluster: some View {
        HStack(spacing: 7) {
            Button {
                store.activateAntigravityApp()
            } label: {
                GravAppIconTile(size: 20)
                    .scaleEffect(!reduceMotion && isHoveringLogo ? 1.06 : 1.0)
                    .animation(reduceMotion ? nil : GravMotion.subtleFade, value: isHoveringLogo)
            }
            .buttonStyle(.plain)
            .onHover { isHoveringLogo = $0 }
            .help("Focus Antigravity")
            .accessibilityLabel("Open Antigravity")

            sessionSwitcherMenu

            inlineStatusReadout
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

            Divider()

            Button("Focus Antigravity") {
                store.activateAntigravityApp()
            }

            if store.activeSession != nil {
                Button("Reveal Transcript in Finder") {
                    store.revealActiveTranscriptInFinder()
                }
            }

            if store.state.isActive {
                Button("Mark Idle") {
                    store.forceSettleIdle()
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(cleanActiveSessionTitle)
                    .font(.system(size: 12, weight: .medium))
                    .tracking(-0.18)
                    .foregroundStyle(
                        store.activeSession != nil ? Color.white.opacity(0.92) : GravPalette.inkTertiary
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 176, alignment: .leading)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(isHoveringSession ? 0.68 : 0.36))
            }
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHoveringSession ? Color.white.opacity(0.07) : Color.clear)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .onHover { isHoveringSession = $0 }
        .animation(reduceMotion ? nil : GravMotion.subtleFade, value: isHoveringSession)
        .help("Switch Antigravity session")
        .accessibilityLabel("Active session: \(cleanActiveSessionTitle)")
    }

    private var inlineStatusReadout: some View {
        HStack(spacing: 4.5) {
            NotchSemanticDot(
                color: stateDotColor,
                size: 5,
                isPulsing: isActivelyStreaming
            )
            Text(stateLabel)
                .font(.system(size: 11, weight: .medium))
                .tracking(-0.1)
                .foregroundStyle(isActivelyStreaming ? Color.white.opacity(0.76) : Color.white.opacity(0.40))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.leading, 2)
        .fixedSize(horizontal: true, vertical: false)
        .animation(reduceMotion ? nil : GravMotionSpec.settle.animation, value: stateLabel)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Telemetry state: \(stateLabel)")
    }

    // MARK: - Right Cluster (Bare Tabular Tokens · Ghost Controls)

    private var rightCluster: some View {
        HStack(spacing: 4) {
            tokenMetricsReadout

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 0.5, height: 11)
                .padding(.horizontal, 3)

            pauseTelemetryButton
            pinNotchButton
            settingsButton
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var pauseTelemetryButton: some View {
        Button {
            GravOnboardingWelcomeAudio.shared.playButtonTap()
            let nextPaused = !store.isPaused
            preferences.isTelemetryPaused = nextPaused
            store.setPaused(nextPaused)
        } label: {
            Image(systemName: store.isPaused ? "play.fill" : "pause")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(
                    store.isPaused ? GravPalette.fileEdit : Color.white.opacity(0.52)
                )
                .frame(width: 22, height: 22)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
        }
        .buttonStyle(NotchChromeButtonStyle(isActive: store.isPaused, cornerRadius: 6))
        .help(store.isPaused ? "Resume Telemetry (⌘P)" : "Pause Telemetry (⌘P)")
        .accessibilityLabel(store.isPaused ? "Resume Telemetry" : "Pause Telemetry")
    }

    private var tokenMetricsReadout: some View {
        let metrics = store.tokenMetrics
        let inputText = TokenMetrics.formatCompact(metrics.inputTokens)
        let cacheText = TokenMetrics.formatCompact(metrics.cacheReadTokens)
        let outputText = TokenMetrics.formatCompact(metrics.outputTokens)

        return Button {
            GravOnboardingWelcomeAudio.shared.playButtonTap()
            isShowingMetricsPopover.toggle()
        } label: {
            HStack(spacing: 7) {
                tokenPair(prefix: "↓", value: inputText, color: Color.white.opacity(0.54))
                tokenPair(prefix: "↑", value: outputText, color: GravPalette.glacialCyan.opacity(0.92))
            }
            .padding(.horizontal, 6)
            .frame(height: 22)
        }
        .buttonStyle(NotchChromeButtonStyle(isActive: isShowingMetricsPopover, cornerRadius: 6))
        .fixedSize(horizontal: true, vertical: false)
        .popover(isPresented: $isShowingMetricsPopover, arrowEdge: .bottom) {
            sessionTelemetryPopover
        }
        .help(
            "Click for session telemetry breakdown — In: \(metrics.inputTokens.formatted()) · Cache: \(metrics.cacheReadTokens.formatted()) · Out: \(metrics.outputTokens.formatted())"
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Tokens: \(inputText) input, \(cacheText) cached, \(outputText) output"
        )
    }

    private var sessionTelemetryPopover: some View {
        let metrics = store.tokenMetrics
        let cachePercent = Int((metrics.cacheHitRate * 100.0).rounded())

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Session Telemetry")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.94))
                Spacer()
                if let model = store.activeModel, !model.isEmpty {
                    Text(model)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .lineLimit(1)
                }
            }

            VStack(spacing: 6) {
                metricRow("Input Tokens", metrics.inputTokens.formatted(), tint: Color.white.opacity(0.84))
                metricRow("Cache Read", "\(metrics.cacheReadTokens.formatted()) (\(cachePercent)%)", tint: GravPalette.emerald)
                metricRow("Output Tokens", metrics.outputTokens.formatted(), tint: GravPalette.glacialCyan)
            }

            // Whisper-thin cache efficiency bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))
                    Capsule(style: .continuous)
                        .fill(GravPalette.emerald.opacity(0.85))
                        .frame(width: max(4, geo.size.width * metrics.cacheHitRate))
                }
            }
            .frame(height: 3)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)

            HStack(spacing: 14) {
                compactCounter("Replies", store.responses.count)
                compactCounter("Files", store.fileChanges.count)
                compactCounter("Commands", store.commands.count)
                Spacer()
            }
        }
        .padding(12)
        .frame(width: 244)
        .background(Color(red: 0.08, green: 0.09, blue: 0.11))
        .environment(\.colorScheme, .dark)
    }

    private func metricRow(_ label: String, _ value: String, tint: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.50))
            Spacer()
            Text(value)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }

    private func compactCounter(_ label: String, _ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(count)")
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.90))
            Text(label)
                .font(.system(size: 9.5, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.42))
        }
    }

    private func tokenPair(prefix: String, value: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(prefix)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(color.opacity(0.62))
            Text(value)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : GravMotion.numericTick, value: value)
        }
    }

    private var pinNotchButton: some View {
        Button {
            GravOnboardingWelcomeAudio.shared.playButtonTap()
            preferences.isNotchPinned.toggle()
        } label: {
            Image(systemName: preferences.isNotchPinned ? "pin.fill" : "pin")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(
                    preferences.isNotchPinned ? GravPalette.glacialCyan : Color.white.opacity(0.52)
                )
                .frame(width: 22, height: 22)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
        }
        .buttonStyle(NotchChromeButtonStyle(isActive: preferences.isNotchPinned, cornerRadius: 6))
        .help(preferences.isNotchPinned ? "Unpin Notch HUD (⌘L)" : "Pin Notch HUD Open (⌘L)")
        .accessibilityLabel(preferences.isNotchPinned ? "Unpin Notch" : "Pin Notch Open")
    }

    private var settingsButton: some View {
        Button {
            GravOnboardingWelcomeAudio.shared.playButtonTap()
            onOpenSettings()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.52))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(NotchChromeButtonStyle(cornerRadius: 6))
        .help("Grav Settings")
        .accessibilityLabel("Open Grav Settings")
    }
}
