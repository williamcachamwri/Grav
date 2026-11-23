import SwiftUI

/// Space 2 (Step 3 of 4): 1:1 Codex-style Floating Desktop Mini Pet experience inside Onboarding.
/// Shows a calm dark Codex Pets settings window alongside a real floating pixel companion with
/// its live status speech bubble anchored to the mock macOS desktop (moving & scaling live).
struct GravMockMiniPetScene: View {
    @ObservedObject var state: GravOnboardingState
    let preferences: PreferencesStore
    var petsStore: CodexPetsStore = .shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var petBounce = false

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

    private var floatingAlignment: Alignment {
        switch preferences.miniPetPlacement {
        case .topRight, .free: return .topTrailing
        case .bottomRight: return .bottomTrailing
        case .bottomLeft: return .bottomLeading
        }
    }

    var body: some View {
        ZStack(alignment: floatingAlignment) {
            GravMockWallpaper(app: .miniPet).equatable()

            // Calm Codex-style Pets window anchored nicely on the mock desktop
            VStack(spacing: 0) {
                codexPetsWindow
                    .padding(.top, GravMockScene.windowTopInset + 10)
                    .padding(.leading, GravMockScene.windowInset - 10)
                    .padding(.trailing, 96)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // TRUE Floating Desktop Mini Pet + Live Status Speech Bubble (1:1 Codex reference!)
            if preferences.miniPetEnabled, let pet = activePet {
                floatingDesktopPetOverlay(for: pet)
                    .padding(.top, GravMockScene.windowTopInset + 14)
                    .padding(.bottom, 54)
                    .padding(.horizontal, 16)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.90))
                    )
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.36, bounce: 0.16), value: preferences.miniPetPlacement)
        .animation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.14), value: preferences.miniPetEnabled)
    }

    // MARK: - Codex-Style Floating Desktop Pet Overlay

    private func floatingDesktopPetOverlay(for pet: InstalledCodexPet) -> some View {
        let scaledSize = CGFloat(min(84, max(44, preferences.miniPetSize * 0.78)))

        return VStack(spacing: 5) {
            ZStack {
                Ellipse()
                    .fill(Color.black.opacity(0.38))
                    .frame(width: scaledSize * 0.62, height: 8)
                    .blur(radius: 4)
                    .offset(y: scaledSize * 0.44)

                CodexPetSpriteView(
                    pet: pet,
                    state: state.miniPetPreviewState,
                    size: scaledSize,
                    speed: preferences.miniPetSpeed,
                    reduceMotion: reduceMotion,
                    petsStore: petsStore
                )
                .scaleEffect(petBounce ? 1.10 : 1.0)
                .offset(y: petBounce ? -6 : 0)
                .animation(reduceMotion ? nil : .spring(duration: 0.26, bounce: 0.44), value: petBounce)
            }
            .contentShape(Rectangle())
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

            if preferences.miniPetShowBubble {
                VStack(alignment: .leading, spacing: 2.5) {
                    HStack(spacing: 5) {
                        Text(mockBubbleTitle)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.95))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Circle()
                            .fill(mockBubbleDotColor)
                            .frame(width: 5, height: 5)
                    }
                    Text(mockBubbleSubtitle)
                        .font(.system(size: 8.5))
                        .foregroundStyle(Color.white.opacity(0.60))
                        .lineLimit(2)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6.5)
                .frame(width: 152, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 9.5, style: .continuous)
                        .fill(Color(red: 0.082, green: 0.086, blue: 0.098).opacity(0.95))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9.5, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7)
                        )
                        .shadow(color: Color.black.opacity(0.45), radius: 12, y: 5)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.24, bounce: 0.16), value: preferences.miniPetShowBubble)
    }

    private var mockBubbleTitle: String {
        switch state.miniPetPreviewState {
        case .idle: return activePet?.displayName ?? "Grav Pet"
        case .running: return "Running swift test"
        case .review: return "Editing PetView.swift"
        case .waving: return "Hey there!"
        case .jumping: return "Task completed"
        case .failed: return "Build failed"
        default: return state.miniPetPreviewState.label
        }
    }

    private var mockBubbleSubtitle: String {
        switch state.miniPetPreviewState {
        case .idle: return "Standing by · Drag anywhere on your desktop"
        case .running: return "Streaming live telemetry from Antigravity…"
        case .review: return "+42 -8 · Updating desktop pet physics"
        case .waving: return "Click your pet anytime for a quick reaction"
        case .jumping: return "30/30 tests passed in 0.16s"
        case .failed: return "Exit code 1 · Click to inspect logs"
        default: return "Synced 100% realtime with Antigravity"
        }
    }

    private var mockBubbleDotColor: Color {
        switch state.miniPetPreviewState {
        case .failed: return GravPalette.coral
        case .review: return GravPalette.fileEdit
        case .running: return GravPalette.glacialCyan
        default: return GravPalette.emerald
        }
    }

    // MARK: - Calm Codex-Style Pets Window

    private var codexPetsWindow: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Minimal titlebar
            HStack(spacing: 8) {
                GravMockTrafficLights(size: 8.5, spacing: 5)

                Text("Pets")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.90))
                    .padding(.leading, 4)

                Spacer()

                Button {
                    GravOnboardingWelcomeAudio.shared.playButtonTap()
                    preferences.miniPetEnabled.toggle()
                    state.markMiniPetCustomized()
                } label: {
                    Text(preferences.miniPetEnabled ? "Tuck Away Pet" : "Show Pet")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.86))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(red: 0.115, green: 0.118, blue: 0.128))

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)

            VStack(alignment: .leading, spacing: 10) {
                // Animation state test pills
                VStack(alignment: .leading, spacing: 6) {
                    Text("TRY LIVE REACTIONS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(Color.white.opacity(0.40))

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 64), spacing: 5)],
                        alignment: .leading,
                        spacing: 5
                    ) {
                        ForEach(showcaseStates) { anim in
                            let selected = state.miniPetPreviewState == anim
                            Button {
                                GravOnboardingWelcomeAudio.shared.playButtonTap()
                                state.selectMiniPetPreviewState(anim)
                            } label: {
                                Text(anim.label)
                                    .font(.system(size: 9.5, weight: selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? .white : Color.white.opacity(0.68))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4.5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                            .fill(selected ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                                    .strokeBorder(
                                                        Color.white.opacity(selected ? 0.22 : 0.06),
                                                        lineWidth: 0.6
                                                    )
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Clean hairline tuning rows
                VStack(spacing: 0) {
                    // Position Snap
                    HStack {
                        Text("Position")
                            .font(.system(size: 9.8, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.88))
                        Spacer()
                        HStack(spacing: 3) {
                            ForEach([MiniPetPlacement.topRight, .bottomRight, .bottomLeft]) { corner in
                                let selected = preferences.miniPetPlacement == corner
                                Button {
                                    GravOnboardingWelcomeAudio.shared.playButtonTap()
                                    preferences.miniPetPlacement = corner
                                    preferences.miniPetOriginX = nil
                                    preferences.miniPetOriginY = nil
                                    preferences.miniPetEnabled = true
                                    state.markMiniPetCustomized()
                                } label: {
                                    Text(corner.displayName)
                                        .font(.system(size: 8.5, weight: selected ? .semibold : .regular))
                                        .foregroundStyle(selected ? .white : Color.white.opacity(0.62))
                                        .padding(.horizontal, 6.5)
                                        .padding(.vertical, 3)
                                        .background(
                                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                .fill(selected ? Color.white.opacity(0.16) : Color.clear)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(2)
                        .background(
                            RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 31)

                    dividerLine

                    // Pet Size
                    HStack {
                        Text("Size")
                            .font(.system(size: 9.8, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.88))
                        Spacer()
                        HStack(spacing: 5) {
                            Button {
                                GravOnboardingWelcomeAudio.shared.playButtonTap()
                                preferences.miniPetSize = max(48, preferences.miniPetSize - 8)
                                state.markMiniPetCustomized()
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.84))
                                    .frame(width: 19, height: 19)
                                    .background(Circle().fill(Color.white.opacity(0.09)))
                            }
                            .buttonStyle(.plain)

                            Text("\(Int(preferences.miniPetSize.rounded())) pt")
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(Color.white.opacity(0.76))
                                .frame(width: 34)

                            Button {
                                GravOnboardingWelcomeAudio.shared.playButtonTap()
                                preferences.miniPetSize = min(144, preferences.miniPetSize + 8)
                                state.markMiniPetCustomized()
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.84))
                                    .frame(width: 19, height: 19)
                                    .background(Circle().fill(Color.white.opacity(0.09)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 31)

                    dividerLine

                    // Status Bubble toggle
                    HStack {
                        Text("Live Status Bubble")
                            .font(.system(size: 9.8, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.88))
                        Spacer()
                        onboardingToggle(
                            isOn: Binding(
                                get: { preferences.miniPetShowBubble },
                                set: { value in
                                    GravOnboardingWelcomeAudio.shared.playButtonTap()
                                    preferences.miniPetShowBubble = value
                                    state.markMiniPetCustomized()
                                }
                            )
                        )
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 31)

                    dividerLine

                    // Idle Roaming toggle
                    HStack {
                        Text("Idle Roaming")
                            .font(.system(size: 9.8, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.88))
                        Spacer()
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
                    .frame(height: 31)
                }
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.075), lineWidth: 0.6)
                        )
                )

                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 8.5))
                        .foregroundStyle(Color.white.opacity(0.45))
                    Text("Browse 3,700+ pets & export GIFs in Settings → Mini Pet")
                        .font(.system(size: 8.8))
                        .foregroundStyle(Color.white.opacity(0.48))
                        .lineLimit(1)
                }
            }
            .padding(12)
        }
        .frame(maxWidth: 344)
        .background(Color(red: 0.088, green: 0.091, blue: 0.099))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.13), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.44), radius: 22, y: 12)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Color.white.opacity(0.065))
            .frame(height: 0.5)
            .padding(.leading, 10)
    }

    private func onboardingToggle(isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.80)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            ZStack(alignment: isOn.wrappedValue ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(isOn.wrappedValue ? Color(red: 0.10, green: 0.52, blue: 0.96) : Color.white.opacity(0.18))
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
