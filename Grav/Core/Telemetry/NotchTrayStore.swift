import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

// MARK: - Staged Drop Item & Queued Prompt Models

/// A file or image dropped onto Grav's Notch Drop Shelf.
public struct StagedDropItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let url: URL
    public let name: String
    public let isImage: Bool
    public let fileSize: Int64
    public let addedAt: Date

    public init(
        url: URL,
        name: String? = nil,
        isImage: Bool? = nil,
        fileSize: Int64 = 0,
        addedAt: Date = Date()
    ) {
        self.id = url.path
        self.url = url
        self.name = name ?? url.lastPathComponent
        if let isImage {
            self.isImage = isImage
        } else {
            let ext = url.pathExtension.lowercased()
            self.isImage = ["png", "jpg", "jpeg", "webp", "gif", "heic", "tiff", "bmp"].contains(ext)
        }
        self.fileSize = fileSize
        self.addedAt = addedAt
    }

    public var formattedSize: String {
        guard fileSize > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    public var abbreviatedPath: String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}

/// A follow-up prompt (with optional staged file attachments) queued while Antigravity is busy.
public struct QueuedPromptItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let text: String
    public let attachedPaths: [String]
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        text: String,
        attachedPaths: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.attachedPaths = attachedPaths
        self.createdAt = createdAt
    }
}

// MARK: - Notch Drop Shelf & Prompt Queue Store

/// `@MainActor @Observable` store managing Grav's Notch Drop Shelf (files/images dropped onto
/// Collapsed or Expanded Notch), inline Prompt Composer draft, and persistent Prompt Queue.
@MainActor
@Observable
public final class NotchTrayStore {
    public static let shared = NotchTrayStore()

    public private(set) var stagedItems: [StagedDropItem] = []
    public private(set) var thumbnails: [String: NSImage] = [:]
    public var draftPrompt: String {
        didSet { persistDraft() }
    }
    public private(set) var queuedPrompts: [QueuedPromptItem] = []

    /// True while a drag cursor is actively hovering over the Collapsed or Expanded Notch.
    public var isDropTargeted: Bool = false

    public var totalBadgeCount: Int {
        stagedItems.count + queuedPrompts.count
    }

    public var hasComposableContent: Bool {
        !draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !stagedItems.isEmpty
    }

    private let defaults: UserDefaults
    private let cacheDirectoryURL: URL
    private let maxStagedItems = 8

    private enum Keys {
        static let draftPrompt = "grav.notch.tray.draftPrompt"
        static let queuedPrompts = "grav.notch.tray.queuedPrompts"
    }

    public init(
        defaults: UserDefaults = .standard,
        cacheDirectoryURL: URL? = nil
    ) {
        self.defaults = defaults
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.cacheDirectoryURL = cacheDirectoryURL
            ?? caches.appendingPathComponent("com.grav.telemetry/DropShelf", isDirectory: true)
        self.draftPrompt = defaults.string(forKey: Keys.draftPrompt) ?? ""
        if let data = defaults.data(forKey: Keys.queuedPrompts),
           let decoded = try? JSONDecoder().decode([QueuedPromptItem].self, from: data)
        {
            self.queuedPrompts = decoded
        }
    }

    // MARK: - Staging Files & Images

    /// Adds local file URLs onto the Notch Drop Shelf, deduplicating and generating thumbnails off-main-actor.
    @discardableResult
    public func stageFileURLs(_ urls: [URL]) -> Int {
        let fm = FileManager.default
        var added = 0

        for rawURL in urls {
            let url = rawURL.standardizedFileURL
            guard url.isFileURL, fm.fileExists(atPath: url.path) else { continue }
            if stagedItems.contains(where: { $0.id == url.path }) { continue }

            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let fileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            let item = StagedDropItem(url: url, fileSize: fileSize)
            stagedItems.insert(item, at: 0)
            added += 1

            if item.isImage {
                loadThumbnailAsync(for: item)
            }
        }

        if stagedItems.count > maxStagedItems {
            stagedItems = Array(stagedItems.prefix(maxStagedItems))
        }
        return added
    }

    /// Persists raw dropped image data (e.g. dragged from Safari/Preview) into the local DropShelf cache and stages it.
    @discardableResult
    public func stageDroppedImageData(_ data: Data, preferredExtension: String = "png") -> StagedDropItem? {
        guard !data.isEmpty else { return nil }
        let fm = FileManager.default
        try? fm.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)

        let ext = preferredExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let filename = "drop-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(4)).\(ext.isEmpty ? "png" : ext)"
        let targetURL = cacheDirectoryURL.appendingPathComponent(filename)

        do {
            try data.write(to: targetURL, options: .atomic)
            _ = stageFileURLs([targetURL])
            return stagedItems.first(where: { $0.url == targetURL })
        } catch {
            return nil
        }
    }

    /// Appends dropped plain text cleanly into the prompt composer draft.
    public func appendDroppedText(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        if draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draftPrompt = cleaned
        } else {
            draftPrompt += "\n" + cleaned
        }
    }

    public func removeStagedItem(id: String) {
        stagedItems.removeAll { $0.id == id }
        thumbnails.removeValue(forKey: id)
    }

    public func clearStagedItems() {
        stagedItems.removeAll()
        thumbnails.removeAll()
    }

    // MARK: - Prompt Queue & Dispatch Bundle Formatting

    /// Moves the current draft + staged file paths into the persistent Prompt Queue for the next turn.
    @discardableResult
    public func enqueueCurrentDraft() -> QueuedPromptItem? {
        let trimmed = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let paths = stagedItems.map(\.url.path)
        guard !trimmed.isEmpty || !paths.isEmpty else { return nil }

        let fallbackTitle = trimmed.isEmpty
            ? (paths.count == 1 ? URL(fileURLWithPath: paths[0]).lastPathComponent : "\(paths.count) staged files")
            : trimmed

        let item = QueuedPromptItem(text: fallbackTitle, attachedPaths: paths)
        queuedPrompts.append(item)
        persistQueue()

        draftPrompt = ""
        clearStagedItems()
        return item
    }

    public func removeQueuedPrompt(id: String) {
        queuedPrompts.removeAll { $0.id == id }
        persistQueue()
    }

    /// Formats a clean prompt + file attachment bundle ready to paste into Antigravity.
    public static func formatPromptBundle(text: String, filePaths: [String]) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPaths = filePaths
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if trimmed.isEmpty {
            return cleanPaths.joined(separator: "\n")
        }
        if cleanPaths.isEmpty {
            return trimmed
        }
        let attachmentsBlock = cleanPaths.map { "@\($0)" }.joined(separator: "\n")
        return "\(trimmed)\n\n\(attachmentsBlock)"
    }

    /// Copies the current draft + staged items to the macOS pasteboard (including native file URLs
    /// when only files/images are staged so `⌘V` attaches images directly inside Antigravity!) and clears the draft.
    @discardableResult
    public func copyCurrentBundleAndClear() -> String? {
        let trimmed = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let urls = stagedItems.map(\.url)
        guard !trimmed.isEmpty || !urls.isEmpty else { return nil }

        let pb = NSPasteboard.general
        pb.clearContents()

        let formatted = Self.formatPromptBundle(text: trimmed, filePaths: urls.map(\.path))
        if trimmed.isEmpty && !urls.isEmpty {
            // Pure file/image drop: write native NSURL objects + string fallback so ⌘V attaches files in Antigravity!
            pb.writeObjects(urls as [NSURL])
            pb.setString(formatted, forType: .string)
        } else {
            pb.setString(formatted, forType: .string)
        }

        draftPrompt = ""
        clearStagedItems()
        return formatted
    }

    /// Pops a queued prompt onto the macOS pasteboard ready to `⌘V` in Antigravity.
    @discardableResult
    public func popQueuedPromptToPasteboard(id: String) -> String? {
        guard let idx = queuedPrompts.firstIndex(where: { $0.id == id }) else { return nil }
        let item = queuedPrompts.remove(at: idx)
        persistQueue()

        let formatted = Self.formatPromptBundle(text: item.text, filePaths: item.attachedPaths)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(formatted, forType: .string)
        return formatted
    }

    /// Handles SwiftUI `NSItemProvider` drops from Finder, Screenshots, Preview, Chrome, Safari, or text selections.
    public func handleDrop(providers: [NSItemProvider], onAccepted: @escaping @MainActor () -> Void) -> Bool {
        guard !providers.isEmpty else { return false }
        var handledAny = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handledAny = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                    let resolvedURL: URL? = {
                        if let data = item as? Data {
                            return URL(dataRepresentation: data, relativeTo: nil)
                        }
                        if let url = item as? URL {
                            return url
                        }
                        if let str = item as? String {
                            return URL(string: str)
                        }
                        return nil
                    }()
                    guard let resolvedURL else { return }
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if self.stageFileURLs([resolvedURL]) > 0 {
                            onAccepted()
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                handledAny = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { [weak self] data, _ in
                    if let data, !data.isEmpty {
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            if self.stageDroppedImageData(data, preferredExtension: "png") != nil {
                                onAccepted()
                            }
                        }
                        return
                    }
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] fallbackData, _ in
                        guard let fallbackData, !fallbackData.isEmpty else { return }
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            if self.stageDroppedImageData(fallbackData, preferredExtension: "png") != nil {
                                onAccepted()
                            }
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                handledAny = true
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, _ in
                    let text: String? = {
                        if let str = item as? String { return str }
                        if let data = item as? Data { return String(data: data, encoding: .utf8) }
                        return nil
                    }()
                    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.appendDroppedText(text)
                        onAccepted()
                    }
                }
            }
        }
        return handledAny
    }

    // MARK: - Private Helpers

    private func loadThumbnailAsync(for item: StagedDropItem) {
        let url = item.url
        let id = item.id
        Task { [weak self] in
            let image = await Task.detached(priority: .utility) { () -> NSImage? in
                guard let full = NSImage(contentsOf: url) else { return nil }
                return full
            }.value
            guard let image, let self else { return }
            self.thumbnails[id] = image
        }
    }

    private func persistDraft() {
        defaults.set(draftPrompt, forKey: Keys.draftPrompt)
    }

    private func persistQueue() {
        if let encoded = try? JSONEncoder().encode(queuedPrompts) {
            defaults.set(encoded, forKey: Keys.queuedPrompts)
        }
    }
}
