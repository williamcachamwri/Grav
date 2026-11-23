import Foundation

/// Pure local filesystem & command telemetry inspector powering Grav's Antigravity-native modules:
/// - **Feature A2**: Quota, HTTP 429 rate-limit, capacity error & mid-session model fallback classifier.
/// - **Feature #4**: Session Artifacts, Plans, Scratch scripts & media Quick-Look scanner (`brain/<id>/`).
/// - **Feature #6**: Installed MCP servers (`~/.gemini/antigravity/mcp/`) & Background Tasks / `/schedule` monitor.
public enum AntigravityRuntimeInspector: Sendable {

    // MARK: - Feature A2: Quota, Rate-Limit, Capacity & Model Error Classifier

    /// Classifies raw error text from Antigravity's SQLite `error_details` or `transcript.jsonl`
    /// into a structured `ModelIncidentEvent`. Returns `nil` for benign or unrelated messages unless
    /// `treatUnknownAsModelError` is `true` (e.g. a failed `PLANNER_RESPONSE` step).
    public static func classifyModelError(
        rawMessage: String,
        stepIndex: Int,
        treatUnknownAsModelError: Bool = false,
        timestamp: Date = Date()
    ) -> ModelIncidentEvent? {
        let cleaned = sanitizeErrorSnippet(rawMessage)
        guard !cleaned.isEmpty else {
            guard treatUnknownAsModelError else { return nil }
            return ModelIncidentEvent(
                id: "model-err-\(stepIndex)",
                stepIndex: stepIndex,
                kind: .modelError,
                title: "Model Request Failed",
                detail: "Antigravity planner step returned an error.",
                badge: "MODEL ERR",
                shortCollapsedLabel: "Error",
                timestamp: timestamp
            )
        }

        let lowered = cleaned.lowercased()

        // 1. Quota exhausted (`RESOURCE_EXHAUSTED`, quota exceeded, usage/daily limit)
        if lowered.contains("resource_exhausted")
            || lowered.contains("quota")
            || lowered.contains("usage limit")
            || lowered.contains("daily limit")
            || lowered.contains("credit") && lowered.contains("exhaust")
            || lowered.contains("insufficient_quota")
        {
            return ModelIncidentEvent(
                id: "quota-\(stepIndex)",
                stepIndex: stepIndex,
                kind: .quotaExceeded,
                title: "Quota Exhausted",
                detail: cleaned,
                badge: "429 · QUOTA",
                shortCollapsedLabel: "Quota",
                timestamp: timestamp
            )
        }

        // 2. Rate-limited (`429`, too many requests, rate limit, throttled)
        if lowered.contains("429")
            || lowered.contains("rate limit")
            || lowered.contains("rate_limit")
            || lowered.contains("too many requests")
            || lowered.contains("throttl")
        {
            return ModelIncidentEvent(
                id: "ratelimit-\(stepIndex)",
                stepIndex: stepIndex,
                kind: .rateLimited,
                title: "Rate Limited (429)",
                detail: cleaned,
                badge: "429 · LIMIT",
                shortCollapsedLabel: "429",
                timestamp: timestamp
            )
        }

        // 3. Model capacity / overloaded (`503`, `529`, overloaded, high demand, unavailable)
        if lowered.contains("overloaded")
            || lowered.contains("capacity")
            || lowered.contains("high demand")
            || lowered.contains("model unavailable")
            || lowered.contains("service unavailable")
            || lowered.contains("temporarily unavailable")
            || lowered.contains("503")
            || lowered.contains("529")
            || lowered.contains("unavailable") && lowered.contains("model")
        {
            return ModelIncidentEvent(
                id: "capacity-\(stepIndex)",
                stepIndex: stepIndex,
                kind: .capacityExhausted,
                title: "Model Capacity Limit",
                detail: cleaned,
                badge: "CAPACITY",
                shortCollapsedLabel: "Capacity",
                timestamp: timestamp
            )
        }

        // 4. Generic planner/model failure when explicitly flagged on a planner step
        if treatUnknownAsModelError {
            return ModelIncidentEvent(
                id: "model-err-\(stepIndex)",
                stepIndex: stepIndex,
                kind: .modelError,
                title: "Model Error",
                detail: cleaned,
                badge: "MODEL ERR",
                shortCollapsedLabel: "Error",
                timestamp: timestamp
            )
        }

        return nil
    }

    /// Classifies a `TranscriptStep` for planner/system quota, rate-limit, capacity, or model errors.
    public static func classifyTranscriptStepError(_ step: TranscriptStep) -> ModelIncidentEvent? {
        let statusUpper = (step.status ?? "").uppercased()
        let typeUpper = (step.type ?? "").uppercased()
        let isPlannerOrSystem = typeUpper == "PLANNER_RESPONSE" || typeUpper == "SYSTEM_MESSAGE" || typeUpper.isEmpty
        let isErrorStatus = statusUpper == "ERROR" || statusUpper == "FAILED"

        let rawText = (step.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // Never falsely flag normal assistant replies that merely discuss quota/429 in prose
        if !isErrorStatus && typeUpper != "SYSTEM_MESSAGE" {
            return nil
        }

        if isErrorStatus && isPlannerOrSystem {
            return classifyModelError(
                rawMessage: rawText,
                stepIndex: step.stepIndex,
                treatUnknownAsModelError: true,
                timestamp: step.parsedDate
            )
        }

        // System messages reporting rate-limit / quota / capacity / model switching
        if typeUpper == "SYSTEM_MESSAGE", !rawText.isEmpty {
            return classifyModelError(
                rawMessage: rawText,
                stepIndex: step.stepIndex,
                treatUnknownAsModelError: false,
                timestamp: step.parsedDate
            )
        }

        return nil
    }

    /// Creates a structured mid-session model fallback event when Antigravity switches models cleanly.
    public static func makeModelFallbackEvent(
        from previousModel: String,
        to nextModel: String,
        stepIndex: Int,
        timestamp: Date = Date()
    ) -> ModelIncidentEvent {
        let shortFrom = shortenModelName(previousModel)
        let shortTo = shortenModelName(nextModel)
        return ModelIncidentEvent(
            id: "fallback-\(stepIndex)-\(shortTo)",
            stepIndex: stepIndex,
            kind: .modelFallback(from: shortFrom, to: shortTo),
            title: "Model Switched",
            detail: "\(shortFrom) → \(shortTo)",
            badge: "FALLBACK",
            shortCollapsedLabel: "Fallback",
            timestamp: timestamp
        )
    }

    private static func shortenModelName(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "models/", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitizeErrorSnippet(_ raw: String) -> String {
        let collapsed = raw
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > 140 else { return collapsed }
        return String(collapsed.prefix(139)) + "…"
    }

    // MARK: - Feature #4: Session Artifacts, Plans & Scratch Quick-Look Scanner

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "gif", "heic"]
    private static let docExtensions: Set<String> = ["md", "markdown", "txt", "pdf", "json", "yaml", "yml"]
    private static let scriptExtensions: Set<String> = ["sh", "zsh", "py", "swift", "ts", "js", "rb", "sql"]

    /// Scans `~/.gemini/antigravity/brain/<session-id>/` (root artifacts, `scratch/`, `.user_uploaded/`,
    /// and browser/generated images) returning items sorted newest-first.
    public static func scanSessionArtifacts(
        sessionDirectoryURL: URL,
        limit: Int = 60
    ) -> [SessionArtifactItem] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionDirectoryURL.path) else { return [] }

        var items: [SessionArtifactItem] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]

        func appendFile(_ url: URL, relativePrefix: String, forcedKind: SessionArtifactItem.Kind? = nil) {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true
            else { return }
            let name = url.lastPathComponent
            if name.hasPrefix(".") { return }
            let ext = url.pathExtension.lowercased()
            let size = Int64(values.fileSize ?? 0)
            let modified = values.contentModificationDate ?? .distantPast

            let kind: SessionArtifactItem.Kind = {
                if let forcedKind { return forcedKind }
                if imageExtensions.contains(ext) { return .image }
                if docExtensions.contains(ext) { return .planDocument }
                if scriptExtensions.contains(ext) { return .scratchScript }
                return .file
            }()

            let rel = relativePrefix.isEmpty ? name : "\(relativePrefix)/\(name)"
            items.append(
                SessionArtifactItem(
                    url: url,
                    name: name,
                    relativePath: rel,
                    kind: kind,
                    fileSize: size,
                    modifiedAt: modified
                )
            )
        }

        // 1. Root artifacts (plans, walkthroughs, implementation notes, exported images)
        if let rootEntries = try? fm.contentsOfDirectory(
            at: sessionDirectoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) {
            for url in rootEntries {
                appendFile(url, relativePrefix: "")
            }
        }

        // 2. `scratch/` helper scripts & intermediate files
        let scratchURL = sessionDirectoryURL.appendingPathComponent("scratch", isDirectory: true)
        if let scratchEntries = try? fm.contentsOfDirectory(
            at: scratchURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) {
            for url in scratchEntries {
                let ext = url.pathExtension.lowercased()
                let kind: SessionArtifactItem.Kind = imageExtensions.contains(ext) ? .image : .scratchScript
                appendFile(url, relativePrefix: "scratch", forcedKind: kind)
            }
        }

        // 3. `.user_uploaded/` attachments & screenshots
        let uploadedURL = sessionDirectoryURL.appendingPathComponent(".user_uploaded", isDirectory: true)
        if let uploadedEntries = try? fm.contentsOfDirectory(
            at: uploadedURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) {
            for url in uploadedEntries {
                appendFile(url, relativePrefix: "attachments")
            }
        }

        // 4. `browser_sandbox/` screenshots if present
        let browserSandboxURL = sessionDirectoryURL.appendingPathComponent("browser_sandbox", isDirectory: true)
        if let browserEntries = try? fm.contentsOfDirectory(
            at: browserSandboxURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) {
            for url in browserEntries {
                let ext = url.pathExtension.lowercased()
                if imageExtensions.contains(ext) {
                    appendFile(url, relativePrefix: "browser", forcedKind: .image)
                }
            }
        }

        items.sort { $0.modifiedAt > $1.modifiedAt }
        if items.count > limit {
            return Array(items.prefix(limit))
        }
        return items
    }

    // MARK: - Feature #6: Installed MCP Servers & Background Tasks / Schedules

    /// Scans `~/.gemini/antigravity/mcp/` for installed MCP servers and their lazy-loaded tool schemas.
    public static func scanInstalledMCPServers(antigravityRootURL: URL) -> [MCPServerSummary] {
        let mcpRoot = antigravityRootURL.appendingPathComponent("mcp", isDirectory: true)
        let fm = FileManager.default
        guard let serverDirs = try? fm.contentsOfDirectory(
            at: mcpRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var summaries: [MCPServerSummary] = []
        for dir in serverDirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let files = (try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            let toolNames = files
                .filter { $0.pathExtension.lowercased() == "json" }
                .map { $0.deletingPathExtension().lastPathComponent }
                .sorted()
            summaries.append(
                MCPServerSummary(
                    name: dir.lastPathComponent,
                    toolCount: toolNames.count,
                    sampleTools: Array(toolNames.prefix(6)),
                    directoryURL: dir
                )
            )
        }
        return summaries.sorted { $0.toolCount > $1.toolCount }
    }

    /// Synthesizes active & recent background tasks, daemons, and `/schedule` timers/crons from
    /// `.system_generated/tasks/*.log`, running commands, and schedule activity entries.
    public static func buildScheduledTaskRecords(
        tasksDirectoryURL: URL,
        commands: [CommandExecutionEvent],
        recentActivity: [TelemetryActivityItem],
        limit: Int = 24
    ) -> [ScheduledTaskRecord] {
        var recordsByID: [String: ScheduledTaskRecord] = [:]

        // 1. Background shell commands & daemons tracked in telemetry
        for cmd in commands {
            guard cmd.taskLogURL != nil || cmd.status == .running else { continue }
            let key = cmd.taskLogURL?.deletingPathExtension().lastPathComponent ?? cmd.id
            let lowerCmd = cmd.commandLine.lowercased()
            let looksLikeDaemon = lowerCmd.contains("dev") || lowerCmd.contains("watch") || lowerCmd.contains("server") || lowerCmd.contains("serve")
            let kind: ScheduledTaskRecord.Kind = looksLikeDaemon ? .daemon : .backgroundTask
            let mappedStatus: ToolExecutionStatus = {
                switch cmd.status {
                case .running: return .running
                case .succeeded: return .succeeded
                case .failed: return .failed
                }
            }()
            recordsByID[key] = ScheduledTaskRecord(
                id: key,
                title: cmd.displayTitle,
                kind: kind,
                status: mappedStatus,
                detail: cmd.commandLine,
                logURL: cmd.taskLogURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil },
                updatedAt: cmd.completedAt ?? cmd.startedAt
            )
        }

        // 2. Scheduled timers / crons emitted in recent activity (`schedule` tool)
        for item in recentActivity {
            guard case let .toolActivity(ev) = item else { continue }
            let lowerName = ev.toolName.lowercased()
            let lowerTitle = ev.title.lowercased()
            let lowerDetail = (ev.detail ?? "").lowercased()
            let isSchedule = lowerName == "schedule" || lowerName == "manage_task"
                || lowerTitle.contains("schedule") || lowerTitle.contains("cron") || lowerTitle.contains("timer")
                || lowerDetail.contains("cron")
            guard isSchedule else { continue }
            let kind: ScheduledTaskRecord.Kind = (lowerDetail.contains("cron") || lowerTitle.contains("cron")) ? .cron : .timer
            recordsByID["sched-\(ev.id)"] = ScheduledTaskRecord(
                id: "sched-\(ev.id)",
                title: ev.title,
                kind: kind,
                status: ev.status,
                detail: ev.detail ?? ev.toolName,
                logURL: nil,
                updatedAt: ev.timestamp
            )
        }

        // 3. Any additional task log files on disk in `.system_generated/tasks/`
        let fm = FileManager.default
        if let logFiles = try? fm.contentsOfDirectory(
            at: tasksDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            let recentLogs = logFiles
                .filter { $0.pathExtension.lowercased() == "log" }
                .sorted { a, b in
                    let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return da > db
                }
                .prefix(12)

            for logURL in recentLogs {
                let taskKey = logURL.deletingPathExtension().lastPathComponent
                let alreadyTracked = recordsByID.keys.contains { $0 == taskKey || $0.hasSuffix("/\(taskKey)") }
                if alreadyTracked { continue }

                let values = try? logURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let modified = values?.contentModificationDate ?? .distantPast
                let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(values?.fileSize ?? 0), countStyle: .file)
                recordsByID[taskKey] = ScheduledTaskRecord(
                    id: taskKey,
                    title: taskKey,
                    kind: .backgroundTask,
                    status: .succeeded,
                    detail: "Task log · \(sizeStr)",
                    logURL: logURL,
                    updatedAt: modified
                )
            }
        }

        let sorted = recordsByID.values.sorted { a, b in
            if a.status == .running && b.status != .running { return true }
            if a.status != .running && b.status == .running { return false }
            return a.updatedAt > b.updatedAt
        }
        return Array(sorted.prefix(limit))
    }
}
