import AppKit
import ApplicationServices
import Carbon.HIToolbox
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

/// Destination mode for sending prompts from Grav's Notch Composer to Antigravity.
public enum AntigravitySendTarget: String, CaseIterable, Identifiable, Sendable {
    /// Targets the currently open Antigravity session (keeps `cascadeId` intact; pastes images + text & submits).
    case activeSession = "active"
    /// Opens a fresh Antigravity conversation via the sanctioned `antigravity://open?prompt=...` deep link.
    case newChat = "new"

    public var id: String { rawValue }
}

/// Outcome of dispatching a prompt bundle from Grav's Notch Composer to Antigravity.
public enum AntigravityPromptDispatchResult: Sendable, Equatable {
    /// Sent directly into the currently open Antigravity session (`⌘L` focusInput -> paste image/text -> `Return`).
    case sentToActiveSession
    /// Focused the active Antigravity session with bundle on clipboard; Accessibility not granted for auto-submit.
    case copiedToActiveSessionNeedsAccessibility
    /// Opened Antigravity's sanctioned `antigravity://open?prompt=...` deep link into a new chat.
    case openedNewChatDeepLink(URL)
    /// Prompt exceeded URL length cap or LaunchServices rejected the URL; copied to clipboard instead.
    case copiedToClipboardFallback
}

// MARK: - Notch Drop Shelf & Prompt Queue Store

/// `@MainActor @Observable` store managing Grav's Notch Drop Shelf (files/images dragged onto
/// the Notch), inline Prompt Composer draft, active-session vs new-chat dispatch, and Prompt Queue.
@MainActor
@Observable
public final class NotchTrayStore {
    public static let shared = NotchTrayStore()

    public private(set) var stagedItems: [StagedDropItem] = []
    public private(set) var thumbnails: [String: NSImage] = [:]
    public var draftPrompt: String {
        didSet { persistDraft() }
    }
    public var sendTarget: AntigravitySendTarget {
        didSet { defaults.set(sendTarget.rawValue, forKey: Keys.sendTarget) }
    }
    public private(set) var queuedPrompts: [QueuedPromptItem] = []

    /// True while any macOS drag carrying files/images is active anywhere on screen.
    public var isGlobalDragActive: Bool = false
    /// True while a drag cursor carrying files/images is inside the expanded Notch capture region (`564×324`).
    public var isGlobalDragNearNotch: Bool = false
    /// Observable request flag so `ExpandedNotchView` mounts directly onto the Drop Shelf with zero notification race.
    public var isTrayOpenRequested: Bool = false
    /// True while a drag cursor is directly hovering inside the Notch drop surface.
    public var isDropTargeted: Bool = false
    /// True when the active macOS drag pasteboard contains at least one image.
    public var globalDragHasImage: Bool = false
    /// Approximate item count on the active macOS drag pasteboard.
    public var globalDragItemCount: Int = 0
    /// Timestamp of the most recent completed drop (keeps the Notch open after drop, matching `boring.notch`'s `dropEvent`).
    public var lastDropCompletedAt: Date = .distantPast
    /// Incremented whenever an image/file is absorbed into the Notch (drives optical capture pulse).
    public private(set) var lastCapturePulseToken: Int = 0

    public var totalBadgeCount: Int {
        stagedItems.count + queuedPrompts.count
    }

    public var hasComposableContent: Bool {
        !draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !stagedItems.isEmpty
    }

    public var isAccessibilityTrustedForAutoSend: Bool {
        AXIsProcessTrusted()
    }

    private let defaults: UserDefaults
    private let cacheDirectoryURL: URL
    private let maxStagedItems = 8

    private enum Keys {
        static let draftPrompt = "grav.notch.tray.draftPrompt"
        static let queuedPrompts = "grav.notch.tray.queuedPrompts"
        static let sendTarget = "grav.notch.tray.sendTarget"
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
        if let rawTarget = defaults.string(forKey: Keys.sendTarget),
           let parsedTarget = AntigravitySendTarget(rawValue: rawTarget)
        {
            self.sendTarget = parsedTarget
        } else {
            self.sendTarget = .activeSession
        }
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
        if added > 0 {
            lastCapturePulseToken += 1
            lastDropCompletedAt = Date()
        }
        return added
    }

    /// Persists raw dropped/pasted image data into the local DropShelf cache and stages it.
    @discardableResult
    public func stageDroppedImageData(_ data: Data, preferredExtension: String = "png") -> StagedDropItem? {
        guard !data.isEmpty else { return nil }
        let fm = FileManager.default
        try? fm.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)

        let ext = preferredExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let filename = "image-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(4)).\(ext.isEmpty ? "png" : ext)"
        let targetURL = cacheDirectoryURL.appendingPathComponent(filename)

        do {
            try data.write(to: targetURL, options: .atomic)
            _ = stageFileURLs([targetURL])
            return stagedItems.first(where: { $0.url == targetURL })
        } catch {
            return nil
        }
    }

    /// Stages an `NSImage` (e.g. from macOS pasteboard or drag) by encoding crisp PNG bytes to the DropShelf cache.
    @discardableResult
    public func stageNSImage(_ image: NSImage) -> StagedDropItem? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            return nil
        }
        let item = stageDroppedImageData(png, preferredExtension: "png")
        if let item {
            thumbnails[item.id] = image
        }
        return item
    }

    /// Reads files, raw images (PNG/TIFF/HEIC/JPEG/NSImage), or plain text from an `NSPasteboard`
    /// (used by both native `NSDraggingDestination` drops and `⌘V` image paste inside the Composer).
    @discardableResult
    public func stageFromPasteboard(_ pb: NSPasteboard, allowPlainText: Bool = true) -> Int {
        // 1. Real local file URLs (Finder, Screenshots, Desktop, Preview)
        if let urls = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            let added = stageFileURLs(urls)
            if added > 0 { return added }
        }

        // 2. Direct PNG bytes on pasteboard (Chrome/Safari/Figma/Screenshots)
        if let pngData = pb.data(forType: .png), !pngData.isEmpty {
            if stageDroppedImageData(pngData, preferredExtension: "png") != nil {
                return 1
            }
        }

        // 3. Direct JPEG / HEIC / WebP bytes
        let extraImageTypes: [(NSPasteboard.PasteboardType, String)] = [
            (NSPasteboard.PasteboardType("public.jpeg"), "jpg"),
            (NSPasteboard.PasteboardType("public.heic"), "heic"),
            (NSPasteboard.PasteboardType("org.webmproject.webp"), "webp"),
        ]
        for (pbType, ext) in extraImageTypes {
            if let data = pb.data(forType: pbType), !data.isEmpty {
                if stageDroppedImageData(data, preferredExtension: ext) != nil {
                    return 1
                }
            }
        }

        // 4. Generic NSImage / TIFF representation (Preview, macOS apps, copied screenshots)
        if let image = NSImage(pasteboard: pb), stageNSImage(image) != nil {
            return 1
        }

        // 5. Fallback: plain text drop (only when requested, e.g. drag-drop text snippet)
        if allowPlainText,
           let str = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !str.isEmpty
        {
            appendDroppedText(str)
            return 1
        }

        return 0
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

    /// Formats a clean prompt + file attachment bundle ready for Antigravity.
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

    private static let deepLinkQueryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        // Percent-encode `+` (decoded as space by JS URLSearchParams) and all query/fragment delimiters.
        allowed.remove(charactersIn: "+&=/?#%\\")
        return allowed
    }()

    /// Builds Antigravity's sanctioned `antigravity://open?prompt=...` deep link URL (New Chat).
    ///
    /// Verified statically against `/Applications/Antigravity.app` (`Info.plist` `CFBundleURLSchemes`,
    /// `app.asar` `dist/main.js` `open-url` -> `handleDeepLink`, and `main.js` `deepLinkListener`),
    /// which focuses the Antigravity window, opens a New Conversation in the active workspace,
    /// injects `prompt` into the Lexical editor, and preserves `\n` / `\t` while stripping `\r`.
    public static func buildAntigravityPromptDeepLinkURL(
        prompt: String,
        project: String? = nil
    ) -> URL? {
        let normalized = prompt
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.utf8.count <= 12_000 else { return nil }
        guard let encodedPrompt = normalized.addingPercentEncoding(withAllowedCharacters: deepLinkQueryValueAllowed) else {
            return nil
        }

        var query = "prompt=\(encodedPrompt)"
        if let project = project?.trimmingCharacters(in: .whitespacesAndNewlines),
           !project.isEmpty,
           let encodedProject = project.addingPercentEncoding(withAllowedCharacters: deepLinkQueryValueAllowed)
        {
            query += "&project=\(encodedProject)"
        }

        var components = URLComponents()
        components.scheme = "antigravity"
        components.host = "open"
        components.percentEncodedQuery = query
        return components.url
    }

    /// Prompts macOS System Settings → Privacy & Security → Accessibility so Grav can auto-send
    /// prompts & image attachments straight into Antigravity's active conversation.
    public func requestAccessibilityPermission(openSystemSettings: Bool = true) {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if openSystemSettings,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        {
            NSWorkspace.shared.open(url)
        }
    }

    /// Dispatches the current draft + staged images/files to Antigravity according to `sendTarget`:
    /// - `.activeSession`: keeps the currently open conversation intact (does NOT open a new chat!).
    ///   With Accessibility permission: hands off activation to Antigravity, waits until Antigravity
    ///   is truly frontmost and physical modifier keys (`⌘`) are released, focuses active chat input (`⌘L`),
    ///   pastes staged images as real native attachments (`⌘V`), pastes text (`⌘V`), and submits (`↵`).
    ///   Without Accessibility permission: preserves the draft, backs up to clipboard, and triggers
    ///   the standard macOS Accessibility prompt so the user can approve Grav in one step.
    /// - `.newChat`: opens a fresh conversation via Antigravity's sanctioned `antigravity://open?prompt=...` scheme.
    @discardableResult
    public func sendCurrentBundleToAntigravity(
        target: AntigravitySendTarget? = nil,
        activateApp: () -> Void,
        openURL: (URL) -> Bool = { NSWorkspace.shared.open($0) },
        isAccessibilityTrustedOverride: Bool? = nil,
        skipLiveKeystrokeDelivery: Bool = false
    ) -> AntigravityPromptDispatchResult? {
        let effectiveTarget = target ?? sendTarget
        let trimmed = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = stagedItems
        guard !trimmed.isEmpty || !items.isEmpty else { return nil }

        let imageURLs = items.filter(\.isImage).map(\.url)
        let nonImagePaths = items.filter { !$0.isImage }.map(\.url.path)
        let allPaths = items.map(\.url.path)

        let trusted = isAccessibilityTrustedOverride ?? AXIsProcessTrusted()
        if effectiveTarget == .activeSession && !trusted {
            // Preserve draft & staged items so user never loses their prompt while granting Accessibility!
            let fullFormatted = Self.formatPromptBundle(text: trimmed, filePaths: allPaths)
            writeFallbackClipboard(text: trimmed, urls: items.map(\.url), formatted: fullFormatted)
            return .copiedToActiveSessionNeedsAccessibility
        }

        draftPrompt = ""
        clearStagedItems()

        return dispatchBundle(
            text: trimmed,
            imageURLs: imageURLs,
            nonImagePaths: nonImagePaths,
            allPaths: allPaths,
            target: effectiveTarget,
            activateApp: activateApp,
            openURL: openURL,
            isAccessibilityTrusted: trusted,
            skipLiveKeystrokeDelivery: skipLiveKeystrokeDelivery
        )
    }

    /// Pops a queued prompt and dispatches it straight to Antigravity (active session or new chat).
    @discardableResult
    public func sendQueuedPromptToAntigravity(
        id: String,
        target: AntigravitySendTarget? = nil,
        activateApp: () -> Void = {},
        openURL: (URL) -> Bool = { NSWorkspace.shared.open($0) },
        isAccessibilityTrustedOverride: Bool? = nil,
        skipLiveKeystrokeDelivery: Bool = false
    ) -> AntigravityPromptDispatchResult? {
        guard let idx = queuedPrompts.firstIndex(where: { $0.id == id }) else { return nil }
        let item = queuedPrompts[idx]

        let effectiveTarget = target ?? sendTarget
        let trusted = isAccessibilityTrustedOverride ?? AXIsProcessTrusted()
        if effectiveTarget == .activeSession && !trusted {
            let fullFormatted = Self.formatPromptBundle(text: item.text, filePaths: item.attachedPaths)
            let urls = item.attachedPaths.map { URL(fileURLWithPath: $0) }
            writeFallbackClipboard(text: item.text, urls: urls, formatted: fullFormatted)
            return .copiedToActiveSessionNeedsAccessibility
        }

        queuedPrompts.remove(at: idx)
        persistQueue()

        let stagedFromQueue = item.attachedPaths.map { StagedDropItem(url: URL(fileURLWithPath: $0)) }
        let imageURLs = stagedFromQueue.filter(\.isImage).map(\.url)
        let nonImagePaths = stagedFromQueue.filter { !$0.isImage }.map(\.url.path)

        return dispatchBundle(
            text: item.text,
            imageURLs: imageURLs,
            nonImagePaths: nonImagePaths,
            allPaths: item.attachedPaths,
            target: effectiveTarget,
            activateApp: activateApp,
            openURL: openURL,
            isAccessibilityTrusted: trusted,
            skipLiveKeystrokeDelivery: skipLiveKeystrokeDelivery
        )
    }

    /// Copies the current draft + staged items to the macOS pasteboard and clears the draft.
    @discardableResult
    public func copyCurrentBundleAndClear() -> String? {
        let trimmed = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let urls = stagedItems.map(\.url)
        guard !trimmed.isEmpty || !urls.isEmpty else { return nil }

        let formatted = Self.formatPromptBundle(text: trimmed, filePaths: urls.map(\.path))
        writeFallbackClipboard(text: trimmed, urls: urls, formatted: formatted)

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

    /// Handles SwiftUI `NSItemProvider` drops as a fallback alongside the native AppKit `NSDraggingDestination`.
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

    // MARK: - Private Dispatch Helpers

    private func dispatchBundle(
        text: String,
        imageURLs: [URL],
        nonImagePaths: [String],
        allPaths: [String],
        target: AntigravitySendTarget,
        activateApp: () -> Void,
        openURL: (URL) -> Bool,
        isAccessibilityTrusted: Bool,
        skipLiveKeystrokeDelivery: Bool
    ) -> AntigravityPromptDispatchResult {
        let fullFormatted = Self.formatPromptBundle(text: text, filePaths: allPaths)
        let urls = allPaths.map { URL(fileURLWithPath: $0) }
        writeFallbackClipboard(text: text, urls: urls, formatted: fullFormatted)

        switch target {
        case .newChat:
            if let deepLink = Self.buildAntigravityPromptDeepLinkURL(prompt: fullFormatted),
               openURL(deepLink)
            {
                return .openedNewChatDeepLink(deepLink)
            }
            activateApp()
            return .copiedToClipboardFallback

        case .activeSession:
            activateApp()
            guard isAccessibilityTrusted else {
                return .copiedToActiveSessionNeedsAccessibility
            }
            if !skipLiveKeystrokeDelivery {
                let textWithNonImageRefs = Self.formatPromptBundle(text: text, filePaths: nonImagePaths)
                Self.deliverToFocusedAntigravitySession(
                    text: textWithNonImageRefs,
                    imageURLs: imageURLs
                )
            }
            return .sentToActiveSession
        }
    }

    private func writeFallbackClipboard(text: String, urls: [URL], formatted: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if text.isEmpty && !urls.isEmpty {
            if urls.count == 1,
               let img = NSImage(contentsOf: urls[0]),
               let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:])
            {
                pb.setData(png, forType: .png)
            }
            pb.writeObjects(urls as [NSURL])
            pb.setString(formatted, forType: .string)
        } else {
            pb.setString(formatted, forType: .string)
        }
    }

    /// Standard macOS Accessibility-authorized delivery into Antigravity's currently open session:
    /// 1. Waits until `com.google.antigravity` is truly the frontmost application (never blind sleep!).
    /// 2. Waits until physical `⌘` / modifier keys (from `⌘↵`) are released so modifiers never bleed.
    /// 3. Sends isolated `.privateState` `⌘L` -> Antigravity's `focusInput` (verified in `main.js` `@5815362`).
    /// 4. Pastes each staged image via `NSPasteboard` PNG bytes + `⌘V` (`lHb` `onMediaPaste` at `@4818699`),
    ///    giving `360ms` for async Chromium FileReader media attachment.
    /// 5. Pastes the prompt text + non-image `@path` references via `⌘V`.
    /// 6. Submits via clean `Return` (`submitPrompt`, verified in `main.js` `@5465280`).
    private static func deliverToFocusedAntigravitySession(text: String, imageURLs: [URL]) {
        Task { @MainActor in
            // 1. Wait until Antigravity is truly frontmost (up to 1.2s)
            let activationDeadline = Date().addingTimeInterval(1.2)
            while Date() < activationDeadline {
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == AntigravityAppDetector.bundleIdentifier {
                    break
                }
                if let app = NSRunningApplication.runningApplications(
                    withBundleIdentifier: AntigravityAppDetector.bundleIdentifier
                ).first {
                    app.unhide()
                    app.activate(options: [.activateAllWindows])
                }
                try? await Task.sleep(for: .milliseconds(30))
            }

            // 2. Wait for physical modifier keys (e.g. Command held during ⌘↵) to be released (up to 500ms)
            let modifierDeadline = Date().addingTimeInterval(0.5)
            let watchedModifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
            while Date() < modifierDeadline {
                let currentFlags = CGEventSource.flagsState(.hidSystemState)
                if currentFlags.intersection(watchedModifiers).isEmpty {
                    break
                }
                try? await Task.sleep(for: .milliseconds(25))
            }

            // Let Electron BrowserWindow settle `document.hasFocus()`
            try? await Task.sleep(for: .milliseconds(140))

            // 3. Focus active session's Lexical chat editor via Antigravity's `focusInput` (`⌘L`)
            await postKeyChord(keyCode: CGKeyCode(kVK_ANSI_L), flags: .maskCommand)
            try? await Task.sleep(for: .milliseconds(160))

            // 4. Attach each staged image directly via native paste (`⌘V`)
            for imageURL in imageURLs {
                if let pngData = loadPNGData(from: imageURL) {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setData(pngData, forType: .png)
                    try? await Task.sleep(for: .milliseconds(50))
                    await postKeyChord(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
                    // Give Antigravity's Lexical `onMediaPaste` FileReader time to mount the image attachment
                    try? await Task.sleep(for: .milliseconds(360))
                }
            }

            // 5. Paste prompt text (if any)
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(trimmedText, forType: .string)
                try? await Task.sleep(for: .milliseconds(50))
                await postKeyChord(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
                try? await Task.sleep(for: .milliseconds(200))
            }

            // 6. Submit straight into the active Antigravity session (`Return`)
            await postKeyChord(keyCode: CGKeyCode(kVK_Return), flags: [])
        }
    }

    private static func loadPNGData(from url: URL) -> Data? {
        if url.pathExtension.lowercased() == "png",
           let raw = try? Data(contentsOf: url), !raw.isEmpty
        {
            return raw
        }
        guard let image = NSImage(contentsOf: url),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }

    private static func postKeyChord(keyCode: CGKeyCode, flags: CGEventFlags) async {
        // `.privateState` isolates synthetic flags from physical keyboard modifier state (zero ⌘ bleed!)
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cgSessionEventTap)
        try? await Task.sleep(for: .milliseconds(24))
        up.post(tap: .cgSessionEventTap)
    }

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
