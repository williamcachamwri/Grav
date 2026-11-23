import SwiftUI

/// Clean, chrome-minimal header bar for Grav's expanded Notch HUD.
/// Zero nested capsules, zero emojis, zero logo halo clutter — pure Apple × Raycast hierarchy
/// with strict layout priority so long conversation titles never crowd token counters or controls.
public struct ExpandedNotchHeaderView: View {
    public var store: AntigravityTelemetryStore
    public var preferences: PreferencesStore
    public var onOpenSettings: () -> Void
    public var onOpenProfile: (() -> Void)?
    public var isProfileOpen: Bool
    public var onOpenTray: (() -> Void)?
    public var isTrayOpen: Bool
    public var trayBadgeCount: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHoveringLogo = false
    @State private var isHoveringSession = false
    @State private var isShowingMetricsPopover = false

    public init(
        store: AntigravityTelemetryStore,
        preferences: PreferencesStore,
        onOpenSettings: @escaping () -> Void,
        onOpenProfile: (() -> Void)? = nil,
        isProfileOpen: Bool = false,
        onOpenTray: (() -> Void)? = nil,
        isTrayOpen: Bool = false,
        trayBadgeCount: Int = 0
    ) {
        self.store = store
        self.preferences = preferences
        self.onOpenSettings = onOpenSettings
        self.onOpenProfile = onOpenProfile
        self.isProfileOpen = isProfileOpen
        self.onOpenTray = onOpenTray
        self.isTrayOpen = isTrayOpen
        self.trayBadgeCount = trayBadgeCount
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

            if store.unreadSessionCount > 0 {
                unreadJumpPill
            }

            inlineStatusReadout
        }
    }

    private var unreadJumpPill: some View {
        Button {
            if let unreadID = store.unreadSessionIDs.first(where: { $0 != store.activeSession?.id })
                ?? store.unreadSessionIDs.first
            {
                GravOnboardingWelcomeAudio.shared.playButtonTap()
                store.selectSessionByID(unreadID)
            }
        } label: {
            HStack(spacing: 3.5) {
                Circle()
                    .fill(GravPalette.glacialCyan)
                    .frame(width: 4.5, height: 4.5)
                Text("\(store.unreadSessionCount)")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(GravPalette.glacialCyan.opacity(0.95))
            }
            .padding(.horizontal, 5.5)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(GravPalette.glacialCyan.opacity(0.14))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(GravPalette.glacialCyan.opacity(0.30), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .help("\(store.unreadSessionCount) Antigravity session(s) finished with unread replies — click to jump")
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
                            Text(store.isSessionUnread(session.id) ? "● \(session.title)" : session.title)
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
        let runningTasks = store.isPaused ? 0 : store.runningTaskCount
        let effectivePulsing = isActivelyStreaming || runningTasks > 0
        let effectiveDotColor: Color = {
            if runningTasks > 0 && !isActivelyStreaming {
                return GravPalette.glacialCyan
            }
            return stateDotColor
        }()

        return HStack(spacing: 5) {
            NotchSemanticDot(
                color: effectiveDotColor,
                size: 5,
                isPulsing: effectivePulsing
            )
            if !store.isPaused {
                switch store.state {
                case .thinking:
                    NotchThinkingShimmerLabel(
                        startDate: store.currentPhaseStartedAt,
                        compact: true,
                        font: .system(size: 11, weight: .medium),
                        reduceMotion: reduceMotion
                    )
                    .fixedSize(horizontal: true, vertical: false)
                case .replying:
                    NotchShimmerText(
                        text: "Replying",
                        font: .system(size: 11, weight: .medium),
                        tracking: -0.1,
                        baseOpacity: 0.48,
                        peakOpacity: 0.96,
                        period: 1.55,
                        reduceMotion: reduceMotion
                    )
                    .fixedSize(horizontal: true, vertical: false)
                case let .working(startedAt):
                    NotchWorkingThinkingShimmerLabel(
                        startDate: startedAt,
                        compact: true,
                        font: .system(size: 11, weight: .medium),
                        reduceMotion: reduceMotion
                    )
                    .fixedSize(horizontal: true, vertical: false)
                case .compacting:
                    NotchShimmerText(
                        text: stateLabel,
                        font: .system(size: 11, weight: .medium),
                        tracking: -0.1,
                        baseOpacity: 0.46,
                        peakOpacity: 0.94,
                        period: 1.8,
                        reduceMotion: reduceMotion
                    )
                    .fixedSize(horizontal: true, vertical: false)
                case .idle where runningTasks > 0:
                    NotchShimmerText(
                        text: runningTasks == 1 ? "1 task running" : "\(runningTasks) tasks running",
                        font: .system(size: 11, weight: .medium),
                        tracking: -0.1,
                        baseOpacity: 0.48,
                        peakOpacity: 0.96,
                        period: 1.75,
                        reduceMotion: reduceMotion
                    )
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
                default:
                    Text(stateLabel)
                        .font(.system(size: 11, weight: .medium))
                        .tracking(-0.1)
                        .foregroundStyle(isActivelyStreaming ? Color.white.opacity(0.76) : Color.white.opacity(0.40))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                if runningTasks > 0 && store.state != .idle {
                    Text("· \(runningTasks) task\(runningTasks == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(GravPalette.glacialCyan.opacity(0.88))
                        .fixedSize(horizontal: true, vertical: false)
                } else if store.activeRunningChatsCount >= 2 {
                    Button {
                        cycleToNextSession()
                    } label: {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(GravPalette.glacialCyan)
                                .frame(width: 4.5, height: 4.5)
                            Text("\(store.activeRunningChatsCount) chats")
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(GravPalette.glacialCyan.opacity(0.95))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(GravPalette.glacialCyan.opacity(0.14))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(GravPalette.glacialCyan.opacity(0.32), lineWidth: 0.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Click to cycle between parallel Antigravity chats (⌘])")
                    .fixedSize(horizontal: true, vertical: false)
                }
            } else {
                Text(stateLabel)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(-0.1)
                    .foregroundStyle(Color.white.opacity(0.40))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.leading, 2)
        .fixedSize(horizontal: true, vertical: false)
        .animation(reduceMotion ? nil : GravMotionSpec.settle.animation, value: stateLabel)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Telemetry state: \(stateLabel)")
    }

    private func cycleToNextSession() {
        guard store.sessions.count >= 2 else { return }
        GravOnboardingWelcomeAudio.shared.playButtonTap()
        if let current = store.activeSession,
           let idx = store.sessions.firstIndex(where: { $0.id == current.id })
        {
            let next = store.sessions[(idx + 1) % store.sessions.count]
            store.selectSession(next)
        } else if let first = store.sessions.first {
            store.selectSession(first)
        }
    }

    // MARK: - Right Cluster (Bare Tabular Tokens · Ghost Controls)

    private var rightCluster: some View {
        HStack(spacing: 4) {
            tokenMetricsReadout

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 0.5, height: 11)
                .padding(.horizontal, 3)

            if let onOpenTray {
                Button {
                    GravOnboardingWelcomeAudio.shared.playButtonTap()
                    onOpenTray()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: isTrayOpen ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(
                                isTrayOpen
                                    ? Color.white
                                    : (trayBadgeCount > 0 ? Color.white.opacity(0.84) : Color.white.opacity(0.54))
                            )
                            .frame(width: 22, height: 22)

                        if trayBadgeCount > 0 && !isTrayOpen {
                            Circle()
                                .fill(GravPalette.glacialCyan)
                                .frame(width: 5, height: 5)
                                .offset(x: -2.5, y: 2.5)
                        }
                    }
                }
                .buttonStyle(NotchChromeButtonStyle(isActive: isTrayOpen, cornerRadius: 6))
                .help("Drop Shelf & Prompt Queue (⌘D)")
                .accessibilityLabel("Drop Shelf and Prompt Queue")
            }

            if let onOpenProfile {
                Button {
                    GravOnboardingWelcomeAudio.shared.playButtonTap()
                    onOpenProfile()
                } label: {
                    Group {
                        if let avatarURL = store.profileSnapshot?.avatarURL {
                            AsyncImage(url: avatarURL) { phase in
                                switch phase {
                                case let .success(image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 15, height: 15)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .strokeBorder(
                                                    isProfileOpen ? Color.white.opacity(0.65) : Color.white.opacity(0.22),
                                                    lineWidth: 0.75
                                                )
                                        )
                                default:
                                    Image(systemName: "person.crop.circle")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(isProfileOpen ? Color.white : Color.white.opacity(0.58))
                                }
                            }
                        } else {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(isProfileOpen ? Color.white : Color.white.opacity(0.58))
                        }
                    }
                    .frame(width: 22, height: 22)
                }
                .buttonStyle(NotchChromeButtonStyle(isActive: isProfileOpen, cornerRadius: 6))
                .help("Account, Usage & Available Models (⌘U)")
                .accessibilityLabel("Account, Usage and Models")
            }

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
            NotchTokenFlowDisplay(
                metrics: metrics,
                isStreaming: isActivelyStreaming,
                style: .expandedHeader,
                reduceMotion: reduceMotion
            )
        }
        .buttonStyle(NotchChromeButtonStyle(isActive: isShowingMetricsPopover, cornerRadius: 6))
        .fixedSize(horizontal: true, vertical: false)
        .popover(isPresented: $isShowingMetricsPopover, arrowEdge: .bottom) {
            SessionTelemetryInspectorPopover(
                store: store,
                reduceMotion: reduceMotion
            )
        }
        .help(
            "Click for token breakdown — In: \(metrics.inputTokens.formatted()) · Cache: \(metrics.cacheReadTokens.formatted()) · Out: \(metrics.outputTokens.formatted())"
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Tokens: \(inputText) input, \(cacheText) cached, \(outputText) output"
        )
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

// MARK: - Precision Session Telemetry Inspector Popover

/// Industrial-minimal macOS inspector popover for live token composition and session activity.
/// Zero boilerplate titles, zero neon text rainbows, balanced full-width grid, and perceptual
/// 3-segment proportional bar.
private struct SessionTelemetryInspectorPopover: View {
    var store: AntigravityTelemetryStore
    var reduceMotion: Bool

    @State private var revealProgress: CGFloat = 0
    @State private var copiedFeedback = false
    @State private var copyResetTask: Task<Void, Never>?

    private var metrics: TokenMetrics { store.tokenMetrics }

    private var netAddedLines: Int {
        store.fileChanges.reduce(0) { $0 + $1.addedLines }
    }

    private var netRemovedLines: Int {
        store.fileChanges.reduce(0) { $0 + $1.removedLines }
    }

    var body: some View {
        let total = metrics.totalTokens
        let cachePercent = Int((metrics.cacheHitRate * 100.0).rounded())

        VStack(alignment: .leading, spacing: 13) {
            // 1. Hero Total + Quiet Model Identifier & Copy Action
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(TokenMetrics.formatCompact(total))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .tracking(-0.6)
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.96))
                        .contentTransition(reduceMotion ? .identity : .numericText())

                    Text("tokens")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.36))
                }

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    if let model = store.activeModel, !model.isEmpty {
                        Text(model)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.42))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Button {
                        copyMetricsSummary()
                    } label: {
                        Image(systemName: copiedFeedback ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(copiedFeedback ? GravPalette.emerald : Color.white.opacity(0.42))
                            .frame(width: 20, height: 20)
                            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    }
                    .buttonStyle(NotchChromeButtonStyle(cornerRadius: 5))
                    .help("Copy token breakdown")
                }
            }

            // 2. Perceptual 3-Segment Token Composition Bar
            tokenCompositionBar

            // 3. Calm Monochrome Tabular Breakdown Ledger
            VStack(spacing: 7) {
                ledgerRow(
                    dotColor: GravPalette.emerald.opacity(0.84),
                    label: "Cached",
                    detail: total > 0 ? "\(cachePercent)%" : nil,
                    value: metrics.cacheReadTokens.formatted()
                )
                ledgerRow(
                    dotColor: Color.white.opacity(0.86),
                    label: "Input",
                    detail: nil,
                    value: metrics.inputTokens.formatted()
                )
                ledgerRow(
                    dotColor: GravPalette.glacialCyan,
                    label: "Output",
                    detail: nil,
                    value: metrics.outputTokens.formatted()
                )
            }

            // 3b. Real Context Window Meter + Throughput (`tok/s`) & Execution Mode
            if metrics.latestContextTokens > 0 || metrics.averageTokensPerSecond != nil {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 0.5)

                VStack(alignment: .leading, spacing: 6) {
                    if metrics.latestContextTokens > 0 {
                        let ctxPct = Int((metrics.contextFillRatio * 100.0).rounded())
                        let barColor: Color = metrics.isContextNearCompaction ? GravPalette.fileEdit : GravPalette.glacialCyan

                        HStack(spacing: 6) {
                            Text("Context")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(Color.white.opacity(0.46))

                            if metrics.isContextNearCompaction {
                                Text("Near compaction")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(GravPalette.fileEdit)
                            }

                            Spacer()

                            Text(
                                verbatim: "\(TokenMetrics.formatCompact(metrics.latestContextTokens)) / \(TokenMetrics.formatCompact(metrics.contextWindowLimit)) (\(ctxPct)%)"
                            )
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(metrics.isContextNearCompaction ? GravPalette.fileEdit : Color.white.opacity(0.76))
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                                Capsule(style: .continuous)
                                    .fill(barColor.opacity(0.88))
                                    .frame(width: max(4, geo.size.width * metrics.contextFillRatio * revealProgress))
                            }
                        }
                        .frame(height: 3.5)
                    }

                    HStack(spacing: 8) {
                        if let tps = metrics.lastTurnTokensPerSecond ?? metrics.averageTokensPerSecond {
                            HStack(spacing: 4) {
                                Text("Speed")
                                    .foregroundStyle(Color.white.opacity(0.40))
                                Text(verbatim: "\(Int(tps.rounded())) tok/s")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundStyle(Color.white.opacity(0.84))
                            }
                            .font(.system(size: 10, weight: .regular))
                        }

                        Spacer()

                        Text(store.executionMode.rawValue)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.46))
                    }
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)

            // 4. Balanced Equal-Width 3-Column Activity Strip (Zero Dead Whitespace)
            HStack(spacing: 0) {
                balancedStatCell(count: store.responses.count, label: "Replies")
                verticalHairline
                balancedStatCell(count: store.fileChanges.count, label: "Files")
                verticalHairline
                balancedStatCell(count: store.commands.count, label: "Commands")
            }

            if netAddedLines > 0 || netRemovedLines > 0 {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 0.5)

                HStack(spacing: 6) {
                    Text("Session Diff")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.38))

                    Spacer()

                    HStack(spacing: 6) {
                        Text("+\(netAddedLines.formatted())")
                            .foregroundStyle(GravPalette.emerald.opacity(0.88))
                        Text("-\(netRemovedLines.formatted())")
                            .foregroundStyle(GravPalette.coral.opacity(0.88))
                    }
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(width: 274)
        .background(
            ZStack {
                Color(red: 0.065, green: 0.070, blue: 0.082)
                LinearGradient(
                    colors: [Color.white.opacity(0.032), Color.clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        )
        .environment(\.colorScheme, .dark)
        .onAppear {
            if reduceMotion {
                revealProgress = 1
            } else {
                revealProgress = 0
                withAnimation(.spring(duration: 0.42, bounce: 0.08)) {
                    revealProgress = 1
                }
            }
        }
        .onDisappear {
            copyResetTask?.cancel()
        }
    }

    // MARK: - Subviews

    private var tokenCompositionBar: some View {
        let segments = resolvedBarSegments()

        return GeometryReader { geo in
            let totalWidth = max(1, geo.size.width)
            let gap: CGFloat = segments.count > 1 ? 2.5 : 0
            let totalGap = gap * CGFloat(max(0, segments.count - 1))
            let usable = max(0, totalWidth - totalGap)

            if segments.isEmpty {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
            } else {
                let widths = perceptualWidths(for: segments.map(\.fraction), usableWidth: usable, minSegment: 10)
                HStack(spacing: gap) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(segment.color)
                            .frame(width: max(2, widths[index] * revealProgress))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 5)
    }

    private struct BarSegment {
        let fraction: Double
        let color: Color
    }

    private func resolvedBarSegments() -> [BarSegment] {
        let total = Double(metrics.totalTokens)
        guard total > 0 else { return [] }
        var list: [BarSegment] = []
        if metrics.cacheReadTokens > 0 {
            list.append(BarSegment(fraction: Double(metrics.cacheReadTokens) / total, color: GravPalette.emerald.opacity(0.84)))
        }
        if metrics.inputTokens > 0 {
            list.append(BarSegment(fraction: Double(metrics.inputTokens) / total, color: Color.white.opacity(0.86)))
        }
        if metrics.outputTokens > 0 {
            list.append(BarSegment(fraction: Double(metrics.outputTokens) / total, color: GravPalette.glacialCyan))
        }
        return list
    }

    /// Distributes bar widths proportionally while guaranteeing each active segment stays
    /// optically readable (at least `minSegment` points) even at 97%+ cache hit ratios.
    private func perceptualWidths(for fractions: [Double], usableWidth: CGFloat, minSegment: CGFloat) -> [CGFloat] {
        guard !fractions.isEmpty else { return [] }
        let raw = fractions.map { CGFloat($0) * usableWidth }
        let clamped = raw.map { max(minSegment, $0) }
        let sum = clamped.reduce(0, +)
        guard sum > 0 else { return raw }
        let scale = usableWidth / sum
        return clamped.map { $0 * scale }
    }

    private func ledgerRow(
        dotColor: Color,
        label: String,
        detail: String?,
        value: String
    ) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(dotColor)
                .frame(width: 5.5, height: 5.5)

            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.54))

            if let detail {
                Text(detail)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.34))
            }

            Spacer(minLength: 8)

            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.90))
        }
    }

    private var verticalHairline: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 0.5, height: 24)
    }

    private func balancedStatCell(count: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.92))
                .contentTransition(reduceMotion ? .identity : .numericText())

            Text(label)
                .font(.system(size: 9.5, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.40))
        }
        .frame(maxWidth: .infinity)
    }

    private func copyMetricsSummary() {
        GravOnboardingWelcomeAudio.shared.playButtonTap()
        let cachePct = Int((metrics.cacheHitRate * 100.0).rounded())
        let modelPart = store.activeModel.map { "Model: \($0)\n" } ?? ""
        let summary = """
        \(modelPart)Total Tokens: \(metrics.totalTokens.formatted())
        Cached: \(metrics.cacheReadTokens.formatted()) (\(cachePct)%)
        Input: \(metrics.inputTokens.formatted())
        Output: \(metrics.outputTokens.formatted())
        Activity: \(store.responses.count) replies · \(store.fileChanges.count) files · \(store.commands.count) commands
        """
        NotchTelemetryHelpers.copyToPasteboard(summary)
        copiedFeedback = true
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            copiedFeedback = false
        }
    }
}
