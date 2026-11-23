import AppKit
import Observation
import SwiftUI

/// `@MainActor` macOS menu bar controller managing Grav's `NSStatusItem`,
/// monochrome template orbital icon, live status header, Mini Pet controls,
/// active session switcher, and rich HUD toggles.
@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    private let store: AntigravityTelemetryStore
    private let preferences: PreferencesStore
    private let petsStore: CodexPetsStore

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private var isInstalled = false
    private var lastRenderedState: MenuBarIconRenderer.VisualState?

    private var headerMenuItem: NSMenuItem?
    private var pinNotchMenuItem: NSMenuItem?
    private var hoverToExpandMenuItem: NSMenuItem?
    private var autoPeekMenuItem: NSMenuItem?
    private var playSoundsMenuItem: NSMenuItem?
    private var pauseResumeMenuItem: NSMenuItem?
    private var miniPetParentMenuItem: NSMenuItem?
    private var miniPetSubmenu: NSMenu?
    private var sessionsParentMenuItem: NSMenuItem?
    private var sessionsSubmenu: NSMenu?
    private var submenusSeparatorItem: NSMenuItem?
    private var openAntigravityMenuItem: NSMenuItem?

    public var onToggleNotch: (() -> Void)?
    public var onReplayWelcome: (() -> Void)?
    public var onOpenPreferences: (() -> Void)?
    public var onOpenSettingsTab: ((SettingsTab) -> Void)?
    public var onQuit: (() -> Void)?

    public init(
        store: AntigravityTelemetryStore,
        preferences: PreferencesStore,
        petsStore: CodexPetsStore = .shared,
        onToggleNotch: (() -> Void)? = nil,
        onReplayWelcome: (() -> Void)? = nil,
        onOpenPreferences: (() -> Void)? = nil,
        onOpenSettingsTab: ((SettingsTab) -> Void)? = nil,
        onQuit: (() -> Void)? = nil
    ) {
        self.store = store
        self.preferences = preferences
        self.petsStore = petsStore
        self.onToggleNotch = onToggleNotch
        self.onReplayWelcome = onReplayWelcome
        self.onOpenPreferences = onOpenPreferences
        self.onOpenSettingsTab = onOpenSettingsTab
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

    /// Immediately synchronizes the menu bar icon and dynamic menu item states.
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

        // Primary Notch & Telemetry Controls
        menu.addItem(makeMenuItem(
            title: "Toggle Notch HUD",
            action: #selector(handleToggleNotch),
            keyEquivalent: "",
            symbolName: "rectangle.topthird.inset.filled"
        ))

        menu.addItem(makeMenuItem(
            title: "Search Antigravity History…",
            action: #selector(handleSearchHistory),
            keyEquivalent: "",
            symbolName: "magnifyingglass"
        ))

        let pinItem = makeMenuItem(
            title: "Pin Notch Open",
            action: #selector(handleTogglePinNotch),
            keyEquivalent: "",
            symbolName: "pin"
        )
        menu.addItem(pinItem)
        pinNotchMenuItem = pinItem

        let hoverItem = makeMenuItem(
            title: "Hover to Expand",
            action: #selector(handleToggleHoverToExpand),
            keyEquivalent: "",
            symbolName: "cursorarrow.motionlines"
        )
        menu.addItem(hoverItem)
        hoverToExpandMenuItem = hoverItem

        let autoPeekItem = makeMenuItem(
            title: "Auto-Peek on Events",
            action: #selector(handleToggleAutoPeek),
            keyEquivalent: "",
            symbolName: "sparkles"
        )
        menu.addItem(autoPeekItem)
        autoPeekMenuItem = autoPeekItem

        let soundsItem = makeMenuItem(
            title: "Play Sounds",
            action: #selector(handleToggleSounds),
            keyEquivalent: "",
            symbolName: "speaker.wave.2"
        )
        menu.addItem(soundsItem)
        playSoundsMenuItem = soundsItem

        let pauseItem = makeMenuItem(
            title: "Pause Telemetry",
            action: #selector(handleTogglePauseTelemetry),
            keyEquivalent: "",
            symbolName: "pause.circle"
        )
        menu.addItem(pauseItem)
        pauseResumeMenuItem = pauseItem

        let submenusSep = NSMenuItem.separator()
        menu.addItem(submenusSep)
        submenusSeparatorItem = submenusSep

        // Mini Pet Submenu
        let petParent = makeMenuItem(
            title: "Mini Pet",
            action: nil,
            keyEquivalent: "",
            symbolName: "pawprint.fill"
        )
        let petSubmenu = NSMenu(title: "Mini Pet")
        petSubmenu.autoenablesItems = false
        petParent.submenu = petSubmenu
        menu.addItem(petParent)
        miniPetParentMenuItem = petParent
        miniPetSubmenu = petSubmenu

        // Active Session Submenu
        let sessionParent = makeMenuItem(
            title: "Active Session",
            action: nil,
            keyEquivalent: "",
            symbolName: "bubble.left.and.bubble.right"
        )
        let sessionSubmenu = NSMenu(title: "Active Session")
        sessionSubmenu.autoenablesItems = false
        sessionParent.submenu = sessionSubmenu
        menu.addItem(sessionParent)
        sessionsParentMenuItem = sessionParent
        sessionsSubmenu = sessionSubmenu

        menu.addItem(.separator())

        // Antigravity & Onboarding Quick Actions
        let openAntigravityItem = makeMenuItem(
            title: "Open Antigravity",
            action: #selector(handleOpenAntigravity),
            keyEquivalent: "",
            symbolName: "arrow.up.forward.app"
        )
        menu.addItem(openAntigravityItem)
        openAntigravityMenuItem = openAntigravityItem

        menu.addItem(makeMenuItem(
            title: "Replay Welcome & Setup",
            action: #selector(handleReplayWelcome),
            keyEquivalent: "",
            symbolName: "arrow.counterclockwise"
        ))

        menu.addItem(.separator())

        // Direct Settings Jump Links
        menu.addItem(makeMenuItem(
            title: "Mini Pet Gallery & Export…",
            action: #selector(handleOpenMiniPetSettings),
            keyEquivalent: "",
            symbolName: "square.grid.2x2"
        ))

        menu.addItem(makeMenuItem(
            title: "Notch HUD Settings…",
            action: #selector(handleOpenNotchHUDSettings),
            keyEquivalent: "",
            symbolName: "slider.horizontal.3"
        ))

        menu.addItem(makeMenuItem(
            title: "Preferences…",
            action: #selector(handleOpenPreferences),
            keyEquivalent: ",",
            symbolName: "gearshape"
        ))

        menu.addItem(.separator())

        menu.addItem(makeMenuItem(
            title: "Quit Grav",
            action: #selector(handleQuit),
            keyEquivalent: "q",
            symbolName: "power"
        ))
    }

    private func makeMenuItem(
        title: String,
        action: Selector?,
        keyEquivalent: String,
        symbolName: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = action != nil ? self : nil
        item.isEnabled = true
        if let symbolName,
           let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        {
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
        let contextPercent: Int? = (preferences.menuBarShowLiveMetrics && store.tokenMetrics.latestContextTokens > 0)
            ? Int((store.tokenMetrics.contextFillRatio * 100.0).rounded())
            : nil

        let snapshot = MenuBarStatusSnapshot(
            state: store.state,
            isPaused: isPaused,
            activeSessionTitle: store.activeSession?.title,
            tokenCount: preferences.menuBarShowLiveMetrics ? store.tokenMetrics.totalTokens : 0,
            contextPercent: contextPercent,
            isAppRunning: store.connectionStatus.isAppRunning,
            isBrainAccessible: store.connectionStatus.isBrainAccessible
        )

        if let headerMenuItem {
            let activePet = (preferences.miniPetEnabled && preferences.menuBarShowPetInHeader)
                ? petsStore.pet(withID: preferences.activeMiniPetID)
                : nil
            let headerView = MenuBarStatusHeaderView(
                snapshot: snapshot,
                activePet: activePet,
                petsStore: petsStore
            )
            let hostingView = NSHostingView(rootView: headerView)
            hostingView.frame = NSRect(x: 0, y: 0, width: 264, height: 48)
            headerMenuItem.view = hostingView
        }

        let showQuick = preferences.menuBarShowQuickToggles
        pinNotchMenuItem?.isHidden = !showQuick
        hoverToExpandMenuItem?.isHidden = !showQuick
        autoPeekMenuItem?.isHidden = !showQuick
        playSoundsMenuItem?.isHidden = !showQuick

        pinNotchMenuItem?.state = preferences.isNotchPinned ? .on : .off
        hoverToExpandMenuItem?.state = preferences.hoverToExpand ? .on : .off
        autoPeekMenuItem?.state = preferences.autoPeekOnEvents ? .on : .off
        playSoundsMenuItem?.state = preferences.playSounds ? .on : .off

        miniPetParentMenuItem?.isHidden = !preferences.menuBarShowMiniPetSubmenu
        sessionsParentMenuItem?.isHidden = !preferences.menuBarShowSessionsSubmenu
        submenusSeparatorItem?.isHidden = !preferences.menuBarShowMiniPetSubmenu && !preferences.menuBarShowSessionsSubmenu

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

        rebuildMiniPetSubmenu()
        rebuildSessionsSubmenu()
    }

    private func rebuildMiniPetSubmenu() {
        guard let submenu = miniPetSubmenu else { return }
        submenu.removeAllItems()

        let showItem = makeMenuItem(
            title: preferences.miniPetEnabled ? "Tuck Away Pet" : "Show Desktop Pet",
            action: #selector(handleToggleMiniPet),
            keyEquivalent: "",
            symbolName: preferences.miniPetEnabled ? "eye.slash" : "eye"
        )
        submenu.addItem(showItem)

        let interactItem = makeMenuItem(
            title: "Wave / Jump",
            action: #selector(handlePetInteract),
            keyEquivalent: "",
            symbolName: "hand.wave"
        )
        interactItem.isEnabled = preferences.miniPetEnabled
        submenu.addItem(interactItem)

        let bubbleItem = makeMenuItem(
            title: "Live Status Bubble",
            action: #selector(handleTogglePetBubble),
            keyEquivalent: "",
            symbolName: "text.bubble"
        )
        bubbleItem.state = preferences.miniPetShowBubble ? .on : .off
        submenu.addItem(bubbleItem)

        let floatItem = makeMenuItem(
            title: "Float Above Windows",
            action: #selector(handleTogglePetAlwaysOnTop),
            keyEquivalent: "",
            symbolName: "macwindow.on.rectangle"
        )
        floatItem.state = preferences.miniPetAlwaysOnTop ? .on : .off
        submenu.addItem(floatItem)

        submenu.addItem(.separator())

        let placementHeader = NSMenuItem(title: "Snap Position", action: nil, keyEquivalent: "")
        placementHeader.isEnabled = false
        submenu.addItem(placementHeader)

        for placement in MiniPetPlacement.allCases {
            let item = makeMenuItem(
                title: placement.displayName,
                action: #selector(handleSelectPetPlacement(_:)),
                keyEquivalent: ""
            )
            item.representedObject = placement.rawValue
            item.state = preferences.miniPetPlacement == placement ? .on : .off
            submenu.addItem(item)
        }

        submenu.addItem(.separator())

        let petsHeader = NSMenuItem(title: "Installed Pets", action: nil, keyEquivalent: "")
        petsHeader.isEnabled = false
        submenu.addItem(petsHeader)

        for pet in petsStore.installedPets {
            let item = makeMenuItem(
                title: pet.displayName,
                action: #selector(handleEquipPet(_:)),
                keyEquivalent: ""
            )
            item.representedObject = pet.id
            item.state = (preferences.activeMiniPetID == pet.id && preferences.miniPetEnabled) ? .on : .off
            submenu.addItem(item)
        }

        submenu.addItem(.separator())

        submenu.addItem(makeMenuItem(
            title: "Browse codex-pets.net & Export GIFs…",
            action: #selector(handleOpenMiniPetSettings),
            keyEquivalent: "",
            symbolName: "arrow.down.circle"
        ))
    }

    private func rebuildSessionsSubmenu() {
        guard let submenu = sessionsSubmenu else { return }
        submenu.removeAllItems()

        if let sessionsParentMenuItem {
            let unread = store.unreadSessionCount
            sessionsParentMenuItem.title = unread > 0
                ? "Active Session (\(unread) unread)"
                : "Active Session"
        }

        if store.sessions.isEmpty {
            let emptyItem = NSMenuItem(title: "No active Antigravity conversations", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
        } else {
            for session in store.sessions.prefix(12) {
                let cleanTitle = session.title
                    .replacingOccurrences(of: "<USER_REQUEST>", with: "")
                    .replacingOccurrences(of: "</USER_REQUEST>", with: "")
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let baseLabel = cleanTitle.isEmpty ? session.id : String(cleanTitle.prefix(48))
                let label = store.isSessionUnread(session.id) ? "● \(baseLabel)" : baseLabel
                let item = makeMenuItem(
                    title: label,
                    action: #selector(handleSelectSession(_:)),
                    keyEquivalent: ""
                )
                item.representedObject = session.id
                item.state = session.id == store.activeSession?.id ? .on : .off
                submenu.addItem(item)
            }
        }

        submenu.addItem(.separator())

        let revealItem = makeMenuItem(
            title: "Reveal Transcript in Finder",
            action: #selector(handleRevealTranscript),
            keyEquivalent: "",
            symbolName: "folder"
        )
        revealItem.isEnabled = store.activeSession != nil
        submenu.addItem(revealItem)

        if store.state.isActive {
            submenu.addItem(makeMenuItem(
                title: "Mark Idle",
                action: #selector(handleForceIdle),
                keyEquivalent: "",
                symbolName: "moon.zzz"
            ))
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

    @objc private func handleSearchHistory() {
        NotificationCenter.default.post(name: .gravOpenNotchSpotlight, object: nil)
    }

    @objc private func handleTogglePinNotch() {
        preferences.isNotchPinned.toggle()
        refresh()
    }

    @objc private func handleToggleHoverToExpand() {
        preferences.hoverToExpand.toggle()
        refresh()
    }

    @objc private func handleToggleAutoPeek() {
        preferences.autoPeekOnEvents.toggle()
        refresh()
    }

    @objc private func handleToggleSounds() {
        preferences.playSounds.toggle()
        refresh()
    }

    @objc private func handleTogglePauseTelemetry() {
        let nextPaused = !isPaused
        preferences.isTelemetryPaused = nextPaused
        store.setPaused(nextPaused)
        refresh()
    }

    @objc private func handleToggleMiniPet() {
        preferences.miniPetEnabled.toggle()
        refresh()
    }

    @objc private func handlePetInteract() {
        petsStore.triggerInteractionReaction()
    }

    @objc private func handleTogglePetBubble() {
        preferences.miniPetShowBubble.toggle()
        refresh()
    }

    @objc private func handleTogglePetAlwaysOnTop() {
        preferences.miniPetAlwaysOnTop.toggle()
        refresh()
    }

    @objc private func handleSelectPetPlacement(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let placement = MiniPetPlacement(rawValue: raw)
        else { return }
        if placement != .free {
            preferences.miniPetOriginX = nil
            preferences.miniPetOriginY = nil
        }
        preferences.miniPetPlacement = placement
        preferences.miniPetEnabled = true
        refresh()
    }

    @objc private func handleEquipPet(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        preferences.activeMiniPetID = id
        preferences.miniPetEnabled = true
        refresh()
    }

    @objc private func handleSelectSession(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        store.selectSessionByID(id)
        refresh()
    }

    @objc private func handleRevealTranscript() {
        store.revealActiveTranscriptInFinder()
    }

    @objc private func handleForceIdle() {
        store.forceSettleIdle()
        refresh()
    }

    @objc private func handleReplayWelcome() {
        onReplayWelcome?()
    }

    @objc private func handleOpenAntigravity() {
        store.activateAntigravityApp()
    }

    @objc private func handleOpenMiniPetSettings() {
        if let onOpenSettingsTab {
            onOpenSettingsTab(.miniPet)
        } else {
            onOpenPreferences?()
        }
    }

    @objc private func handleOpenNotchHUDSettings() {
        if let onOpenSettingsTab {
            onOpenSettingsTab(.notchHUD)
        } else {
            onOpenPreferences?()
        }
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
    let contextPercent: Int?
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
            let clean = activeSessionTitle
                .replacingOccurrences(of: "<USER_REQUEST>", with: "")
                .replacingOccurrences(of: "</USER_REQUEST>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append(clean.isEmpty ? "Connected" : clean)
        } else {
            parts.append(isAppRunning ? "Connected" : "Local watcher ready")
        }
        if tokenCount > 0 {
            parts.append("\(TokenMetrics.formatCompact(tokenCount)) tok")
        }
        if let contextPercent {
            parts.append("\(contextPercent)% ctx")
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
    let activePet: InstalledCodexPet?
    let petsStore: CodexPetsStore

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

            Spacer(minLength: 4)

            if let activePet {
                CodexPetSpriteView(
                    pet: activePet,
                    state: .idle,
                    size: 24,
                    speed: 1.0,
                    reduceMotion: true,
                    petsStore: petsStore
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(width: 264, height: 48, alignment: .leading)
    }
}
