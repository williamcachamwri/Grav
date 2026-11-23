import AppKit
import SwiftUI

/// Modern Codex-inspired Pets Settings pane:
/// - Fluid `ScrollView` layout (zero macOS `Form` hit-test/focus trapping) so Search works instantaneously.
/// - Clean monochrome hairline hierarchy, calm neutral controls, silky spring transitions.
/// - Interactive Live Pixel Stage + 1:1 `codex-pets.net` Export bar (`<State> GIF`, `All GIFs`, `Sheet`).
/// - Codex-style Installed Pets list + live `codex-pets.net` search & 1-click download gallery.
struct MiniPetSettingsPane: View {
    private enum LibraryTab: String, CaseIterable, Identifiable {
        case installed = "Installed"
        case explore = "codex-pets.net"
        var id: String { rawValue }
    }

    @Bindable var preferences: PreferencesStore
    var petsStore: CodexPetsStore = .shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Namespace private var tabIndicatorNamespace
    @Namespace private var statePillNamespace

    @State private var previewState: CodexPetAnimationState = .idle
    @State private var libraryTab: LibraryTab = .explore
    @State private var searchQuery: String = ""
    @State private var sortOrder: CodexPetSort = .popular
    @State private var stageBounce: Bool = false
    @State private var debounceTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool

    private let quickTags = ["goku", "anime", "cat", "pokemon", "robot", "duck"]

    private var activePet: InstalledCodexPet? {
        petsStore.pet(withID: preferences.activeMiniPetID)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                headerBar

                if let pet = activePet {
                    liveStageCard(for: pet)
                }

                librarySection

                tuningSection
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task {
            if petsStore.galleryPets.isEmpty {
                await petsStore.searchGallery(query: "", sort: sortOrder)
            }
        }
        .onChange(of: preferences.activeMiniPetID) { _, _ in
            if let pet = activePet,
               !CodexPetAnimationState.availableStates(for: pet.spriteVersionNumber).contains(previewState)
            {
                withAnimation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.14)) {
                    previewState = .idle
                }
            }
        }
        .onDisappear {
            debounceTask?.cancel()
        }
    }

    // MARK: - 1. Codex-Style Minimal Header Bar

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pets")
                    .font(.system(size: 18, weight: .semibold))
                    .tracking(-0.3)

                Text("Floating desktop companion synced live with Antigravity.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .layoutPriority(0)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                subtleActionButton(title: "codex-pets.net", systemImage: "arrow.up.right") {
                    if let url = URL(string: "https://codex-pets.net/") {
                        openURL(url)
                    }
                }

                subtleActionButton(title: "Refresh", systemImage: "arrow.clockwise") {
                    petsStore.reloadInstalledPets()
                    Task { await petsStore.searchGallery(query: searchQuery, sort: sortOrder) }
                }

                subtleActionButton(
                    title: preferences.miniPetEnabled ? "Tuck Away Pet" : "Show Pet",
                    systemImage: preferences.miniPetEnabled ? "eye.slash" : "eye",
                    isEmphasized: !preferences.miniPetEnabled
                ) {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.24, bounce: 0.14)) {
                        preferences.miniPetEnabled.toggle()
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
        }
    }

    // MARK: - 2. Interactive Live Stage & 1:1 Export Card

    private func liveStageCard(for pet: InstalledCodexPet) -> some View {
        let states = CodexPetAnimationState.availableStates(for: pet.spriteVersionNumber)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                // Crisp Matte Dark Pixel Stage
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.055, green: 0.058, blue: 0.070))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.75)
                        )

                    stageSubtleDotGrid
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Ellipse()
                        .fill(Color.black.opacity(0.45))
                        .frame(width: 56, height: 10)
                        .blur(radius: 4)
                        .offset(y: 42)

                    CodexPetSpriteView(
                        pet: pet,
                        state: previewState,
                        size: 88,
                        speed: preferences.miniPetSpeed,
                        reduceMotion: reduceMotion,
                        petsStore: petsStore
                    )
                    .scaleEffect(stageBounce ? 1.09 : 1.0)
                    .offset(y: stageBounce ? -5 : 0)
                    .animation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.44), value: stageBounce)
                }
                .frame(width: 118, height: 118)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onTapGesture {
                    triggerStagePreviewTap()
                }
                .help("Click to trigger wave / jump")

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(pet.displayName)
                            .font(.system(size: 14.5, weight: .semibold))
                            .tracking(-0.2)
                            .lineLimit(1)

                        Text("v\(pet.spriteVersionNumber) · \(states.count) states")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))

                        Spacer(minLength: 0)

                        if let source = pet.sourceURL, let url = URL(string: source) {
                            Button {
                                openURL(url)
                            } label: {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Open on codex-pets.net")
                        }
                    }

                    Text("@\(pet.ownerHandle)\(pet.description.isEmpty ? "" : " — \(pet.description)")")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    // Sleek animated state selector pills
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 74, maximum: 104), spacing: 5)],
                        alignment: .leading,
                        spacing: 5
                    ) {
                        ForEach(states) { state in
                            let selected = state == previewState
                            Button {
                                withAnimation(reduceMotion ? nil : .spring(duration: 0.24, bounce: 0.16)) {
                                    previewState = state
                                }
                            } label: {
                                Text(state.label)
                                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4.5)
                                    .padding(.horizontal, 6)
                                    .background {
                                        if selected {
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .fill(Color.primary.opacity(0.12))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                        .strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.75)
                                                )
                                                .matchedGeometryEffect(id: "activeStatePill", in: statePillNamespace)
                                        } else {
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .fill(Color.primary.opacity(0.04))
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Rectangle()
                .fill(Color.primary.opacity(0.075))
                .frame(height: 0.5)

            // Exact 1:1 `codex-pets.net` EXPORT bar (clean neutral aesthetic)
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("EXPORT")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.9)
                        .foregroundStyle(.secondary)

                    Text("GIFs render from the live sheet — pick a state on the stage, then grab it.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    subtleActionButton(title: "\(previewState.label) GIF", systemImage: "arrow.down.to.line") {
                        petsStore.exportSingleStateGIF(
                            pet: pet,
                            state: previewState,
                            speed: preferences.miniPetSpeed
                        )
                    }

                    subtleActionButton(title: "All GIFs", systemImage: "shippingbox") {
                        petsStore.exportAllStateGIFs(
                            pet: pet,
                            speed: preferences.miniPetSpeed
                        )
                    }

                    subtleActionButton(title: "Sheet", systemImage: "square.grid.3x3") {
                        petsStore.exportSpritesheet(pet: pet)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(16)
        .background(cardSurface)
    }

    private var stageSubtleDotGrid: some View {
        Canvas { context, size in
            let step: CGFloat = 14
            var y: CGFloat = step
            while y < size.height {
                var x: CGFloat = step
                while x < size.width {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2)),
                        with: .color(Color.white.opacity(0.08))
                    )
                    x += step
                }
                y += step
            }
        }
    }

    private func triggerStagePreviewTap() {
        let next: CodexPetAnimationState = (previewState == .waving) ? .jumping : .waving
        withAnimation(reduceMotion ? nil : .spring(duration: 0.24, bounce: 0.16)) {
            previewState = next
        }
        if !reduceMotion {
            stageBounce = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                stageBounce = false
            }
        }
    }

    // MARK: - 3. Codex-Style Installed List + Live `codex-pets.net` Gallery

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Sliding Pill Tab Bar + Sort
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 2) {
                    ForEach(LibraryTab.allCases) { tab in
                        let selected = libraryTab == tab
                        let label = tab == .installed
                            ? "Installed (\(petsStore.installedPets.count))"
                            : "Explore codex-pets.net"
                        Button {
                            withAnimation(reduceMotion ? nil : .spring(duration: 0.26, bounce: 0.14)) {
                                libraryTab = tab
                            }
                        } label: {
                            Text(label)
                                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                                .foregroundStyle(selected ? Color.primary : Color.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background {
                                    if selected {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(Color.primary.opacity(0.11))
                                            .matchedGeometryEffect(id: "libraryTabPill", in: tabIndicatorNamespace)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6)
                        )
                )

                Spacer(minLength: 8)

                if libraryTab == .explore {
                    HStack(spacing: 2) {
                        ForEach(CodexPetSort.allCases) { option in
                            let selected = sortOrder == option
                            Button {
                                guard sortOrder != option else { return }
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                                    sortOrder = option
                                }
                                performSearch(immediate: true)
                            } label: {
                                Text(option.displayName)
                                    .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                            .fill(selected ? Color.primary.opacity(0.11) : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2.5)
                    .background(
                        RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                            .fill(Color.primary.opacity(0.045))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6)
                            )
                    )
                }
            }

            if let error = petsStore.galleryError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                )
            } else if let status = petsStore.statusMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                    Text(status)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }

            if libraryTab == .installed {
                installedCodexList
                    .transition(.opacity)
            } else {
                exploreGalleryContent
                    .transition(.opacity)
            }
        }
    }

    /// 1:1 inspired by Codex's clean horizontal row list (`Select` / `Selected`).
    private var installedCodexList: some View {
        VStack(spacing: 0) {
            ForEach(Array(petsStore.installedPets.enumerated()), id: \.element.id) { index, pet in
                if index > 0 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.07))
                        .frame(height: 0.5)
                        .padding(.leading, 68)
                }
                InstalledPetListRow(
                    pet: pet,
                    isSelected: preferences.activeMiniPetID == pet.id && preferences.miniPetEnabled,
                    speed: preferences.miniPetSpeed,
                    reduceMotion: reduceMotion,
                    petsStore: petsStore,
                    onSelect: {
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.24, bounce: 0.14)) {
                            preferences.activeMiniPetID = pet.id
                            preferences.miniPetEnabled = true
                        }
                    },
                    onDelete: pet.isBundledDefault ? nil : {
                        if preferences.activeMiniPetID == pet.id {
                            preferences.activeMiniPetID = "super-saiyan-goku-combat"
                        }
                        petsStore.deleteInstalledPet(pet)
                    }
                )
            }
        }
        .background(cardSurface)
    }

    private var exploreGalleryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Single-line, 100% responsive native Search Bar (outside Form!)
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("Search pets or paste codex-pets.net URL…", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .lineLimit(1)
                        .focused($isSearchFocused)
                        .onSubmit {
                            performSearch(immediate: true)
                        }
                        .onChange(of: searchQuery) { _, _ in
                            performSearch(immediate: false)
                        }

                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                            performSearch(immediate: true)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear search")
                    }
                }
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(
                                    Color.primary.opacity(isSearchFocused ? 0.28 : 0.10),
                                    lineWidth: isSearchFocused ? 1.0 : 0.75
                                )
                        )
                )

                Button {
                    performSearch(immediate: true)
                } label: {
                    HStack(spacing: 5) {
                        if petsStore.isLoadingGallery {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text("Search")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.primary.opacity(0.11))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.75)
                            )
                    )
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            // Quick filter chips + live count
            HStack(spacing: 6) {
                ForEach(quickTags, id: \.self) { tag in
                    let active = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == tag
                    Button {
                        searchQuery = active ? "" : tag
                        performSearch(immediate: true)
                    } label: {
                        Text(tag)
                            .font(.system(size: 11, weight: active ? .semibold : .regular))
                            .foregroundStyle(active ? Color.primary : Color.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3.5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.primary.opacity(active ? 0.13 : 0.045))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(Color.primary.opacity(active ? 0.20 : 0.07), lineWidth: 0.6)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 8)

                if petsStore.galleryTotal > 0 {
                    Text("\(petsStore.galleryTotal.formatted()) pets")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            // Gallery Grid
            if petsStore.isLoadingGallery && petsStore.galleryPets.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading pets from codex-pets.net…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 132)
            } else if petsStore.galleryPets.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18))
                        .foregroundStyle(.tertiary)
                    Text("No pets matched \"\(searchQuery)\"")
                        .font(.system(size: 12.5, weight: .medium))
                    Text("Try another keyword or paste a link like https://codex-pets.net/#/pets/super-saiyan-goku-combat")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .padding(.horizontal, 16)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 156, maximum: 210), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(petsStore.galleryPets) { item in
                        RemotePetGalleryCard(
                            item: item,
                            isInstalled: petsStore.isInstalled(item.id),
                            isSelected: petsStore.isInstalled(item.id)
                                && preferences.activeMiniPetID == item.id
                                && preferences.miniPetEnabled,
                            isDownloading: petsStore.downloadingPetIDs.contains(item.id),
                            reduceMotion: reduceMotion,
                            onSelectOrDownload: {
                                if petsStore.isInstalled(item.id) {
                                    preferences.activeMiniPetID = item.id
                                    preferences.miniPetEnabled = true
                                } else {
                                    Task {
                                        if let record = await petsStore.downloadAndInstall(item) {
                                            preferences.activeMiniPetID = record.id
                                            preferences.miniPetEnabled = true
                                        }
                                    }
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private func performSearch(immediate: Bool) {
        debounceTask?.cancel()
        let querySnapshot = searchQuery
        let sortSnapshot = sortOrder
        debounceTask = Task { @MainActor in
            if !immediate {
                try? await Task.sleep(for: .milliseconds(320))
                guard !Task.isCancelled else { return }
            }
            await petsStore.searchGallery(query: querySnapshot, sort: sortSnapshot)
        }
    }

    // MARK: - 4. Desktop Companion Tuning Section

    private var tuningSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Desktop Companion")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                tuningToggleRow(
                    title: "Show Floating Desktop Pet",
                    subtitle: "Keep your pixel companion floating on your desktop and reacting live to Antigravity.",
                    isOn: $preferences.miniPetEnabled
                )

                rowDivider

                tuningRow(
                    title: "Snap Position",
                    subtitle: "Choose a resting corner or drag the pet freely anywhere on screen."
                ) {
                    HStack(spacing: 3) {
                        ForEach(MiniPetPlacement.allCases) { placement in
                            let selected = preferences.miniPetPlacement == placement
                            Button {
                                preferences.miniPetPlacement = placement
                                if placement != .free {
                                    preferences.miniPetOriginX = nil
                                    preferences.miniPetOriginY = nil
                                }
                            } label: {
                                Text(placement.displayName)
                                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(selected ? Color.primary.opacity(0.12) : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.045))
                    )
                }

                rowDivider

                tuningRow(
                    title: "Pet Size",
                    subtitle: "You can also drag the bottom-right corner handle directly on the desktop pet."
                ) {
                    HStack(spacing: 8) {
                        Slider(value: $preferences.miniPetSize, in: 48...144, step: 4)
                            .frame(width: 132)
                        Text("\(Int(preferences.miniPetSize.rounded())) pt")
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }

                rowDivider

                tuningRow(
                    title: "Animation Speed",
                    subtitle: "Scales the native 120 ms Codex sprite cadence across all states."
                ) {
                    HStack(spacing: 8) {
                        Slider(value: $preferences.miniPetSpeed, in: 0.5...2.0, step: 0.1)
                            .frame(width: 132)
                        Text(String(format: "%.1f×", preferences.miniPetSpeed))
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }

                rowDivider

                tuningToggleRow(
                    title: "Live Status Bubble",
                    subtitle: "Display Antigravity's current task, diff, or waiting prompt right beneath the pet.",
                    isOn: $preferences.miniPetShowBubble
                )

                rowDivider

                tuningToggleRow(
                    title: "Float Above All Windows",
                    subtitle: "Keep your pet visible over Xcode, Antigravity, and browsers across Spaces.",
                    isOn: $preferences.miniPetAlwaysOnTop
                )

                rowDivider

                tuningToggleRow(
                    title: "Idle Roaming & Patrol",
                    subtitle: "Let your pet glance around and take short walks while Antigravity is idle.",
                    isOn: $preferences.miniPetRoaming
                )

                rowDivider

                tuningToggleRow(
                    title: "Click to Interact",
                    subtitle: "Clicking the pet triggers a spring bounce with wave and jump animations.",
                    isOn: $preferences.miniPetInteractiveClick
                )
            }
            .background(cardSurface)
        }
    }

    // MARK: - Shared Minimalist Chrome

    private var cardSurface: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(0.032))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.085), lineWidth: 0.75)
            )
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.065))
            .frame(height: 0.5)
            .padding(.leading, 14)
    }

    private func subtleActionButton(
        title: String,
        systemImage: String,
        isEmphasized: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10.5, weight: .medium))
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(isEmphasized ? Color.white : Color.primary.opacity(0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 5.5)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                    .fill(isEmphasized ? Color.accentColor : Color.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                            .strokeBorder(
                                isEmphasized ? Color.clear : Color.primary.opacity(0.11),
                                lineWidth: 0.75
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func tuningRow<Control: View>(
        title: String,
        subtitle: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .id(title)
    }

    private func tuningToggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        tuningRow(title: title, subtitle: subtitle) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

// MARK: - Codex-Style Installed Pet Row

private struct InstalledPetListRow: View {
    let pet: InstalledCodexPet
    let isSelected: Bool
    let speed: Double
    let reduceMotion: Bool
    let petsStore: CodexPetsStore
    let onSelect: () -> Void
    let onDelete: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(red: 0.06, green: 0.064, blue: 0.076))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6)
                    )

                CodexPetSpriteView(
                    pet: pet,
                    state: isHovering ? .waving : .idle,
                    size: 36,
                    speed: speed,
                    reduceMotion: reduceMotion,
                    petsStore: petsStore
                )
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2.5) {
                HStack(spacing: 6) {
                    Text(pet.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    Text("@\(pet.ownerHandle)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                Text(pet.description.isEmpty ? "v\(pet.spriteVersionNumber) Codex pixel pet" : pet.description)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            HStack(spacing: 8) {
                if let onDelete, isHovering {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .help("Remove pet")
                    .transition(.opacity)
                }

                if isSelected {
                    Text("Selected")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                } else {
                    Button("Select", action: onSelect)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.90))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(isHovering ? 0.11 : 0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
                                )
                        )
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isHovering ? Color.primary.opacity(0.025) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Sleek Anti-Slop Remote Gallery Card

private struct RemotePetGalleryCard: View {
    let item: CodexPetRemoteItem
    let isInstalled: Bool
    let isSelected: Bool
    let isDownloading: Bool
    let reduceMotion: Bool
    let onSelectOrDownload: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(red: 0.055, green: 0.058, blue: 0.070))
                    .frame(height: 88)
                    .overlay {
                        if let poster = item.resolvedPosterURL {
                            AsyncImage(url: poster) { phase in
                                switch phase {
                                case let .success(image):
                                    image
                                        .interpolation(.none)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 66, height: 66)
                                        .scaleEffect(!reduceMotion && isHovering ? 1.07 : 1.0)
                                        .animation(reduceMotion ? nil : .spring(duration: 0.24, bounce: 0.26), value: isHovering)
                                case .failure:
                                    Image(systemName: "pawprint")
                                        .foregroundStyle(.tertiary)
                                default:
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                        } else {
                            Image(systemName: "pawprint")
                                .foregroundStyle(.tertiary)
                        }
                    }

                Text("v\(item.resolvedSpriteVersion)")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.66))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.50)))
                    .padding(6)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text("@\(item.ownerHandle ?? item.ownerName ?? "codex")")
                        .lineLimit(1)
                    if let likes = item.likeCount, likes > 0 {
                        Text("· ♥ \(likes)")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            // Calm, understated Codex action pill (NO wall of loud blue rectangles!)
            Button(action: onSelectOrDownload) {
                HStack(spacing: 5) {
                    if isDownloading {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Downloading…")
                    } else if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("Selected")
                    } else if isInstalled {
                        Text("Select")
                    } else {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Download")
                    }
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isSelected ? Color.secondary : Color.primary.opacity(0.92))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .fill(
                            isSelected
                                ? Color.primary.opacity(0.04)
                                : Color.primary.opacity(isHovering ? 0.13 : 0.075)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                                .strokeBorder(
                                    Color.primary.opacity(isSelected ? 0.06 : 0.13),
                                    lineWidth: 0.75
                                )
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(isDownloading || isSelected)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.048 : 0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            Color.primary.opacity(isSelected ? 0.24 : (isHovering ? 0.16 : 0.08)),
                            lineWidth: isSelected ? 1.1 : 0.75
                        )
                )
        )
        .scaleEffect(!reduceMotion && isHovering ? 1.012 : 1.0)
        .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.18), value: isHovering)
        .onHover { isHovering = $0 }
    }
}
