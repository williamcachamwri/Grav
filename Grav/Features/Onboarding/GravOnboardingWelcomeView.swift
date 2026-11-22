import SwiftUI

/// Full-bleed 7-beat Welcome choreography for Grav:
/// 1. Obsidian void (`#05080C`) -> 36-segment 4-harmonic liquid orb blooms (`0 -> 0.27`) with glacial corona
/// 2. Breathing hover beat -> orb unfolds edge-to-edge (`0.27 -> 1.0`) into Glacial Aurora + film grain
/// 3. Crisp white `GravOrbitalMark` (`84pt`) pulls out of `28pt` optical cinema blur at dead center
/// 4. Mark glides upward (`84pt -> 56pt`) through silky rack-focus blur shimmer to perch above headline
/// 5. Word-by-word focus-pull headline `"Meet Grav."` with trailing `.` landing a crisp beat after
/// 6. Subtitle `"Live telemetry for Antigravity, right in your MacBook notch."` focuses into place
/// 7. Editorial magnetic pill button materializes while Step 1 silently pre-warms behind the aurora
/// Exit: Aurora exhales (`1.0 -> 1.055`) & dissolves while the mark crystallizes into `GravAppIconTile` (`26x26`)
/// and flies along a curved `C∞` cubic Bezier arc pixel-for-pixel into the top-left header logo position.
public struct GravOnboardingWelcomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Exact center of the docked `26x26` header icon measured in `OnboardingCoordinateSpace.root`.
    public var targetLogoCenter: CGPoint?
    /// Incrementing trigger invoked by keyboard `Return` to initiate the exit flight.
    public var exitTrigger: Int
    /// Invoked at Beat 7 so Step 1 mounts silently behind the aurora.
    public var onPrewarmStep1: () -> Void
    /// Invoked when exit begins so the pre-warmed shell fades smoothly into view.
    public var onBeginExit: () -> Void
    /// Invoked the exact instant the flying `26x26` icon lands on the header anchor.
    public var onLogoArrived: () -> Void

    // Beats 1–2: Organic liquid portal
    @State private var portalProgress: CGFloat = 0
    @State private var choreographyStart: Date = Date()

    // Beats 3–4: Hero orbital mark focus-pull & glide
    @State private var markOpacity: Double = 0
    @State private var markBlur: CGFloat = 28
    @State private var markScale: CGFloat = 0.88
    @State private var markSize: CGFloat = 84
    @State private var markVerticalOffset: CGFloat = 0
    @State private var markShimmerBlur: CGFloat = 0

    // Beat 5: Word-by-word focus-pull headline ("Meet" + "Grav" + ".")
    @State private var wordMeetVisible = false
    @State private var wordGravVisible = false
    @State private var periodVisible = false

    // Beat 6: Subtitle focus-pull
    @State private var subtitleVisible = false

    // Beat 7: Magnetic CTA pill & prewarm state
    @State private var ctaVisible = false
    @State private var isReadyForExit = false

    // Exit choreography state
    @State private var isExiting = false
    @State private var exitStartDate: Date?
    @State private var hasReportedArrival = false

    private static let perchedOffsetY: CGFloat = -92
    private static let flightDuration: TimeInterval = 0.78
    private static let reducedFlightDuration: TimeInterval = 0.24

    public init(
        targetLogoCenter: CGPoint?,
        exitTrigger: Int = 0,
        onPrewarmStep1: @escaping () -> Void,
        onBeginExit: @escaping () -> Void,
        onLogoArrived: @escaping () -> Void
    ) {
        self.targetLogoCenter = targetLogoCenter
        self.exitTrigger = exitTrigger
        self.onPrewarmStep1 = onPrewarmStep1
        self.onBeginExit = onBeginExit
        self.onLogoArrived = onLogoArrived
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            let perchedPoint = CGPoint(x: center.x, y: center.y + Self.perchedOffsetY)
            // Fallback aligns with OnboardingShellView's exact header logo coordinates (36pt gutter + 13pt half icon, 32pt header midY)
            let resolvedTarget = targetLogoCenter ?? CGPoint(x: GravSpacing.onboardingGutter + 13, y: 32)

            if isExiting, let exitStartDate {
                TimelineView(.animation(minimumInterval: 1.0 / 120.0)) { timeline in
                    let duration = reduceMotion ? Self.reducedFlightDuration : Self.flightDuration
                    let rawProgress = max(0, min(1, timeline.date.timeIntervalSince(exitStartDate) / duration))
                    exitScene(
                        size: size,
                        center: center,
                        perchedPoint: perchedPoint,
                        targetPoint: resolvedTarget,
                        rawProgress: CGFloat(rawProgress)
                    )
                }
            } else {
                introScene(size: size, center: center)
            }
        }
        .task {
            await runChoreography()
        }
        .onChange(of: exitTrigger) { _, newValue in
            guard newValue > 0 else { return }
            beginExitTransition()
        }
    }

    // MARK: - Beats 1–7 Intro Composition

    @ViewBuilder
    private func introScene(size: CGSize, center: CGPoint) -> some View {
        let shouldDrivePortalPhase = !reduceMotion && portalProgress > 0 && portalProgress < 0.995

        ZStack {
            // Beat 1 substrate: Pure Hardware Obsidian void (`#05080C`)
            GravPalette.obsidianVoid

            // Beat 1–2: Soft glacial cyan-teal ambient corona & 36-segment 4-harmonic liquid portal
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !shouldDrivePortalPhase)) { timeline in
                let elapsed = timeline.date.timeIntervalSince(choreographyStart)
                let phase = reduceMotion ? 0 : CGFloat(elapsed * 2.15)

                ZStack {
                    PortalAmbientCorona(progress: portalProgress, phase: phase)

                    ZStack {
                        GlacialAuroraView(isPaused: false)
                        FilmGrainOverlay(opacity: 0.035)
                    }
                    .clipShape(OrganicPortalShape(progress: portalProgress, phase: phase))
                }
            }

            // Beats 5–7: Editorial center stack (positioned relative to center below perched mark)
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 26)

                // Beat 5: Word-by-word focus-pull headline "Meet Grav."
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    focusWord("Meet", visible: wordMeetVisible)
                    Text(" ")
                        .font(GravTypography.heroTitle)
                    focusWord("Grav", visible: wordGravVisible)
                    Text(".")
                        .font(GravTypography.heroTitle)
                        .foregroundStyle(GravPalette.titaniumWhite)
                        .opacity(periodVisible ? 1 : 0)
                        .blur(radius: reduceMotion ? 0 : (periodVisible ? 0 : 7))
                        .scaleEffect(reduceMotion ? 1 : (periodVisible ? 1.0 : 1.24))
                        .offset(y: reduceMotion ? 0 : (periodVisible ? 0 : -3))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Meet Grav.")

                // Beat 6: Subtitle
                Text("Live telemetry for Antigravity, right in your MacBook notch.")
                    .font(.system(size: 16, weight: .regular, design: .default))
                    .foregroundStyle(GravPalette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
                    .opacity(subtitleVisible ? 1 : 0)
                    .blur(radius: reduceMotion ? 0 : (subtitleVisible ? 0 : 10))
                    .offset(y: reduceMotion ? 0 : (subtitleVisible ? 0 : 8))

                // Beat 7: Editorial magnetic arrow pill CTA
                OnboardingMagneticPillButton(title: "Get Started") {
                    beginExitTransition()
                }
                .padding(.top, 34)
                .opacity(ctaVisible ? 1 : 0)
                .blur(radius: reduceMotion ? 0 : (ctaVisible ? 0 : 8))
                .offset(y: reduceMotion ? 0 : (ctaVisible ? 0 : 10))
                .allowsHitTesting(ctaVisible)
            }
            .position(x: center.x, y: center.y + 42)

            // Beats 3–4: Hero white GravOrbitalMark
            GravOrbitalMark(size: markSize, tint: GravPalette.titaniumWhite)
                .scaleEffect(markScale)
                .blur(radius: reduceMotion ? 0 : (markBlur + markShimmerBlur))
                .opacity(markOpacity)
                .position(x: center.x, y: center.y + markVerticalOffset)
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Exit Transition (Aurora Exhale + Curved C∞ Bezier Logo Flight)

    @ViewBuilder
    private func exitScene(
        size: CGSize,
        center: CGPoint,
        perchedPoint: CGPoint,
        targetPoint: CGPoint,
        rawProgress: CGFloat
    ) -> some View {
        let auroraProgress = min(1, rawProgress / 0.56)
        let auroraEase = 1 - pow(1 - auroraProgress, 2.4)
        let auroraScale: CGFloat = reduceMotion ? 1.0 : (1.0 + 0.055 * auroraEase)
        let auroraOpacity: Double = Double(max(0, 1 - auroraEase))

        let copyProgress = min(1, rawProgress / 0.28)
        let copyOpacity = Double(max(0, 1 - copyProgress))

        let flightU = CubicBezierArc.smoothStep(rawProgress)
        let arc = CubicBezierArc.liftedArc(
            from: perchedPoint,
            to: targetPoint,
            lift: 74,
            lateralBias: 0.26
        )
        let logoPosition = reduceMotion
            ? CGPoint(
                x: perchedPoint.x + (targetPoint.x - perchedPoint.x) * flightU,
                y: perchedPoint.y + (targetPoint.y - perchedPoint.y) * flightU
            )
            : arc.point(at: flightU)

        let currentSize = 56 + (26 - 56) * flightU
        let tileOpacity = Double(min(1, flightU / 0.44))
        let orbitalOpacity = Double(max(0, 1 - flightU / 0.38))
        let flightShimmer: CGFloat = reduceMotion ? 0 : sin(flightU * .pi) * 2.0

        ZStack {
            // Aurora exhales (scale 1.0 -> 1.055) and dissolves into Dark Liquid Glass underneath
            ZStack {
                GlacialAuroraView(isPaused: true)
                FilmGrainOverlay(opacity: 0.035)
            }
            .scaleEffect(auroraScale)
            .opacity(auroraOpacity)

            // Typography & CTA dissolve swiftly upward
            VStack(spacing: 0) {
                Spacer().frame(height: 26)
                Text("Meet Grav.")
                    .font(GravTypography.heroTitle)
                    .foregroundStyle(GravPalette.titaniumWhite)

                Text("Live telemetry for Antigravity, right in your MacBook notch.")
                    .font(.system(size: 16, weight: .regular, design: .default))
                    .foregroundStyle(GravPalette.inkSecondary)
                    .padding(.top, 14)

                OnboardingMagneticPillButton(title: "Get Started", action: {})
                    .padding(.top, 34)
                    .allowsHitTesting(false)
            }
            .position(x: center.x, y: center.y + 42)
            .opacity(copyOpacity)
            .offset(y: reduceMotion ? 0 : -14 * copyProgress)
            .blur(radius: reduceMotion ? 0 : 7 * copyProgress)

            // Crystallizing flying logo: white GravOrbitalMark -> 26x26 GravAppIconTile
            ZStack {
                GravOrbitalMark(size: currentSize, tint: GravPalette.titaniumWhite)
                    .opacity(orbitalOpacity)

                GravAppIconTile(size: currentSize)
                    .opacity(tileOpacity)
            }
            .blur(radius: flightShimmer)
            .position(logoPosition)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func focusWord(_ text: String, visible: Bool) -> some View {
        Text(text)
            .font(GravTypography.heroTitle)
            .foregroundStyle(GravPalette.titaniumWhite)
            .opacity(visible ? 1 : 0)
            .blur(radius: reduceMotion ? 0 : (visible ? 0 : 14))
            .offset(y: reduceMotion ? 0 : (visible ? 0 : 10))
    }

    // MARK: - 7-Beat Choreography Sequencer

    @MainActor
    private func runChoreography() async {
        choreographyStart = Date()

        if reduceMotion {
            portalProgress = 1.0
            markSize = 56
            markVerticalOffset = Self.perchedOffsetY
            markBlur = 0
            markScale = 1.0
            withAnimation(.easeOut(duration: 0.24)) {
                markOpacity = 1.0
                wordMeetVisible = true
                wordGravVisible = true
                periodVisible = true
                subtitleVisible = true
                ctaVisible = true
            }
            isReadyForExit = true
            onPrewarmStep1()
            return
        }

        // Beat 1: Organic liquid orb blooms from obsidian void (0 -> 0.27)
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled, !isExiting else { return }
        withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.88)) {
            portalProgress = 0.27
        }

        // Beat 2: Breathing hover beat, then unfold edge-to-edge (0.27 -> 1.0)
        try? await Task.sleep(for: .milliseconds(1260))
        guard !Task.isCancelled, !isExiting else { return }
        withAnimation(.timingCurve(0.32, 0.0, 0.18, 1.0, duration: 1.02)) {
            portalProgress = 1.0
        }

        // Beat 3: Crisp white GravOrbitalMark pulls out of 28pt cinema blur in dead center (84pt)
        try? await Task.sleep(for: .milliseconds(580))
        guard !Task.isCancelled, !isExiting else { return }
        isReadyForExit = true
        withAnimation(.timingCurve(0.16, 1.0, 0.30, 1.0, duration: 0.82)) {
            markOpacity = 1.0
            markBlur = 0
            markScale = 1.0
        }

        // Beat 4: Mark glides upward (84pt -> 56pt) through silky rack-focus blur shimmer
        try? await Task.sleep(for: .milliseconds(720))
        guard !Task.isCancelled, !isExiting else { return }
        withAnimation(.timingCurve(0.40, 0.0, 0.20, 1.0, duration: 0.68)) {
            markSize = 56
            markVerticalOffset = Self.perchedOffsetY
        }
        withAnimation(.easeIn(duration: 0.24)) {
            markShimmerBlur = 5.5
        }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled, !isExiting else { return }
        withAnimation(.easeOut(duration: 0.40)) {
            markShimmerBlur = 0
        }

        // Beat 5: Word-by-word focus-pull headline "Meet Grav." with trailing "." a crisp beat after
        try? await Task.sleep(for: .milliseconds(160))
        guard !Task.isCancelled, !isExiting else { return }
        withAnimation(.timingCurve(0.16, 1.0, 0.30, 1.0, duration: 0.56)) {
            wordMeetVisible = true
        }

        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled, !isExiting else { return }
        withAnimation(.timingCurve(0.16, 1.0, 0.30, 1.0, duration: 0.56)) {
            wordGravVisible = true
        }

        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled, !isExiting else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
            periodVisible = true
        }

        // Beat 6: Subtitle focuses gently into place
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled, !isExiting else { return }
        withAnimation(.timingCurve(0.16, 1.0, 0.30, 1.0, duration: 0.58)) {
            subtitleVisible = true
        }

        // Beat 7: Editorial magnetic arrow pill materializes while Step 1 silently pre-warms
        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled, !isExiting else { return }
        onPrewarmStep1()
        withAnimation(.timingCurve(0.16, 1.0, 0.30, 1.0, duration: 0.52)) {
            ctaVisible = true
        }
    }

    @MainActor
    private func beginExitTransition() {
        guard !isExiting, isReadyForExit || ctaVisible else { return }
        onPrewarmStep1()
        isExiting = true
        exitStartDate = Date()
        onBeginExit()

        let duration = reduceMotion ? Self.reducedFlightDuration : Self.flightDuration
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !hasReportedArrival else { return }
            hasReportedArrival = true
            onLogoArrived()
        }
    }
}
