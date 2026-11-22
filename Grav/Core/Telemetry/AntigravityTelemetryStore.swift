import AppKit
import Foundation
import Observation

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
    public internal(set) var fileChanges: [FileChangeEvent] = []
    public internal(set) var commands: [CommandExecutionEvent] = []
    public internal(set) var recentActivity: [TelemetryActivityItem] = []
    public internal(set) var tokenMetrics = TokenMetrics()
    public internal(set) var activeModel: String?

    public internal(set) var isPaused: Bool = false
    public internal(set) var isMonitoring: Bool = false

    /// Emitted when a significant telemetry transition warrants a subtle NotchKit `peek()`.
    public var onPeekRequested: ((NotchPeekEvent) -> Void)?

    // MARK: - Internal Engine Dependencies

    private let appDetector: AntigravityAppDetector
    private let taskLogTailer: TaskLogTailer
    private let idleDecaySeconds: TimeInterval
    private let maxRetainedEvents: Int

    private var discovery: ConversationDiscovery?
    private var activeTailer: TranscriptTailer?
    private var classifier = EventClassifier()

    private var userPinnedSessionID: String?
    private var isHydratingActiveSession: Bool = false
    private var idleDecayTask: Task<Void, Never>?
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
    }

    public func stop() {
        isMonitoring = false
        cancelIdleDecayTimer()
        removeWorkspaceObservers()

        let currentDiscovery = discovery
        discovery = nil
        let currentTailer = activeTailer
        activeTailer = nil
        let logTailer = taskLogTailer

        Task {
            await currentDiscovery?.stopWatching()
            await currentTailer?.stopWatching()
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
            let logTailer = taskLogTailer
            Task {
                await currentTailer?.stopWatching()
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

    public func activateAntigravityApp() {
        appDetector.activateAntigravityApp()
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

        return fullStep
    }

    /// Reveals a changed file in Finder.
    public func revealInFinder(path: String) {
        appDetector.revealInFinder(path: path)
    }

    /// Opens a file directly in Antigravity (falling back to default macOS handler).
    public func openInAntigravity(path: String) {
        appDetector.openInAntigravity(path: path)
    }

    /// Convenience accessor for the most recent running command, if any.
    public var activeCommand: CommandExecutionEvent? {
        commands.first(where: { $0.status == .running })
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
        for step in steps {
            lastStepDate = step.parsedDate
            let classified = classifier.process(step: step, session: activeSession)
            applyClassification(classified, suppressPeeks: isInitialHydration || isPaused)
        }

        if isInitialHydration {
            // If the latest historical step is older than the idle window, settle calmly to `.idle`
            if let lastStepDate, Date().timeIntervalSince(lastStepDate) > idleDecaySeconds {
                if activeCommand == nil {
                    settleToIdle()
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
    }

    private func activateSession(_ session: ConversationSession) {
        sessionGeneration &+= 1
        let generation = sessionGeneration

        cancelIdleDecayTimer()
        let previousTailer = activeTailer
        activeTailer = nil
        let logTailer = taskLogTailer

        // Reset session-scoped observable state
        activeSession = session
        classifier.reset()
        state = .idle
        currentThinking = nil
        thinkingHistory = []
        fileChanges = []
        commands = []
        recentActivity = []
        tokenMetrics = TokenMetrics()
        activeModel = nil

        let tailer = TranscriptTailer(transcriptURL: session.transcriptURL, initialOffset: 0)
        activeTailer = tailer
        isHydratingActiveSession = true

        guard isMonitoring, !isPaused else {
            Task {
                await previousTailer?.stopWatching()
                await logTailer.stopAll()
            }
            return
        }

        Task { [weak self] in
            await previousTailer?.stopWatching()
            await logTailer.stopAll()

            // Initial synchronous catch-up read (suppressing peek bursts for historical steps)
            let initialSteps = await tailer.readNewSteps()
            await MainActor.run { [weak self] in
                guard let self, self.sessionGeneration == generation else { return }
                self.ingestSteps(initialSteps, isInitialHydration: true)
                self.isHydratingActiveSession = false
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

        Task { [weak self] in
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
        let logTailer = taskLogTailer

        activeSession = nil
        classifier.reset()
        state = .idle
        currentThinking = nil
        thinkingHistory = []
        fileChanges = []
        commands = []
        recentActivity = []
        tokenMetrics = TokenMetrics()
        activeModel = nil

        Task {
            await previousTailer?.stopWatching()
            await logTailer.stopAll()
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

        if !output.fileChanges.isEmpty {
            for change in output.fileChanges {
                fileChanges.insert(change, at: 0)
                upsertActivity(.fileChange(change))
            }
            if fileChanges.count > maxRetainedEvents {
                fileChanges.removeLast(fileChanges.count - maxRetainedEvents)
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
                if let stepOutputURL = updated.stepOutputURL,
                   (updated.isTruncated || updated.logOutput.isEmpty)
                {
                    loadCompletedStepOutput(commandID: updated.id, outputURL: stepOutputURL)
                }
            }
        }

        state = output.state

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
        }
    }

    private func loadCompletedStepOutput(commandID: String, outputURL: URL) {
        let generation = sessionGeneration
        let logTailer = taskLogTailer

        Task { [weak self] in
            guard let loaded = await logTailer.readStepOutput(at: outputURL) else { return }
            await MainActor.run { [weak self] in
                guard let self, self.sessionGeneration == generation else { return }
                guard let idx = self.commands.firstIndex(where: { $0.id == commandID }) else { return }
                if !loaded.text.isEmpty {
                    self.commands[idx].logOutput = loaded.text
                    self.commands[idx].isTruncated = loaded.isTruncated
                    self.upsertActivity(.command(self.commands[idx]))
                }
            }
        }
    }

    // MARK: - Active-Only Idle Decay (Zero Idle CPU)

    private func scheduleIdleDecayIfNeeded() {
        cancelIdleDecayTimer()

        // Never run a background timer when already idle or while a command is actively executing
        guard state.isActive, !isPaused else { return }
        if case .runningCommand = state {
            return
        }

        let delayNanoseconds = UInt64(idleDecaySeconds * 1_000_000_000)
        idleDecayTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.settleToIdle()
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

        if state == .idle, var thinking = currentThinking, thinking.isActive {
            thinking.isActive = false
            thinking.completedAt = thinking.completedAt ?? Date()
            currentThinking = thinking
            if let idx = thinkingHistory.firstIndex(where: { $0.stepIndex == thinking.stepIndex }) {
                thinkingHistory[idx] = thinking
                upsertActivity(.thinking(thinking))
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
