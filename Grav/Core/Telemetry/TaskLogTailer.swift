import Darwin
import Foundation

/// Dedicated Swift `actor` that incrementally tails live `.system_generated/tasks/task-<id>.log`
/// files via `DispatchSource.makeFileSystemObjectSource` while commands execute, and loads
/// completed `.system_generated/steps/<idx>/output.txt` logs with ANSI stripping.
public actor TaskLogTailer {
    public static let defaultMaxRetainedCharacters = 131_072
    public static let defaultMaxStepOutputBytes = 262_144

    private struct ActiveWatch {
        let commandID: String
        let logURL: URL
        var byteOffset: UInt64
        var accumulatedOutput: String
        var fileSource: DispatchSourceFileSystemObject?
        var directorySource: DispatchSourceFileSystemObject?
        let onUpdate: @Sendable (String, String) -> Void
    }

    private let maxRetainedCharacters: Int
    private let watcherQueue: DispatchQueue
    private var activeWatches: [String: ActiveWatch] = [:]

    public init(maxRetainedCharacters: Int = TaskLogTailer.defaultMaxRetainedCharacters) {
        self.maxRetainedCharacters = max(4_096, maxRetainedCharacters)
        self.watcherQueue = DispatchQueue(
            label: "com.grav.telemetry.task-log-tailer.\(UUID().uuidString)",
            qos: .utility
        )
    }

    /// Starts real-time event-driven tailing for a running command's `task-<id>.log`.
    /// If the log file does not yet exist on disk, watches the parent `tasks/` directory until it appears.
    public func startTailing(
        commandID: String,
        taskLogURL: URL,
        onUpdate: @escaping @Sendable (String, String) -> Void
    ) {
        stopTailing(commandID: commandID)

        let watch = ActiveWatch(
            commandID: commandID,
            logURL: taskLogURL,
            byteOffset: 0,
            accumulatedOutput: "",
            fileSource: nil,
            directorySource: nil,
            onUpdate: onUpdate
        )
        activeWatches[commandID] = watch

        if FileManager.default.fileExists(atPath: taskLogURL.path) {
            attachFileWatcher(for: commandID)
            if let text = readIncrementalUpdate(for: commandID), !text.isEmpty {
                onUpdate(commandID, text)
            }
        } else {
            attachParentDirectoryWatcher(for: commandID)
        }
    }

    /// Performs an incremental read from the active watch's `byteOffset`, strips ANSI escapes,
    /// and returns the updated accumulated output if new bytes were read.
    public func readIncrementalUpdate(for commandID: String) -> String? {
        guard var watch = activeWatches[commandID] else { return nil }

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: watch.logURL.path),
              let sizeNumber = attributes[.size] as? NSNumber
        else {
            return nil
        }

        let fileSize = sizeNumber.uint64Value
        if fileSize < watch.byteOffset {
            // File was truncated or recreated
            watch.byteOffset = 0
            watch.accumulatedOutput = ""
        }

        guard fileSize > watch.byteOffset else {
            activeWatches[commandID] = watch
            return nil
        }

        guard let handle = try? FileHandle(forReadingFrom: watch.logURL) else {
            return nil
        }
        defer {
            try? handle.close()
        }

        do {
            try handle.seek(toOffset: watch.byteOffset)
            guard let chunk = try handle.readToEnd(), !chunk.isEmpty else {
                return nil
            }
            watch.byteOffset += UInt64(chunk.count)

            let rawText = String(decoding: chunk, as: UTF8.self)
            let cleanedChunk = ANSIStripper.strip(rawText)
            if !cleanedChunk.isEmpty {
                watch.accumulatedOutput.append(cleanedChunk)
                if watch.accumulatedOutput.count > maxRetainedCharacters {
                    let dropCount = watch.accumulatedOutput.count - maxRetainedCharacters
                    watch.accumulatedOutput.removeFirst(dropCount)
                }
            }
            activeWatches[commandID] = watch
            return watch.accumulatedOutput
        } catch {
            return nil
        }
    }

    /// Stops tailing a specific command's task log and releases its `DispatchSource`.
    public func stopTailing(commandID: String) {
        guard let existing = activeWatches.removeValue(forKey: commandID) else {
            return
        }
        existing.fileSource?.cancel()
        existing.directorySource?.cancel()
    }

    /// Stops all active task log watchers and releases all underlying file descriptors.
    public func stopAll() {
        let watches = activeWatches.values
        activeWatches.removeAll()
        for watch in watches {
            watch.fileSource?.cancel()
            watch.directorySource?.cancel()
        }
    }

    /// Returns the currently active tailed command IDs.
    public var activeCommandIDs: [String] {
        Array(activeWatches.keys)
    }

    /// Reads a completed step output file (`.system_generated/steps/<idx>/output.txt`),
    /// capping large outputs to the trailing `maxBytes` and stripping ANSI sequences.
    public func readStepOutput(
        at outputURL: URL,
        maxBytes: Int = TaskLogTailer.defaultMaxStepOutputBytes
    ) -> (text: String, isTruncated: Bool)? {
        Self.readStepOutputFile(at: outputURL, maxBytes: maxBytes)
    }

    /// Static reader for `.system_generated/steps/<idx>/output.txt` with ANSI stripping.
    public static func readStepOutputFile(
        at outputURL: URL,
        maxBytes: Int = TaskLogTailer.defaultMaxStepOutputBytes
    ) -> (text: String, isTruncated: Bool)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
              let sizeNumber = attributes[.size] as? NSNumber
        else {
            return nil
        }

        let fileSize = sizeNumber.uint64Value
        guard let handle = try? FileHandle(forReadingFrom: outputURL) else {
            return nil
        }
        defer {
            try? handle.close()
        }

        let limit = UInt64(max(1_024, maxBytes))
        let isTruncated = fileSize > limit
        do {
            if isTruncated {
                try handle.seek(toOffset: fileSize - limit)
            }
            guard let data = try handle.readToEnd() else {
                return nil
            }
            let decoded = String(decoding: data, as: UTF8.self)
            let cleaned = ANSIStripper.strip(decoded)
            return (cleaned, isTruncated)
        } catch {
            return nil
        }
    }

    // MARK: - DispatchSource Helpers

    private func attachFileWatcher(for commandID: String) {
        guard var watch = activeWatches[commandID] else { return }
        watch.fileSource?.cancel()
        watch.fileSource = nil
        watch.directorySource?.cancel()
        watch.directorySource = nil

        let fd = open(watch.logURL.path, O_EVTONLY)
        guard fd >= 0 else {
            activeWatches[commandID] = watch
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: watcherQueue
        )

        source.setEventHandler { [weak self] in
            let rawFlags = source.data.rawValue
            Task { [weak self] in
                await self?.handleFileEvent(commandID: commandID, rawFlags: rawFlags)
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        watch.fileSource = source
        activeWatches[commandID] = watch
        source.resume()
    }

    private func attachParentDirectoryWatcher(for commandID: String) {
        guard var watch = activeWatches[commandID] else { return }
        watch.directorySource?.cancel()
        watch.directorySource = nil

        let parentURL = watch.logURL.deletingLastPathComponent()
        let fd = open(parentURL.path, O_EVTONLY)
        guard fd >= 0 else {
            activeWatches[commandID] = watch
            return
        }

        let dirSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .link, .rename],
            queue: watcherQueue
        )

        dirSource.setEventHandler { [weak self] in
            Task { [weak self] in
                await self?.handleParentDirectoryEvent(commandID: commandID)
            }
        }

        dirSource.setCancelHandler {
            close(fd)
        }

        watch.directorySource = dirSource
        activeWatches[commandID] = watch
        dirSource.resume()
    }

    private func handleParentDirectoryEvent(commandID: String) {
        guard let watch = activeWatches[commandID] else { return }
        guard FileManager.default.fileExists(atPath: watch.logURL.path) else { return }

        attachFileWatcher(for: commandID)
        if let updated = readIncrementalUpdate(for: commandID),
           let current = activeWatches[commandID]
        {
            current.onUpdate(commandID, updated)
        }
    }

    private func handleFileEvent(commandID: String, rawFlags: UInt) {
        guard let watch = activeWatches[commandID] else { return }
        let flags = DispatchSource.FileSystemEvent(rawValue: rawFlags)

        if flags.contains(.delete) || flags.contains(.rename) || flags.contains(.revoke) {
            if FileManager.default.fileExists(atPath: watch.logURL.path) {
                attachFileWatcher(for: commandID)
            } else {
                attachParentDirectoryWatcher(for: commandID)
                return
            }
        }

        if let updated = readIncrementalUpdate(for: commandID),
           let current = activeWatches[commandID]
        {
            current.onUpdate(commandID, updated)
        }
    }
}
