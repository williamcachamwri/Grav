import CoreGraphics
import SwiftUI

/// Crisp nearest-neighbor pixel-art renderer for a single `InstalledCodexPet` animation state.
/// Matches `codex-pets.net` exact `120 ms` base cadence and preserves razor-sharp pixel edges on Retina.
public struct CodexPetSpriteView: View {
    public var pet: InstalledCodexPet
    public var state: CodexPetAnimationState
    public var size: CGFloat
    public var speed: Double = 1.0
    public var reduceMotion: Bool = false
    public var petsStore: CodexPetsStore = .shared

    public init(
        pet: InstalledCodexPet,
        state: CodexPetAnimationState,
        size: CGFloat,
        speed: Double = 1.0,
        reduceMotion: Bool = false,
        petsStore: CodexPetsStore = .shared
    ) {
        self.pet = pet
        self.state = state
        self.size = size
        self.speed = speed
        self.reduceMotion = reduceMotion
        self.petsStore = petsStore
    }

    private var frameInterval: TimeInterval {
        CodexPetAnimationState.baseFrameInterval / max(0.35, min(2.5, speed))
    }

    private func resolvedFrames() -> [CGImage] {
        guard let allFrames = petsStore.frames(for: pet) else { return [] }
        if let direct = allFrames[state], !direct.isEmpty {
            return direct
        }
        return allFrames[.idle] ?? allFrames.values.first ?? []
    }

    public var body: some View {
        let frames = resolvedFrames()

        Group {
            if frames.isEmpty {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: max(10, size * 0.52), weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .frame(width: size, height: size)
            } else if reduceMotion || frames.count == 1 {
                renderFrame(frames[0])
            } else {
                TimelineView(.periodic(from: .now, by: frameInterval)) { context in
                    let tick = Int(floor(context.date.timeIntervalSinceReferenceDate / frameInterval))
                    let index = ((tick % frames.count) + frames.count) % frames.count
                    renderFrame(frames[index])
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func renderFrame(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1.0)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

/// Maps live Antigravity telemetry + explicit user click reactions strictly and deterministically
/// to the exact `CodexPetAnimationState` row on the equipped pet's sprite sheet (zero random actions).
public enum CodexPetTelemetryMapper {
    @MainActor
    public static func latestFailedTool(in store: AntigravityTelemetryStore) -> AgentToolActivityEvent? {
        for item in store.recentActivity.prefix(8) {
            if case let .toolActivity(ev) = item, ev.status == .failed {
                return ev
            }
        }
        return nil
    }

    @MainActor
    public static func animationState(
        for store: AntigravityTelemetryStore,
        reactionOverride: CodexPetAnimationState?,
        roamingEnabled: Bool,
        spriteVersion: Int,
        now: Date = Date()
    ) -> CodexPetAnimationState {
        _ = roamingEnabled
        if let reactionOverride {
            return normalize(reactionOverride, spriteVersion: spriteVersion)
        }

        if store.isPaused {
            return .idle
        }

        // React immediately with `.failed` when Antigravity hits a Quota / 429 / Capacity / Model error
        if store.activeModelFailureIncident(now: now, maxAge: 25.0) != nil {
            return .failed
        }

        // React immediately with `.failed` when a command or tool fails recently (10s window)
        if let latestCommand = store.commands.first,
           latestCommand.status == .failed,
           let completedAt = latestCommand.completedAt,
           now.timeIntervalSince(completedAt) <= 10.0
        {
            return .failed
        }

        if let latestTool = latestFailedTool(in: store),
           now.timeIntervalSince(latestTool.completedAt ?? latestTool.timestamp) <= 10.0
        {
            return .failed
        }

        let mapped: CodexPetAnimationState
        switch store.state {
        case .waitingForInput:
            mapped = .waiting
        case .runningCommand:
            mapped = .running
        case .editing, .inspecting:
            mapped = .review
        case .working, .thinking, .compacting, .toolActivity:
            mapped = .running
        case .replying:
            mapped = .jumping
        case .idle:
            if store.runningTaskCount > 0 || store.activeSwarmSnapshot != nil {
                mapped = .running
            } else {
                mapped = .idle
            }
        }

        return normalize(mapped, spriteVersion: spriteVersion)
    }

    private static func normalize(
        _ state: CodexPetAnimationState,
        spriteVersion: Int
    ) -> CodexPetAnimationState {
        if spriteVersion < 2 && state.rowIndex >= 9 {
            return .idle
        }
        return state
    }
}

/// Live reactive Mini Pet badge mounted inside the Collapsed and Expanded Notch HUD.
public struct NotchMiniPetBadge: View {
    public var store: AntigravityTelemetryStore
    public var preferences: PreferencesStore
    public var size: CGFloat
    public var petsStore: CodexPetsStore = .shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    public init(
        store: AntigravityTelemetryStore,
        preferences: PreferencesStore,
        size: CGFloat,
        petsStore: CodexPetsStore = .shared
    ) {
        self.store = store
        self.preferences = preferences
        self.size = size
        self.petsStore = petsStore
    }

    private var activePet: InstalledCodexPet? {
        petsStore.pet(withID: preferences.activeMiniPetID)
    }

    public var body: some View {
        if let pet = activePet {
            TimelineView(.periodic(from: .now, by: 1.5)) { context in
                let animState = CodexPetTelemetryMapper.animationState(
                    for: store,
                    reactionOverride: petsStore.reactionOverride,
                    roamingEnabled: preferences.miniPetRoaming && !reduceMotion,
                    spriteVersion: pet.spriteVersionNumber,
                    now: context.date
                )

                let sprite = CodexPetSpriteView(
                    pet: pet,
                    state: animState,
                    size: size,
                    speed: preferences.miniPetSpeed,
                    reduceMotion: reduceMotion,
                    petsStore: petsStore
                )
                .opacity(store.isPaused ? 0.50 : 1.0)
                .scaleEffect(!reduceMotion && isHovering && preferences.miniPetInteractiveClick ? 1.09 : 1.0)
                .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.28), value: isHovering)

                if preferences.miniPetInteractiveClick {
                    Button {
                        if preferences.playSounds {
                            GravOnboardingWelcomeAudio.shared.playButtonTap()
                        }
                        petsStore.triggerInteractionReaction()
                    } label: {
                        sprite
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovering = $0 }
                    .help("\(pet.displayName) · \(animState.label) — Click to interact")
                    .accessibilityLabel("\(pet.displayName), \(animState.label)")
                } else {
                    sprite
                        .help("\(pet.displayName) · \(animState.label)")
                        .accessibilityLabel("\(pet.displayName), \(animState.label)")
                }
            }
        }
    }
}
