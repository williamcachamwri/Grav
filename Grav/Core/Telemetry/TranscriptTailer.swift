import Darwin
import Foundation

/// Dedicated Swift `actor` that incrementally tails an Antigravity `transcript.jsonl` file
/// from a maintained byte offset using kernel `kqueue` file-system events (`DispatchSource`).
public actor TranscriptTailer {
    public let transcriptURL: URL
    public private(set) var byteOffset: UInt64

    private let offsetStoreKey: String?
    private let watcherQueue: DispatchQueue
    private let decoder: JSONDecoder

    private var source: DispatchSourceFileSystemObject?
    private var directorySource: DispatchSourceFileSystemObject?
    private var watchedInode: UInt64?
    private var onStepsHandler: (@Sendable ([TranscriptStep]) -> Void)?
    private var isWatching: Bool = false

    public init(
        transcriptURL: URL,
        initialOffset: UInt64? = nil,
        offsetStoreKey: String? = nil
    ) {
        self.transcriptURL = transcriptURL
        self.offsetStoreKey = offsetStoreKey
        self.watcherQueue = DispatchQueue(
            label: "com.grav.telemetry.transcript-tailer.\(UUID().uuidString)",
            qos: .utility
        )
        self.decoder = JSONDecoder()

        if let initialOffset {
            self.byteOffset = initialOffset
        } else if let offsetStoreKey,
                  let persisted = UserDefaults.standard.object(forKey: offsetStoreKey) as? NSNumber
        {
            self.byteOffset = persisted.uint64Value
        } else {
            self.byteOffset = 0
        }
    }

    /// Reads all newly appended complete JSONL `TranscriptStep` lines since `byteOffset`.
    /// Automatically resets `byteOffset` to `0` if the file was truncated or rotated to a smaller size.
    public func readNewSteps() -> [TranscriptStep] {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: transcriptURL.path),
              let fileSizeNumber = attributes[.size] as? NSNumber
        else {
            return []
        }

        let fileSize = fileSizeNumber.uint64Value
        let currentInode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value

        // Reset byteOffset to 0 only when the file shrinks (true truncation or rotation to a new shorter transcript).
        // Atomic rename-writes that extend the transcript preserve the prefix bytes and only append at the tail.
        if fileSize < byteOffset {
            byteOffset = 0
            persistOffset()
        }
        watchedInode = currentInode

        guard fileSize > byteOffset else {
            return []
        }

        guard let handle = try? FileHandle(forReadingFrom: transcriptURL) else {
            return []
        }
        defer {
            try? handle.close()
        }

        do {
            try handle.seek(toOffset: byteOffset)
            guard let chunk = try handle.readToEnd(), !chunk.isEmpty else {
                return []
            }
            return parseSteps(from: chunk)
        } catch {
            return []
        }
    }

    /// Begins event-driven watching of `transcriptURL` via `DispatchSource.makeFileSystemObjectSource`,
    /// performing an initial catch-up read and invoking `onSteps` whenever new steps arrive.
    public func startWatching(onSteps: @escaping @Sendable ([TranscriptStep]) -> Void) {
        stopWatching()
        self.onStepsHandler = onSteps
        self.isWatching = true

        let initialSteps = readNewSteps()
        if !initialSteps.isEmpty {
            onSteps(initialSteps)
        }

        attachFileSystemSource()
        attachParentDirectorySource()
    }

    /// Stops watching and releases the underlying file descriptor and `DispatchSource`.
    public func stopWatching() {
        isWatching = false
        onStepsHandler = nil
        cancelSource()
        cancelDirectorySource()
    }

    /// Resets the tailer offset back to the beginning of the file.
    public func resetOffset() {
        byteOffset = 0
        persistOffset()
    }

    /// Scans `transcript_full.jsonl` on demand for a specific `step_index` without loading
    /// the entire full transcript into memory at once.
    public func readFullStep(stepIndex: Int, from fullTranscriptURL: URL? = nil) -> TranscriptStep? {
        let targetURL = fullTranscriptURL ?? transcriptURL
            .deletingLastPathComponent()
            .appendingPathComponent("transcript_full.jsonl")
        return Self.readFullStep(stepIndex: stepIndex, from: targetURL)
    }

    /// Streaming lookup of a specific `step_index` in `transcript_full.jsonl`.
    public static func readFullStep(stepIndex: Int, from fullTranscriptURL: URL) -> TranscriptStep? {
        guard let handle = try? FileHandle(forReadingFrom: fullTranscriptURL) else {
            return nil
        }
        defer {
            try? handle.close()
        }

        let decoder = JSONDecoder()
        let chunkSize = 65_536
        let newline: UInt8 = 0x0A
        let indexNeedleCompact = Data("\"step_index\":\(stepIndex)".utf8)
        let indexNeedleSpaced = Data("\"step_index\": \(stepIndex)".utf8)

        var pending = Data()

        func decodeIfMatching(_ lineData: Data) -> TranscriptStep? {
            guard !lineData.isEmpty else { return nil }
            // Fast pre-filter before full JSON decoding of potentially large full-transcript lines
            guard lineData.range(of: indexNeedleCompact) != nil ||
                  lineData.range(of: indexNeedleSpaced) != nil
            else {
                return nil
            }
            guard let step = try? decoder.decode(TranscriptStep.self, from: lineData),
                  step.stepIndex == stepIndex
            else {
                return nil
            }
            return step
        }

        while true {
            guard let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty else {
                break
            }
            pending.append(chunk)

            var searchStart = pending.startIndex
            while let newlineIdx = pending[searchStart..<pending.endIndex].firstIndex(of: newline) {
                let lineData = Data(pending[searchStart..<newlineIdx])
                if let matched = decodeIfMatching(lineData) {
                    return matched
                }
                searchStart = pending.index(after: newlineIdx)
            }

            if searchStart > pending.startIndex {
                pending.removeSubrange(pending.startIndex..<searchStart)
            }
        }

        if !pending.isEmpty {
            return decodeIfMatching(pending)
        }
        return nil
    }

    // MARK: - Line Parsing

    private func parseSteps(from data: Data) -> [TranscriptStep] {
        var steps: [TranscriptStep] = []
        var consumedBytes: UInt64 = 0
        let newline: UInt8 = 0x0A

        var lineStart = data.startIndex
        let endIndex = data.endIndex

        while lineStart < endIndex {
            if let newlineIndex = data[lineStart..<endIndex].firstIndex(of: newline) {
                let lineSlice = data[lineStart..<newlineIndex]
                let byteLength = UInt64(data.distance(from: lineStart, to: newlineIndex) + 1)
                consumedBytes += byteLength

                if let step = decodeLine(lineSlice) {
                    steps.append(step)
                }
                lineStart = data.index(after: newlineIndex)
            } else {
                // Trailing bytes without a newline: decode only if already a complete JSON object;
                // otherwise leave `byteOffset` before this partial line until the writer finishes flushing.
                let trailingSlice = data[lineStart..<endIndex]
                if let step = decodeLine(trailingSlice) {
                    steps.append(step)
                    consumedBytes += UInt64(data.distance(from: lineStart, to: endIndex))
                }
                break
            }
        }

        if consumedBytes > 0 {
            byteOffset += consumedBytes
            persistOffset()
        }

        return steps
    }

    private func decodeLine(_ slice: Data.SubSequence) -> TranscriptStep? {
        // Trim whitespace and CR without allocating unnecessarily for empty lines
        var start = slice.startIndex
        var end = slice.endIndex
        while start < end, isASCIIWhitespace(slice[start]) {
            start = slice.index(after: start)
        }
        while end > start, isASCIIWhitespace(slice[slice.index(before: end)]) {
            end = slice.index(before: end)
        }
        guard start < end else { return nil }

        let trimmed = Data(slice[start..<end])
        return try? decoder.decode(TranscriptStep.self, from: trimmed)
    }

    private func isASCIIWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0D || byte == 0x0A
    }

    private func persistOffset() {
        guard let offsetStoreKey else { return }
        UserDefaults.standard.set(NSNumber(value: byteOffset), forKey: offsetStoreKey)
    }

    // MARK: - kqueue DispatchSource Management

    private func attachFileSystemSource() {
        cancelSource()
        guard isWatching else { return }

        let fd = open(transcriptURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        if let attributes = try? FileManager.default.attributesOfItem(atPath: transcriptURL.path),
           let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        {
            watchedInode = inode
        }

        let eventMask: DispatchSource.FileSystemEvent = [.write, .extend, .delete, .rename, .revoke, .attrib]
        let dispatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: eventMask,
            queue: watcherQueue
        )

        dispatchSource.setEventHandler { [weak self] in
            let rawFlags = dispatchSource.data.rawValue
            Task { [weak self] in
                await self?.handleFileSystemEvent(rawFlags: rawFlags)
            }
        }

        dispatchSource.setCancelHandler {
            close(fd)
        }

        self.source = dispatchSource
        dispatchSource.resume()
    }

    private func cancelSource() {
        if let existing = source {
            source = nil
            existing.cancel()
        }
    }

    private func attachParentDirectorySource() {
        cancelDirectorySource()
        guard isWatching else { return }

        let parentPath = transcriptURL.deletingLastPathComponent().path
        let dirFD = open(parentPath, O_EVTONLY)
        guard dirFD >= 0 else { return }

        let dirSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFD,
            eventMask: [.write, .extend, .rename],
            queue: watcherQueue
        )

        dirSource.setEventHandler { [weak self] in
            Task { [weak self] in
                await self?.handleParentDirectoryEvent()
            }
        }

        dirSource.setCancelHandler {
            close(dirFD)
        }

        self.directorySource = dirSource
        dirSource.resume()
    }

    private func cancelDirectorySource() {
        if let existing = directorySource {
            directorySource = nil
            existing.cancel()
        }
    }

    private func handleParentDirectoryEvent() {
        guard isWatching else { return }

        // If the file was atomically replaced (new inode) or newly created, re-bind the file watcher
        if let attributes = try? FileManager.default.attributesOfItem(atPath: transcriptURL.path),
           let currentInode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        {
            if source == nil || (watchedInode != nil && watchedInode != currentInode) {
                attachFileSystemSource()
            }
        }

        let steps = readNewSteps()
        if !steps.isEmpty, let handler = onStepsHandler {
            handler(steps)
        }
    }

    private func handleFileSystemEvent(rawFlags: UInt) {
        guard isWatching else { return }
        let flags = DispatchSource.FileSystemEvent(rawValue: rawFlags)

        if flags.contains(.delete) || flags.contains(.rename) || flags.contains(.revoke) {
            // File was atomically replaced; re-attach to the new vnode while keeping byteOffset
            // (readNewSteps() automatically resets byteOffset to 0 if the replacement file is smaller).
            watchedInode = nil
            attachFileSystemSource()
        }

        let steps = readNewSteps()
        if !steps.isEmpty, let handler = onStepsHandler {
            handler(steps)
        }
    }
}

/// Streaming write signal from Antigravity's live conversation WAL.
public struct WALActivityPulse: Sendable, Equatable {
    public let deltaBytes: Int64
    /// True when multiple consecutive WAL growth frames arrive in rapid succession
    /// (the signature of active token-by-token reply streaming).
    public let isRapidStreamingBurst: Bool

    public init(deltaBytes: Int64, isRapidStreamingBurst: Bool) {
        self.deltaBytes = deltaBytes
        self.isRapidStreamingBurst = isRapidStreamingBurst
    }
}

/// Event-driven `O_EVTONLY` kernel watcher on Antigravity's live conversation WAL file
/// (`~/.gemini/antigravity/conversations/<session-id>.db-wal`).
public actor ConversationWALWatcher {
    public let walURL: URL
    public let summariesWALURL: URL

    private let watcherQueue: DispatchQueue
    private var fileSource: DispatchSourceFileSystemObject?
    private var summariesSource: DispatchSourceFileSystemObject?
    private var dirSource: DispatchSourceFileSystemObject?
    private var onPulse: (@Sendable (WALActivityPulse) -> Void)?
    private var lastWALSize: UInt64 = 0
    private var recentGrowthTimes: [Date] = []
    private var isWatching: Bool = false

    public init(session: ConversationSession) {
        let antigravityRoot = session.directoryURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        self.walURL = antigravityRoot
            .appendingPathComponent("conversations", isDirectory: true)
            .appendingPathComponent("\(session.id).db-wal")
        self.summariesWALURL = antigravityRoot
            .appendingPathComponent("conversation_summaries.db-wal")
        self.watcherQueue = DispatchQueue(
            label: "com.grav.telemetry.wal-pulse.\(UUID().uuidString)",
            qos: .utility
        )
    }

    public func startWatching(onPulse: @escaping @Sendable (WALActivityPulse) -> Void) {
        stopWatching()
        self.onPulse = onPulse
        self.isWatching = true
        self.lastWALSize = currentWALFileSize()
        self.recentGrowthTimes.removeAll()
        attachFileSource()
        attachSummariesSource()
        attachDirectorySource()
    }

    public func stopWatching() {
        isWatching = false
        onPulse = nil
        lastWALSize = 0
        recentGrowthTimes.removeAll()
        fileSource?.cancel()
        fileSource = nil
        summariesSource?.cancel()
        summariesSource = nil
        dirSource?.cancel()
        dirSource = nil
    }

    private func currentWALFileSize() -> UInt64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: walURL.path),
              let num = attrs[.size] as? NSNumber
        else {
            return 0
        }
        return num.uint64Value
    }

    private func attachFileSource() {
        fileSource?.cancel()
        fileSource = nil
        guard isWatching else { return }

        let fd = open(walURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: watcherQueue
        )
        source.setEventHandler { [weak self] in
            let flags = source.data
            let replaced = flags.contains(.rename) || flags.contains(.delete)
            Task { [weak self] in
                await self?.handleWALEvent(replaced: replaced)
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        fileSource = source
        source.resume()
    }

    private func attachSummariesSource() {
        summariesSource?.cancel()
        summariesSource = nil
        guard isWatching else { return }

        let fd = open(summariesWALURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: watcherQueue
        )
        source.setEventHandler { [weak self] in
            let flags = source.data
            let replaced = flags.contains(.rename) || flags.contains(.delete)
            Task { [weak self] in
                await self?.handleSummariesWALEvent(replaced: replaced)
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        summariesSource = source
        source.resume()
    }

    private func handleSummariesWALEvent(replaced: Bool) {
        guard isWatching else { return }
        if replaced {
            attachSummariesSource()
        }
        // Emit a zero-delta probe pulse so `AntigravityTelemetryStore` immediately reads
        // `conversation_summaries.db` + `conversations/<id>.db` on any run-state transition.
        onPulse?(WALActivityPulse(deltaBytes: 0, isRapidStreamingBurst: false))
    }

    private func attachDirectorySource() {
        dirSource?.cancel()
        dirSource = nil
        guard isWatching else { return }

        let parentPath = walURL.deletingLastPathComponent().path
        let fd = open(parentPath, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: watcherQueue
        )
        source.setEventHandler { [weak self] in
            Task { [weak self] in
                await self?.handleDirectoryEvent()
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        dirSource = source
        source.resume()
    }

    private func handleDirectoryEvent() {
        guard isWatching else { return }
        if fileSource == nil, FileManager.default.fileExists(atPath: walURL.path) {
            attachFileSource()
            emitGrowthIfNeeded()
        }
    }

    private func handleWALEvent(replaced: Bool) {
        guard isWatching else { return }
        if replaced {
            attachFileSource()
        }
        emitGrowthIfNeeded()
    }

    private func emitGrowthIfNeeded() {
        let newSize = currentWALFileSize()
        let delta: Int64 = newSize > lastWALSize ? Int64(newSize - lastWALSize) : 0
        lastWALSize = newSize
        let now = Date()
        if delta >= 4096 {
            recentGrowthTimes.append(now)
            recentGrowthTimes.removeAll { now.timeIntervalSince($0) > 2.4 }
        }
        let isBurst = recentGrowthTimes.count >= 3
        // Always emit on WAL mutations so `ConversationSQLiteProbe` reads authoritative live `steps` state at 0ms
        onPulse?(WALActivityPulse(deltaBytes: delta, isRapidStreamingBurst: isBurst))
    }
}

/// Event-driven `kqueue` watcher on `~/.gemini/antigravity/annotations/<session-id>.pbtxt`
/// reading the live per-conversation `permission_preset` (`Turbo` / `Auto` / `Default` / `Request Review`)
/// and official conversation title with 0% idle CPU.
public actor ConversationAnnotationWatcher {
    public let annotationURL: URL

    private let watcherQueue: DispatchQueue
    private var fileSource: DispatchSourceFileSystemObject?
    private var dirSource: DispatchSourceFileSystemObject?
    private var onAnnotation: (@Sendable (ConversationAnnotation) -> Void)?
    private var lastEmitted: ConversationAnnotation?
    private var isWatching: Bool = false

    public init(session: ConversationSession) {
        let antigravityRoot = session.directoryURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        self.annotationURL = antigravityRoot
            .appendingPathComponent("annotations", isDirectory: true)
            .appendingPathComponent("\(session.id).pbtxt")
        self.watcherQueue = DispatchQueue(
            label: "com.grav.telemetry.annotation.\(UUID().uuidString)",
            qos: .utility
        )
    }

    public static func readAnnotation(at url: URL) -> ConversationAnnotation? {
        guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
            return nil
        }
        return ConversationAnnotation.parse(pbtxt: text)
    }

    public func startWatching(onAnnotation: @escaping @Sendable (ConversationAnnotation) -> Void) {
        stopWatching()
        self.onAnnotation = onAnnotation
        self.isWatching = true
        refreshAndNotify(force: true)
        attachFileSource()
        attachDirectorySource()
    }

    public func stopWatching() {
        isWatching = false
        onAnnotation = nil
        lastEmitted = nil
        fileSource?.cancel()
        fileSource = nil
        dirSource?.cancel()
        dirSource = nil
    }

    private func attachFileSource() {
        fileSource?.cancel()
        fileSource = nil
        guard isWatching else { return }

        let fd = open(annotationURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete, .attrib],
            queue: watcherQueue
        )
        source.setEventHandler { [weak self] in
            let flags = source.data
            let replaced = flags.contains(.rename) || flags.contains(.delete)
            Task { [weak self] in
                await self?.handleFileEvent(replaced: replaced)
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        fileSource = source
        source.resume()
    }

    private func attachDirectorySource() {
        dirSource?.cancel()
        dirSource = nil
        guard isWatching else { return }

        let parentPath = annotationURL.deletingLastPathComponent().path
        let fd = open(parentPath, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: watcherQueue
        )
        source.setEventHandler { [weak self] in
            Task { [weak self] in
                await self?.handleDirectoryEvent()
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        dirSource = source
        source.resume()
    }

    private func handleDirectoryEvent() {
        guard isWatching else { return }
        if fileSource == nil, FileManager.default.fileExists(atPath: annotationURL.path) {
            attachFileSource()
        }
        refreshAndNotify(force: false)
    }

    private func handleFileEvent(replaced: Bool) {
        guard isWatching else { return }
        if replaced {
            attachFileSource()
        }
        refreshAndNotify(force: false)
    }

    private func refreshAndNotify(force: Bool) {
        guard isWatching, let parsed = Self.readAnnotation(at: annotationURL) else { return }
        if !force, parsed == lastEmitted { return }
        lastEmitted = parsed
        onAnnotation?(parsed)
    }
}
