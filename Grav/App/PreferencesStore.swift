import Foundation
import Observation
import ServiceManagement

/// User-configurable preferences for Grav's Notch HUD, telemetry behavior, and macOS integration.
@MainActor
@Observable
public final class PreferencesStore {
    private enum Keys {
        static let hasCompletedOnboarding = "grav.hasCompletedOnboarding"
        static let hoverToExpand = "grav.hoverToExpand"
        static let autoPeekOnEvents = "grav.autoPeekOnEvents"
        static let isNotchPinned = "grav.isNotchPinned"
        static let isTelemetryPaused = "grav.isTelemetryPaused"
        static let launchAtLogin = "grav.launchAtLogin"
    }

    private let defaults: UserDefaults

    public var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    public var hoverToExpand: Bool {
        didSet { defaults.set(hoverToExpand, forKey: Keys.hoverToExpand) }
    }

    public var autoPeekOnEvents: Bool {
        didSet { defaults.set(autoPeekOnEvents, forKey: Keys.autoPeekOnEvents) }
    }

    public var isNotchPinned: Bool {
        didSet { defaults.set(isNotchPinned, forKey: Keys.isNotchPinned) }
    }

    public var isTelemetryPaused: Bool {
        didSet { defaults.set(isTelemetryPaused, forKey: Keys.isTelemetryPaused) }
    }

    public var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    public private(set) var launchAtLoginError: String?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        self.hoverToExpand = defaults.object(forKey: Keys.hoverToExpand) as? Bool ?? true
        self.autoPeekOnEvents = defaults.object(forKey: Keys.autoPeekOnEvents) as? Bool ?? true
        self.isNotchPinned = defaults.bool(forKey: Keys.isNotchPinned)
        self.isTelemetryPaused = defaults.bool(forKey: Keys.isTelemetryPaused)

        if defaults.object(forKey: Keys.launchAtLogin) != nil {
            self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
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
