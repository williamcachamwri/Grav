//
//  GravOnboardingInstructionPanel.swift
//  Grav
//
//  Left-column instruction panel: narrative, interactive challenge checklist, simulation prompt
//  card, and tip, ported 1:1 from Snapzy's `SnapzyOnboardingInstructionPanel.swift`.
//

import SwiftUI

struct GravOnboardingInstructionPanel: View {
    @ObservedObject var state: GravOnboardingState
    let store: AntigravityTelemetryStore
    let preferences: PreferencesStore
    /// Allows pre-warming the panel behind the Welcome screen and firing its staggered entrance
    /// at the exact moment the Welcome aurora glides aside to reveal the left column.
    var isRevealed: Bool = true

    @State private var hasAppeared = false

    private var checklistOffset: Int { 1 }

    private var trailingIndex: Int {
        checklistOffset + state.currentStep.challenges.count
    }

    private var activeChallenge: GravOnboardingChallenge? {
        state.currentStep.challenges.first { !state.completedChallenges.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headline
                .gravEntrance(0, appeared: hasAppeared)

            challengeChecklist
                .padding(.top, GravSpace.hero)

            if !state.currentStep.examplePrompt.isEmpty {
                promptCard
                    .padding(.top, GravSpace.huge)
                    .gravEntrance(trailingIndex, appeared: hasAppeared)
            }

            if !state.currentStep.tip.isEmpty {
                tip
                    .padding(.top, GravSpace.xxl)
                    .gravEntrance(trailingIndex + 1, appeared: hasAppeared)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if isRevealed {
                hasAppeared = true
            }
        }
        .onChange(of: isRevealed) { _, revealed in
            if revealed {
                hasAppeared = true
            }
        }
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: GravSpace.xl) {
            GravOnboardingOverline(
                "Step \(state.currentStep.stepNumber) of \(GravOnboardingStep.allCases.count)"
            )

            Text(state.currentStep.title)
                .font(.system(size: GravOnboardingType.display, weight: .bold))
                .tracking(GravOnboardingType.displayTracking)
                .foregroundStyle(GravGlassInk.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(state.currentStep.subtitle)
                .font(.system(size: GravOnboardingType.lede))
                .foregroundStyle(GravGlassInk.body)
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Checklist

    private var challengeChecklist: some View {
        VStack(alignment: .leading, spacing: GravSpace.xl) {
            ForEach(Array(state.currentStep.challenges.enumerated()), id: \.element) { index, challenge in
                ChallengeRow(
                    challenge: challenge,
                    isDone: state.completedChallenges.contains(challenge),
                    isActive: activeChallenge == challenge
                )
                .gravEntrance(checklistOffset + index, appeared: hasAppeared)
            }
        }
        .animation(GravMotionPreferences.shared.spec(.settle).animation, value: state.completedChallenges)
    }

    // MARK: - Prompt Card

    private var promptText: String {
        switch state.currentStep {
        case .connect:
            let status = store.connectionStatus
            if status.isAppInstalled && status.isBrainAccessible {
                let count = status.activeConversationCount
                let plural = count == 1 ? "conversation" : "conversations"
                return "Antigravity bridge verified (\(count) \(plural) detected). Click here to re-scan."
            } else if status.needsFolderAccess || !status.isBrainAccessible {
                return "Click here to grant read access to ~/.gemini/antigravity/brain/."
            } else {
                return "Click here to re-check Antigravity installation and local telemetry."
            }

        case .notchHud:
            if !state.isMockNotchExpanded {
                return "Click here (or hover the notch on the right) to expand the live 3-tab HUD."
            } else if state.visitedMockTabs.count < 2 {
                return "Notch expanded on \(state.selectedMockNotchTab.title). Click here to cycle to the next telemetry tab."
            } else {
                return "All telemetry tabs explored! Click here to keep cycling or press Continue."
            }

        case .preferences:
            if state.hasReviewedPreferences {
                return "Preferences updated live. Click here to restore recommended defaults anytime."
            } else {
                return "Click here to apply recommended HUD defaults, or toggle options individually on the right."
            }
        }
    }

    private var promptCard: some View {
        Button {
            triggerNextStage()
        } label: {
            VStack(alignment: .leading, spacing: GravSpace.lg) {
                GravOnboardingOverline("Try it live", tint: GravGlassInk.muted)

                Text(promptText)
                    .font(.system(size: GravOnboardingType.lede - 0.5).italic())
                    .foregroundStyle(GravGlassInk.primary.opacity(0.94))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, GravSpace.xxl + GravSpace.xs)
            .padding(.vertical, GravSpace.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardShape.fill(GravGlassInk.fillQuiet))
            .overlay(cardShape.strokeBorder(GravGlassInk.hairline, lineWidth: GravSurfaceGlass.specularLineWidth))
            .contentShape(cardShape)
        }
        .buttonStyle(GravPromptCardButtonStyle())
        .help("Click to interact with the live stage on the right")
    }

    private var cardShape: RoundedRectangle {
        Radius.rect(Radius.card)
    }

    private func triggerNextStage() {
        switch state.currentStep {
        case .connect:
            if !store.connectionStatus.isBrainAccessible {
                store.requestBrainFolderAccess()
            } else {
                store.refreshConnectionStatus()
            }
            state.recordConnectionRefresh(store.connectionStatus)

        case .notchHud:
            state.advanceMockNotchDemo()

        case .preferences:
            preferences.autoPeekOnEvents = true
            preferences.hoverToExpand = true
            preferences.useLiquidGlass = true
            state.markPreferencesReviewed()
        }
    }

    // MARK: - Tip

    private var tip: some View {
        HStack(alignment: .top, spacing: GravSpace.lg) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(GravGlassInk.faint)
                .accessibilityHidden(true)

            Text(state.currentStep.tip)
                .font(.system(size: GravOnboardingType.caption))
                .foregroundStyle(GravGlassInk.muted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Challenge Row

private struct ChallengeRow: View {
    var challenge: GravOnboardingChallenge
    var isDone: Bool
    var isActive: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: GravSpace.xl) {
            marker
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 5 }

            Text(challenge.label)
                .font(.system(size: GravOnboardingType.challenge, weight: isActive ? .semibold : .regular))
                .foregroundStyle(labelInk)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: GravSpace.md)

            if !challenge.keys.isEmpty {
                GravKeycapRow(keys: challenge.keys, emphasis: isActive)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 5 }
            }
        }
        .animation(GravMotionPreferences.shared.spec(.pop).animation, value: isDone)
    }

    private var labelInk: Color {
        if isActive {
            return GravGlassInk.primary
        }
        if isDone {
            return GravGlassInk.body
        }
        return GravGlassInk.muted
    }

    /// 18×18 ring → filled Glacial Teal disc with crisp white checkmark entering from scale 0.7.
    private var marker: some View {
        ZStack {
            Circle()
                .fill(isDone ? GravPalette.glacialTeal : Color.clear)

            Circle()
                .strokeBorder(
                    isDone ? Color.clear : GravGlassInk.primary.opacity(isActive ? 0.78 : 0.24),
                    lineWidth: isActive ? 1.4 : 1
                )

            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

// MARK: - Prompt Card Style

private struct GravPromptCardButtonStyle: ButtonStyle {
    @State private var isHovered = false

    private var cardShape: RoundedRectangle {
        Radius.rect(Radius.card)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                cardShape
                    .fill(GravGlassInk.fillHover.opacity(pressOpacity(configuration.isPressed)))
                    .overlay(
                        cardShape.strokeBorder(
                            GravGlassInk.hairlineStrong,
                            lineWidth: GravSurfaceGlass.specularLineWidth
                        )
                        .opacity(pressOpacity(configuration.isPressed))
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .onHover { hovering in
                withAnimation(GravMotionPreferences.shared.spec(.hover).animation) { isHovered = hovering }
            }
            .animation(GravMotionPreferences.shared.spec(.anticipation).animation, value: configuration.isPressed)
    }

    private func pressOpacity(_ isPressed: Bool) -> Double {
        if isPressed {
            return 0.6
        }
        return isHovered ? 1 : 0
    }
}
