import AppKit
import SwiftUI

/// Borderless, transparent, click-through full-screen `NSWindow` overlay (`.screenSaver` level)
/// that launches `GravAppIconTile` from the onboarding window's docked icon coordinates along a
/// 120fps curved `C∞` cubic Bezier arc across the live macOS desktop directly into the MacBook notch,
/// emits a crisp dual `1pt` optical hairline ripple ring, invokes `onArrival()`, and cleanly closes itself.
@MainActor
public final class OnboardingFinaleOverlay {
    private var overlayWindow: NSWindow?
    private var activeSelf: OnboardingFinaleOverlay?

    public init() {}

    /// Launches the full-screen finale flight in global macOS screen coordinates (AppKit bottom-left origin).
    /// - Parameters:
    ///   - startScreenPoint: Screen coordinate of the `26x26` docked onboarding header icon.
    ///   - targetScreenPoint: Screen coordinate of the live MacBook notch center.
    ///   - screen: Optional target `NSScreen`; falls back to the screen containing `targetScreenPoint` or `NSScreen.main`.
    ///   - onArrival: Invoked the exact instant the icon arrives in the notch (triggers `presenter.peek()`).
    ///   - onFinished: Invoked after the dual optical ripple completes and the overlay closes.
    public func launch(
        from startScreenPoint: CGPoint,
        to targetScreenPoint: CGPoint,
        on screen: NSScreen? = nil,
        onArrival: @escaping @MainActor () -> Void,
        onFinished: (@MainActor () -> Void)? = nil
    ) {
        close()

        let resolvedScreen = screen
            ?? NSScreen.screens.first(where: { $0.frame.contains(targetScreenPoint) })
            ?? NSScreen.screens.first(where: { $0.frame.contains(startScreenPoint) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let targetScreen = resolvedScreen else {
            onArrival()
            onFinished?()
            return
        }

        let screenFrame = targetScreen.frame
        let localStart = CGPoint(
            x: startScreenPoint.x - screenFrame.minX,
            y: screenFrame.maxY - startScreenPoint.y
        )
        let localTarget = CGPoint(
            x: targetScreenPoint.x - screenFrame.minX,
            y: screenFrame.maxY - targetScreenPoint.y
        )

        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: targetScreen
        )
        window.setFrame(screenFrame, display: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false

        activeSelf = self
        overlayWindow = window

        let rootView = OnboardingFinaleOverlayView(
            startPoint: localStart,
            targetPoint: localTarget,
            onArrival: {
                onArrival()
            },
            onComplete: { [weak self] in
                self?.close()
                onFinished?()
            }
        )

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = CGRect(origin: .zero, size: screenFrame.size)
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        window.orderFrontRegardless()
    }

    public func close() {
        overlayWindow?.orderOut(nil)
        overlayWindow?.contentView = nil
        overlayWindow = nil
        activeSelf = nil
    }
}

private struct OnboardingFinaleOverlayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let startPoint: CGPoint
    let targetPoint: CGPoint
    let onArrival: () -> Void
    let onComplete: () -> Void

    @State private var launchDate = Date()
    @State private var rippleTriggerID = 0
    @State private var hasFiredArrival = false
    @State private var hasFinished = false

    private static let flightDuration: TimeInterval = 0.74
    private static let reducedDuration: TimeInterval = 0.24
    private static let rippleSettleDuration: TimeInterval = 0.82

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 120.0)) { timeline in
            let duration = reduceMotion ? Self.reducedDuration : Self.flightDuration
            let elapsed = max(0, timeline.date.timeIntervalSince(launchDate))
            let rawT = min(1.0, elapsed / duration)
            let u = CubicBezierArc.smoothStep(CGFloat(rawT))

            let arc = buildNotchArc(from: startPoint, to: targetPoint)
            let position = reduceMotion
                ? CGPoint(
                    x: startPoint.x + (targetPoint.x - startPoint.x) * u,
                    y: startPoint.y + (targetPoint.y - startPoint.y) * u
                )
                : arc.point(at: u)

            // Icon briefly lifts in optical presence mid-arc, then tucks cleanly into the notch bezel
            let midLift = sin(u * .pi)
            let iconSize: CGFloat = 26 + (reduceMotion ? 0 : midLift * 8) - (u > 0.78 ? ((u - 0.78) / 0.22) * 8 : 0)
            let iconOpacity: Double = rawT >= 0.96 ? Double(max(0, (1 - rawT) / 0.04)) : 1.0
            let shadowRadius: CGFloat = reduceMotion ? 4 : (8 + midLift * 14)

            ZStack {
                // Crisp dual 1pt optical hairline ripple ring at the live MacBook notch
                OnboardingOpticalRing(
                    triggerID: rippleTriggerID,
                    baseSize: 28,
                    maxScale: 4.4,
                    tint: GravPalette.glacialTeal,
                    isDual: true
                )
                .position(targetPoint)

                // Flying GravAppIconTile with restrained glacial halo along the Bezier trajectory
                if iconOpacity > 0.001 {
                    ZStack {
                        if !reduceMotion {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            GravPalette.glacialCyan.opacity(0.32 * Double(midLift)),
                                            GravPalette.glacialTeal.opacity(0.14 * Double(midLift)),
                                            Color.clear,
                                        ],
                                        center: .center,
                                        startRadius: 2,
                                        endRadius: iconSize * 1.15
                                    )
                                )
                                .frame(width: iconSize * 2.3, height: iconSize * 2.3)
                        }

                        GravAppIconTile(size: max(16, iconSize))
                            .shadow(color: GravPalette.obsidianVoid.opacity(0.55), radius: shadowRadius, y: 4)
                    }
                    .opacity(iconOpacity)
                    .position(position)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .task {
            launchDate = Date()
            let duration = reduceMotion ? Self.reducedDuration : Self.flightDuration

            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, !hasFiredArrival else { return }
            hasFiredArrival = true
            rippleTriggerID += 1
            onArrival()

            let settle = reduceMotion ? 0.34 : Self.rippleSettleDuration
            try? await Task.sleep(for: .seconds(settle))
            guard !Task.isCancelled, !hasFinished else { return }
            hasFinished = true
            onComplete()
        }
    }

    private func buildNotchArc(from start: CGPoint, to end: CGPoint) -> CubicBezierArc {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        let arcSweep = min(140, max(54, distance * 0.20))

        // Sweep smoothly outward and upward so the icon arcs gracefully into the top center notch
        let c1 = CGPoint(
            x: start.x + dx * 0.18,
            y: start.y - arcSweep
        )
        let c2 = CGPoint(
            x: end.x - dx * 0.16,
            y: end.y + min(96, max(28, abs(dy) * 0.28))
        )
        return CubicBezierArc(start: start, control1: c1, control2: c2, end: end)
    }
}
