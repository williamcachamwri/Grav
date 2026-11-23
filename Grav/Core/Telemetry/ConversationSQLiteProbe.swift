import Foundation
import SQLite3

/// Live real-time snapshot decoded directly from Antigravity's active SQLite WAL database
/// (`~/.gemini/antigravity/conversations/<id>.db`), reverse-engineered from `/Applications/Antigravity.app`.
///
/// Gives Grav 100% ground-truth sub-millisecond visibility into in-flight steps BEFORE they finish
/// and flush to `transcript.jsonl`:
/// - `step_type == 15` (`PLANNER_RESPONSE`, `status == 2` RUNNING / `8` GENERATING):
///   exact live `thinking` text vs live streaming `response` text!
/// - `step_type == 23` (`CHECKPOINT`, `status == 2`): exact live `Compacting`!
/// - `step_type == 132` (`GENERIC`, `status == 2` RUNNING / `6` WAITING):
///   exact in-flight tool name & JSON arguments (`read_file`, `edit_file`, `run_command`,
///   `search_web`, `call_mcp_tool`, `ask_question`, `update_focus`, `update_steps`, etc.)!
/// - `status == 3` (`DONE`) with zero pending/running/waiting rows and final reply: exact `Idle`!
public struct ConversationSQLiteLiveSnapshot: Sendable, Equatable {
    public enum LivePhase: Sendable, Equatable {
        case idle
        case working
        case thinking(text: String?)
        case replying(text: String)
        case compacting
        case waitingForInput(prompt: String)
        case runningTool(name: String, argsJSON: String?)
    }

    public let latestStepIndex: Int
    public let phase: LivePhase
    public let latestFocus: String?
    public let latestSteps: AgentStepsProgress?
    public let activeRunningCount: Int

    public init(
        latestStepIndex: Int,
        phase: LivePhase,
        latestFocus: String? = nil,
        latestSteps: AgentStepsProgress? = nil,
        activeRunningCount: Int = 0
    ) {
        self.latestStepIndex = latestStepIndex
        self.phase = phase
        self.latestFocus = latestFocus
        self.latestSteps = latestSteps
        self.activeRunningCount = activeRunningCount
    }
}

/// Non-blocking read-only SQLite + minimal Protobuf wire decoder for Antigravity's live `steps` table.
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

    /// Reads the latest rows from `conversations/<id>.db` in read-only mode (including active `-wal` frames).
    /// Returns `nil` if the database does not exist or cannot be read within the 40ms busy timeout.
    public static func readLiveSnapshot(dbURL: URL) -> ConversationSQLiteLiveSnapshot? {
        guard FileManager.default.fileExists(atPath: dbURL.path) else { return nil }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(dbURL.path, &db, flags, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(db) }

        sqlite3_busy_timeout(db, 40)

        let sql = "SELECT idx, step_type, status, step_payload FROM steps ORDER BY idx DESC LIMIT 12;"
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
        }

        var rows: [RawRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let idx = Int(sqlite3_column_int64(stmt, 0))
            let stepType = Int(sqlite3_column_int(stmt, 1))
            let status = Int(sqlite3_column_int(stmt, 2))
            let payload: Data
            if let bytes = sqlite3_column_blob(stmt, 3) {
                let count = Int(sqlite3_column_bytes(stmt, 3))
                payload = count > 0 ? Data(bytes: bytes, count: count) : Data()
            } else {
                payload = Data()
            }
            rows.append(RawRow(idx: idx, stepType: stepType, status: status, payload: payload))
        }

        guard let newest = rows.first else { return nil }

        // Extract latest `update_focus` / `update_steps` if present in recent rows
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

        // 1. Highest priority: WAITING (user approval or `ask_question`)
        if let waiting = waitingRows.first {
            let tool = decodeGenericToolCall(waiting.payload)
            let prompt = extractWaitingPrompt(toolName: tool?.name, argsJSON: tool?.argsJSON)
            return ConversationSQLiteLiveSnapshot(
                latestStepIndex: newest.idx,
                phase: .waitingForInput(prompt: prompt),
                latestFocus: foundFocus,
                latestSteps: foundSteps,
                activeRunningCount: activeRows.count
            )
        }

        // 2. Active RUNNING / GENERATING step
        if let running = activeRows.first {
            switch running.stepType {
            case StepType.checkpoint:
                return ConversationSQLiteLiveSnapshot(
                    latestStepIndex: newest.idx,
                    phase: .compacting,
                    latestFocus: foundFocus,
                    latestSteps: foundSteps,
                    activeRunningCount: activeRows.count
                )

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
                return ConversationSQLiteLiveSnapshot(
                    latestStepIndex: newest.idx,
                    phase: phase,
                    latestFocus: foundFocus,
                    latestSteps: foundSteps,
                    activeRunningCount: activeRows.count
                )

            case StepType.generic:
                if let tool = decodeGenericToolCall(running.payload) {
                    if tool.name == "ask_question" {
                        let prompt = extractWaitingPrompt(toolName: tool.name, argsJSON: tool.argsJSON)
                        return ConversationSQLiteLiveSnapshot(
                            latestStepIndex: newest.idx,
                            phase: .waitingForInput(prompt: prompt),
                            latestFocus: foundFocus,
                            latestSteps: foundSteps,
                            activeRunningCount: activeRows.count
                        )
                    }
                    return ConversationSQLiteLiveSnapshot(
                        latestStepIndex: newest.idx,
                        phase: .runningTool(name: tool.name, argsJSON: tool.argsJSON),
                        latestFocus: foundFocus,
                        latestSteps: foundSteps,
                        activeRunningCount: activeRows.count
                    )
                }
                return ConversationSQLiteLiveSnapshot(
                    latestStepIndex: newest.idx,
                    phase: .working,
                    latestFocus: foundFocus,
                    latestSteps: foundSteps,
                    activeRunningCount: activeRows.count
                )

            default:
                return ConversationSQLiteLiveSnapshot(
                    latestStepIndex: newest.idx,
                    phase: .working,
                    latestFocus: foundFocus,
                    latestSteps: foundSteps,
                    activeRunningCount: activeRows.count
                )
            }
        }

        // 3. Pending queued steps waiting to run next
        if !pendingRows.isEmpty {
            return ConversationSQLiteLiveSnapshot(
                latestStepIndex: newest.idx,
                phase: .working,
                latestFocus: foundFocus,
                latestSteps: foundSteps,
                activeRunningCount: pendingRows.count
            )
        }

        // 4. Terminal check: if the newest step is a final PLANNER_RESPONSE (DONE, no tool calls), we are 100% IDLE!
        if newest.stepType == StepType.plannerResponse && newest.status == StepStatus.done {
            let parsed = decodePlannerPayload(newest.payload)
            if parsed.toolCalls.isEmpty {
                return ConversationSQLiteLiveSnapshot(
                    latestStepIndex: newest.idx,
                    phase: .idle,
                    latestFocus: foundFocus,
                    latestSteps: foundSteps,
                    activeRunningCount: 0
                )
            }
        }

        // 5. If newest step is USER_INPUT or a completed tool result (`GENERIC` DONE) right before the next planner call,
        // the model is actively working on the next turn step!
        if newest.stepType == StepType.userInput
            || (newest.stepType == StepType.generic && newest.status == StepStatus.done)
            || newest.stepType == StepType.systemMessage
        {
            return ConversationSQLiteLiveSnapshot(
                latestStepIndex: newest.idx,
                phase: .working,
                latestFocus: foundFocus,
                latestSteps: foundSteps,
                activeRunningCount: 0
            )
        }

        return ConversationSQLiteLiveSnapshot(
            latestStepIndex: newest.idx,
            phase: .idle,
            latestFocus: foundFocus,
            latestSteps: foundSteps,
            activeRunningCount: 0
        )
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
                case 0: // varint
                    guard readVarint() != nil else { return }
                case 1: // 64-bit
                    guard pos + 8 <= count else { return }
                    pos += 8
                case 2: // length-delimited
                    guard let len64 = readVarint() else { return }
                    let len = Int(len64)
                    guard len >= 0, pos + len <= count else { return }
                    let slice = Data(bytes: ptr.advanced(by: pos), count: len)
                    pos += len
                    fields.append(PBField(fieldNumber: fieldNumber, wireType: 2, bytes: slice))
                case 5: // 32-bit
                    guard pos + 4 <= count else { return }
                    pos += 4
                default:
                    return
                }
            }
        }
        return fields
    }

    // MARK: - JSON Argument Extractors

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
}
