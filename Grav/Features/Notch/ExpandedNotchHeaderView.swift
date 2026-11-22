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
            if !store.isPaused {
                switch store.state {
                case .thinking:
                    NotchThinkingShimmerLabel(
                        startDate: store.currentThinking?.startedAt ?? Date(),
                        compact: true,
                        font: .system(size: 11, weight: .medium),
                        reduceMotion: reduceMotion
                    )
                    .fixedSize(horizontal: true, vertical: false)
                case .working, .compacting:
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
                default:
                    Text(stateLabel)
                        .font(.system(size: 11, weight: .medium))
                        .tracking(-0.1)
                        .foregroundStyle(isActivelyStreaming ? Color.white.opacity(0.76) : Color.white.opacity(0.40))
                        .lineLimit(1)
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
