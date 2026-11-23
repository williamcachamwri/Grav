import Foundation
import SQLite3

/// Authoritative global run-state summary decoded directly from `~/.gemini/antigravity/conversation_summaries.db`.
public struct ConversationRunSummarySnapshot: Sendable, Equatable {
    public let conversationID: String
    public let title: String
    public let runStatus: String // e.g. "CASCADE_RUN_STATUS_RUNNING" / "CASCADE_RUN_STATUS_IDLE"
    public let notFullyIdle: Bool
    public let lastUserInputTime: Date?
    public let workspaceName: String?
    public let activeRunningCountAcrossAllChats: Int

    public var isRunning: Bool {
        notFullyIdle
            || runStatus == "CASCADE_RUN_STATUS_RUNNING"
            || runStatus == "CASCADE_RUN_STATUS_BUSY"
    }

    public var isExplicitlyIdle: Bool {
        !notFullyIdle && runStatus == "CASCADE_RUN_STATUS_IDLE"
    }
}

/// Live in-flight tool execution decoded from `conversations/<id>.db` (`steps` table).
public struct LiveSQLiteToolExecution: Sendable, Equatable {
    public let stepIndex: Int
    public let name: String
    public let argsJSON: String?
    public let status: ToolExecutionStatus
    public let errorMessage: String?
}

/// Live planner/model error decoded directly from SQLite `steps.error_details`.
public struct LiveSQLiteModelError: Sendable, Equatable {
    public let stepIndex: Int
    public let message: String
    public let isPlannerStep: Bool
}

/// Live real-time snapshot decoded directly from Antigravity's active SQLite WAL database
/// (`~/.gemini/antigravity/conversations/<id>.db`) combined with global `conversation_summaries.db`.
public struct ConversationSQLiteLiveSnapshot: Sendable, Equatable {
    public enum LivePhase: Sendable, Equatable {
        case idle
        case working
        case thinking(text: String?)
        case replying(text: String)
        case compacting
        case waitingForInput(prompt: String)
        case runningTool(LiveSQLiteToolExecution)
    }

    public let latestStepIndex: Int
    public let phase: LivePhase
    public let latestFocus: String?
    public let latestSteps: AgentStepsProgress?
    public let activeTools: [LiveSQLiteToolExecution]
    public let recentToolErrors: [LiveSQLiteToolExecution]
    public let latestModelError: LiveSQLiteModelError?
    public let activeRunningCount: Int
    public let globalSummary: ConversationRunSummarySnapshot?

    public init(
        latestStepIndex: Int,
        phase: LivePhase,
        latestFocus: String? = nil,
        latestSteps: AgentStepsProgress? = nil,
        activeTools: [LiveSQLiteToolExecution] = [],
        recentToolErrors: [LiveSQLiteToolExecution] = [],
        latestModelError: LiveSQLiteModelError? = nil,
        activeRunningCount: Int = 0,
        globalSummary: ConversationRunSummarySnapshot? = nil
    ) {
        self.latestStepIndex = latestStepIndex
        self.phase = phase
        self.latestFocus = latestFocus
        self.latestSteps = latestSteps
        self.activeTools = activeTools
        self.recentToolErrors = recentToolErrors
        self.latestModelError = latestModelError
        self.activeRunningCount = activeRunningCount
        self.globalSummary = globalSummary
    }
}

/// Non-blocking read-only SQLite + minimal Protobuf wire decoder for Antigravity's live `steps` table
/// and global `conversation_summaries.db` index.
public enum ConversationSQLiteProbe {
    // Verified exact enum values from `/Applications/Antigravity.app/Contents/Resources/bin/language_server`
    private enum StepType {
        static let userInput = 14
        static let plannerResponse = 15
        static let checkpoint = 23
        static let systemMessage = 101
        static let generic = 132
    }

    private enum StepStatus {
        static let pending = 1
        static let running = 2
        static let done = 3
        static let invalid = 4
        static let canceled = 5
        static let waiting = 6
        static let error = 7
        static let generating = 8
    }

    /// Reads the authoritative global run status for `conversationID` and counts all currently running chats
    /// from `~/.gemini/antigravity/conversation_summaries.db`.
    public static func readGlobalSummary(
        antigravityRootURL: URL,
        conversationID: String
    ) -> ConversationRunSummarySnapshot? {
        let summariesURL = antigravityRootURL.appendingPathComponent("conversation_summaries.db")
        guard FileManager.default.fileExists(atPath: summariesURL.path) else { return nil }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(summariesURL.path, &db, flags, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 30)

        // Count active running conversations across all Antigravity windows
        var activeCount = 0
        var countStmt: OpaquePointer?
        let countSQL = "SELECT count(*) FROM conversation_summaries WHERE not_fully_idle = 1 OR status IN ('CASCADE_RUN_STATUS_RUNNING', 'CASCADE_RUN_STATUS_BUSY');"
        if sqlite3_prepare_v2(db, countSQL, -1, &countStmt, nil) == SQLITE_OK, let countStmt {
            if sqlite3_step(countStmt) == SQLITE_ROW {
                activeCount = Int(sqlite3_column_int(countStmt, 0))
            }
            sqlite3_finalize(countStmt)
        }

        // Read target conversation row
        let sql = "SELECT title, status, not_fully_idle, last_user_input_time, workspace_uris FROM conversation_summaries WHERE conversation_id = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return nil }
        defer { sqlite3_finalize(stmt) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        conversationID.withCString { cStr in
            _ = sqlite3_bind_text(stmt, 1, cStr, -1, SQLITE_TRANSIENT)
        }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        let title = columnString(stmt, 0) ?? ""
        let status = columnString(stmt, 1) ?? ""
        let notFullyIdle = sqlite3_column_int(stmt, 2) != 0
        let lastUserInputRaw = columnString(stmt, 3)
        let workspaceURIsRaw = columnString(stmt, 4)

        let lastUserInputDate = lastUserInputRaw.flatMap { parseSummaryTimestamp($0) }
        let workspaceName = workspaceURIsRaw.flatMap { parseWorkspaceName(from: $0) }

        return ConversationRunSummarySnapshot(
            conversationID: conversationID,
            title: title,
            runStatus: status,
            notFullyIdle: notFullyIdle,
            lastUserInputTime: lastUserInputDate,
            workspaceName: workspaceName,
            activeRunningCountAcrossAllChats: activeCount
        )
    }

    /// Reads the latest rows from `conversations/<id>.db` in read-only mode (including active `-wal` frames),
    /// cross-referenced with `conversation_summaries.db` for 100% authoritative run-state accuracy.
    public static func readLiveSnapshot(
        dbURL: URL,
        antigravityRootURL: URL? = nil,
        conversationID: String? = nil
    ) -> ConversationSQLiteLiveSnapshot? {
        let globalSummary: ConversationRunSummarySnapshot? = {
            guard let root = antigravityRootURL, let cid = conversationID else { return nil }
            return readGlobalSummary(antigravityRootURL: root, conversationID: cid)
        }()

        guard FileManager.default.fileExists(atPath: dbURL.path) else { return nil }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(dbURL.path, &db, flags, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(db) }

        sqlite3_busy_timeout(db, 40)

        let sql = "SELECT idx, step_type, status, step_payload, error_details FROM steps ORDER BY idx DESC LIMIT 16;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        struct RawRow {
            let idx: Int
            let stepType: Int
            let status: Int
            let payload: Data
            let errorDetails: Data
        }

        var rows: [RawRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let idx = Int(sqlite3_column_int64(stmt, 0))
            let stepType = Int(sqlite3_column_int(stmt, 1))
            let status = Int(sqlite3_column_int(stmt, 2))
            let payload = columnBlob(stmt, 3)
            let errData = columnBlob(stmt, 4)
            rows.append(RawRow(idx: idx, stepType: stepType, status: status, payload: payload, errorDetails: errData))
        }

        guard let newest = rows.first else { return nil }

        // Extract latest `update_focus` / `update_steps` from recent rows
        var foundFocus: String?
        var foundSteps: AgentStepsProgress?
        for row in rows {
            if foundFocus != nil && foundSteps != nil { break }
            if row.stepType == StepType.plannerResponse {
                let parsed = decodePlannerPayload(row.payload)
                for call in parsed.toolCalls.reversed() {
                    if foundFocus == nil && call.name == "update_focus",
                       let focus = parseFocusFromArgsJSON(call.argsJSON)
                    {
                        foundFocus = focus
                    }
                    if foundSteps == nil && call.name == "update_steps",
                       let steps = parseStepsFromArgsJSON(call.argsJSON, stepIndex: row.idx)
                    {
                        foundSteps = steps
                    }
                }
            }
        }

        let activeRows = rows.filter {
            $0.status == StepStatus.running || $0.status == StepStatus.generating
        }
        let waitingRows = rows.filter { $0.status == StepStatus.waiting }
        let pendingRows = rows.filter { $0.status == StepStatus.pending }

        // Collect all currently active generic tool executions (including parallel MCP / command calls!)
        var activeTools: [LiveSQLiteToolExecution] = []
        for row in activeRows where row.stepType == StepType.generic {
            if let tool = decodeGenericToolCall(row.payload) {
                activeTools.append(
                    LiveSQLiteToolExecution(
                        stepIndex: row.idx,
                        name: tool.name,
                        argsJSON: tool.argsJSON,
                        status: .running,
                        errorMessage: nil
                    )
                )
            }
        }

        // Collect recent tool errors (`status == 7` + `error_details`)
        var recentErrors: [LiveSQLiteToolExecution] = []
        for row in rows.prefix(6) where row.stepType == StepType.generic && row.status == StepStatus.error {
            if let tool = decodeGenericToolCall(row.payload) {
                let errMsg = decodeErrorDetails(row.errorDetails)
                recentErrors.append(
                    LiveSQLiteToolExecution(
                        stepIndex: row.idx,
                        name: tool.name,
                        argsJSON: tool.argsJSON,
                        status: .failed,
                        errorMessage: errMsg
                    )
                )
            }
        }

        // Collect the newest planner/system quota, rate-limit, capacity, or model error from `error_details`
        var latestModelError: LiveSQLiteModelError?
        for row in rows.prefix(4) {
            let isPlanner = row.stepType == StepType.plannerResponse
            let isErrorRow = row.status == StepStatus.error
            guard isErrorRow || !row.errorDetails.isEmpty else { continue }
            let decoded = decodeErrorDetails(row.errorDetails) ?? ""
            if isPlanner && isErrorRow {
                latestModelError = LiveSQLiteModelError(
                    stepIndex: row.idx,
                    message: decoded,
                    isPlannerStep: true
                )
                break
            }
            if !decoded.isEmpty,
               AntigravityRuntimeInspector.classifyModelError(
                   rawMessage: decoded,
                   stepIndex: row.idx,
                   treatUnknownAsModelError: false
               ) != nil
            {
                latestModelError = LiveSQLiteModelError(
                    stepIndex: row.idx,
                    message: decoded,
                    isPlannerStep: isPlanner
                )
                break
            }
        }

        // Helper to ensure every snapshot carries `latestModelError` consistently
        func makeSnapshot(
            phase: ConversationSQLiteLiveSnapshot.LivePhase,
            tools: [LiveSQLiteToolExecution] = activeTools,
            runningCount: Int = activeRows.count
        ) -> ConversationSQLiteLiveSnapshot {
            ConversationSQLiteLiveSnapshot(
                latestStepIndex: newest.idx,
                phase: phase,
                latestFocus: foundFocus,
                latestSteps: foundSteps,
                activeTools: tools,
                recentToolErrors: recentErrors,
                latestModelError: latestModelError,
                activeRunningCount: runningCount,
                globalSummary: globalSummary
            )
        }

        // 0. Terminal newest PLANNER_RESPONSE ERROR (quota / 429 / capacity / model failure)
        if newest.stepType == StepType.plannerResponse && newest.status == StepStatus.error && activeRows.isEmpty {
            return makeSnapshot(phase: .idle, tools: [], runningCount: 0)
        }

        // 1. Highest priority: WAITING (user approval or `ask_question`)
        if let waiting = waitingRows.first {
            let tool = decodeGenericToolCall(waiting.payload)
            let prompt = extractWaitingPrompt(toolName: tool?.name, argsJSON: tool?.argsJSON)
            return makeSnapshot(phase: .waitingForInput(prompt: prompt))
        }

        // 2. Active RUNNING / GENERATING step
        if let running = activeRows.first {
            switch running.stepType {
            case StepType.checkpoint:
                return makeSnapshot(phase: .compacting)

            case StepType.plannerResponse:
                let parsed = decodePlannerPayload(running.payload)
                let reply = parsed.response.trimmingCharacters(in: .whitespacesAndNewlines)
                let thinking = parsed.thinking.trimmingCharacters(in: .whitespacesAndNewlines)
                let phase: ConversationSQLiteLiveSnapshot.LivePhase
                if !reply.isEmpty {
                    phase = .replying(text: reply)
                } else if !thinking.isEmpty {
                    phase = .thinking(text: thinking)
                } else {
                    phase = .working
                }
                return makeSnapshot(phase: phase)

            case StepType.generic:
                if let primaryTool = activeTools.first {
                    if primaryTool.name == "ask_question" {
                        let prompt = extractWaitingPrompt(toolName: primaryTool.name, argsJSON: primaryTool.argsJSON)
                        return makeSnapshot(phase: .waitingForInput(prompt: prompt))
                    }
                    return makeSnapshot(phase: .runningTool(primaryTool))
                }
                return makeSnapshot(phase: .working)

            default:
                return makeSnapshot(phase: .working)
            }
        }

        // 3. Pending queued steps waiting to execute next
        if !pendingRows.isEmpty {
            return makeSnapshot(phase: .working, runningCount: pendingRows.count)
        }

        // 4. Authoritative global summary check: if Antigravity explicitly marks conversation IDLE & not_fully_idle=0
        if let summary = globalSummary, summary.isExplicitlyIdle {
            return makeSnapshot(phase: .idle, tools: [], runningCount: 0)
        }

        // 5. Terminal check: final PLANNER_RESPONSE (DONE, no tool calls)
        if newest.stepType == StepType.plannerResponse && newest.status == StepStatus.done {
            let parsed = decodePlannerPayload(newest.payload)
            if parsed.toolCalls.isEmpty {
                return makeSnapshot(phase: .idle, tools: [], runningCount: 0)
            }
        }

        // 6. Authoritative global RUNNING or freshly-completed tool / user input awaiting next LLM step
        if (globalSummary?.isRunning == true)
            || newest.stepType == StepType.userInput
            || (newest.stepType == StepType.generic && (newest.status == StepStatus.done || newest.status == StepStatus.error))
            || newest.stepType == StepType.systemMessage
        {
            return makeSnapshot(phase: .working, runningCount: 0)
        }

        return makeSnapshot(phase: .idle, tools: [], runningCount: 0)
    }

    // MARK: - Pretty JSON Formatter (Shared by SQLite Probe & EventClassifier)

    public static func prettyFormatJSON(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data)
        else {
            return raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return prettyFormatJSONObject(obj)
    }

    public static func prettyFormatJSONObject(_ obj: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(obj),
              let prettyData = try? JSONSerialization.data(
                  withJSONObject: obj,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let pretty = String(data: prettyData, encoding: .utf8)
        else {
            return nil
        }
        return pretty
    }

    // MARK: - Minimal Zero-Dependency Protobuf Wire Decoder

    struct DecodedToolCall {
        let name: String
        let argsJSON: String?
    }

    struct DecodedPlannerPayload {
        var response: String = ""
        var thinking: String = ""
        var toolCalls: [DecodedToolCall] = []
    }

    static func decodePlannerPayload(_ data: Data) -> DecodedPlannerPayload {
        var result = DecodedPlannerPayload()
        for field in parseProtobufFields(data) where field.fieldNumber == 20 && field.wireType == 2 {
            guard let subData = field.bytes else { continue }
            for sub in parseProtobufFields(subData) where sub.wireType == 2 {
                guard let bytes = sub.bytes else { continue }
                switch sub.fieldNumber {
                case 1, 8:
                    if result.response.isEmpty, let text = String(data: bytes, encoding: .utf8), !text.isEmpty {
                        result.response = text
                    }
                case 3:
                    if let text = String(data: bytes, encoding: .utf8), !text.isEmpty {
                        result.thinking = text
                    }
                case 7:
                    if let call = decodeToolCallMessage(bytes) {
                        result.toolCalls.append(call)
                    }
                default:
                    break
                }
            }
        }
        return result
    }

    static func decodeGenericToolCall(_ data: Data) -> DecodedToolCall? {
        for field in parseProtobufFields(data) where field.fieldNumber == 5 && field.wireType == 2 {
            guard let metaBytes = field.bytes else { continue }
            for sub in parseProtobufFields(metaBytes) where sub.fieldNumber == 4 && sub.wireType == 2 {
                guard let callBytes = sub.bytes else { continue }
                if let call = decodeToolCallMessage(callBytes) {
                    return call
                }
            }
        }
        return nil
    }

    static func decodeErrorDetails(_ data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        for field in parseProtobufFields(data) where field.wireType == 2 {
            if let bytes = field.bytes,
               let text = String(data: bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty
            {
                return text
            }
        }
        return nil
    }

    private static func decodeToolCallMessage(_ data: Data) -> DecodedToolCall? {
        var name: String?
        var argsJSON: String?
        for field in parseProtobufFields(data) where field.wireType == 2 {
            guard let bytes = field.bytes, let str = String(data: bytes, encoding: .utf8) else { continue }
            if field.fieldNumber == 2 {
                name = str
            } else if field.fieldNumber == 3 {
                argsJSON = str
            }
        }
        guard let name, !name.isEmpty else { return nil }
        return DecodedToolCall(name: name, argsJSON: argsJSON)
    }

    private struct PBField {
        let fieldNumber: Int
        let wireType: Int
        let bytes: Data?
    }

    private static func parseProtobufFields(_ data: Data) -> [PBField] {
        var fields: [PBField] = []
        let count = data.count
        guard count > 0 else { return fields }

        data.withUnsafeBytes { rawBuf in
            guard let ptr = rawBuf.bindMemory(to: UInt8.self).baseAddress else { return }
            var pos = 0

            func readVarint() -> UInt64? {
                var val: UInt64 = 0
                var shift: UInt64 = 0
                while pos < count && shift < 64 {
                    let b = ptr[pos]
                    pos += 1
                    val |= UInt64(b & 0x7F) << shift
                    if (b & 0x80) == 0 {
                        return val
                    }
                    shift += 7
                }
                return nil
            }

            while pos < count {
                guard let tag = readVarint() else { break }
                let fieldNumber = Int(tag >> 3)
                let wireType = Int(tag & 7)
                switch wireType {
                case 0:
                    guard readVarint() != nil else { return }
                case 1:
                    guard pos + 8 <= count else { return }
                    pos += 8
                case 2:
                    guard let len64 = readVarint() else { return }
                    let len = Int(len64)
                    guard len >= 0, pos + len <= count else { return }
                    let slice = Data(bytes: ptr.advanced(by: pos), count: len)
                    pos += len
                    fields.append(PBField(fieldNumber: fieldNumber, wireType: 2, bytes: slice))
                case 5:
                    guard pos + 4 <= count else { return }
                    pos += 4
                default:
                    return
                }
            }
        }
        return fields
    }

    // MARK: - SQLite & JSON Helpers

    private static func columnString(_ stmt: OpaquePointer, _ idx: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, idx) else { return nil }
        return String(cString: cStr)
    }

    private static func columnBlob(_ stmt: OpaquePointer, _ idx: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(stmt, idx) else { return Data() }
        let count = Int(sqlite3_column_bytes(stmt, idx))
        return count > 0 ? Data(bytes: bytes, count: count) : Data()
    }

    private static func parseSummaryTimestamp(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("0001-01-01") else { return nil }
        // Format from Go sqlite driver: "2026-11-23 05:26:41.512969+00:00"
        let normalized = trimmed.replacingOccurrences(of: " ", with: "T")
        if let d = TranscriptDateParser.parse(normalized) { return d }
        // Strip sub-millisecond digits beyond 3 places if ISO8601DateFormatter rejected 6-digit microseconds
        if let dotIdx = normalized.firstIndex(of: "."),
           let tzIdx = normalized[dotIdx...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" })
        {
            let frac = normalized[normalized.index(after: dotIdx)..<tzIdx].prefix(3)
            let rebuilt = String(normalized[..<dotIdx]) + "." + frac + String(normalized[tzIdx...])
            return TranscriptDateParser.parse(rebuilt)
        }
        return nil
    }

    private static func parseWorkspaceName(from jsonArray: String) -> String? {
        guard let data = jsonArray.data(using: .utf8),
              let uris = try? JSONSerialization.jsonObject(with: data) as? [String],
              let first = uris.first, !first.isEmpty
        else { return nil }
        if let url = URL(string: first) {
            return url.lastPathComponent
        }
        return URL(fileURLWithPath: first).lastPathComponent
    }

    static func parseFocusFromArgsJSON(_ json: String?) -> String? {
        guard let json, let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let focus = dict["focus"] as? String
        else { return nil }
        let trimmed = focus.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func parseStepsFromArgsJSON(_ json: String?, stepIndex: Int) -> AgentStepsProgress? {
        guard let json, let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawSteps = dict["steps"] as? [[String: Any]]
        else { return nil }

        let items: [AgentStepItem] = rawSteps.enumerated().compactMap { idx, entry in
            guard let title = (entry["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty
            else { return nil }
            let rawStatus = (entry["status"] as? String) ?? "pending"
            let status = AgentStepStatus(rawValue: rawStatus) ?? .pending
            return AgentStepItem(index: idx, title: title, status: status)
        }
        guard !items.isEmpty else { return nil }
        return AgentStepsProgress(stepIndex: stepIndex, updatedAt: Date(), steps: items)
    }

    private static func extractWaitingPrompt(toolName: String?, argsJSON: String?) -> String {
        if toolName == "ask_question",
           let argsJSON, let data = argsJSON.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let questions = dict["questions"] as? [[String: Any]],
           let firstQ = questions.first?["question"] as? String,
           !firstQ.isEmpty
        {
            return firstQ
        }
        if let toolName, !toolName.isEmpty {
            return "Approve \(toolName)"
        }
        return "Waiting for your input"
    }

    // MARK: - Feature #1: Instant FTS5 Spotlight Search across All Antigravity Conversations

    /// Queries Antigravity's native SQLite FTS5 index (`conversations_fts`) joined with `conversation_summaries`.
    /// When `query` is empty, returns the most recently modified conversations ready for instant jump.
    public static func searchConversations(
        antigravityRootURL: URL,
        query: String,
        limit: Int = 24,
        unreadIDs: Set<String> = []
    ) -> [AntigravitySpotlightHit] {
        let summariesURL = antigravityRootURL.appendingPathComponent("conversation_summaries.db")
        guard FileManager.default.fileExists(atPath: summariesURL.path) else { return [] }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(summariesURL.path, &db, flags, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return []
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 40)

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let boundedLimit = max(1, min(limit, 50))

        if trimmed.isEmpty {
            return fetchRecentSummaries(db: db, limit: boundedLimit, unreadIDs: unreadIDs)
        }

        // Primary path: native FTS5 full-text search across title, workspace, user_body, agent_body
        if let ftsQuery = buildFTS5MatchExpression(from: trimmed) {
            let ftsHits = queryFTS5(
                db: db,
                matchExpression: ftsQuery,
                limit: boundedLimit,
                unreadIDs: unreadIDs
            )
            if !ftsHits.isEmpty {
                return ftsHits
            }
        }

        // Graceful fallback: LIKE scan over title, preview, and workspace_uris
        return querySummariesLike(db: db, query: trimmed, limit: boundedLimit, unreadIDs: unreadIDs)
    }

    private static func fetchRecentSummaries(
        db: OpaquePointer,
        limit: Int,
        unreadIDs: Set<String>
    ) -> [AntigravitySpotlightHit] {
        let sql = """
        SELECT conversation_id, title, preview, workspace_uris, last_modified_time, step_count, status, not_fully_idle
        FROM conversation_summaries
        WHERE parent_conversation_id = '' AND killed = 0
        ORDER BY last_modified_time DESC
        LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))

        var results: [AntigravitySpotlightHit] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cid = columnString(stmt, 0), !cid.isEmpty else { continue }
            let rawTitle = (columnString(stmt, 1) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = cleanSnippetText(columnString(stmt, 2) ?? "")
            let workspace = columnString(stmt, 3).flatMap { parseWorkspaceName(from: $0) }
            let modified = columnString(stmt, 4).flatMap { parseSummaryTimestamp($0) }
            let stepCount = Int(sqlite3_column_int(stmt, 5))
            let status = columnString(stmt, 6) ?? ""
            let notFullyIdle = sqlite3_column_int(stmt, 7) != 0
            let isRunning = notFullyIdle
                || status == "CASCADE_RUN_STATUS_RUNNING"
                || status == "CASCADE_RUN_STATUS_BUSY"

            results.append(
                AntigravitySpotlightHit(
                    conversationID: cid,
                    title: rawTitle.isEmpty ? String(cid.prefix(8)) : rawTitle,
                    workspaceName: workspace,
                    snippet: preview,
                    lastModified: modified,
                    stepCount: stepCount,
                    isRunning: isRunning,
                    isUnread: unreadIDs.contains(cid)
                )
            )
        }
        return results
    }

    private static func queryFTS5(
        db: OpaquePointer,
        matchExpression: String,
        limit: Int,
        unreadIDs: Set<String>
    ) -> [AntigravitySpotlightHit] {
        // NOTE: SQLite FTS5 strictly forbids table aliases or `GROUP BY` when calling `bm25()` / `snippet()`.
        // Always reference `conversations_fts` directly and deduplicate cleanly in Swift.
        let sql = """
        SELECT
            conversations_fts.conversation_id,
            COALESCE(NULLIF(s.title, ''), conversations_fts.title),
            s.workspace_uris,
            snippet(conversations_fts, 13, '«', '»', '…', 18),
            snippet(conversations_fts, 14, '«', '»', '…', 18),
            COALESCE(s.preview, ''),
            COALESCE(s.last_modified_time, conversations_fts.last_modified_time),
            COALESCE(s.step_count, conversations_fts.step_count),
            COALESCE(s.status, ''),
            COALESCE(s.not_fully_idle, 0),
            conversations_fts.chunk_index,
            conversations_fts.chunk_first_step
        FROM conversations_fts
        LEFT JOIN conversation_summaries s ON s.conversation_id = conversations_fts.conversation_id
        WHERE conversations_fts MATCH ?
        ORDER BY bm25(conversations_fts)
        LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        matchExpression.withCString { cStr in
            _ = sqlite3_bind_text(stmt, 1, cStr, -1, SQLITE_TRANSIENT)
        }
        sqlite3_bind_int(stmt, 2, Int32(max(limit * 3, 40)))

        var results: [AntigravitySpotlightHit] = []
        var perConversationCount: [String: Int] = [:]
        var seenSnippets: Set<String> = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cid = columnString(stmt, 0), !cid.isEmpty else { continue }
            let countForConvo = perConversationCount[cid, default: 0]
            guard countForConvo < 6 else { continue }

            let rawTitle = (columnString(stmt, 1) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let workspace = columnString(stmt, 2).flatMap { parseWorkspaceName(from: $0) }
            let userSnippet = columnString(stmt, 3) ?? ""
            let agentSnippet = columnString(stmt, 4) ?? ""
            let fallbackPreview = columnString(stmt, 5) ?? ""
            let modified = columnString(stmt, 6).flatMap { parseSummaryTimestamp($0) }
            let stepCount = Int(sqlite3_column_int(stmt, 7))
            let status = columnString(stmt, 8) ?? ""
            let notFullyIdle = sqlite3_column_int(stmt, 9) != 0
            let chunkIdx = Int(sqlite3_column_int(stmt, 10))
            let firstStep = Int(sqlite3_column_int(stmt, 11))

            let chosenRawSnippet: String = {
                if userSnippet.contains("«") { return userSnippet }
                if agentSnippet.contains("«") { return agentSnippet }
                if !userSnippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return userSnippet }
                if !agentSnippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return agentSnippet }
                return fallbackPreview
            }()
            let snippet = cleanSnippetText(
                chosenRawSnippet
                    .replacingOccurrences(of: "«", with: "")
                    .replacingOccurrences(of: "»", with: "")
            )
            let dedupeKey = "\(cid)|\(snippet.prefix(80))"
            guard !seenSnippets.contains(dedupeKey) else { continue }
            seenSnippets.insert(dedupeKey)

            let isRunning = notFullyIdle
                || status == "CASCADE_RUN_STATUS_RUNNING"
                || status == "CASCADE_RUN_STATUS_BUSY"

            let stepLabel = firstStep > 0 ? "Step \(firstStep)" : nil

            results.append(
                AntigravitySpotlightHit(
                    id: "\(cid)-chunk-\(chunkIdx)",
                    conversationID: cid,
                    title: rawTitle.isEmpty ? String(cid.prefix(8)) : rawTitle,
                    workspaceName: workspace,
                    snippet: snippet,
                    chunkStepLabel: stepLabel,
                    lastModified: modified,
                    stepCount: stepCount,
                    isRunning: isRunning,
                    isUnread: unreadIDs.contains(cid)
                )
            )
            perConversationCount[cid] = countForConvo + 1
            if results.count >= limit { break }
        }
        return results
    }

    private static func querySummariesLike(
        db: OpaquePointer,
        query: String,
        limit: Int,
        unreadIDs: Set<String>
    ) -> [AntigravitySpotlightHit] {
        // Fallback substring scan across both summaries AND FTS body columns for punctuation/partial matches
        let sql = """
        SELECT
            conversations_fts.conversation_id,
            COALESCE(NULLIF(s.title, ''), conversations_fts.title),
            s.workspace_uris,
            COALESCE(NULLIF(s.preview, ''), substr(conversations_fts.user_body, 1, 180), substr(conversations_fts.agent_body, 1, 180)),
            COALESCE(s.last_modified_time, conversations_fts.last_modified_time),
            COALESCE(s.step_count, conversations_fts.step_count),
            COALESCE(s.status, ''),
            COALESCE(s.not_fully_idle, 0),
            conversations_fts.chunk_index,
            conversations_fts.chunk_first_step
        FROM conversations_fts
        LEFT JOIN conversation_summaries s ON s.conversation_id = conversations_fts.conversation_id
        WHERE conversations_fts.title LIKE ?
           OR conversations_fts.user_body LIKE ?
           OR conversations_fts.agent_body LIKE ?
           OR COALESCE(s.title, '') LIKE ?
           OR COALESCE(s.workspace_uris, '') LIKE ?
        ORDER BY COALESCE(s.last_modified_time, conversations_fts.last_modified_time) DESC
        LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }

        let pattern = "%\(query)%"
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        pattern.withCString { cStr in
            for idx: Int32 in 1...5 {
                _ = sqlite3_bind_text(stmt, idx, cStr, -1, SQLITE_TRANSIENT)
            }
        }
        sqlite3_bind_int(stmt, 6, Int32(limit))

        var results: [AntigravitySpotlightHit] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cid = columnString(stmt, 0), !cid.isEmpty else { continue }
            let rawTitle = (columnString(stmt, 1) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let workspace = columnString(stmt, 2).flatMap { parseWorkspaceName(from: $0) }
            let preview = cleanSnippetText(columnString(stmt, 3) ?? "")
            let modified = columnString(stmt, 4).flatMap { parseSummaryTimestamp($0) }
            let stepCount = Int(sqlite3_column_int(stmt, 5))
            let status = columnString(stmt, 6) ?? ""
            let notFullyIdle = sqlite3_column_int(stmt, 7) != 0
            let chunkIdx = Int(sqlite3_column_int(stmt, 8))
            let firstStep = Int(sqlite3_column_int(stmt, 9))
            let isRunning = notFullyIdle
                || status == "CASCADE_RUN_STATUS_RUNNING"
                || status == "CASCADE_RUN_STATUS_BUSY"

            results.append(
                AntigravitySpotlightHit(
                    id: "\(cid)-like-\(chunkIdx)",
                    conversationID: cid,
                    title: rawTitle.isEmpty ? String(cid.prefix(8)) : rawTitle,
                    workspaceName: workspace,
                    snippet: preview,
                    chunkStepLabel: firstStep > 0 ? "Step \(firstStep)" : nil,
                    lastModified: modified,
                    stepCount: stepCount,
                    isRunning: isRunning,
                    isUnread: unreadIDs.contains(cid)
                )
            )
        }
        return results
    }

    static func buildFTS5MatchExpression(from query: String) -> String? {
        let normalized = query.precomposedStringWithCanonicalMapping
        let tokens = normalized
            .split(whereSeparator: { $0.isWhitespace })
            .map { raw -> String in
                let stripped = raw.unicodeScalars.filter {
                    CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
                }
                return String(String.UnicodeScalarView(stripped))
            }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " AND ")
    }

    private static func cleanSnippetText(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "<USER_REQUEST>", with: "")
            .replacingOccurrences(of: "</USER_REQUEST>", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Feature #3: Unread / Unseen Reply Radar across Parallel Antigravity Sessions

    /// Compares `conversation_summaries.last_modified_time` against each session's
    /// `~/.gemini/antigravity/annotations/<id>.pbtxt` `last_user_view_time` to detect
    /// sessions where Antigravity finished replying after the user last viewed them.
    public static func computeUnreadSessionIDs(
        antigravityRootURL: URL,
        candidateSessionIDs: [String]? = nil
    ) -> Set<String> {
        let summariesURL = antigravityRootURL.appendingPathComponent("conversation_summaries.db")
        let annotationsDir = antigravityRootURL.appendingPathComponent("annotations", isDirectory: true)
        guard FileManager.default.fileExists(atPath: summariesURL.path) else { return [] }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(summariesURL.path, &db, flags, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return []
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 30)

        let sql = """
        SELECT conversation_id, last_modified_time, status, not_fully_idle
        FROM conversation_summaries
        WHERE parent_conversation_id = '' AND killed = 0
        ORDER BY last_modified_time DESC
        LIMIT 40;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }

        let allowedSet = candidateSessionIDs.map(Set.init)
        var unread: Set<String> = []
        let now = Date()

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cid = columnString(stmt, 0), !cid.isEmpty else { continue }
            if let allowedSet, !allowedSet.contains(cid) { continue }

            let status = columnString(stmt, 2) ?? ""
            let notFullyIdle = sqlite3_column_int(stmt, 3) != 0
            let isRunning = notFullyIdle
                || status == "CASCADE_RUN_STATUS_RUNNING"
                || status == "CASCADE_RUN_STATUS_BUSY"
            // Only flag sessions that actually finished / settled with an unseen update
            guard !isRunning else { continue }

            guard let modifiedAt = columnString(stmt, 1).flatMap({ parseSummaryTimestamp($0) }) else { continue }
            // Ignore ancient sessions older than 7 days to keep radar signal crisp
            guard now.timeIntervalSince(modifiedAt) < 7 * 86_400 else { continue }

            let annotationURL = annotationsDir.appendingPathComponent("\(cid).pbtxt")
            guard let pbtxt = try? String(contentsOf: annotationURL, encoding: .utf8) else { continue }
            let annotation = ConversationAnnotation.parse(pbtxt: pbtxt)
            if let viewedAt = annotation.lastUserViewTime,
               modifiedAt.timeIntervalSince(viewedAt) > 3.0
            {
                unread.insert(cid)
            }
        }
        return unread
    }
}
