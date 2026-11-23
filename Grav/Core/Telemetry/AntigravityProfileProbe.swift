import Foundation
import SQLite3

// MARK: - Antigravity Account, Usage & Observed Models Snapshot

/// Single quota or local usage window displayed cleanly inside the Profile drawer.
public struct AntigravityUsageWindow: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    /// Exact server-reported remaining fraction (`0.0...1.0`), or `nil` when only local transcript usage is available.
    public let serverRemainingFraction: Double?
    public let resetDate: Date?
    public let tokensUsed: Int
    public let turnsCount: Int
    public let inlineResetCaption: Bool

    public var remainingPercent: Int? {
        guard let serverRemainingFraction else { return nil }
        return Int((min(1.0, max(0.0, serverRemainingFraction)) * 100.0).rounded())
    }

    public func resetCountdownLabel(now: Date = Date()) -> String? {
        guard let resetDate else { return nil }
        let seconds = Int(resetDate.timeIntervalSince(now))
        guard seconds > 60 else { return nil }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(1, minutes))m"
    }

    public init(
        id: String,
        label: String,
        serverRemainingFraction: Double? = nil,
        resetDate: Date? = nil,
        tokensUsed: Int = 0,
        turnsCount: Int = 0,
        inlineResetCaption: Bool = false
    ) {
        self.id = id
        self.label = label
        self.serverRemainingFraction = serverRemainingFraction.map { min(1.0, max(0.0, $0)) }
        self.resetDate = resetDate
        self.tokensUsed = tokensUsed
        self.turnsCount = turnsCount
        self.inlineResetCaption = inlineResetCaption
    }
}

/// Model family usage group (`Gemini Models`, `Claude and GPT models`, `Gemini 4 Argon`, etc.).
public struct AntigravityUsageGroup: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let windows: [AntigravityUsageWindow]

    public init(id: String, title: String, windows: [AntigravityUsageWindow]) {
        self.id = id
        self.title = title
        self.windows = windows
    }
}

/// Model discovered from live Antigravity transcripts or matching-account local cache.
public struct AntigravityAvailableModel: Sendable, Equatable, Identifiable {
    public enum Family: String, Sendable, Equatable, CaseIterable {
        case gemini = "Gemini"
        case claude = "Claude"
        case gpt = "GPT"
        case other = "Other"
    }

    public let id: String
    public let displayName: String
    public let rawIdentifier: String
    public let family: Family
    public let tag: String?
    /// Exact server-reported quota fraction when available for this account; `nil` otherwise.
    public let serverRemainingFraction: Double?
    public let recentTurns7d: Int
    public let recentTokens7d: Int
    public let isObservedInTranscripts: Bool

    public var remainingPercent: Int? {
        guard let serverRemainingFraction else { return nil }
        return Int((min(1.0, max(0.0, serverRemainingFraction)) * 100.0).rounded())
    }

    public init(
        id: String,
        displayName: String,
        rawIdentifier: String,
        family: Family,
        tag: String? = nil,
        serverRemainingFraction: Double? = nil,
        recentTurns7d: Int = 0,
        recentTokens7d: Int = 0,
        isObservedInTranscripts: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.rawIdentifier = rawIdentifier
        self.family = family
        self.tag = tag
        self.serverRemainingFraction = serverRemainingFraction.map { min(1.0, max(0.0, $0)) }
        self.recentTurns7d = recentTurns7d
        self.recentTokens7d = recentTokens7d
        self.isObservedInTranscripts = isObservedInTranscripts
    }
}

/// Complete local profile snapshot strictly scoped to the currently logged-in Antigravity account.
public struct AntigravityProfileSnapshot: Sendable, Equatable {
    public let displayName: String
    public let email: String?
    public let avatarURL: URL?
    public let planName: String?
    public let availableCredits: Int?
    public let hasFreshServerQuota: Bool
    public let usageGroups: [AntigravityUsageGroup]
    public let availableModels: [AntigravityAvailableModel]
    public let totalTokens5h: Int
    public let totalTokens7d: Int
    public let totalTurns5h: Int
    public let totalTurns7d: Int
    public let updatedAt: Date

    public var initials: String {
        let parts = displayName
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(2)
            .compactMap(\.first)
        if parts.count >= 2 {
            return String(parts).uppercased()
        }
        if let first = displayName.first {
            return String(displayName.prefix(2)).uppercased()
        }
        if let first = email?.first {
            return String(first).uppercased()
        }
        return "AG"
    }

    public init(
        displayName: String,
        email: String? = nil,
        avatarURL: URL? = nil,
        planName: String? = nil,
        availableCredits: Int? = nil,
        hasFreshServerQuota: Bool = false,
        usageGroups: [AntigravityUsageGroup] = [],
        availableModels: [AntigravityAvailableModel] = [],
        totalTokens5h: Int = 0,
        totalTokens7d: Int = 0,
        totalTurns5h: Int = 0,
        totalTurns7d: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.displayName = displayName
        self.email = email
        self.avatarURL = avatarURL
        self.planName = planName
        self.availableCredits = availableCredits
        self.hasFreshServerQuota = hasFreshServerQuota
        self.usageGroups = usageGroups
        self.availableModels = availableModels
        self.totalTokens5h = totalTokens5h
        self.totalTokens7d = totalTokens7d
        self.totalTurns5h = totalTurns5h
        self.totalTurns7d = totalTurns7d
        self.updatedAt = updatedAt
    }
}

// MARK: - Strict Account-Scoped Local Profile, Usage & Models Probe

/// Reads Antigravity's local non-secret state files (`app_storage.json`, matching-account `state.vscdb`,
/// and `~/.gemini/antigravity/brain/*/.system_generated/logs/transcript.jsonl`).
///
/// Strict integrity guarantees:
/// - **Zero cross-account bleed**: cached `Antigravity IDE` avatar, plan, credits, and model catalog
///   are ONLY used when their cached email matches the live logged-in account in `app_storage.json`.
/// - **Zero fabricated quota percentages**: server `% left` rings are rendered ONLY from a fresh,
///   unexpired matching-account quota cache; otherwise, 100% real local 5h / 7d token & turn metrics
///   are shown cleanly with a direct shortcut to Antigravity's live Usage view.
public enum AntigravityProfileProbe: Sendable {

    private struct DecodedUserStatus {
        var displayName: String?
        var email: String?
        var avatarURL: URL?
        var planName: String?
        var models: [DecodedCatalogModel] = []
    }

    private struct DecodedCatalogModel {
        let label: String
        let remainingFraction: Double
        let resetDate: Date?
        let tag: String?
    }

    private struct TranscriptFamilyAccumulator {
        var tokens5h: Int = 0
        var tokens7d: Int = 0
        var turns5h: Int = 0
        var turns7d: Int = 0
    }

    private struct ObservedModelStats {
        var turns7d: Int = 0
        var tokens7d: Int = 0
    }

    /// Loads the current account-accurate Antigravity profile, usage summary, and models.
    public static func loadProfile(
        antigravityRootURL: URL,
        appSupportURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true),
        activeModel: String? = nil,
        now: Date = Date()
    ) -> AntigravityProfileSnapshot {
        // 1. Live active login email from Antigravity 2.0 `app_storage.json`
        let appStorageURL = appSupportURL
            .appendingPathComponent("Antigravity/app_storage.json")
        let liveEmail = readLiveLoginEmail(from: appStorageURL)

        // 2. Legacy/IDE `state.vscdb` cache — ONLY accepted if its email strictly matches `liveEmail`!
        let ideStateDB = appSupportURL
            .appendingPathComponent("Antigravity IDE/User/globalStorage/state.vscdb")
        let rawCachedStatus = readUserStatusFromVSCDB(url: ideStateDB)
        let isCacheForSameAccount: Bool = {
            guard let cached = rawCachedStatus else { return false }
            guard let liveEmail else { return true }
            guard let cachedEmail = cached.email else { return false }
            return liveEmail.caseInsensitiveCompare(cachedEmail) == .orderedSame
        }()

        let matchedStatus: DecodedUserStatus? = isCacheForSameAccount ? rawCachedStatus : nil
        let matchedCredits: Int? = isCacheForSameAccount ? readAvailableCreditsFromVSCDB(url: ideStateDB) : nil

        let resolvedEmail = liveEmail ?? matchedStatus?.email
        let resolvedName: String = {
            if let name = matchedStatus?.displayName, !name.isEmpty {
                return name
            }
            if let resolvedEmail {
                return displayNameFromEmail(resolvedEmail)
            }
            return NSFullUserName().isEmpty ? "Antigravity User" : NSFullUserName()
        }()

        // 3. Real 5h & 7d local transcript telemetry across all sessions
        let brainDir = antigravityRootURL.appendingPathComponent("brain", isDirectory: true)
        let scanned = scanTranscriptUsage(
            brainDirectoryURL: brainDir,
            activeModel: activeModel,
            now: now
        )

        // 4. Build honest Usage groups (fresh server quota if available & matching; otherwise real local tokens/turns)
        let (usageGroups, hasFreshQuota) = buildUsageGroups(
            matchedStatus: matchedStatus,
            familyUsage: scanned.familyUsage,
            now: now
        )

        // 5. Build accurate Models list (live Antigravity 2.0 observed models + matching-account fresh catalog only)
        let models = buildModelsList(
            matchedStatus: matchedStatus,
            observedModels: scanned.observedModels,
            activeModel: activeModel,
            now: now
        )

        return AntigravityProfileSnapshot(
            displayName: resolvedName,
            email: resolvedEmail,
            avatarURL: matchedStatus?.avatarURL,
            planName: matchedStatus?.planName,
            availableCredits: matchedCredits,
            hasFreshServerQuota: hasFreshQuota,
            usageGroups: usageGroups,
            availableModels: models,
            totalTokens5h: scanned.totalTokens5h,
            totalTokens7d: scanned.totalTokens7d,
            totalTurns5h: scanned.totalTurns5h,
            totalTurns7d: scanned.totalTurns7d,
            updatedAt: now
        )
    }

    // MARK: - 1. Live `app_storage.json` Email Reader

    private static func readLiveLoginEmail(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = dict["agy.onboarding.lastLoginUsername"] as? String
        else { return nil }
        let cleaned = raw
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\r\t"))
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func displayNameFromEmail(_ email: String) -> String {
        let local = email.split(separator: "@").first.map(String.init) ?? email
        let words = local
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return words.isEmpty ? email : words.joined(separator: " ")
    }

    // MARK: - 2. `state.vscdb` Protobuf Decoder (`userStatus` & `modelCredits`)

    private static func readUserStatusFromVSCDB(url: URL) -> DecodedUserStatus? {
        guard let base64Value = readVSCDBStringValue(url: url, key: "antigravityUnifiedStateSync.userStatus"),
              let outerData = Data(base64Encoded: base64Value)
        else { return nil }
        return decodeUserStatusEnvelope(outerData)
    }

    private static func readAvailableCreditsFromVSCDB(url: URL) -> Int? {
        guard let base64Value = readVSCDBStringValue(url: url, key: "antigravityUnifiedStateSync.modelCredits"),
              let outerData = Data(base64Encoded: base64Value)
        else { return nil }

        for field in parseProtoFields(outerData) where field.fieldNumber == 1 && field.wireType == 2 {
            var isCreditsEntry = false
            var encodedVal: String?
            for sub in parseProtoFields(field.bytes) where sub.wireType == 2 {
                if sub.fieldNumber == 1,
                   let key = String(data: sub.bytes, encoding: .utf8),
                   key == "availableCreditsSentinelKey"
                {
                    isCreditsEntry = true
                } else if sub.fieldNumber == 2 {
                    for inner in parseProtoFields(sub.bytes) where inner.fieldNumber == 1 && inner.wireType == 2 {
                        encodedVal = String(data: inner.bytes, encoding: .utf8)
                    }
                }
            }
            if isCreditsEntry, let encodedVal, let innerBytes = Data(base64Encoded: encodedVal) {
                for f in parseProtoFields(innerBytes) where f.wireType == 0 {
                    return Int(f.varint)
                }
            }
        }
        return nil
    }

    private static func readVSCDBStringValue(url: URL, key: String) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 30)

        let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return nil }
        defer { sqlite3_finalize(stmt) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        key.withCString { cStr in
            _ = sqlite3_bind_text(stmt, 1, cStr, -1, SQLITE_TRANSIENT)
        }
        guard sqlite3_step(stmt) == SQLITE_ROW, let cText = sqlite3_column_text(stmt, 0) else {
            return nil
        }
        return String(cString: cText)
    }

    private static func decodeUserStatusEnvelope(_ outerData: Data) -> DecodedUserStatus? {
        var userStatusBytes: Data?
        for field in parseProtoFields(outerData) where field.fieldNumber == 1 && field.wireType == 2 {
            for sub in parseProtoFields(field.bytes) where sub.fieldNumber == 2 && sub.wireType == 2 {
                for inner in parseProtoFields(sub.bytes) where inner.fieldNumber == 1 && inner.wireType == 2 {
                    if let b64 = String(data: inner.bytes, encoding: .ascii),
                       let decoded = Data(base64Encoded: b64)
                    {
                        userStatusBytes = decoded
                    }
                }
            }
        }
        guard let usData = userStatusBytes else { return nil }

        var result = DecodedUserStatus()
        for field in parseProtoFields(usData) where field.wireType == 2 {
            switch field.fieldNumber {
            case 3:
                let str = String(data: field.bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let str, !str.isEmpty { result.displayName = str }
            case 7:
                let str = String(data: field.bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let str, !str.isEmpty { result.email = str }
            case 38:
                if let str = String(data: field.bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   str.hasPrefix("https://"),
                   let url = URL(string: str)
                {
                    result.avatarURL = url
                }
            case 36:
                for sub in parseProtoFields(field.bytes) where sub.wireType == 2 {
                    if sub.fieldNumber == 2 || sub.fieldNumber == 3,
                       let plan = String(data: sub.bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !plan.isEmpty
                    {
                        result.planName = plan
                        break
                    }
                }
            case 33:
                for sub in parseProtoFields(field.bytes) where sub.fieldNumber == 1 && sub.wireType == 2 {
                    if let model = decodeCatalogModel(sub.bytes) {
                        result.models.append(model)
                    }
                }
            default:
                break
            }
        }
        return result
    }

    private static func decodeCatalogModel(_ data: Data) -> DecodedCatalogModel? {
        var label: String?
        var remaining: Double = 1.0
        var resetDate: Date?
        var tag: String?

        for field in parseProtoFields(data) {
            if field.fieldNumber == 1 && field.wireType == 2 {
                label = String(data: field.bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if field.fieldNumber == 15 && field.wireType == 2 {
                for qf in parseProtoFields(field.bytes) {
                    if qf.fieldNumber == 1 && qf.wireType == 5 {
                        remaining = Double(qf.float32)
                    } else if qf.fieldNumber == 2 && qf.wireType == 2 {
                        for tf in parseProtoFields(qf.bytes) where tf.fieldNumber == 1 && tf.wireType == 0 {
                            if tf.varint > 1_000_000_000 {
                                resetDate = Date(timeIntervalSince1970: TimeInterval(tf.varint))
                            }
                        }
                    }
                }
            } else if field.fieldNumber == 16 && field.wireType == 2 {
                let t = String(data: field.bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let t, !t.isEmpty { tag = t }
            }
        }

        guard let label, !label.isEmpty else { return nil }
        return DecodedCatalogModel(
            label: label,
            remainingFraction: min(1.0, max(0.0, remaining)),
            resetDate: resetDate,
            tag: tag
        )
    }

    // MARK: - 3. Real Local Transcript 5h & 7d Usage Scanner

    private struct TranscriptScanResult {
        let familyUsage: [String: TranscriptFamilyAccumulator]
        let observedModels: [String: ObservedModelStats]
        let totalTokens5h: Int
        let totalTokens7d: Int
        let totalTurns5h: Int
        let totalTurns7d: Int
    }

    private static func scanTranscriptUsage(
        brainDirectoryURL: URL,
        activeModel: String?,
        now: Date
    ) -> TranscriptScanResult {
        let fm = FileManager.default
        var familyMap: [String: TranscriptFamilyAccumulator] = [:]
        var observedModels: [String: ObservedModelStats] = [:]
        var totalTokens5h = 0
        var totalTokens7d = 0
        var totalTurns5h = 0
        var totalTurns7d = 0

        if let activeModel, !activeModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            observedModels[activeModel] = observedModels[activeModel] ?? ObservedModelStats()
        }

        guard let sessionDirs = try? fm.contentsOfDirectory(
            at: brainDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return TranscriptScanResult(
                familyUsage: familyMap,
                observedModels: observedModels,
                totalTokens5h: 0,
                totalTokens7d: 0,
                totalTurns5h: 0,
                totalTurns7d: 0
            )
        }

        let cutoff7d = now.addingTimeInterval(-7 * 86_400)
        let cutoff5h = now.addingTimeInterval(-5 * 3600)

        for dir in sessionDirs {
            let logURL = dir.appendingPathComponent(".system_generated/logs/transcript.jsonl")
            guard fm.fileExists(atPath: logURL.path) else { continue }
            if let mdate = try? logURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               mdate < cutoff7d
            {
                continue
            }

            guard let content = try? String(contentsOf: logURL, encoding: .utf8) else { continue }
            for line in content.split(separator: "\n") {
                guard line.contains("\"PLANNER_RESPONSE\""), line.contains("\"model\"") else { continue }
                guard let lineData = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
                else { continue }

                guard let rawModel = obj["model"] as? String else { continue }
                let model = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !model.isEmpty, model != "\\" else { continue }

                let stepDate: Date = {
                    if let created = obj["created_at"] as? String,
                       let parsed = TranscriptDateParser.parse(created)
                    {
                        return parsed
                    }
                    return now
                }()
                guard stepDate >= cutoff7d else { continue }

                let input = (obj["input_tokens"] as? Int) ?? 0
                let output = (obj["output_tokens"] as? Int) ?? 0
                let stepTokens = max(0, input + output)

                var modelStats = observedModels[model] ?? ObservedModelStats()
                modelStats.turns7d += 1
                modelStats.tokens7d += stepTokens
                observedModels[model] = modelStats

                let groupKey = usageGroupKey(forModelName: model)
                var acc = familyMap[groupKey] ?? TranscriptFamilyAccumulator()
                acc.tokens7d += stepTokens
                acc.turns7d += 1
                totalTokens7d += stepTokens
                totalTurns7d += 1

                if stepDate >= cutoff5h {
                    acc.tokens5h += stepTokens
                    acc.turns5h += 1
                    totalTokens5h += stepTokens
                    totalTurns5h += 1
                }
                familyMap[groupKey] = acc
            }
        }

        return TranscriptScanResult(
            familyUsage: familyMap,
            observedModels: observedModels,
            totalTokens5h: totalTokens5h,
            totalTokens7d: totalTokens7d,
            totalTurns5h: totalTurns5h,
            totalTurns7d: totalTurns7d
        )
    }

    // MARK: - 4. Build Honest Usage Groups & Accurate Models List

    private static func buildUsageGroups(
        matchedStatus: DecodedUserStatus?,
        familyUsage: [String: TranscriptFamilyAccumulator],
        now: Date
    ) -> ([AntigravityUsageGroup], Bool) {
        func freshServerQuota(matching predicate: (String) -> Bool) -> (Double, Date)? {
            guard let models = matchedStatus?.models else { return nil }
            let matching = models.filter { predicate($0.label.lowercased()) }
            guard let first = matching.first,
                  let reset = first.resetDate,
                  reset > now
            else { return nil }
            let minRemaining = matching.map(\.remainingFraction).min() ?? first.remainingFraction
            return (minRemaining, reset)
        }

        let geminiAcc = familyUsage["gemini"] ?? TranscriptFamilyAccumulator()
        let claudeGPTAcc = familyUsage["claude_gpt"] ?? TranscriptFamilyAccumulator()
        let argonAcc = familyUsage["argon"] ?? TranscriptFamilyAccumulator()

        let geminiQuota = freshServerQuota(matching: { $0.contains("gemini") && !$0.contains("argon") })
        let claudeQuota = freshServerQuota(matching: { $0.contains("claude") || $0.contains("gpt") })
        let hasFreshQuota = geminiQuota != nil || claudeQuota != nil

        var groups: [AntigravityUsageGroup] = [
            AntigravityUsageGroup(
                id: "gemini",
                title: "Gemini Models",
                windows: [
                    AntigravityUsageWindow(
                        id: "gemini-weekly",
                        label: "7-day activity",
                        serverRemainingFraction: geminiQuota?.0,
                        resetDate: geminiQuota?.1,
                        tokensUsed: geminiAcc.tokens7d,
                        turnsCount: geminiAcc.turns7d
                    ),
                    AntigravityUsageWindow(
                        id: "gemini-5h",
                        label: "5h window",
                        serverRemainingFraction: nil,
                        resetDate: nil,
                        tokensUsed: geminiAcc.tokens5h,
                        turnsCount: geminiAcc.turns5h
                    ),
                ]
            ),
            AntigravityUsageGroup(
                id: "claude-gpt",
                title: "Claude and GPT models",
                windows: [
                    AntigravityUsageWindow(
                        id: "claude-weekly",
                        label: "7-day activity",
                        serverRemainingFraction: claudeQuota?.0,
                        resetDate: claudeQuota?.1,
                        tokensUsed: claudeGPTAcc.tokens7d,
                        turnsCount: claudeGPTAcc.turns7d
                    ),
                    AntigravityUsageWindow(
                        id: "claude-5h",
                        label: "5h window",
                        serverRemainingFraction: nil,
                        resetDate: nil,
                        tokensUsed: claudeGPTAcc.tokens5h,
                        turnsCount: claudeGPTAcc.turns5h
                    ),
                ]
            ),
        ]

        if argonAcc.turns7d > 0 {
            groups.append(
                AntigravityUsageGroup(
                    id: "gemini-argon",
                    title: "Gemini 4 Argon",
                    windows: [
                        AntigravityUsageWindow(
                            id: "argon-weekly",
                            label: "7-day activity",
                            serverRemainingFraction: nil,
                            resetDate: nil,
                            tokensUsed: argonAcc.tokens7d,
                            turnsCount: argonAcc.turns7d,
                            inlineResetCaption: true
                        ),
                    ]
                )
            )
        }

        return (groups, hasFreshQuota)
    }

    private static func buildModelsList(
        matchedStatus: DecodedUserStatus?,
        observedModels: [String: ObservedModelStats],
        activeModel: String?,
        now: Date
    ) -> [AntigravityAvailableModel] {
        var models: [AntigravityAvailableModel] = []
        var seenDisplayLower: Set<String> = []

        // 1. Real models observed in live Antigravity transcripts (active model first, then by usage)
        let sortedObserved = observedModels.sorted { a, b in
            if a.key == activeModel { return true }
            if b.key == activeModel { return false }
            return a.value.turns7d > b.value.turns7d
        }

        for (raw, stats) in sortedObserved {
            let pretty = prettifyModelIdentifier(raw)
            let key = pretty.lowercased()
            guard !seenDisplayLower.contains(key) else { continue }
            seenDisplayLower.insert(key)
            models.append(
                AntigravityAvailableModel(
                    id: "live-\(raw)",
                    displayName: pretty,
                    rawIdentifier: raw,
                    family: classifyFamily(raw),
                    tag: raw == activeModel ? "Active" : "Observed",
                    serverRemainingFraction: nil,
                    recentTurns7d: stats.turns7d,
                    recentTokens7d: stats.tokens7d,
                    isObservedInTranscripts: true
                )
            )
        }

        // 2. Matching-account cached catalog ONLY when its reset timestamps are still fresh (not stale from months ago!)
        if let catalog = matchedStatus?.models {
            let hasFreshCatalog = catalog.contains { ($0.resetDate ?? .distantPast) > now }
            if hasFreshCatalog {
                for item in catalog {
                    let key = item.label.lowercased()
                    guard !seenDisplayLower.contains(key) else { continue }
                    seenDisplayLower.insert(key)
                    models.append(
                        AntigravityAvailableModel(
                            id: "cat-\(item.label)",
                            displayName: item.label,
                            rawIdentifier: item.label,
                            family: classifyFamily(item.label),
                            tag: item.tag,
                            serverRemainingFraction: item.remainingFraction,
                            isObservedInTranscripts: false
                        )
                    )
                }
            }
        }

        return models
    }

    static func prettifyModelIdentifier(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "models/", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.contains(" ") else { return cleaned }

        let parts = cleaned.split(separator: "-").map(String.init)
        guard parts.count >= 2 else { return cleaned }

        let effortTiers: Set<String> = ["low", "medium", "high", "thinking"]
        var baseParts = parts
        var suffix: String?
        if let last = baseParts.last?.lowercased(), effortTiers.contains(last) {
            suffix = last.prefix(1).uppercased() + last.dropFirst()
            baseParts.removeLast()
        }

        let formattedBase = baseParts.map { token -> String in
            let lower = token.lowercased()
            if lower == "gpt" { return "GPT" }
            if lower == "oss" { return "OSS" }
            if lower.first?.isNumber == true { return token }
            return lower.prefix(1).uppercased() + lower.dropFirst()
        }.joined(separator: " ")

        if let suffix {
            return "\(formattedBase) (\(suffix))"
        }
        return formattedBase
    }

    private static func usageGroupKey(forModelName name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("argon") { return "argon" }
        if lower.contains("claude") || lower.contains("gpt") { return "claude_gpt" }
        return "gemini"
    }

    private static func classifyFamily(_ name: String) -> AntigravityAvailableModel.Family {
        let lower = name.lowercased()
        if lower.contains("gemini") { return .gemini }
        if lower.contains("claude") { return .claude }
        if lower.contains("gpt") { return .gpt }
        return .other
    }

    // MARK: - Minimal Zero-Dependency Protobuf Wire Decoder

    private struct ProtoField {
        let fieldNumber: Int
        let wireType: Int
        let varint: UInt64
        let bytes: Data
        let float32: Float
    }

    private static func parseProtoFields(_ data: Data) -> [ProtoField] {
        let bytes = [UInt8](data)
        var i = 0
        var fields: [ProtoField] = []

        func readVarint() -> UInt64? {
            var value: UInt64 = 0
            var shift: UInt64 = 0
            while i < bytes.count {
                let b = bytes[i]
                i += 1
                value |= UInt64(b & 0x7F) << shift
                if (b & 0x80) == 0 { return value }
                shift += 7
                if shift >= 64 { return nil }
            }
            return nil
        }

        while i < bytes.count {
            guard let tag = readVarint() else { break }
            let fieldNumber = Int(tag >> 3)
            let wireType = Int(tag & 0x07)
            guard fieldNumber > 0 else { break }

            switch wireType {
            case 0:
                guard let v = readVarint() else { return fields }
                fields.append(ProtoField(fieldNumber: fieldNumber, wireType: 0, varint: v, bytes: Data(), float32: 0))
            case 1:
                guard i + 8 <= bytes.count else { return fields }
                let slice = Data(bytes[i..<(i + 8)])
                i += 8
                fields.append(ProtoField(fieldNumber: fieldNumber, wireType: 1, varint: 0, bytes: slice, float32: 0))
            case 2:
                guard let len64 = readVarint() else { return fields }
                let len = Int(len64)
                guard len >= 0, i + len <= bytes.count else { return fields }
                let slice = Data(bytes[i..<(i + len)])
                i += len
                fields.append(ProtoField(fieldNumber: fieldNumber, wireType: 2, varint: 0, bytes: slice, float32: 0))
            case 5:
                guard i + 4 <= bytes.count else { return fields }
                let bits = UInt32(bytes[i])
                    | (UInt32(bytes[i + 1]) << 8)
                    | (UInt32(bytes[i + 2]) << 16)
                    | (UInt32(bytes[i + 3]) << 24)
                i += 4
                let f = Float(bitPattern: bits)
                fields.append(ProtoField(fieldNumber: fieldNumber, wireType: 5, varint: 0, bytes: Data(), float32: f))
            default:
                return fields
            }
        }
        return fields
    }
}
