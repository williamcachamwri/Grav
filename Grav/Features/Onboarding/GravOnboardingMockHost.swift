//
//  GravOnboardingMockHost.swift
//  Grav
//
//  Right-column stage: a physical MacBook display hosting persistent hardware chrome (camera notch
//  & macOS menu bar) over a 120fps GPU-accelerated macOS Spaces 3D depth-parallax deck,
//  ported 1:1 from Snapzy's `SnapzyOnboardingMockHost.swift`.
//

import SwiftUI

struct GravOnboardingMockHost: View {
    @ObservedObject var state: GravOnboardingState
    let store: AntigravityTelemetryStore
    let preferences: PreferencesStore
    @Environment(\.accessibilityReduceMotion) private var envReduceMotion

    @State private var activeSpaceIndex: CGFloat
    @State private var settledSpaceIndex: Int
    @State private var glideRange: ClosedRange<Int>?
    @State private var settleTask: Task<Void, Never>?

    init(
        state: GravOnboardingState,
        store: AntigravityTelemetryStore,
        preferences: PreferencesStore
    ) {
        self.state = state
        self.store = store
        self.preferences = preferences
        _activeSpaceIndex = State(initialValue: CGFloat(Self.spaceIndex(for: state.currentStep)))
        _settledSpaceIndex = State(initialValue: -1)
    }

    private var reduceMotion: Bool {
        GravMotionPreferences.shared.reduceMotion || envReduceMotion
    }

    private var currentSpaceInt: Int {
        Self.spaceIndex(for: state.currentStep)
    }

    private var currentMockApp: GravMockApp {
        switch state.currentStep {
        case .connect: .antigravity
        case .notchHud: .notchHud
        case .preferences: .settings
        }
    }

    private static func spaceIndex(for step: GravOnboardingStep) -> Int {
        switch step {
        case .connect: 0
        case .notchHud: 1
        case .preferences: 2
        }
    }

    private static let gutterColor = Color(red: 0.045, green: 0.050, blue: 0.065)

    private var viewportShape: GravUnevenRoundedRectangle {
        GravUnevenRoundedRectangle(
            cornerRadii: GravCornerRadii(
                topLeading: 18,
                bottomLeading: 0,
                bottomTrailing: GravOnboardingMetrics.windowRadius,
                topTrailing: 0
            )
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let stageWidth = max(1, proxy.size.width)

            ZStack(alignment: .top) {
                // Deep obsidian Spaces gutter visible cleanly between desktop cards mid-swipe
                Self.gutterColor

                // Persistent 3-Space macOS Desktop Deck: zero view-tree teardown on step switches,
                // pure GPU 120fps horizontal swipe with Mission Control depth recession & 4.8° yaw.
                spaceSlot(index: 0, stageWidth: stageWidth) {
                    GravMockConnectScene(state: state, store: store)
                }

                spaceSlot(index: 1, stageWidth: stageWidth) {
                    GravMockNotchScene(state: state)
                }

                spaceSlot(index: 2, stageWidth: stageWidth) {
                    GravMockPreferencesScene(state: state, preferences: preferences)
                }

                // Cropped real-scale macOS menu bar & shifted hardware notch stay anchored while
                // Desktop Spaces glide smoothly beneath them (camera notch hides cleanly on Step 2
                // so the interactive miniature MacBook Notch HUD takes center stage at y = 0).
                GravMockMenuBar(
                    app: currentMockApp,
                    showsCameraNotch: state.currentStep != .notchHud
                )
                .allowsHitTesting(false)

                // Authentic macOS Dark Glass Dock anchored cleanly at the bottom of the MacBook desktop
                VStack {
                    Spacer()
                    GravMockMacOSDock()
                        .padding(.bottom, 8)
                }
                .allowsHitTesting(false)

                // Interactive 1:1 MacBook Notch HUD rendered flush at y = 0 above the menu bar
                // and synchronized with Space 1's 3D glide.
                GravMockNotchOverlay(state: state)
                    .environment(
                        \.gravMockSceneIsLive,
                        currentSpaceInt == 1 || settledSpaceIndex == 1 || glideRange?.contains(1) == true
                    )
                    .allowsHitTesting(currentSpaceInt == 1)
                    .accessibilityHidden(currentSpaceInt != 1)
                    .offset(x: reduceMotion ? 0 : (1.0 - activeSpaceIndex) * (stageWidth + 28))
                    .opacity(max(0, 1.0 - Double(abs(1.0 - activeSpaceIndex) * 1.4)))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(viewportShape)
        .overlay(
            viewportShape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.24),
                        Color.white.opacity(0.09),
                        Color.white.opacity(0.02),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.75
            )
            .allowsHitTesting(false)
        )
        // Static shadow plate prevents recomputing shadow blur from gliding Spaces every frame
        .background(
            viewportShape
                .fill(Self.gutterColor)
                .shadow(color: Color.black.opacity(0.38), radius: 28, x: -6, y: 8)
                .shadow(color: Color.black.opacity(0.16), radius: 6, x: -2, y: 2)
        )
        .onAppear {
            activeSpaceIndex = CGFloat(currentSpaceInt)
            settle(on: currentSpaceInt, after: Self.entranceSettleDelay)
        }
        .onDisappear {
            settleTask?.cancel()
            state.isStageInFlight = false
        }
        .onChange(of: state.currentStep) { _, newStep in
            let target = CGFloat(Self.spaceIndex(for: newStep))
            let origin = Int(activeSpaceIndex.rounded())
            glideRange = min(origin, Int(target))...max(origin, Int(target))
            let jump = abs(target - activeSpaceIndex)
            let duration: Double
            if reduceMotion {
                duration = 0.22
                withAnimation(.easeInOut(duration: duration)) {
                    activeSpaceIndex = target
                }
            } else {
                duration = jump > 1.5 ? 0.80 : 0.64
                withAnimation(.timingCurve(0.20, 0.0, 0.10, 1.0, duration: duration)) {
                    activeSpaceIndex = target
                }
            }
            settle(on: Int(target), after: duration)
        }
    }

    private static let entranceSettleDelay: Double = 0.95

    private func settle(on index: Int, after delay: Double) {
        settleTask?.cancel()
        settleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            settledSpaceIndex = index
            glideRange = nil
            state.isStageInFlight = false
        }
    }

    private func spaceSlot<Content: View>(
        index: Int,
        stageWidth: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(
                \.gravMockSceneIsLive,
                index == currentSpaceInt || index == settledSpaceIndex || glideRange?.contains(index) == true
            )
            .environment(
                \.gravMockSceneIsSettled,
                !state.isStageInFlight && index == currentSpaceInt && index == settledSpaceIndex
            )
            .allowsHitTesting(currentSpaceInt == index)
            .accessibilityHidden(currentSpaceInt != index)
            .modifier(
                MacOSSpacesParallaxModifier(
                    spaceIndex: CGFloat(index),
                    activeIndex: activeSpaceIndex,
                    stageWidth: stageWidth,
                    reduceMotion: reduceMotion
                )
            )
    }
}

// MARK: - macOS Spaces 3D Depth-Parallax Transform (Pure GPU 120fps)

private struct MacOSSpacesParallaxModifier: ViewModifier, Animatable {
    let spaceIndex: CGFloat
    var activeIndex: CGFloat
    let stageWidth: CGFloat
    let reduceMotion: Bool

    nonisolated var animatableData: CGFloat {
        get { activeIndex }
        set { activeIndex = newValue }
    }

    func body(content: Content) -> some View {
        let delta = spaceIndex - activeIndex
        let distance = abs(delta)
        let isOffscreen = !reduceMotion && distance >= 1.18
        let t: CGFloat = reduceMotion ? 0 : min(1.0, distance)
        let isMoving = !reduceMotion && !isOffscreen && distance > 0.0005

        // 28pt dark-glass macOS Spaces gutter between desktop cards
        let gutter: CGFloat = 28
        let offsetX: CGFloat = reduceMotion ? 0 : delta * (stageWidth + gutter)

        // Smooth Mission Control depth recession (`scale 1.0 → 0.935`) + 4.8° optical perspective yaw
        let scale: CGFloat = 1.0 - 0.065 * t
        let clampedDelta = max(-1.0, min(1.0, delta))
        let tiltDegrees: Double = reduceMotion ? 0 : Double(-clampedDelta) * 4.8

        // Continuous rounded corners emerge only while gliding in 3D space (0 → 14pt), then lock flush
        let cornerRadius: CGFloat = 14.0 * t
        let cardShape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        let dimOpacity = Double(t) * 0.24
        let rimOpacity = Double(t) * 0.22
        let cardOpacity: Double = reduceMotion
            ? max(0.0, 1.0 - Double(distance))
            : (isOffscreen ? 0.0 : 1.0)

        content
            .overlay {
                if dimOpacity > 0.004 && !isOffscreen {
                    Color.black.opacity(dimOpacity)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(cardShape)
            .overlay {
                if isMoving {
                    cardShape.strokeBorder(Color.white, lineWidth: 0.75)
                        .mask(
                            LinearGradient(
                                colors: [Color.white, Color.white.opacity(0.30)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .opacity(rimOpacity)
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(scale)
            .rotation3DEffect(
                .degrees(tiltDegrees),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.42
            )
            .offset(x: offsetX)
            .opacity(cardOpacity)
    }
}
