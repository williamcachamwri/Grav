import AppKit
import Foundation
import NotchKit
import SwiftUI

/// Primary macOS application delegate owning Grav's accessory lifecycle, real telemetry store,
/// NotchKit HUD coordinator, menu bar status item, Settings window, and Onboarding flow.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences = PreferencesStore()
    let telemetryStore = AntigravityTelemetryStore()

    private(set) var notchHUD: NotchHUDCoordinator?
    private(set) var desktopPet: DesktopPetCoordinator?
    private(set) var menuBarController: MenuBarController?
    private(set) var settingsWindowController: SettingsWindowController?
    private(set) var onboardingWindowController: OnboardingWindowController?

    private var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification

        // Run as a pure menu-bar / notch accessory app (no Dock icon)
        NSApp.setActivationPolicy(.accessory)
        if let brandIcon = NSImage(named: "GravLogo") {
            NSApp.applicationIconImage = brandIcon
        }

        // Avoid presenting live windows or global event taps when hosted by XCTest
        guard !isRunningUnderXCTest else { return }

        setupControllers()
        startTelemetry()

        if !preferences.hasCompletedOnboarding {
            showOnboarding(replay: false)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = notification
        telemetryStore.stop()
        GlobalHotkeyManager.shared.uninstall()
        notchHUD?.uninstall()
        desktopPet?.uninstall()
        menuBarController?.uninstall()
        onboardingWindowController?.close()
        settingsWindowController?.closeWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        _ = sender
        return false
    }

    // MARK: - Wiring

    private func setupControllers() {
        let settings = SettingsWindowController(
            preferences: preferences,
            store: telemetryStore,
            onReplayWelcome: { [weak self] in
                self?.showOnboarding(replay: true)
            }
        )
        settings.onToggleNotch = { [weak self] in
            self?.notchHUD?.toggle()
        }
        self.settingsWindowController = settings

        let hud = NotchHUDCoordinator(
            store: telemetryStore,
            preferences: preferences,
            onOpenSettings: { [weak self] in
                self?.openSettings()
            }
        )
        self.notchHUD = hud
        hud.install()

        let petCoordinator = DesktopPetCoordinator(
            store: telemetryStore,
            preferences: preferences,
            onOpenPetSettings: { [weak self] in
                self?.openSettings(tab: .miniPet)
            },
            onFocusAntigravity: { [weak self] in
                self?.telemetryStore.activateAntigravityApp()
            },
            onToggleNotch: { [weak self] in
                self?.notchHUD?.toggle()
            }
        )
        self.desktopPet = petCoordinator
        petCoordinator.install()

        let hotkeys = GlobalHotkeyManager.shared
        hotkeys.onToggleNotch = { [weak self] in
            self?.notchHUD?.toggle()
        }
        hotkeys.onToggleMiniPet = { [weak self] in
            self?.preferences.miniPetEnabled.toggle()
        }
        hotkeys.onFocusAntigravity = { [weak self] in
            self?.telemetryStore.activateAntigravityApp()
        }
        hotkeys.install(preferences: preferences)
        observeGlobalHotkeys()

        let menuBar = MenuBarController(
            store: telemetryStore,
            preferences: preferences,
            onToggleNotch: { [weak self] in
                self?.notchHUD?.toggle()
            },
            onReplayWelcome: { [weak self] in
                self?.showOnboarding(replay: true)
            },
            onOpenPreferences: { [weak self] in
                self?.openSettings()
            },
            onOpenSettingsTab: { [weak self] tab in
                self?.openSettings(tab: tab)
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )
        self.menuBarController = menuBar
        if preferences.showMenuBarIcon {
            menuBar.install()
        }
        observeMenuBarVisibility()

        let onboarding = OnboardingWindowController(
            store: telemetryStore,
            preferences: preferences
        )
        onboarding.notchTargetPointProvider = { [weak self] in
            self?.notchHUD?.notchTargetScreenPoint() ?? .zero
        }
        onboarding.onTriggerNotchPeek = { [weak self] in
            self?.notchHUD?.triggerWelcomePeek()
        }
        onboarding.onComplete = { [weak self] in
            self?.preferences.hasCompletedOnboarding = true
            self?.notchHUD?.syncPreferences()
        }
        self.onboardingWindowController = onboarding
    }

    private func startTelemetry() {
        telemetryStore.setPaused(preferences.isTelemetryPaused)
        telemetryStore.start()
    }

    private func observeMenuBarVisibility() {
        withObservationTracking {
            _ = preferences.showMenuBarIcon
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.preferences.showMenuBarIcon {
                    self.menuBarController?.install()
                } else {
                    self.menuBarController?.uninstall()
                }
                self.observeMenuBarVisibility()
            }
        }
    }

    private func observeGlobalHotkeys() {
        withObservationTracking {
            _ = preferences.globalHotkeysEnabled
            _ = preferences.hotkeyToggleNotch
            _ = preferences.hotkeyToggleMiniPet
            _ = preferences.hotkeyFocusAntigravity
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                GlobalHotkeyManager.shared.sync(with: self.preferences)
                self.observeGlobalHotkeys()
            }
        }
    }

    // MARK: - Actions

    func showOnboarding(replay: Bool) {
        onboardingWindowController?.show(replay: replay)
    }

    func openSettings(tab: SettingsTab? = nil) {
        settingsWindowController?.show(tab: tab)
    }
}
