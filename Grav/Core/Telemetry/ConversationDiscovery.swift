import Darwin
import Foundation

/// Event-driven watcher for `~/.gemini/antigravity/brain/` that discovers Antigravity conversation
/// directories containing `.system_generated/logs/transcript.jsonl`, extracts readable session titles,
/// sorts sessions by most recent transcript modification, and emits updates with zero idle polling.
public actor ConversationDiscovery {
    public let brainDirectoryURL: URL

    private let maxTranscriptWatchers: Int
    private let watcherQueue: DispatchQueue
    private let decoder: JSONDecoder

    private var brainDirSource: DispatchSourceFileSystemObject?
    private var pendingDirSources: [String: DispatchSourceFileSystemObject] = [:]
    private var transcriptSources: [String: DispatchSourceFileSystemObject] = [:]
    private var cachedTitles: [String: String] = [:]
    private var lastSessions: [ConversationSession] = []
    private var onUpdateHandler: (@Sendable ([ConversationSession]) -> Void)?
    private var isWatching: Bool = false

    public init(
        brainDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity/brain", isDirectory: true),
        maxTranscriptWatchers: Int = 16
    ) {
        self.brainDirectoryURL = brainDirectoryURL
        self.maxTranscriptWatchers = max(1, maxTranscriptWatchers)
        self.watcherQueue = DispatchQueue(
            label: "com.grav.telemetry.conversation-discovery.\(UUID().uuidString)",
            qos: .utility
        )
        self.decoder = JSONDecoder()
    }

    /// Synchronously scans `brainDirectoryURL` for conversation directories that contain
    /// `.system_generated/logs/transcript.jsonl`, sorted by transcript modification date descending.
    public func scanConversations() -> [ConversationSession] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: brainDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var discovered: [ConversationSession] = []
        discovered.reserveCapacity(entries.count)

        for entryURL in entries {
            guard let values = try? entryURL.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true
            else {
                continue
            }

            let sessionID = entryURL.lastPathComponent
            let candidate = ConversationSession(id: sessionID, directoryURL: entryURL)

            guard let attrs = try? fm.attributesOfItem(atPath: candidate.transcriptURL.path) else {
                continue
            }

            let modifiedDate = (attrs[.modificationDate] as? Date) ?? Date.distantPast
            let title: String
            if let cached = cachedTitles[sessionID] {
                title = cached
            } else {
                let extracted = Self.extractSessionTitle(
                    from: candidate.transcriptURL,
                    fallbackID: sessionID,
                    decoder: decoder
                )
                // Cache only once a meaningful title is found or transcript is non-empty
                let fileSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
                if fileSize > 0 {
                    cachedTitles[sessionID] = extracted
                }
                title = extracted
            }

            var session = candidate
            session.title = title
            session.lastModified = modifiedDate
            discovered.append(session)
        }

        discovered.sort { lhs, rhs in
            if lhs.lastModified != rhs.lastModified {
                return lhs.lastModified > rhs.lastModified
            }
            return lhs.id < rhs.id
        }

        return discovered
    }

    /// Starts event-driven watching on `brainDirectoryURL` and the most recent conversation transcripts.
    public func startWatching(onUpdate: @escaping @Sendable ([ConversationSession]) -> Void) {
        stopWatching()
        self.onUpdateHandler = onUpdate
        self.isWatching = true

        refreshAndNotify(forceNotify: true)
        attachBrainDirectoryWatcher()
    }

    /// Stops all directory and transcript `DispatchSource` watchers and releases file descriptors.
    public func stopWatching() {
        isWatching = false
        onUpdateHandler = nil

        brainDirSource?.cancel()
        brainDirSource = nil

        for source in pendingDirSources.values {
            source.cancel()
        }
        pendingDirSources.removeAll()

        for source in transcriptSources.values {
            source.cancel()
        }
        transcriptSources.removeAll()
    }

    // MARK: - Title Extraction

    /// Extracts a clean human-readable title from the first `USER_INPUT` step in `transcript.jsonl`,
    /// falling back to a workspace path basename or the short 8-character conversation ID prefix.
    public static func extractSessionTitle(
        from transcriptURL: URL,
        fallbackID: String,
        decoder: JSONDecoder = JSONDecoder()
    ) -> String {
        guard let handle = try? FileHandle(forReadingFrom: transcriptURL) else {
            return String(fallbackID.prefix(8))
        }
        defer {
            try? handle.close()
        }

        // Read at most the first 64 KB to keep discovery instant and memory-light
        guard let prefixData = try? handle.read(upToCount: 65_536), !prefixData.isEmpty else {
            return String(fallbackID.prefix(8))
        }

        let newline: UInt8 = 0x0A
        var lineStart = prefixData.startIndex
        var fallbackWorkspaceTitle: String?
        var inspectedLines = 0

        while lineStart < prefixData.endIndex, inspectedLines < 40 {
            let lineEnd = prefixData[lineStart..<prefixData.endIndex].firstIndex(of: newline) ?? prefixData.endIndex
            let lineData = Data(prefixData[lineStart..<lineEnd])
            lineStart = lineEnd < prefixData.endIndex ? prefixData.index(after: lineEnd) : prefixData.endIndex
            inspectedLines += 1

            guard !lineData.isEmpty,
                  let step = try? decoder.decode(TranscriptStep.self, from: lineData)
            else {
                continue
            }

            if step.type == "USER_INPUT", let content = step.content {
                let cleaned = cleanUserPromptSnippet(content)
                if !cleaned.isEmpty {
                    return cleaned
                }
            }

            if fallbackWorkspaceTitle == nil, let toolCalls = step.toolCalls {
                for call in toolCalls {
                    if let path = call.stringArg("Path", "TargetFile"), path.hasPrefix("/") {
                        let parentName = URL(fileURLWithPath: path)
                            .deletingLastPathComponent()
                            .lastPathComponent
                        if !parentName.isEmpty && parentName != "/" {
                            fallbackWorkspaceTitle = parentName
                            break
                        }
                    }
                }
            }
        }

        if let workspace = fallbackWorkspaceTitle {
            return workspace
        }
        return String(fallbackID.prefix(8))
    }

    internal static func cleanUserPromptSnippet(_ raw: String, maxLength: Int = 60) -> String {
        var text = raw

        // Extract content inside <USER_REQUEST>...</USER_REQUEST> when present
        if let openRange = text.range(of: "<USER_REQUEST>") {
            let afterOpen = text[openRange.upperBound...]
            if let closeRange = afterOpen.range(of: "</USER_REQUEST>") {
                text = String(afterOpen[..<closeRange.lowerBound])
            } else {
                text = String(afterOpen)
            }
        } else if let metaRange = text.range(of: "<ADDITIONAL_METADATA>") {
            text = String(text[..<metaRange.lowerBound])
        }

        // Collapse markdown bold/backticks and whitespace into a single readable line
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: "`", with: "")

        let components = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let singleLine = components.joined(separator: " ")
        guard !singleLine.isEmpty else { return "" }

        if singleLine.count <= maxLength {
            return singleLine
        }

        let endIdx = singleLine.index(singleLine.startIndex, offsetBy: maxLength - 1)
        return String(singleLine[..<endIdx]).trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: - Event-Driven Watchers

    private func refreshAndNotify(forceNotify: Bool) {
        let sessions = scanConversations()
        syncPendingDirectoryWatchers(discoveredIDs: Set(sessions.map(\.id)))
        syncTranscriptWatchers(for: sessions)

        if forceNotify || sessions != lastSessions {
            lastSessions = sessions
            onUpdateHandler?(sessions)
        }
    }

    private func attachBrainDirectoryWatcher() {
        brainDirSource?.cancel()
        brainDirSource = nil
        guard isWatching else { return }

        let fd = open(brainDirectoryURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .link, .rename, .delete],
            queue: watcherQueue
        )

        source.setEventHandler { [weak self] in
            let rawFlags = source.data.rawValue
            Task { [weak self] in
                await self?.handleBrainDirectoryEvent(rawFlags: rawFlags)
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        brainDirSource = source
        source.resume()
    }

    private func handleBrainDirectoryEvent(rawFlags: UInt) {
        guard isWatching else { return }
        let flags = DispatchSource.FileSystemEvent(rawValue: rawFlags)
        if flags.contains(.delete) || flags.contains(.rename) {
            attachBrainDirectoryWatcher()
        }
        refreshAndNotify(forceNotify: false)
    }

    /// Watches newly created conversation directories whose `.system_generated/logs/transcript.jsonl`
    /// has not been created yet so we detect the transcript the moment it appears without polling.
    private func syncPendingDirectoryWatchers(discoveredIDs: Set<String>) {
        guard isWatching else { return }

        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: brainDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        var desiredPending: [String: URL] = [:]
        for entryURL in entries {
            let id = entryURL.lastPathComponent
            guard !discoveredIDs.contains(id) else { continue }
            guard let values = try? entryURL.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true
            else {
                continue
            }
            // Watch the deepest existing directory along `<uuid>/.system_generated/logs`
            let logsDir = entryURL
                .appendingPathComponent(".system_generated", isDirectory: true)
                .appendingPathComponent("logs", isDirectory: true)
            let sysDir = entryURL.appendingPathComponent(".system_generated", isDirectory: true)
            if fm.fileExists(atPath: logsDir.path) {
                desiredPending[id] = logsDir
            } else if fm.fileExists(atPath: sysDir.path) {
                desiredPending[id] = sysDir
            } else if UUID(uuidString: id) != nil {
                desiredPending[id] = entryURL
            }
        }

        // Remove obsolete pending watchers
        for (id, source) in pendingDirSources where desiredPending[id] == nil {
            source.cancel()
            pendingDirSources.removeValue(forKey: id)
        }

        // Attach watchers for new pending directories (capped at 8)
        for (id, watchURL) in desiredPending.prefix(8) where pendingDirSources[id] == nil {
            let fd = open(watchURL.path, O_EVTONLY)
            guard fd >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .link, .rename],
                queue: watcherQueue
            )
            source.setEventHandler { [weak self] in
                Task { [weak self] in
                    await self?.handlePendingDirectoryEvent(sessionID: id)
                }
            }
            source.setCancelHandler {
                close(fd)
            }
            pendingDirSources[id] = source
            source.resume()
        }
    }

    private func handlePendingDirectoryEvent(sessionID: String) {
        guard isWatching else { return }
        if let existing = pendingDirSources.removeValue(forKey: sessionID) {
            existing.cancel()
        }
        refreshAndNotify(forceNotify: false)
    }

    /// Attaches lightweight `O_EVTONLY` watchers to the most recently active conversation transcripts
    /// so cross-session activity immediately re-sorts the session list without polling.
    private func syncTranscriptWatchers(for sessions: [ConversationSession]) {
        guard isWatching else { return }

        let targetSessions = Array(sessions.prefix(maxTranscriptWatchers))
        let targetIDs = Set(targetSessions.map(\.id))

        for (id, source) in transcriptSources where !targetIDs.contains(id) {
            source.cancel()
            transcriptSources.removeValue(forKey: id)
        }

        for session in targetSessions where transcriptSources[session.id] == nil {
            let fd = open(session.transcriptURL.path, O_EVTONLY)
            guard fd >= 0 else { continue }

            let sessionID = session.id
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .rename, .delete],
                queue: watcherQueue
            )
            source.setEventHandler { [weak self] in
                let rawFlags = source.data.rawValue
                Task { [weak self] in
                    await self?.handleTranscriptActivity(sessionID: sessionID, rawFlags: rawFlags)
                }
            }
            source.setCancelHandler {
                close(fd)
            }
            transcriptSources[sessionID] = source
            source.resume()
        }
    }

    private func handleTranscriptActivity(sessionID: String, rawFlags: UInt) {
        guard isWatching else { return }
        let flags = DispatchSource.FileSystemEvent(rawValue: rawFlags)
        if flags.contains(.delete) || flags.contains(.rename) {
            if let existing = transcriptSources.removeValue(forKey: sessionID) {
                existing.cancel()
            }
        }
        // Invalidate cached title if it was previously just the short UUID prefix
        if let cached = cachedTitles[sessionID], cached == String(sessionID.prefix(8)) {
            cachedTitles.removeValue(forKey: sessionID)
        }
        refreshAndNotify(forceNotify: false)
    }
}
