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
    private var hydratedTruncatedFileSteps: Set<Int> = []
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

    /// Opens a file directly in Antigravity (falling back to default macOS handler).
    public func openInAntigravity(path: String) {
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
        hydratedTruncatedFileSteps.removeAll()
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
        latestResponse = nil
        responses = []
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
                hydrateTruncatedFileChangesIfNeeded(stepIndex: stepIdx, isHistoricalReplay: suppressPeeks)
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
            // Reset command liveness timer whenever fresh stdout/stderr arrives
            scheduleIdleDecayIfNeeded()
        }
    }

    private func hydrateTruncatedFileChangesIfNeeded(stepIndex: Int, isHistoricalReplay: Bool) {
        guard !hydratedTruncatedFileSteps.contains(stepIndex) else { return }
        guard let session = activeSession else { return }
        // During large historical replay, hydrate only recent truncated steps so startup stays instantaneous
        if isHistoricalReplay && hydratedTruncatedFileSteps.count >= 20 {
            return
        }
        hydratedTruncatedFileSteps.insert(stepIndex)

        let generation = sessionGeneration
        let fullURL = session.fullTranscriptURL
        let tailer = activeTailer

        Task { [weak self] in
            let fullStep: TranscriptStep?
            if let tailer {
                fullStep = await tailer.readFullStep(stepIndex: stepIndex, from: fullURL)
            } else {
                fullStep = await Task.detached(priority: .utility) {
                    TranscriptTailer.readFullStep(stepIndex: stepIndex, from: fullURL)
                }.value
            }

            guard let fullStep else { return }
            let fullChanges = EventClassifier.extractFileChanges(from: fullStep)
            guard !fullChanges.isEmpty else { return }

            await MainActor.run { [weak self] in
                guard let self, self.sessionGeneration == generation else { return }
                for fullChange in fullChanges {
                    if let idx = self.fileChanges.firstIndex(where: { $0.id == fullChange.id }) {
                        var merged = self.fileChanges[idx]
                        merged.diffHunks = fullChange.diffHunks
                        // Keep authoritative GENERIC counts if larger, otherwise use full untruncated counts
                        if fullChange.kind == .create || fullChange.kind == .overwrite
                            || (merged.addedLines <= 2 && merged.removedLines <= 2
                                && (fullChange.addedLines > merged.addedLines || fullChange.removedLines > merged.removedLines))
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

        // While a shell command is running, give it a generous quiet-liveness window (45s);
        // if no transcript step or task log byte arrives in 45s (e.g., user clicked Stop),
        // re-check log mtime and settle gracefully to `.idle`.
        let isRunningCommand: Bool
        if case .runningCommand = state {
            isRunningCommand = true
        } else {
            isRunningCommand = false
        }
        let timeout = isRunningCommand ? max(45.0, idleDecaySeconds * 3.5) : idleDecaySeconds
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

        if state == .idle, var thinking = currentThinking, thinking.isActive {
            thinking.isActive = false
            thinking.completedAt = thinking.completedAt ?? Date()
            currentThinking = thinking
            if let idx = thinkingHistory.firstIndex(where: { $0.stepIndex == thinking.stepIndex }) {
                thinkingHistory[idx] = thinking
                upsertActivity(.thinking(thinking))
            }
        }
        if state == .idle {
            finalizeActiveCompactions()
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
