import AppKit
import SwiftUI

/// `@MainActor` controller managing Grav's single-instance native macOS Settings window.
/// Configured at 520×440 with a unified macOS titlebar and full Light/Dark appearance adaptability.
@MainActor
public final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static let windowSize = NSSize(width: 520, height: 440)
    private static let autosaveName = NSWindow.FrameAutosaveName("GravSettingsWindow")

    private let preferences: PreferencesStore
    private let store: AntigravityTelemetryStore
    private let navigation = SettingsNavigationModel()
    private var hasPositionedWindow = false

    public var onReplayWelcome: (() -> Void)?

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

    /// Presents or focuses the single Settings window, optionally selecting a specific tab.
    public func show(tab: SettingsTab? = nil) {
        if let tab {
            navigation.selectedTab = tab
        }

        let settingsWindow = ensureWindow()
        preferences.refreshLaunchAtLoginStatus()
        store.refreshConnectionStatus()

        if !hasPositionedWindow {
            if !settingsWindow.setFrameUsingName(Self.autosaveName) {
                settingsWindow.center()
            }
            hasPositionedWindow = true
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow.makeKeyAndOrderFront(nil)
        settingsWindow.orderFrontRegardless()
    }

    /// Closes the Settings window if currently open.
    public func closeWindow() {
        window?.close()
    }

    /// Whether the Settings window is currently visible on screen.
    public var isVisible: Bool {
        window?.isVisible ?? false
    }

    // MARK: - Window Construction

    private func ensureWindow() -> NSWindow {
        if let existing = window {
            return existing
        }

        let rootView = SettingsView(
            preferences: preferences,
            store: store,
            navigation: navigation,
            onReplayWelcome: { [weak self] in
                self?.onReplayWelcome?()
            }
        )

        let hostingController = NSHostingController(rootView: rootView)
        hostingController.preferredContentSize = Self.windowSize

        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        let createdWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        createdWindow.title = "Grav Settings"
        createdWindow.toolbarStyle = .unified
        createdWindow.titleVisibility = .visible
        createdWindow.titlebarAppearsTransparent = false
        createdWindow.appearance = nil // Follow macOS Light and Dark Mode dynamically
        createdWindow.isReleasedWhenClosed = false
        createdWindow.contentMinSize = Self.windowSize
        createdWindow.contentMaxSize = Self.windowSize
        createdWindow.setContentSize(Self.windowSize)
        createdWindow.setFrameAutosaveName(Self.autosaveName)
        createdWindow.collectionBehavior = [.moveToActiveSpace]
        createdWindow.contentViewController = hostingController
        createdWindow.delegate = self

        self.window = createdWindow
        return createdWindow
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        _ = notification
    }
}
