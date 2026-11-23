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
    public var preferences: PreferencesStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        store: AntigravityTelemetryStore,
        presenter: NotchPresenter,
        preferences: PreferencesStore = PreferencesStore()
    ) {
        self.store = store
        self.presenter = presenter
        self.preferences = preferences
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
                HStack(alignment: .center, spacing: 10) {
                    leadingWing(compact: false)
                        .fixedSize(horizontal: true, vertical: false)
                    trailingWing(compact: false)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .frame(width: presenter.collapsedSurfaceWidth, height: pillHeight, alignment: .center)
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
        } else if store.activeSwarmSnapshot != nil {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(GravPalette.prismViolet)
                .transition(signalTransition)
        } else if store.runningTaskCount > 0 && effectiveState == .idle {
            NotchBars(commandWaveStyle)
                .transition(signalTransition)
        } else {
            switch effectiveState {
            case .working:
                NotchBars(workingWaveStyle)
                    .transition(signalTransition)

            case .compacting:
                Image(systemName: "rectangle.compress.vertical")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GravPalette.prismViolet)
                    .transition(signalTransition)

            case .thinking:
                NotchBars(thinkingWaveStyle)
                    .transition(signalTransition)

            case .replying:
                NotchBars(replyingWaveStyle)
                    .transition(signalTransition)

            case let .inspecting(event):
                TimelineView(.periodic(from: store.currentPhaseStartedAt, by: 1.0)) { context in
                    if context.date.timeIntervalSince(store.currentPhaseStartedAt) >= 5.0 {
                        NotchBars(thinkingWaveStyle)
                    } else {
                        LanguageIconView(path: event.path, changeKind: nil, size: 14)
                    }
                }
                .transition(signalTransition)

            case let .editing(event):
                TimelineView(.periodic(from: store.currentPhaseStartedAt, by: 1.0)) { context in
                    if context.date.timeIntervalSince(store.currentPhaseStartedAt) >= 5.0 {
                        NotchBars(thinkingWaveStyle)
                    } else {
                        LanguageIconView(path: event.path, changeKind: event.kind, size: 14)
                    }
                }
                .transition(signalTransition)

            case .runningCommand:
                NotchBars(commandWaveStyle)
                    .transition(signalTransition)

            case .waitingForInput:
                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GravPalette.fileEdit)
                    .transition(signalTransition)

            case let .toolActivity(event):
                Image(systemName: event.kind.symbolName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GravPalette.glacialCyan)
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
        HStack(alignment: .center, spacing: 6) {
            ZStack(alignment: .trailing) {
                if !store.isPaused, let activeSwarm = store.activeSwarmSnapshot {
                    swarmTrailingSignal(for: activeSwarm, compact: compact)
                        .id("collapsed-swarm-\(activeSwarm.runningWorkers.count)-\(activeSwarm.waitingWorkers.count)")
                        .transition(signalTransition)
                } else if !store.isPaused, store.runningTaskCount > 0, effectiveState == .idle {
                    runningTasksTrailingSignal(count: store.runningTaskCount, compact: compact)
                        .id("collapsed-tasks-\(store.runningTaskCount)")
                        .transition(signalTransition)
                } else {
                    switch effectiveState {
                    case let .working(startedAt):
                        workingTrailingSignal(startedAt: startedAt, compact: compact)
                            .id("collapsed-working")
                            .transition(signalTransition)

                    case .compacting:
                        compactingTrailingSignal(compact: compact)
                            .id("collapsed-compacting")
                            .transition(signalTransition)

                    case .thinking:
                        thinkingTrailingSignal(compact: compact)
                            .id("collapsed-thinking")
                            .transition(signalTransition)

                    case .replying:
                        replyingTrailingSignal(compact: compact)
                            .id("collapsed-replying")
                            .transition(signalTransition)

                    case let .inspecting(event):
                        inspectingTrailingSignal(for: event, compact: compact)
                            .id("collapsed-inspect-\(event.id)")
                            .transition(signalTransition)

                    case let .editing(event):
                        editingTrailingSignal(for: event, compact: compact)
                            .id("collapsed-edit-\(event.id)")
                            .transition(signalTransition)

                    case let .runningCommand(command):
                        if store.runningTaskCount >= 2 {
                            runningTasksTrailingSignal(count: store.runningTaskCount, compact: compact)
                                .id("collapsed-multi-tasks-\(store.runningTaskCount)")
                                .transition(signalTransition)
                        } else {
                            commandTrailingSignal(for: command, compact: compact)
                                .id("collapsed-cmd-\(command.id)")
                                .transition(signalTransition)
                        }

                    case let .waitingForInput(prompt):
                        waitingTrailingSignal(prompt: prompt, compact: compact)
                            .id("collapsed-waiting")
                            .transition(signalTransition)

                    case let .toolActivity(event):
                        toolActivityTrailingSignal(for: event, compact: compact)
                            .id("collapsed-tool-\(event.id)")
                            .transition(signalTransition)

                    case .idle:
                        idleTrailingSignal(compact: compact)
                            .id("collapsed-idle")
                            .transition(.opacity)
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : islandSpring, value: effectiveState)
        .animation(reduceMotion ? nil : islandSpring, value: store.runningTaskCount)
        .animation(reduceMotion ? nil : islandSpring, value: store.activeSwarmSnapshot?.collapsedRatioBadge)
    }

    private func swarmTrailingSignal(for swarm: SwarmSnapshot, compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 6) {
            if compact {
                NotchShimmerText(
                    text: "Swarm \(swarm.collapsedRatioBadge)",
                    font: .system(size: 11, weight: .medium),
                    tracking: -0.15,
                    baseOpacity: 0.48,
                    peakOpacity: 0.96,
                    period: 1.8,
                    reduceMotion: reduceMotion
                )
                .monospacedDigit()
            } else {
                NotchPingPongMarqueeText(
                    text: swarm.collapsedSummaryText,
                    font: .system(size: 11.5, weight: .medium),
                    color: Color.white.opacity(0.88),
                    alignment: .trailing,
                    reduceMotion: reduceMotion
                )

                Text(swarm.collapsedRatioBadge)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(GravPalette.prismViolet)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func runningTasksTrailingSignal(count: Int, compact: Bool) -> some View {
        let label = count == 1 ? "1 task running" : "\(count) tasks running"
        return NotchShimmerText(
            text: compact ? "\(count) task\(count == 1 ? "" : "s")" : label,
            font: .system(size: compact ? 11 : 11.5, weight: .medium),
            tracking: -0.15,
            baseOpacity: 0.46,
            peakOpacity: 0.96,
            period: 1.75,
            reduceMotion: reduceMotion
        )
        .monospacedDigit()
    }

    private func workingTrailingSignal(startedAt: Date, compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 5) {
            if !compact, preferences.showCollapsedFocus, let focus = store.currentFocus, !focus.isEmpty {
                NotchPingPongMarqueeText(
                    text: focus,
                    font: .system(size: 11.5, weight: .medium),
                    color: Color.white.opacity(0.88),
                    alignment: .trailing,
                    reduceMotion: reduceMotion
                )
            } else {
                NotchWorkingThinkingShimmerLabel(
                    startDate: startedAt,
                    compact: compact,
                    font: .system(size: compact ? 11 : 11.5, weight: .medium),
                    reduceMotion: reduceMotion
                )
            }

            if preferences.showCollapsedStepProgress, let steps = store.stepsProgress, !steps.isAllDone {
                miniStepsProgressBadge(steps, compact: compact)
            } else if !compact && store.runningTaskCount > 0 {
                Text("· \(store.runningTaskCount) task\(store.runningTaskCount == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(GravPalette.glacialCyan.opacity(0.88))
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func compactingTrailingSignal(compact: Bool) -> some View {
        NotchShimmerText(
            text: "Compacting",
            font: .system(size: compact ? 11 : 11.5, weight: .medium),
            tracking: -0.15,
            baseOpacity: 0.46,
            peakOpacity: 0.96,
            period: 1.85,
            reduceMotion: reduceMotion
        )
    }

    private func thinkingTrailingSignal(compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 5) {
            if !compact, preferences.showCollapsedFocus, let focus = store.currentFocus, !focus.isEmpty {
                NotchPingPongMarqueeText(
                    text: focus,
                    font: .system(size: 11.5, weight: .medium),
                    color: Color.white.opacity(0.86),
                    alignment: .trailing,
                    reduceMotion: reduceMotion
                )
            } else {
                NotchThinkingShimmerLabel(
                    startDate: store.currentPhaseStartedAt,
                    compact: compact,
                    font: .system(size: compact ? 11 : 11.5, weight: .medium),
                    reduceMotion: reduceMotion
                )
            }

            if preferences.showCollapsedStepProgress, let steps = store.stepsProgress, !steps.isAllDone {
                miniStepsProgressBadge(steps, compact: compact)
            } else if !compact && store.runningTaskCount > 0 {
                Text("· \(store.runningTaskCount) task\(store.runningTaskCount == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(GravPalette.glacialCyan.opacity(0.88))
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func waitingTrailingSignal(prompt: String, compact: Bool) -> some View {
        if compact {
            return AnyView(
                NotchShimmerText(
                    text: "Needs input",
                    font: .system(size: 11, weight: .semibold),
                    tracking: -0.15,
                    baseOpacity: 0.60,
                    peakOpacity: 1.0,
                    period: 1.35,
                    reduceMotion: reduceMotion
                )
            )
        }
        return AnyView(
            NotchPingPongMarqueeText(
                text: prompt,
                font: .system(size: 11.5, weight: .medium),
                color: GravPalette.fileEdit.opacity(0.95),
                alignment: .trailing,
                reduceMotion: reduceMotion
            )
        )
    }

    private func toolActivityTrailingSignal(for event: AgentToolActivityEvent, compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 5) {
            NotchPingPongMarqueeText(
                text: compact ? event.kind.shortLabel : event.title,
                font: .system(size: compact ? 11 : 11.5, weight: .medium),
                color: Color.white.opacity(0.88),
                alignment: .trailing,
                reduceMotion: reduceMotion
            )

            if preferences.showCollapsedStepProgress, let steps = store.stepsProgress, !steps.isAllDone, !compact {
                miniStepsProgressBadge(steps, compact: true)
            }
        }
    }

    private func miniStepsProgressBadge(_ steps: AgentStepsProgress, compact: Bool) -> some View {
        HStack(spacing: 3.5) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 1.4)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0.08, steps.fraction)))
                    .stroke(
                        Color.white.opacity(0.86),
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 9, height: 9)

            Text(verbatim: "\(steps.completedCount)/\(steps.totalCount)")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.68))
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func replyingTrailingSignal(compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 6) {
            NotchShimmerText(
                text: "Replying",
                font: .system(size: compact ? 11 : 11.5, weight: .medium),
                tracking: -0.15,
                baseOpacity: 0.50,
                peakOpacity: 0.98,
                period: 1.55,
                reduceMotion: reduceMotion
            )

            if !compact && preferences.showCollapsedTokens && store.tokenMetrics.outputTokens > 0 {
                NotchTokenFlowDisplay(
                    metrics: store.tokenMetrics,
                    isStreaming: true,
                    style: .collapsedStreamingOutput,
                    reduceMotion: reduceMotion
                )
            }
        }
    }

    private func inspectingTrailingSignal(for event: FileInspectionEvent, compact: Bool) -> some View {
        TimelineView(.periodic(from: store.currentPhaseStartedAt, by: 1.0)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(store.currentPhaseStartedAt))
            if elapsed >= 5.0 {
                // After clearly showcasing the analyzed file for 5s, smoothly morph to live
                // `Thinking for Ns` while Antigravity reasons about the next step.
                NotchThinkingShimmerLabel(
                    startDate: store.currentPhaseStartedAt,
                    compact: compact,
                    font: .system(size: compact ? 11 : 11.5, weight: .medium),
                    reduceMotion: reduceMotion
                )
            } else {
                HStack(alignment: .center, spacing: 6) {
                    NotchPingPongMarqueeText(
                        text: compact ? event.basename : "Analyzed \(event.basename)",
                        font: .system(size: 11.5, weight: .medium),
                        color: Color.white.opacity(0.86),
                        alignment: .trailing,
                        reduceMotion: reduceMotion
                    )

                    if let range = event.lineRangeLabel {
                        Text(range)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(Color.white.opacity(0.46))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
    }

    private func editingTrailingSignal(for event: FileChangeEvent, compact: Bool) -> some View {
        TimelineView(.periodic(from: store.currentPhaseStartedAt, by: 1.0)) { context in
            if context.date.timeIntervalSince(store.currentPhaseStartedAt) >= 5.0 {
                NotchThinkingShimmerLabel(
                    startDate: store.currentPhaseStartedAt,
                    compact: compact,
                    font: .system(size: compact ? 11 : 11.5, weight: .medium),
                    reduceMotion: reduceMotion
                )
            } else {
                HStack(spacing: 6) {
                    NotchPingPongMarqueeText(
                        text: event.basename,
                        font: .system(size: 11.5, weight: .medium),
                        color: Color.white.opacity(0.90),
                        alignment: .trailing,
                        reduceMotion: reduceMotion
                    )

                    if event.kind == .delete {
                        Text("DEL")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(GravPalette.coral)
                            .fixedSize(horizontal: true, vertical: false)
                    } else {
                        HStack(spacing: 3.5) {
                            if event.addedLines > 0 || event.removedLines == 0 {
                                Text(verbatim: "+\(event.addedLines)")
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundStyle(GravPalette.emerald)
                                    .contentTransition(reduceMotion ? .identity : .numericText())
                            }
                            if event.removedLines > 0 {
                                Text(verbatim: "-\(event.removedLines)")
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
        }
    }

    private func commandTrailingSignal(for command: CommandExecutionEvent, compact: Bool) -> some View {
        HStack(spacing: 6) {
            NotchPingPongMarqueeText(
                text: command.displayTitle,
                font: .system(size: 11.5, weight: .medium),
                color: Color.white.opacity(0.88),
                alignment: .trailing,
                reduceMotion: reduceMotion
            )

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
            if let radar = store.activeRadarAlert, !store.isPaused {
                HStack(spacing: 4) {
                    NotchSemanticDot(
                        color: radar.severity == .destructive
                            ? Color(red: 0.96, green: 0.36, blue: 0.36)
                            : Color(red: 0.96, green: 0.72, blue: 0.28),
                        size: 5,
                        isPulsing: true
                    )
                    Text(radar.severity == .destructive ? "Risk" : "Reply")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.86))
                        .lineLimit(1)
                }
            } else if store.unreadSessionCount > 0 && !store.isPaused {
                HStack(spacing: 4) {
                    Circle()
                        .fill(GravPalette.glacialCyan)
                        .frame(width: 5, height: 5)
                    Text(compact ? "\(store.unreadSessionCount)" : "\(store.unreadSessionCount) unread")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(GravPalette.glacialCyan.opacity(0.92))
                        .lineLimit(1)
                }
            } else if preferences.showCollapsedTokens && store.tokenMetrics.totalTokens > 0 {
                NotchTokenFlowDisplay(
                    metrics: store.tokenMetrics,
                    isStreaming: false,
                    style: .collapsedIdle(compact: compact),
                    reduceMotion: reduceMotion
                )

                Circle()
                    .fill(store.connectionStatus.isAppRunning ? GravPalette.emerald.opacity(0.82) : GravPalette.idleDot)
                    .frame(width: 5, height: 5)
            } else {
                Circle()
                    .fill(store.connectionStatus.isAppRunning ? GravPalette.emerald.opacity(0.82) : GravPalette.idleDot)
                    .frame(width: 5, height: 5)
            }
        }
        .padding(.trailing, 1)
    }

    // MARK: - Transitions & Bare Harmonic Waveforms

    private var signalTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 3)),
            removal: .opacity.combined(with: .offset(y: -3))
        )
    }

    private var workingWaveStyle: NotchBarsStyle {
        let tint = Color.white.opacity(0.72)
        if reduceMotion {
            return .steady([0.38, 0.78, 0.50], barWidth: 1.5, spacing: 1.7, height: 9, tint: tint)
        }
        return .wave(
            count: 3,
            low: 0.24,
            high: 0.96,
            barWidth: 1.5,
            spacing: 1.7,
            height: 9,
            period: 0.86,
            stagger: 0.14,
            tint: tint
        )
    }

    private var thinkingWaveStyle: NotchBarsStyle {
        let tint = GravPalette.thinking
        if reduceMotion {
            return .steady([0.38, 0.85, 0.55, 0.92], barWidth: 1.6, spacing: 1.7, height: 10, tint: tint)
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
            tint: tint
        )
    }

    private var replyingWaveStyle: NotchBarsStyle {
        let tint = GravPalette.emerald
        if reduceMotion {
            return .steady([0.52, 0.88, 0.64], barWidth: 1.6, spacing: 1.7, height: 9.5, tint: tint)
        }
        return .wave(
            count: 3,
            low: 0.28,
            high: 1.0,
            barWidth: 1.6,
            spacing: 1.7,
            height: 9.5,
            period: 0.62,
            stagger: 0.10,
            tint: tint
        )
    }

    private var commandWaveStyle: NotchBarsStyle {
        let tint = Color.white.opacity(0.85)
        if reduceMotion {
            return .steady([0.45, 0.9, 0.55], barWidth: 1.6, spacing: 1.7, height: 9.5, tint: tint)
        }
        return .wave(
            count: 3,
            low: 0.26,
            high: 1.0,
            barWidth: 1.6,
            spacing: 1.7,
            height: 9.5,
            period: 0.56,
            stagger: 0.10,
            tint: tint
        )
    }

    // MARK: - Accessibility

    private var accessibilityStatusLabel: String {
        if store.isPaused {
            return "Grav telemetry paused"
        }
        switch effectiveState {
        case .idle:
            return "Grav idle"
        case .working:
            return "Antigravity working"
        case .compacting:
            return "Antigravity compacting context"
        case .thinking:
            return "Antigravity thinking"
        case .replying:
            return "Antigravity replying"
        case let .inspecting(event):
            return "Analyzing \(event.basename)"
        case let .editing(event):
            return event.kind == .delete
                ? "Deleting \(event.basename)"
                : "Editing \(event.basename), +\(event.addedLines) -\(event.removedLines)"
        case let .runningCommand(command):
            return "Running \(command.displayTitle)"
        case let .waitingForInput(prompt):
            return "Needs input: \(prompt)"
        case let .toolActivity(event):
            return event.title
        }
    }
}

/// Smooth 120Hz ping-pong back-and-forth marquee for long titles inside the collapsed Notch pill.
/// - Zero animation & zero CPU when `textWidth <= containerWidth`.
/// - When overflowing: pauses briefly at leading edge, glides smoothly left to reveal the end,
///   pauses, and glides back smoothly with soft feathered leading/trailing masks.
struct NotchPingPongMarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    var alignment: Alignment = .trailing
    let reduceMotion: Bool

    @State private var containerWidth: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var offsetX: CGFloat = 0
    @State private var marqueeTask: Task<Void, Never>?

    private var overflow: CGFloat {
        max(0, textWidth - containerWidth)
    }

    private var shouldScroll: Bool {
        !reduceMotion && containerWidth > 12 && overflow > 3
    }

    var body: some View {
        GeometryReader { geo in
            let horizontalInset: CGFloat = shouldScroll ? 4 : 0
            ZStack(alignment: shouldScroll ? .leading : alignment) {
                Text(text)
                    .font(font)
                    .tracking(-0.15)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        GeometryReader { textGeo in
                            Color.clear
                                .onAppear { textWidth = textGeo.size.width }
                                .onChange(of: textGeo.size.width) { _, w in textWidth = w }
                        }
                    )
                    .padding(.horizontal, horizontalInset)
                    .offset(x: shouldScroll ? offsetX : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: shouldScroll ? .leading : alignment)
            .clipped()
            .mask(edgeFadeMask)
            .onAppear {
                containerWidth = geo.size.width
                restartMarqueeIfNeeded()
            }
            .onChange(of: geo.size.width) { _, w in
                containerWidth = w
                restartMarqueeIfNeeded()
            }
            .onChange(of: text) { _, _ in
                offsetX = 0
                restartMarqueeIfNeeded()
            }
            .onChange(of: textWidth) { _, _ in
                restartMarqueeIfNeeded()
            }
            .onChange(of: reduceMotion) { _, _ in
                restartMarqueeIfNeeded()
            }
            .onDisappear {
                marqueeTask?.cancel()
                marqueeTask = nil
            }
        }
        .frame(maxWidth: .infinity, minHeight: 19, maxHeight: 19, alignment: .center)
    }

    @ViewBuilder
    private var edgeFadeMask: some View {
        if shouldScroll {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black, location: 0.05),
                    .init(color: .black, location: 0.93),
                    .init(color: .clear, location: 1.0),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            Rectangle().fill(Color.black)
        }
    }

    private func restartMarqueeIfNeeded() {
        marqueeTask?.cancel()
        marqueeTask = nil
        offsetX = 0

        guard shouldScroll else { return }
        // Calm, legible Dynamic Island reading speed (~18 pt/s) with relaxed dwell pauses at both ends
        let travel = overflow + 8.0
        let duration = max(3.2, min(11.0, Double(travel) / 18.0))

        marqueeTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.85))
                guard !Task.isCancelled else { break }

                withAnimation(.easeInOut(duration: duration)) {
                    offsetX = -travel
                }
                try? await Task.sleep(for: .seconds(duration + 1.85))
                guard !Task.isCancelled else { break }

                withAnimation(.easeInOut(duration: duration)) {
                    offsetX = 0
                }
                try? await Task.sleep(for: .seconds(duration))
            }
        }
    }
}
