import SwiftUI

/// Space 2 (Step 3 of 4): 1:1 Interactive Codex Mini Pet studio inside Onboarding.
/// Bound live to `PreferencesStore` and `CodexPetsStore` with a real miniature Notch pill preview,
/// crisp nearest-neighbor pixel stage, clickable animation states, and placement/size/roaming tuning.
struct GravMockMiniPetScene: View {
    @ObservedObject var state: GravOnboardingState
    let preferences: PreferencesStore
    var petsStore: CodexPetsStore = .shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let macSystemBlue = Color(red: 0x0A / 255.0, green: 0x84 / 255.0, blue: 0xFF / 255.0)
    private let macSystemGreen = Color(red: 0x30 / 255.0, green: 0xD1 / 255.0, blue: 0x58 / 255.0)
    private let macSystemOrange = Color(red: 0xFF / 255.0, green: 0x9F / 255.0, blue: 0x0A / 255.0)
    private let macSystemIndigo = Color(red: 0x5E / 255.0, green: 0x5C / 255.0, blue: 0xE6 / 255.0)
    private let macSystemGray = Color(red: 0x6E / 255.0, green: 0x6E / 255.0, blue: 0x73 / 255.0)

    private let showcaseStates: [CodexPetAnimationState] = [
        .idle,
        .running,
        .review,
        .waving,
        .jumping,
        .failed,
    ]

    private var activePet: InstalledCodexPet? {
        petsStore.pet(withID: preferences.activeMiniPetID)
    }

    var body: some View {
        ZStack {
            GravMockWallpaper(app: .miniPet).equatable()

            VStack(spacing: 0) {
                miniPetWindow
                    .padding(.top, GravMockScene.windowTopInset + 10)
                    .padding(.horizontal, GravMockScene.windowInset - 8)

                Spacer(minLength: 0)
            }
        }
    }

    private var miniPetWindow: some View {
        HStack(spacing: 0) {
            // Left Sidebar matching 1:1 macOS System Settings chrome
            VStack(alignment: .leading, spacing: 0) {
                GravMockTrafficLights(size: 9, spacing: 5.5)
                    .padding(.horizontal, 12)
                    .padding(.top, 11)
                    .padding(.bottom, 10)

                HStack(spacing: 8) {
                    GravAppIconTile(size: 24)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Grav")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.94))
                        Text("Codex Companion")
                            .font(.system(size: 8, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.48))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)

                VStack(spacing: 2) {
                    sidebarRow(icon: "gearshape.fill", title: "General", color: macSystemGray, selected: false)
                    sidebarRow(icon: "macbook", title: "Notch HUD", color: macSystemBlue, selected: false)
                    sidebarRow(icon: "pawprint.fill", title: "Mini Pet", color: macSystemOrange, selected: true)
                    sidebarRow(icon: "waveform.path.ecg", title: "Telemetry", color: macSystemGreen, selected: false)
                }

                Spacer(minLength: 8)

                // Installed pets quick picker inside sidebar
                if petsStore.installedPets.count > 1 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("INSTALLED")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.35))
                            .padding(.horizontal, 10)

                        ForEach(petsStore.installedPets.prefix(3)) { pet in
                            let selected = pet.id == preferences.activeMiniPetID
                            Button {
                                GravOnboardingWelcomeAudio.shared.playButtonTap()
                                preferences.activeMiniPetID = pet.id
                                preferences.miniPetEnabled = true
                                state.markMiniPetCustomized()
                            } label: {
                                HStack(spacing: 6) {
                                    CodexPetSpriteView(
                                        pet: pet,
                                        state: .idle,
                                        size: 16,
                                        speed: preferences.miniPetSpeed,
                                        reduceMotion: reduceMotion,
                                        petsStore: petsStore
                                    )
                                    Text(pet.displayName)
                                        .font(.system(size: 8.5, weight: selected ? .semibold : .regular))
                                        .foregroundStyle(selected ? .white : Color.white.opacity(0.72))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(selected ? Color.white.opacity(0.11) : Color.clear)
                                )
                                .padding(.horizontal, 7)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 10)
                }

                HStack(spacing: 5) {
                    Image(systemName: "globe")
                        .font(.system(size: 8.5))
                        .foregroundStyle(Color.white.opacity(0.42))
                    Text("codex-pets.net")
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                .padding(.horizontal, 11)
                .padding(.bottom, 11)
            }
            .frame(width: 146)
            .background(Color(red: 0.118, green: 0.122, blue: 0.130))

            Rectangle()
                .fill(Color.black.opacity(0.65))
                .frame(width: 0.75)

            // Right Detail Canvas: Live Notch Preview + Pixel Stage + Tuning
            VStack(alignment: .leading, spacing: 9) {
                // 1. Live miniature Notch Pill Preview
                liveNotchPillPreview

                // 2. Crisp Pixel Stage + State Selector
                if let pet = activePet {
                    stageCard(for: pet)
                }

                // 3. Live-bound Tuning Card
                tuningCard

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(red: 0.088, green: 0.091, blue: 0.099))
        }
        .frame(height: 332)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.46), radius: 22, y: 12)
    }

    // MARK: - Live Miniature Notch Pill

    private var liveNotchPillPreview: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("LIVE NOTCH PREVIEW")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(Color.white.opacity(0.42))
                Spacer()
                Text(preferences.miniPetEnabled ? preferences.miniPetPlacement.displayName : "Hidden")
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.56))
            }

            HStack {
                Spacer(minLength: 0)

                HStack(spacing: 7) {
                    GravAppIconTile(size: 16)

                    if preferences.miniPetEnabled,
                       preferences.miniPetPlacement == .leading,
                       let pet = activePet
                    {
                        CodexPetSpriteView(
                            pet: pet,
                            state: state.miniPetPreviewState,
                            size: min(22, max(16, CGFloat(preferences.miniPetSize * 0.85))),
                            speed: preferences.miniPetSpeed,
                            reduceMotion: reduceMotion,
                            petsStore: petsStore
                        )
                    }

                    Text(state.miniPetPreviewState.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.76))
                        .lineLimit(1)

                    Spacer(minLength: 10)

                    if preferences.miniPetEnabled,
                       preferences.miniPetPlacement == .trailing,
                       let pet = activePet
                    {
                        CodexPetSpriteView(
                            pet: pet,
                            state: state.miniPetPreviewState,
                            size: min(22, max(16, CGFloat(preferences.miniPetSize * 0.85))),
                            speed: preferences.miniPetSpeed,
                            reduceMotion: reduceMotion,
                            petsStore: petsStore
                        )
                    }

                    Circle()
                        .fill(macSystemGreen.opacity(0.88))
                        .frame(width: 5, height: 5)
                }
                .padding(.horizontal, 11)
                .frame(width: 224, height: 28)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6)
                        )
                )

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(cardBackground)
    }

    // MARK: - Interactive Pixel Stage

    private func stageCard(for pet: InstalledCodexPet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(red: 0.055, green: 0.060, blue: 0.072))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.75)
                        )

                    CodexPetSpriteView(
                        pet: pet,
                        state: state.miniPetPreviewState,
                        size: 56,
                        speed: preferences.miniPetSpeed,
                        reduceMotion: reduceMotion,
                        petsStore: petsStore
                    )
                }
                .frame(width: 68, height: 68)
                .onTapGesture {
                    GravOnboardingWelcomeAudio.shared.playButtonTap()
                    let next: CodexPetAnimationState = (state.miniPetPreviewState == .waving) ? .jumping : .waving
                    state.selectMiniPetPreviewState(next)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(pet.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .lineLimit(1)

                    Text("@\(pet.ownerHandle) · v\(pet.spriteVersionNumber) sheet")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.46))

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 56), spacing: 4)],
                        alignment: .leading,
                        spacing: 4
                    ) {
                        ForEach(showcaseStates) { anim in
                            let selected = state.miniPetPreviewState == anim
                            Button {
                                GravOnboardingWelcomeAudio.shared.playButtonTap()
                                state.selectMiniPetPreviewState(anim)
                            } label: {
                                Text(anim.label)
                                    .font(.system(size: 9, weight: selected ? .semibold : .medium))
                                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.72))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 3.5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                            .fill(selected ? macSystemBlue : Color.white.opacity(0.07))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(cardBackground)
    }

    // MARK: - Live Bound Tuning Card

    private var tuningCard: some View {
        VStack(spacing: 0) {
            // Row 1: Show Mini Pet
            HStack {
                Text("Show Mini Pet in Notch")
                    .font(.system(size: 9.8, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.90))
                Spacer()
                onboardingToggle(
                    isOn: Binding(
                        get: { preferences.miniPetEnabled },
                        set: { value in
                            GravOnboardingWelcomeAudio.shared.playButtonTap()
                            preferences.miniPetEnabled = value
                            state.markMiniPetCustomized()
                        }
                    )
                )
            }
            .padding(.horizontal, 10)
            .frame(height: 29)

            dividerLine

            // Row 2: Placement
            HStack {
                Text("Placement")
                    .font(.system(size: 9.8, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.90))
                Spacer()
                HStack(spacing: 3) {
                    ForEach(MiniPetPlacement.allCases) { placement in
                        let selected = preferences.miniPetPlacement == placement
                        Button {
                            GravOnboardingWelcomeAudio.shared.playButtonTap()
                            preferences.miniPetPlacement = placement
                            preferences.miniPetEnabled = true
                            state.markMiniPetCustomized()
                        } label: {
                            Text(placement == .expandedOnly ? "Expanded" : placement.displayName)
                                .font(.system(size: 8.8, weight: selected ? .semibold : .medium))
                                .foregroundStyle(selected ? .white : Color.white.opacity(0.68))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(selected ? macSystemBlue : Color.white.opacity(0.06))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)

            dividerLine

            // Row 3: Size & Idle Roaming
            HStack(spacing: 8) {
                Text("Size")
                    .font(.system(size: 9.8, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.90))

                HStack(spacing: 4) {
                    Button {
                        GravOnboardingWelcomeAudio.shared.playButtonTap()
                        preferences.miniPetSize = max(16, preferences.miniPetSize - 2)
                        state.markMiniPetCustomized()
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.84))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.white.opacity(0.09)))
                    }
                    .buttonStyle(.plain)

                    Text("\(Int(preferences.miniPetSize.rounded()))pt")
                        .font(.system(size: 9.2, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.76))
                        .frame(width: 28)

                    Button {
                        GravOnboardingWelcomeAudio.shared.playButtonTap()
                        preferences.miniPetSize = min(32, preferences.miniPetSize + 2)
                        state.markMiniPetCustomized()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.84))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.white.opacity(0.09)))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text("Roaming")
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.72))

                onboardingToggle(
                    isOn: Binding(
                        get: { preferences.miniPetRoaming },
                        set: { value in
                            GravOnboardingWelcomeAudio.shared.playButtonTap()
                            preferences.miniPetRoaming = value
                            state.markMiniPetCustomized()
                        }
                    )
                )
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
        }
        .background(cardBackground)
    }

    // MARK: - Helpers

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(red: 0.118, green: 0.122, blue: 0.130))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.065), lineWidth: 0.5)
            )
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Color.white.opacity(0.065))
            .frame(height: 0.5)
            .padding(.leading, 10)
    }

    private func sidebarRow(icon: String, title: String, color: Color, selected: Bool) -> some View {
        HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(color)
                    .frame(width: 16, height: 16)
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(title)
                .font(.system(size: 9.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .white : Color.white.opacity(0.84))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6.5)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? macSystemBlue : Color.clear)
        )
        .padding(.horizontal, 7)
    }

    private func onboardingToggle(isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.80)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            ZStack(alignment: isOn.wrappedValue ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(isOn.wrappedValue ? macSystemBlue : Color.white.opacity(0.18))
                    .frame(width: 26, height: 15)
                Circle()
                    .fill(Color.white)
                    .frame(width: 11.5, height: 11.5)
                    .padding(1.75)
            }
        }
        .buttonStyle(.plain)
    }
}
