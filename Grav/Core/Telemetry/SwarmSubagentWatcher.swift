import Darwin
import Foundation

/// Event-driven watcher for an Antigravity conversation's `.system_generated/swarm/`
/// and `.system_generated/subagents/` directories.
///
/// Uses `DispatchSourceFileSystemObject` on `.system_generated/`, `swarm/`, `subagents/`,
/// and individual swarm state files (`members.json`, `plan.json`, `board.jsonl`) for
/// real-time, zero-polling updates — automatically picking up `/swarm` and `invoke_subagent`
/// invocations even when those directories are created mid-session.
public actor SwarmSubagentWatcher {
    public let sessionDirectoryURL: URL
    public let brainDirectoryURL: URL

    private let watcherQueue: DispatchQueue
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var onUpdate: (@Sendable (SwarmSubagentUpdate) -> Void)?
    private var isWatching: Bool = false
    private var lastEmitted: SwarmSubagentUpdate?

    public init(sessionDirectoryURL: URL) {
        self.sessionDirectoryURL = sessionDirectoryURL
        self.brainDirectoryURL = sessionDirectoryURL.deletingLastPathComponent()
        self.watcherQueue = DispatchQueue(
            label: "com.grav.telemetry.swarm-subagent.\(UUID().uuidString)",
            qos: .utility
        )
    }

    public func startWatching(onUpdate: @escaping @Sendable (SwarmSubagentUpdate) -> Void) {
        stopWatching()
        self.onUpdate = onUpdate
        self.isWatching = true
        refreshAndNotify(force: true)
        reconcileWatchers()
    }

    public func stopWatching() {
        isWatching = false
        onUpdate = nil
        lastEmitted = nil
        for source in sources.values {
            source.cancel()
        }
        sources.removeAll()
    }

    /// Forces an immediate rescan (e.g., when a `swarm` or `invoke_subagent` tool call is seen in transcript).
    public func triggerRefresh() {
        guard isWatching else { return }
        reconcileWatchers()
        refreshAndNotify(force: false)
    }

    // MARK: - Synchronous Snapshot Reader (Testable)

    public static func readSnapshot(
        sessionDirectoryURL: URL,
        brainDirectoryURL: URL? = nil
    ) -> SwarmSubagentUpdate {
        let brainRoot = brainDirectoryURL ?? sessionDirectoryURL.deletingLastPathComponent()
        let systemDir = sessionDirectoryURL.appendingPathComponent(".system_generated", isDirectory: true)
        let swarmDir = systemDir.appendingPathComponent("swarm", isDirectory: true)
        let subagentsDir = systemDir.appendingPathComponent("subagents", isDirectory: true)

        let swarm = parseSwarm(swarmDir: swarmDir, brainDirectoryURL: brainRoot)
        let swarmConversationIDs = Set((swarm?.members ?? []).map(\.conversationId))
        let subagents = parseSubagents(
            subagentsDir: subagentsDir,
            swarmConversationIDs: swarmConversationIDs,
            brainDirectoryURL: brainRoot
        )

        return SwarmSubagentUpdate(swarm: swarm, subagents: subagents)
    }

    // MARK: - File System Watchers

    private func reconcileWatchers() {
        guard isWatching else { return }
        let systemDir = sessionDirectoryURL.appendingPathComponent(".system_generated", isDirectory: true)
        let swarmDir = systemDir.appendingPathComponent("swarm", isDirectory: true)
        let subagentsDir = systemDir.appendingPathComponent("subagents", isDirectory: true)

        let targets: [(String, URL)] = [
            ("system", systemDir),
            ("swarm-dir", swarmDir),
            ("subagents-dir", subagentsDir),
            ("swarm-members", swarmDir.appendingPathComponent("members.json")),
            ("swarm-plan", swarmDir.appendingPathComponent("plan.json")),
            ("swarm-board", swarmDir.appendingPathComponent("board.jsonl")),
            ("swarm-meta", swarmDir.appendingPathComponent("swarm.json")),
        ]

        let fm = FileManager.default
        for (key, url) in targets {
            guard fm.fileExists(atPath: url.path) else {
                if let existing = sources.removeValue(forKey: key) {
                    existing.cancel()
                }
                continue
            }
            if sources[key] == nil {
                attachWatcher(key: key, url: url)
            }
        }
    }

    private func attachWatcher(key: String, url: URL) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let mask: DispatchSource.FileSystemEvent = [.write, .extend, .rename, .delete, .attrib]
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: mask,
            queue: watcherQueue
        )

        source.setEventHandler { [weak self] in
            let flags = source.data
            let needsReattach = flags.contains(.delete) || flags.contains(.rename)
            Task { [weak self] in
                await self?.handleFileSystemEvent(key: key, needsReattach: needsReattach)
            }
        }
        source.setCancelHandler {
            close(fd)
        }

        sources[key] = source
        source.resume()
    }

    private func handleFileSystemEvent(key: String, needsReattach: Bool) {
        guard isWatching else { return }
        if needsReattach {
            if let old = sources.removeValue(forKey: key) {
                old.cancel()
            }
        }
        reconcileWatchers()
        refreshAndNotify(force: false)
    }

    private func refreshAndNotify(force: Bool) {
        guard isWatching else { return }
        let update = Self.readSnapshot(
            sessionDirectoryURL: sessionDirectoryURL,
            brainDirectoryURL: brainDirectoryURL
        )
        if !force, update == lastEmitted {
            return
        }
        lastEmitted = update
        onUpdate?(update)
    }

    // MARK: - Swarm Directory Parsing

    private struct RawSwarmMeta: Decodable {
        let swarm_id: String?
        let created_at: String?
    }

    private struct RawMembersFile: Decodable {
        let title: String?
        let members: [String: RawMemberEntry]?
    }

    private struct RawMemberEntry: Decodable {
        let conversation_id: String?
        let role: String?
        let desired_state: String?
        let phase: String?
        let wake_mode: String?
        let killed: Bool?
        let model: String?
        let applied_model: String?
        let desired_model: String?
        let workspace_mode: String?
    }

    private struct RawPlanFile: Decodable {
        struct Goal: Decodable {
            let title: String?
            let line: String?
        }

        struct Thread: Decodable {
            let id: String?
            let title: String?
            let goal: String?
            let tasks: [String]?
        }

        let goal: Goal?
        let tasks: [String: String]?
        let threads: [Thread]?
    }

    private struct RawBoardLine: Decodable {
        let seq: Int?
        let agent: String?
        let text: String?
        let time: String?
    }

    private static func parseSwarm(swarmDir: URL, brainDirectoryURL: URL) -> SwarmSnapshot? {
        let fm = FileManager.default
        let metaURL = swarmDir.appendingPathComponent("swarm.json")
        let membersURL = swarmDir.appendingPathComponent("members.json")
        let planURL = swarmDir.appendingPathComponent("plan.json")
        let boardURL = swarmDir.appendingPathComponent("board.jsonl")

        let hasAny = fm.fileExists(atPath: metaURL.path) || fm.fileExists(atPath: membersURL.path)
        guard hasAny else { return nil }

        let decoder = JSONDecoder()

        let meta: RawSwarmMeta? = {
            guard let data = try? Data(contentsOf: metaURL) else { return nil }
            return try? decoder.decode(RawSwarmMeta.self, from: data)
        }()

        let rawMembers: RawMembersFile? = {
            guard let data = try? Data(contentsOf: membersURL) else { return nil }
            return try? decoder.decode(RawMembersFile.self, from: data)
        }()

        let rawPlan: RawPlanFile? = {
            guard let data = try? Data(contentsOf: planURL) else { return nil }
            return try? decoder.decode(RawPlanFile.self, from: data)
        }()

        // Parse board.jsonl (newest first for HUD display)
        var boardMessages: [SwarmBoardMessage] = []
        var latestByAgent: [String: String] = [:]
        if let boardData = try? Data(contentsOf: boardURL),
           let boardText = String(data: boardData, encoding: .utf8)
        {
            for line in boardText.split(whereSeparator: \.isNewline) {
                guard let lineData = line.data(using: .utf8),
                      let parsed = try? decoder.decode(RawBoardLine.self, from: lineData),
                      let seq = parsed.seq,
                      let agent = parsed.agent,
                      let text = parsed.text
                else {
                    continue
                }
                let msg = SwarmBoardMessage(
                    seq: seq,
                    agent: agent,
                    text: text,
                    timestampLabel: parsed.time
                )
                boardMessages.append(msg)
                latestByAgent[agent] = msg.previewLine
            }
        }
        boardMessages.sort { $0.seq > $1.seq }

        let planTasks = rawPlan?.tasks ?? [:]
        var members: [SwarmMember] = []
        for (name, entry) in (rawMembers?.members ?? [:]) {
            let phase = SwarmMemberPhase.parse(
                phase: entry.phase,
                desiredState: entry.desired_state,
                wakeMode: entry.wake_mode,
                killed: entry.killed
            )
            let convID = entry.conversation_id ?? name
            let liveHint: String? = (phase == .running && name.lowercased() != "coordinator")
                ? extractLiveActivityHint(conversationId: convID, brainDirectoryURL: brainDirectoryURL)
                : nil

            let member = SwarmMember(
                name: name,
                conversationId: convID,
                role: entry.role ?? (name == "coordinator" ? "coordinator" : "worker"),
                phase: phase,
                model: entry.model ?? entry.applied_model ?? entry.desired_model,
                workspaceMode: entry.workspace_mode,
                taskSummary: planTasks[name],
                lastBoardMessage: latestByAgent[name],
                liveActivityHint: liveHint
            )
            members.append(member)
        }

        // Deterministic sort: running workers first, then waiting workers, then coordinator, then done/killed
        members.sort { lhs, rhs in
            let rank: (SwarmMember) -> Int = { m in
                if m.isCoordinator { return 2 }
                switch m.phase {
                case .running: return 0
                case .waiting: return 1
                case .stopped: return 3
                case .killed: return 4
                }
            }
            let rL = rank(lhs)
            let rR = rank(rhs)
            if rL != rR { return rL < rR }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        let threads: [SwarmPlanThread] = (rawPlan?.threads ?? []).compactMap { t in
            guard let title = t.title else { return nil }
            return SwarmPlanThread(
                id: t.id ?? title,
                title: title,
                goal: t.goal ?? "",
                tasks: t.tasks ?? []
            )
        }

        let createdAt = meta?.created_at.flatMap { TranscriptDateParser.parse($0) }

        return SwarmSnapshot(
            swarmId: meta?.swarm_id ?? swarmDir.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent,
            title: rawMembers?.title,
            goalTitle: rawPlan?.goal?.title,
            goalLine: rawPlan?.goal?.line,
            members: members,
            threads: threads,
            boardMessages: boardMessages,
            createdAt: createdAt
        )
    }

    // MARK: - Subagents Directory Parsing

    private struct RawSubagentFile: Decodable {
        struct Descriptor: Decodable {
            let typeName: String?
            let role: String?
        }

        let conversationId: String?
        let subagentDescriptor: Descriptor?
        let state: String?
        let spawnStepIndex: Int?
    }

    private static func parseSubagents(
        subagentsDir: URL,
        swarmConversationIDs: Set<String>,
        brainDirectoryURL: URL
    ) -> [SubagentRecord] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: subagentsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let decoder = JSONDecoder()
        var records: [SubagentRecord] = []

        for fileURL in entries where fileURL.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: fileURL),
                  let raw = try? decoder.decode(RawSubagentFile.self, from: data)
            else {
                continue
            }

            let convID = raw.conversationId ?? fileURL.deletingPathExtension().lastPathComponent
            let parsedState = SubagentState.parse(raw.state)
            let isSwarm = swarmConversationIDs.contains(convID)
            let liveHint: String? = parsedState.isActive
                ? extractLiveActivityHint(conversationId: convID, brainDirectoryURL: brainDirectoryURL)
                : nil

            records.append(
                SubagentRecord(
                    conversationId: convID,
                    typeName: raw.subagentDescriptor?.typeName ?? "subagent",
                    role: raw.subagentDescriptor?.role ?? raw.subagentDescriptor?.typeName ?? "Subagent",
                    state: parsedState,
                    spawnStepIndex: raw.spawnStepIndex,
                    isSwarmWorker: isSwarm,
                    liveActivityHint: liveHint
                )
            )
        }

        records.sort { lhs, rhs in
            if lhs.isActive != rhs.isActive {
                return lhs.isActive && !rhs.isActive
            }
            let sL = lhs.spawnStepIndex ?? -1
            let sR = rhs.spawnStepIndex ?? -1
            if sL != sR {
                return sL > sR
            }
            return lhs.role < rhs.role
        }

        return records
    }

    /// Reads only the last ~8 KB of a running worker/subagent's `transcript.jsonl` to surface
    /// what tool or reasoning step it is currently executing with near-zero I/O overhead.
    private static func extractLiveActivityHint(
        conversationId: String,
        brainDirectoryURL: URL
    ) -> String? {
        let transcriptURL = brainDirectoryURL
            .appendingPathComponent(conversationId, isDirectory: true)
            .appendingPathComponent(".system_generated/logs/transcript.jsonl")

        guard let handle = try? FileHandle(forReadingFrom: transcriptURL) else {
            return nil
        }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        guard fileSize > 0 else { return nil }
        let readLen: UInt64 = min(fileSize, 8192)
        try? handle.seek(toOffset: fileSize - readLen)
        guard let data = try? handle.read(upToCount: Int(readLen)),
              let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        let decoder = JSONDecoder()
        let lines = text.split(whereSeparator: \.isNewline).reversed()
        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let step = try? decoder.decode(TranscriptStep.self, from: lineData)
            else {
                continue
            }
            if let call = step.toolCalls?.last {
                if call.name == "run_command" {
                    let summary = call.stringArg("toolSummary", "CommandLine") ?? "Running command"
                    return "Running: \(summary)"
                }
                if ["edit_file", "write_file", "write_to_file", "replace_file_content", "multi_replace_file_content"].contains(call.name),
                   let path = call.stringArg("Path", "TargetFile", "AbsolutePath")
                {
                    return "Editing \(URL(fileURLWithPath: path).lastPathComponent)"
                }
                if ["read_file", "view_file"].contains(call.name),
                   let path = call.stringArg("Path", "AbsolutePath")
                {
                    return "Analyzing \(URL(fileURLWithPath: path).lastPathComponent)"
                }
                return "Using \(call.name)"
            }
            if let thinking = step.thinking?.trimmingCharacters(in: .whitespacesAndNewlines), !thinking.isEmpty {
                let firstLine = thinking.replacingOccurrences(of: "\n", with: " ")
                return String(firstLine.prefix(90))
            }
        }
        return nil
    }
}
