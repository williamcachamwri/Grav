import Observation
import SwiftUI

/// `@MainActor` observable session controller linking `OnboardingWindowController` keyboard events
/// and finale launch coordinates with the SwiftUI `OnboardingRootView` hierarchy.
@MainActor
@Observable
final class OnboardingFlowModel {
    var phase: OnboardingPhase = .welcome
    var currentStep: OnboardingStep = .connect
    var flowDirection: OnboardingFlowDirection = .forward

    /// Set to `true` at Beat 7 so Step 1 silently pre-warms behind the aurora.
    var isStep1Prewarmed: Bool = false

    /// Controls visibility of the pre-warmed shell during the Welcome exit dissolve.
    var isShellRevealed: Bool = false

    /// Keeps the docked `26x26` header icon hidden until the flying welcome logo lands
    /// (and hides it again when the Grand Finale launches it out of the window into the notch).
    var isHeaderLogoVisible: Bool = false

    /// Incremented to fire the single `1pt` optical hairline arrival ring at the docked header icon.
    var arrivalRingTrigger: Int = 0

    /// Incremented by keyboard `Return` while in `.welcome` to initiate the Welcome exit flight.
    var welcomeExitTrigger: Int = 0

    /// Exact center of the docked `26x26` header icon measured in SwiftUI top-left window coordinates.
    var headerLogoCenterInWindow: CGPoint = CGPoint(x: GravSpacing.onboardingGutter + 13, y: 32)

    /// Callbacks supplied by `OnboardingWindowController`.
    var onRequestSkipOrClose: (() -> Void)?
    var onRequestGrandFinale: ((CGPoint) -> Void)?

    func reset(startAtWelcome: Bool = true) {
        phase = startAtWelcome ? .welcome : .steps
        currentStep = .connect
        flowDirection = .forward
        isStep1Prewarmed = !startAtWelcome
        isShellRevealed = !startAtWelcome
        isHeaderLogoVisible = !startAtWelcome
        arrivalRingTrigger = 0
        welcomeExitTrigger = 0
    }

    func selectStep(_ step: OnboardingStep) {
        guard step != currentStep else { return }
        flowDirection = step.index > currentStep.index ? .forward : .backward
        currentStep = step
    }

    func handleReturn() {
        switch phase {
        case .welcome:
            welcomeExitTrigger += 1
        case .steps:
            advanceOrComplete()
        }
    }

    func handleEscape() {
        onRequestSkipOrClose?()
    }

    func advanceOrComplete() {
        if let next = currentStep.next {
            flowDirection = .forward
            currentStep = next
        } else {
            // Vacate the docked header icon as it lifts off into the full-screen finale overlay
            isHeaderLogoVisible = false
            onRequestGrandFinale?(headerLogoCenterInWindow)
        }
    }
}

/// Root SwiftUI view hosted inside `OnboardingWindowController`, clipping cleanly to
/// `GravRadius.window` (26pt continuous) with a `0.5pt` outer top-lit specular border.
struct OnboardingRootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let store: AntigravityTelemetryStore
    let preferences: PreferencesStore
    let model: OnboardingFlowModel

    var body: some View {
        @Bindable var bindableModel = model

        ZStack {
            // Pre-warmed Step 1..3 Dark Liquid Glass Shell
            if model.isStep1Prewarmed || model.phase == .steps {
                OnboardingShellView(
                    store: store,
                    preferences: preferences,
                    currentStep: $bindableModel.currentStep,
                    flowDirection: model.flowDirection,
                    isHeaderLogoVisible: model.isHeaderLogoVisible,
                    arrivalRingTrigger: model.arrivalRingTrigger,
                    onSelectStep: { step in
                        model.selectStep(step)
                    },
                    onContinue: {
                        model.advanceOrComplete()
                    },
                    onSkip: {
                        model.handleEscape()
                    },
                    onClose: {
                        model.handleEscape()
                    }
                )
                .opacity(model.isShellRevealed || model.phase == .steps ? 1 : 0)
                .allowsHitTesting(model.phase == .steps)
            }

            // Full-bleed 7-beat Welcome experience sitting above the pre-warmed shell
            if model.phase == .welcome {
                GravOnboardingWelcomeView(
                    targetLogoCenter: model.headerLogoCenterInWindow,
                    exitTrigger: model.welcomeExitTrigger,
                    onPrewarmStep1: {
                        if !model.isStep1Prewarmed {
                            model.isStep1Prewarmed = true
                        }
                    },
                    onBeginExit: {
                        let anim = reduceMotion ? GravMotion.subtleFade : Animation.easeOut(duration: 0.42)
                        withAnimation(anim) {
                            model.isShellRevealed = true
                        }
                    },
                    onLogoArrived: {
                        model.isHeaderLogoVisible = true
                        model.phase = .steps
                        model.arrivalRingTrigger += 1
                    }
                )
            }
        }
        .coordinateSpace(name: OnboardingCoordinateSpace.root)
        .onPreferenceChange(OnboardingLogoCenterPreferenceKey.self) { point in
            if let point {
                model.headerLogoCenterInWindow = point
            }
        }
        .clipShape(RoundedRectangle.grav(GravRadius.window))
        .overlay(
            RoundedRectangle.grav(GravRadius.window)
                .strokeBorder(GravPalette.specularStroke, lineWidth: 0.5)
        )
        .preferredColorScheme(.dark)
    }
}
