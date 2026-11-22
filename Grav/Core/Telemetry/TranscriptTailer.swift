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

        // Detect truncation or file rotation (inode swap)
        if fileSize < byteOffset || (watchedInode != nil && currentInode != nil && currentInode != watchedInode) {
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
    }

    /// Stops watching and releases the underlying file descriptor and `DispatchSource`.
    public func stopWatching() {
        isWatching = false
        onStepsHandler = nil
        cancelSource()
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

    private func handleFileSystemEvent(rawFlags: UInt) {
        guard isWatching else { return }
        let flags = DispatchSource.FileSystemEvent(rawValue: rawFlags)

        if flags.contains(.delete) || flags.contains(.rename) || flags.contains(.revoke) {
            // File was rotated or atomically replaced; reset offset and re-attach to the path
            byteOffset = 0
            watchedInode = nil
            persistOffset()
            attachFileSystemSource()
        }

        let steps = readNewSteps()
        if !steps.isEmpty, let handler = onStepsHandler {
            handler(steps)
        }
    }
}
