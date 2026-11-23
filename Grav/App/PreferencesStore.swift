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

/// Selectable Dragon Ball Super Saiyan transformation forms for Turbo Mode visuals & audio.
public enum SuperSaiyanAuraTheme: String, CaseIterable, Identifiable, Sendable {
    case superSaiyan = "superSaiyan"
    case god = "god"
    case blue = "blue"
    case rose = "rose"
    case ultraInstinct = "ultraInstinct"
    case legendary = "legendary"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .superSaiyan: return "Super Saiyan"
        case .god: return "God"
        case .blue: return "Blue"
        case .rose: return "Rosé"
        case .ultraInstinct: return "Ultra Instinct"
        case .legendary: return "Legendary"
        }
    }

    public var subtitle: String {
        switch self {
        case .superSaiyan: return "Solar Gold · SSJ2 Cyan Lightning"
        case .god: return "Divine Crimson Flame · Amber Sparks"
        case .blue: return "Cobalt Plasma · Diamond Arcs"
        case .rose: return "Ethereal Crimson-Pink · Violet Lightning"
        case .ultraInstinct: return "Silver-Ice Heat Shimmer · Prismatic Sparks"
        case .legendary: return "Radioactive Emerald · Bio-Lime Surge"
        }
    }

    /// Deep outer flame edge RGB (high saturation, zero muddy brown).
    public var outerFlameRGB: SIMD3<Float> {
        switch self {
        case .superSaiyan:   return SIMD3<Float>(1.00, 0.56, 0.02)
        case .god:           return SIMD3<Float>(0.96, 0.06, 0.14)
        case .blue:          return SIMD3<Float>(0.02, 0.36, 1.00)
        case .rose:          return SIMD3<Float>(0.76, 0.05, 0.44)
        case .ultraInstinct: return SIMD3<Float>(0.18, 0.34, 0.98)
        case .legendary:     return SIMD3<Float>(0.00, 0.76, 0.24)
        }
    }

    /// Primary roaring Ki flame body RGB.
    public var primaryAuraRGB: SIMD3<Float> {
        switch self {
        case .superSaiyan:   return SIMD3<Float>(1.00, 0.87, 0.10)
        case .god:           return SIMD3<Float>(1.00, 0.28, 0.10)
        case .blue:          return SIMD3<Float>(0.04, 0.78, 1.00)
        case .rose:          return SIMD3<Float>(1.00, 0.20, 0.58)
        case .ultraInstinct: return SIMD3<Float>(0.64, 0.86, 1.00)
        case .legendary:     return SIMD3<Float>(0.32, 1.00, 0.16)
        }
    }

    /// High-voltage inner flare RGB.
    public var innerFlareRGB: SIMD3<Float> {
        switch self {
        case .superSaiyan:   return SIMD3<Float>(1.00, 0.97, 0.50)
        case .god:           return SIMD3<Float>(1.00, 0.74, 0.24)
        case .blue:          return SIMD3<Float>(0.50, 0.96, 1.00)
        case .rose:          return SIMD3<Float>(1.00, 0.64, 0.86)
        case .ultraInstinct: return SIMD3<Float>(0.90, 0.96, 1.00)
        case .legendary:     return SIMD3<Float>(0.78, 1.00, 0.44)
        }
    }

    /// Blinding white-hot Ki core RGB.
    public var coreWhiteRGB: SIMD3<Float> {
        switch self {
        case .superSaiyan:   return SIMD3<Float>(1.00, 1.00, 0.94)
        case .god:           return SIMD3<Float>(1.00, 0.97, 0.88)
        case .blue:          return SIMD3<Float>(0.94, 1.00, 1.00)
        case .rose:          return SIMD3<Float>(1.00, 0.95, 0.99)
        case .ultraInstinct: return SIMD3<Float>(1.00, 1.00, 1.00)
        case .legendary:     return SIMD3<Float>(0.95, 1.00, 0.92)
        }
    }

    /// Secondary bio-electric lightning outer glow RGB.
    public var lightningRGB: SIMD3<Float> {
        switch self {
        case .superSaiyan:   return SIMD3<Float>(0.24, 0.88, 1.00)
        case .god:           return SIMD3<Float>(1.00, 0.86, 0.28)
        case .blue:          return SIMD3<Float>(0.58, 0.96, 1.00)
        case .rose:          return SIMD3<Float>(0.88, 0.42, 1.00)
        case .ultraInstinct: return SIMD3<Float>(0.54, 0.92, 1.00)
        case .legendary:     return SIMD3<Float>(0.58, 1.00, 0.30)
        }
    }

    public var primaryColor: Color {
        Color(red: Double(primaryAuraRGB.x), green: Double(primaryAuraRGB.y), blue: Double(primaryAuraRGB.z))
    }

    public var outerColor: Color {
        Color(red: Double(outerFlameRGB.x), green: Double(outerFlameRGB.y), blue: Double(outerFlameRGB.z))
    }

    public var innerColor: Color {
        Color(red: Double(innerFlareRGB.x), green: Double(innerFlareRGB.y), blue: Double(innerFlareRGB.z))
    }

    public var coreColor: Color {
        Color(red: Double(coreWhiteRGB.x), green: Double(coreWhiteRGB.y), blue: Double(coreWhiteRGB.z))
    }

    public var lightningColor: Color {
        Color(red: Double(lightningRGB.x), green: Double(lightningRGB.y), blue: Double(lightningRGB.z))
    }

    /// Harmonic pitch root (Hz) giving each transformation its own distinctive audio resonance.
    public var audioRootHz: Double {
        switch self {
        case .superSaiyan:   return 73.42  // D2 — fierce iconic golden power chord
        case .god:           return 82.41  // E2 — intense fiery divine resonance
        case .blue:          return 92.50  // F#2 — deep glacial godly plasma
        case .rose:          return 69.30  // C#2 — regal dark crimson resonance
        case .ultraInstinct: return 110.00 // A2 — transcendent shimmering harmonic aura
        case .legendary:     return 55.00  // A1 — colossal seismic sub-bass eruption
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
    public static let turboAuraEnabled = "grav.turboAuraEnabled"
    public static let turboAuraTheme = "grav.turboAuraTheme"
    public static let turboAudioEnabled = "grav.turboAudioEnabled"
    public static let turboAuraLoopEnabled = "grav.turboAuraLoopEnabled"
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

    public var turboAuraEnabled: Bool {
        didSet { defaults.set(turboAuraEnabled, forKey: GravPreferenceKeys.turboAuraEnabled) }
    }

    public var turboAuraTheme: SuperSaiyanAuraTheme {
        didSet { defaults.set(turboAuraTheme.rawValue, forKey: GravPreferenceKeys.turboAuraTheme) }
    }

    public var turboAudioEnabled: Bool {
        didSet { defaults.set(turboAudioEnabled, forKey: GravPreferenceKeys.turboAudioEnabled) }
    }

    public var turboAuraLoopEnabled: Bool {
        didSet { defaults.set(turboAuraLoopEnabled, forKey: GravPreferenceKeys.turboAuraLoopEnabled) }
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
        self.turboAuraEnabled = defaults.object(forKey: GravPreferenceKeys.turboAuraEnabled) as? Bool ?? true
        self.turboAudioEnabled = defaults.object(forKey: GravPreferenceKeys.turboAudioEnabled) as? Bool ?? true
        self.turboAuraLoopEnabled = defaults.object(forKey: GravPreferenceKeys.turboAuraLoopEnabled) as? Bool ?? true

        if let rawTurboTheme = defaults.string(forKey: GravPreferenceKeys.turboAuraTheme),
           let parsedTurboTheme = SuperSaiyanAuraTheme(rawValue: rawTurboTheme)
        {
            self.turboAuraTheme = parsedTurboTheme
        } else {
            self.turboAuraTheme = .superSaiyan
        }

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
