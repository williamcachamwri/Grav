import AppKit
import Foundation

/// Detects the local Google Antigravity installation, caches its real app icon on `@MainActor`,
/// activates/focuses the running application, and manages access to `~/.gemini/antigravity/brain`.
@MainActor
public final class AntigravityAppDetector {
    public static let bundleIdentifier = "com.google.antigravity"
    public static let defaultAppURL = URL(fileURLWithPath: "/Applications/Antigravity.app")
    public static var defaultBrainDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity/brain", isDirectory: true)
    }

    public let appURL: URL
    public internal(set) var brainDirectoryURL: URL
    public private(set) var cachedIcon: NSImage?

    internal let userDefaults: UserDefaults
    private let fileManager: FileManager

    public init(
        appURL: URL = AntigravityAppDetector.defaultAppURL,
        brainDirectoryURL: URL = AntigravityAppDetector.defaultBrainDirectoryURL,
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.appURL = appURL
        self.brainDirectoryURL = brainDirectoryURL
        self.userDefaults = userDefaults
        self.fileManager = fileManager
    }

    /// Resolves the installed Antigravity bundle URL, checking the canonical `/Applications/Antigravity.app`
    /// path first before consulting LaunchServices for `com.google.antigravity`.
    public var resolvedAppURL: URL {
        if fileManager.fileExists(atPath: appURL.path) {
            return appURL
        }
        if let bundleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) {
            return bundleURL
        }
        return appURL
    }

    public var isAppInstalled: Bool {
        if fileManager.fileExists(atPath: appURL.path) {
            return true
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) != nil
    }

    public var isAppRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty
    }

    /// Verifies that the brain directory exists and is actually readable by the current process.
    public var isBrainAccessible: Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: brainDirectoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return false
        }
        guard fileManager.isReadableFile(atPath: brainDirectoryURL.path) else {
            return false
        }
        do {
            _ = try fileManager.contentsOfDirectory(atPath: brainDirectoryURL.path)
            return true
        } catch {
            return false
        }
    }

    /// Loads and caches the real Antigravity app icon once on `@MainActor`.
    @discardableResult
    public func loadIconIfNeeded() -> NSImage? {
        if let cachedIcon {
            return cachedIcon
        }
        guard isAppInstalled else {
            return nil
        }

        let targetURL = resolvedAppURL
        let icnsURL = targetURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("icon.icns")

        let icon: NSImage
        if fileManager.fileExists(atPath: icnsURL.path), let loaded = NSImage(contentsOf: icnsURL) {
            icon = loaded
        } else {
            icon = NSWorkspace.shared.icon(forFile: targetURL.path)
        }
        cachedIcon = icon
        return icon
    }

    /// Produces a fresh `AntigravityConnectionStatus` snapshot.
    public func connectionStatus(activeConversationCount: Int) -> AntigravityConnectionStatus {
        let installed = isAppInstalled
        let running = isAppRunning
        let accessible = isBrainAccessible
        return AntigravityConnectionStatus(
            isAppInstalled: installed,
            isAppRunning: running,
            appURL: resolvedAppURL,
            brainDirectoryURL: brainDirectoryURL,
            isBrainAccessible: accessible,
            activeConversationCount: activeConversationCount,
            needsFolderAccess: !accessible
        )
    }

    /// Focuses the running Antigravity window, or launches `/Applications/Antigravity.app` if installed.
    public func activateAntigravityApp() {
        if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).first {
            runningApp.unhide()
            runningApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            return
        }
        guard isAppInstalled else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: resolvedAppURL, configuration: configuration)
    }

    /// Opens a file directly in Antigravity, falling back to the default macOS handler when Antigravity is unavailable.
    public func openInAntigravity(path: String) {
        let fileURL = URL(fileURLWithPath: path)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            activateAntigravityApp()
            return
        }
        if isAppInstalled {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([fileURL], withApplicationAt: resolvedAppURL, configuration: configuration)
        } else {
            NSWorkspace.shared.open(fileURL)
        }
    }

    /// Reveals a changed file in Finder (or its parent directory if the file was deleted).
    public func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        if fileManager.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            let parent = url.deletingLastPathComponent()
            if fileManager.fileExists(atPath: parent.path) {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: parent.path)
            }
        }
    }
}
