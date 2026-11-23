import AppKit
import Foundation
import Observation
import ServiceManagement
import SwiftUI

/// User preference for app appearance (System / Light / Dark), matching Snapzy's `AppearanceMode`.
public enum GravAppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    public var id: String { rawValue }

    public var displayName: String { rawValue }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    public var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// Shared UserDefaults keys used across `PreferencesStore`, `@AppStorage`, and Liquid Glass surfaces.
public enum GravPreferenceKeys {
    public static let hasCompletedOnboarding = "grav.hasCompletedOnboarding"
    public static let hoverToExpand = "grav.hoverToExpand"
    public static let autoPeekOnEvents = "grav.autoPeekOnEvents"
    public static let isNotchPinned = "grav.isNotchPinned"
    public static let isTelemetryPaused = "grav.isTelemetryPaused"
    public static let launchAtLogin = "grav.launchAtLogin"
    public static let useLiquidGlass = "grav.useLiquidGlass"
    public static let appearanceMode = "grav.appearanceMode"
    public static let showMenuBarIcon = "grav.showMenuBarIcon"
    public static let menuBarShowPetInHeader = "grav.menuBarShowPetInHeader"
    public static let menuBarShowLiveMetrics = "grav.menuBarShowLiveMetrics"
    public static let menuBarShowQuickToggles = "grav.menuBarShowQuickToggles"
    public static let menuBarShowMiniPetSubmenu = "grav.menuBarShowMiniPetSubmenu"
    public static let menuBarShowSessionsSubmenu = "grav.menuBarShowSessionsSubmenu"
    public static let playSounds = "grav.playSounds"

    // Mini Pet preferences (Codex-style floating desktop companion)
    public static let miniPetEnabled = "grav.miniPetEnabled"
    public static let activeMiniPetID = "grav.activeMiniPetID"
    public static let miniPetPlacement = "grav.miniPetPlacement"
    public static let miniPetSize = "grav.miniPetSize"
    public static let miniPetSpeed = "grav.miniPetSpeed"
    public static let miniPetInteractiveClick = "grav.miniPetInteractiveClick"
    public static let miniPetRoaming = "grav.miniPetRoaming"
    public static let miniPetShowBubble = "grav.miniPetShowBubble"
    public static let miniPetAlwaysOnTop = "grav.miniPetAlwaysOnTop"
    public static let miniPetAutoHideFullscreen = "grav.miniPetAutoHideFullscreen"
    public static let miniPetOriginX = "grav.miniPetOriginX"
    public static let miniPetOriginY = "grav.miniPetOriginY"

    // Expanded Notch HUD & Smart Attention Rules
    public static let hoverOpenDelay = "grav.hoverOpenDelay"
    public static let showCollapsedTokens = "grav.showCollapsedTokens"
    public static let showCollapsedFocus = "grav.showCollapsedFocus"
    public static let showCollapsedStepProgress = "grav.showCollapsedStepProgress"
    public static let autoExpandOnNeedsInput = "grav.autoExpandOnNeedsInput"
    public static let hapticsEnabled = "grav.hapticsEnabled"
    public static let smartAlertMinDurationSeconds = "grav.smartAlertMinDurationSeconds"
    public static let urgentAlertWhenBackgrounded = "grav.urgentAlertWhenBackgrounded"
    public static let notifyOnTurnCompleted = "grav.notifyOnTurnCompleted"
    public static let notifyOnFailure = "grav.notifyOnFailure"

    // Global Hotkeys
    public static let globalHotkeysEnabled = "grav.globalHotkeysEnabled"
    public static let hotkeyToggleNotch = "grav.hotkeyToggleNotch"
    public static let hotkeyToggleMiniPet = "grav.hotkeyToggleMiniPet"
    public static let hotkeyFocusAntigravity = "grav.hotkeyFocusAntigravity"
}

/// User-configurable preferences for Grav's Notch HUD, Liquid Glass, Appearance, and macOS integration.
@MainActor
@Observable
public final class PreferencesStore {
    private let defaults: UserDefaults

    public var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: GravPreferenceKeys.hasCompletedOnboarding) }
    }

    public var hoverToExpand: Bool {
        didSet { defaults.set(hoverToExpand, forKey: GravPreferenceKeys.hoverToExpand) }
    }

    public var autoPeekOnEvents: Bool {
        didSet { defaults.set(autoPeekOnEvents, forKey: GravPreferenceKeys.autoPeekOnEvents) }
    }

    public var isNotchPinned: Bool {
        didSet { defaults.set(isNotchPinned, forKey: GravPreferenceKeys.isNotchPinned) }
    }

    public var isTelemetryPaused: Bool {
        didSet { defaults.set(isTelemetryPaused, forKey: GravPreferenceKeys.isTelemetryPaused) }
    }

    public var useLiquidGlass: Bool {
        didSet { defaults.set(useLiquidGlass, forKey: GravPreferenceKeys.useLiquidGlass) }
    }

    public var appearanceMode: GravAppearanceMode {
        didSet { defaults.set(appearanceMode.rawValue, forKey: GravPreferenceKeys.appearanceMode) }
    }

    public var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: GravPreferenceKeys.showMenuBarIcon) }
    }

    public var menuBarShowPetInHeader: Bool {
        didSet { defaults.set(menuBarShowPetInHeader, forKey: GravPreferenceKeys.menuBarShowPetInHeader) }
    }

    public var menuBarShowLiveMetrics: Bool {
        didSet { defaults.set(menuBarShowLiveMetrics, forKey: GravPreferenceKeys.menuBarShowLiveMetrics) }
    }

    public var menuBarShowQuickToggles: Bool {
        didSet { defaults.set(menuBarShowQuickToggles, forKey: GravPreferenceKeys.menuBarShowQuickToggles) }
    }

    public var menuBarShowMiniPetSubmenu: Bool {
        didSet { defaults.set(menuBarShowMiniPetSubmenu, forKey: GravPreferenceKeys.menuBarShowMiniPetSubmenu) }
    }

    public var menuBarShowSessionsSubmenu: Bool {
        didSet { defaults.set(menuBarShowSessionsSubmenu, forKey: GravPreferenceKeys.menuBarShowSessionsSubmenu) }
    }

    public var playSounds: Bool {
        didSet { defaults.set(playSounds, forKey: GravPreferenceKeys.playSounds) }
    }

    // MARK: - Mini Pet Preferences

    public var miniPetEnabled: Bool {
        didSet { defaults.set(miniPetEnabled, forKey: GravPreferenceKeys.miniPetEnabled) }
    }

    public var activeMiniPetID: String {
        didSet { defaults.set(activeMiniPetID, forKey: GravPreferenceKeys.activeMiniPetID) }
    }

    public var miniPetPlacement: MiniPetPlacement {
        didSet { defaults.set(miniPetPlacement.rawValue, forKey: GravPreferenceKeys.miniPetPlacement) }
    }

    public var miniPetSize: Double {
        didSet { defaults.set(miniPetSize, forKey: GravPreferenceKeys.miniPetSize) }
    }

    public var miniPetSpeed: Double {
        didSet { defaults.set(miniPetSpeed, forKey: GravPreferenceKeys.miniPetSpeed) }
    }

    public var miniPetInteractiveClick: Bool {
        didSet { defaults.set(miniPetInteractiveClick, forKey: GravPreferenceKeys.miniPetInteractiveClick) }
    }

    public var miniPetRoaming: Bool {
        didSet { defaults.set(miniPetRoaming, forKey: GravPreferenceKeys.miniPetRoaming) }
    }

    public var miniPetShowBubble: Bool {
        didSet { defaults.set(miniPetShowBubble, forKey: GravPreferenceKeys.miniPetShowBubble) }
    }

    public var miniPetAlwaysOnTop: Bool {
        didSet { defaults.set(miniPetAlwaysOnTop, forKey: GravPreferenceKeys.miniPetAlwaysOnTop) }
    }

    public var miniPetAutoHideFullscreen: Bool {
        didSet { defaults.set(miniPetAutoHideFullscreen, forKey: GravPreferenceKeys.miniPetAutoHideFullscreen) }
    }

    /// Saved screen X coordinate when user drags the desktop pet freely (`nil` uses `miniPetPlacement` snap).
    public var miniPetOriginX: Double? {
        didSet {
            if let miniPetOriginX {
                defaults.set(miniPetOriginX, forKey: GravPreferenceKeys.miniPetOriginX)
            } else {
                defaults.removeObject(forKey: GravPreferenceKeys.miniPetOriginX)
            }
        }
    }

    /// Saved screen Y coordinate when user drags the desktop pet freely (`nil` uses `miniPetPlacement` snap).
    public var miniPetOriginY: Double? {
        didSet {
            if let miniPetOriginY {
                defaults.set(miniPetOriginY, forKey: GravPreferenceKeys.miniPetOriginY)
            } else {
                defaults.removeObject(forKey: GravPreferenceKeys.miniPetOriginY)
            }
        }
    }

    // MARK: - Expanded Notch HUD & UI Customizations

    public var hoverOpenDelay: Double {
        didSet { defaults.set(hoverOpenDelay, forKey: GravPreferenceKeys.hoverOpenDelay) }
    }

    public var showCollapsedTokens: Bool {
        didSet { defaults.set(showCollapsedTokens, forKey: GravPreferenceKeys.showCollapsedTokens) }
    }

    public var showCollapsedFocus: Bool {
        didSet { defaults.set(showCollapsedFocus, forKey: GravPreferenceKeys.showCollapsedFocus) }
    }

    public var showCollapsedStepProgress: Bool {
        didSet { defaults.set(showCollapsedStepProgress, forKey: GravPreferenceKeys.showCollapsedStepProgress) }
    }

    public var autoExpandOnNeedsInput: Bool {
        didSet { defaults.set(autoExpandOnNeedsInput, forKey: GravPreferenceKeys.autoExpandOnNeedsInput) }
    }

    public var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: GravPreferenceKeys.hapticsEnabled) }
    }

    // MARK: - Smart Attention Rules

    /// Minimum active turn duration (seconds) before playing completion chime/peek (`0` = always).
    public var smartAlertMinDurationSeconds: Double {
        didSet { defaults.set(smartAlertMinDurationSeconds, forKey: GravPreferenceKeys.smartAlertMinDurationSeconds) }
    }

    /// Prominently alert when Antigravity is backgrounded and hits a failure or asks for input.
    public var urgentAlertWhenBackgrounded: Bool {
        didSet { defaults.set(urgentAlertWhenBackgrounded, forKey: GravPreferenceKeys.urgentAlertWhenBackgrounded) }
    }

    public var notifyOnTurnCompleted: Bool {
        didSet { defaults.set(notifyOnTurnCompleted, forKey: GravPreferenceKeys.notifyOnTurnCompleted) }
    }

    public var notifyOnFailure: Bool {
        didSet { defaults.set(notifyOnFailure, forKey: GravPreferenceKeys.notifyOnFailure) }
    }

    // MARK: - Global Hotkeys

    public var globalHotkeysEnabled: Bool {
        didSet { defaults.set(globalHotkeysEnabled, forKey: GravPreferenceKeys.globalHotkeysEnabled) }
    }

    public var hotkeyToggleNotch: GravHotkeyShortcut? {
        didSet { Self.saveHotkey(hotkeyToggleNotch, key: GravPreferenceKeys.hotkeyToggleNotch, to: defaults) }
    }

    public var hotkeyToggleMiniPet: GravHotkeyShortcut? {
        didSet { Self.saveHotkey(hotkeyToggleMiniPet, key: GravPreferenceKeys.hotkeyToggleMiniPet, to: defaults) }
    }

    public var hotkeyFocusAntigravity: GravHotkeyShortcut? {
        didSet { Self.saveHotkey(hotkeyFocusAntigravity, key: GravPreferenceKeys.hotkeyFocusAntigravity, to: defaults) }
    }

    public var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: GravPreferenceKeys.launchAtLogin)
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    public private(set) var launchAtLoginError: String?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasCompletedOnboarding = defaults.bool(forKey: GravPreferenceKeys.hasCompletedOnboarding)
        self.hoverToExpand = defaults.object(forKey: GravPreferenceKeys.hoverToExpand) as? Bool ?? true
        self.autoPeekOnEvents = defaults.object(forKey: GravPreferenceKeys.autoPeekOnEvents) as? Bool ?? true
        self.isNotchPinned = defaults.bool(forKey: GravPreferenceKeys.isNotchPinned)
        self.isTelemetryPaused = defaults.bool(forKey: GravPreferenceKeys.isTelemetryPaused)
        self.useLiquidGlass = defaults.object(forKey: GravPreferenceKeys.useLiquidGlass) as? Bool ?? true
        self.showMenuBarIcon = defaults.object(forKey: GravPreferenceKeys.showMenuBarIcon) as? Bool ?? true
        self.menuBarShowPetInHeader = defaults.object(forKey: GravPreferenceKeys.menuBarShowPetInHeader) as? Bool ?? true
        self.menuBarShowLiveMetrics = defaults.object(forKey: GravPreferenceKeys.menuBarShowLiveMetrics) as? Bool ?? true
        self.menuBarShowQuickToggles = defaults.object(forKey: GravPreferenceKeys.menuBarShowQuickToggles) as? Bool ?? true
        self.menuBarShowMiniPetSubmenu = defaults.object(forKey: GravPreferenceKeys.menuBarShowMiniPetSubmenu) as? Bool ?? true
        self.menuBarShowSessionsSubmenu = defaults.object(forKey: GravPreferenceKeys.menuBarShowSessionsSubmenu) as? Bool ?? true
        self.playSounds = defaults.object(forKey: GravPreferenceKeys.playSounds) as? Bool ?? true

        self.miniPetEnabled = defaults.object(forKey: GravPreferenceKeys.miniPetEnabled) as? Bool ?? true
        self.activeMiniPetID = defaults.string(forKey: GravPreferenceKeys.activeMiniPetID) ?? "super-saiyan-goku-combat"
        if let rawPlacement = defaults.string(forKey: GravPreferenceKeys.miniPetPlacement),
           let parsedPlacement = MiniPetPlacement(rawValue: rawPlacement)
        {
            self.miniPetPlacement = parsedPlacement
        } else {
            self.miniPetPlacement = .topRight
        }
        let storedPetSize = defaults.object(forKey: GravPreferenceKeys.miniPetSize) as? Double ?? 84.0
        // Migrate legacy tiny Notch-era values (< 48) cleanly to the floating desktop default (84 pt)
        self.miniPetSize = storedPetSize < 48.0 ? 84.0 : min(144.0, max(48.0, storedPetSize))
        let storedPetSpeed = defaults.object(forKey: GravPreferenceKeys.miniPetSpeed) as? Double ?? 1.0
        self.miniPetSpeed = min(2.0, max(0.5, storedPetSpeed))
        self.miniPetInteractiveClick = defaults.object(forKey: GravPreferenceKeys.miniPetInteractiveClick) as? Bool ?? true
        // Default false so the pet strictly mirrors exact Antigravity telemetry state without random idle actions.
        self.miniPetRoaming = defaults.object(forKey: GravPreferenceKeys.miniPetRoaming) as? Bool ?? false
        self.miniPetShowBubble = defaults.object(forKey: GravPreferenceKeys.miniPetShowBubble) as? Bool ?? true
        self.miniPetAlwaysOnTop = defaults.object(forKey: GravPreferenceKeys.miniPetAlwaysOnTop) as? Bool ?? true
        self.miniPetAutoHideFullscreen = defaults.object(forKey: GravPreferenceKeys.miniPetAutoHideFullscreen) as? Bool ?? true
        self.miniPetOriginX = defaults.object(forKey: GravPreferenceKeys.miniPetOriginX) as? Double
        self.miniPetOriginY = defaults.object(forKey: GravPreferenceKeys.miniPetOriginY) as? Double

        let storedHoverDelay = defaults.object(forKey: GravPreferenceKeys.hoverOpenDelay) as? Double ?? 0.15
        self.hoverOpenDelay = min(0.50, max(0.05, storedHoverDelay))
        self.showCollapsedTokens = defaults.object(forKey: GravPreferenceKeys.showCollapsedTokens) as? Bool ?? true
        self.showCollapsedFocus = defaults.object(forKey: GravPreferenceKeys.showCollapsedFocus) as? Bool ?? true
        self.showCollapsedStepProgress = defaults.object(forKey: GravPreferenceKeys.showCollapsedStepProgress) as? Bool ?? true
        self.autoExpandOnNeedsInput = defaults.object(forKey: GravPreferenceKeys.autoExpandOnNeedsInput) as? Bool ?? true
        self.hapticsEnabled = defaults.object(forKey: GravPreferenceKeys.hapticsEnabled) as? Bool ?? true
        self.smartAlertMinDurationSeconds = defaults.object(forKey: GravPreferenceKeys.smartAlertMinDurationSeconds) as? Double ?? 0.0
        self.urgentAlertWhenBackgrounded = defaults.object(forKey: GravPreferenceKeys.urgentAlertWhenBackgrounded) as? Bool ?? true
        self.notifyOnTurnCompleted = defaults.object(forKey: GravPreferenceKeys.notifyOnTurnCompleted) as? Bool ?? true
        self.notifyOnFailure = defaults.object(forKey: GravPreferenceKeys.notifyOnFailure) as? Bool ?? true

        self.globalHotkeysEnabled = defaults.object(forKey: GravPreferenceKeys.globalHotkeysEnabled) as? Bool ?? true
        self.hotkeyToggleNotch = Self.loadHotkey(
            key: GravPreferenceKeys.hotkeyToggleNotch,
            defaultValue: .defaultToggleNotch,
            from: defaults
        )
        self.hotkeyToggleMiniPet = Self.loadHotkey(
            key: GravPreferenceKeys.hotkeyToggleMiniPet,
            defaultValue: .defaultToggleMiniPet,
            from: defaults
        )
        self.hotkeyFocusAntigravity = Self.loadHotkey(
            key: GravPreferenceKeys.hotkeyFocusAntigravity,
            defaultValue: .defaultFocusAntigravity,
            from: defaults
        )

        if let rawAppearance = defaults.string(forKey: GravPreferenceKeys.appearanceMode),
           let parsed = GravAppearanceMode(rawValue: rawAppearance)
        {
            self.appearanceMode = parsed
        } else {
            self.appearanceMode = .system
        }

        if defaults.object(forKey: GravPreferenceKeys.launchAtLogin) != nil {
            self.launchAtLogin = defaults.bool(forKey: GravPreferenceKeys.launchAtLogin)
        } else {
            self.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    public func resetGlobalHotkeysToDefaults() {
        hotkeyToggleNotch = .defaultToggleNotch
        hotkeyToggleMiniPet = .defaultToggleMiniPet
        hotkeyFocusAntigravity = .defaultFocusAntigravity
    }

    private static func saveHotkey(_ shortcut: GravHotkeyShortcut?, key: String, to defaults: UserDefaults) {
        if let shortcut, let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: key)
        } else {
            // Store empty Data sentinel so nil ("disabled") is distinguished from unset default
            defaults.set(Data(), forKey: key)
        }
    }

    private static func loadHotkey(
        key: String,
        defaultValue: GravHotkeyShortcut,
        from defaults: UserDefaults
    ) -> GravHotkeyShortcut? {
        guard let data = defaults.data(forKey: key) else {
            return defaultValue
        }
        if data.isEmpty { return nil }
        return (try? JSONDecoder().decode(GravHotkeyShortcut.self, from: data)) ?? defaultValue
    }

    public func refreshLaunchAtLoginStatus() {
        let enabled = SMAppService.mainApp.status == .enabled
        if launchAtLogin != enabled {
            launchAtLogin = enabled
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            launchAtLoginError = error.localizedDescription
        }
    }
}
