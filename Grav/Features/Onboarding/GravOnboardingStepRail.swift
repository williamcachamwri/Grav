//
//  GravOnboardingStepRail.swift
//  Grav
//
//  The progress spine across the onboarding header: 22pt beads joined by 1.5pt filling tracks,
//  ported 1:1 from Snapzy's `SnapzyOnboardingStepRail.swift`.
//

import SwiftUI

struct GravOnboardingStepRail: View {
    @ObservedObject var state: GravOnboardingState

    private static let beadDiameter: CGFloat = 22
    private static let trackHeight: CGFloat = 1.5

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(GravOnboardingStep.allCases.enumerated()), id: \.element) { index, step in
                if index > 0 {
                    track(leadingInto: step)
                }
                node(for: step)
            }
        }
        .animation(GravMotionPreferences.shared.spec(.settle).animation, value: state.currentStep)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Node

    private func node(for step: GravOnboardingStep) -> some View {
        let isCurrent = state.currentStep == step
        let isVisited = state.completedSteps.contains(step)
        let isReachable = isVisited || step.stepNumber <= state.currentStep.stepNumber

        return Button {
            guard isReachable else { return }
            state.transition(to: step)
        } label: {
            HStack(spacing: GravSpace.md) {
                bead(number: step.stepNumber, isCurrent: isCurrent, isVisited: isVisited)

                Text(step.shortTitle)
                    .font(.system(size: GravOnboardingType.caption, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(
                        isCurrent
                            ? GravGlassInk.primary
                            : (isVisited ? GravGlassInk.body : GravGlassInk.muted)
                    )
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GravStepNodeButtonStyle())
        .disabled(!isReachable)
        .help(step.shortTitle)
        .accessibilityLabel("\(step.stepNumber). \(step.shortTitle)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private struct GravStepNodeButtonStyle: ButtonStyle {
        @State private var isHovered = false

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .background {
                    Capsule(style: .continuous)
                        .fill(GravGlassInk.fillQuiet)
                        .opacity(isHovered && !configuration.isPressed ? 1 : 0)
                }
                .animation(GravMotionPreferences.shared.spec(.hover).animation, value: isHovered)
                .animation(GravMotionPreferences.shared.spec(.anticipation).animation, value: configuration.isPressed)
                .onHover { isHovered = $0 }
        }
    }

    private func bead(number: Int, isCurrent: Bool, isVisited: Bool) -> some View {
        ZStack {
            Circle()
                .fill(
                    isCurrent
                        ? Color.white
                        : (isVisited ? Color.white.opacity(0.16) : Color.white.opacity(0.04))
                )

            Circle()
                .strokeBorder(
                    isCurrent
                        ? Color.clear
                        : GravGlassInk.faint.opacity(isVisited ? 0.85 : 0.45),
                    lineWidth: 0.75
                )

            if isVisited, !isCurrent {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(GravGlassInk.primary)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            } else {
                Text("\(number)")
                    .font(.system(size: 10.5, weight: isCurrent ? .bold : .medium))
                    .foregroundStyle(
                        isCurrent
                            ? Color(red: 0.02, green: 0.14, blue: 0.18)
                            : GravGlassInk.muted
                    )
            }
        }
        .scaleEffect(isCurrent ? 1.04 : 1)
        .frame(width: GravOnboardingStepRail.beadDiameter, height: GravOnboardingStepRail.beadDiameter)
    }

    // MARK: - Track

    private func track(leadingInto step: GravOnboardingStep) -> some View {
        let isTraversed = step.stepNumber <= state.currentStep.stepNumber

        return ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(GravGlassInk.faint.opacity(0.32))

            Capsule(style: .continuous)
                .fill(GravGlassInk.primary.opacity(0.82))
                .scaleEffect(x: isTraversed ? 1 : 0, anchor: .leading)
        }
        .frame(height: GravOnboardingStepRail.trackHeight)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, GravSpace.md)
        .accessibilityHidden(true)
    }
}
