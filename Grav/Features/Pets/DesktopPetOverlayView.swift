import AppKit
import SwiftUI

/// Codex-style floating desktop Mini Pet companion with crisp nearest-neighbor pixel rendering,
/// playful spring interactions, hover quick-actions (`Close pet`, menu chevron, corner resize handle),
/// subtle desktop patrolling, and a live telemetry speech bubble directly underneath.
struct DesktopPetOverlayView: View {
    var store: AntigravityTelemetryStore
    var preferences: PreferencesStore
    var petsStore: CodexPetsStore = .shared

    var onDragBegan: () -> Void
    var onDragChanged: () -> Void
    var onDragEnded: () -> Void
    var onSnapPlacement: (MiniPetPlacement) -> Void
    var onTuckAway: () -> Void
    var onOpenSettings: () -> Void
    var onFocusAntigravity: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHoveringStage = false
    @State private var isDraggingWindow = false
    @State private var isResizing = false
    @State private var resizeStartSize: Double = 84
    @State private var tapBounce = false
    @State private var patrolOffsetX: CGFloat = 0

    private var activePet: InstalledCodexPet? {
        petsStore.pet(withID: preferences.activeMiniPetID)
    }

    private var petDisplaySize: CGFloat {
        CGFloat(min(144.0, max(48.0, preferences.miniPetSize)))
    }

    var body: some View {
        if let pet = activePet {
            TimelineView(.periodic(from: .now, by: 1.5)) { context in
                let animState = CodexPetTelemetryMapper.animationState(
                    for: store,
                    reactionOverride: petsStore.reactionOverride,
                    roamingEnabled: preferences.miniPetRoaming && !reduceMotion && !isDraggingWindow && !isResizing,
                    spriteVersion: pet.spriteVersionNumber,
                    now: context.date
                )

                VStack(spacing: 6) {
                    petCharacterStage(pet: pet, animState: animState)

                    if shouldShowStatusBubble {
                        liveSpeechBubble(animState: animState)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .asymmetric(
                                        insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top)).combined(with: .offset(y: -4)),
                                        removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                                    )
                            )
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 8)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .animation(reduceMotion ? nil : .spring(duration: 0.30, bounce: 0.16), value: shouldShowStatusBubble)
                .onChange(of: animState) { _, newState in
                    updatePatrolMotion(for: newState)
                }
            }
        }
    }

    // MARK: - Interactive Pixel Character Stage

    private func petCharacterStage(
        pet: InstalledCodexPet,
        animState: CodexPetAnimationState
    ) -> some View {
        ZStack {
            // Subtle desktop contact shadow directly under the pet's feet
            Ellipse()
                .fill(Color.black.opacity(isDraggingWindow ? 0.16 : 0.30))
                .frame(width: petDisplaySize * 0.62, height: max(7, petDisplaySize * 0.13))
                .blur(radius: isDraggingWindow ? 7 : 4.5)
                .offset(y: petDisplaySize * 0.45)

            // Crisp nearest-neighbor Codex sprite
            CodexPetSpriteView(
                pet: pet,
                state: animState,
                size: petDisplaySize,
                speed: preferences.miniPetSpeed,
                reduceMotion: reduceMotion,
                petsStore: petsStore
            )
            .opacity(store.isPaused ? 0.62 : 1.0)
            .scaleEffect(spriteScale)
            .offset(y: isDraggingWindow ? -5 : (tapBounce ? -6 : 0))
            .animation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.42), value: tapBounce)
            .animation(reduceMotion ? nil : .spring(duration: 0.24, bounce: 0.22), value: isDraggingWindow)
            .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.20), value: isHoveringStage)
            .contentShape(Rectangle())
            .onTapGesture {
                handlePetTap()
            }
            .gesture(windowDragGesture)

            // Hover-only Codex micro-controls (exact 1:1 ergonomics)
            if isHoveringStage && !isDraggingWindow {
                hoverControlsOverlay(pet: pet)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(width: petDisplaySize + 44, height: petDisplaySize + 18)
        .offset(x: reduceMotion ? 0 : patrolOffsetX)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                isHoveringStage = hovering
            }
        }
        .contextMenu {
            petContextMenuItems
        }
    }

    private var spriteScale: CGFloat {
        if isDraggingWindow { return 1.05 }
        if tapBounce { return 1.09 }
        if isHoveringStage { return 1.03 }
        return 1.0
    }

    private func hoverControlsOverlay(pet: InstalledCodexPet) -> some View {
        ZStack {
            // Top-right quiet menu chevron
            VStack {
                HStack {
                    Spacer()
                    Menu {
                        petContextMenuItems
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.86))
                            .frame(width: 20, height: 20)
                            .background(
                                Circle()
                                    .fill(Color(red: 0.10, green: 0.105, blue: 0.12).opacity(0.82))
                                    .overlay(
                                        Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6)
                                    )
                            )
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("\(pet.displayName) options")
                }
                Spacer()
            }

            // Codex-style sleek `Close pet` hover pill (matches reference screenshot!)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        if preferences.playSounds {
                            GravOnboardingWelcomeAudio.shared.playButtonTap()
                        }
                        onTuckAway()
                    } label: {
                        Text("Close pet")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3.5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color(red: 0.10, green: 0.48, blue: 0.94).opacity(0.95))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.6)
                                    )
                                    .shadow(color: Color.black.opacity(0.40), radius: 6, y: 2)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 12)
                }
            }

            // Bottom-right subtle drag-to-resize corner handle
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(isResizing ? 0.95 : 0.62))
                        .frame(width: 18, height: 18)
                        .background(
                            Circle()
                                .fill(Color(red: 0.09, green: 0.095, blue: 0.11).opacity(0.76))
                                .overlay(
                                    Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                                )
                        )
                        .gesture(resizeGesture)
                        .help("Drag to resize pet")
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var petContextMenuItems: some View {
        Button("Wave / Jump") {
            handlePetTap()
        }

        Divider()

        Menu("Switch Pet") {
            ForEach(petsStore.installedPets) { item in
                Button {
                    preferences.activeMiniPetID = item.id
                } label: {
                    HStack {
                        Text(item.displayName)
                        if item.id == preferences.activeMiniPetID {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Menu("Snap Position") {
            ForEach([MiniPetPlacement.topRight, .bottomRight, .bottomLeft]) { corner in
                Button(corner.displayName) {
                    onSnapPlacement(corner)
                }
            }
        }

        Divider()

        Button("Open Pets Settings…") {
            onOpenSettings()
        }

        Button("Tuck Away Pet") {
            onTuckAway()
        }
    }

    // MARK: - Live Codex-Style Telemetry Speech Bubble

    private var shouldShowStatusBubble: Bool {
        guard preferences.miniPetShowBubble else { return false }
        if isHoveringStage { return true }
        if store.isPaused { return false }
        if store.state.isActive || store.runningTaskCount > 0 || store.activeSwarmSnapshot != nil {
            return true
        }
        if let cmd = store.commands.first,
           cmd.status == .failed,
           let completedAt = cmd.completedAt,
           Date().timeIntervalSince(completedAt) <= 8.0
        {
            return true
        }
        return false
    }

    private var bubbleHeadline: String {
        if store.isPaused { return "Telemetry paused" }
        if let focus = store.currentFocus, !focus.isEmpty, store.state.isActive {
            return focus
        }
        switch store.state {
        case .idle:
            if store.runningTaskCount > 0 {
                return "\(store.runningTaskCount) background task\(store.runningTaskCount == 1 ? "" : "s")"
            }
            return activePet?.displayName ?? "Grav Pet"
        case .working:
            return "Working"
        case .compacting:
            return "Compacting context"
        case .thinking:
            return "Thinking"
        case .replying:
            return "Writing reply"
        case let .inspecting(event):
            return "Analyzing \(event.basename)"
        case let .editing(event):
            return "\(event.kind == .delete ? "Deleting" : "Editing") \(event.basename)"
        case let .runningCommand(cmd):
            return cmd.displayTitle
        case let .waitingForInput(prompt):
            return prompt.isEmpty ? "Needs your input" : prompt
        case let .toolActivity(tool):
            return tool.title
        }
    }

    private var bubbleDetail: String {
        if store.isPaused {
            return "Resume telemetry from the Notch or Menu Bar."
        }
        switch store.state {
        case let .editing(event):
            let shortPath = (event.path as NSString).abbreviatingWithTildeInPath
            return "+\(event.addedLines) -\(event.removedLines) · \(shortPath)"
        case let .inspecting(event):
            let shortPath = (event.path as NSString).abbreviatingWithTildeInPath
            if let range = event.lineRangeLabel {
                return "\(shortPath) (\(range))"
            }
            return shortPath
        case let .runningCommand(cmd):
            return cmd.commandLine
        case let .toolActivity(tool):
            return tool.detail ?? tool.kind.shortLabel
        case .thinking, .working:
            if let thought = store.currentThinking?.text ?? store.thinkingHistory.first?.text {
                let cleaned = thought.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { return String(cleaned.prefix(96)) }
            }
            if let steps = store.stepsProgress, !steps.isAllDone {
                return "Step \(steps.completedCount)/\(steps.totalCount) in progress"
            }
            return store.activeSession?.title ?? "Streaming live Antigravity telemetry"
        case .replying:
            if let text = store.latestResponse?.text {
                let cleaned = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { return String(cleaned.prefix(96)) }
            }
            return "Streaming assistant response…"
        case .waitingForInput:
            return "Click to focus Antigravity and respond."
        case .compacting:
            return "Summarizing conversation context window…"
        case .idle:
            if let title = store.activeSession?.title, !title.isEmpty {
                let clean = title
                    .replacingOccurrences(of: "<USER_REQUEST>", with: "")
                    .replacingOccurrences(of: "</USER_REQUEST>", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty { return clean }
            }
            return "Drag to move · Click pet to interact"
        }
    }

    private func liveSpeechBubble(animState: CodexPetAnimationState) -> some View {
        Button {
            onFocusAntigravity()
        } label: {
            VStack(alignment: .leading, spacing: 3.5) {
                HStack(alignment: .center, spacing: 6) {
                    Text(bubbleHeadline)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    bubbleStatusIndicator(animState: animState)
                }

                Text(bubbleDetail)
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.64))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(width: 212, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color(red: 0.082, green: 0.086, blue: 0.098).opacity(0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.13), lineWidth: 0.75)
                    )
                    .shadow(color: Color.black.opacity(0.45), radius: 14, y: 6)
            )
        }
        .buttonStyle(.plain)
        .help("Click to focus Antigravity")
    }

    @ViewBuilder
    private func bubbleStatusIndicator(animState: CodexPetAnimationState) -> some View {
        if animState == .failed {
            Circle()
                .fill(GravPalette.coral)
                .frame(width: 6, height: 6)
        } else if animState == .waiting {
            Circle()
                .fill(GravPalette.fileEdit)
                .frame(width: 6, height: 6)
        } else if !store.isPaused && (store.state.isActive || store.runningTaskCount > 0) {
            BubbleActivityRing(reduceMotion: reduceMotion)
        } else {
            Circle()
                .fill(store.connectionStatus.isAppRunning ? GravPalette.emerald.opacity(0.85) : Color.white.opacity(0.32))
                .frame(width: 5.5, height: 5.5)
        }
    }

    // MARK: - Gestures & Micro-Animations

    private func handlePetTap() {
        guard preferences.miniPetInteractiveClick else { return }
        if preferences.playSounds {
            GravOnboardingWelcomeAudio.shared.playButtonTap()
        }
        petsStore.triggerInteractionReaction()
        if !reduceMotion {
            tapBounce = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(260))
                tapBounce = false
            }
        }
    }

    private var windowDragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { _ in
                if !isDraggingWindow {
                    isDraggingWindow = true
                    onDragBegan()
                }
                onDragChanged()
            }
            .onEnded { _ in
                isDraggingWindow = false
                onDragEnded()
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if !isResizing {
                    isResizing = true
                    resizeStartSize = preferences.miniPetSize
                }
                let delta = Double((value.translation.width + value.translation.height) * 0.5)
                preferences.miniPetSize = min(144.0, max(48.0, (resizeStartSize + delta).rounded()))
            }
            .onEnded { _ in
                isResizing = false
            }
    }

    private func updatePatrolMotion(for newState: CodexPetAnimationState) {
        guard !reduceMotion, preferences.miniPetRoaming, !isDraggingWindow, !isResizing else {
            if patrolOffsetX != 0 {
                withAnimation(.easeOut(duration: 0.35)) { patrolOffsetX = 0 }
            }
            return
        }
        switch newState {
        case .runningRight:
            withAnimation(.easeInOut(duration: 2.2)) {
                patrolOffsetX = 16
            }
        case .runningLeft:
            withAnimation(.easeInOut(duration: 2.2)) {
                patrolOffsetX = -16
            }
        default:
            if patrolOffsetX != 0 {
                withAnimation(.spring(duration: 0.45, bounce: 0.14)) {
                    patrolOffsetX = 0
                }
            }
        }
    }
}

private struct BubbleActivityRing: View {
    let reduceMotion: Bool
    @State private var angle: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0.12, to: 0.82)
            .stroke(Color.white.opacity(0.68), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            .frame(width: 10, height: 10)
            .rotationEffect(.degrees(angle))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 0.95).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}
