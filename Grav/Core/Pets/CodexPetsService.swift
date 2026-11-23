import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

// MARK: - Live REST API Client (`https://codex-pets.net/api/pets`)

public struct CodexPetsCatalogService: Sendable {
    public static let baseURL = URL(string: "https://codex-pets.net")!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchPets(
        query: String = "",
        sort: CodexPetSort = .popular,
        page: Int = 1,
        pageSize: Int = 36
    ) async throws -> CodexPetsCatalogResponse {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent("api/pets"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "\(max(1, page))"),
            URLQueryItem(name: "pageSize", value: "\(min(60, max(1, pageSize)))"),
            URLQueryItem(name: "sort", value: sort.rawValue),
        ]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            items.append(URLQueryItem(name: "q", value: trimmed))
        }
        components.queryItems = items

        guard let url = components.url else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(CodexPetsCatalogResponse.self, from: data)
    }

    public func fetchPetDetail(slug: String) async throws -> CodexPetRemoteItem {
        let cleaned = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = Self.baseURL.appendingPathComponent("api/pets/\(cleaned)")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(CodexPetDetailResponse.self, from: data)
        return decoded.pet
    }

    public func downloadData(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

// MARK: - Crisp Pixel-Art Sprite Sheet Slicer & Native GIF Exporter

public enum CodexPetSpriteSlicer {
    public static let atlasColumns = 8

    /// Decodes a WebP/PNG Codex Pet sprite sheet and slices every state row into crisp `CGImage` frames.
    public static func sliceAtlas(
        data: Data,
        spriteVersion: Int
    ) -> [CodexPetAnimationState: [CGImage]]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let fullImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }

        let width = fullImage.width
        let height = fullImage.height
        guard width >= 64, height >= 64 else { return nil }

        let totalRows = spriteVersion >= 2 ? 11 : 9
        let cellW = Double(width) / Double(atlasColumns)
        let cellH = Double(height) / Double(totalRows)
        guard cellW >= 8, cellH >= 8 else { return nil }

        var result: [CodexPetAnimationState: [CGImage]] = [:]
        for state in CodexPetAnimationState.availableStates(for: spriteVersion) {
            let row = state.rowIndex
            guard row < totalRows else { continue }
            let count = state.frameCount(spriteVersion: spriteVersion)
            var frames: [CGImage] = []
            frames.reserveCapacity(count)

            for col in 0..<count {
                let rect = CGRect(
                    x: (Double(col) * cellW).rounded(.down),
                    y: (Double(row) * cellH).rounded(.down),
                    width: cellW.rounded(.down),
                    height: cellH.rounded(.down)
                )
                if let cropped = fullImage.cropping(to: rect) {
                    frames.append(cropped)
                }
            }
            if !frames.isEmpty {
                result[state] = frames
            }
        }

        return result.isEmpty ? nil : result
    }

    /// Exports a single animation state as an authentic transparent looping `.gif` via macOS ImageIO.
    public static func exportGIF(
        frames: [CGImage],
        frameDelay: TimeInterval = CodexPetAnimationState.baseFrameInterval,
        to destinationURL: URL
    ) throws {
        guard !frames.isEmpty else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard let dest = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let fileProps: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0,
            ],
        ]
        CGImageDestinationSetProperties(dest, fileProps as CFDictionary)

        let frameProps: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDelay,
                kCGImagePropertyGIFUnclampedDelayTime: frameDelay,
            ],
        ]

        for frame in frames {
            CGImageDestinationAddImage(dest, frame, frameProps as CFDictionary)
        }

        guard CGImageDestinationFinalize(dest) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

// MARK: - Central Observable Mini Pet Store

@MainActor
@Observable
public final class CodexPetsStore {
    public static let shared = CodexPetsStore()

    public private(set) var installedPets: [InstalledCodexPet] = []
    public private(set) var galleryPets: [CodexPetRemoteItem] = []
    public private(set) var galleryTotal: Int = 0
    public private(set) var isLoadingGallery: Bool = false
    public private(set) var galleryError: String?
    public private(set) var downloadingPetIDs: Set<String> = []
    public private(set) var statusMessage: String?

    /// Short-lived interactive override triggered when the user clicks or pets the Mini Pet.
    public private(set) var reactionOverride: CodexPetAnimationState?

    private var reactionResetTask: Task<Void, Never>?
    private var framesCache: [String: [CodexPetAnimationState: [CGImage]]] = [:]
    private let service = CodexPetsCatalogService()
    private let petsRootURL: URL

    public init(baseDirectoryURL: URL? = nil) {
        if let baseDirectoryURL {
            self.petsRootURL = baseDirectoryURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
            self.petsRootURL = appSupport
                .appendingPathComponent("Grav", isDirectory: true)
                .appendingPathComponent("Pets", isDirectory: true)
        }

        ensureBundledDefaultPetInstalled()
        reloadInstalledPets()
    }

    // MARK: - Active Pet & Sprite Access

    public func pet(withID id: String) -> InstalledCodexPet? {
        installedPets.first { $0.id == id } ?? installedPets.first
    }

    public func frames(for pet: InstalledCodexPet) -> [CodexPetAnimationState: [CGImage]]? {
        if let cached = framesCache[pet.id] {
            return cached
        }
        guard let url = spritesheetURL(for: pet),
              let data = try? Data(contentsOf: url),
              let sliced = CodexPetSpriteSlicer.sliceAtlas(data: data, spriteVersion: pet.spriteVersionNumber)
        else {
            return nil
        }
        framesCache[pet.id] = sliced
        return sliced
    }

    public func spritesheetURL(for pet: InstalledCodexPet) -> URL? {
        let localURL = petsRootURL
            .appendingPathComponent(pet.id, isDirectory: true)
            .appendingPathComponent(pet.spritesheetFilename)
        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }
        if pet.isBundledDefault {
            return Bundle.main.url(forResource: "super-saiyan-goku-combat", withExtension: "webp")
        }
        return nil
    }

    public func isInstalled(_ id: String) -> Bool {
        installedPets.contains { $0.id == id }
    }

    /// Triggers an interactive click/hover reaction (alternates `.waving` & `.jumping` smoothly).
    public func triggerInteractionReaction() {
        let next: CodexPetAnimationState = (reactionOverride == .waving) ? .jumping : .waving
        reactionOverride = next
        reactionResetTask?.cancel()
        reactionResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.65))
            guard !Task.isCancelled else { return }
            self?.reactionOverride = nil
        }
    }

    // MARK: - Live `codex-pets.net` Gallery Search & Download

    public func searchGallery(query: String, sort: CodexPetSort = .popular) async {
        isLoadingGallery = true
        galleryError = nil
        defer { isLoadingGallery = false }

        do {
            switch CodexPetSearchInput.parse(query) {
            case let .directPetSlug(slug):
                let detail = try await service.fetchPetDetail(slug: slug)
                galleryPets = [detail]
                galleryTotal = 1

            case let .query(cleaned):
                let response = try await service.fetchPets(query: cleaned, sort: sort, page: 1, pageSize: 36)
                galleryPets = response.pets
                galleryTotal = response.total ?? response.pets.count
            }
        } catch {
            galleryError = "Could not reach codex-pets.net (\(error.localizedDescription))."
        }
    }

    @discardableResult
    public func downloadAndInstall(_ remote: CodexPetRemoteItem) async -> InstalledCodexPet? {
        guard !downloadingPetIDs.contains(remote.id) else { return pet(withID: remote.id) }
        guard let sheetURL = remote.resolvedSpritesheetURL else {
            galleryError = "Missing sprite sheet URL for \(remote.displayName)."
            return nil
        }

        downloadingPetIDs.insert(remote.id)
        defer { downloadingPetIDs.remove(remote.id) }

        do {
            let sheetData = try await service.downloadData(from: sheetURL)
            let version = remote.resolvedSpriteVersion

            // Validate & pre-slice off the main actor
            let sliced = await Task.detached(priority: .userInitiated) {
                CodexPetSpriteSlicer.sliceAtlas(data: sheetData, spriteVersion: version)
            }.value
            guard let sliced else {
                galleryError = "Downloaded sprite sheet for \(remote.displayName) could not be decoded."
                return nil
            }

            let petDir = petsRootURL.appendingPathComponent(remote.id, isDirectory: true)
            try FileManager.default.createDirectory(at: petDir, withIntermediateDirectories: true)

            let sheetFile = petDir.appendingPathComponent("spritesheet.webp")
            try sheetData.write(to: sheetFile, options: .atomic)

            let record = InstalledCodexPet(
                id: remote.id,
                displayName: remote.displayName,
                description: remote.description ?? "",
                ownerHandle: remote.ownerHandle ?? remote.ownerName ?? "codex-pets",
                spriteVersionNumber: version,
                tags: remote.tags ?? [],
                spritesheetFilename: "spritesheet.webp",
                sourceURL: remote.webPageURL?.absoluteString,
                installedAt: Date(),
                isBundledDefault: false
            )
            let metaData = try JSONEncoder().encode(record)
            try metaData.write(to: petDir.appendingPathComponent("metadata.json"), options: .atomic)

            framesCache[record.id] = sliced
            reloadInstalledPets()
            statusMessage = "Downloaded \(record.displayName)"
            return record
        } catch {
            galleryError = "Download failed: \(error.localizedDescription)"
            return nil
        }
    }

    public func deleteInstalledPet(_ pet: InstalledCodexPet) {
        guard !pet.isBundledDefault else { return }
        let petDir = petsRootURL.appendingPathComponent(pet.id, isDirectory: true)
        try? FileManager.default.removeItem(at: petDir)
        framesCache.removeValue(forKey: pet.id)
        reloadInstalledPets()
    }

    // MARK: - Export GIF / All GIFs / Sprite Sheet (1:1 with codex-pets.net)

    public func exportSingleStateGIF(
        pet: InstalledCodexPet,
        state: CodexPetAnimationState,
        speed: Double = 1.0
    ) {
        guard let frames = frames(for: pet)?[state], !frames.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        panel.nameFieldStringValue = "\(pet.id)-\(state.rawValue).gif"
        panel.title = "Export \(state.label) GIF"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let delay = CodexPetAnimationState.baseFrameInterval / max(0.25, speed)
        do {
            try CodexPetSpriteSlicer.exportGIF(frames: frames, frameDelay: delay, to: url)
            statusMessage = "Exported \(url.lastPathComponent)"
        } catch {
            galleryError = "GIF export failed: \(error.localizedDescription)"
        }
    }

    public func exportAllStateGIFs(pet: InstalledCodexPet, speed: Double = 1.0) {
        guard let allFrames = frames(for: pet), !allFrames.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export All GIFs Here"
        panel.title = "Choose Folder for \(pet.displayName) GIFs"
        guard panel.runModal() == .OK, let folderURL = panel.url else { return }

        let targetDir = folderURL.appendingPathComponent("\(pet.id)-gifs", isDirectory: true)
        let delay = CodexPetAnimationState.baseFrameInterval / max(0.25, speed)

        do {
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            var exported = 0
            for state in CodexPetAnimationState.availableStates(for: pet.spriteVersionNumber) {
                guard let stateFrames = allFrames[state], !stateFrames.isEmpty else { continue }
                let dest = targetDir.appendingPathComponent("\(pet.id)-\(state.rawValue).gif")
                try CodexPetSpriteSlicer.exportGIF(frames: stateFrames, frameDelay: delay, to: dest)
                exported += 1
            }
            statusMessage = "Exported \(exported) GIFs to \(targetDir.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([targetDir])
        } catch {
            galleryError = "Bulk GIF export failed: \(error.localizedDescription)"
        }
    }

    public func exportSpritesheet(pet: InstalledCodexPet) {
        guard let sourceURL = spritesheetURL(for: pet) else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(pet.id)-sheet.webp"
        panel.title = "Export Sprite Sheet"
        guard panel.runModal() == .OK, let destURL = panel.url else { return }

        do {
            let data = try Data(contentsOf: sourceURL)
            try data.write(to: destURL, options: .atomic)
            statusMessage = "Exported \(destURL.lastPathComponent)"
        } catch {
            galleryError = "Sheet export failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Persistence & Bundled Starter Seeding

    private func ensureBundledDefaultPetInstalled() {
        let defaultID = "super-saiyan-goku-combat"
        let petDir = petsRootURL.appendingPathComponent(defaultID, isDirectory: true)
        let metaURL = petDir.appendingPathComponent("metadata.json")
        let sheetDest = petDir.appendingPathComponent("spritesheet.webp")

        if FileManager.default.fileExists(atPath: metaURL.path)
            && FileManager.default.fileExists(atPath: sheetDest.path)
        {
            return
        }

        try? FileManager.default.createDirectory(at: petDir, withIntermediateDirectories: true)
        if let bundled = Bundle.main.url(forResource: "super-saiyan-goku-combat", withExtension: "webp") {
            if !FileManager.default.fileExists(atPath: sheetDest.path) {
                try? FileManager.default.copyItem(at: bundled, to: sheetDest)
            }
        }

        let starter = InstalledCodexPet(
            id: defaultID,
            displayName: "Super Saiyan Goku Combat",
            description: "A combat-focused Super Saiyan Goku pet that meditates, flies, powers up, uses Instant Transmission, Kamehameha, and Kienzan training.",
            ownerHandle: "datpham",
            spriteVersionNumber: 2,
            tags: ["animated", "anime"],
            spritesheetFilename: "spritesheet.webp",
            sourceURL: "https://codex-pets.net/#/pets/super-saiyan-goku-combat",
            installedAt: Date(),
            isBundledDefault: true
        )
        if let data = try? JSONEncoder().encode(starter) {
            try? data.write(to: metaURL, options: .atomic)
        }
    }

    public func reloadInstalledPets() {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: petsRootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        var loaded: [InstalledCodexPet] = []
        for dir in entries {
            let metaURL = dir.appendingPathComponent("metadata.json")
            guard let data = try? Data(contentsOf: metaURL),
                  let pet = try? JSONDecoder().decode(InstalledCodexPet.self, from: data)
            else {
                continue
            }
            loaded.append(pet)
        }

        loaded.sort { lhs, rhs in
            if lhs.isBundledDefault != rhs.isBundledDefault {
                return lhs.isBundledDefault
            }
            return lhs.installedAt > rhs.installedAt
        }
        installedPets = loaded
    }
}
