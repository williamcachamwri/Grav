import Foundation
import Observation

/// Primary navigation tabs for Grav's System Settings–style Preferences window.
public enum SettingsTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case general
    case notchHUD
    case miniPet
    case telemetry
    case menuBar
    case shortcuts
    case permissions
    case about

    public var id: String { rawValue }

    public static let storageKey = "grav.settings.lastSelectedTab"

    public static var lastSelected: SettingsTab {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let tab = SettingsTab(rawValue: raw)
        else {
            return .general
        }
        return tab
    }

    public var title: String {
        switch self {
        case .general: return "General"
        case .notchHUD: return "Notch HUD"
        case .miniPet: return "Mini Pet"
        case .telemetry: return "Telemetry"
        case .menuBar: return "Menu Bar"
        case .shortcuts: return "Shortcuts"
        case .permissions: return "Permissions"
        case .about: return "About"
        }
    }

    /// SF Symbol rendered duotone on each sidebar row's glossy near-black squircle tile.
    public var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .notchHUD: return "rectangle.topthird.inset.filled"
        case .miniPet: return "pawprint.fill"
        case .telemetry: return "waveform.path.ecg"
        case .menuBar: return "menubar.rectangle"
        case .shortcuts: return "command"
        case .permissions: return "lock.shield.fill"
        case .about: return "info.circle"
        }
    }

    /// Alias for callers expecting `systemImage`.
    public var systemImage: String { symbol }

    /// Extra non-displayed terms matched by the sidebar search engine below title matches.
    public var searchKeywords: [String] {
        switch self {
        case .general:
            return ["startup", "login", "appearance", "theme", "light", "dark", "system", "liquid glass", "onboarding", "welcome"]
        case .notchHUD:
            return ["notch", "hud", "hover", "pin", "peek", "expand", "collapse", "dynamic island", "toggle", "delay", "haptics", "sounds", "focus", "steps", "tokens"]
        case .miniPet:
            return ["pet", "mini pet", "codex", "codex-pets", "goku", "gif", "export", "spritesheet", "pixel", "companion", "download", "gallery", "roaming"]
        case .telemetry:
            return ["antigravity", "brain", "transcript", "session", "conversation", "tokens", "model", "pause", "resume", "watcher"]
        case .menuBar:
            return ["status", "item", "icon", "tray", "top bar", "menu"]
        case .shortcuts:
            return ["keyboard", "hotkey", "keys", "keycap", "bindings", "tabs", "escape"]
        case .permissions:
            return ["folder", "access", "privacy", "security", "brain directory", "login item", "service management"]
        case .about:
            return ["version", "build", "notchkit", "architecture", "info", "welcome"]
        }
    }

    /// Sidebar tabs grouped into 3 System Settings sections separated by vertical breathing room.
    public static let groups: [[SettingsTab]] = [
        [.general, .notchHUD, .miniPet, .telemetry],
        [.menuBar, .shortcuts, .permissions],
        [.about],
    ]

    /// Every tab in sidebar reading order.
    public static let sidebarOrder: [SettingsTab] = groups.flatMap { $0 }
}

// MARK: - Search Models

/// Searchable item in the Settings sidebar: either a tab page or an individual setting row inside it.
public struct SettingsSearchEntry: Identifiable, Hashable, Sendable {
    public let tab: SettingsTab
    public let section: String?
    public let title: String
    public let detail: String?
    public let keywords: [String]
    /// When `true`, `title` matches a `SettingRow` scroll anchor that flashes on jump.
    public let anchored: Bool
    /// `true` when this entry represents a top-level tab rather than a row inside it.
    public let isPage: Bool

    public var id: String {
        isPage ? tab.rawValue : "\(tab.rawValue)/\(section ?? "")/\(title)"
    }

    public init(
        _ tab: SettingsTab,
        section: String?,
        title: String,
        detail: String? = nil,
        keywords: [String] = [],
        anchored: Bool = true
    ) {
        self.tab = tab
        self.section = section
        self.title = title
        self.detail = detail
        self.keywords = keywords
        self.anchored = anchored
        self.isPage = false
    }

    public init(page tab: SettingsTab) {
        self.tab = tab
        self.section = nil
        self.title = tab.title
        self.detail = nil
        self.keywords = tab.searchKeywords
        self.anchored = false
        self.isPage = true
    }

    /// Complete catalog of every searchable setting across all Grav Settings panes.
    public static func catalog() -> [SettingsSearchEntry] {
        [
            // General
            SettingsSearchEntry(
                .general,
                section: "Startup",
                title: "Launch at Login",
                detail: "Start Grav automatically when you sign in to macOS.",
                keywords: ["startup", "boot", "login item", "auto start"]
            ),
            SettingsSearchEntry(
                .general,
                section: "Startup",
                title: "Show Menu Bar Icon",
                detail: "Display Grav's orbital telemetry icon in the macOS menu bar.",
                keywords: ["status bar", "menu bar", "tray", "hide icon"]
            ),
            SettingsSearchEntry(
                .general,
                section: "Appearance",
                title: "Appearance",
                detail: "Switch between System, Light, and Dark window appearances.",
                keywords: ["theme", "light mode", "dark mode", "auto", "color scheme"]
            ),
            SettingsSearchEntry(
                .general,
                section: "Appearance",
                title: "Liquid Glass",
                detail: "Enable translucent Liquid Glass materials across Grav surfaces.",
                keywords: ["glass", "blur", "vibrancy", "translucency", "macos 26"]
            ),
            SettingsSearchEntry(
                .general,
                section: "Help",
                title: "Restart Onboarding",
                detail: "Reopen the welcome experience and live Antigravity connection check.",
                keywords: ["welcome", "walkthrough", "tour", "setup", "replay"]
            ),

            // Notch HUD
            SettingsSearchEntry(
                .notchHUD,
                section: "Interaction",
                title: "Hover to Expand",
                detail: "Rest the pointer over the notch to smoothly expand live telemetry.",
                keywords: ["pointer", "mouse", "trigger", "click only", "open"]
            ),
            SettingsSearchEntry(
                .notchHUD,
                section: "Interaction",
                title: "Pin Notch Open",
                detail: "Keep the expanded telemetry panel visible until dismissed manually.",
                keywords: ["stay open", "lock", "sticky", "docked"]
            ),
            SettingsSearchEntry(
                .notchHUD,
                section: "Interaction",
                title: "Auto-Peek on Events",
                detail: "Briefly surface the notch on new thinking bursts, file edits, and completed commands.",
                keywords: ["notify", "alert", "toast", "activity", "thinking", "command"]
            ),
            SettingsSearchEntry(
                .notchHUD,
                section: "Interaction",
                title: "Hover Open Delay",
                detail: "Adjust how long the pointer must rest on the notch before expanding.",
                keywords: ["hover", "delay", "timing", "speed", "ms"]
            ),
            SettingsSearchEntry(
                .notchHUD,
                section: "Interaction",
                title: "Auto-Expand on Input Needed",
                detail: "Automatically open the Notch HUD whenever Antigravity asks a question or waits for approval.",
                keywords: ["waiting", "input", "ask question", "expand", "alert"]
            ),
            SettingsSearchEntry(
                .notchHUD,
                section: "Display & Feedback",
                title: "Show Live Focus",
                detail: "Show Antigravity's current update_focus status text in the collapsed Notch pill.",
                keywords: ["focus", "marquee", "collapsed", "status"]
            ),
            SettingsSearchEntry(
                .notchHUD,
                section: "Display & Feedback",
                title: "Show Step Progress Ring",
                detail: "Display the circular N/M step progress indicator in the collapsed Notch pill.",
                keywords: ["steps", "progress", "ring", "checklist"]
            ),
            SettingsSearchEntry(
                .notchHUD,
                section: "Display & Feedback",
                title: "Show Idle Token Count",
                detail: "Display cumulative compact session tokens while Antigravity is idle.",
                keywords: ["tokens", "idle", "metrics", "compact"]
            ),
            SettingsSearchEntry(
                .notchHUD,
                section: "Display & Feedback",
                title: "Haptic Feedback",
                detail: "Play subtle trackpad haptics when expanding the Notch HUD.",
                keywords: ["haptic", "taptic", "vibration", "trackpad"]
            ),
            SettingsSearchEntry(
                .notchHUD,
                section: "Display & Feedback",
                title: "Play Sounds",
                detail: "Play crisp subtle sound cues for completions, errors, and Mini Pet taps.",
                keywords: ["audio", "sound", "chime", "mute"]
            ),

            // Mini Pet
            SettingsSearchEntry(
                .miniPet,
                section: "Desktop Companion",
                title: "Show Floating Desktop Pet",
                detail: "Keep a reactive Codex pixel companion floating on your desktop.",
                keywords: ["pet", "codex", "goku", "toggle", "enable", "tuck away", "desktop"]
            ),
            SettingsSearchEntry(
                .miniPet,
                section: "Desktop Companion",
                title: "Snap Position",
                detail: "Snap the floating desktop pet to Top Right, Bottom Right, Bottom Left, or drag freely.",
                keywords: ["position", "corner", "top right", "bottom right", "drag", "free"]
            ),
            SettingsSearchEntry(
                .miniPet,
                section: "Desktop Companion",
                title: "Pet Size",
                detail: "Adjust size of the floating desktop pet from 48 pt to 144 pt.",
                keywords: ["scale", "height", "size", "resize", "slider"]
            ),
            SettingsSearchEntry(
                .miniPet,
                section: "Desktop Companion",
                title: "Animation Speed",
                detail: "Speed up or slow down the Mini Pet's sprite frame rate.",
                keywords: ["fps", "cadence", "tempo", "speed"]
            ),
            SettingsSearchEntry(
                .miniPet,
                section: "Desktop Companion",
                title: "Live Status Bubble",
                detail: "Display Antigravity's live focus, diff, or prompt directly below the pet.",
                keywords: ["bubble", "speech", "tooltip", "status", "codex"]
            ),
            SettingsSearchEntry(
                .miniPet,
                section: "Desktop Companion",
                title: "Float Above All Windows",
                detail: "Keep the desktop pet floating over apps across all macOS Spaces.",
                keywords: ["always on top", "floating", "overlay", "spaces"]
            ),
            SettingsSearchEntry(
                .miniPet,
                section: "Desktop Companion",
                title: "Idle Roaming & Patrol",
                detail: "Allow the Mini Pet to look around and patrol while Antigravity is idle.",
                keywords: ["roam", "patrol", "look", "idle"]
            ),
            SettingsSearchEntry(
                .miniPet,
                section: "Desktop Companion",
                title: "Click to Interact",
                detail: "Click the desktop pet to trigger wave and jump animations.",
                keywords: ["click", "tap", "wave", "jump", "interact"]
            ),
            SettingsSearchEntry(
                .miniPet,
                section: "Codex Pets Gallery",
                title: "Download & Export GIFs",
                detail: "Search codex-pets.net, install new pixel pets, or export state GIFs and sprite sheets.",
                keywords: ["codex-pets", "gif", "export", "download", "sheet", "search"],
                anchored: false
            ),

            // Quick Actions
            SettingsSearchEntry(
                .notchHUD,
                section: "Quick Actions",
                title: "Notch Status",
                detail: "Inspect the current live telemetry state driving the Notch HUD.",
                keywords: ["state", "idle", "thinking", "running", "live"]
            ),
            SettingsSearchEntry(
                .notchHUD,
                section: "Quick Actions",
                title: "Toggle Notch HUD",
                detail: "Immediately expand or collapse the Notch HUD panel.",
                keywords: ["show", "hide", "expand", "collapse", "preview"]
            ),

            // Telemetry
            SettingsSearchEntry(
                .telemetry,
                section: "Antigravity Runtime",
                title: "Antigravity App",
                detail: "Live installation and process status for Google Antigravity.",
                keywords: ["installed", "running", "focus", "open", "runtime"]
            ),
            SettingsSearchEntry(
                .telemetry,
                section: "Antigravity Runtime",
                title: "Brain Directory",
                detail: "Local transcript directory monitored via event-driven kqueue watchers.",
                keywords: ["path", "folder", "finder", "gemini", "jsonl", "transcript"]
            ),
            SettingsSearchEntry(
                .telemetry,
                section: "Sessions & Monitoring",
                title: "Active Conversations",
                detail: "Number of discovered local Antigravity conversation workspaces.",
                keywords: ["count", "sessions", "workspaces", "chats"]
            ),
            SettingsSearchEntry(
                .telemetry,
                section: "Sessions & Monitoring",
                title: "Active Session",
                detail: "Choose which discovered conversation Grav streams into the Notch HUD.",
                keywords: ["picker", "switch", "pin session", "conversation"]
            ),
            SettingsSearchEntry(
                .telemetry,
                section: "Sessions & Monitoring",
                title: "Pause Telemetry",
                detail: "Temporarily stop live transcript and task log observation.",
                keywords: ["mute", "stop", "resume", "monitoring"]
            ),
            SettingsSearchEntry(
                .telemetry,
                section: "Session Metrics",
                title: "Active Model",
                detail: "Model reported by the latest Antigravity planner step.",
                keywords: ["gemini", "claude", "llm", "planner"]
            ),
            SettingsSearchEntry(
                .telemetry,
                section: "Session Metrics",
                title: "Token Totals",
                detail: "Cumulative input, cache read, and output tokens for the active session.",
                keywords: ["usage", "tokens", "context", "cache", "metrics"]
            ),

            // Menu Bar
            SettingsSearchEntry(
                .menuBar,
                section: "Menu Bar",
                title: "Show Menu Bar Icon",
                detail: "Keep Grav accessible from the macOS menu bar with live status.",
                keywords: ["status item", "icon", "top bar", "preview"]
            ),
            SettingsSearchEntry(
                .menuBar,
                section: "Menu Content",
                title: "Show Mini Pet in Header",
                detail: "Display your equipped Codex Mini Pet inside the menu bar status header.",
                keywords: ["pet", "header", "menu bar", "sprite"]
            ),
            SettingsSearchEntry(
                .menuBar,
                section: "Menu Content",
                title: "Show Token & Context Metrics",
                detail: "Include token totals and context window percentage in the menu bar header.",
                keywords: ["tokens", "context", "metrics", "menu bar"]
            ),
            SettingsSearchEntry(
                .menuBar,
                section: "Menu Content",
                title: "Show Quick HUD Toggles",
                detail: "Show Pin Notch, Hover, Auto-Peek, and Sound toggles in the menu bar dropdown.",
                keywords: ["toggles", "pin", "hover", "sounds", "quick"]
            ),
            SettingsSearchEntry(
                .menuBar,
                section: "Menu Content",
                title: "Show Mini Pet Submenu",
                detail: "Quickly switch pets, snap position, or tuck away your desktop pet.",
                keywords: ["submenu", "pet", "menu bar"]
            ),
            SettingsSearchEntry(
                .menuBar,
                section: "Menu Content",
                title: "Show Active Sessions Submenu",
                detail: "Switch Antigravity conversations directly from the menu bar.",
                keywords: ["sessions", "conversations", "submenu"]
            ),

            // Shortcuts
            SettingsSearchEntry(
                .shortcuts,
                section: "Notch HUD",
                title: "Live Tab",
                detail: "Jump to the Live thinking and activity stream in the Notch HUD.",
                keywords: ["1", "tab", "stream", "thinking"]
            ),
            SettingsSearchEntry(
                .shortcuts,
                section: "Notch HUD",
                title: "Files Tab",
                detail: "Jump to modified files and inline diff previews in the Notch HUD.",
                keywords: ["2", "tab", "diff", "edits"]
            ),
            SettingsSearchEntry(
                .shortcuts,
                section: "Notch HUD",
                title: "Terminal Tab",
                detail: "Jump to live command executions and streaming logs in the Notch HUD.",
                keywords: ["3", "tab", "commands", "shell", "logs"]
            ),
            SettingsSearchEntry(
                .shortcuts,
                section: "Notch HUD",
                title: "Collapse Notch",
                detail: "Dismiss the expanded Notch HUD back to its compact pill.",
                keywords: ["esc", "escape", "close", "dismiss"]
            ),
            SettingsSearchEntry(
                .shortcuts,
                section: "Notch HUD",
                title: "Copy Log or Diff",
                detail: "Copy the active command log or selected file diff to the clipboard.",
                keywords: ["cmd c", "clipboard", "copy", "diff", "log"]
            ),
            SettingsSearchEntry(
                .shortcuts,
                section: "Settings Window",
                title: "Search Settings",
                detail: "Focus the sidebar search field from anywhere in Settings.",
                keywords: ["cmd f", "find", "filter", "search"]
            ),
            SettingsSearchEntry(
                .shortcuts,
                section: "Settings Window",
                title: "Navigate Back",
                detail: "Return to the previous Settings pane in history.",
                keywords: ["history", "previous", "back"]
            ),
            SettingsSearchEntry(
                .shortcuts,
                section: "Settings Window",
                title: "Navigate Forward",
                detail: "Move forward to the next Settings pane in history.",
                keywords: ["history", "next", "forward"]
            ),

            // Permissions
            SettingsSearchEntry(
                .permissions,
                section: "Permissions",
                title: "Antigravity Brain Directory",
                detail: "Read access to ~/.gemini/antigravity/brain for local transcript telemetry.",
                keywords: ["folder access", "grant", "bookmark", "read", "disk"]
            ),
            SettingsSearchEntry(
                .permissions,
                section: "Permissions",
                title: "Launch at Login",
                detail: "macOS Service Management login item registration status.",
                keywords: ["smappservice", "login items", "startup", "background"]
            ),

            // About
            SettingsSearchEntry(
                .about,
                section: "About",
                title: "Version & Architecture",
                detail: "Grav version, NotchKit engine, and macOS native stack details.",
                keywords: ["version", "build", "notchkit", "swiftui", "appkit"],
                anchored: false
            ),
        ]
    }
}

/// One matched entry with relevance score and matched title spans for bold highlighting.
public struct SettingsSearchResult: Identifiable, Sendable {
    public let entry: SettingsSearchEntry
    public let score: Double
    public let titleHighlights: [Range<String.Index>]

    public var id: String { entry.id }
}

/// Results grouped per tab: the tab header row followed by its matching setting rows.
public struct SettingsSearchGroup: Identifiable, Sendable {
    public let tab: SettingsTab
    public let pageResult: SettingsSearchResult?
    public let settings: [SettingsSearchResult]

    public var id: SettingsTab { tab }
}

// MARK: - Search Engine (Ported 1:1 from Snapzy's PreferencesSearchEngine)

/// Ranked, typo-tolerant search engine over Settings tabs and catalogued rows.
public struct SettingsSearchEngine: Sendable {
    private let documents: [Document]

    public static func standard() -> SettingsSearchEngine {
        SettingsSearchEngine(
            entries: SettingsTab.sidebarOrder.map { SettingsSearchEntry(page: $0) }
                + SettingsSearchEntry.catalog()
        )
    }

    public init(entries: [SettingsSearchEntry]) {
        documents = entries.enumerated().map { Document(entry: $1, order: $0) }
    }

    public func search(_ query: String, limit: Int = 60) -> [SettingsSearchResult] {
        let normalizedQuery = SearchText(query)
        let tokens = normalizedQuery.words.map { Array(normalizedQuery.chars[$0]) }
        guard !tokens.isEmpty else { return [] }

        let phrase = tokens.map { String($0) }.joined(separator: " ")
        var scored: [(result: SettingsSearchResult, order: Int)] = []

        for document in documents {
            guard let match = document.match(tokens: tokens, phrase: phrase) else { continue }
            scored.append((match, document.order))
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.result.score != rhs.result.score { return lhs.result.score > rhs.result.score }
                return lhs.order < rhs.order
            }
            .prefix(limit)
            .map(\.result)
    }

    public func groupedSearch(_ query: String) -> [SettingsSearchGroup] {
        let results = search(query)
        var order: [SettingsTab] = []
        var pages: [SettingsTab: SettingsSearchResult] = [:]
        var settings: [SettingsTab: [SettingsSearchResult]] = [:]

        for result in results {
            let tab = result.entry.tab
            if pages[tab] == nil && settings[tab] == nil { order.append(tab) }
            if result.entry.isPage {
                pages[tab] = result
            } else {
                settings[tab, default: []].append(result)
            }
        }

        return order.map {
            SettingsSearchGroup(tab: $0, pageResult: pages[$0], settings: settings[$0] ?? [])
        }
    }
}

private extension SettingsSearchEngine {
    enum Weight {
        static let title = 1.0
        static let section = 0.7
        static let keyword = 0.6
        static let detail = 0.35
        static let threshold = 0.2
    }

    enum Tier {
        static let exact = 1.0
        static let prefix = 0.9
        static let initials = 0.8
        static let abbreviation = 0.6
        static let substring = 0.5
        static let typo = 0.45
    }

    struct TokenMatch: Sendable {
        var score: Double
        var spans: [Range<Int>]
    }

    struct Document: Sendable {
        let entry: SettingsSearchEntry
        let order: Int
        let title: SearchText
        let section: SearchText?
        let detail: SearchText?
        let keywords: [SearchText]

        init(entry: SettingsSearchEntry, order: Int) {
            self.entry = entry
            self.order = order
            self.title = SearchText(entry.title)
            self.section = entry.section.map(SearchText.init)
            self.detail = entry.detail.map(SearchText.init)
            self.keywords = entry.keywords.map(SearchText.init)
        }

        func match(tokens: [[Character]], phrase: String) -> SettingsSearchResult? {
            var total = 0.0
            var allInTitle = true
            var spans: [Range<Int>] = []

            for token in tokens {
                var best = 0.0
                if let hit = title.bestMatch(for: token) {
                    best = hit.score * Weight.title
                    spans += hit.spans
                } else {
                    allInTitle = false
                }
                if let section, let hit = section.bestMatch(for: token) {
                    best = max(best, hit.score * Weight.section)
                }
                for keyword in keywords {
                    if let hit = keyword.bestMatch(for: token) {
                        best = max(best, hit.score * Weight.keyword)
                    }
                }
                if let detail, let hit = detail.bestMatch(for: token) {
                    best = max(best, hit.score * Weight.detail)
                }
                guard best > 0 else { return nil }
                total += best
            }

            var score = total / Double(tokens.count)
            if allInTitle { score += 0.1 }
            if title.folded.hasPrefix(phrase) { score += 0.15 }
            if entry.isPage { score += 0.05 }
            guard score >= Weight.threshold else { return nil }

            return SettingsSearchResult(
                entry: entry,
                score: score,
                titleHighlights: title.originalRanges(for: spans)
            )
        }
    }

    struct SearchText: Sendable {
        let chars: [Character]
        let origins: [Range<String.Index>]
        let words: [Range<Int>]
        let folded: String

        init(_ text: String) {
            var chars: [Character] = []
            var origins: [Range<String.Index>] = []
            var index = text.startIndex

            while index < text.endIndex {
                let next = text.index(after: index)
                for character in Self.fold(text[index]) {
                    chars.append(character)
                    origins.append(index..<next)
                }
                index = next
            }

            var words: [Range<Int>] = []
            var start: Int?
            for (offset, character) in chars.enumerated() {
                let isWordCharacter = character.isLetter || character.isNumber
                if isWordCharacter, start == nil {
                    start = offset
                } else if !isWordCharacter, let wordStart = start {
                    words.append(wordStart..<offset)
                    start = nil
                }
            }
            if let start { words.append(start..<chars.count) }

            self.chars = chars
            self.origins = origins
            self.words = words
            self.folded = words.map { String(chars[$0]) }.joined(separator: " ")
        }

        private static func fold(_ character: Character) -> String {
            let folded = String(character).folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: nil
            )
            return folded == "đ" ? "d" : folded
        }

        func originalRanges(for spans: [Range<Int>]) -> [Range<String.Index>] {
            let covered = Set(spans.flatMap { $0 }).sorted()
            var ranges: [Range<String.Index>] = []
            for offset in covered {
                let origin = origins[offset]
                if let last = ranges.last, last.upperBound >= origin.lowerBound {
                    ranges[ranges.count - 1] = last.lowerBound..<max(last.upperBound, origin.upperBound)
                } else {
                    ranges.append(origin)
                }
            }
            return ranges
        }

        func bestMatch(for token: [Character]) -> TokenMatch? {
            var best: TokenMatch?

            func consider(_ score: Double, _ spans: [Range<Int>]) {
                if score > (best?.score ?? 0) { best = TokenMatch(score: score, spans: spans) }
            }

            for word in words {
                let wordChars = chars[word]
                if wordChars.elementsEqual(token) {
                    consider(Tier.exact, [word])
                    return best
                }
                if wordChars.starts(with: token) {
                    let coverage = Double(token.count) / Double(wordChars.count)
                    consider(Tier.prefix - 0.1 * (1 - coverage), [word.lowerBound..<word.lowerBound + token.count])
                }
            }

            if token.count >= 2, let spans = initialsMatch(token) {
                consider(Tier.initials, spans)
            }

            if token.count >= 2 {
                for word in words where chars[word.lowerBound] == token[0] {
                    if let spans = subsequence(token, in: word) {
                        consider(Tier.abbreviation, spans)
                    }
                }
            }

            if token.count >= 3, let start = firstOccurrence(of: token) {
                consider(Tier.substring, [start..<start + token.count])
            }

            if best == nil, token.count >= 4 {
                let allowed = token.count >= 8 ? 2 : 1
                for word in words where chars[word].count >= 3 {
                    let wordChars = Array(chars[word])
                    let prefix = Array(wordChars.prefix(token.count))
                    let distance = min(
                        SettingsSearchEngine.editDistance(token, wordChars, limit: allowed),
                        SettingsSearchEngine.editDistance(token, prefix, limit: allowed)
                    )
                    if distance <= allowed {
                        consider(Tier.typo - 0.1 * Double(distance - 1), [word])
                    }
                }
            }

            return best
        }

        private func initialsMatch(_ token: [Character]) -> [Range<Int>]? {
            guard words.count >= token.count else { return nil }
            for start in 0...(words.count - token.count) {
                let run = words[start..<start + token.count]
                if zip(run, token).allSatisfy({ chars[$0.lowerBound] == $1 }) {
                    return run.map { $0.lowerBound..<$0.lowerBound + 1 }
                }
            }
            return nil
        }

        private func subsequence(_ token: [Character], in word: Range<Int>) -> [Range<Int>]? {
            guard token.count < word.count else { return nil }
            var spans: [Range<Int>] = []
            var tokenIndex = 0
            for offset in word where tokenIndex < token.count && chars[offset] == token[tokenIndex] {
                spans.append(offset..<offset + 1)
                tokenIndex += 1
            }
            return tokenIndex == token.count ? spans : nil
        }

        private func firstOccurrence(of token: [Character]) -> Int? {
            guard token.count <= chars.count else { return nil }
            for start in 0...(chars.count - token.count)
            where chars[start..<start + token.count].elementsEqual(token) {
                return start
            }
            return nil
        }
    }

    static func editDistance(_ a: [Character], _ b: [Character], limit: Int) -> Int {
        if abs(a.count - b.count) > limit { return limit + 1 }
        if a.isEmpty || b.isEmpty { return max(a.count, b.count) }

        var previousPrevious = [Int](repeating: 0, count: b.count + 1)
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            var rowMinimum = current[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    value = min(value, previousPrevious[j - 2] + 1)
                }
                current[j] = value
                rowMinimum = min(rowMinimum, value)
            }
            if rowMinimum > limit { return limit + 1 }
            (previousPrevious, previous, current) = (previous, current, previousPrevious)
        }
        return previous[b.count]
    }
}

// MARK: - Navigation State

/// Pending scroll-and-highlight jump triggered by selecting a search result.
public struct SettingsRevealRequest: Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let scrolls: Bool

    public init(id: UUID = UUID(), title: String, scrolls: Bool) {
        self.id = id
        self.title = title
        self.scrolls = scrolls
    }
}

/// Shared observable navigation state with back/forward history and search-jump highlighting.
@MainActor
@Observable
public final class SettingsNavigationState {
    public var selectedTab: SettingsTab {
        didSet {
            UserDefaults.standard.set(selectedTab.rawValue, forKey: SettingsTab.storageKey)
        }
    }

    /// Pending setting row scroll target triggered by a sidebar search jump.
    public private(set) var revealRequest: SettingsRevealRequest?

    /// Title of the setting row currently flashing after a search jump.
    public private(set) var highlightedSetting: String?

    public private(set) var backStack: [SettingsTab] = []
    public private(set) var forwardStack: [SettingsTab] = []

    private var highlightClearTask: Task<Void, Never>?

    public var canGoBack: Bool { !backStack.isEmpty }
    public var canGoForward: Bool { !forwardStack.isEmpty }

    public var title: String { selectedTab.title }

    public init(initialTab: SettingsTab? = nil) {
        self.selectedTab = initialTab ?? SettingsTab.lastSelected
    }

    /// Directly selects a tab and pushes the previous tab onto the back stack.
    public func select(_ tab: SettingsTab) {
        guard tab != selectedTab else { return }
        backStack.append(selectedTab)
        forwardStack.removeAll()
        selectedTab = tab
    }

    /// Opens a search result's tab and schedules a scroll-and-flash jump when anchored.
    public func reveal(_ entry: SettingsSearchEntry) {
        select(entry.tab)
        guard entry.anchored else {
            revealRequest = nil
            return
        }
        revealRequest = SettingsRevealRequest(title: entry.title, scrolls: true)
    }

    /// Completes a scroll request and flashes the target row briefly.
    public func didReveal(_ request: SettingsRevealRequest) {
        guard revealRequest == request else { return }
        revealRequest = nil
        guard request.scrolls else { return }

        highlightedSetting = request.title
        highlightClearTask?.cancel()
        highlightClearTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(1600))
            } catch {
                return
            }
            guard !Task.isCancelled, self?.highlightedSetting == request.title else { return }
            self?.highlightedSetting = nil
        }
    }

    /// Navigates back to the previous tab in history.
    public func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(selectedTab)
        selectedTab = previous
    }

    /// Navigates forward to the next tab in history.
    public func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(selectedTab)
        selectedTab = next
    }
}
