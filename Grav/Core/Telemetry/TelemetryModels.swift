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

public struct TokenMetrics: Sendable, Equatable {
    public var inputTokens: Int
    public var cacheReadTokens: Int
    public var outputTokens: Int

    public init(inputTokens: Int = 0, cacheReadTokens: Int = 0, outputTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.cacheReadTokens = cacheReadTokens
        self.outputTokens = outputTokens
    }

    public var totalTokens: Int {
        inputTokens + cacheReadTokens + outputTokens
    }

    public var cacheHitRate: Double {
        let totalIn = inputTokens + cacheReadTokens
        guard totalIn > 0 else { return 0 }
        return Double(cacheReadTokens) / Double(totalIn)
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
    public let addedLines: Int
    public let removedLines: Int
    public let diffHunks: [FileDiffHunk]
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

// MARK: - Unified Activity Feed & High-Level Telemetry State

public enum TelemetryActivityItem: Sendable, Equatable, Identifiable {
    case thinking(ThinkingSnapshot)
    case fileChange(FileChangeEvent)
    case command(CommandExecutionEvent)

    public var id: String {
        switch self {
        case let .thinking(snapshot): return "thinking-\(snapshot.stepIndex)"
        case let .fileChange(event): return "file-\(event.id)"
        case let .command(event): return "cmd-\(event.id)"
        }
    }

    public var timestamp: Date {
        switch self {
        case let .thinking(snapshot): return snapshot.startedAt
        case let .fileChange(event): return event.timestamp
        case let .command(event): return event.startedAt
        }
    }
}

public enum TelemetryState: Sendable, Equatable {
    case idle
    case thinking
    case editing(FileChangeEvent)
    case runningCommand(CommandExecutionEvent)

    public var isActive: Bool {
        if case .idle = self { return false }
        return true
    }

    public var label: String {
        switch self {
        case .idle: return "Idle"
        case .thinking: return "Thinking"
        case let .editing(event):
            return event.kind == .delete ? "Deleting" : "Editing"
        case .runningCommand: return "Running"
        }
    }
}

public enum NotchPeekEvent: Sendable, Equatable {
    case thinkingStarted
    case fileDeleted(String)
    case multiFileEdit(Int)
    case commandCompleted(String, Int)
    case commandFailed(String, Int)
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
