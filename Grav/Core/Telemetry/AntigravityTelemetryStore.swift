import AppKit
import Foundation
import Observation
import SwiftUI

/// Central `@MainActor` telemetry store exposing real-time local Antigravity runtime state
/// to the Notch HUD, Onboarding live connection check, and Menu Bar.
///
/// Wires together `AntigravityAppDetector`, `ConversationDiscovery`, `TranscriptTailer`,
/// `TaskLogTailer`, and `EventClassifier` using event-driven `DispatchSource` watchers and
/// active-only idle decay (0% idle CPU, zero background polling).
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
    public internal(set) var latestResponse: AssistantResponseSnapshot?
    public internal(set) var responses: [AssistantResponseSnapshot] = []
    public internal(set) var fileChanges: [FileChangeEvent] = []
    public internal(set) var commands: [CommandExecutionEvent] = []
    public internal(set) var recentActivity: [TelemetryActivityItem] = []
    public internal(set) var tokenMetrics = TokenMetrics()
    public internal(set) var activeModel: String?
    public internal(set) var swarmSnapshot: SwarmSnapshot?
    public internal(set) var subagents: [SubagentRecord] = []
    public internal(set) var currentFocus: String?
    public internal(set) var stepsProgress: AgentStepsProgress?
    public internal(set) var turnStartedAt: Date?
    public internal(set) var lastTurnDuration: TimeInterval?
    public internal(set) var activeWorkspaceName: String?
    public internal(set) var activeRunningChatsCount: Int = 0
    public internal(set) var currentPhaseStartedAt: Date = Date()
    public internal(set) var executionMode: AntigravityExecutionMode = .defaultMode

    public var isTurboMode: Bool {
        executionMode.isTurbo
    }

    public internal(set) var isPaused: Bool = false
    public internal(set) var isMonitoring: Bool = false

    // MARK: - Antigravity-Native Power Modules (#1-#4, #6)

    /// Sessions whose latest reply/modification in `conversation_summaries.db` is newer than
    /// `last_user_view_time` in `~/.gemini/antigravity/annotations/<id>.pbtxt` (Feature #3).
    public internal(set) var unreadSessionIDs: Set<String> = []
    /// Artifacts, plans, scratch scripts, and screenshots inside active `brain/<id>/` (Feature #4).
    public internal(set) var sessionArtifacts: [SessionArtifactItem] = []
    /// Installed MCP servers discovered in `~/.gemini/antigravity/mcp/` (Feature #6).
    public internal(set) var mcpServers: [MCPServerSummary] = []
    /// Active & recent background tasks, daemons, and `/schedule` timers/crons (Feature #6).
    public internal(set) var scheduledTasks: [ScheduledTaskRecord] = []
    /// Last radar alert ID explicitly dismissed by the user (Feature #2).
    public internal(set) var dismissedRadarAlertID: String?

    public var unreadSessionCount: Int {
        unreadSessionIDs.count
    }

    public func isSessionUnread(_ sessionID: String) -> Bool {
        unreadSessionIDs.contains(sessionID)
    }

    /// Recent MCP tool invocations captured in the active session's telemetry stream (Feature #6).
    public var mcpToolActivities: [AgentToolActivityEvent] {
        recentActivity.compactMap { item in
            guard case let .toolActivity(ev) = item, ev.kind == .mcpTool else { return nil }
            return ev
        }
    }

    /// High-signal real-time Attention / Safety Radar alert for the active session (Feature #2).
    public var activeRadarAlert: AntigravityRadarAlert? {
        guard !isPaused else { return nil }

        // 1. Waiting for user input / ask_question / approval
        if case let .waitingForInput(prompt) = state {
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = trimmed.isEmpty ? "Antigravity paused for your response or approval." : trimmed
            let alert = AntigravityRadarAlert(
                id: "waiting-\(detail.hashValue)",
                severity: .approval,
                title: "Approval or Reply Needed",
                detail: detail,
                badge: isTurboMode ? "TURBO · WAITING" : "WAITING"
            )
            return dismissedRadarAlertID == alert.id ? nil : alert
        }

        // 2. Destructive shell command currently running or executed within the last 15 seconds
        let now = Date()
        for cmd in commands.prefix(4) {
            let isFresh = cmd.status == .running
                || now.timeIntervalSince(cmd.completedAt ?? cmd.startedAt) < 15.0
            guard isFresh else { continue }
            if let risk = AntigravityRuntimeInspector.assessDestructiveRisk(commandLine: cmd.commandLine) {
                let alert = AntigravityRadarAlert(
                    id: "destructive-\(cmd.id)",
                    severity: .destructive,
                    title: risk,
                    detail: cmd.commandLine,
                    badge: isTurboMode ? "TURBO · RISK" : "HIGH RISK",
                    timestamp: cmd.startedAt
                )
                return dismissedRadarAlertID == alert.id ? nil : alert
            }
        }

        return nil
    }

    /// Emitted when a significant telemetry transition warrants a subtle NotchKit `peek()`.
    public var onPeekRequested: ((NotchPeekEvent) -> Void)?

    // MARK: - Internal Engine Dependencies

    private let appDetector: AntigravityAppDetector
    private let taskLogTailer: TaskLogTailer
    private let idleDecaySeconds: TimeInterval
    private let maxRetainedEvents: Int

    private var discovery: ConversationDiscovery?
    private var activeTailer: TranscriptTailer?
    private var activeSwarmWatcher: SwarmSubagentWatcher?
    private var activeWALWatcher: ConversationWALWatcher?
    private var activeAnnotationWatcher: ConversationAnnotationWatcher?
    private var classifier = EventClassifier()

    private var userPinnedSessionID: String?
    private var isHydratingActiveSession: Bool = false
    private var hydratedTruncatedFileSteps: Set<Int> = []
    private var pendingTruncatedHydrationSteps: [Int] = []
    private var truncatedHydrationTask: Task<Void, Never>?
    private var sqliteProbeTask: Task<Void, Never>?
    private var lastSQLiteProbeAt: Date = .distantPast
    private var hydratedFileContents: [String: String] = [:]
    private var lastFinalIdleAt: Date = .distantPast
    private var isSpeculativeWALWorking: Bool = false
    private var idleDecayTask: Task<Void, Never>?
    private var unreadRefreshTask: Task<Void, Never>?
    private var artifactsRefreshTask: Task<Void, Never>?
    private var runtimeInspectionTask: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var sessionGeneration: UInt64 = 0

    // MARK: - Initialization

    public init() {
        self.appDetector = AntigravityAppDetector()
        self.taskLogTailer = TaskLogTailer()
        self.idleDecaySeconds = 12.0
        self.maxRetainedEvents = 200
    }

    /// Injectable initializer for deterministic unit tests and custom brain directory fixtures.
    public init(
        appDetector: AntigravityAppDetector,
        taskLogTailer: TaskLogTailer = TaskLogTailer(),
        idleDecaySeconds: TimeInterval = 12.0,
        maxRetainedEvents: Int = 200
    ) {
        self.appDetector = appDetector
        self.taskLogTailer = taskLogTailer
        self.idleDecaySeconds = max(0.05, idleDecaySeconds)
        self.maxRetainedEvents = max(10, maxRetainedEvents)
    }

    // MARK: - Lifecycle & Controls

    public func start() {
        guard !isMonitoring else {
            refreshConnectionStatus()
            return
        }
        isMonitoring = true
        _ = appDetector.restoreBookmarkedBrainDirectory()
        refreshConnectionStatus()
        installWorkspaceObservers()
        startConversationDiscovery()
        refreshUnreadSessions()
        refreshRuntimeInspection()
    }

    public func stop() {
        isMonitoring = false
        cancelIdleDecayTimer()
        unreadRefreshTask?.cancel()
        unreadRefreshTask = nil
        artifactsRefreshTask?.cancel()
        artifactsRefreshTask = nil
        runtimeInspectionTask?.cancel()
        runtimeInspectionTask = nil
        removeWorkspaceObservers()

        let currentDiscovery = discovery
        discovery = nil
        let currentTailer = activeTailer
        activeTailer = nil
        let currentSwarmWatcher = activeSwarmWatcher
        activeSwarmWatcher = nil
        let currentWALWatcher = activeWALWatcher
        activeWALWatcher = nil
        let currentAnnotationWatcher = activeAnnotationWatcher
        activeAnnotationWatcher = nil
        truncatedHydrationTask?.cancel()
        truncatedHydrationTask = nil
        let logTailer = taskLogTailer

        Task {
            await currentDiscovery?.stopWatching()
            await currentTailer?.stopWatching()
            await currentSwarmWatcher?.stopWatching()
            await currentWALWatcher?.stopWatching()
            await currentAnnotationWatcher?.stopWatching()
            await logTailer.stopAll()
        }

        appDetector.stopAccessingBookmarkedDirectory()
    }

    public func setPaused(_ paused: Bool) {
        guard isPaused != paused else { return }
        isPaused = paused

        if paused {
            cancelIdleDecayTimer()
            let currentTailer = activeTailer
            let currentSwarmWatcher = activeSwarmWatcher
            let currentWALWatcher = activeWALWatcher
            let currentAnnotationWatcher = activeAnnotationWatcher
            let logTailer = taskLogTailer
            Task {
                await currentTailer?.stopWatching()
                await currentSwarmWatcher?.stopWatching()
                await currentWALWatcher?.stopWatching()
                await currentAnnotationWatcher?.stopWatching()
                await logTailer.stopAll()
            }
        } else if isMonitoring {
            if let session = activeSession {
                resumeTailingActiveSession(session)
            } else {
                startConversationDiscovery()
            }
        }
    }

    public func refreshConnectionStatus() {
        connectionStatus = appDetector.connectionStatus(activeConversationCount: sessions.count)
        if connectionStatus.isAppInstalled, antigravityIcon == nil {
            antigravityIcon = appDetector.loadIconIfNeeded()
        }
    }

    public func selectSession(_ session: ConversationSession) {
        userPinnedSessionID = session.id
        activateSession(session)
    }

    public func selectSessionByID(_ conversationID: String) {
        if let existing = sessions.first(where: { $0.id == conversationID }) {
            selectSession(existing)
            return
        }
        let candidateDir = appDetector.brainDirectoryURL.appendingPathComponent(conversationID, isDirectory: true)
        let candidate = ConversationSession(id: conversationID, directoryURL: candidateDir)
        if FileManager.default.fileExists(atPath: candidate.transcriptURL.path) {
            selectSession(candidate)
        }
    }

    public func activateAntigravityApp() {
        appDetector.activateAntigravityApp()
    }

    public func dismissRadarAlert(_ alertID: String) {
        dismissedRadarAlertID = alertID
    }

    /// Root `~/.gemini/antigravity/` directory derived from the active brain folder.
    public var antigravityRootURL: URL {
        appDetector.brainDirectoryURL.deletingLastPathComponent()
    }

    /// Executes an off-main-actor SQLite FTS5 Spotlight search across all local Antigravity conversations (Feature #1).
    public func searchConversations(query: String, limit: Int = 24) async -> [AntigravitySpotlightHit] {
        let rootURL = antigravityRootURL
        let unreadSnapshot = unreadSessionIDs
        return await Task.detached(priority: .userInitiated) {
            ConversationSQLiteProbe.searchConversations(
                antigravityRootURL: rootURL,
                query: query,
                limit: limit,
                unreadIDs: unreadSnapshot
            )
        }.value
    }

    /// Recomputes unread/unseen finished Antigravity sessions by comparing `last_modified_time`
    /// against `annotations/<id>.pbtxt`'s `last_user_view_time` (Feature #3).
    public func refreshUnreadSessions() {
        let rootURL = antigravityRootURL
        unreadRefreshTask?.cancel()
        unreadRefreshTask = Task { [weak self] in
            let unread = await Task.detached(priority: .utility) {
                ConversationSQLiteProbe.computeUnreadSessionIDs(antigravityRootURL: rootURL)
            }.value
            guard !Task.isCancelled, let self else { return }
            if self.unreadSessionIDs != unread {
                self.unreadSessionIDs = unread
            }
        }
    }

    /// Scans the active session's `brain/<id>/` directory for plans, markdown docs, scratch scripts, and images (Feature #4).
    public func refreshSessionArtifacts() {
        guard let sessionDir = activeSession?.directoryURL else {
            sessionArtifacts = []
            return
        }
        let generation = sessionGeneration
        artifactsRefreshTask?.cancel()
        artifactsRefreshTask = Task { [weak self] in
            let items = await Task.detached(priority: .utility) {
                AntigravityRuntimeInspector.scanSessionArtifacts(sessionDirectoryURL: sessionDir)
            }.value
            guard !Task.isCancelled, let self, self.sessionGeneration == generation else { return }
            if self.sessionArtifacts != items {
                self.sessionArtifacts = items
            }
        }
    }

    /// Refreshes installed MCP servers and active/recent background tasks & `/schedule` records (Feature #6).
    public func refreshRuntimeInspection() {
        let rootURL = antigravityRootURL
        let tasksDir = activeSession?.tasksDirectoryURL
        let commandsSnapshot = commands
        let activitySnapshot = recentActivity
        let generation = sessionGeneration

        runtimeInspectionTask?.cancel()
        runtimeInspectionTask = Task { [weak self] in
            let (servers, tasks) = await Task.detached(priority: .utility) {
                let foundServers = AntigravityRuntimeInspector.scanInstalledMCPServers(antigravityRootURL: rootURL)
                let foundTasks: [ScheduledTaskRecord]
                if let tasksDir {
                    foundTasks = AntigravityRuntimeInspector.buildScheduledTaskRecords(
                        tasksDirectoryURL: tasksDir,
                        commands: commandsSnapshot,
                        recentActivity: activitySnapshot
                    )
                } else {
                    foundTasks = []
                }
                return (foundServers, foundTasks)
            }.value
            guard !Task.isCancelled, let self, self.sessionGeneration == generation else { return }
            if self.mcpServers != servers {
                self.mcpServers = servers
            }
            if self.scheduledTasks != tasks {
                self.scheduledTasks = tasks
            }
        }
    }

    public func requestBrainFolderAccess() {
        let granted = appDetector.requestBrainFolderAccess()
        refreshConnectionStatus()
        if granted && isMonitoring {
            startConversationDiscovery()
        }
    }

    /// Loads full untruncated content for a specific `stepIndex` on demand from `transcript_full.jsonl`
    /// and hydrates matching observable `ThinkingSnapshot` / command records in place.
    public func loadFullStep(stepIndex: Int) async -> TranscriptStep? {
        guard let session = activeSession else { return nil }
        let fullURL = session.fullTranscriptURL
        let tailer = activeTailer

        let fullStep: TranscriptStep?
        if let tailer {
            fullStep = await tailer.readFullStep(stepIndex: stepIndex, from: fullURL)
        } else {
            fullStep = await Task.detached(priority: .userInitiated) {
                TranscriptTailer.readFullStep(stepIndex: stepIndex, from: fullURL)
            }.value
        }

        guard let fullStep else { return nil }

        // Hydrate full thinking text into observable state if present
        if let fullThinking = fullStep.thinking?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fullThinking.isEmpty
        {
            if var current = currentThinking, current.stepIndex == stepIndex {
                current.text = fullThinking
                current.isTruncated = false
                current.isFullTextLoaded = true
                currentThinking = current
            }
            if let idx = thinkingHistory.firstIndex(where: { $0.stepIndex == stepIndex }) {
                thinkingHistory[idx].text = fullThinking
                thinkingHistory[idx].isTruncated = false
                thinkingHistory[idx].isFullTextLoaded = true
                upsertActivity(.thinking(thinkingHistory[idx]))
            }
        }

        // Hydrate full assistant response text into observable state if present
        if let fullContent = fullStep.content?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fullContent.isEmpty
        {
            if var latest = latestResponse, latest.stepIndex == stepIndex {
                latest.text = fullContent
                latest.isTruncated = false
                latest.isFullTextLoaded = true
                latestResponse = latest
            }
            if let idx = responses.firstIndex(where: { $0.stepIndex == stepIndex }) {
                responses[idx].text = fullContent
                responses[idx].isTruncated = false
                responses[idx].isFullTextLoaded = true
            }
        }

        return fullStep
    }

    /// Reveals a changed file in Finder.
    public func revealInFinder(path: String) {
        appDetector.revealInFinder(path: path)
    }

    /// Opens a file directly in Antigravity, jumping straight to `line` (`#L`) when provided
    /// via Antigravity's `--goto` CLI handler (falling back cleanly to macOS `NSWorkspace.open`).
    public func openInAntigravity(path: String, line: Int? = nil) {
        if let line, line > 0 {
            let cliCandidates = [
                "/Applications/Antigravity.app/Contents/Resources/app/bin/antigravity",
                "/Applications/Antigravity.app/Contents/Resources/app/bin/agy",
                "/usr/local/bin/agy",
                "/opt/homebrew/bin/agy",
            ]
            if let cliPath = cliCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                let target = "\(path):\(line)"
                Task.detached(priority: .userInitiated) {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: cliPath)
                    process.arguments = ["--goto", target]
                    try? process.run()
                }
                return
            }
        }
        appDetector.openInAntigravity(path: path)
    }

    /// Reveals the active session's `transcript.jsonl` file in Finder.
    public func revealActiveTranscriptInFinder() {
        guard let url = activeSession?.transcriptURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Opens macOS Terminal with the selected shell command copied to pasteboard for quick inspection.
    public func openCommandInTerminal(_ commandLine: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commandLine, forType: .string)
        if let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: terminalURL, configuration: config)
        }
    }

    /// Explicitly settles any lingering active thinking/running state to `.idle`.
    public func forceSettleIdle() {
        cancelIdleDecayTimer()
        let settledCommands = classifier.forceIdle()
        for cmd in settledCommands {
            upsertCommand(cmd)
            stopLiveTaskLogTailing(commandID: cmd.id)
            hydrateCompletedCommandLogIfNeeded(cmd)
        }
        state = .idle
        if var thinking = currentThinking, thinking.isActive {
            thinking.isActive = false
            thinking.completedAt = thinking.completedAt ?? Date()
            currentThinking = thinking
            if let idx = thinkingHistory.firstIndex(where: { $0.stepIndex == thinking.stepIndex }) {
                thinkingHistory[idx] = thinking
                upsertActivity(.thinking(thinking))
            }
        }
        finalizeActiveCompactions()
    }

    /// Convenience accessor for the most recent running command, if any.
    public var activeCommand: CommandExecutionEvent? {
        commands.first(where: { $0.status == .running })
    }

    /// Number of currently running shell commands / background tasks.
    public var runningCommandCount: Int {
        commands.filter { $0.status == .running }.count
    }

    /// Standalone non-swarm subagents (`research`, `browser`, `self`, etc.).
    public var standaloneSubagents: [SubagentRecord] {
        subagents.filter { !$0.isSwarmWorker }
    }

    /// Number of currently running standalone subagents.
    public var runningSubagentCount: Int {
        standaloneSubagents.filter(\.isActive).count
    }

    /// Number of currently working swarm workers.
    public var runningSwarmWorkerCount: Int {
        swarmSnapshot?.runningWorkers.count ?? 0
    }

    /// Total concurrent running tasks across background commands, subagents, and swarm workers.
    public var runningTaskCount: Int {
        runningCommandCount + runningSubagentCount + runningSwarmWorkerCount
    }

    /// Non-nil when a swarm has live working or waiting workers.
    public var activeSwarmSnapshot: SwarmSnapshot? {
        guard let snap = swarmSnapshot, snap.hasLiveWorkers else { return nil }
        return snap
    }

    /// Total number of swarm workers + standalone subagents for the Swarm tab badge.
    public var totalAgentsBadgeCount: Int {
        (swarmSnapshot?.workers.count ?? 0) + standaloneSubagents.count
    }

    /// Convenience accessor for the most recent file change, if any.
    public var latestFileChange: FileChangeEvent? {
        fileChanges.first
    }

    // MARK: - Direct Step Ingestion (Live & Testable)

    /// Ingests an ordered batch of `TranscriptStep`s into `EventClassifier` and updates observable state.
    /// Set `isInitialHydration = true` when replaying historical steps on session attach so peek
    /// notifications are suppressed and stale sessions settle calmly to `.idle`.
    public func ingestSteps(_ steps: [TranscriptStep], isInitialHydration: Bool = false) {
        guard !steps.isEmpty else { return }

        var lastStepDate: Date?
        let applyBlock = {
            for step in steps {
                lastStepDate = step.parsedDate
                let classified = self.classifier.process(step: step, session: self.activeSession)
                self.applyClassification(classified, suppressPeeks: isInitialHydration || self.isPaused)
            }
        }

        if !isInitialHydration && !GravMotionPreferences.shared.reduceMotion {
            withAnimation(GravMotionSpec.settle.animation) {
                applyBlock()
            }
        } else {
            applyBlock()
        }

        flushTruncatedFileHydrationQueue(isHistoricalReplay: isInitialHydration)

        if isInitialHydration {
            // If the latest historical step is older than the idle window, settle calmly to `.idle`
            // (and settle stale running commands whose task log has not been written recently).
            if let lastStepDate, Date().timeIntervalSince(lastStepDate) > idleDecaySeconds {
                if let running = activeCommand, isTaskLogRecentlyModified(running.taskLogURL, within: 20) {
                    scheduleIdleDecayIfNeeded()
                } else {
                    forceSettleIdle()
                }
            } else {
                scheduleIdleDecayIfNeeded()
            }
        } else {
            scheduleIdleDecayIfNeeded()
        }
    }

    // MARK: - Conversation Discovery & Session Switching

    private func startConversationDiscovery() {
        guard connectionStatus.isBrainAccessible else { return }

        let oldDiscovery = discovery
        let newDiscovery = ConversationDiscovery(brainDirectoryURL: appDetector.brainDirectoryURL)
        discovery = newDiscovery

        Task { [weak self] in
            await oldDiscovery?.stopWatching()
            await newDiscovery.startWatching { [weak self] discovered in
                Task { @MainActor [weak self] in
                    self?.handleDiscoveredSessions(discovered)
                }
            }
        }
    }

    private func handleDiscoveredSessions(_ discovered: [ConversationSession]) {
        sessions = discovered
        connectionStatus.activeConversationCount = discovered.count

        guard !discovered.isEmpty else {
            if activeSession != nil {
                clearActiveSessionState()
            }
            return
        }

        if let current = activeSession {
            if let refreshed = discovered.first(where: { $0.id == current.id }) {
                activeSession = refreshed
            } else {
                // Previously active session was removed; fall back to newest available
                userPinnedSessionID = nil
                activateSession(discovered[0])
                return
            }

            // Auto-follow a newly active conversation if the user has not pinned a specific session
            if userPinnedSessionID == nil,
               let newest = discovered.first,
               newest.id != current.id,
               newest.lastModified > current.lastModified
            {
                activateSession(newest)
            }
        } else {
            activateSession(discovered[0])
        }
        refreshUnreadSessions()
    }

    private func activateSession(_ session: ConversationSession) {
        sessionGeneration &+= 1
        let generation = sessionGeneration

        cancelIdleDecayTimer()
        let previousTailer = activeTailer
        activeTailer = nil
        let previousSwarmWatcher = activeSwarmWatcher
        activeSwarmWatcher = nil
        let previousWALWatcher = activeWALWatcher
        activeWALWatcher = nil
        let previousAnnotationWatcher = activeAnnotationWatcher
        activeAnnotationWatcher = nil
        truncatedHydrationTask?.cancel()
        truncatedHydrationTask = nil
        let logTailer = taskLogTailer

        // Reset session-scoped observable state
        activeSession = session
        hydratedTruncatedFileSteps.removeAll()
        pendingTruncatedHydrationSteps.removeAll()
        hydratedFileContents.removeAll()
        lastFinalIdleAt = .distantPast
        isSpeculativeWALWorking = false
        currentPhaseStartedAt = Date()
        executionMode = .defaultMode
        classifier.reset()
        state = .idle
        currentThinking = nil
        thinkingHistory = []
        latestResponse = nil
        responses = []
        fileChanges = []
        commands = []
        recentActivity = []
        tokenMetrics = TokenMetrics()
        activeModel = nil
        swarmSnapshot = nil
        subagents = []
        currentFocus = nil
        stepsProgress = nil
        turnStartedAt = nil
        lastTurnDuration = nil
        sqliteProbeTask?.cancel()
        sqliteProbeTask = nil

        let tailer = TranscriptTailer(transcriptURL: session.transcriptURL, initialOffset: 0)
        activeTailer = tailer
        let swarmWatcher = SwarmSubagentWatcher(sessionDirectoryURL: session.directoryURL)
        activeSwarmWatcher = swarmWatcher
        let walWatcher = ConversationWALWatcher(session: session)
        activeWALWatcher = walWatcher
        let annotationWatcher = ConversationAnnotationWatcher(session: session)
        activeAnnotationWatcher = annotationWatcher
        isHydratingActiveSession = true

        guard isMonitoring, !isPaused else {
            Task {
                await previousTailer?.stopWatching()
                await previousSwarmWatcher?.stopWatching()
                await previousWALWatcher?.stopWatching()
                await previousAnnotationWatcher?.stopWatching()
                await logTailer.stopAll()
            }
            return
        }

        Task { [weak self] in
            await previousTailer?.stopWatching()
            await previousSwarmWatcher?.stopWatching()
            await previousWALWatcher?.stopWatching()
            await previousAnnotationWatcher?.stopWatching()
            await logTailer.stopAll()

            // Attach live annotation watcher (`permission_preset` Turbo mode + official title)
            await annotationWatcher.startWatching { [weak self] annotation in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionGeneration == generation else { return }
                    self.applyConversationAnnotation(annotation)
                }
            }

            // Attach live Swarm & Subagent directory watcher
            await swarmWatcher.startWatching { [weak self] update in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionGeneration == generation, !self.isPaused else { return }
                    self.applySwarmSubagentUpdate(update)
                }
            }

            // Initial synchronous catch-up read (suppressing peek bursts for historical steps)
            let initialSteps = await tailer.readNewSteps()
            await MainActor.run { [weak self] in
                guard let self, self.sessionGeneration == generation else { return }
                self.ingestSteps(initialSteps, isInitialHydration: true)
                self.isHydratingActiveSession = false
                // Immediately synchronize live state from SQLite + conversation_summaries.db
                self.lastSQLiteProbeAt = .distantPast
                self.handleLiveConversationWALActivity(pulse: WALActivityPulse(deltaBytes: 0, isRapidStreamingBurst: false))
                self.refreshSessionArtifacts()
                self.refreshRuntimeInspection()
                self.refreshUnreadSessions()
            }

            // Attach live WAL pulse watcher so `Working` -> `Thinking for Ns` / `Replying` activates at 0ms
            await walWatcher.startWatching { [weak self] pulse in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionGeneration == generation, !self.isPaused else { return }
                    self.handleLiveConversationWALActivity(pulse: pulse)
                }
            }

            // Attach live kqueue watcher for subsequent incremental appends
            await tailer.startWatching { [weak self] newSteps in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionGeneration == generation, !self.isPaused else { return }
                    self.ingestSteps(newSteps, isInitialHydration: false)
                }
            }
        }
    }

    private func resumeTailingActiveSession(_ session: ConversationSession) {
        let generation = sessionGeneration
        let tailer: TranscriptTailer
        if let existing = activeTailer, existing.transcriptURL == session.transcriptURL {
            tailer = existing
        } else {
            tailer = TranscriptTailer(transcriptURL: session.transcriptURL, initialOffset: 0)
            activeTailer = tailer
        }

        let swarmWatcher: SwarmSubagentWatcher
        if let existingSwarm = activeSwarmWatcher, existingSwarm.sessionDirectoryURL == session.directoryURL {
            swarmWatcher = existingSwarm
        } else {
            swarmWatcher = SwarmSubagentWatcher(sessionDirectoryURL: session.directoryURL)
            activeSwarmWatcher = swarmWatcher
        }

        let walWatcher: ConversationWALWatcher
        if let existingWAL = activeWALWatcher {
            walWatcher = existingWAL
        } else {
            walWatcher = ConversationWALWatcher(session: session)
            activeWALWatcher = walWatcher
        }

        let annotationWatcher: ConversationAnnotationWatcher
        if let existingAnnotation = activeAnnotationWatcher {
            annotationWatcher = existingAnnotation
        } else {
            annotationWatcher = ConversationAnnotationWatcher(session: session)
            activeAnnotationWatcher = annotationWatcher
        }

        Task { [weak self] in
            await annotationWatcher.startWatching { [weak self] annotation in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionGeneration == generation else { return }
                    self.applyConversationAnnotation(annotation)
                }
            }
            await swarmWatcher.startWatching { [weak self] update in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionGeneration == generation, !self.isPaused else { return }
                    self.applySwarmSubagentUpdate(update)
                }
            }
            await walWatcher.startWatching { [weak self] pulse in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionGeneration == generation, !self.isPaused else { return }
                    self.handleLiveConversationWALActivity(pulse: pulse)
                }
            }
            await tailer.startWatching { [weak self] newSteps in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionGeneration == generation, !self.isPaused else { return }
                    self.ingestSteps(newSteps, isInitialHydration: false)
                }
            }
        }
    }

    private func clearActiveSessionState() {
        sessionGeneration &+= 1
        cancelIdleDecayTimer()
        let previousTailer = activeTailer
        activeTailer = nil
        let previousSwarmWatcher = activeSwarmWatcher
        activeSwarmWatcher = nil
        let previousWALWatcher = activeWALWatcher
        activeWALWatcher = nil
        let previousAnnotationWatcher = activeAnnotationWatcher
        activeAnnotationWatcher = nil
        truncatedHydrationTask?.cancel()
        truncatedHydrationTask = nil
        sqliteProbeTask?.cancel()
        sqliteProbeTask = nil
        let logTailer = taskLogTailer

        activeSession = nil
        hydratedTruncatedFileSteps.removeAll()
        pendingTruncatedHydrationSteps.removeAll()
        hydratedFileContents.removeAll()
        executionMode = .defaultMode
        classifier.reset()
        state = .idle
        currentThinking = nil
        thinkingHistory = []
        latestResponse = nil
        responses = []
        fileChanges = []
        commands = []
        recentActivity = []
        tokenMetrics = TokenMetrics()
        activeModel = nil
        swarmSnapshot = nil
        subagents = []
        currentFocus = nil
        stepsProgress = nil
        turnStartedAt = nil
        lastTurnDuration = nil
        sqliteProbeTask?.cancel()
        sqliteProbeTask = nil

        Task {
            await previousTailer?.stopWatching()
            await previousSwarmWatcher?.stopWatching()
            await previousWALWatcher?.stopWatching()
            await previousAnnotationWatcher?.stopWatching()
            await logTailer.stopAll()
        }
    }

    private func applyConversationAnnotation(_ annotation: ConversationAnnotation) {
        if GravMotionPreferences.shared.reduceMotion {
            executionMode = annotation.executionMode
        } else {
            withAnimation(.spring(duration: 0.42, bounce: 0.12)) {
                executionMode = annotation.executionMode
            }
        }
        if let officialTitle = annotation.title, !officialTitle.isEmpty, var session = activeSession {
            session.title = officialTitle
            activeSession = session
            if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[idx].title = officialTitle
            }
        }
        refreshUnreadSessions()
    }

    private func handleLiveConversationWALActivity(pulse: WALActivityPulse) {
        guard !isHydratingActiveSession, !isPaused, let session = activeSession else { return }

        // Throttle read-only SQLite WAL probes to at most once every 220ms (< 0.4ms each)
        let now = Date()
        guard now.timeIntervalSince(lastSQLiteProbeAt) >= 0.22 else { return }
        lastSQLiteProbeAt = now

        let generation = sessionGeneration
        let antigravityRoot = session.directoryURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dbURL = antigravityRoot
            .appendingPathComponent("conversations", isDirectory: true)
            .appendingPathComponent("\(session.id).db")
        let sessionID = session.id

        sqliteProbeTask?.cancel()
        sqliteProbeTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .userInitiated) {
                ConversationSQLiteProbe.readLiveSnapshot(
                    dbURL: dbURL,
                    antigravityRootURL: antigravityRoot,
                    conversationID: sessionID
                )
            }.value
            guard !Task.isCancelled, let self, self.sessionGeneration == generation, !self.isPaused else { return }
            if let snapshot {
                self.applySQLiteLiveSnapshot(snapshot)
            } else {
                // Fallback for isolated unit-test environments without a conversations/*.db file
                self.applyFallbackWALPulse(pulse)
            }
        }
    }

    private func applySQLiteLiveSnapshot(_ snapshot: ConversationSQLiteLiveSnapshot) {
        let now = Date()
        if let summary = snapshot.globalSummary {
            activeRunningChatsCount = summary.activeRunningCountAcrossAllChats
            if let ws = summary.workspaceName, !ws.isEmpty {
                activeWorkspaceName = ws
            }
            if let userInputAt = summary.lastUserInputTime {
                if turnStartedAt == nil || userInputAt > (turnStartedAt ?? .distantPast) {
                    turnStartedAt = userInputAt
                }
            }
        }
        if let focus = snapshot.latestFocus, !focus.isEmpty {
            currentFocus = focus
        }
        if let steps = snapshot.latestSteps,
           stepsProgress == nil || steps.stepIndex >= (stepsProgress?.stepIndex ?? -1)
        {
            stepsProgress = steps
        }

        // Surface any recent SQLite tool errors onto matching activity rows immediately
        for errTool in snapshot.recentToolErrors {
            if let idx = recentActivity.firstIndex(where: {
                if case let .toolActivity(ev) = $0 { return ev.stepIndex == errTool.stepIndex || ev.id == "live-tool-\(errTool.stepIndex)" }
                return false
            }), case var .toolActivity(existing) = recentActivity[idx] {
                existing.status = .failed
                existing.completedAt = existing.completedAt ?? now
                if let msg = errTool.errorMessage, !msg.isEmpty {
                    existing.outputPreview = msg
                }
                recentActivity[idx] = .toolActivity(existing)
            }
        }

        let setState: (TelemetryState) -> Void = { newState in
            if GravMotionPreferences.shared.reduceMotion {
                self.state = newState
            } else {
                withAnimation(GravMotionSpec.settle.animation) {
                    self.state = newState
                }
            }
        }

        switch snapshot.phase {
        case .idle:
            // Ground-truth SQLite confirms final reply is DONE with zero pending/running/waiting steps!
            if state != .idle && commands.allSatisfy({ $0.status != .running }) {
                isSpeculativeWALWorking = false
                lastFinalIdleAt = now
                currentFocus = nil
                if let started = turnStartedAt, lastTurnDuration == nil {
                    lastTurnDuration = max(1, now.timeIntervalSince(started))
                }
                settleToIdle()
            }

        case .working:
            isSpeculativeWALWorking = false
            if state == .idle {
                currentPhaseStartedAt = now
                if turnStartedAt == nil { turnStartedAt = now }
                setState(.working(startedAt: now))
            }
            scheduleIdleDecayIfNeeded()

        case let .thinking(liveText):
            isSpeculativeWALWorking = false
            if state != .thinking {
                currentPhaseStartedAt = now
                if turnStartedAt == nil { turnStartedAt = now }
                setState(.thinking)
            }
            if let liveText, !liveText.isEmpty {
                let liveSnap = ThinkingSnapshot(
                    stepIndex: snapshot.latestStepIndex,
                    text: liveText,
                    isTruncated: false,
                    isFullTextLoaded: true,
                    model: activeModel,
                    startedAt: currentThinking?.stepIndex == snapshot.latestStepIndex
                        ? (currentThinking?.startedAt ?? now)
                        : now,
                    completedAt: nil,
                    isActive: true
                )
                currentThinking = liveSnap
                if let idx = thinkingHistory.firstIndex(where: { $0.stepIndex == liveSnap.stepIndex }) {
                    thinkingHistory[idx] = liveSnap
                } else {
                    thinkingHistory.insert(liveSnap, at: 0)
                }
            }
            scheduleIdleDecayIfNeeded()

        case let .replying(liveReply):
            isSpeculativeWALWorking = false
            let liveSnap = AssistantResponseSnapshot(
                stepIndex: snapshot.latestStepIndex,
                promptPreview: latestResponse?.promptPreview,
                text: liveReply,
                isTruncated: false,
                isFullTextLoaded: true,
                model: activeModel,
                timestamp: now,
                isStreaming: true
            )
            latestResponse = liveSnap
            if let idx = responses.firstIndex(where: { $0.stepIndex == liveSnap.stepIndex }) {
                responses[idx] = liveSnap
            } else {
                responses.insert(liveSnap, at: 0)
            }
            if case .replying = state {
                state = .replying(liveSnap)
            } else {
                currentPhaseStartedAt = now
                setState(.replying(liveSnap))
            }
            scheduleIdleDecayIfNeeded()

        case .compacting:
            isSpeculativeWALWorking = false
            let event = CompactionEvent(stepIndex: snapshot.latestStepIndex, startedAt: now, isActive: true)
            if case .compacting = state {
                // Already showing compacting
            } else {
                currentPhaseStartedAt = now
                setState(.compacting(event))
            }
            scheduleIdleDecayIfNeeded()

        case let .waitingForInput(prompt):
            isSpeculativeWALWorking = false
            if case .waitingForInput = state {
                state = .waitingForInput(prompt)
            } else {
                currentPhaseStartedAt = now
                setState(.waitingForInput(prompt))
                onPeekRequested?(.needsInput(prompt))
            }
            cancelIdleDecayTimer()

        case let .runningTool(liveTool):
            isSpeculativeWALWorking = false
            if turnStartedAt == nil { turnStartedAt = now }
            applyLiveSQLiteTool(
                name: liveTool.name,
                argsJSON: liveTool.argsJSON,
                stepIndex: liveTool.stepIndex,
                now: now,
                setState: setState
            )
            scheduleIdleDecayIfNeeded()
        }
    }

    private func applyLiveSQLiteTool(
        name: String,
        argsJSON: String?,
        stepIndex: Int,
        now: Date,
        setState: (TelemetryState) -> Void
    ) {
        let dict: [String: Any]? = argsJSON
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }

        switch name {
        case "update_focus":
            if let focus = dict?["focus"] as? String, !focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                currentFocus = focus.trimmingCharacters(in: .whitespacesAndNewlines)
            }

        case "update_steps":
            if let steps = ConversationSQLiteProbe.parseStepsFromArgsJSON(argsJSON, stepIndex: stepIndex) {
                stepsProgress = steps
            }

        case "read_file", "view_file", "view_file_outline", "view_code_item":
            if let path = (dict?["Path"] as? String) ?? (dict?["AbsolutePath"] as? String) ?? (dict?["TargetFile"] as? String),
               !path.isEmpty
            {
                let startLine = dict?["StartLine"] as? Int
                let endLine = dict?["EndLine"] as? Int
                let ev = FileInspectionEvent(
                    id: "live-\(stepIndex)-\(path)",
                    stepIndex: stepIndex,
                    path: path,
                    startLine: startLine,
                    endLine: endLine,
                    timestamp: now,
                    toolName: name
                )
                currentPhaseStartedAt = now
                setState(.inspecting(ev))
            }

        case "run_command":
            if case .runningCommand = state { return }
            let cmdLine = (dict?["CommandLine"] as? String) ?? ""
            let summary = (dict?["toolSummary"] as? String) ?? ""
            let cmd = CommandExecutionEvent(
                id: "live-cmd-\(stepIndex)",
                stepIndex: stepIndex,
                commandLine: cmdLine,
                summary: summary,
                status: .running,
                startedAt: now
            )
            currentPhaseStartedAt = now
            setState(.runningCommand(cmd))

        case "search_web":
            let q = (dict?["query"] as? String) ?? ""
            let ev = AgentToolActivityEvent(
                id: "live-tool-\(stepIndex)",
                stepIndex: stepIndex,
                kind: .searchWeb,
                toolName: name,
                title: q.isEmpty ? "Searching web" : "Searching \"\(q)\"",
                detail: dict?["domain"] as? String,
                argumentsJSON: ConversationSQLiteProbe.prettyFormatJSON(argsJSON),
                status: .running,
                startedAt: now,
                timestamp: now
            )
            upsertActivity(.toolActivity(ev))
            currentPhaseStartedAt = now
            setState(.toolActivity(ev))

        case "call_mcp_tool", "list_resources", "read_resource":
            let server = (dict?["ServerName"] as? String) ?? "mcp"
            let tool = (dict?["ToolName"] as? String) ?? name
            let innerArgs: String? = {
                if let argObj = dict?["Arguments"] {
                    return ConversationSQLiteProbe.prettyFormatJSONObject(argObj)
                }
                return ConversationSQLiteProbe.prettyFormatJSON(argsJSON)
            }()
            let ev = AgentToolActivityEvent(
                id: "live-tool-\(stepIndex)",
                stepIndex: stepIndex,
                kind: .mcpTool,
                toolName: tool,
                serverName: server,
                title: "\(tool) · \(server)",
                detail: dict?["Uri"] as? String,
                argumentsJSON: innerArgs,
                status: .running,
                startedAt: now,
                timestamp: now
            )
            upsertActivity(.toolActivity(ev))
            currentPhaseStartedAt = now
            setState(.toolActivity(ev))

        case "invoke_subagent":
            let typeName = ((dict?["TypeName"] as? String) ?? "").lowercased()
            let role = (dict?["Role"] as? String) ?? (typeName.isEmpty ? "Subagent" : typeName)
            let kind: AgentToolActivityKind = typeName.contains("browser")
                ? .browser
                : (typeName.contains("image") ? .imageGeneration : .subagent)
            let prefix = kind == .browser ? "Browsing" : (kind == .imageGeneration ? "Generating image" : "Subagent")
            let ev = AgentToolActivityEvent(
                id: "live-tool-\(stepIndex)",
                stepIndex: stepIndex,
                kind: kind,
                toolName: name,
                title: "\(prefix) · \(role)",
                detail: dict?["Prompt"] as? String,
                argumentsJSON: ConversationSQLiteProbe.prettyFormatJSON(argsJSON),
                status: .running,
                startedAt: now,
                timestamp: now
            )
            upsertActivity(.toolActivity(ev))
            currentPhaseStartedAt = now
            setState(.toolActivity(ev))

        case "run_workflow":
            let desc = (dict?["Description"] as? String) ?? "Workflow"
            let ev = AgentToolActivityEvent(
                id: "live-tool-\(stepIndex)",
                stepIndex: stepIndex,
                kind: .workflow,
                toolName: name,
                title: "Workflow · \(desc)",
                detail: dict?["ScriptPath"] as? String,
                argumentsJSON: ConversationSQLiteProbe.prettyFormatJSON(argsJSON),
                status: .running,
                startedAt: now,
                timestamp: now
            )
            upsertActivity(.toolActivity(ev))
            currentPhaseStartedAt = now
            setState(.toolActivity(ev))

        case "schedule":
            let ev = AgentToolActivityEvent(
                id: "live-tool-\(stepIndex)",
                stepIndex: stepIndex,
                kind: .schedule,
                toolName: name,
                title: "Scheduling task",
                detail: dict?["Prompt"] as? String,
                argumentsJSON: ConversationSQLiteProbe.prettyFormatJSON(argsJSON),
                status: .running,
                startedAt: now,
                timestamp: now
            )
            upsertActivity(.toolActivity(ev))
            currentPhaseStartedAt = now
            setState(.toolActivity(ev))

        default:
            if state == .idle {
                currentPhaseStartedAt = now
                setState(.working(startedAt: now))
            }
        }
    }

    private func applyFallbackWALPulse(_ pulse: WALActivityPulse) {
        guard pulse.deltaBytes >= 4096 else { return }
        if Date().timeIntervalSince(lastFinalIdleAt) < 5.0 { return }
        let now = Date()
        switch state {
        case .idle:
            currentPhaseStartedAt = now
            isSpeculativeWALWorking = true
            state = .working(startedAt: now)
            scheduleIdleDecayIfNeeded()
        case .working, .thinking:
            if pulse.isRapidStreamingBurst && now.timeIntervalSince(currentPhaseStartedAt) >= 3.0 {
                state = .replying(latestResponse)
            }
            scheduleIdleDecayIfNeeded()
        default:
            scheduleIdleDecayIfNeeded()
        }
    }

    private func applySwarmSubagentUpdate(_ update: SwarmSubagentUpdate) {
        if GravMotionPreferences.shared.reduceMotion {
            swarmSnapshot = update.swarm
            subagents = update.subagents
        } else {
            withAnimation(GravMotionSpec.settle.animation) {
                swarmSnapshot = update.swarm
                subagents = update.subagents
            }
        }
    }

    // MARK: - Classification Application

    private func applyClassification(
        _ output: EventClassificationOutput,
        suppressPeeks: Bool
    ) {
        activeModel = output.activeModel
        tokenMetrics = output.tokenMetrics

        if let completedIdx = output.completedThinkingStepIndex {
            if var current = currentThinking, current.stepIndex == completedIdx {
                current.isActive = false
                if current.completedAt == nil {
                    current.completedAt = Date()
                }
                currentThinking = current
            }
            if let idx = thinkingHistory.firstIndex(where: { $0.stepIndex == completedIdx }) {
                thinkingHistory[idx].isActive = false
                if thinkingHistory[idx].completedAt == nil {
                    thinkingHistory[idx].completedAt = Date()
                }
                upsertActivity(.thinking(thinkingHistory[idx]))
            }
        }

        if let snapshot = output.thinkingSnapshot {
            currentThinking = snapshot
            if let existingIdx = thinkingHistory.firstIndex(where: { $0.stepIndex == snapshot.stepIndex }) {
                thinkingHistory[existingIdx] = snapshot
            } else {
                thinkingHistory.insert(snapshot, at: 0)
                if thinkingHistory.count > maxRetainedEvents {
                    thinkingHistory.removeLast(thinkingHistory.count - maxRetainedEvents)
                }
            }
            upsertActivity(.thinking(snapshot))
        }

        if let response = output.responseSnapshot {
            latestResponse = response
            if let existingIdx = responses.firstIndex(where: { $0.stepIndex == response.stepIndex }) {
                responses[existingIdx] = response
            } else {
                responses.insert(response, at: 0)
                if responses.count > maxRetainedEvents {
                    responses.removeLast(responses.count - maxRetainedEvents)
                }
            }
        }

        if let compaction = output.compactionEvent {
            upsertActivity(.compaction(compaction))
        }

        if let focus = output.focusUpdate, !focus.isEmpty {
            currentFocus = focus
        } else if output.clearFocus {
            currentFocus = nil
        }

        if let steps = output.stepsProgress {
            stepsProgress = steps
        }

        if let turnStart = output.turnStartedAt {
            turnStartedAt = turnStart
            lastTurnDuration = nil
        }
        if let turnDur = output.lastTurnDuration {
            lastTurnDuration = turnDur
        }

        if !output.toolActivities.isEmpty {
            for activity in output.toolActivities {
                // Remove any speculative live-tool row for the same tool so the transcript row replaces it cleanly
                recentActivity.removeAll {
                    if case let .toolActivity(existing) = $0 {
                        return existing.id.hasPrefix("live-tool-") && existing.toolName == activity.toolName
                    }
                    return false
                }
                upsertActivity(.toolActivity(activity))
            }
        }

        if !output.updatedToolActivities.isEmpty {
            for updated in output.updatedToolActivities {
                upsertActivity(.toolActivity(updated))
            }
        }

        if !output.fileInspections.isEmpty {
            for inspection in output.fileInspections {
                upsertActivity(.fileInspection(inspection))
            }
        }

        if !output.fileChanges.isEmpty {
            for change in output.fileChanges {
                if let existingIdx = fileChanges.firstIndex(where: { $0.id == change.id }) {
                    fileChanges[existingIdx] = change
                } else {
                    fileChanges.insert(change, at: 0)
                }
                upsertActivity(.fileChange(change))
            }
            if fileChanges.count > maxRetainedEvents {
                fileChanges.removeLast(fileChanges.count - maxRetainedEvents)
            }
        }

        if !output.truncatedFileChangeStepIndices.isEmpty {
            for stepIdx in output.truncatedFileChangeStepIndices {
                enqueueTruncatedFileHydration(stepIndex: stepIdx)
            }
        }

        for started in output.startedCommands {
            upsertCommand(started)
            if !suppressPeeks || isRecentlyStarted(started) {
                startLiveTaskLogTailing(for: started)
            }
        }

        for updated in output.updatedCommands {
            upsertCommand(updated)
            if updated.status == .running {
                if !suppressPeeks || isRecentlyStarted(updated) {
                    startLiveTaskLogTailing(for: updated)
                }
            } else {
                stopLiveTaskLogTailing(commandID: updated.id)
                hydrateCompletedCommandLogIfNeeded(updated)
            }
        }

        let previousState = state
        isSpeculativeWALWorking = false
        state = output.state

        if output.state == .idle {
            finalizeActiveThinking()
            finalizeActiveCompactions()
        }

        if output.state == .idle && previousState != .idle && !suppressPeeks {
            lastFinalIdleAt = Date()
        } else if output.state != previousState {
            switch output.state {
            case let .working(startedAt):
                currentPhaseStartedAt = suppressPeeks ? startedAt : Date()
            case .thinking:
                currentPhaseStartedAt = suppressPeeks ? (output.thinkingSnapshot?.startedAt ?? Date()) : Date()
            case .replying:
                currentPhaseStartedAt = Date()
            case let .compacting(event):
                currentPhaseStartedAt = suppressPeeks ? event.startedAt : Date()
            case let .inspecting(event):
                currentPhaseStartedAt = suppressPeeks ? event.timestamp : Date()
            case let .editing(event):
                currentPhaseStartedAt = suppressPeeks ? event.timestamp : Date()
            case let .runningCommand(cmd):
                currentPhaseStartedAt = cmd.startedAt
            case .waitingForInput:
                currentPhaseStartedAt = Date()
            case let .toolActivity(event):
                currentPhaseStartedAt = suppressPeeks ? event.timestamp : Date()
            case .idle:
                break
            }
        }

        if output.didMutateAgentsOrSwarm, let watcher = activeSwarmWatcher {
            Task {
                await watcher.triggerRefresh()
            }
        }

        if !suppressPeeks {
            for peekEvent in output.peekEvents {
                onPeekRequested?(peekEvent)
            }
        }
    }

    private func upsertCommand(_ command: CommandExecutionEvent) {
        if let idx = commands.firstIndex(where: { $0.id == command.id }) {
            // Preserve live-tailed logOutput if the updated event has an empty log body
            var merged = command
            if merged.logOutput.isEmpty, !commands[idx].logOutput.isEmpty {
                merged.logOutput = commands[idx].logOutput
            }
            commands[idx] = merged
            upsertActivity(.command(merged))
        } else {
            commands.insert(command, at: 0)
            if commands.count > maxRetainedEvents {
                commands.removeLast(commands.count - maxRetainedEvents)
            }
            upsertActivity(.command(command))
        }
    }

    private func upsertActivity(_ item: TelemetryActivityItem) {
        if let idx = recentActivity.firstIndex(where: { $0.id == item.id }) {
            recentActivity[idx] = item
        } else {
            recentActivity.insert(item, at: 0)
            if recentActivity.count > maxRetainedEvents {
                recentActivity.removeLast(recentActivity.count - maxRetainedEvents)
            }
        }
    }

    // MARK: - Live Task Logs & Completed Step Output

    private func isRecentlyStarted(_ command: CommandExecutionEvent) -> Bool {
        Date().timeIntervalSince(command.startedAt) < 900
    }

    private func startLiveTaskLogTailing(for command: CommandExecutionEvent) {
        guard let taskLogURL = command.taskLogURL, isMonitoring, !isPaused else { return }
        let generation = sessionGeneration
        let commandID = command.id
        let logTailer = taskLogTailer

        Task { [weak self] in
            await logTailer.startTailing(commandID: commandID, taskLogURL: taskLogURL) { [weak self] id, cleanedLog in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionGeneration == generation else { return }
                    self.applyLiveTaskLogUpdate(commandID: id, logOutput: cleanedLog)
                }
            }
        }
    }

    private func stopLiveTaskLogTailing(commandID: String) {
        let logTailer = taskLogTailer
        Task {
            await logTailer.stopTailing(commandID: commandID)
        }
    }

    private func applyLiveTaskLogUpdate(commandID: String, logOutput: String) {
        guard let idx = commands.firstIndex(where: { $0.id == commandID }) else { return }
        commands[idx].logOutput = logOutput
        let updated = commands[idx]
        upsertActivity(.command(updated))

        if case let .runningCommand(active) = state, active.id == commandID {
            state = .runningCommand(updated)
            // Reset command liveness timer whenever fresh stdout/stderr arrives
            scheduleIdleDecayIfNeeded()
        }
    }

    private func enqueueTruncatedFileHydration(stepIndex: Int) {
        guard !hydratedTruncatedFileSteps.contains(stepIndex) else { return }
        if !pendingTruncatedHydrationSteps.contains(stepIndex) {
            pendingTruncatedHydrationSteps.append(stepIndex)
        }
    }

    /// Hydrates recent truncated file-change steps in ascending chronological order so
    /// `write_file(Overwrite: true)` diffs against the exact prior file content (`+536 -62`
    /// instead of treating every line of an overwritten file as newly added).
    private func flushTruncatedFileHydrationQueue(isHistoricalReplay: Bool) {
        guard !pendingTruncatedHydrationSteps.isEmpty, let session = activeSession else { return }

        var batch = pendingTruncatedHydrationSteps.sorted()
        pendingTruncatedHydrationSteps.removeAll()
        if isHistoricalReplay && batch.count > 36 {
            batch = Array(batch.suffix(36))
        }
        batch = batch.filter { !hydratedTruncatedFileSteps.contains($0) }
        guard !batch.isEmpty else { return }

        for idx in batch {
            hydratedTruncatedFileSteps.insert(idx)
        }

        let generation = sessionGeneration
        let fullURL = session.fullTranscriptURL
        let tailer = activeTailer
        let existingTask = truncatedHydrationTask

        truncatedHydrationTask = Task { [weak self] in
            await existingTask?.value
            guard !Task.isCancelled else { return }

            for stepIndex in batch {
                guard !Task.isCancelled else { return }
                let fullStep: TranscriptStep?
                if let tailer {
                    fullStep = await tailer.readFullStep(stepIndex: stepIndex, from: fullURL)
                } else {
                    fullStep = await Task.detached(priority: .utility) {
                        TranscriptTailer.readFullStep(stepIndex: stepIndex, from: fullURL)
                    }.value
                }

                guard let fullStep else { continue }

                await MainActor.run { [weak self] in
                    guard let self, self.sessionGeneration == generation else { return }
                    let result = EventClassifier.extractFileChangesWithContents(
                        from: fullStep,
                        priorFileContents: self.hydratedFileContents
                    )
                    self.hydratedFileContents = result.updatedContents
                    for fullChange in result.changes {
                        if let idx = self.fileChanges.firstIndex(where: { $0.id == fullChange.id }) {
                            var merged = self.fileChanges[idx]
                            merged.diffHunks = fullChange.diffHunks
                            if fullChange.kind == .create || fullChange.kind == .overwrite {
                                merged.addedLines = fullChange.addedLines
                                merged.removedLines = fullChange.removedLines
                            } else if merged.addedLines <= 2 && merged.removedLines <= 2
                                && (fullChange.addedLines > merged.addedLines || fullChange.removedLines > merged.removedLines)
                            {
                                merged.addedLines = fullChange.addedLines
                                merged.removedLines = fullChange.removedLines
                            }
                            self.fileChanges[idx] = merged
                            self.upsertActivity(.fileChange(merged))
                        }
                    }
                }
            }
        }
    }

    private func hydrateCompletedCommandLogIfNeeded(_ command: CommandExecutionEvent) {
        guard command.logOutput.isEmpty || command.isTruncated || command.exitCode == nil else {
            return
        }
        let fm = FileManager.default
        if let stepOutputURL = command.stepOutputURL, fm.fileExists(atPath: stepOutputURL.path) {
            loadCompletedStepOutput(commandID: command.id, outputURL: stepOutputURL)
        } else if let taskLogURL = command.taskLogURL, fm.fileExists(atPath: taskLogURL.path) {
            loadCompletedStepOutput(commandID: command.id, outputURL: taskLogURL)
        }
    }

    private func loadCompletedStepOutput(commandID: String, outputURL: URL) {
        let generation = sessionGeneration
        let logTailer = taskLogTailer

        Task { [weak self] in
            guard let loaded = await logTailer.readStepOutput(at: outputURL) else { return }
            let parsedExitCode = EventClassifier.extractExitCode(from: loaded.text)
            let cleanedText = EventClassifier.extractCleanCommandOutput(from: loaded.text)
            let finalText = cleanedText.isEmpty ? loaded.text : cleanedText

            await MainActor.run { [weak self] in
                guard let self, self.sessionGeneration == generation else { return }
                guard let idx = self.commands.firstIndex(where: { $0.id == commandID }) else { return }
                if !finalText.isEmpty {
                    self.commands[idx].logOutput = finalText
                    self.commands[idx].isTruncated = loaded.isTruncated
                }
                if let parsedExitCode, self.commands[idx].exitCode == nil {
                    self.commands[idx].exitCode = parsedExitCode
                    self.commands[idx].status = parsedExitCode == 0 ? .succeeded : .failed
                }
                self.upsertActivity(.command(self.commands[idx]))
            }
        }
    }

    private func isTaskLogRecentlyModified(_ url: URL?, within seconds: TimeInterval) -> Bool {
        guard let url,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date
        else {
            return false
        }
        return Date().timeIntervalSince(modified) <= seconds
    }

    // MARK: - Active-Only Idle Decay (Zero Idle CPU)

    private func scheduleIdleDecayIfNeeded() {
        cancelIdleDecayTimer()

        guard state.isActive, !isPaused else { return }

        // Antigravity writes `PLANNER_RESPONSE` only after a model finishes thinking for that step,
        // which routinely takes 15–60s on deep reasoning models. Keep active turns alive generously
        // (75s safety fallback for manual Cancel/Stop) while normal turn completions still drop to
        // `.idle` instantaneously (0ms) on the final `PLANNER_RESPONSE`.
        let isRunningCommand: Bool
        if case .runningCommand = state {
            isRunningCommand = true
        } else {
            isRunningCommand = false
        }
        let timeout: TimeInterval
        if idleDecaySeconds < 5.0 {
            // Preserve fast deterministic timeouts in unit tests
            timeout = isRunningCommand ? max(45.0, idleDecaySeconds * 3.5) : idleDecaySeconds
        } else if isSpeculativeWALWorking {
            // Speculative WAL-only `.working` must settle rapidly (9s) if no sustained WAL growth
            // or transcript step follows, preventing stuck `Thinking for 1m 13s` after idle flushes.
            timeout = 9.0
        } else if isRunningCommand {
            timeout = max(55.0, idleDecaySeconds * 4.5)
        } else {
            timeout = max(45.0, idleDecaySeconds * 3.5)
        }
        let delayNanoseconds = UInt64(timeout * 1_000_000_000)

        idleDecayTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            if isRunningCommand {
                if let running = self.activeCommand, self.isTaskLogRecentlyModified(running.taskLogURL, within: 30) {
                    self.scheduleIdleDecayIfNeeded()
                } else {
                    self.forceSettleIdle()
                }
            } else {
                self.settleToIdle()
            }
        }
    }

    private func cancelIdleDecayTimer() {
        idleDecayTask?.cancel()
        idleDecayTask = nil
    }

    private func settleToIdle() {
        cancelIdleDecayTimer()
        classifier.markIdle()
        state = classifier.state

        if state == .idle {
            finalizeActiveThinking()
            finalizeActiveCompactions()
            refreshUnreadSessions()
            refreshSessionArtifacts()
            refreshRuntimeInspection()
        }
    }

    private func finalizeActiveThinking() {
        let now = Date()
        if var thinking = currentThinking, thinking.isActive {
            thinking.isActive = false
            thinking.completedAt = thinking.completedAt ?? now
            currentThinking = thinking
        }
        for idx in thinkingHistory.indices where thinkingHistory[idx].isActive {
            thinkingHistory[idx].isActive = false
            thinkingHistory[idx].completedAt = thinkingHistory[idx].completedAt ?? now
            upsertActivity(.thinking(thinkingHistory[idx]))
        }
    }

    private func finalizeActiveCompactions() {
        let now = Date()
        for idx in recentActivity.indices {
            if case var .compaction(event) = recentActivity[idx], event.isActive {
                event.isActive = false
                event.completedAt = event.completedAt ?? now
                recentActivity[idx] = .compaction(event)
            }
        }
    }

    // MARK: - Event-Driven App Launch/Termination Observers

    private func installWorkspaceObservers() {
        removeWorkspaceObservers()
        let center = NSWorkspace.shared.notificationCenter
        let targetBundleID = AntigravityAppDetector.bundleIdentifier

        let launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let bundleID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .bundleIdentifier
            guard bundleID == targetBundleID else { return }
            Task { @MainActor [weak self] in
                self?.refreshConnectionStatus()
            }
        }

        let terminateObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let bundleID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .bundleIdentifier
            guard bundleID == targetBundleID else { return }
            Task { @MainActor [weak self] in
                self?.refreshConnectionStatus()
                self?.forceSettleIdle()
            }
        }

        workspaceObservers = [launchObserver, terminateObserver]
    }

    private func removeWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            center.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }
}
