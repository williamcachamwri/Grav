//
//  GravOnboardingActionBar.swift
//  Grav
//
//  Rounded-full capsule Liquid Glass Action Bar with tactile spring button feedback,
//  ported 1:1 from Snapzy's `SnapzyOnboardingActionBar.swift`.
//

import SwiftUI

private enum GravOnboardingGlassAppearance {
    static let barTint = Color.black.opacity(0.52)
    static let segmentActiveTint = Color.black.opacity(0.54)
}

struct GravOnboardingActionBar: View {
    var skipTitle: String?
    var continueTitle: String
    var continueKey: String?
    var isContinueEnabled: Bool = true
    var isBusy: Bool = false
    var isHinted: Bool = false
    var minWidth: CGFloat?
    var onSkip: (() -> Void)?
    var onContinue: () -> Void

    private let barHeight: CGFloat = 40

    var body: some View {
        HStack(spacing: 0) {
            if let skipTitle, let onSkip {
                GravOnboardingBarSegment(
                    title: skipTitle,
                    trailingKey: nil,
                    isEnabled: true,
                    isBusy: false,
                    action: onSkip
                )

                // Etched vertical hairline divider
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.0),
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: GravSurfaceGlass.specularLineWidth, height: 18)
                    .padding(.horizontal, 2)
            }

            GravOnboardingBarSegment(
                title: continueTitle,
                trailingKey: continueKey,
                isEnabled: isContinueEnabled,
                isBusy: isBusy,
                isHinted: isHinted,
                action: onContinue
            )
        }
        .padding(3.5)
        .frame(height: barHeight)
        .frame(minWidth: minWidth)
        .liquidGlassGroup(spacing: 0)
        .liquidGlassSurface(
            shape: Capsule(style: .continuous),
            substrate: GravSurfaceGlass.baseDarkness,
            tint: 0.04,
            nativeGlassTint: GravOnboardingGlassAppearance.barTint
        )
        .clipShape(Capsule(style: .continuous))
        .shadow(color: Color.black.opacity(0.20), radius: 12, y: 5)
        .shadow(color: Color.black.opacity(0.10), radius: 2, y: 1)
        .animation(GravMotionPreferences.shared.spec(.settle).animation, value: isContinueEnabled)
    }
}

private struct GravOnboardingBarSegment: View {
    var title: String
    var trailingKey: String?
    var isEnabled: Bool = true
    var isBusy: Bool = false
    var isHinted: Bool = false
    var action: () -> Void

    @State private var isHovered = false

    private var showsHint: Bool {
        isHinted && isEnabled && !isBusy
    }

    private var labelInk: Color {
        if !isEnabled {
            return Color.white.opacity(0.30)
        }
        if isHovered || showsHint {
            return GravGlassInk.primary
        }
        return GravGlassInk.body
    }

    var body: some View {
        Button {
            guard isEnabled, !isBusy else { return }
            action()
        } label: {
            HStack(spacing: GravSpace.sm) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(GravGlassInk.primary)
                }

                Text(title)
                    .font(.system(size: GravOnboardingType.body + 1, weight: .medium))
                    .foregroundStyle(labelInk)

                if let trailingKey, !isBusy {
                    GravKeycapChip(label: trailingKey, emphasis: (isHovered || showsHint) && isEnabled)
                        .opacity(isEnabled ? 1.0 : 0.35)
                }
            }
            .padding(.horizontal, GravSpace.xl + 1)
            .frame(maxHeight: .infinity)
            .liquidGlassSurface(
                shape: Capsule(style: .continuous),
                isVisible: isHovered && isEnabled && !isBusy,
                substrate: GravSurfaceGlass.controlSubstrateHover,
                tint: 0.10,
                highlight: .custom(top: 0.24, bottom: 0.08),
                isInteractive: isEnabled && !isBusy,
                nativeGlassTint: GravOnboardingGlassAppearance.segmentActiveTint,
                nativeHighlight: .custom(top: 0.24, bottom: 0.08)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(GravInteractiveButtonStyle(isEnabled: isEnabled && !isBusy))
        .disabled(!isEnabled || isBusy)
        .onHover { hovering in
            guard isEnabled, !isBusy else {
                isHovered = false
                return
            }
            withAnimation(GravMotionPreferences.shared.spec(.hover).animation) {
                isHovered = hovering
            }
        }
        .animation(GravMotionPreferences.shared.spec(.settle).animation, value: isEnabled)
    }
}

private struct GravInteractiveButtonStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect((configuration.isPressed && isEnabled) ? 0.96 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.8), value: configuration.isPressed)
    }
}
