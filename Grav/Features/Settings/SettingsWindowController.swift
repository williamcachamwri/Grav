import AppKit
import Observation
import SwiftUI

/// Dedicated window controller for Grav's System Settings–style Preferences window,
/// ported 1:1 from Snapzy's `PreferencesWindowController`.
///
/// Manages NSWindow lifecycle, 800×620 default / 700×520 minimum bounds, non-collapsible sidebar
/// AppKit enforcement, dynamic `appearanceMode` syncing, and `.regular` ↔ `.accessory` elevation.
@MainActor
public final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    /// Default content size: wide enough for the 220pt sidebar and grouped form cards.
    public static let defaultContentSize = CGSize(width: 800, height: 620)

    /// Minimum window size to prevent label truncation.
    public static let minimumContentSize = CGSize(width: 700, height: 520)

    private let preferences: PreferencesStore
    private let store: AntigravityTelemetryStore
    private let navigationState = SettingsNavigationState()

    private var didElevateActivationPolicy = false
    private var isObservingWindowState = false

    public var onReplayWelcome: (() -> Void)?
    public var onToggleNotch: (() -> Void)?

    public var isVisible: Bool {
        window?.isVisible ?? false
    }

    public init(
        preferences: PreferencesStore,
        store: AntigravityTelemetryStore,
        onReplayWelcome: (() -> Void)? = nil
    ) {
        self.preferences = preferences
        self.store = store
        self.onReplayWelcome = onReplayWelcome
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for SettingsWindowController")
    }

    /// Presents the Settings window, optionally navigating directly to a specific tab.
    public func show(tab: SettingsTab? = nil) {
        if let tab {
            navigationState.select(tab)
        }

        // Elevate to regular app so Grav appears in the menu bar and takes key focus cleanly.
        if !didElevateActivationPolicy {
            NSApp.setActivationPolicy(.regular)
            didElevateActivationPolicy = true
        }

        NSApp.activate(ignoringOtherApps: true)

        let targetWindow = self.window ?? makeWindow()
        self.window = targetWindow

        preferences.refreshLaunchAtLoginStatus()
        store.refreshConnectionStatus()

        if !targetWindow.isVisible {
            targetWindow.center()
        }

        targetWindow.makeKeyAndOrderFront(nil)
        configureNonCollapsibleSidebar()
    }

    /// Closes the Settings window if currently open.
    public func closeWindow() {
        window?.performClose(nil)
    }

    // MARK: - Window Construction

    private func makeWindow() -> NSWindow {
        let created = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        created.title = navigationState.selectedTab.title
        created.delegate = self
        created.isReleasedWhenClosed = false
        created.level = .normal
        created.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
        created.contentMinSize = Self.minimumContentSize

        // Let the sidebar material run full height behind the macOS traffic lights.
        created.titlebarAppearsTransparent = true

        // Sync AppKit appearance and surface background with user's selected mode.
        created.appearance = preferences.appearanceMode.nsAppearance
        created.backgroundColor = NSColor.windowBackgroundColor

        let rootView = SettingsView(
            preferences: preferences,
            store: store,
            navigationState: navigationState,
            onReplayWelcome: { [weak self] in
                self?.onReplayWelcome?()
            },
            onToggleNotch: { [weak self] in
                self?.onToggleNotch?()
            }
        )
        created.contentView = NSHostingView(rootView: rootView)

        isObservingWindowState = true
        observeWindowState(for: created)

        return created
    }

    /// Dynamically syncs `window.appearance` and `window.title` with `@Observable` stores.
    private func observeWindowState(for targetWindow: NSWindow) {
        guard isObservingWindowState else { return }

        withObservationTracking {
            let mode = preferences.appearanceMode
            let tabTitle = navigationState.selectedTab.title
            targetWindow.appearance = mode.nsAppearance
            targetWindow.backgroundColor = NSColor.windowBackgroundColor
            targetWindow.title = tabTitle
        } onChange: { [weak self, weak targetWindow] in
            Task { @MainActor [weak self, weak targetWindow] in
                guard let self, let targetWindow, self.window === targetWindow, self.isObservingWindowState else {
                    return
                }
                self.observeWindowState(for: targetWindow)
            }
        }
    }

    /// Ensures the underlying AppKit split view item for the sidebar cannot be collapsed.
    private func configureNonCollapsibleSidebar() {
        Task { @MainActor [weak self] in
            guard let window = self?.window,
                  let splitView = window.contentView?.firstDescendant(ofType: NSSplitView.self),
                  let splitViewController = splitView.delegate as? NSSplitViewController,
                  let sidebarItem = splitViewController.splitViewItems.first
            else {
                return
            }

            if sidebarItem.canCollapse {
                sidebarItem.canCollapse = false
            }
            if sidebarItem.isCollapsed {
                sidebarItem.isCollapsed = false
            }
        }
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        let visibleNormalWindows = NSApp.windows.filter { win in
            win.isVisible
                && win !== self.window
                && win.className != "NSStatusBarWindow"
                && win.level == .normal
        }

        // Revert to accessory (menu bar / notch only) mode when no normal windows remain.
        if visibleNormalWindows.isEmpty && didElevateActivationPolicy {
            NSApp.setActivationPolicy(.accessory)
            didElevateActivationPolicy = false
        }

        // Tear down the SwiftUI hierarchy on close so an ordered-out window consumes zero idle CPU.
        guard let closingWindow = notification.object as? NSWindow, closingWindow === window else {
            return
        }

        isObservingWindowState = false
        Task { @MainActor [weak self, weak closingWindow] in
            guard let self,
                  let closingWindow,
                  self.window === closingWindow,
                  !closingWindow.isVisible
            else {
                return
            }
            closingWindow.contentView = nil
            closingWindow.delegate = nil
            self.window = nil
        }
    }
}
