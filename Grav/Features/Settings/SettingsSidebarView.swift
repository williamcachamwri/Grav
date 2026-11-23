import AppKit
import SwiftUI

/// System Settings–style sidebar: capsule search field (⌘F), profile header, and grouped icon rows.
struct SettingsSidebarView: View {
    let navigationState: SettingsNavigationState
    let store: AntigravityTelemetryStore
    var onReplayWelcome: (() -> Void)? = nil

    @State private var query = ""
    @State private var searchGroups: [SettingsSearchGroup] = []
    /// Result last opened from the list so keyboard arrow movement continues from it.
    @State private var activeResultID: String?
    @FocusState private var isSearchFocused: Bool
    @Namespace private var sidebarSelectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let searchEngine = SettingsSearchEngine.standard()

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Results in display order: each tab row followed by its matching setting rows.
    private var flatResults: [SettingsSearchEntry] {
        searchGroups.flatMap { group in
            [group.pageResult?.entry ?? SettingsSearchEntry(page: group.tab)] + group.settings.map(\.entry)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 10)

            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    if isSearching {
                        searchResultList
                    } else {
                        browseContent
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .focusable()
            .focusEffectDisabled()
            .onMoveCommand(perform: moveSelection)
        }
        .background {
            // ⌘F jumps to the search field, matching Finder and macOS System Settings.
            Button("") { isSearchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
        .onChange(of: query) { _, newValue in
            searchGroups = Self.searchEngine.groupedSearch(newValue)
            activeResultID = nil
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isSearchFocused)
                .onSubmit {
                    let results = flatResults
                    if let entry = results.first(where: { $0.id == activeResultID }) ?? results.first {
                        open(entry)
                    }
                }
                .onMoveCommand(perform: moveSelection)
                .onExitCommand { query = "" }

            if isSearching {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(isSearchFocused ? 0.12 : 0.04), lineWidth: 1))
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchResultList: some View {
        if searchGroups.isEmpty {
            Text("No Results")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        } else {
            VStack(spacing: 10) {
                ForEach(searchGroups) { group in
                    VStack(spacing: 2) {
                        SettingsSidebarRow(
                            tab: group.tab,
                            isSelected: isPageRowSelected(group.tab)
                        ) {
                            open(group.pageResult?.entry ?? SettingsSearchEntry(page: group.tab))
                        }

                        ForEach(group.settings) { result in
                            SettingsSidebarSearchResultRow(
                                result: result,
                                isSelected: activeResultID == result.id
                            ) {
                                open(result.entry)
                            }
                        }
                    }
                }
            }
        }
    }

    private func isPageRowSelected(_ tab: SettingsTab) -> Bool {
        guard navigationState.selectedTab == tab else { return false }
        return activeResultID == nil || activeResultID == tab.rawValue
    }

    private func open(_ entry: SettingsSearchEntry) {
        activeResultID = entry.id
        navigationState.reveal(entry)
    }

    // MARK: - Browse List

    private var browseContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSidebarProfileHeader(
                store: store,
                isSelected: navigationState.selectedTab == .about,
                onReplayWelcome: onReplayWelcome
            ) {
                navigationState.select(.about)
            }

            ForEach(Array(SettingsTab.groups.enumerated()), id: \.offset) { groupIdx, group in
                VStack(spacing: 2) {
                    if groupIdx > 0 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.06))
                            .frame(height: 0.5)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 6)
                    }
                    ForEach(group) { tab in
                        row(for: tab)
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.14), value: navigationState.selectedTab)
    }

    private func row(for tab: SettingsTab) -> some View {
        let badgeText: String? = {
            switch tab {
            case .miniPet:
                let count = CodexPetsStore.shared.installedPets.count
                return count > 0 ? "\(count)" : nil
            case .telemetry:
                return store.state.isActive && !store.isPaused ? "LIVE" : nil
            default:
                return nil
            }
        }()

        return SettingsSidebarRow(
            tab: tab,
            isSelected: navigationState.selectedTab == tab,
            badgeText: badgeText,
            isLiveBadge: tab == .telemetry && store.state.isActive && !store.isPaused,
            selectionNamespace: sidebarSelectionNamespace
        ) {
            navigationState.select(tab)
        }
    }

    // MARK: - Keyboard Navigation

    private func moveSelection(_ direction: MoveCommandDirection) {
        let step: Int
        switch direction {
        case .up:
            step = -1
        case .down:
            step = 1
        default:
            return
        }

        if isSearching {
            let order = flatResults
            guard !order.isEmpty else { return }
            let current = order.firstIndex { $0.id == activeResultID }
            let next = current.map { min(max($0 + step, 0), order.count - 1) } ?? (step > 0 ? 0 : order.count - 1)
            open(order[next])
            return
        }

        let order = SettingsTab.sidebarOrder
        let current = order.firstIndex(of: navigationState.selectedTab)
        let next = current.map { min(max($0 + step, 0), order.count - 1) } ?? 0
        navigationState.select(order[next])
    }
}

// MARK: - Search Result Row

/// Indented setting match beneath its parent tab row, with bold matched-character highlights.
private struct SettingsSidebarSearchResultRow: View {
    let result: SettingsSearchResult
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    /// Aligns the title with the parent tab label above (7pt padding + 22pt icon + 9pt spacing).
    private static let leadingInset: CGFloat = 7 + 22 + 9

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(highlightedTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)

                if let section = result.entry.section, !section.isEmpty {
                    Text(section)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Self.leadingInset)
            .padding(.trailing, 7)
            .padding(.vertical, 5)
            .background {
                Radius.controlRect(forHeight: 32)
                    .fill(Color.primary.opacity(isSelected ? 0.08 : (isHovering ? 0.045 : 0)))
            }
            .contentShape(Radius.controlRect(forHeight: 32))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(result.entry.detail ?? "")
        .accessibilityLabel([result.entry.title, result.entry.section].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var highlightedTitle: AttributedString {
        let title = result.entry.title
        var attributed = AttributedString(title)
        for range in result.titleHighlights {
            guard let attributedRange = Range(range, in: attributed) else { continue }
            attributed[attributedRange].font = .system(size: 12, weight: .semibold)
        }
        return attributed
    }
}

// MARK: - Sidebar Row

private struct SettingsSidebarRow: View {
    let tab: SettingsTab
    let isSelected: Bool
    var badgeText: String? = nil
    var isLiveBadge: Bool = false
    var selectionNamespace: Namespace.ID? = nil
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private static let height: CGFloat = 33

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                PreferencesSidebarIcon(tab: tab, size: 22, duotone: true)
                    .scaleEffect(!reduceMotion && isHovering && !isSelected ? 1.05 : 1.0)
                    .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.24), value: isHovering)

                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.84))
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let badgeText {
                    HStack(spacing: 4) {
                        if isLiveBadge {
                            Circle()
                                .fill(GravPalette.emerald)
                                .frame(width: 5, height: 5)
                        }
                        Text(badgeText)
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(isLiveBadge ? GravPalette.emerald : Color.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isLiveBadge ? GravPalette.emerald.opacity(0.14) : Color.primary.opacity(0.06))
                    )
                }
            }
            .padding(.horizontal, 8)
            .frame(height: Self.height)
            .background {
                ZStack(alignment: .leading) {
                    if isSelected {
                        Group {
                            if let ns = selectionNamespace {
                                Radius.controlRect(forHeight: Self.height)
                                    .fill(Color.primary.opacity(0.095))
                                    .overlay(
                                        Radius.controlRect(forHeight: Self.height)
                                            .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.6)
                                    )
                                    .matchedGeometryEffect(id: "sidebarActivePill", in: ns)
                            } else {
                                Radius.controlRect(forHeight: Self.height)
                                    .fill(Color.primary.opacity(0.095))
                            }
                        }

                        if let ns = selectionNamespace {
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.75))
                                .frame(width: 2.5, height: 14)
                                .padding(.leading, 1.5)
                                .matchedGeometryEffect(id: "sidebarActiveRail", in: ns)
                        }
                    } else if isHovering {
                        Radius.controlRect(forHeight: Self.height)
                            .fill(Color.primary.opacity(0.045))
                    }
                }
            }
            .contentShape(Radius.controlRect(forHeight: Self.height))
        }
        .buttonStyle(PrecisionPressButtonStyle())
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Droppy / macOS 26 Glossy Icon Tiles (Ported 1:1 from Snapzy)

/// Pastel glyph tint that sits light on the near-black glossy squircle tile, washed toward
/// white at the top and settling into full hue at the bottom.
struct PreferencesIconTint: Equatable, Sendable {
    var hue: Double
    var saturation: Double = 0.6

    static let graphite = PreferencesIconTint(hue: 225, saturation: 0.07)
    static let teal = PreferencesIconTint(hue: 174)
    static let cyan = PreferencesIconTint(hue: 196)
    static let emerald = PreferencesIconTint(hue: 152, saturation: 0.58)
    static let periwinkle = PreferencesIconTint(hue: 238)
    static let amber = PreferencesIconTint(hue: 34, saturation: 0.66)
    static let blue = PreferencesIconTint(hue: 214)

    /// Near-white silver primary layer for duotone glyphs so the pastel hue reads as an accent.
    static var silver: LinearGradient {
        LinearGradient(
            colors: [Color(white: 0.98), Color(white: 0.76)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hue: wrapped(hue - 3), saturation: saturation * 0.55, brightness: 1),
                Color(hue: wrapped(hue + 3), saturation: saturation, brightness: 0.86),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func wrapped(_ degrees: Double) -> Double {
        (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
    }
}

extension SettingsTab {
    var iconTint: PreferencesIconTint {
        switch self {
        case .general: return .graphite
        case .notchHUD: return .teal
        case .miniPet: return .amber
        case .telemetry: return .cyan
        case .menuBar: return .emerald
        case .shortcuts: return .periwinkle
        case .permissions: return .amber
        case .about: return .teal
        }
    }
}

/// System Settings–style squircle for each tab, with special duotone treatment for the single-layer ⌘ glyph.
struct PreferencesSidebarIcon: View {
    let tab: SettingsTab
    var size: CGFloat = 22
    var duotone = false

    var body: some View {
        if tab == .shortcuts && duotone {
            PreferencesIconTile(size: size, tint: tab.iconTint, duotone: true) {
                ZStack {
                    ForEach(0..<4, id: \.self) { corner in
                        Circle()
                            .fill(.secondary)
                            .frame(width: size * 0.11, height: size * 0.11)
                            .offset(
                                x: size * (corner % 2 == 0 ? -0.15 : 0.15),
                                y: size * (corner < 2 ? -0.15 : 0.15)
                            )
                    }
                    Radius.rect(size * 0.02)
                        .fill(.secondary)
                        .frame(width: size * 0.2, height: size * 0.2)
                    Image(systemName: tab.symbol)
                        .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }
        } else {
            PreferencesSymbolTile(symbol: tab.symbol, size: size, tint: tab.iconTint, duotone: duotone)
        }
    }
}

/// Bold rounded SF Symbol on the near-black glossy squircle tile.
struct PreferencesSymbolTile: View {
    let symbol: String
    var size: CGFloat = 22
    var tint: PreferencesIconTint = .blue
    var duotone = false

    var body: some View {
        PreferencesIconTile(size: size, tint: tint, duotone: duotone) {
            Image(systemName: symbol)
                .symbolRenderingMode(duotone ? .palette : .monochrome)
                .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
        }
    }
}

/// Droppy / macOS 26 glossy near-black squircle tile with top specular rim.
struct PreferencesIconTile<Glyph: View>: View {
    var size: CGFloat
    var tint: PreferencesIconTint = .blue
    var duotone = false
    @ViewBuilder let glyph: () -> Glyph

    private var isLarge: Bool { size > 36 }

    var body: some View {
        let shape = isLarge ? Radius.rect(size * 0.24) : Radius.controlRect(forHeight: size)
        styledGlyph
            .frame(width: size, height: size)
            .background {
                shape.fill(
                    LinearGradient(
                        colors: [Color(white: 0.18), Color(white: 0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .overlay {
                if isLarge {
                    specularRim(shape)
                } else {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.24), Color.white.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
                }
            }
    }

    @ViewBuilder
    private var styledGlyph: some View {
        if duotone {
            glyph().foregroundStyle(PreferencesIconTint.silver, tint.gradient)
        } else {
            glyph().foregroundStyle(tint.gradient)
        }
    }

    private func specularRim(_ shape: RoundedRectangle) -> some View {
        let rimWidth = size * 0.022
        return ZStack {
            shape.strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.55), location: 0),
                        .init(color: Color.white.opacity(0.16), location: 0.3),
                        .init(color: Color.white.opacity(0.05), location: 0.55),
                        .init(color: Color.white.opacity(0.32), location: 1),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: rimWidth
            )
            shape
                .inset(by: rimWidth)
                .strokeBorder(Color.black.opacity(0.55), lineWidth: 0.75)
        }
    }
}
