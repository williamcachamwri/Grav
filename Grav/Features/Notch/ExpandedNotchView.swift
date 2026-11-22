import SwiftUI

/// Expanded 120Hz interactive Notch HUD combining header telemetry, segmented mode rail,
/// directional slide tab transitions, and full keyboard shortcut navigation.
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
        VStack(spacing: 7) {
            ExpandedNotchHeaderView(
                store: store,
                preferences: preferences,
                onOpenSettings: onOpenSettings
            )

            SegmentedModeRail(
                selection: tabBinding,
                liveCount: store.recentActivity.count,
                filesCount: store.fileChanges.count,
                terminalCount: store.commands.count,
                hasRunningCommand: store.activeCommand != nil && !store.isPaused
            )

            tabViewport
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            footerShortcutStrip
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            hiddenShortcutControls
        }
        .onKeyPress(keys: [.escape, "1", "2", "3"]) { keyPress in
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

    // MARK: - Whisper-Quiet Compact Footer Strip

    private var footerShortcutStrip: some View {
        HStack(spacing: 10) {
            if let message = statusBannerMessage {
                HStack(spacing: 5) {
                    Circle()
                        .fill(GravPalette.emerald)
                        .frame(width: 4.5, height: 4.5)
                    Text(message)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.84))
                }
                .transition(.opacity)
            } else {
                HStack(spacing: 4) {
                    Text("1–3")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.46))
                    Text("Tab")
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.30))
                }

                Text("·")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.18))

                HStack(spacing: 4) {
                    Text("⌘C")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.46))
                    Text(copyHintLabel)
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.30))
                }
            }

            Spacer(minLength: 4)

            Button {
                onCollapse()
            } label: {
                HStack(spacing: 4) {
                    Text("esc")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.46))
                    Text("Close")
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.30))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse Notch HUD")
        }
        .padding(.horizontal, 2)
        .frame(height: 12)
        .animation(reduceMotion ? nil : GravMotion.subtleFade, value: statusBannerMessage)
    }

    private var copyHintLabel: String {
        switch selectedTab {
        case .live:
            return "Copy Thought"
        case .files:
            return "Copy Diff"
        case .terminal:
            return "Copy Log"
        }
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
            switchTab(to: .files)
            return .handled
        case "3":
            switchTab(to: .terminal)
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
            showBanner("Copied reasoning snapshot")
        }
    }

    private func showBanner(_ message: String) {
        statusBannerMessage = message
        statusBannerTask?.cancel()
        statusBannerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            statusBannerMessage = nil
        }
    }
}
