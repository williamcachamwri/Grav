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

/// Thread-safe, zero-allocation ISO 8601 parser supporting fractional (1–9 digits) and whole seconds.
public enum TranscriptDateParser {
    private static let fallbackLock = NSLock()
    nonisolated(unsafe) private static let fallbackFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let fallbackStandard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func parse(_ string: String) -> Date? {
        if let fast = parseFastISO8601(string) {
            return fast
        }
        fallbackLock.lock()
        defer { fallbackLock.unlock() }
        if let date = fallbackFractional.date(from: string) {
            return date
        }
        return fallbackStandard.date(from: string)
    }

    /// Pure ASCII-byte ISO 8601 parser (~40ns, 0 heap allocations) covering
    /// `YYYY-MM-DD[T| ]HH:MM:SS(.f+)?(Z|[+-]HH:?MM)`.
    private static func parseFastISO8601(_ string: String) -> Date? {
        let bytes = Array(string.utf8)
        let count = bytes.count
        guard count >= 20 else { return nil }

        @inline(__always)
        func digit(_ index: Int) -> Int? {
            let b = bytes[index]
            guard b >= 48 && b <= 57 else { return nil }
            return Int(b - 48)
        }

        @inline(__always)
        func parse2(_ start: Int) -> Int? {
            guard let d0 = digit(start), let d1 = digit(start + 1) else { return nil }
            return d0 * 10 + d1
        }

        @inline(__always)
        func parse4(_ start: Int) -> Int? {
            guard let hi = parse2(start), let lo = parse2(start + 2) else { return nil }
            return hi * 100 + lo
        }

        guard bytes[4] == 45, bytes[7] == 45, // '-'
              bytes[10] == 84 || bytes[10] == 116 || bytes[10] == 32, // 'T', 't', or ' '
              bytes[13] == 58, bytes[16] == 58, // ':'
              let year = parse4(0),
              let month = parse2(5), (1...12).contains(month),
              let day = parse2(8), (1...31).contains(day),
              let hour = parse2(11), (0...23).contains(hour),
              let minute = parse2(14), (0...59).contains(minute),
              let second = parse2(17), (0...60).contains(second)
        else { return nil }

        var idx = 19
        var fractionalSeconds: Double = 0

        if idx < count && (bytes[idx] == 46 || bytes[idx] == 44) { // '.' or ','
            idx += 1
            var scale = 0.1
            var sawDigit = false
            while idx < count, let d = digit(idx) {
                sawDigit = true
                if scale >= 1e-9 {
                    fractionalSeconds += Double(d) * scale
                    scale *= 0.1
                }
                idx += 1
            }
            guard sawDigit else { return nil }
        }

        guard idx < count else { return nil }
        var tzOffsetSeconds = 0
        let tzByte = bytes[idx]
        if tzByte == 90 || tzByte == 122 { // 'Z' or 'z'
            idx += 1
        } else if tzByte == 43 || tzByte == 45 { // '+' or '-'
            let sign = tzByte == 43 ? 1 : -1
            idx += 1
            guard idx + 1 < count, let tzHour = parse2(idx), (0...23).contains(tzHour) else { return nil }
            idx += 2
            var tzMinute = 0
            if idx < count {
                if bytes[idx] == 58 { idx += 1 }
                guard idx + 1 < count, let m = parse2(idx), (0...59).contains(m) else { return nil }
                tzMinute = m
                idx += 2
            }
            tzOffsetSeconds = sign * (tzHour * 3600 + tzMinute * 60)
        } else {
            return nil
        }

        guard idx == count else { return nil }

        // Howard Hinnant's exact civil-from-gregorian days since 1970-01-01
        let y = year - (month <= 2 ? 1 : 0)
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let daysSinceEpoch = era * 146097 + doe - 719468

        let wholeSeconds = daysSinceEpoch * 86400 + hour * 3600 + minute * 60 + second - tzOffsetSeconds
        return Date(timeIntervalSince1970: Double(wholeSeconds) + fractionalSeconds)
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
    public var lastUserViewTime: Date?

    public init(
        title: String? = nil,
        executionMode: AntigravityExecutionMode = .defaultMode,
        lastUserViewTime: Date? = nil
    ) {
        self.title = title
        self.executionMode = executionMode
        self.lastUserViewTime = lastUserViewTime
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

        var parsedViewTime: Date?
        if let range = pbtxt.range(
            of: #"last_user_view_time:\s*\{\s*seconds:\s*(\d+)(?:\s+nanos:\s*(\d+))?"#,
            options: .regularExpression
        ) {
            let slice = String(pbtxt[range])
            if let secRange = slice.range(of: #"seconds:\s*(\d+)"#, options: .regularExpression) {
                let secDigits = slice[secRange].filter(\.isNumber)
                if let seconds = TimeInterval(secDigits), seconds > 0 {
                    var nanos: TimeInterval = 0
                    if let nanoRange = slice.range(of: #"nanos:\s*(\d+)"#, options: .regularExpression) {
                        let nanoDigits = slice[nanoRange].filter(\.isNumber)
                        if let n = TimeInterval(nanoDigits) {
                            nanos = n / 1_000_000_000.0
                        }
                    }
                    parsedViewTime = Date(timeIntervalSince1970: seconds + nanos)
                }
            }
        }

        return ConversationAnnotation(
            title: parsedTitle,
            executionMode: mode,
            lastUserViewTime: parsedViewTime
        )
    }
}

// MARK: - Antigravity Spotlight Search, Radar, Artifacts & Runtime Inspection Models

/// Single search result returned from Antigravity's local SQLite FTS5 index (`conversations_fts`).
public struct AntigravitySpotlightHit: Sendable, Equatable, Identifiable {
    public let id: String
    public let conversationID: String
    public let title: String
    public let workspaceName: String?
    public let snippet: String
    public let chunkStepLabel: String?
    public let lastModified: Date?
    public let stepCount: Int
    public let isRunning: Bool
    public let isUnread: Bool

    public init(
        id: String? = nil,
        conversationID: String,
        title: String,
        workspaceName: String? = nil,
        snippet: String = "",
        chunkStepLabel: String? = nil,
        lastModified: Date? = nil,
        stepCount: Int = 0,
        isRunning: Bool = false,
        isUnread: Bool = false
    ) {
        self.id = id ?? conversationID
        self.conversationID = conversationID
        self.title = title
        self.workspaceName = workspaceName
        self.snippet = snippet
        self.chunkStepLabel = chunkStepLabel
        self.lastModified = lastModified
        self.stepCount = stepCount
        self.isRunning = isRunning
        self.isUnread = isUnread
    }
}

/// High-signal real-time Antigravity attention alert (Approval / Question / Quota & Model Incident).
public struct AntigravityRadarAlert: Sendable, Equatable, Identifiable {
    public enum Severity: String, Sendable, Equatable {
        case approval
        case modelIncident
        case modelFallback
    }

    public let id: String
    public let severity: Severity
    public let title: String
    public let detail: String
    public let badge: String
    public let timestamp: Date

    public init(
        id: String,
        severity: Severity,
        title: String,
        detail: String,
        badge: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
        self.badge = badge
        self.timestamp = timestamp
    }
}

/// Detected Antigravity quota exhaustion, HTTP 429 rate-limit, capacity error, or mid-session model fallback.
public struct ModelIncidentEvent: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case quotaExceeded
        case rateLimited
        case capacityExhausted
        case modelError
        case modelFallback(from: String, to: String)

        public var isFailure: Bool {
            switch self {
            case .quotaExceeded, .rateLimited, .capacityExhausted, .modelError:
                return true
            case .modelFallback:
                return false
            }
        }
    }

    public let id: String
    public let stepIndex: Int
    public let kind: Kind
    public let title: String
    public let detail: String
    public let badge: String
    public let shortCollapsedLabel: String
    public let timestamp: Date

    public var isFailure: Bool {
        kind.isFailure
    }

    public init(
        id: String,
        stepIndex: Int,
        kind: Kind,
        title: String,
        detail: String,
        badge: String,
        shortCollapsedLabel: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.stepIndex = stepIndex
        self.kind = kind
        self.title = title
        self.detail = detail
        self.badge = badge
        self.shortCollapsedLabel = shortCollapsedLabel
        self.timestamp = timestamp
    }
}

/// Artifact, plan document, scratch script, or image discovered inside `~/.gemini/antigravity/brain/<id>/`.
public struct SessionArtifactItem: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        case planDocument = "Docs"
        case image = "Images"
        case scratchScript = "Scratch"
        case file = "Other"

        public var symbolName: String {
            switch self {
            case .planDocument: return "doc.richtext"
            case .image: return "photo"
            case .scratchScript: return "curlybraces"
            case .file: return "doc"
            }
        }
    }

    public let id: String
    public let url: URL
    public let name: String
    public let relativePath: String
    public let kind: Kind
    public let fileSize: Int64
    public let modifiedAt: Date

    public init(
        url: URL,
        name: String,
        relativePath: String,
        kind: Kind,
        fileSize: Int64,
        modifiedAt: Date
    ) {
        self.id = url.path
        self.url = url
        self.name = name
        self.relativePath = relativePath
        self.kind = kind
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

/// Installed MCP server discovered from `~/.gemini/antigravity/mcp/`.
public struct MCPServerSummary: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let toolCount: Int
    public let sampleTools: [String]
    public let directoryURL: URL

    public init(
        name: String,
        toolCount: Int,
        sampleTools: [String],
        directoryURL: URL
    ) {
        self.id = name
        self.name = name
        self.toolCount = toolCount
        self.sampleTools = sampleTools
        self.directoryURL = directoryURL
    }
}

/// Unified background task, daemon, or `/schedule` timer/cron record for the active Antigravity session.
public struct ScheduledTaskRecord: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Equatable {
        case backgroundTask = "Task"
        case daemon = "Daemon"
        case timer = "Timer"
        case cron = "Cron"

        public var symbolName: String {
            switch self {
            case .backgroundTask: return "bolt.horizontal.circle"
            case .daemon: return "infinity.circle"
            case .timer: return "timer"
            case .cron: return "clock.arrow.2.circlepath"
            }
        }
    }

    public let id: String
    public let title: String
    public let kind: Kind
    public let status: ToolExecutionStatus
    public let detail: String
    public let logURL: URL?
    public let updatedAt: Date

    public init(
        id: String,
        title: String,
        kind: Kind,
        status: ToolExecutionStatus,
        detail: String,
        logURL: URL? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.status = status
        self.detail = detail
        self.logURL = logURL
        self.updatedAt = updatedAt
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
    case artifact
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
        case .artifact: return "doc.richtext"
        case .waitingForInput: return "questionmark.bubble"
        case .genericTool: return "wrench.and.screwdriver"
        }
    }

    public var shortLabel: String {
        switch self {
        case .searchWeb: return "Searching"
        case .mcpTool: return "MCP"
        case .browser: return "Browsing"
        case .imageGeneration: return "Generating"
        case .subagent: return "Subagent"
        case .workflow: return "Workflow"
        case .schedule: return "Schedule"
        case .marketplace: return "Marketplace"
        case .artifact: return "Artifact"
        case .waitingForInput: return "Waiting"
        case .genericTool: return "Tool"
        }
    }
}

public enum ToolExecutionStatus: String, Sendable, Equatable {
    case running
    case succeeded
    case failed
    case waiting
}

public struct AgentToolActivityEvent: Sendable, Equatable, Identifiable {
    public let id: String
    public let stepIndex: Int
    public let kind: AgentToolActivityKind
    public let toolName: String
    public let serverName: String?
    public let title: String
    public let detail: String?
    public let argumentsJSON: String?
    public var outputPreview: String?
    public var status: ToolExecutionStatus
    public let startedAt: Date
    public var completedAt: Date?
    public let timestamp: Date

    public init(
        id: String,
        stepIndex: Int,
        kind: AgentToolActivityKind,
        toolName: String,
        serverName: String? = nil,
        title: String,
        detail: String? = nil,
        argumentsJSON: String? = nil,
        outputPreview: String? = nil,
        status: ToolExecutionStatus = .succeeded,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.stepIndex = stepIndex
        self.kind = kind
        self.toolName = toolName
        self.serverName = serverName
        self.title = title
        self.detail = detail
        self.argumentsJSON = argumentsJSON
        self.outputPreview = outputPreview
        self.status = status
        self.startedAt = startedAt ?? timestamp
        self.completedAt = completedAt
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
