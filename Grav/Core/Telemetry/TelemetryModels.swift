import Foundation

// MARK: - Raw Antigravity Transcript Schema

/// Defensive Codable representation of a single JSONL line from
/// `~/.gemini/antigravity/brain/<uuid>/.system_generated/logs/transcript.jsonl`.
public struct TranscriptStep: Sendable, Equatable, Codable {
    public let stepIndex: Int
    public let source: String?
    public let type: String?
    public let status: String?
    public let createdAt: String?
    public let model: String?
    public let inputTokens: Int?
    public let cacheReadTokens: Int?
    public let outputTokens: Int?
    public let thinking: String?
    public let content: String?
    public let toolCalls: [ToolCall]?
    public let truncatedFields: [String]?

    enum CodingKeys: String, CodingKey {
        case stepIndex = "step_index"
        case source
        case type
        case status
        case createdAt = "created_at"
        case model
        case inputTokens = "input_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case outputTokens = "output_tokens"
        case thinking
        case content
        case toolCalls = "tool_calls"
        case truncatedFields = "truncated_fields"
    }

    public init(
        stepIndex: Int,
        source: String? = nil,
        type: String? = nil,
        status: String? = nil,
        createdAt: String? = nil,
        model: String? = nil,
        inputTokens: Int? = nil,
        cacheReadTokens: Int? = nil,
        outputTokens: Int? = nil,
        thinking: String? = nil,
        content: String? = nil,
        toolCalls: [ToolCall]? = nil,
        truncatedFields: [String]? = nil
    ) {
        self.stepIndex = stepIndex
        self.source = source
        self.type = type
        self.status = status
        self.createdAt = createdAt
        self.model = model
        self.inputTokens = inputTokens
        self.cacheReadTokens = cacheReadTokens
        self.outputTokens = outputTokens
        self.thinking = thinking
        self.content = content
        self.toolCalls = toolCalls
        self.truncatedFields = truncatedFields
    }

    public var parsedDate: Date {
        guard let createdAt else { return Date() }
        return TranscriptDateParser.parse(createdAt) ?? Date()
    }

    public func isFieldTruncated(_ field: String) -> Bool {
        truncatedFields?.contains(field) ?? false
    }
}

public struct ToolCall: Sendable, Equatable, Codable {
    public let name: String
    public let args: [String: JSONValue]?

    public init(name: String, args: [String: JSONValue]? = nil) {
        self.name = name
        self.args = args
    }

    public func stringArg(_ keys: String...) -> String? {
        guard let args else { return nil }
        for key in keys {
            if let value = args[key]?.unwrappedString {
                return value
            }
        }
        return nil
    }

    public func boolArg(_ keys: String...) -> Bool? {
        guard let args else { return nil }
        for key in keys {
            if let value = args[key]?.unwrappedBool {
                return value
            }
        }
        return nil
    }

    public func intArg(_ keys: String...) -> Int? {
        guard let args else { return nil }
        for key in keys {
            if let value = args[key]?.unwrappedInt {
                return value
            }
            if let rawStr = args[key]?.unwrappedString, let parsed = Int(rawStr) {
                return parsed
            }
        }
        return nil
    }
}

/// Thread-safe ISO 8601 parser supporting fractional and whole seconds.
public enum TranscriptDateParser {
    public static func parse(_ string: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) {
            return date
        }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: string)
    }
}

// MARK: - Conversation & Session Telemetry

public struct ConversationSession: Sendable, Equatable, Identifiable {
    public let id: String
    public let directoryURL: URL
    public let transcriptURL: URL
    public let fullTranscriptURL: URL
    public let tasksDirectoryURL: URL
    public let stepsDirectoryURL: URL
    public var title: String
    public var lastModified: Date

    public init(
        id: String,
        directoryURL: URL,
        title: String? = nil,
        lastModified: Date = Date()
    ) {
        self.id = id
        self.directoryURL = directoryURL
        let systemDir = directoryURL.appendingPathComponent(".system_generated", isDirectory: true)
        let logsDir = systemDir.appendingPathComponent("logs", isDirectory: true)
        self.transcriptURL = logsDir.appendingPathComponent("transcript.jsonl")
        self.fullTranscriptURL = logsDir.appendingPathComponent("transcript_full.jsonl")
        self.tasksDirectoryURL = systemDir.appendingPathComponent("tasks", isDirectory: true)
        self.stepsDirectoryURL = systemDir.appendingPathComponent("steps", isDirectory: true)
        self.title = title ?? String(id.prefix(8))
        self.lastModified = lastModified
    }
}

public enum AntigravityExecutionMode: String, Sendable, Equatable {
    case requestReview = "Request Review"
    case defaultMode = "Default"
    case auto = "Auto"
    case turbo = "Turbo"

    public var isTurbo: Bool {
        self == .turbo
    }

    public static func parse(fromAnnotationText text: String) -> AntigravityExecutionMode {
        if text.contains("AGENT_PERMISSION_PRESET_TURBO") {
            return .turbo
        }
        if text.contains("AGENT_PERMISSION_PRESET_AUTO") {
            return .auto
        }
        if text.contains("AGENT_PERMISSION_PRESET_REQUEST_REVIEW")
            || text.contains("AGENT_PERMISSION_PRESET_STRICT")
        {
            return .requestReview
        }
        return .defaultMode
    }
}

public struct ConversationAnnotation: Sendable, Equatable {
    public var title: String?
    public var executionMode: AntigravityExecutionMode

    public init(title: String? = nil, executionMode: AntigravityExecutionMode = .defaultMode) {
        self.title = title
        self.executionMode = executionMode
    }

    /// Parses `~/.gemini/antigravity/annotations/<session-id>.pbtxt` cleanly.
    public static func parse(pbtxt: String) -> ConversationAnnotation {
        let mode = AntigravityExecutionMode.parse(fromAnnotationText: pbtxt)
        var parsedTitle: String?
        if let titleRange = pbtxt.range(of: #"title:"([^"\\]*(?:\\.[^"\\]*)*)""#, options: .regularExpression) {
            let matched = String(pbtxt[titleRange])
            if let firstQuote = matched.firstIndex(of: "\""),
               let lastQuote = matched.lastIndex(of: "\""),
               firstQuote < lastQuote
            {
                let inner = String(matched[matched.index(after: firstQuote)..<lastQuote])
                    .replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\\\", with: "\\")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !inner.isEmpty {
                    parsedTitle = inner
                }
            }
        }
        return ConversationAnnotation(title: parsedTitle, executionMode: mode)
    }
}

public struct TokenMetrics: Sendable, Equatable {
    public var inputTokens: Int
    public var cacheReadTokens: Int
    public var outputTokens: Int
    /// Live context window fill from the most recent `PLANNER_RESPONSE` (`input + cacheRead`).
    public var latestContextTokens: Int
    /// Model context window capacity (1M tokens for Gemini 4 / Pro / Flash series).
    public var contextWindowLimit: Int
    /// Most recent measured output generation throughput in tokens/second.
    public var lastTurnTokensPerSecond: Double?
    /// Session rolling average output throughput in tokens/second.
    public var averageTokensPerSecond: Double?

    public init(
        inputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        outputTokens: Int = 0,
        latestContextTokens: Int = 0,
        contextWindowLimit: Int = 1_000_000,
        lastTurnTokensPerSecond: Double? = nil,
        averageTokensPerSecond: Double? = nil
    ) {
        self.inputTokens = inputTokens
        self.cacheReadTokens = cacheReadTokens
        self.outputTokens = outputTokens
        self.latestContextTokens = latestContextTokens
        self.contextWindowLimit = max(1, contextWindowLimit)
        self.lastTurnTokensPerSecond = lastTurnTokensPerSecond
        self.averageTokensPerSecond = averageTokensPerSecond
    }

    public var totalTokens: Int {
        inputTokens + cacheReadTokens + outputTokens
    }

    public var cacheHitRate: Double {
        let totalIn = inputTokens + cacheReadTokens
        guard totalIn > 0 else { return 0 }
        return Double(cacheReadTokens) / Double(totalIn)
    }

    public var contextFillRatio: Double {
        guard contextWindowLimit > 0 else { return 0 }
        return min(1.0, max(0.0, Double(latestContextTokens) / Double(contextWindowLimit)))
    }

    /// True when the active context window is nearing Antigravity's automatic compaction threshold.
    public var isContextNearCompaction: Bool {
        contextFillRatio >= 0.78
    }

    public static func inferredContextLimit(for model: String?) -> Int {
        guard let lower = model?.lowercased() else { return 1_000_000 }
        if lower.contains("claude") { return 200_000 }
        if lower.contains("gpt-4o") || lower.contains("o1") || lower.contains("o3") { return 200_000 }
        return 1_000_000
    }

    public static func formatCompact(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000.0)
        }
        return "\(count)"
    }
}

// MARK: - Thinking Stream

public struct ThinkingSnapshot: Sendable, Equatable, Identifiable {
    public var id: Int { stepIndex }
    public let stepIndex: Int
    public var text: String
    public var isTruncated: Bool
    public var isFullTextLoaded: Bool
    public var model: String?
    public let startedAt: Date
    public var completedAt: Date?
    public var isActive: Bool

    public init(
        stepIndex: Int,
        text: String,
        isTruncated: Bool = false,
        isFullTextLoaded: Bool = false,
        model: String? = nil,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        isActive: Bool = true
    ) {
        self.stepIndex = stepIndex
        self.text = text
        self.isTruncated = isTruncated
        self.isFullTextLoaded = isFullTextLoaded
        self.model = model
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.isActive = isActive
    }

    public var elapsedSeconds: TimeInterval {
        let end = completedAt ?? Date()
        return max(0, end.timeIntervalSince(startedAt))
    }
}

// MARK: - AI Assistant Response Stream

public struct AssistantResponseSnapshot: Sendable, Equatable, Identifiable {
    public var id: Int { stepIndex }
    public let stepIndex: Int
    public var promptPreview: String?
    public var text: String
    public var isTruncated: Bool
    public var isFullTextLoaded: Bool
    public var model: String?
    public let timestamp: Date
    public var isStreaming: Bool

    public init(
        stepIndex: Int,
        promptPreview: String? = nil,
        text: String,
        isTruncated: Bool = false,
        isFullTextLoaded: Bool = false,
        model: String? = nil,
        timestamp: Date = Date(),
        isStreaming: Bool = false
    ) {
        self.stepIndex = stepIndex
        self.promptPreview = promptPreview
        self.text = text
        self.isTruncated = isTruncated
        self.isFullTextLoaded = isFullTextLoaded
        self.model = model
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }
}

// MARK: - File Changes & Mini-Diffs

public enum FileChangeKind: String, Sendable, Equatable {
    case edit
    case create
    case overwrite
    case delete
}

public struct FileDiffLine: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Equatable {
        case context
        case added
        case removed
    }

    public let id: Int
    public let kind: Kind
    public let text: String

    public init(id: Int, kind: Kind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

public struct FileDiffHunk: Sendable, Equatable, Identifiable {
    public let id: Int
    public let lines: [FileDiffLine]
    public let addedCount: Int
    public let removedCount: Int

    public init(id: Int = 0, lines: [FileDiffLine], addedCount: Int, removedCount: Int) {
        self.id = id
        self.lines = lines
        self.addedCount = addedCount
        self.removedCount = removedCount
    }
}

public struct FileChangeEvent: Sendable, Equatable, Identifiable {
    public let id: String
    public let stepIndex: Int
    public let path: String
    public let basename: String
    public let kind: FileChangeKind
    public var addedLines: Int
    public var removedLines: Int
    public var diffHunks: [FileDiffHunk]
    public let timestamp: Date
    public let toolName: String

    public init(
        id: String,
        stepIndex: Int,
        path: String,
        kind: FileChangeKind,
        addedLines: Int,
        removedLines: Int,
        diffHunks: [FileDiffHunk] = [],
        timestamp: Date = Date(),
        toolName: String
    ) {
        self.id = id
        self.stepIndex = stepIndex
        self.path = path
        self.basename = URL(fileURLWithPath: path).lastPathComponent
        self.kind = kind
        self.addedLines = addedLines
        self.removedLines = removedLines
        self.diffHunks = diffHunks
        self.timestamp = timestamp
        self.toolName = toolName
    }
}

// MARK: - Command Executions & Streaming Logs

public enum CommandStatus: String, Sendable, Equatable {
    case running
    case succeeded
    case failed
}

public struct CommandExecutionEvent: Sendable, Equatable, Identifiable {
    public let id: String
    public let stepIndex: Int
    public let resultStepIndex: Int?
    public let commandLine: String
    public let summary: String
    public var status: CommandStatus
    public var exitCode: Int?
    public let startedAt: Date
    public var completedAt: Date?
    public var logOutput: String
    public var isTruncated: Bool
    public var taskLogURL: URL?
    public var stepOutputURL: URL?

    public init(
        id: String,
        stepIndex: Int,
        resultStepIndex: Int? = nil,
        commandLine: String,
        summary: String,
        status: CommandStatus = .running,
        exitCode: Int? = nil,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        logOutput: String = "",
        isTruncated: Bool = false,
        taskLogURL: URL? = nil,
        stepOutputURL: URL? = nil
    ) {
        self.id = id
        self.stepIndex = stepIndex
        self.resultStepIndex = resultStepIndex
        self.commandLine = commandLine
        self.summary = summary
        self.status = status
        self.exitCode = exitCode
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.logOutput = logOutput
        self.isTruncated = isTruncated
        self.taskLogURL = taskLogURL
        self.stepOutputURL = stepOutputURL
    }

    public var displayTitle: String {
        if !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return summary
        }
        return commandLine
    }

    public var elapsedSeconds: TimeInterval {
        let end = completedAt ?? Date()
        return max(0, end.timeIntervalSince(startedAt))
    }
}

// MARK: - File Analysis / Inspection Events (`read_file`, `view_file`, etc.)

public struct FileInspectionEvent: Sendable, Equatable, Identifiable {
    public let id: String
    public let stepIndex: Int
    public let path: String
    public let startLine: Int?
    public let endLine: Int?
    public let timestamp: Date
    public let toolName: String

    public init(
        id: String,
        stepIndex: Int,
        path: String,
        startLine: Int? = nil,
        endLine: Int? = nil,
        timestamp: Date = Date(),
        toolName: String = "read_file"
    ) {
        self.id = id
        self.stepIndex = stepIndex
        self.path = path
        self.startLine = startLine
        self.endLine = endLine
        self.timestamp = timestamp
        self.toolName = toolName
    }

    public var basename: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    /// Formats line range matching Antigravity's exact `#L480-810` convention.
    public var lineRangeLabel: String? {
        switch (startLine, endLine) {
        case let (s?, e?) where s > 0 && e >= s:
            return s == e ? "#L\(s)" : "#L\(s)-\(e)"
        case let (s?, nil) where s > 0:
            return "#L\(s)"
        case let (nil, e?) where e > 0:
            return "#L1-\(e)"
        default:
            return nil
        }
    }
}

// MARK: - Context Compaction Events (`CHECKPOINT`)

public struct CompactionEvent: Sendable, Equatable, Identifiable {
    public let id: String
    public let stepIndex: Int
    public let startedAt: Date
    public var completedAt: Date?
    public var isActive: Bool

    public init(
        id: String? = nil,
        stepIndex: Int,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        isActive: Bool = true
    ) {
        self.id = id ?? "compact-\(stepIndex)"
        self.stepIndex = stepIndex
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.isActive = isActive
    }
}

// MARK: - Live Agent Steps Checklist (`update_steps`) & Tool Activity Events

public enum AgentStepStatus: String, Sendable, Equatable, Codable {
    case pending
    case inProgress = "in_progress"
    case done
    case skipped
    case failed
}

public struct AgentStepItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let index: Int
    public let title: String
    public let status: AgentStepStatus

    public init(index: Int, title: String, status: AgentStepStatus) {
        self.id = "step-\(index)-\(title)"
        self.index = index
        self.title = title
        self.status = status
    }
}

public struct AgentStepsProgress: Sendable, Equatable {
    public let stepIndex: Int
    public let updatedAt: Date
    public let steps: [AgentStepItem]

    public init(stepIndex: Int, updatedAt: Date = Date(), steps: [AgentStepItem]) {
        self.stepIndex = stepIndex
        self.updatedAt = updatedAt
        self.steps = steps
    }

    public var completedCount: Int {
        steps.filter { $0.status == .done }.count
    }

    public var totalCount: Int {
        steps.count
    }

    public var fraction: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    public var activeStep: AgentStepItem? {
        steps.first { $0.status == .inProgress }
    }

    public var isAllDone: Bool {
        totalCount > 0 && steps.allSatisfy { $0.status == .done || $0.status == .skipped }
    }

    public var ratioLabel: String {
        "\(completedCount)/\(totalCount) steps"
    }
}

public enum AgentToolActivityKind: String, Sendable, Equatable {
    case searchWeb
    case mcpTool
    case browser
    case imageGeneration
    case subagent
    case workflow
    case schedule
    case marketplace
    case waitingForInput
    case genericTool

    public var symbolName: String {
        switch self {
        case .searchWeb: return "globe"
        case .mcpTool: return "puzzlepiece.extension"
        case .browser: return "safari"
        case .imageGeneration: return "wand.and.stars"
        case .subagent: return "person.2.wave.2"
        case .workflow: return "flowchart"
        case .schedule: return "clock.badge.checkmark"
        case .marketplace: return "bag"
        case .waitingForInput: return "questionmark.bubble"
        case .genericTool: return "wrench.and.screwdriver"
        }
    }

    public var shortLabel: String {
        switch self {
        case .searchWeb: return "Searching"
        case .mcpTool: return "MCP Tool"
        case .browser: return "Browsing"
        case .imageGeneration: return "Generating"
        case .subagent: return "Subagent"
        case .workflow: return "Workflow"
        case .schedule: return "Schedule"
        case .marketplace: return "Marketplace"
        case .waitingForInput: return "Waiting"
        case .genericTool: return "Tool"
        }
    }
}

public struct AgentToolActivityEvent: Sendable, Equatable, Identifiable {
    public let id: String
    public let stepIndex: Int
    public let kind: AgentToolActivityKind
    public let toolName: String
    public let title: String
    public let detail: String?
    public let timestamp: Date

    public init(
        id: String,
        stepIndex: Int,
        kind: AgentToolActivityKind,
        toolName: String,
        title: String,
        detail: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.stepIndex = stepIndex
        self.kind = kind
        self.toolName = toolName
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
    }
}

// MARK: - Unified Activity Feed & High-Level Telemetry State

public enum TelemetryActivityItem: Sendable, Equatable, Identifiable {
    case thinking(ThinkingSnapshot)
    case compaction(CompactionEvent)
    case fileInspection(FileInspectionEvent)
    case fileChange(FileChangeEvent)
    case command(CommandExecutionEvent)
    case toolActivity(AgentToolActivityEvent)

    public var id: String {
        switch self {
        case let .thinking(snapshot): return "thinking-\(snapshot.stepIndex)"
        case let .compaction(event): return event.id
        case let .fileInspection(event): return "inspect-\(event.id)"
        case let .fileChange(event): return "file-\(event.id)"
        case let .command(event): return "cmd-\(event.id)"
        case let .toolActivity(event): return "tool-\(event.id)"
        }
    }

    public var timestamp: Date {
        switch self {
        case let .thinking(snapshot): return snapshot.startedAt
        case let .compaction(event): return event.startedAt
        case let .fileInspection(event): return event.timestamp
        case let .fileChange(event): return event.timestamp
        case let .command(event): return event.startedAt
        case let .toolActivity(event): return event.timestamp
        }
    }
}

public enum TelemetryState: Sendable, Equatable {
    case idle
    case working(startedAt: Date)
    case compacting(CompactionEvent)
    case thinking
    case replying(AssistantResponseSnapshot?)
    case inspecting(FileInspectionEvent)
    case editing(FileChangeEvent)
    case runningCommand(CommandExecutionEvent)
    case waitingForInput(String)
    case toolActivity(AgentToolActivityEvent)

    public var isActive: Bool {
        if case .idle = self { return false }
        return true
    }

    public var label: String {
        switch self {
        case .idle: return "Idle"
        case .working: return "Working"
        case .compacting: return "Compacting"
        case .thinking: return "Thinking"
        case .replying: return "Replying"
        case .inspecting: return "Analyzing"
        case let .editing(event):
            return event.kind == .delete ? "Deleting" : "Editing"
        case .runningCommand: return "Running"
        case .waitingForInput: return "Needs Input"
        case let .toolActivity(event): return event.kind.shortLabel
        }
    }
}

public enum NotchPeekEvent: Sendable, Equatable {
    case thinkingStarted
    case fileDeleted(String)
    case multiFileEdit(Int)
    case commandCompleted(String, Int)
    case commandFailed(String, Int)
    case turnCompleted
    case needsInput(String)
    case welcome
}

public struct AntigravityConnectionStatus: Sendable, Equatable {
    public var isAppInstalled: Bool
    public var isAppRunning: Bool
    public var appURL: URL
    public var brainDirectoryURL: URL
    public var isBrainAccessible: Bool
    public var activeConversationCount: Int
    public var needsFolderAccess: Bool

    public init(
        isAppInstalled: Bool = false,
        isAppRunning: Bool = false,
        appURL: URL = URL(fileURLWithPath: "/Applications/Antigravity.app"),
        brainDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity/brain", isDirectory: true),
        isBrainAccessible: Bool = false,
        activeConversationCount: Int = 0,
        needsFolderAccess: Bool = false
    ) {
        self.isAppInstalled = isAppInstalled
        self.isAppRunning = isAppRunning
        self.appURL = appURL
        self.brainDirectoryURL = brainDirectoryURL
        self.isBrainAccessible = isBrainAccessible
        self.activeConversationCount = activeConversationCount
        self.needsFolderAccess = needsFolderAccess
    }
}
