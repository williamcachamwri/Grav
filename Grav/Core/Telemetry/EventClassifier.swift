import Foundation

/// Incremental output emitted by `EventClassifier` for each processed `TranscriptStep`.
public struct EventClassificationOutput: Sendable, Equatable {
    public var state: TelemetryState
    public var activeModel: String?
    public var tokenMetrics: TokenMetrics
    public var thinkingSnapshot: ThinkingSnapshot?
    public var completedThinkingStepIndex: Int?
    public var fileChanges: [FileChangeEvent]
    public var startedCommands: [CommandExecutionEvent]
    public var updatedCommands: [CommandExecutionEvent]
    public var peekEvents: [NotchPeekEvent]

    public init(
        state: TelemetryState = .idle,
        activeModel: String? = nil,
        tokenMetrics: TokenMetrics = TokenMetrics(),
        thinkingSnapshot: ThinkingSnapshot? = nil,
        completedThinkingStepIndex: Int? = nil,
        fileChanges: [FileChangeEvent] = [],
        startedCommands: [CommandExecutionEvent] = [],
        updatedCommands: [CommandExecutionEvent] = [],
        peekEvents: [NotchPeekEvent] = []
    ) {
        self.state = state
        self.activeModel = activeModel
        self.tokenMetrics = tokenMetrics
        self.thinkingSnapshot = thinkingSnapshot
        self.completedThinkingStepIndex = completedThinkingStepIndex
        self.fileChanges = fileChanges
        self.startedCommands = startedCommands
        self.updatedCommands = updatedCommands
        self.peekEvents = peekEvents
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

    internal var processedTokenStepIndices: Set<Int> = []
    internal var burstEditedPaths: Set<String> = []
    internal var hasPeekedMultiFileBurst: Bool = false

    public init() {}

    /// Resets all accumulated session classification state (e.g., when switching active sessions).
    public mutating func reset() {
        state = .idle
        activeModel = nil
        tokenMetrics = TokenMetrics()
        activeThinkingStepIndex = nil
        pendingCommands.removeAll()
        processedTokenStepIndices.removeAll()
        burstEditedPaths.removeAll()
        hasPeekedMultiFileBurst = false
    }

    /// Marks the telemetry state as `.idle` (for example after an idle decay timeout) and clears
    /// transient burst counters.
    public mutating func markIdle() {
        if pendingCommands.isEmpty {
            state = .idle
            activeThinkingStepIndex = nil
            burstEditedPaths.removeAll()
            hasPeekedMultiFileBurst = false
        }
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

        // 2. Classify thinking stream updates
        let trimmedThinking = step.thinking?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let toolCalls = step.toolCalls ?? []
        let isFinalPlannerResponse = step.type == "PLANNER_RESPONSE"
            && toolCalls.isEmpty
            && step.status == "DONE"

        if !trimmedThinking.isEmpty {
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
            // A fresh user prompt resets multi-file burst tracking and wakes from idle
            burstEditedPaths.removeAll()
            hasPeekedMultiFileBurst = false
            if let prevActive = activeThinkingStepIndex {
                output.completedThinkingStepIndex = prevActive
                activeThinkingStepIndex = nil
            }
        }

        // 3. Classify tool calls (file edits, creates, overwrites, deletes, and shell commands)
        if !toolCalls.isEmpty {
            classifyToolCalls(
                toolCalls,
                step: step,
                stepDate: stepDate,
                session: session,
                into: &output
            )
        }

        // 4. Transition high-level state
        if let activeCmd = pendingCommands.last {
            state = .runningCommand(activeCmd)
        } else if let latestFile = output.fileChanges.last {
            state = .editing(latestFile)
        } else if !trimmedThinking.isEmpty && !isFinalPlannerResponse {
            state = .thinking
        } else if !toolCalls.isEmpty {
            state = .thinking
        } else if isFinalPlannerResponse {
            if let prevActive = activeThinkingStepIndex {
                output.completedThinkingStepIndex = prevActive
                activeThinkingStepIndex = nil
            }
            state = .idle
            burstEditedPaths.removeAll()
            hasPeekedMultiFileBurst = false
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
        let candidateTaskLogURL = session?.tasksDirectoryURL
            .appendingPathComponent("task-\(stepIndex).log")

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
}
