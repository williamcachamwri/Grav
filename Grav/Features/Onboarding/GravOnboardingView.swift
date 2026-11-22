//
//  GravOnboardingView.swift
//  Grav
//
//  Root onboarding view: Liquid Glass backdrop, header with 22pt progress spine, two-column step
//  layout with 3D macOS Spaces stage and floating Liquid Glass action bar, completion screen,
//  and full-window Welcome aurora choreography, ported 1:1 from Snapzy's `SnapzyOnboardingView.swift`.
//

import AppKit
import SwiftUI

struct GravOnboardingView: View {
    let store: AntigravityTelemetryStore
    let preferences: PreferencesStore
    /// Called when onboarding finishes. When `launchIconWindowFrame` is non-nil (user completed via
    /// "Start Using Grav"), the window controller performs the celebratory desktop ascent straight
    /// into the live MacBook notch.
    var onDismiss: (_ launchIconWindowFrame: CGRect?) -> Void

    @StateObject private var state = GravOnboardingState()
    @State private var isShowingCompletion = false
    @State private var isLaunchingFinale = false
    @State private var completionLaunchTrigger = 0
    @State private var isShowingWelcome: Bool
    @State private var isFlowMounted: Bool
    @State private var isFlowSettled: Bool
    @State private var isBrandIconDocked: Bool
    @State private var brandIconFrame: CGRect = CGRect(
        x: GravOnboardingMetrics.gutter,
        y: (GravOnboardingMetrics.gutter - 10) + (GravOnboardingMetrics.headerHeight - 26) * 0.5,
        width: 26,
        height: 26
    )
    @State private var welcomeStartTrigger = 0
    @Environment(\.accessibilityReduceMotion) private var envReduceMotion

    init(
        store: AntigravityTelemetryStore,
        preferences: PreferencesStore,
        startAtWelcome: Bool = true,
        onDismiss: @escaping (_ launchIconWindowFrame: CGRect?) -> Void
    ) {
        self.store = store
        self.preferences = preferences
        self.onDismiss = onDismiss
        _isShowingWelcome = State(initialValue: startAtWelcome)
        _isFlowMounted = State(initialValue: !startAtWelcome)
        _isFlowSettled = State(initialValue: !startAtWelcome)
        _isBrandIconDocked = State(initialValue: !startAtWelcome)
    }

    private var reduceMotion: Bool {
        GravMotionPreferences.shared.reduceMotion || envReduceMotion
    }

    var body: some View {
        ZStack {
            LiquidGlassWindowBackdrop()

            if isFlowMounted {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, GravOnboardingMetrics.gutter)
                        .padding(.top, GravOnboardingMetrics.gutter - 10)
                        .opacity(isLaunchingFinale ? 0 : 1)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.20), value: isLaunchingFinale)

                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .animation(GravMotionPreferences.shared.spec(.morph).animation, value: state.currentStep)
                        .animation(GravMotionPreferences.shared.spec(.settle).animation, value: isShowingCompletion)
                }
            }

            if isShowingWelcome {
                GravOnboardingWelcome(
                    externalStartTrigger: welcomeStartTrigger,
                    targetLogoFrame: brandIconFrame,
                    onReadyForPrewarm: prewarmFlow,
                    onBeginTransition: beginFlowReveal,
                    onDockLogo: dockBrandLogo,
                    onCompleteTransition: completeFlowReveal,
                    onClose: { finish(launchIconWindowFrame: nil) }
                )
            }
        }
        .coordinateSpace(name: OnboardingRootCoordinateSpace.name)
        .onPreferenceChange(OnboardingBrandIconFrameKey.self) { frame in
            if frame.width > 0 && frame.height > 0 {
                brandIconFrame = frame
            }
        }
        .frame(
            minWidth: GravOnboardingMetrics.minSize.width,
            maxWidth: GravOnboardingMetrics.maxSize.width,
            minHeight: GravOnboardingMetrics.minSize.height,
            maxHeight: GravOnboardingMetrics.maxSize.height
        )
        .environment(\.colorScheme, .dark)
        .background(keyboardShortcuts)
        .onAppear {
            store.refreshConnectionStatus()
            state.syncConnectionStatus(store.connectionStatus)
        }
    }

    // MARK: - Content

    private var content: some View {
        ZStack(alignment: .top) {
            if isShowingCompletion {
                GravOnboardingCompletionCard(
                    externalLaunchTrigger: completionLaunchTrigger,
                    onBeginLaunch: { isLaunchingFinale = true },
                    onFinish: { iconFrame in
                        finish(launchIconWindowFrame: iconFrame)
                    },
                    onBack: retreat
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, GravOnboardingMetrics.gutter)
                .padding(.bottom, GravOnboardingMetrics.gutter)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(2)
            } else {
                stepColumns
                    .transition(stepTransition)
                    .zIndex(0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var stepTransition: AnyTransition {
        if GravMotionPreferences.shared.reduceMotion {
            return .opacity
        }
        let travel = min(18 + CGFloat(state.navigationDistance) * 14, 58)
        let arrival: CGFloat = state.navigationDirection == .forward ? travel : -travel
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: arrival)).combined(with: .scale(scale: 0.985)),
            removal: .opacity.combined(with: .offset(x: -arrival))
        )
    }

    private var stepColumns: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left Column: instruction rail + bottom-left escape hint
            VStack(alignment: .leading, spacing: 0) {
                GravOnboardingInstructionPanel(
                    state: state,
                    store: store,
                    preferences: preferences,
                    isRevealed: isFlowSettled
                )
                .drawingGroup()
                .padding(.top, 10)
                .id(state.currentStep)
                .transition(stepTransition)

                Spacer(minLength: 16)

                GravOnboardingEscapeHint(text: escapeHintText)
                    .frame(height: GravOnboardingMetrics.footerHeight, alignment: .leading)
                    .padding(.bottom, GravOnboardingMetrics.gutter - 12)
            }
            .frame(width: GravOnboardingMetrics.railWidth, alignment: .topLeading)
            .padding(.leading, GravOnboardingMetrics.gutter)
            .padding(.trailing, GravOnboardingMetrics.columnGap)
            .offset(x: reduceMotion ? 0 : (isFlowSettled ? 0 : -22))
            .animation(
                reduceMotion ? nil : .timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.78),
                value: isFlowSettled
            )

            // Right Column: full-bleed cropped macOS screen stage with floating Liquid Glass Action Bar
            ZStack(alignment: .bottomTrailing) {
                GravOnboardingMockHost(
                    state: state,
                    store: store,
                    preferences: preferences
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 6)
                .opacity(isFlowSettled ? 1 : 0)
                .scaleEffect(reduceMotion ? 1.0 : (isFlowSettled ? 1.0 : 0.965))
                .offset(y: reduceMotion ? 0 : (isFlowSettled ? 0 : 14))
                .animation(
                    reduceMotion ? .easeOut(duration: 0.20) : .timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.86).delay(0.06),
                    value: isFlowSettled
                )

                // Liquid Glass Golden Rule: never animate `.opacity` on a view containing `.glassEffect`.
                actionBar
                    .padding(.trailing, GravOnboardingMetrics.gutter)
                    .padding(.bottom, GravOnboardingMetrics.gutter - 12)
                    .offset(y: reduceMotion ? 0 : (isFlowSettled ? 0 : 64))
                    .animation(
                        reduceMotion ? nil : .timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.84).delay(0.10),
                        value: isFlowSettled
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            HStack {
                brand
                Spacer(minLength: 0)
                GravOnboardingCloseButton(action: { finish(launchIconWindowFrame: nil) })
                    .opacity(isFlowSettled ? 1 : 0)
                    .offset(y: reduceMotion ? 0 : (isFlowSettled ? 0 : -8))
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.20) : .timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.76).delay(0.08),
                        value: isFlowSettled
                    )
            }

            if !isShowingCompletion {
                GravOnboardingStepRail(state: state)
                    .frame(maxWidth: 420)
                    .opacity(isFlowSettled ? 1 : 0)
                    .offset(y: reduceMotion ? 0 : (isFlowSettled ? 0 : -8))
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.20) : .timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.78).delay(0.06),
                        value: isFlowSettled
                    )
                    .transition(.opacity)
            }
        }
        .frame(height: GravOnboardingMetrics.headerHeight)
        .padding(.bottom, GravSpace.lg)
    }

    private var brand: some View {
        HStack(spacing: GravSpace.lg) {
            Image(nsImage: GravOnboardingIconCache.appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 26, height: 26)
                .clipShape(Radius.rect(Radius.controlS))
                // Stays fixed at exact resting coordinates (zero offset) so the Welcome morph lands on it
                // pixel-for-pixel, then reveals synchronously on dock.
                .opacity(isBrandIconDocked ? 1 : 0)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: OnboardingBrandIconFrameKey.self,
                            value: geo.frame(in: .named(OnboardingRootCoordinateSpace.name))
                        )
                    }
                )

            Text("Grav")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GravGlassInk.primary)
                .opacity(isFlowSettled ? 1 : 0)
                .offset(x: reduceMotion ? 0 : (isFlowSettled ? 0 : -10))
                .animation(
                    reduceMotion ? .easeOut(duration: 0.20) : .timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.56).delay(0.56),
                    value: isFlowSettled
                )
        }
        .fixedSize()
    }

    // MARK: - Footer & Action Bar

    private var escapeHintText: String {
        state.canGoBack ? "Go back" : "Close"
    }

    private var actionBar: some View {
        let isLastStep = !state.canGoForward
        let skipTitle: String? = isLastStep ? nil : "Skip"
        let skipAction: (() -> Void)? = isLastStep ? nil : { skip() }
        let canAdvance = state.isCurrentStepComplete || isLastStep

        return GravOnboardingActionBar(
            skipTitle: skipTitle,
            continueTitle: isLastStep ? "Finish" : "Continue",
            continueKey: "\u{21A9}",
            isContinueEnabled: canAdvance,
            isHinted: state.isCurrentStepComplete || isLastStep,
            onSkip: skipAction,
            onContinue: advance
        )
    }

    // MARK: - Keyboard Shortcuts

    private var keyboardShortcuts: some View {
        ZStack {
            Button("", action: advance)
                .keyboardShortcut(.defaultAction)

            Button("", action: retreat)
                .keyboardShortcut(.cancelAction)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: - Navigation

    private func startFlow() {
        welcomeStartTrigger += 1
    }

    private func prewarmFlow() {
        guard !isFlowMounted else { return }
        isFlowMounted = true
    }

    private func beginFlowReveal() {
        if !isFlowMounted {
            isFlowMounted = true
        }
        isFlowSettled = true
    }

    private func dockBrandLogo() {
        isBrandIconDocked = true
    }

    private func completeFlowReveal() {
        isBrandIconDocked = true
        isShowingWelcome = false
    }

    private func advance() {
        if isShowingWelcome {
            startFlow()
            return
        }
        if isShowingCompletion {
            completionLaunchTrigger += 1
            return
        }
        guard state.canGoForward else {
            withAnimation(GravMotionPreferences.shared.spec(.settle).animation) {
                isShowingCompletion = true
            }
            return
        }
        state.markCurrentStepVisited()
        state.nextStep()
    }

    private func skip() {
        guard state.canGoForward else {
            withAnimation(GravMotionPreferences.shared.spec(.settle).animation) {
                isShowingCompletion = true
            }
            return
        }
        state.nextStep()
    }

    private func retreat() {
        if isShowingWelcome {
            startFlow()
            return
        }
        if isShowingCompletion {
            guard !isLaunchingFinale else { return }
            withAnimation(GravMotionPreferences.shared.spec(.settle).animation) {
                isShowingCompletion = false
            }
        } else if state.canGoBack {
            state.previousStep()
        } else {
            finish(launchIconWindowFrame: nil)
        }
    }

    private func finish(launchIconWindowFrame: CGRect?) {
        preferences.hasCompletedOnboarding = true
        let isUnderXCTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let finaleFrame = isUnderXCTest ? nil : launchIconWindowFrame
        onDismiss(finaleFrame)
    }
}

private enum OnboardingRootCoordinateSpace {
    static let name = "GravOnboardingRootSpace"
}

private struct OnboardingBrandIconFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let candidate = nextValue()
        if candidate.width > 0 && candidate.height > 0 {
            value = candidate
        }
    }
}
