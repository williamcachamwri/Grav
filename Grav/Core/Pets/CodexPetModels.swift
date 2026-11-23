import Foundation

/// Preferred screen anchor for Grav's floating desktop Codex Mini Pet.
public enum MiniPetPlacement: String, CaseIterable, Identifiable, Sendable {
    case topRight = "topRight"
    case bottomRight = "bottomRight"
    case bottomLeft = "bottomLeft"
    case free = "free"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .topRight: return "Top Right"
        case .bottomRight: return "Bottom Right"
        case .bottomLeft: return "Bottom Left"
        case .free: return "Free"
        }
    }
}

/// Sort order supported by `https://codex-pets.net/api/pets`.
public enum CodexPetSort: String, CaseIterable, Identifiable, Sendable {
    case popular = "popular"
    case newest = "new"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .popular: return "Popular"
        case .newest: return "Newest"
        }
    }
}

/// Exact 1:1 sprite-sheet animation states reverse-engineered from `https://codex-pets.net`
/// (`spriteVersionNumber == 1`: 9 rows, `spriteVersionNumber == 2`: 11 rows; always 8 columns).
public enum CodexPetAnimationState: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case idle = "idle"
    case runningRight = "running-right"
    case runningLeft = "running-left"
    case waving = "waving"
    case jumping = "jumping"
    case failed = "failed"
    case waiting = "waiting"
    case running = "running"
    case review = "review"
    case lookRightSide = "look-right-side"
    case lookLeftSide = "look-left-side"

    public var id: String { rawValue }

    public var rowIndex: Int {
        switch self {
        case .idle: return 0
        case .runningRight: return 1
        case .runningLeft: return 2
        case .waving: return 3
        case .jumping: return 4
        case .failed: return 5
        case .waiting: return 6
        case .running: return 7
        case .review: return 8
        case .lookRightSide: return 9
        case .lookLeftSide: return 10
        }
    }

    public var label: String {
        switch self {
        case .idle: return "Idle"
        case .runningRight: return "Run right"
        case .runningLeft: return "Run left"
        case .waving: return "Waving"
        case .jumping: return "Jumping"
        case .failed: return "Failed"
        case .waiting: return "Waiting"
        case .running: return "Running"
        case .review: return "Review"
        case .lookRightSide: return "Look right"
        case .lookLeftSide: return "Look left"
        }
    }

    /// Exact active animation frame count for this row (matching `codex-pets.net` `Ka` / `Fd` / `Xb`).
    public func frameCount(spriteVersion: Int) -> Int {
        switch self {
        case .idle: return 6 // Frame 6 (index 6) in v2 is neutral static pose; 0..5 are looping idle animation
        case .runningRight: return 8
        case .runningLeft: return 8
        case .waving: return 4
        case .jumping: return 5
        case .failed: return 8
        case .waiting: return 6
        case .running: return 6
        case .review: return 6
        case .lookRightSide: return spriteVersion >= 2 ? 8 : 6
        case .lookLeftSide: return spriteVersion >= 2 ? 8 : 6
        }
    }

    /// States available for a given sprite sheet version (`1` = 9 states, `2` = 11 states).
    public static func availableStates(for spriteVersion: Int) -> [CodexPetAnimationState] {
        if spriteVersion >= 2 {
            return allCases
        }
        return allCases.filter { $0.rowIndex < 9 }
    }

    /// Standard frame delay from `codex-pets.net` (`120 ms` = ~8.33 FPS).
    public static let baseFrameInterval: TimeInterval = 0.120
}

// MARK: - Remote API DTOs (`https://codex-pets.net/api/pets`)

public struct CodexPetsCatalogResponse: Codable, Sendable {
    public let pets: [CodexPetRemoteItem]
    public let total: Int?
}

public struct CodexPetDetailResponse: Codable, Sendable {
    public let pet: CodexPetRemoteItem
}

public struct CodexPetValidationReport: Codable, Equatable, Sendable {
    public let manifestId: String?
    public let atlasSize: String?
    public let cellSize: String?
    public let statesDetected: Int?
    public let spriteVersionNumber: Int?
}

public struct CodexPetRemoteItem: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let description: String?
    public let spriteVersionNumber: Int?
    public let kind: String?
    public let ownerHandle: String?
    public let ownerName: String?
    public let viewCount: Int?
    public let likeCount: Int?
    public let tags: [String]?
    public let spritesheetUrl: String
    public let posterUrl: String?
    public let previewUrl: String?
    public let validationReport: CodexPetValidationReport?

    public var resolvedSpriteVersion: Int {
        if let v = spriteVersionNumber, v >= 1 && v <= 2 { return v }
        if let v = validationReport?.spriteVersionNumber, v >= 1 && v <= 2 { return v }
        if validationReport?.atlasSize == "1536x2288" || validationReport?.statesDetected == 11 {
            return 2
        }
        return 1
    }

    public var resolvedSpritesheetURL: URL? {
        Self.resolveURL(spritesheetUrl)
    }

    public var resolvedPosterURL: URL? {
        posterUrl.flatMap { Self.resolveURL($0) } ?? previewUrl.flatMap { Self.resolveURL($0) }
    }

    public var webPageURL: URL? {
        URL(string: "https://codex-pets.net/#/pets/\(id)")
    }

    private static func resolveURL(_ raw: String) -> URL? {
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        if raw.hasPrefix("/") {
            return URL(string: "https://codex-pets.net\(raw)")
        }
        return URL(string: "https://codex-pets.net/\(raw)")
    }
}

// MARK: - Installed Local Pet Record

public struct InstalledCodexPet: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let description: String
    public let ownerHandle: String
    public let spriteVersionNumber: Int
    public let tags: [String]
    public let spritesheetFilename: String
    public let sourceURL: String?
    public let installedAt: Date
    public let isBundledDefault: Bool

    public init(
        id: String,
        displayName: String,
        description: String = "",
        ownerHandle: String = "codex-pets",
        spriteVersionNumber: Int = 2,
        tags: [String] = [],
        spritesheetFilename: String = "spritesheet.webp",
        sourceURL: String? = nil,
        installedAt: Date = Date(),
        isBundledDefault: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.ownerHandle = ownerHandle
        self.spriteVersionNumber = spriteVersionNumber
        self.tags = tags
        self.spritesheetFilename = spritesheetFilename
        self.sourceURL = sourceURL
        self.installedAt = installedAt
        self.isBundledDefault = isBundledDefault
    }
}

// MARK: - URL / Query Parser

public enum CodexPetSearchInput: Equatable, Sendable {
    case query(String)
    case directPetSlug(String)

    /// Parses user input from the search bar:
    /// - `https://codex-pets.net/#/pets/super-saiyan-goku-combat` -> `.directPetSlug("super-saiyan-goku-combat")`
    /// - `https://codex-pets.net/#/?q=goku` -> `.query("goku")`
    /// - `goku` -> `.query("goku")`
    public static func parse(_ raw: String) -> CodexPetSearchInput {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .query("") }

        if let range = trimmed.range(of: "/pets/") {
            let tail = String(trimmed[range.upperBound...])
            let slug = tail
                .split(whereSeparator: { $0 == "?" || $0 == "#" || $0 == "/" })
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !slug.isEmpty {
                return .directPetSlug(slug)
            }
        }

        if let qRange = trimmed.range(of: "q=") {
            let tail = String(trimmed[qRange.upperBound...])
            let rawQ = tail.split(separator: "&").first.map(String.init) ?? ""
            let decoded = rawQ.removingPercentEncoding ?? rawQ
            return .query(decoded.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return .query(trimmed)
    }
}
