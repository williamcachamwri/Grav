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
