import AppKit
import Foundation

/// Holds an active security-scoped resource lease and releases it automatically on deallocation.
private final class SecurityScopedLease: Sendable {
    let url: URL

    init?(url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            return nil
        }
        self.url = url
    }

    deinit {
        url.stopAccessingSecurityScopedResource()
    }
}

/// Detects the local Google Antigravity installation, caches its real app icon on `@MainActor`,
/// activates/focuses the running application, and manages access to `~/.gemini/antigravity/brain`.
@MainActor
public final class AntigravityAppDetector {
    public static let bundleIdentifier = "com.google.antigravity"
    public static let defaultAppURL = URL(fileURLWithPath: "/Applications/Antigravity.app")
    public static let bookmarkDefaultsKey = "com.grav.telemetry.brainDirectoryBookmark"
    public static var defaultBrainDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity/brain", isDirectory: true)
    }

    public let appURL: URL
    public internal(set) var brainDirectoryURL: URL
    public private(set) var cachedIcon: NSImage?

    internal let userDefaults: UserDefaults
    private let fileManager: FileManager
    private var activeSecurityScope: SecurityScopedLease?

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
    /// Uses macOS 14+ cooperative activation handoff (`NSApp.yieldActivation(to:)`) + LaunchServices fallback
    /// so focus reliably transfers from Grav's floating Notch panel to Antigravity's main window.
    public func activateAntigravityApp() {
        for window in NSApp.windows where window is NSPanel && window.isKeyWindow {
            window.resignKey()
        }

        if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).first {
            if NSApp.isActive {
                NSApp.yieldActivation(to: runningApp)
            }
            runningApp.unhide()
            if runningApp.activate(options: [.activateAllWindows]) {
                return
            }
            // Fallback via NSWorkspace activates reliably even when called from an LSUIElement accessory app
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            if let appURL = runningApp.bundleURL ?? (isAppInstalled ? resolvedAppURL : nil) {
                NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            }
            return
        }
        guard isAppInstalled else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: resolvedAppURL, configuration: configuration)
    }

    // MARK: - Security-Scoped Brain Folder Access

    /// Attempts to restore a previously granted security-scoped bookmark for the Antigravity brain directory.
    /// Returns `true` if a persisted bookmark was successfully resolved and applied.
    @discardableResult
    public func restoreBookmarkedBrainDirectory() -> Bool {
        guard let bookmarkData = userDefaults.data(forKey: Self.bookmarkDefaultsKey) else {
            return false
        }

        var isStale = false
        let resolvedURL: URL?
        if let scopedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            resolvedURL = scopedURL
        } else if let plainURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            resolvedURL = plainURL
        } else {
            resolvedURL = nil
        }

        guard let url = resolvedURL else {
            return false
        }

        activeSecurityScope = SecurityScopedLease(url: url)
        brainDirectoryURL = url

        if isStale {
            _ = persistBookmark(for: url)
        }
        return isBrainAccessible
    }

    /// Prompts the user with an `NSOpenPanel` rooted near `~/.gemini/antigravity/brain` to grant folder access
    /// and persists a security-scoped bookmark for subsequent launches.
    @discardableResult
    public func requestBrainFolderAccess() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Grant Access to Antigravity Telemetry Folder"
        panel.message = "Select your ~/.gemini/antigravity/brain folder so Grav can read local Antigravity transcripts."
        panel.prompt = "Grant Access"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true

        if fileManager.fileExists(atPath: brainDirectoryURL.path) {
            panel.directoryURL = brainDirectoryURL
        } else {
            let parent = brainDirectoryURL.deletingLastPathComponent()
            panel.directoryURL = fileManager.fileExists(atPath: parent.path)
                ? parent
                : fileManager.homeDirectoryForCurrentUser
        }

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return false
        }

        brainDirectoryURL = selectedURL
        activeSecurityScope = SecurityScopedLease(url: selectedURL)
        _ = persistBookmark(for: selectedURL)
        return isBrainAccessible
    }

    /// Persists a bookmark for the given brain directory URL (preferring security-scoped bookmarks when supported).
    @discardableResult
    public func persistBookmark(for url: URL) -> Bool {
        let data: Data?
        if let scoped = try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            data = scoped
        } else if let standard = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            data = standard
        } else {
            data = nil
        }

        guard let data else { return false }
        userDefaults.set(data, forKey: Self.bookmarkDefaultsKey)
        return true
    }

    /// Releases any active security-scoped resource access lease.
    public func stopAccessingBookmarkedDirectory() {
        activeSecurityScope = nil
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
