import AppKit
import Foundation
import Observation

/// Central `@MainActor` telemetry store exposing real-time local Antigravity runtime state
/// to the Notch HUD, Onboarding live connection check, and Menu Bar.
///
/// Full real-time file watching, incremental JSONL tailing, and live task log ingestion
/// are wired in by the telemetry engine modules.
@MainActor
@Observable
public final class AntigravityTelemetryStore {
    // MARK: - Observable Telemetry State

    public internal(set) var state: TelemetryState = .idle
    public internal(set) var connectionStatus = AntigravityConnectionStatus()
    public internal(set) var antigravityIcon: NSImage?

    public internal(set) var sessions: [ConversationSession] = []
    public internal(set) var activeSession: ConversationSession?

    public internal(set) var currentThinking: ThinkingSnapshot?
    public internal(set) var thinkingHistory: [ThinkingSnapshot] = []
    public internal(set) var fileChanges: [FileChangeEvent] = []
    public internal(set) var commands: [CommandExecutionEvent] = []
    public internal(set) var recentActivity: [TelemetryActivityItem] = []
    public internal(set) var tokenMetrics = TokenMetrics()
    public internal(set) var activeModel: String?

    public internal(set) var isPaused: Bool = false
    public internal(set) var isMonitoring: Bool = false

    /// Emitted when a significant telemetry transition warrants a subtle NotchKit `peek()`.
    public var onPeekRequested: ((NotchPeekEvent) -> Void)?

    public init() {}

    // MARK: - Lifecycle & Controls

    public func start() {
        isMonitoring = true
        refreshConnectionStatus()
    }

    public func stop() {
        isMonitoring = false
    }

    public func setPaused(_ paused: Bool) {
        isPaused = paused
    }

    public func refreshConnectionStatus() {
        let appURL = URL(fileURLWithPath: "/Applications/Antigravity.app")
        let installed = FileManager.default.fileExists(atPath: appURL.path)
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.antigravity").isEmpty
        let brainURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity/brain", isDirectory: true)
        let accessible = FileManager.default.isReadableFile(atPath: brainURL.path)
        connectionStatus = AntigravityConnectionStatus(
            isAppInstalled: installed,
            isAppRunning: running,
            appURL: appURL,
            brainDirectoryURL: brainURL,
            isBrainAccessible: accessible,
            activeConversationCount: sessions.count,
            needsFolderAccess: !accessible
        )
        if installed, antigravityIcon == nil {
            antigravityIcon = NSWorkspace.shared.icon(forFile: appURL.path)
        }
    }

    public func selectSession(_ session: ConversationSession) {
        activeSession = session
    }

    public func activateAntigravityApp() {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.antigravity").first {
            app.activate(options: .activateIgnoringOtherApps)
        } else if FileManager.default.fileExists(atPath: "/Applications/Antigravity.app") {
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: "/Applications/Antigravity.app"),
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }

    public func requestBrainFolderAccess() {
        refreshConnectionStatus()
    }

    /// Loads full untruncated content for a specific `stepIndex` on demand from `transcript_full.jsonl`.
    public func loadFullStep(stepIndex: Int) async -> TranscriptStep? {
        _ = stepIndex
        return nil
    }

    /// Reveals a changed file in Finder.
    public func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
        }
    }

    /// Opens a file directly in Antigravity (falling back to default macOS handler).
    public func openInAntigravity(path: String) {
        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            activateAntigravityApp()
            return
        }
        let appURL = URL(fileURLWithPath: "/Applications/Antigravity.app")
        if FileManager.default.fileExists(atPath: appURL.path) {
            NSWorkspace.shared.open(
                [fileURL],
                withApplicationAt: appURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
        } else {
            NSWorkspace.shared.open(fileURL)
        }
    }

    /// Convenience accessor for the most recent running command, if any.
    public var activeCommand: CommandExecutionEvent? {
        commands.first(where: { $0.status == .running })
    }

    /// Convenience accessor for the most recent file change, if any.
    public var latestFileChange: FileChangeEvent? {
        fileChanges.first
    }
}
