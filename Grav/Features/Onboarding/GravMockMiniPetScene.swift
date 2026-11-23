import SwiftUI

/// Space 2 (Step 3 of 4): Pixel-faithful 1:1 replica of Grav's real Settings → Mini Pet window
/// (`Grav` sidebar, `< > Mini Pet` toolbar, `Pets` header with single-line actions, interactive
/// 11-state Live Stage + `EXPORT` bar, `Installed / Explore codex-pets.net` search bar) paired
/// with the live floating Desktop Mini Pet & telemetry speech bubble anchored cleanly on screen.
struct GravMockMiniPetScene: View {
    @ObservedObject var state: GravOnboardingState
    let preferences: PreferencesStore
    var petsStore: CodexPetsStore = .shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var petBounce = false
    @State private var selectedChip: String? = "goku"

    private var activePet: InstalledCodexPet? {
        petsStore.pet(withID: preferences.activeMiniPetID)
    }

    private var availableStates: [CodexPetAnimationState] {
        CodexPetAnimationState.availableStates(for: activePet?.spriteVersionNumber ?? 2)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                GravMockWallpaper(app: .miniPet).equatable()
                    .frame(width: geo.size.width, height: geo.size.height)

                // Exact 1:1 Grav Settings → Mini Pet window
                VStack(spacing: 0) {
                    gravMiniPetSettingsWindow
                        .padding(.top, GravMockScene.windowTopInset + 8)
                        .padding(.horizontal, max(10, GravMockScene.windowInset - 14))

                    Spacer(minLength: 0)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)

                // Live Floating Desktop Mini Pet + Status Bubble positioned cleanly inside viewport
                if preferences.miniPetEnabled, let pet = activePet {
                    floatingDesktopPetBadge(for: pet)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, 14)
                        .padding(.bottom, 58)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .scale(scale: 0.90))
                        )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.16), value: preferences.miniPetEnabled)
    }

    // MARK: - 1:1 Grav Settings → Mini Pet Window

    private var gravMiniPetSettingsWindow: some View {
        HStack(spacing: 0) {
            // Left Sidebar matching Grav Settings 1:1
            VStack(alignment: .leading, spacing: 0) {
                GravMockTrafficLights(size: 8.5, spacing: 5)
                    .padding(.horizontal, 11)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                // Capsule Search Pill
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.42))
                    Text("Search")
                        .font(.system(size: 8.8, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.42))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 7)
                .frame(height: 19)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.075))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 9)

                // Grav Profile Row
                HStack(spacing: 7) {
                    GravAppIconTile(size: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Grav")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.94))
                        HStack(spacing: 3) {
                            Circle()
                                .fill(GravPalette.emerald)
                                .frame(width: 4.5, height: 4.5)
                            Text("v1.0.0 · Telemetry")
                                .font(.system(size: 7.5))
                                .foregroundStyle(Color.white.opacity(0.48))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 9)
                .padding(.bottom, 9)

                // Group 1
                VStack(spacing: 1.5) {
                    sidebarRow(symbol: "gearshape.fill", title: "General", tint: Color(white: 0.72), selected: false)
                    sidebarRow(symbol: "rectangle.topthird.inset.filled", title: "Notch HUD", tint: Color(red: 0.36, green: 0.85, blue: 0.82), selected: false)
                    sidebarRow(symbol: "pawprint.fill", title: "Mini Pet", tint: Color(red: 0.96, green: 0.72, blue: 0.36), selected: true)
                    sidebarRow(symbol: "waveform.path.ecg", title: "Telemetry", tint: Color(red: 0.36, green: 0.78, blue: 0.96), selected: false)
                }
                .padding(.bottom, 8)

                // Group 2
                VStack(spacing: 1.5) {
                    sidebarRow(symbol: "menubar.rectangle", title: "Menu Bar", tint: Color(red: 0.34, green: 0.84, blue: 0.60), selected: false)
                    sidebarRow(symbol: "command", title: "Shortcuts", tint: Color(red: 0.54, green: 0.58, blue: 0.96), selected: false)
                    sidebarRow(symbol: "lock.shield.fill", title: "Permissions", tint: Color(red: 0.96, green: 0.74, blue: 0.34), selected: false)
                }
                .padding(.bottom, 8)

                // Group 3
                sidebarRow(symbol: "info.circle", title: "About", tint: Color(red: 0.36, green: 0.85, blue: 0.82), selected: false)

                Spacer(minLength: 0)
            }
            .frame(width: 128)
            .background(Color(red: 0.106, green: 0.110, blue: 0.118))

            Rectangle()
                .fill(Color.black.opacity(0.65))
                .frame(width: 0.75)

            // Right Detail Pane matching Image 4 100%
            VStack(alignment: .leading, spacing: 9) {
                // Toolbar: `< >` pill + `Mini Pet`
                HStack(spacing: 8) {
                    HStack(spacing: 0) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.48))
                            .frame(width: 20, height: 19)
                        Rectangle()
                            .fill(Color.white.opacity(0.14))
                            .frame(width: 0.5, height: 10)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.24))
                            .frame(width: 20, height: 19)
                    }
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                            )
                    )

                    Text("Mini Pet")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 9) {
                    // Pets Header + Single-Line Action Pills
                    HStack(alignment: .center, spacing: 6) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Pets")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.94))
                            Text("Floating desktop companion synced live with Antigravity.")
                                .font(.system(size: 8.2))
                                .foregroundStyle(Color.white.opacity(0.48))
                                .lineLimit(1)
                        }
                        .layoutPriority(0)

                        Spacer(minLength: 4)

                        HStack(spacing: 4) {
                            mockHeaderPill(icon: "arrow.up.right", title: "codex-pets.net") {
                                GravOnboardingWelcomeAudio.shared.playButtonTap()
                                state.markMiniPetCustomized()
                            }
                            mockHeaderPill(icon: "arrow.clockwise", title: "Refresh") {
                                GravOnboardingWelcomeAudio.shared.playButtonTap()
                                state.markMiniPetCustomized()
                            }
                            mockHeaderPill(
                                icon: preferences.miniPetEnabled ? "eye.slash" : "eye",
                                title: preferences.miniPetEnabled ? "Tuck Away Pet" : "Show Pet"
                            ) {
                                GravOnboardingWelcomeAudio.shared.playButtonTap()
                                preferences.miniPetEnabled.toggle()
                                state.markMiniPetCustomized()
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                    }

                    // Live Stage + 11 State Pills + Export Bar Card (1:1 Image 4)
                    if let pet = activePet {
                        liveStageAndExportCard(for: pet)
                    }

                    // Gallery Tabs + Search Bar + Quick Chips (1:1 Image 4)
                    galleryBrowserStrip
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(red: 0.082, green: 0.085, blue: 0.094))
        }
        .frame(height: 334)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.48), radius: 22, y: 12)
    }

    private func liveStageAndExportCard(for pet: InstalledCodexPet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                // Dark Matte Pixel Stage
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(red: 0.052, green: 0.055, blue: 0.066))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.6)
                        )

                    CodexPetSpriteView(
                        pet: pet,
                        state: state.miniPetPreviewState,
                        size: 58,
                        speed: preferences.miniPetSpeed,
                        reduceMotion: reduceMotion,
                        petsStore: petsStore
                    )
                }
                .frame(width: 76, height: 76)
                .onTapGesture {
                    GravOnboardingWelcomeAudio.shared.playButtonTap()
                    let next: CodexPetAnimationState = (state.miniPetPreviewState == .waving) ? .jumping : .waving
                    state.selectMiniPetPreviewState(next)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Text(pet.displayName)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.94))
                            .lineLimit(1)

                        Text("v\(pet.spriteVersionNumber) · \(availableStates.count) states")
                            .font(.system(size: 7.8, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.56))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.white.opacity(0.07)))
                            .fixedSize()
                    }

                    Text("@\(pet.ownerHandle) — \(pet.description)")
                        .font(.system(size: 8.2))
                        .foregroundStyle(Color.white.opacity(0.48))
                        .lineLimit(1)

                    // All 11 clickable state pills matching Image 4
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 52), spacing: 4)],
                        alignment: .leading,
                        spacing: 4
                    ) {
                        ForEach(availableStates) { anim in
                            let selected = state.miniPetPreviewState == anim
                            Button {
                                GravOnboardingWelcomeAudio.shared.playButtonTap()
                                state.selectMiniPetPreviewState(anim)
                            } label: {
                                Text(anim.label)
                                    .font(.system(size: 8.2, weight: selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? .white : Color.white.opacity(0.62))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .fill(selected ? Color.white.opacity(0.14) : Color.white.opacity(0.045))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                    .strokeBorder(
                                                        Color.white.opacity(selected ? 0.22 : 0.05),
                                                        lineWidth: 0.5
                                                    )
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)

            // 1:1 EXPORT Strip
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("EXPORT")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(Color.white.opacity(0.55))
                    Text("GIFs render from the live sheet — pick a state, then grab it.")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.white.opacity(0.44))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                HStack(spacing: 4) {
                    mockHeaderPill(icon: "arrow.down.to.line", title: "\(state.miniPetPreviewState.label) GIF") {
                        GravOnboardingWelcomeAudio.shared.playButtonTap()
                        state.markMiniPetCustomized()
                    }
                    mockHeaderPill(icon: "shippingbox", title: "All GIFs") {
                        GravOnboardingWelcomeAudio.shared.playButtonTap()
                        state.markMiniPetCustomized()
                    }
                    mockHeaderPill(icon: "square.grid.3x3", title: "Sheet") {
                        GravOnboardingWelcomeAudio.shared.playButtonTap()
                        state.markMiniPetCustomized()
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.085), lineWidth: 0.65)
                )
        )
    }

    private var galleryBrowserStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 2) {
                    Text("Installed (\(petsStore.installedPets.count))")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.56))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)

                    Text("Explore codex-pets.net")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.white.opacity(0.11))
                        )
                }
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                )

                Spacer()

                HStack(spacing: 2) {
                    Text("Popular")
                        .font(.system(size: 8.2, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.11)))
                    Text("Newest")
                        .font(.system(size: 8.2))
                        .foregroundStyle(Color.white.opacity(0.50))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.045)))
            }

            // Single-line Search Field Preview
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 8.5))
                        .foregroundStyle(Color.white.opacity(0.45))
                    Text(selectedChip.map { "Search: \($0)" } ?? "Search pets or paste codex-pets.net URL…")
                        .font(.system(size: 8.8))
                        .foregroundStyle(Color.white.opacity(selectedChip == nil ? 0.42 : 0.85))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)
                        )
                )

                Text("Search")
                    .font(.system(size: 8.8, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.90))
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                            .fill(Color.white.opacity(0.11))
                    )
            }

            HStack(spacing: 4) {
                ForEach(["goku", "anime", "cat", "pokemon", "robot", "duck"], id: \.self) { chip in
                    let active = selectedChip == chip
                    Button {
                        GravOnboardingWelcomeAudio.shared.playButtonTap()
                        selectedChip = chip
                        state.markMiniPetCustomized()
                    } label: {
                        Text(chip)
                            .font(.system(size: 8, weight: active ? .semibold : .regular))
                            .foregroundStyle(active ? .white : Color.white.opacity(0.55))
                            .padding(.horizontal, 6.5)
                            .padding(.vertical, 2.5)
                            .background(
                                Capsule().fill(Color.white.opacity(active ? 0.14 : 0.05))
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("3,711 pets")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.36))
            }
        }
    }

    // MARK: - Live Floating Desktop Pet Badge

    private func floatingDesktopPetBadge(for pet: InstalledCodexPet) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Ellipse()
                    .fill(Color.black.opacity(0.42))
                    .frame(width: 40, height: 7)
                    .blur(radius: 3.5)
                    .offset(y: 26)

                CodexPetSpriteView(
                    pet: pet,
                    state: state.miniPetPreviewState,
                    size: 58,
                    speed: preferences.miniPetSpeed,
                    reduceMotion: reduceMotion,
                    petsStore: petsStore
                )
                .scaleEffect(petBounce ? 1.10 : 1.0)
                .offset(y: petBounce ? -5 : 0)
                .animation(reduceMotion ? nil : .spring(duration: 0.26, bounce: 0.44), value: petBounce)
            }
            .onTapGesture {
                GravOnboardingWelcomeAudio.shared.playButtonTap()
                let next: CodexPetAnimationState = (state.miniPetPreviewState == .waving) ? .jumping : .waving
                state.selectMiniPetPreviewState(next)
                if !reduceMotion {
                    petBounce = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        petBounce = false
                    }
                }
            }

            HStack(spacing: 5) {
                Text(state.miniPetPreviewState.label)
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.92))
                Circle()
                    .fill(state.miniPetPreviewState == .failed ? GravPalette.coral : GravPalette.emerald)
                    .frame(width: 4.5, height: 4.5)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(red: 0.082, green: 0.086, blue: 0.098).opacity(0.95))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.65)
                    )
                    .shadow(color: Color.black.opacity(0.45), radius: 8, y: 3)
            )
        }
    }

    // MARK: - Helpers

    private func sidebarRow(symbol: String, title: String, tint: Color, selected: Bool) -> some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.20), Color(white: 0.07)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 15, height: 15)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.4)
                    )
                Image(systemName: symbol)
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(tint)
            }
            Text(title)
                .font(.system(size: 8.8, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .white : Color.white.opacity(0.80))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(
            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                .fill(selected ? Color.white.opacity(0.10) : Color.clear)
        )
        .padding(.horizontal, 7)
    }

    private func mockHeaderPill(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 7.5, weight: .medium))
                Text(title)
                    .font(.system(size: 8, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(Color.white.opacity(0.86))
            .padding(.horizontal, 6.5)
            .padding(.vertical, 3.5)
            .background(
                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .fill(Color.white.opacity(0.065))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.11), lineWidth: 0.6)
                    )
            )
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
    }
}
