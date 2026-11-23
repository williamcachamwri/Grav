import SwiftUI

/// Expanded 120Hz interactive Notch HUD combining clean header telemetry, segmented mode rail,
/// directional slide tab transitions, ephemeral copy confirmation toast, and full keyboard navigation
/// (`1`–`3`, `⌘C`, `ESC`) with zero permanent footer clutter.
public struct ExpandedNotchView: View {
    public var store: AntigravityTelemetryStore
    public var preferences: PreferencesStore
    public var onCollapse: () -> Void
    public var onOpenSettings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedTab: NotchTab = .live
    @State private var slideDirection: Int = 1
    @State private var selectedFileID: String?
    @State private var selectedCommandID: String?
    @State private var isTerminalSearchFocused: Bool = false
    @State private var statusBannerMessage: String?
    @State private var statusBannerTask: Task<Void, Never>?

    public init(
        store: AntigravityTelemetryStore,
        preferences: PreferencesStore,
        onCollapse: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.store = store
        self.preferences = preferences
        self.onCollapse = onCollapse
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 8) {
                ExpandedNotchHeaderView(
                    store: store,
                    preferences: preferences,
                    onOpenSettings: onOpenSettings
                )

                SegmentedModeRail(
                    selection: tabBinding,
                    liveCount: store.recentActivity.count,
                    replyCount: store.responses.count,
                    filesCount: store.fileChanges.count,
                    terminalCount: store.commands.count,
                    swarmCount: store.totalAgentsBadgeCount,
                    hasStreamingReply: store.latestResponse?.isStreaming == true && !store.isPaused,
                    hasRunningCommand: store.activeCommand != nil && !store.isPaused,
                    hasActiveSwarm: (store.activeSwarmSnapshot != nil || store.runningSubagentCount > 0) && !store.isPaused
                )

                tabViewport
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if let message = statusBannerMessage {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(GravPalette.emerald)
                    Text(message)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.92))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(red: 0.10, green: 0.11, blue: 0.14).opacity(0.96))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                        )
                )
                .shadow(color: Color.black.opacity(0.45), radius: 10, y: 4)
                .padding(.bottom, 4)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .offset(y: 6)).combined(with: .scale(scale: 0.96))
                )
                .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : GravMotionSpec.settle.animation, value: statusBannerMessage)
        .background {
            hiddenShortcutControls
        }
        .onKeyPress(keys: [.escape, "1", "2", "3", "4", "5"]) { keyPress in
            handleKeyPress(keyPress)
        }
        .onDisappear {
            statusBannerTask?.cancel()
        }
    }

    // MARK: - Tab Content Viewport

    private var tabBinding: Binding<NotchTab> {
        Binding(
            get: { selectedTab },
            set: { switchTab(to: $0) }
        )
    }

    private var tabViewport: some View {
        ZStack {
            switch selectedTab {
            case .live:
                LiveTelemetryTabView(
                    store: store,
                    onInspectFile: { event in
                        selectedFileID = event.id
                        switchTab(to: .files)
                    },
                    onInspectCommand: { command in
                        selectedCommandID = command.id
                        switchTab(to: .terminal)
                    }
                )
                .id(NotchTab.live)
                .transition(tabTransition)

            case .reply:
                ResponseTelemetryTabView(store: store)
                    .id(NotchTab.reply)
                    .transition(tabTransition)

            case .files:
                FilesTelemetryTabView(
                    store: store,
                    selectedFileID: $selectedFileID
                )
                .id(NotchTab.files)
                .transition(tabTransition)

            case .terminal:
                TerminalTelemetryTabView(
                    store: store,
                    selectedCommandID: $selectedCommandID,
                    isSearchFieldFocused: $isTerminalSearchFocused
                )
                .id(NotchTab.terminal)
                .transition(tabTransition)

            case .swarm:
                SwarmTelemetryTabView(
                    store: store,
                    onPinSessionAsMain: { conversationID in
                        store.selectSessionByID(conversationID)
                    }
                )
                .id(NotchTab.swarm)
                .transition(tabTransition)
            }
        }
        .animation(reduceMotion ? nil : GravMotion.contentSlide, value: selectedTab)
    }

    private var tabTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        let insertionEdge: Edge = slideDirection >= 0 ? .trailing : .leading
        let removalEdge: Edge = slideDirection >= 0 ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    // MARK: - Keyboard Navigation & Clipboard

    private var hiddenShortcutControls: some View {
        Group {
            Button("") {
                onCollapse()
            }
            .keyboardShortcut(.escape, modifiers: [])

            if !isTerminalSearchFocused {
                Button("") {
                    copyActiveContext()
                }
                .keyboardShortcut("c", modifiers: [.command])

                Button("") {
                    GravOnboardingWelcomeAudio.shared.playButtonTap()
                    let next = !store.isPaused
                    preferences.isTelemetryPaused = next
                    store.setPaused(next)
                    showBanner(next ? "Telemetry paused" : "Telemetry resumed")
                }
                .keyboardShortcut("p", modifiers: [.command])

                Button("") {
                    GravOnboardingWelcomeAudio.shared.playButtonTap()
                    preferences.isNotchPinned.toggle()
                    showBanner(preferences.isNotchPinned ? "Notch pinned open" : "Notch unpinned")
                }
                .keyboardShortcut("l", modifiers: [.command])

                Button("") {
                    cycleSession(step: 1)
                }
                .keyboardShortcut("]", modifiers: [.command])

                Button("") {
                    cycleSession(step: -1)
                }
                .keyboardShortcut("[", modifiers: [.command])

                ForEach(NotchTab.allCases) { tab in
                    Button("") {
                        switchTab(to: tab)
                    }
                    .keyboardShortcut(tab.keyEquivalent, modifiers: [])
                }
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0.001)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        if keyPress.key == .escape {
            onCollapse()
            return .handled
        }
        guard !isTerminalSearchFocused, keyPress.modifiers.isEmpty else {
            return .ignored
        }
        switch keyPress.characters {
        case "1":
            switchTab(to: .live)
            return .handled
        case "2":
            switchTab(to: .reply)
            return .handled
        case "3":
            switchTab(to: .files)
            return .handled
        case "4":
            switchTab(to: .terminal)
            return .handled
        case "5":
            switchTab(to: .swarm)
            return .handled
        default:
            return .ignored
        }
    }

    private func switchTab(to target: NotchTab) {
        guard target != selectedTab else { return }
        slideDirection = target.rawValue >= selectedTab.rawValue ? 1 : -1
        if reduceMotion {
            selectedTab = target
        } else {
            withAnimation(GravMotion.contentSlide) {
                selectedTab = target
            }
        }
    }

    private func copyActiveContext() {
        switch selectedTab {
        case .reply:
            guard let reply = store.latestResponse ?? store.responses.first, !reply.text.isEmpty else {
                return
            }
            GravOnboardingWelcomeAudio.shared.playButtonTap()
            NotchTelemetryHelpers.copyToPasteboard(reply.text)
            showBanner("Copied assistant reply")

        case .files:
            let file = store.fileChanges.first(where: { $0.id == selectedFileID }) ?? store.fileChanges.first
            guard let file else { return }
            NotchTelemetryHelpers.copyToPasteboard(NotchTelemetryHelpers.formatUnifiedDiff(for: file))
            showBanner("Copied diff for \(file.basename)")

        case .terminal:
            let command = store.commands.first(where: { $0.id == selectedCommandID })
                ?? store.activeCommand
                ?? store.commands.first
            guard let command, !command.logOutput.isEmpty else { return }
            NotchTelemetryHelpers.copyToPasteboard(command.logOutput)
            showBanner("Copied log for \(command.displayTitle)")

        case .live:
            guard let thought = store.currentThinking ?? store.thinkingHistory.first,
                  !thought.text.isEmpty
            else {
                return
            }
            NotchTelemetryHelpers.copyToPasteboard(thought.text)
            showBanner("Copied reasoning")

        case .swarm:
            guard let swarm = store.swarmSnapshot else { return }
            let summary = swarm.members
                .map { "\($0.name) [\($0.phase.displayLabel)]" }
                .joined(separator: ", ")
            NotchTelemetryHelpers.copyToPasteboard("\(swarm.displayTitle): \(summary)")
            showBanner("Copied swarm roster")
        }
    }

    private func cycleSession(step: Int) {
        let list = store.sessions
        guard list.count >= 2 else { return }
        GravOnboardingWelcomeAudio.shared.playButtonTap()
        let currentIdx = store.activeSession.flatMap { active in
            list.firstIndex(where: { $0.id == active.id })
        } ?? 0
        let nextIdx = ((currentIdx + step) % list.count + list.count) % list.count
        let target = list[nextIdx]
        store.selectSession(target)
        let title = target.title
            .replacingOccurrences(of: "<USER_REQUEST>", with: "")
            .replacingOccurrences(of: "</USER_REQUEST>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        showBanner("Switched: \(String(title.prefix(28)))")
    }

    private func showBanner(_ message: String) {
        statusBannerMessage = message
        statusBannerTask?.cancel()
        statusBannerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.35))
            guard !Task.isCancelled else { return }
            statusBannerMessage = nil
        }
    }
}
