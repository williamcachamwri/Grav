import AppKit
import Observation
import SwiftUI

/// `@MainActor` macOS menu bar controller managing Grav's `NSStatusItem`,
/// monochrome template orbital icon, live status header, and quick actions.
@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    private let store: AntigravityTelemetryStore
    private let preferences: PreferencesStore

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private var isInstalled = false
    private var lastRenderedState: MenuBarIconRenderer.VisualState?

    private var headerMenuItem: NSMenuItem?
    private var pauseResumeMenuItem: NSMenuItem?
    private var openAntigravityMenuItem: NSMenuItem?

    public var onToggleNotch: (() -> Void)?
    public var onReplayWelcome: (() -> Void)?
    public var onOpenPreferences: (() -> Void)?
    public var onQuit: (() -> Void)?

    public init(
        store: AntigravityTelemetryStore,
        preferences: PreferencesStore,
        onToggleNotch: (() -> Void)? = nil,
        onReplayWelcome: (() -> Void)? = nil,
        onOpenPreferences: (() -> Void)? = nil,
        onQuit: (() -> Void)? = nil
    ) {
        self.store = store
        self.preferences = preferences
        self.onToggleNotch = onToggleNotch
        self.onReplayWelcome = onReplayWelcome
        self.onOpenPreferences = onOpenPreferences
        self.onQuit = onQuit
        super.init()
    }

    /// Creates the `NSStatusItem`, populates the menu, and begins reactive observation.
    public func install() {
        guard !isInstalled else { return }
        isInstalled = true

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.isVisible = true
        item.menu = menu

        if let button = item.button {
            button.imagePosition = .imageOnly
            button.toolTip = "Grav — Antigravity Telemetry"
        }

        statusItem = item
        configureMenu()
        refresh()
        startObservationLoop()
    }

    /// Removes the `NSStatusItem` from the macOS menu bar and stops observation.
    public func uninstall() {
        isInstalled = false
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        lastRenderedState = nil
    }

    /// Immediately synchronizes the menu bar icon and dynamic menu item titles.
    public func refresh() {
        updateStatusIcon()
        updateDynamicMenuItems()
    }

    // MARK: - Menu Construction

    private func configureMenu() {
        menu.removeAllItems()
        menu.delegate = self
        menu.autoenablesItems = false

        let headerItem = NSMenuItem()
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        headerMenuItem = headerItem

        menu.addItem(.separator())

        let toggleNotchItem = makeMenuItem(
            title: "Toggle Notch",
            action: #selector(handleToggleNotch),
            keyEquivalent: "",
            symbolName: "rectangle.topthird.inset.filled"
        )
        menu.addItem(toggleNotchItem)

        let pauseItem = makeMenuItem(
            title: "Pause Telemetry",
            action: #selector(handleTogglePauseTelemetry),
            keyEquivalent: "",
            symbolName: "pause.circle"
        )
        menu.addItem(pauseItem)
        pauseResumeMenuItem = pauseItem

        menu.addItem(.separator())

        let replayWelcomeItem = makeMenuItem(
            title: "Replay Welcome Screen",
            action: #selector(handleReplayWelcome),
            keyEquivalent: "",
            symbolName: "arrow.counterclockwise"
        )
        menu.addItem(replayWelcomeItem)

        let openAntigravityItem = makeMenuItem(
            title: "Open Antigravity",
            action: #selector(handleOpenAntigravity),
            keyEquivalent: "",
            symbolName: "arrow.up.forward.app"
        )
        menu.addItem(openAntigravityItem)
        openAntigravityMenuItem = openAntigravityItem

        menu.addItem(.separator())

        let preferencesItem = makeMenuItem(
            title: "Preferences…",
            action: #selector(handleOpenPreferences),
            keyEquivalent: ",",
            symbolName: "gearshape"
        )
        menu.addItem(preferencesItem)

        menu.addItem(.separator())

        let quitItem = makeMenuItem(
            title: "Quit Grav",
            action: #selector(handleQuit),
            keyEquivalent: "q",
            symbolName: "power"
        )
        menu.addItem(quitItem)
    }

    private func makeMenuItem(
        title: String,
        action: Selector,
        keyEquivalent: String,
        symbolName: String
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.isEnabled = true
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) {
            image.isTemplate = true
            item.image = image
        }
        return item
    }

    // MARK: - Live State Updates

    private var isPaused: Bool {
        store.isPaused || preferences.isTelemetryPaused
    }

    private var iconVisualState: MenuBarIconRenderer.VisualState {
        if isPaused {
            return .paused
        }
        return store.state.isActive ? .active : .idle
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let targetState = iconVisualState
        if lastRenderedState != targetState {
            button.image = MenuBarIconRenderer.makeIcon(state: targetState)
            lastRenderedState = targetState
        }

        if isPaused {
            button.toolTip = "Grav — Telemetry Paused"
        } else if store.state.isActive {
            button.toolTip = "Grav — \(store.state.label)"
        } else {
            button.toolTip = "Grav — Telemetry Idle"
        }
    }

    private func updateDynamicMenuItems() {
        let snapshot = MenuBarStatusSnapshot(
            state: store.state,
            isPaused: isPaused,
            activeSessionTitle: store.activeSession?.title,
            tokenCount: store.tokenMetrics.totalTokens,
            isAppRunning: store.connectionStatus.isAppRunning,
            isBrainAccessible: store.connectionStatus.isBrainAccessible
        )

        if let headerMenuItem {
            let headerView = MenuBarStatusHeaderView(snapshot: snapshot)
            let hostingView = NSHostingView(rootView: headerView)
            hostingView.frame = NSRect(x: 0, y: 0, width: 248, height: 46)
            headerMenuItem.view = hostingView
        }

        if let pauseResumeMenuItem {
            let paused = isPaused
            pauseResumeMenuItem.title = paused ? "Resume Telemetry" : "Pause Telemetry"
            let symbolName = paused ? "play.circle" : "pause.circle"
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: pauseResumeMenuItem.title) {
                image.isTemplate = true
                pauseResumeMenuItem.image = image
            }
        }

        if let openAntigravityMenuItem {
            openAntigravityMenuItem.title = store.connectionStatus.isAppRunning
                ? "Focus Antigravity"
                : "Open Antigravity"
        }
    }

    private func startObservationLoop() {
        guard isInstalled else { return }
        withObservationTracking {
            _ = store.state
            _ = store.isPaused
            _ = preferences.isTelemetryPaused
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isInstalled else { return }
                self.updateStatusIcon()
                self.startObservationLoop()
            }
        }
    }

    // MARK: - NSMenuDelegate

    public func menuWillOpen(_ menu: NSMenu) {
        _ = menu
        store.refreshConnectionStatus()
        refresh()
    }

    // MARK: - Actions

    @objc private func handleToggleNotch() {
        onToggleNotch?()
    }

    @objc private func handleTogglePauseTelemetry() {
        let nextPaused = !isPaused
        preferences.isTelemetryPaused = nextPaused
        store.setPaused(nextPaused)
        refresh()
    }

    @objc private func handleReplayWelcome() {
        onReplayWelcome?()
    }

    @objc private func handleOpenAntigravity() {
        store.activateAntigravityApp()
    }

    @objc private func handleOpenPreferences() {
        onOpenPreferences?()
    }

    @objc private func handleQuit() {
        if let onQuit {
            onQuit()
        } else {
            NSApp.terminate(nil)
        }
    }
}

// MARK: - Live Status Header View

private struct MenuBarStatusSnapshot: Sendable {
    let state: TelemetryState
    let isPaused: Bool
    let activeSessionTitle: String?
    let tokenCount: Int
    let isAppRunning: Bool
    let isBrainAccessible: Bool

    var headline: String {
        if isPaused {
            return "Telemetry Paused"
        }
        switch state {
        case .idle:
            return isAppRunning ? "Antigravity Idle" : "Standby"
        case .working:
            return "Working"
        case .compacting:
            return "Compacting"
        case .thinking:
            return "Thinking"
        case .replying:
            return "Replying"
        case let .inspecting(event):
            if let range = event.lineRangeLabel {
                return "Analyzed \(event.basename) \(range)"
            }
            return "Analyzed \(event.basename)"
        case let .editing(event):
            let verb = event.kind == .delete ? "Deleting" : "Editing"
            return "\(verb) \(event.basename)"
        case let .runningCommand(event):
            return event.displayTitle
        case let .waitingForInput(prompt):
            return prompt
        case let .toolActivity(event):
            return event.title
        }
    }

    var subtitle: String {
        if isPaused {
            return "Resume to stream live local transcripts"
        }
        if !isBrainAccessible {
            return "Waiting for local brain folder access"
        }
        var parts: [String] = []
        if let activeSessionTitle, !activeSessionTitle.isEmpty {
            parts.append(activeSessionTitle)
        } else {
            parts.append(isAppRunning ? "Connected" : "Local watcher ready")
        }
        if tokenCount > 0 {
            parts.append("\(TokenMetrics.formatCompact(tokenCount)) tok")
        }
        return parts.joined(separator: " · ")
    }

    var dotTone: SemanticDotTone {
        if isPaused { return .idle }
        if state.isActive { return SemanticDotTone(telemetryState: state) }
        return isAppRunning && isBrainAccessible ? .success : .idle
    }
}

private struct MenuBarStatusHeaderView: View {
    @Environment(\.colorScheme) private var colorScheme
    let snapshot: MenuBarStatusSnapshot

    var body: some View {
        let palette = GravAdaptivePalette(colorScheme: colorScheme)

        HStack(spacing: GravSpacing.sm) {
            SemanticDot(
                tone: snapshot.dotTone,
                size: 6,
                isActive: false,
                showPulse: false,
                adaptive: true
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.headline)
                    .font(GravTypography.bodyMedium)
                    .foregroundStyle(palette.inkPrimary)
                    .lineLimit(1)

                Text(snapshot.subtitle)
                    .font(GravTypography.caption)
                    .foregroundStyle(palette.inkTertiary)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(width: 248, height: 46, alignment: .leading)
    }
}
