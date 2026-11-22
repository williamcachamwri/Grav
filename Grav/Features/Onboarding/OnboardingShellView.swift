import SwiftUI

/// Two-column Dark Liquid Glass onboarding shell matching Snapzy's exact layout proportions:
/// - Top header: docked `26x26` `GravAppIconTile` + `"Grav"` wordmark with `1pt` optical arrival ring,
///   centered pill Step Progress Rail, and adaptive close button.
/// - Left instruction rail (`420pt`, `36pt` gutter, `32pt` column gap, bottom-left `ESC` hint badge).
/// - Right full-bleed cropped macOS desktop mock stage (`GravRadius.panel = 20pt`, 3-stop specular rim)
///   with floating bottom-right Liquid Glass Action Bar (`Skip` + `Continue ↩` / `"Start Using Grav"`).
public struct OnboardingShellView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public let store: AntigravityTelemetryStore
    public let preferences: PreferencesStore
    @Binding public var currentStep: OnboardingStep
    public var flowDirection: OnboardingFlowDirection
    public var isHeaderLogoVisible: Bool
    public var arrivalRingTrigger: Int
    public var onSelectStep: (OnboardingStep) -> Void
    public var onContinue: () -> Void
    public var onSkip: () -> Void
    public var onClose: () -> Void

    @State private var selectedNotchMode: NotchPreviewMode = .thinking
    @State private var isNotchPreviewPinned = false
    @State private var isCloseHovered = false
    @Namespace private var railNamespace

    public init(
        store: AntigravityTelemetryStore,
        preferences: PreferencesStore,
        currentStep: Binding<OnboardingStep>,
        flowDirection: OnboardingFlowDirection = .forward,
        isHeaderLogoVisible: Bool = true,
        arrivalRingTrigger: Int = 0,
        onSelectStep: @escaping (OnboardingStep) -> Void,
        onContinue: @escaping () -> Void,
        onSkip: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.store = store
        self.preferences = preferences
        self._currentStep = currentStep
        self.flowDirection = flowDirection
        self.isHeaderLogoVisible = isHeaderLogoVisible
        self.arrivalRingTrigger = arrivalRingTrigger
        self.onSelectStep = onSelectStep
        self.onContinue = onContinue
        self.onSkip = onSkip
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            // Aerospace Obsidian Dark Liquid Glass window substrate
            shellBackdrop

            VStack(spacing: 0) {
                headerBar
                    .frame(height: 64)
                    .padding(.horizontal, GravSpacing.onboardingGutter)

                // Two-column body: 420pt left rail + 32pt gap + right mock stage
                HStack(alignment: .top, spacing: GravSpacing.onboardingGap) {
                    leftInstructionRail
                        .frame(width: GravSpacing.onboardingLeftRailWidth)
                        .frame(maxHeight: .infinity)

                    rightStageColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, GravSpacing.onboardingGutter)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
        }
    }

    // MARK: - Backdrop

    private var shellBackdrop: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: GravPalette.obsidianSurface, location: 0.0),
                    .init(color: GravPalette.obsidianVoid, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Restrained glacial top-left atmospheric ambient lift
            RadialGradient(
                stops: [
                    .init(color: GravPalette.glacialTeal.opacity(0.11), location: 0.0),
                    .init(color: GravPalette.glacialCyan.opacity(0.04), location: 0.45),
                    .init(color: Color.clear, location: 1.0),
                ],
                center: UnitPoint(x: 0.14, y: 0.0),
                startRadius: 0,
                endRadius: 460
            )

            FilmGrainOverlay(opacity: 0.018)
        }
        .ignoresSafeArea()
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        ZStack {
            // Left: Docked 26x26 GravAppIconTile + "Grav" wordmark + 1pt optical hairline arrival ring
            HStack(spacing: 10) {
                ZStack {
                    OnboardingOpticalRing(
                        triggerID: arrivalRingTrigger,
                        baseSize: 26,
                        maxScale: 2.7,
                        tint: GravPalette.glacialCyan,
                        isDual: false
                    )

                    GravAppIconTile(size: 26)
                        .opacity(isHeaderLogoVisible ? 1 : 0)
                        .background(
                            GeometryReader { iconProxy in
                                let frame = iconProxy.frame(in: .named(OnboardingCoordinateSpace.root))
                                Color.clear.preference(
                                    key: OnboardingLogoCenterPreferenceKey.self,
                                    value: CGPoint(x: frame.midX, y: frame.midY)
                                )
                            }
                        )
                }
                .frame(width: 26, height: 26)

                Text("Grav")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(GravPalette.inkPrimary)

                Spacer()
            }

            // Center: Pill Step Progress Rail
            stepProgressRail

            // Right: Adaptive Dark Liquid Glass Close Button
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isCloseHovered ? GravPalette.inkPrimary : GravPalette.inkTertiary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(isCloseHovered ? GravPalette.cardFillElevated : GravPalette.cardFillSubtle)
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(GravPalette.specularStroke, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(GravMotion.rowHover) {
                        isCloseHovered = hovering
                    }
                }
                .accessibilityLabel("Close Onboarding")
            }
        }
    }

    private var stepProgressRail: some View {
        HStack(spacing: 4) {
            ForEach(OnboardingStep.allCases) { step in
                let isCurrent = step == currentStep
                let isCompleted = step.index < currentStep.index

                Button {
                    onSelectStep(step)
                } label: {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(
                                    isCurrent
                                        ? GravPalette.glacialTeal
                                        : (isCompleted ? GravPalette.emerald.opacity(0.22) : GravPalette.cardFillBase)
                                )
                                .frame(width: 17, height: 17)

                            if isCompleted {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundStyle(GravPalette.emerald)
                            } else {
                                Text("\(step.stepNumber)")
                                    .font(GravTypography.monoMicro)
                                    .foregroundStyle(isCurrent ? GravPalette.obsidianVoid : GravPalette.inkTertiary)
                            }
                        }

                        Text(step.shortTitle)
                            .font(GravTypography.caption)
                            .foregroundStyle(
                                isCurrent
                                    ? GravPalette.inkPrimary
                                    : (isCompleted ? GravPalette.inkSecondary : GravPalette.inkTertiary)
                            )
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background {
                        if isCurrent {
                            Capsule(style: .continuous)
                                .fill(GravPalette.cardFillElevated)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(GravPalette.specularStroke, lineWidth: 0.5)
                                )
                                .matchedGeometryEffect(id: "activeStepPill", in: railNamespace)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(GravPalette.cardFillSubtle)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(GravPalette.specularStroke, lineWidth: 0.5)
        )
        .animation(reduceMotion ? GravMotion.subtleFade : GravMotion.railSpring, value: currentStep)
    }

    // MARK: - Left Instruction Rail

    private var leftInstructionRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Step eyebrow counter
            HStack(spacing: 8) {
                Text("STEP \(currentStep.stepNumber) OF \(OnboardingStep.allCases.count)")
                    .font(GravTypography.monoMicro)
                    .tracking(1.1)
                    .foregroundStyle(GravPalette.glacialTeal)

                Rectangle()
                    .fill(GravPalette.glacialTeal.opacity(0.28))
                    .frame(height: 0.5)
            }
            .padding(.bottom, 12)

            // Step title & subtitle
            VStack(alignment: .leading, spacing: 8) {
                Text(currentStep.title)
                    .font(GravTypography.onboardingTitle)
                    .foregroundStyle(GravPalette.inkPrimary)

                Text(currentStep.subtitle)
                    .font(GravTypography.onboardingSubtitle)
                    .foregroundStyle(GravPalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .id("header-\(currentStep.id)")
            .transition(stepTransition)

            // Step-specific interactive content
            Group {
                switch currentStep {
                case .connect:
                    OnboardingStepConnectRail(store: store)
                case .notchPreview:
                    OnboardingStepNotchPreviewRail(
                        selectedMode: $selectedNotchMode,
                        isPreviewPinnedExpanded: $isNotchPreviewPinned
                    )
                case .preferences:
                    OnboardingStepPreferencesRail(preferences: preferences)
                }
            }
            .id("rail-\(currentStep.id)")
            .transition(stepTransition)
            .padding(.top, 22)

            Spacer(minLength: 16)

            // Bottom-left ESC hint badge
            HStack(spacing: 7) {
                OnboardingKeycapBadge("ESC")
                Text("to skip setup")
                    .font(GravTypography.caption)
                    .foregroundStyle(GravPalette.inkQuaternary)
            }
            .padding(.bottom, 4)
        }
        .animation(reduceMotion ? GravMotion.subtleFade : GravMotion.contentSlide, value: currentStep)
    }

    // MARK: - Right Cropped Stage + Floating Bottom-Right Liquid Glass Action Bar

    private var rightStageColumn: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                switch currentStep {
                case .connect:
                    OnboardingStepConnectStage(store: store)
                case .notchPreview:
                    OnboardingStepNotchPreviewStage(
                        selectedMode: selectedNotchMode,
                        isPinnedExpanded: $isNotchPreviewPinned
                    )
                case .preferences:
                    OnboardingStepPreferencesStage(store: store, preferences: preferences)
                }
            }
            .id("stage-\(currentStep.id)")
            .transition(stageTransition)
            .animation(reduceMotion ? GravMotion.subtleFade : GravMotion.contentSlide, value: currentStep)

            floatingActionBar
                .padding(.trailing, 18)
                .padding(.bottom, 18)
        }
    }

    private var floatingActionBar: some View {
        HStack(spacing: 8) {
            if !currentStep.isLast {
                ShellGhostButton(title: "Skip", action: onSkip)
            }

            ShellPrimaryButton(
                title: currentStep.primaryActionTitle,
                showReturnGlyph: !currentStep.isLast,
                isFinalStep: currentStep.isLast,
                action: onContinue
            )
        }
        .padding(6)
        .background(
            Capsule(style: .continuous)
                .fill(Color(red: 0x08 / 255.0, green: 0x0E / 255.0, blue: 0x15 / 255.0).opacity(0.84))
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(GravPalette.specularStroke, lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 20, y: 8)
    }

    private var stepTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        let offset: CGFloat = flowDirection == .forward ? 14 : -14
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: offset)),
            removal: .opacity.combined(with: .offset(x: -offset * 0.6))
        )
    }

    private var stageTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.985)),
            removal: .opacity
        )
    }
}

// MARK: - Floating Action Bar Buttons

private struct ShellGhostButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(GravTypography.bodyMedium)
                .foregroundStyle(isHovered ? GravPalette.inkPrimary : GravPalette.inkSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(isHovered ? GravPalette.cardFillElevated : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(GravMotion.rowHover) {
                isHovered = hovering
            }
        }
    }
}

private struct ShellPrimaryButton: View {
    let title: String
    let showReturnGlyph: Bool
    let isFinalStep: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                if showReturnGlyph {
                    Text("↩")
                        .font(GravTypography.monoMicro)
                        .foregroundStyle(GravPalette.obsidianVoid.opacity(0.72))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle.grav(4)
                                .fill(GravPalette.obsidianVoid.opacity(0.12))
                        )
                } else if isFinalStep {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .foregroundStyle(GravPalette.obsidianVoid)
            .padding(.horizontal, 18)
            .padding(.vertical, 8.5)
            .background(
                Capsule(style: .continuous)
                    .fill(GravPalette.brandAccentGradient)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(isHovered ? 0.55 : 0.35), lineWidth: 0.5)
            )
            .brightness(isHovered ? 0.04 : 0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(GravMotion.rowHover) {
                isHovered = hovering
            }
        }
    }
}
