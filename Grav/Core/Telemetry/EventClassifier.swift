import Foundation

/// Incremental output emitted by `EventClassifier` for each processed `TranscriptStep`.
public struct EventClassificationOutput: Sendable, Equatable {
    public var state: TelemetryState
    public var activeModel: String?
    public var tokenMetrics: TokenMetrics
    public var thinkingSnapshot: ThinkingSnapshot?
    public var compactionEvent: CompactionEvent?
    public var responseSnapshot: AssistantResponseSnapshot?
    public var completedThinkingStepIndex: Int?
    public var fileInspections: [FileInspectionEvent]
    public var fileChanges: [FileChangeEvent]
    public var truncatedFileChangeStepIndices: [Int]
    public var startedCommands: [CommandExecutionEvent]
    public var updatedCommands: [CommandExecutionEvent]
    public var peekEvents: [NotchPeekEvent]
    public var didMutateAgentsOrSwarm: Bool

    public init(
        state: TelemetryState = .idle,
        activeModel: String? = nil,
        tokenMetrics: TokenMetrics = TokenMetrics(),
        thinkingSnapshot: ThinkingSnapshot? = nil,
        compactionEvent: CompactionEvent? = nil,
        responseSnapshot: AssistantResponseSnapshot? = nil,
        completedThinkingStepIndex: Int? = nil,
        fileInspections: [FileInspectionEvent] = [],
        fileChanges: [FileChangeEvent] = [],
        truncatedFileChangeStepIndices: [Int] = [],
        startedCommands: [CommandExecutionEvent] = [],
        updatedCommands: [CommandExecutionEvent] = [],
        peekEvents: [NotchPeekEvent] = [],
        didMutateAgentsOrSwarm: Bool = false
    ) {
        self.state = state
        self.activeModel = activeModel
        self.tokenMetrics = tokenMetrics
        self.thinkingSnapshot = thinkingSnapshot
        self.compactionEvent = compactionEvent
        self.responseSnapshot = responseSnapshot
        self.completedThinkingStepIndex = completedThinkingStepIndex
        self.fileInspections = fileInspections
        self.fileChanges = fileChanges
        self.truncatedFileChangeStepIndices = truncatedFileChangeStepIndices
        self.startedCommands = startedCommands
        self.updatedCommands = updatedCommands
        self.peekEvents = peekEvents
        self.didMutateAgentsOrSwarm = didMutateAgentsOrSwarm
    }
}

/// Pure, `Sendable` telemetry state machine that classifies raw Antigravity `TranscriptStep`s into
/// `ThinkingSnapshot`s, `FileChangeEvent`s with real diffs, `CommandExecutionEvent`s,
/// `TelemetryState` transitions, and `NotchPeekEvent` triggers.
public struct EventClassifier: Sendable {
    public private(set) var state: TelemetryState = .idle
    public private(set) var activeModel: String?
    public private(set) var tokenMetrics = TokenMetrics()
    public private(set) var activeThinkingStepIndex: Int?
    public private(set) var pendingCommands: [CommandExecutionEvent] = []
    internal var pendingFileChanges: [FileChangeEvent] = []

    internal var processedTokenStepIndices: Set<Int> = []
    internal var burstEditedPaths: Set<String> = []
    internal var hasPeekedMultiFileBurst: Bool = false
    internal var lastBackgroundNoticeStepIndex: Int?
    internal var confirmedBackgroundCommandIDs: Set<String> = []
    internal var lastUserPromptPreview: String?
    internal var isTurnActive: Bool = false

    public init() {}

    /// Resets all accumulated session classification state (e.g., when switching active sessions).
    public mutating func reset() {
        state = .idle
        activeModel = nil
        tokenMetrics = TokenMetrics()
        activeThinkingStepIndex = nil
        pendingCommands.removeAll()
        pendingFileChanges.removeAll()
        processedTokenStepIndices.removeAll()
        burstEditedPaths.removeAll()
        hasPeekedMultiFileBurst = false
        lastBackgroundNoticeStepIndex = nil
        confirmedBackgroundCommandIDs.removeAll()
        lastUserPromptPreview = nil
        isTurnActive = false
    }

    /// Marks the telemetry state as `.idle` (for example after an idle decay timeout) and clears
    /// transient burst counters.
    public mutating func markIdle() {
        if pendingCommands.isEmpty {
            state = .idle
            activeThinkingStepIndex = nil
            burstEditedPaths.removeAll()
            hasPeekedMultiFileBurst = false
            isTurnActive = false
        }
    }

    /// Settles all lingering pending commands and forces the classifier into `.idle`
    /// (used when Antigravity quits, a turn finishes, or a command stalls/cancels).
    public mutating func forceIdle(at date: Date = Date()) -> [CommandExecutionEvent] {
        var settled: [CommandExecutionEvent] = []
        if !pendingCommands.isEmpty {
            for existing in pendingCommands {
                let done = CommandExecutionEvent(
                    id: existing.id,
                    stepIndex: existing.stepIndex,
                    resultStepIndex: existing.resultStepIndex,
                    commandLine: existing.commandLine,
                    summary: existing.summary,
                    status: .succeeded,
                    exitCode: existing.exitCode ?? 0,
                    startedAt: existing.startedAt,
                    completedAt: existing.completedAt ?? date,
                    logOutput: existing.logOutput,
                    isTruncated: existing.isTruncated,
                    taskLogURL: existing.taskLogURL,
                    stepOutputURL: existing.stepOutputURL
                )
                settled.append(done)
            }
            pendingCommands.removeAll()
        }
        state = .idle
        activeThinkingStepIndex = nil
        burstEditedPaths.removeAll()
        hasPeekedMultiFileBurst = false
        lastBackgroundNoticeStepIndex = nil
        confirmedBackgroundCommandIDs.removeAll()
        isTurnActive = false
        return settled
    }

    /// Processes a single `TranscriptStep` from a conversation session and returns all classified
    /// telemetry events and updated high-level state.
    public mutating func process(
        step: TranscriptStep,
        session: ConversationSession? = nil
    ) -> EventClassificationOutput {
        let previousState = state
        let stepDate = step.parsedDate

        // 1. Update active model and cumulative token usage (deduplicated by step_index)
        if let model = step.model, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            activeModel = model
        }
        if !processedTokenStepIndices.contains(step.stepIndex) {
            let input = step.inputTokens ?? 0
            let cache = step.cacheReadTokens ?? 0
            let output = step.outputTokens ?? 0
            if input > 0 || cache > 0 || output > 0 {
                processedTokenStepIndices.insert(step.stepIndex)
                tokenMetrics.inputTokens += input
                tokenMetrics.cacheReadTokens += cache
                tokenMetrics.outputTokens += output
            }
        }

        var output = EventClassificationOutput(
            state: state,
            activeModel: activeModel,
            tokenMetrics: tokenMetrics
        )

        // 2. Classify thinking stream, user prompt, and context compaction updates
        let trimmedThinking = step.thinking?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let toolCalls = step.toolCalls ?? []
        let isFinalPlannerResponse = step.type == "PLANNER_RESPONSE"
            && toolCalls.isEmpty
            && step.status == "DONE"

        let upperType = step.type?.uppercased() ?? ""
        let isCompactionStep = upperType == "CHECKPOINT"
            || upperType.contains("COMPACT")
            || (step.source == "SYSTEM" && (step.content?.localizedCaseInsensitiveContains("compaction") == true))

        if isCompactionStep {
            isTurnActive = true
            let isDone = step.status == "DONE"
            let event = CompactionEvent(
                stepIndex: step.stepIndex,
                startedAt: stepDate,
                completedAt: isDone ? stepDate : nil,
                isActive: !isDone
            )
            output.compactionEvent = event
        }

        if !trimmedThinking.isEmpty {
            isTurnActive = !isFinalPlannerResponse
            let isTruncated = step.isFieldTruncated("thinking")
            let isThinkingStillActive = !isFinalPlannerResponse
            let snapshot = ThinkingSnapshot(
                stepIndex: step.stepIndex,
                text: trimmedThinking,
                isTruncated: isTruncated,
                isFullTextLoaded: !isTruncated,
                model: step.model ?? activeModel,
                startedAt: stepDate,
                completedAt: isThinkingStillActive ? nil : stepDate,
                isActive: isThinkingStillActive
            )
            output.thinkingSnapshot = snapshot

            if let prevActive = activeThinkingStepIndex, prevActive != step.stepIndex {
                output.completedThinkingStepIndex = prevActive
            }
            activeThinkingStepIndex = isThinkingStillActive ? step.stepIndex : nil

            if previousState == .idle {
                output.peekEvents.append(.thinkingStarted)
            }
        } else if step.type == "USER_INPUT" {
            // Capture clean user prompt preview for pairing with the assistant's reply
            if let rawContent = step.content {
                let cleaned = Self.extractCleanUserPrompt(from: rawContent)
                if !cleaned.isEmpty {
                    lastUserPromptPreview = cleaned
                }
            }
            // A fresh user prompt resets multi-file burst tracking and clears any orphaned commands from prior turns
            burstEditedPaths.removeAll()
            hasPeekedMultiFileBurst = false
            if let prevActive = activeThinkingStepIndex {
                output.completedThinkingStepIndex = prevActive
                activeThinkingStepIndex = nil
            }
            if !pendingCommands.isEmpty {
                let orphaned = forceIdle(at: stepDate)
                output.updatedCommands.append(contentsOf: orphaned)
            }
            isTurnActive = true
        }

        // 2b. Capture real-time AI Assistant responses (`PLANNER_RESPONSE` with visible content)
        if step.type == "PLANNER_RESPONSE",
           let rawReply = step.content?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawReply.isEmpty
        {
            let isTruncated = step.isFieldTruncated("content")
            output.responseSnapshot = AssistantResponseSnapshot(
                stepIndex: step.stepIndex,
                promptPreview: lastUserPromptPreview,
                text: rawReply,
                isTruncated: isTruncated,
                isFullTextLoaded: !isTruncated,
                model: step.model ?? activeModel,
                timestamp: stepDate,
                isStreaming: step.status != "DONE"
            )
        }

        // 3. Classify tool calls (file edits, creates, overwrites, deletes, and shell commands)
        if !toolCalls.isEmpty {
            pendingFileChanges.removeAll()
            let hasNonCommandTool = toolCalls.contains { $0.name != "run_command" }
            if hasNonCommandTool {
                isTurnActive = true
            }
            let agentSwarmTools: Set<String> = [
                "swarm", "post_message", "read_board", "swarm_wait",
                "invoke_subagent", "define_subagent", "manage_subagents", "send_message",
            ]
            if toolCalls.contains(where: { agentSwarmTools.contains($0.name) }) {
                output.didMutateAgentsOrSwarm = true
            }
            classifyToolCalls(
                toolCalls,
                step: step,
                stepDate: stepDate,
                session: session,
                into: &output
            )
            if !output.fileChanges.isEmpty {
                pendingFileChanges = output.fileChanges
                if step.isFieldTruncated("tool_calls") {
                    output.truncatedFileChangeStepIndices.append(step.stepIndex)
                }
            }
        }

        // 4. Correlate subsequent tool-result steps (`GENERIC` / `SYSTEM_MESSAGE`) with pending file edits & commands
        if !pendingFileChanges.isEmpty, toolCalls.isEmpty, step.type == "GENERIC" {
            correlateFileEditResult(step: step, into: &output)
        }

        var commandJustFinished = false
        if !pendingCommands.isEmpty, toolCalls.isEmpty, step.type != "USER_INPUT" {
            commandJustFinished = correlateCommandResult(
                step: step,
                stepDate: stepDate,
                session: session,
                into: &output
            )
        }

        // 4b. If Antigravity delivered a final response (`PLANNER_RESPONSE`, no tool calls, `DONE`)
        // and there is NO confirmed running background task, settle any stale pending commands so
        // the Notch drops cleanly to `.idle`. If a background task IS running, keep tracking it!
        let hasConfirmedBackgroundTask = pendingCommands.contains { confirmedBackgroundCommandIDs.contains($0.id) }
        let isWaitingForFreshBackgroundTask = isFinalPlannerResponse
            && !pendingCommands.isEmpty
            && (hasConfirmedBackgroundTask || lastBackgroundNoticeStepIndex == step.stepIndex - 1)

        if isFinalPlannerResponse && !isWaitingForFreshBackgroundTask && !pendingCommands.isEmpty {
            let settled = forceIdle(at: stepDate)
            output.updatedCommands.append(contentsOf: settled)
        }

        // 5. Transition high-level state
        if isFinalPlannerResponse && !isWaitingForFreshBackgroundTask {
            if let prevActive = activeThinkingStepIndex {
                output.completedThinkingStepIndex = prevActive
                activeThinkingStepIndex = nil
            }
            state = .idle
            isTurnActive = false
            burstEditedPaths.removeAll()
            hasPeekedMultiFileBurst = false
        } else if let compaction = output.compactionEvent {
            state = .compacting(compaction)
        } else if let activeCmd = pendingCommands.last {
            state = .runningCommand(activeCmd)
        } else if let latestFile = output.fileChanges.last {
            state = .editing(latestFile)
        } else if let latestInspection = output.fileInspections.last {
            state = .inspecting(latestInspection)
        } else if !trimmedThinking.isEmpty && !isFinalPlannerResponse {
            state = .thinking
        } else if !toolCalls.isEmpty {
            state = .thinking
        } else if step.type == "USER_INPUT" {
            state = .working(startedAt: stepDate)
        } else if commandJustFinished {
            // Command completed; return to `.thinking`/`.working` if the turn is still active, otherwise `.idle`
            if activeThinkingStepIndex != nil {
                state = .thinking
            } else if isTurnActive {
                state = .working(startedAt: stepDate)
            } else {
                state = .idle
            }
        } else if isTurnActive && step.type == "GENERIC" && step.status != "RUNNING" {
            // Preserve `.inspecting` / `.editing` right after their instant GENERIC DONE result so
            // the Notch actually displays `Analyzed File.swift #L...` / `File.swift +N -M` instead
            // of getting stomped in <1ms; for all other tool completions, transition to `.working`.
            switch state {
            case .inspecting, .editing:
                break
            default:
                state = .working(startedAt: stepDate)
            }
        } else if step.type == "PLANNER_RESPONSE" && step.status == "RUNNING" {
            state = .working(startedAt: stepDate)
        }

        output.state = state
        output.activeModel = activeModel
        output.tokenMetrics = tokenMetrics
        return output
    }

    // MARK: - Tool Call Classification

    private mutating func classifyToolCalls(
        _ toolCalls: [ToolCall],
        step: TranscriptStep,
        stepDate: Date,
        session: ConversationSession?,
        into output: inout EventClassificationOutput
    ) {
        var stepEditedPaths = Set<String>()

        for (index, call) in toolCalls.enumerated() {
            switch call.name {
            case "read_file", "view_file", "view_file_outline", "view_code_item":
                if let path = call.stringArg("Path", "AbsolutePath", "File", "TargetFile"), !path.isEmpty {
                    let event = FileInspectionEvent(
                        id: "\(step.stepIndex)-\(index)-\(path)",
                        stepIndex: step.stepIndex,
                        path: path,
                        startLine: call.intArg("StartLine"),
                        endLine: call.intArg("EndLine"),
                        timestamp: stepDate,
                        toolName: call.name
                    )
                    output.fileInspections.append(event)
                }

            case "edit_file", "replace_file_content":
                if let event = classifySingleEdit(call: call, stepIndex: step.stepIndex, callIndex: index, date: stepDate) {
                    output.fileChanges.append(event)
                    stepEditedPaths.insert(event.path)
                    burstEditedPaths.insert(event.path)
                }

            case "multi_replace_file_content":
                if let event = classifyMultiEdit(call: call, stepIndex: step.stepIndex, callIndex: index, date: stepDate) {
                    output.fileChanges.append(event)
                    stepEditedPaths.insert(event.path)
                    burstEditedPaths.insert(event.path)
                }

            case "write_file", "write_to_file":
                if let event = classifyWrite(call: call, stepIndex: step.stepIndex, callIndex: index, date: stepDate) {
                    output.fileChanges.append(event)
                    stepEditedPaths.insert(event.path)
                    burstEditedPaths.insert(event.path)
                }

            case "delete_file":
                if let path = call.stringArg("Path", "TargetFile"), !path.isEmpty {
                    let event = FileChangeEvent(
                        id: "\(step.stepIndex)-\(index)-\(path)",
                        stepIndex: step.stepIndex,
                        path: path,
                        kind: .delete,
                        addedLines: 0,
                        removedLines: 0,
                        diffHunks: [],
                        timestamp: stepDate,
                        toolName: call.name
                    )
                    output.fileChanges.append(event)
                    output.peekEvents.append(.fileDeleted(event.basename))
                }

            case "run_command":
                let commandLine = call.stringArg("CommandLine") ?? ""
                let deletedPaths = DestructiveCommandParser.extractDeletedPaths(from: commandLine)
                for (deleteIndex, deletedPath) in deletedPaths.enumerated() {
                    let event = FileChangeEvent(
                        id: "\(step.stepIndex)-\(index)-rm-\(deleteIndex)-\(deletedPath)",
                        stepIndex: step.stepIndex,
                        path: deletedPath,
                        kind: .delete,
                        addedLines: 0,
                        removedLines: 0,
                        diffHunks: [],
                        timestamp: stepDate,
                        toolName: call.name
                    )
                    output.fileChanges.append(event)
                    output.peekEvents.append(.fileDeleted(event.basename))
                }
                registerCommandStart(
                    call: call,
                    commandLine: commandLine,
                    stepIndex: step.stepIndex,
                    callIndex: index,
                    date: stepDate,
                    session: session,
                    into: &output
                )

            default:
                break
            }
        }

        if stepEditedPaths.count >= 2 || (burstEditedPaths.count >= 3 && !hasPeekedMultiFileBurst) {
            hasPeekedMultiFileBurst = true
            output.peekEvents.append(.multiFileEdit(max(stepEditedPaths.count, burstEditedPaths.count)))
        }
    }

    private func classifySingleEdit(
        call: ToolCall,
        stepIndex: Int,
        callIndex: Int,
        date: Date
    ) -> FileChangeEvent? {
        guard let path = call.stringArg("Path", "TargetFile"), !path.isEmpty else {
            return nil
        }
        let target = call.stringArg("Target", "TargetContent") ?? ""
        let replacement = call.stringArg("Replacement", "ReplacementContent") ?? ""
        let diff = DiffComputer.computeDiff(oldText: target, newText: replacement)

        return FileChangeEvent(
            id: "\(stepIndex)-\(callIndex)-\(path)",
            stepIndex: stepIndex,
            path: path,
            kind: .edit,
            addedLines: diff.addedLines,
            removedLines: diff.removedLines,
            diffHunks: diff.hunks,
            timestamp: date,
            toolName: call.name
        )
    }

    private func classifyMultiEdit(
        call: ToolCall,
        stepIndex: Int,
        callIndex: Int,
        date: Date
    ) -> FileChangeEvent? {
        guard let path = call.stringArg("Path", "TargetFile"), !path.isEmpty else {
            return nil
        }

        var chunks: [(target: String, replacement: String)] = []
        if let rawChunks = call.args?["ReplacementChunks"]?.unwrappedArray {
            for item in rawChunks {
                guard let dict = item.unwrappedObject else { continue }
                let target = dict["TargetContent"]?.unwrappedString
                    ?? dict["Target"]?.unwrappedString
                    ?? ""
                let replacement = dict["ReplacementContent"]?.unwrappedString
                    ?? dict["Replacement"]?.unwrappedString
                    ?? ""
                chunks.append((target: target, replacement: replacement))
            }
        }

        let diff = DiffComputer.computeMultiChunkDiff(chunks: chunks)
        return FileChangeEvent(
            id: "\(stepIndex)-\(callIndex)-\(path)",
            stepIndex: stepIndex,
            path: path,
            kind: .edit,
            addedLines: diff.addedLines,
            removedLines: diff.removedLines,
            diffHunks: diff.hunks,
            timestamp: date,
            toolName: call.name
        )
    }

    private func classifyWrite(
        call: ToolCall,
        stepIndex: Int,
        callIndex: Int,
        date: Date
    ) -> FileChangeEvent? {
        guard let path = call.stringArg("Path", "TargetFile"), !path.isEmpty else {
            return nil
        }
        let content = call.stringArg("Content", "CodeContent") ?? ""
        let isOverwrite = call.boolArg("Overwrite") ?? false
        let isAppend = call.boolArg("Append") ?? false

        let kind: FileChangeKind
        if isAppend {
            kind = .edit
        } else if isOverwrite {
            kind = .overwrite
        } else {
            kind = .create
        }

        let diff = DiffComputer.computeWriteDiff(content: content)
        return FileChangeEvent(
            id: "\(stepIndex)-\(callIndex)-\(path)",
            stepIndex: stepIndex,
            path: path,
            kind: kind,
            addedLines: diff.addedLines,
            removedLines: 0,
            diffHunks: diff.hunks,
            timestamp: date,
            toolName: call.name
        )
    }

    internal mutating func registerCommandStart(
        call: ToolCall,
        commandLine: String,
        stepIndex: Int,
        callIndex: Int,
        date: Date,
        session: ConversationSession?,
        into output: inout EventClassificationOutput
    ) {
        let summary = call.stringArg("toolSummary") ?? ""
        // Antigravity names live task logs after the immediately following GENERIC tool-result step
        // (`task-<plannerStepIndex + 1 + callIndex>.log`), with fallback updated on correlation.
        let candidateTaskLogURL = session?.tasksDirectoryURL
            .appendingPathComponent("task-\(stepIndex + 1 + callIndex).log")

        let event = CommandExecutionEvent(
            id: "\(stepIndex)-\(callIndex)",
            stepIndex: stepIndex,
            resultStepIndex: nil,
            commandLine: commandLine,
            summary: summary,
            status: .running,
            exitCode: nil,
            startedAt: date,
            completedAt: nil,
            logOutput: "",
            isTruncated: false,
            taskLogURL: candidateTaskLogURL,
            stepOutputURL: nil
        )
        pendingCommands.append(event)
        output.startedCommands.append(event)
    }

    /// Recomputes full untruncated `FileChangeEvent`s for a `PLANNER_RESPONSE` step loaded from
    /// `transcript_full.jsonl` when `transcript.jsonl` had `truncated_fields: ["tool_calls"]`.
    public static func extractFileChanges(from fullStep: TranscriptStep) -> [FileChangeEvent] {
        guard let toolCalls = fullStep.toolCalls, !toolCalls.isEmpty else { return [] }
        var temp = EventClassifier()
        var output = EventClassificationOutput()
        temp.classifyToolCalls(
            toolCalls,
            step: fullStep,
            stepDate: fullStep.parsedDate,
            session: nil,
            into: &output
        )
        return output.fileChanges
    }

    // MARK: - File Edit Result Correlation (Authoritative Antigravity `+N/-M` Counts)

    /// Correlates Antigravity's `GENERIC` edit_file result summary
    /// (e.g. `Made 1 replacement in /path/File.swift starting at line 1043 (+29/-29 lines).`)
    /// back onto the matching pending `FileChangeEvent` so line diff metrics match Antigravity 1:1
    /// even when compact `transcript.jsonl` truncated `tool_calls`.
    private mutating func correlateFileEditResult(
        step: TranscriptStep,
        into output: inout EventClassificationOutput
    ) {
        guard let content = step.content, !content.isEmpty else { return }
        guard let parsed = Self.extractFileEditDiffSummary(from: content) else { return }

        let matchIndex = pendingFileChanges.firstIndex { event in
            event.path == parsed.path || URL(fileURLWithPath: event.path).lastPathComponent == URL(fileURLWithPath: parsed.path).lastPathComponent
        }
        guard let idx = matchIndex else { return }

        var matched = pendingFileChanges.remove(at: idx)
        matched.addedLines = parsed.added
        matched.removedLines = parsed.removed
        output.fileChanges.append(matched)
    }

    /// Extracts `(path, added, removed)` from Antigravity's authoritative `edit_file` result message:
    /// `Made N replacement(s) in <path> starting at line <L> (+<A>/-<R> lines).`
    public static func extractFileEditDiffSummary(from content: String) -> (path: String, added: Int, removed: Int)? {
        let pattern = #"Made\s+\d+\s+replacements?\s+in\s+(.+?)\s+starting\s+at\s+line\s+\d+\s+\(\+(\d+)/-(\d+)\s+lines?\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let ns = content as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: content, options: [], range: range),
              match.numberOfRanges >= 4
        else {
            return nil
        }
        let path = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let added = Int(ns.substring(with: match.range(at: 2))),
              let removed = Int(ns.substring(with: match.range(at: 3)))
        else {
            return nil
        }
        return (path, added, removed)
    }

    // MARK: - Command Result Correlation

    private mutating func correlateCommandResult(
        step: TranscriptStep,
        stepDate: Date,
        session: ConversationSession?,
        into output: inout EventClassificationOutput
    ) -> Bool {
        guard let content = step.content, !content.isEmpty else {
            return false
        }

        let exitCode = Self.extractExitCode(from: content)
        let extractedTaskLogURL = Self.extractTaskLogURL(from: content, session: session)
        let extractedStepOutputURL = Self.extractStepOutputURL(from: content, stepIndex: step.stepIndex, session: session)
        let isRunningNotice = Self.looksLikeRunningCommandNotice(content) || step.status == "RUNNING"
        let hasCommandOutputHeader = content.contains("Command output:") || content.contains("No output from command")
        let isTruncatedToolOutput = content.localizedCaseInsensitiveContains("output was truncated")
            && extractedStepOutputURL != nil
        let isAbortedOrError = step.status == "ERROR" || step.status == "CANCELLED" || step.status == "ABORTED"

        // Only match steps that actually represent command output / exit / task status / truncated command output
        guard exitCode != nil
            || extractedTaskLogURL != nil
            || isRunningNotice
            || hasCommandOutputHeader
            || isTruncatedToolOutput
            || (isAbortedOrError && step.type == "GENERIC")
        else {
            return false
        }

        // Prefer matching by task log filename if present, otherwise oldest pending command with stepIndex < step.stepIndex
        let matchIndex: Int?
        if let taskLogURL = extractedTaskLogURL,
           let byTaskLog = pendingCommands.firstIndex(where: { $0.taskLogURL?.lastPathComponent == taskLogURL.lastPathComponent })
        {
            matchIndex = byTaskLog
        } else {
            matchIndex = pendingCommands.firstIndex(where: { $0.stepIndex < step.stepIndex })
        }

        guard let idx = matchIndex else {
            return false
        }

        let existing = pendingCommands[idx]
        let cleanedOutput = Self.extractCleanCommandOutput(from: content)
        let mergedLog = cleanedOutput.isEmpty ? existing.logOutput : cleanedOutput
        let isTruncated = existing.isTruncated
            || step.isFieldTruncated("content")
            || content.localizedCaseInsensitiveContains("output was truncated")
        let resolvedTaskLogURL = extractedTaskLogURL ?? existing.taskLogURL
        let resolvedStepOutputURL = extractedStepOutputURL ?? existing.stepOutputURL

        let isCompletedWithoutInlineExitCode = !isRunningNotice
            && step.status != "RUNNING"
            && (isTruncatedToolOutput
                || isAbortedOrError
                || (step.status == "DONE" && hasCommandOutputHeader))

        if let code = exitCode {
            let status: CommandStatus = (code == 0) ? .succeeded : .failed
            let completedAt = Self.extractCompletedDate(from: content) ?? stepDate
            let completedEvent = CommandExecutionEvent(
                id: existing.id,
                stepIndex: existing.stepIndex,
                resultStepIndex: step.stepIndex,
                commandLine: existing.commandLine,
                summary: existing.summary,
                status: status,
                exitCode: code,
                startedAt: existing.startedAt,
                completedAt: completedAt,
                logOutput: mergedLog,
                isTruncated: isTruncated,
                taskLogURL: resolvedTaskLogURL,
                stepOutputURL: resolvedStepOutputURL
            )

            pendingCommands.remove(at: idx)
            confirmedBackgroundCommandIDs.remove(existing.id)
            output.updatedCommands.append(completedEvent)

            if code == 0 {
                output.peekEvents.append(.commandCompleted(completedEvent.displayTitle, code))
            } else {
                output.peekEvents.append(.commandFailed(completedEvent.displayTitle, code))
            }
            return true
        }

        if isCompletedWithoutInlineExitCode {
            let status: CommandStatus = isAbortedOrError ? .failed : .succeeded
            let completedAt = Self.extractCompletedDate(from: content) ?? stepDate
            let completedEvent = CommandExecutionEvent(
                id: existing.id,
                stepIndex: existing.stepIndex,
                resultStepIndex: step.stepIndex,
                commandLine: existing.commandLine,
                summary: existing.summary,
                status: status,
                exitCode: isAbortedOrError ? 1 : nil,
                startedAt: existing.startedAt,
                completedAt: completedAt,
                logOutput: isTruncatedToolOutput ? existing.logOutput : mergedLog,
                isTruncated: isTruncated,
                taskLogURL: resolvedTaskLogURL,
                stepOutputURL: resolvedStepOutputURL
            )

            pendingCommands.remove(at: idx)
            confirmedBackgroundCommandIDs.remove(existing.id)
            output.updatedCommands.append(completedEvent)
            if status == .failed {
                output.peekEvents.append(.commandFailed(completedEvent.displayTitle, 1))
            }
            return true
        }

        // Still running (e.g., backgrounded with a `task-<id>.log` reference)
        if isRunningNotice {
            lastBackgroundNoticeStepIndex = step.stepIndex
            confirmedBackgroundCommandIDs.insert(existing.id)
        }
        let runningEvent = CommandExecutionEvent(
            id: existing.id,
            stepIndex: existing.stepIndex,
            resultStepIndex: existing.resultStepIndex ?? step.stepIndex,
            commandLine: existing.commandLine,
            summary: existing.summary,
            status: .running,
            exitCode: nil,
            startedAt: existing.startedAt,
            completedAt: nil,
            logOutput: mergedLog,
            isTruncated: isTruncated,
            taskLogURL: resolvedTaskLogURL,
            stepOutputURL: resolvedStepOutputURL
        )
        pendingCommands[idx] = runningEvent
        output.updatedCommands.append(runningEvent)
        return false
    }

    // MARK: - Command Output Parsers

    public static func extractExitCode(from content: String) -> Int? {
        let patterns = [
            #"Command exited with code\s+(-?\d+)"#,
            #"exited with (?:code|status)\s+(-?\d+)"#,
            #"Exit code:\s*(-?\d+)"#,
        ]

        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: content, options: [], range: fullRange),
                  match.numberOfRanges >= 2
            else {
                continue
            }
            let codeString = nsContent.substring(with: match.range(at: 1))
            if let code = Int(codeString) {
                return code
            }
        }
        return nil
    }

    public static func extractTaskLogURL(from content: String, session: ConversationSession?) -> URL? {
        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)

        // Check for full path first (e.g., `/.../tasks/task-12.log` or `file:///.../tasks/task-12.log`)
        if let fullPathRegex = try? NSRegularExpression(
            pattern: #"(?:file://)?(/[^\s"'`<>]+/tasks/task-[A-Za-z0-9._-]+\.log)"#,
            options: []
        ),
           let match = fullPathRegex.firstMatch(in: content, options: [], range: fullRange),
           match.numberOfRanges >= 2
        {
            let path = nsContent.substring(with: match.range(at: 1))
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:)]}"))
            return URL(fileURLWithPath: path)
        }

        // Check for relative `task-<id>.log` filename
        if let nameRegex = try? NSRegularExpression(
            pattern: #"\b(task-[A-Za-z0-9._-]+\.log)\b"#,
            options: []
        ),
           let match = nameRegex.firstMatch(in: content, options: [], range: fullRange),
           match.numberOfRanges >= 2
        {
            let filename = nsContent.substring(with: match.range(at: 1))
            if let session {
                return session.tasksDirectoryURL.appendingPathComponent(filename)
            }
            return URL(fileURLWithPath: filename)
        }

        // Check for Antigravity task identifier without `.log` suffix (e.g. `sender=<uuid>/task-561` or `task id: <uuid>/task-561`)
        if let idRegex = try? NSRegularExpression(
            pattern: #"/(task-[A-Za-z0-9._-]+)(?=["'\s,.;:)]|$)"#,
            options: []
        ),
           let match = idRegex.firstMatch(in: content, options: [], range: fullRange),
           match.numberOfRanges >= 2
        {
            let taskName = nsContent.substring(with: match.range(at: 1))
            let filename = taskName.hasSuffix(".log") ? taskName : "\(taskName).log"
            if let session {
                return session.tasksDirectoryURL.appendingPathComponent(filename)
            }
            return URL(fileURLWithPath: filename)
        }

        return nil
    }

    public static func extractStepOutputURL(
        from content: String,
        stepIndex: Int,
        session: ConversationSession?
    ) -> URL? {
        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)

        if let regex = try? NSRegularExpression(
            pattern: #"(?:file://)?(/[^\s"'`<>]+/\.system_generated/steps/\d+/output\.txt)"#,
            options: []
        ),
           let match = regex.firstMatch(in: content, options: [], range: fullRange),
           match.numberOfRanges >= 2
        {
            let path = nsContent.substring(with: match.range(at: 1))
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:)]}"))
            return URL(fileURLWithPath: path)
        }

        if let session {
            let candidate = session.stepsDirectoryURL
                .appendingPathComponent("\(stepIndex)", isDirectory: true)
                .appendingPathComponent("output.txt")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    public static func extractCompletedDate(from content: String) -> Date? {
        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        guard let regex = try? NSRegularExpression(
            pattern: #"Completed At:\s*([^\s\r\n]+)"#,
            options: []
        ),
              let match = regex.firstMatch(in: content, options: [], range: fullRange),
              match.numberOfRanges >= 2
        else {
            return nil
        }
        let dateString = nsContent.substring(with: match.range(at: 1))
        return TranscriptDateParser.parse(dateString)
    }

    public static func extractCleanCommandOutput(from content: String) -> String {
        let stripped = ANSIStripper.strip(content)
        if let markerRange = stripped.range(of: "Command output:\n") {
            return String(stripped[markerRange.upperBound...])
                .trimmingCharacters(in: .newlines)
        }

        // Filter standard Antigravity metadata headers when no explicit `Command output:` header exists
        let lines = stripped.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let filtered = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Created At:") { return false }
            if trimmed.hasPrefix("Completed At:") { return false }
            if trimmed.hasPrefix("Command exited with code ") { return false }
            return true
        }
        return filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func extractCleanUserPrompt(from raw: String) -> String {
        var text = raw
        if let start = text.range(of: "<USER_REQUEST>"),
           let end = text.range(of: "</USER_REQUEST>", range: start.upperBound..<text.endIndex)
        {
            text = String(text[start.upperBound..<end.lowerBound])
        } else if let meta = text.range(of: "<ADDITIONAL_METADATA>") {
            text = String(text[..<meta.lowerBound])
        }
        return text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeRunningCommandNotice(_ content: String) -> Bool {
        let lowered = content.lowercased()
        return lowered.contains("still running")
            || lowered.contains("running in the background")
            || lowered.contains("background task")
            || lowered.contains("command is running")
    }
}
