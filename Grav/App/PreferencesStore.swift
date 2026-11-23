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
    public static let playSounds = "grav.playSounds"

    // Mini Pet preferences
    public static let miniPetEnabled = "grav.miniPetEnabled"
    public static let activeMiniPetID = "grav.activeMiniPetID"
    public static let miniPetPlacement = "grav.miniPetPlacement"
    public static let miniPetSize = "grav.miniPetSize"
    public static let miniPetSpeed = "grav.miniPetSpeed"
    public static let miniPetInteractiveClick = "grav.miniPetInteractiveClick"
    public static let miniPetRoaming = "grav.miniPetRoaming"

    // Expanded Notch HUD & UI customizations
    public static let hoverOpenDelay = "grav.hoverOpenDelay"
    public static let showCollapsedTokens = "grav.showCollapsedTokens"
    public static let showCollapsedFocus = "grav.showCollapsedFocus"
    public static let showCollapsedStepProgress = "grav.showCollapsedStepProgress"
    public static let autoExpandOnNeedsInput = "grav.autoExpandOnNeedsInput"
    public static let hapticsEnabled = "grav.hapticsEnabled"
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
        self.playSounds = defaults.object(forKey: GravPreferenceKeys.playSounds) as? Bool ?? true

        self.miniPetEnabled = defaults.object(forKey: GravPreferenceKeys.miniPetEnabled) as? Bool ?? true
        self.activeMiniPetID = defaults.string(forKey: GravPreferenceKeys.activeMiniPetID) ?? "super-saiyan-goku-combat"
        if let rawPlacement = defaults.string(forKey: GravPreferenceKeys.miniPetPlacement),
           let parsedPlacement = MiniPetPlacement(rawValue: rawPlacement)
        {
            self.miniPetPlacement = parsedPlacement
        } else {
            self.miniPetPlacement = .leading
        }
        let storedPetSize = defaults.object(forKey: GravPreferenceKeys.miniPetSize) as? Double ?? 22.0
        self.miniPetSize = min(32.0, max(16.0, storedPetSize))
        let storedPetSpeed = defaults.object(forKey: GravPreferenceKeys.miniPetSpeed) as? Double ?? 1.0
        self.miniPetSpeed = min(2.0, max(0.5, storedPetSpeed))
        self.miniPetInteractiveClick = defaults.object(forKey: GravPreferenceKeys.miniPetInteractiveClick) as? Bool ?? true
        self.miniPetRoaming = defaults.object(forKey: GravPreferenceKeys.miniPetRoaming) as? Bool ?? true

        let storedHoverDelay = defaults.object(forKey: GravPreferenceKeys.hoverOpenDelay) as? Double ?? 0.15
        self.hoverOpenDelay = min(0.50, max(0.05, storedHoverDelay))
        self.showCollapsedTokens = defaults.object(forKey: GravPreferenceKeys.showCollapsedTokens) as? Bool ?? true
        self.showCollapsedFocus = defaults.object(forKey: GravPreferenceKeys.showCollapsedFocus) as? Bool ?? true
        self.showCollapsedStepProgress = defaults.object(forKey: GravPreferenceKeys.showCollapsedStepProgress) as? Bool ?? true
        self.autoExpandOnNeedsInput = defaults.object(forKey: GravPreferenceKeys.autoExpandOnNeedsInput) as? Bool ?? true
        self.hapticsEnabled = defaults.object(forKey: GravPreferenceKeys.hapticsEnabled) as? Bool ?? true

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
