import AppKit
import SwiftUI

/// Dedicated native macOS Settings pane for Grav's Codex Mini Pet:
/// live interactive sprite stage, 1:1 `codex-pets.net` GIF/Sheet export, Notch HUD tuning,
/// and live `codex-pets.net` catalog search & download.
struct MiniPetSettingsPane: View {
    private enum LibraryMode: String, CaseIterable, Identifiable {
        case browse = "codex-pets.net"
        case installed = "Installed"
        var id: String { rawValue }
    }

    @Bindable var preferences: PreferencesStore
    var petsStore: CodexPetsStore = .shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    @State private var previewState: CodexPetAnimationState = .idle
    @State private var libraryMode: LibraryMode = .browse
    @State private var searchQuery: String = ""
    @State private var sortOrder: CodexPetSort = .popular

    private let quickQueries = ["goku", "anime", "cat", "pokemon", "robot"]

    private var activePet: InstalledCodexPet? {
        petsStore.pet(withID: preferences.activeMiniPetID)
    }

    var body: some View {
        Form {
            if let pet = activePet {
                Section("Live Stage & Export") {
                    liveStageCard(for: pet)
                        .listRowInsets(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
                }
            }

            Section("Notch Mini Pet") {
                SettingRow(
                    title: "Show Mini Pet",
                    description: "Display a reactive pixel companion inside Grav's collapsed and expanded Notch HUD."
                ) {
                    Toggle("", isOn: $preferences.miniPetEnabled)
                        .labelsHidden()
                }

                SettingRow(
                    title: "Pet Placement",
                    description: "Choose whether the Mini Pet sits on the leading wing, trailing wing, or only inside the expanded HUD."
                ) {
                    Picker("", selection: $preferences.miniPetPlacement) {
                        ForEach(MiniPetPlacement.allCases) { placement in
                            Text(placement.displayName).tag(placement)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 248)
                }
                .disabled(!preferences.miniPetEnabled)

                SettingRow(
                    title: "Pet Size",
                    description: "Pixel height inside the collapsed Notch pill (automatically clamped to fit the display notch)."
                ) {
                    HStack(spacing: 8) {
                        Slider(value: $preferences.miniPetSize, in: 16...32, step: 1)
                            .frame(width: 128)
                        Text("\(Int(preferences.miniPetSize.rounded())) pt")
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                .disabled(!preferences.miniPetEnabled)

                SettingRow(
                    title: "Animation Speed",
                    description: "Scales the native 120 ms Codex sprite cadence smoothly across all states."
                ) {
                    HStack(spacing: 8) {
                        Slider(value: $preferences.miniPetSpeed, in: 0.5...2.0, step: 0.1)
                            .frame(width: 128)
                        Text(String(format: "%.1f×", preferences.miniPetSpeed))
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                .disabled(!preferences.miniPetEnabled)

                SettingRow(
                    title: "Idle Roaming & Glances",
                    description: "Allow the Mini Pet to look around and briefly patrol while Antigravity is idle."
                ) {
                    Toggle("", isOn: $preferences.miniPetRoaming)
                        .labelsHidden()
                }
                .disabled(!preferences.miniPetEnabled)

                SettingRow(
                    title: "Click to Interact",
                    description: "Clicking the Mini Pet in the Notch triggers an interactive wave or jump reaction."
                ) {
                    Toggle("", isOn: $preferences.miniPetInteractiveClick)
                        .labelsHidden()
                }
                .disabled(!preferences.miniPetEnabled)
            }

            Section("Codex Pets Gallery") {
                libraryBrowserContent
                    .listRowInsets(EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14))
            }
        }
        .formStyle(.grouped)
        .task {
            if petsStore.galleryPets.isEmpty {
                await petsStore.searchGallery(query: "", sort: sortOrder)
            }
        }
        .onChange(of: preferences.activeMiniPetID) { _, _ in
            if let pet = activePet,
               !CodexPetAnimationState.availableStates(for: pet.spriteVersionNumber).contains(previewState)
            {
                previewState = .idle
            }
        }
    }

    // MARK: - Live Stage & 1:1 Codex Export Bar

    private func liveStageCard(for pet: InstalledCodexPet) -> some View {
        let states = CodexPetAnimationState.availableStates(for: pet.spriteVersionNumber)

        return VStack(alignment: .leading, spacing: 12) {
            // Header + Interactive Pixel Stage
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.06, green: 0.065, blue: 0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                        )

                    stageGridPattern
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    CodexPetSpriteView(
                        pet: pet,
                        state: previewState,
                        size: 88,
                        speed: preferences.miniPetSpeed,
                        reduceMotion: reduceMotion,
                        petsStore: petsStore
                    )
                }
                .frame(width: 112, height: 112)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onTapGesture {
                    let next: CodexPetAnimationState = (previewState == .waving) ? .jumping : .waving
                    previewState = next
                }
                .help("Click stage to test wave/jump")

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(pet.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)

                        Text("v\(pet.spriteVersionNumber) · \(states.count) states")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }

                    Text("@\(pet.ownerHandle)")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)

                    if !pet.description.isEmpty {
                        Text(pet.description)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 8) {
                        if let source = pet.sourceURL, let url = URL(string: source) {
                            Button {
                                openURL(url)
                            } label: {
                                Label("Open on codex-pets.net", systemImage: "arrow.up.right.square")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.link)
                        }

                        Spacer(minLength: 0)

                        Text("Stage: \(previewState.label)")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // State selector grid
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 78, maximum: 110), spacing: 6)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(states) { state in
                    let selected = state == previewState
                    Button {
                        previewState = state
                    } label: {
                        Text(state.label)
                            .font(.system(size: 11, weight: selected ? .semibold : .medium))
                            .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.82))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(selected ? Color.accentColor : Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Exact 1:1 `codex-pets.net` EXPORT bar
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("EXPORT")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(.primary)

                    Text("GIFs render from the live sheet — pick a state on the stage, then grab it.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Button {
                        petsStore.exportSingleStateGIF(
                            pet: pet,
                            state: previewState,
                            speed: preferences.miniPetSpeed
                        )
                    } label: {
                        Label("\(previewState.label) GIF", systemImage: "arrow.down.to.line")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        petsStore.exportAllStateGIFs(
                            pet: pet,
                            speed: preferences.miniPetSpeed
                        )
                    } label: {
                        Label("All GIFs", systemImage: "shippingbox")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        petsStore.exportSpritesheet(pet: pet)
                    } label: {
                        Label("Sheet", systemImage: "square.grid.3x3")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var stageGridPattern: some View {
        Canvas { context, size in
            let step: CGFloat = 12
            var path = Path()
            var x: CGFloat = step
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = step
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(path, with: .color(Color.white.opacity(0.04)), lineWidth: 0.5)
        }
    }

    // MARK: - Live `codex-pets.net` Gallery & Installed Manager

    private var libraryBrowserContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Picker("", selection: $libraryMode) {
                    Text("codex-pets.net").tag(LibraryMode.browse)
                    Text("Installed (\(petsStore.installedPets.count))").tag(LibraryMode.installed)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 240)

                Spacer()

                if libraryMode == .browse {
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(CodexPetSort.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 148)
                    .onChange(of: sortOrder) { _, newSort in
                        Task { await petsStore.searchGallery(query: searchQuery, sort: newSort) }
                    }
                }
            }

            if libraryMode == .browse {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)

                            TextField("Search pets or paste codex-pets.net URL…", text: $searchQuery)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .onSubmit {
                                    Task { await petsStore.searchGallery(query: searchQuery, sort: sortOrder) }
                                }

                            if !searchQuery.isEmpty {
                                Button {
                                    searchQuery = ""
                                    Task { await petsStore.searchGallery(query: "", sort: sortOrder) }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75)
                                )
                        )

                        Button("Search") {
                            Task { await petsStore.searchGallery(query: searchQuery, sort: sortOrder) }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }

                    // Quick search chips
                    HStack(spacing: 6) {
                        Text("Quick:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        ForEach(quickQueries, id: \.self) { chip in
                            Button(chip) {
                                searchQuery = chip
                                Task { await petsStore.searchGallery(query: chip, sort: sortOrder) }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }

                        Spacer()

                        if petsStore.galleryTotal > 0 {
                            Text("\(petsStore.galleryTotal) pets")
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            if let error = petsStore.galleryError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else if let status = petsStore.statusMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(status)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            if libraryMode == .browse {
                browseGrid
            } else {
                installedGrid
            }
        }
    }

    @ViewBuilder
    private var browseGrid: some View {
        if petsStore.isLoadingGallery {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading pets from codex-pets.net…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 110)
        } else if petsStore.galleryPets.isEmpty {
            VStack(spacing: 6) {
                Text("No matching pets found")
                    .font(.system(size: 12.5, weight: .medium))
                Text("Try another keyword or paste a link like https://codex-pets.net/#/pets/super-saiyan-goku-combat")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 152, maximum: 200), spacing: 10)],
                spacing: 10
            ) {
                ForEach(petsStore.galleryPets) { item in
                    remotePetCard(item)
                }
            }
        }
    }

    private func remotePetCard(_ item: CodexPetRemoteItem) -> some View {
        let installed = petsStore.isInstalled(item.id)
        let equipped = installed && preferences.activeMiniPetID == item.id
        let isDownloading = petsStore.downloadingPetIDs.contains(item.id)

        return VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 0.06, green: 0.065, blue: 0.08))
                    .frame(height: 82)
                    .overlay {
                        if let poster = item.resolvedPosterURL {
                            AsyncImage(url: poster) { phase in
                                switch phase {
                                case let .success(image):
                                    image
                                        .interpolation(.none)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 64, height: 64)
                                case .failure:
                                    Image(systemName: "pawprint")
                                        .foregroundStyle(.secondary)
                                default:
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                        } else {
                            Image(systemName: "pawprint")
                                .foregroundStyle(.secondary)
                        }
                    }

                Text("v\(item.resolvedSpriteVersion)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.76))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .padding(5)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text("@\(item.ownerHandle ?? item.ownerName ?? "codex")")
                        .lineLimit(1)
                    if let likes = item.likeCount, likes > 0 {
                        Text("· ♥ \(likes)")
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                if isDownloading {
                    HStack(spacing: 5) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Downloading…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 3)
                } else if equipped {
                    Label("Equipped", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 3)
                } else if installed {
                    Button("Equip") {
                        preferences.activeMiniPetID = item.id
                        preferences.miniPetEnabled = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                } else {
                    Button {
                        Task {
                            if let record = await petsStore.downloadAndInstall(item) {
                                preferences.activeMiniPetID = record.id
                                preferences.miniPetEnabled = true
                            }
                        }
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            equipped ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.08),
                            lineWidth: equipped ? 1.2 : 0.75
                        )
                )
        )
    }

    private var installedGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 152, maximum: 200), spacing: 10)],
            spacing: 10
        ) {
            ForEach(petsStore.installedPets) { pet in
                let equipped = preferences.activeMiniPetID == pet.id

                VStack(alignment: .leading, spacing: 8) {
                    ZStack(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(red: 0.06, green: 0.065, blue: 0.08))
                            .frame(height: 82)
                            .overlay {
                                CodexPetSpriteView(
                                    pet: pet,
                                    state: .idle,
                                    size: 62,
                                    speed: preferences.miniPetSpeed,
                                    reduceMotion: reduceMotion,
                                    petsStore: petsStore
                                )
                            }

                        if !pet.isBundledDefault {
                            Button {
                                if preferences.activeMiniPetID == pet.id {
                                    preferences.activeMiniPetID = "super-saiyan-goku-combat"
                                }
                                petsStore.deleteInstalledPet(pet)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.75))
                                    .padding(5)
                                    .background(Circle().fill(Color.black.opacity(0.55)))
                            }
                            .buttonStyle(.plain)
                            .padding(5)
                            .help("Remove downloaded pet")
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(pet.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)

                        Text("@\(pet.ownerHandle) · v\(pet.spriteVersionNumber)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if equipped {
                        Label("Equipped", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 3)
                    } else {
                        Button("Equip") {
                            preferences.activeMiniPetID = pet.id
                            preferences.miniPetEnabled = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    equipped ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.08),
                                    lineWidth: equipped ? 1.2 : 0.75
                                )
                        )
                )
            }
        }
    }
}
