//
//  OnboardingWindowController.swift
//  Grav
//
//  Window controller hosting the borderless Dark Liquid Glass onboarding window and the
//  celebratory desktop finale flight straight into the MacBook notch,
//  ported 1:1 from Snapzy's `SnapzyOnboardingWindowController.swift`.
//

import AppKit
import SwiftUI

@MainActor
public final class OnboardingWindowController: NSObject, NSWindowDelegate {
    // MARK: - Public Callbacks

    /// Invoked once onboarding finishes or is dismissed.
    public var onComplete: (() -> Void)?

    /// Invoked at the exact instant the celebratory finale icon docks into the MacBook notch
    /// so `AppDelegate` can trigger `notchHUD?.triggerWelcomePeek()`.
    public var onTriggerNotchPeek: (() -> Void)?

    /// Optional provider returning the live MacBook notch center in global macOS screen coordinates
    /// (AppKit bottom-left origin). Falls back to top-center bezel of the active screen when nil/zero.
    public var notchTargetPointProvider: (() -> CGPoint)?

    // MARK: - Dependencies & State

    private let store: AntigravityTelemetryStore
    private let preferences: PreferencesStore

    private var window: NSWindow?
    private var finaleOverlay: OnboardingFinaleOverlayController?

    private var isPresenting = false
    private var isEnforcing = false
    private var didNotifyCompleteForCurrentSession = false

    public var isVisible: Bool { window?.isVisible ?? false }

    public init(store: AntigravityTelemetryStore, preferences: PreferencesStore) {
        self.store = store
        self.preferences = preferences
        super.init()
    }

    // MARK: - Public Lifecycle

    public func show(replay: Bool = false) {
        didNotifyCompleteForCurrentSession = false

        if replay {
            teardownImmediate()
        } else if let existing = window, existing.isVisible {
            activate()
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
            return
        }

        activate()

        let activeWindow = window ?? makeWindow(startAtWelcome: true)
        self.window = activeWindow

        let isFirstPresentation = !activeWindow.isVisible
        if isFirstPresentation {
            activeWindow.setFrame(Self.preferredFrame(), display: false)
            activeWindow.alphaValue = GravMotionPreferences.shared.reduceMotion ? 1 : 0
        }

        activeWindow.makeKeyAndOrderFront(nil)
        activeWindow.orderFrontRegardless()

        fitWithinScreen(activeWindow)

        if isFirstPresentation {
            presentAnimated(activeWindow)
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, let currentWindow = self.window else { return }
            currentWindow.makeKeyAndOrderFront(nil)
            self.activate()
        }
    }

    public func close() {
        close(launchIconWindowFrame: nil)
    }

    private func close(launchIconWindowFrame: CGRect?) {
        guard let activeWindow = window else { return }
        if let launchIconWindowFrame {
            dismissWithFinale(activeWindow, iconWindowFrame: launchIconWindowFrame)
        } else {
            dismissAnimated(activeWindow)
        }
    }

    private func teardownImmediate() {
        finaleOverlay?.teardown()
        finaleOverlay = nil
        if let existing = window {
            existing.delegate = nil
            existing.orderOut(nil)
            existing.close()
            window = nil
        }
    }

    // MARK: - Geometry & Clamping

    private static func visibleFrame(of screen: NSScreen?) -> NSRect {
        (screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private static func sizeLimits(on screen: NSScreen?) -> (min: NSSize, max: NSSize) {
        let visible = visibleFrame(of: screen)
        let inset = GravOnboardingMetrics.screenMargin * 2
        let ceiling = NSSize(
            width: min(GravOnboardingMetrics.maxSize.width, max(visible.width - inset, 1)),
            height: min(GravOnboardingMetrics.maxSize.height, max(visible.height - inset, 1))
        )
        let floor = NSSize(
            width: min(GravOnboardingMetrics.minSize.width, ceiling.width),
            height: min(GravOnboardingMetrics.minSize.height, ceiling.height)
        )
        return (floor, ceiling)
    }

    private static func preferredFrame(on screen: NSScreen? = nil) -> NSRect {
        let visible = visibleFrame(of: screen)
        let limits = sizeLimits(on: screen)

        let size = NSSize(
            width: min(max(visible.width * GravOnboardingMetrics.screenFill, limits.min.width), limits.max.width),
            height: min(max(visible.height * GravOnboardingMetrics.screenFill, limits.min.height), limits.max.height)
        )

        return NSRect(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.midY - size.height / 2).rounded(),
            width: size.width.rounded(),
            height: size.height.rounded()
        )
    }

    private func clamped(_ size: NSSize, on screen: NSScreen?) -> NSSize {
        let limits = Self.sizeLimits(on: screen)
        return NSSize(
            width: min(max(size.width, limits.min.width), limits.max.width),
            height: min(max(size.height, limits.min.height), limits.max.height)
        )
    }

    private func fitWithinScreen(_ window: NSWindow) {
        let size = clamped(window.frame.size, on: window.screen)
        guard size != window.frame.size else { return }
        let visible = Self.visibleFrame(of: window.screen)
        window.setFrame(
            NSRect(
                x: (visible.midX - size.width / 2).rounded(),
                y: (visible.midY - size.height / 2).rounded(),
                width: size.width,
                height: size.height
            ),
            display: true
        )
    }

    private func enforceSizeLimits(on window: NSWindow) {
        let size = clamped(window.frame.size, on: window.screen)
        guard size != window.frame.size else { return }

        var frame = window.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        window.setFrame(Self.nudgedOnScreen(frame, on: window.screen), display: true)
    }

    private static func nudgedOnScreen(_ frame: NSRect, on screen: NSScreen?) -> NSRect {
        let visible = visibleFrame(of: screen)
        var frame = frame
        frame.origin.x = min(max(frame.minX, visible.minX), max(visible.maxX - frame.width, visible.minX))
        frame.origin.y = min(max(frame.minY, visible.minY), max(visible.maxY - frame.height, visible.minY))
        return frame
    }

    // MARK: - Presentation & Animation

    private func presentAnimated(_ window: NSWindow) {
        guard !GravMotionPreferences.shared.reduceMotion else {
            window.alphaValue = 1
            return
        }

        let target = window.frame
        let start = clamped(
            NSSize(width: target.width * 0.98, height: target.height * 0.98),
            on: window.screen
        )
        isPresenting = true
        window.setFrame(
            NSRect(
                x: (target.midX - start.width / 2).rounded(),
                y: (target.midY - start.height / 2).rounded(),
                width: start.width,
                height: start.height
            ),
            display: false
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = GravMotionSpec.settle.duration
            context.timingFunction = GravMotionSpec.glide.timingFunction
            window.animator().alphaValue = 1
            window.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                window.alphaValue = 1
                window.setFrame(target, display: false)
                self?.isPresenting = false
            }
        }
    }

    private func dismissWithFinale(_ window: NSWindow, iconWindowFrame: CGRect) {
        let windowFrame = window.frame
        let startScreenCenter = CGPoint(
            x: windowFrame.minX + iconWindowFrame.midX,
            y: windowFrame.maxY - iconWindowFrame.midY
        )

        let providedTarget = notchTargetPointProvider?()
        let resolvedProvidedTarget: CGPoint? = if let pt = providedTarget, pt != .zero {
            pt
        } else {
            nil
        }

        let targetScreen = Self.screenContaining(point: resolvedProvidedTarget)
            ?? window.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first

        if let targetScreen {
            let screenFrame = targetScreen.frame
            let menuBarHeight = max(24, screenFrame.maxY - targetScreen.visibleFrame.maxY)
            let targetNotchCenter = resolvedProvidedTarget
                ?? CGPoint(x: screenFrame.midX, y: screenFrame.maxY - menuBarHeight * 0.5)

            let overlay = OnboardingFinaleOverlayController(
                screen: targetScreen,
                startScreenCenter: startScreenCenter,
                targetNotchCenter: targetNotchCenter,
                menuBarHeight: menuBarHeight,
                reduceMotion: GravMotionPreferences.shared.reduceMotion,
                onArrival: { [weak self] in
                    self?.onTriggerNotchPeek?()
                },
                onFinish: { [weak self] in
                    self?.finaleOverlay = nil
                }
            )
            self.finaleOverlay = overlay
            overlay.present()
        } else {
            onTriggerNotchPeek?()
        }

        notifyCompleteIfNeeded()

        // Dissolve the onboarding window cleanly right as the desktop overlay picks up the icon
        guard !GravMotionPreferences.shared.reduceMotion else {
            window.close()
            self.window = nil
            return
        }

        let endSize = NSSize(width: windowFrame.width * 0.975, height: windowFrame.height * 0.975)
        let endFrame = NSRect(
            x: (windowFrame.midX - endSize.width * 0.5).rounded(),
            y: (windowFrame.midY - endSize.height * 0.5).rounded(),
            width: endSize.width.rounded(),
            height: endSize.height.rounded()
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            window.animator().alphaValue = 0
            window.animator().setFrame(endFrame, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                window.close()
                window.alphaValue = 1
                self?.window = nil
            }
        }
    }

    private static func screenContaining(point: CGPoint?) -> NSScreen? {
        guard let point else { return nil }
        return NSScreen.screens.first { $0.frame.contains(point) }
    }

    private func dismissAnimated(_ window: NSWindow) {
        notifyCompleteIfNeeded()

        guard !GravMotionPreferences.shared.reduceMotion else {
            window.close()
            self.window = nil
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = GravMotionSpec.contentOut.duration + 0.06
            context.timingFunction = GravMotionSpec.contentOut.timingFunction
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                window.close()
                window.alphaValue = 1
                self?.window = nil
            }
        }
    }

    private func notifyCompleteIfNeeded() {
        guard !didNotifyCompleteForCurrentSession else { return }
        didNotifyCompleteForCurrentSession = true
        onComplete?()
    }

    // MARK: - Window Construction

    private func activate() {
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow(startAtWelcome: Bool) -> NSWindow {
        let created = GravOnboardingPanel(
            contentRect: Self.preferredFrame(),
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        created.title = "Welcome to Grav"
        created.delegate = self
        created.isReleasedWhenClosed = false
        created.level = .normal
        created.collectionBehavior = [.fullScreenAuxiliary]
        fitWithinScreen(created)

        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = true
        created.isMovableByWindowBackground = true
        created.appearance = NSAppearance(named: .darkAqua)

        let hosting = NSHostingView(
            rootView: GravOnboardingView(
                store: store,
                preferences: preferences,
                startAtWelcome: startAtWelcome,
                onDismiss: { [weak self] launchIconWindowFrame in
                    self?.close(launchIconWindowFrame: launchIconWindowFrame)
                }
            )
        )
        hosting.sizingOptions = [.minSize, .maxSize]

        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = GravOnboardingMetrics.windowRadius
        hosting.layer?.cornerCurve = .continuous
        hosting.layer?.masksToBounds = true
        hosting.layer?.drawsAsynchronously = true

        created.contentView = hosting
        return created
    }

    // MARK: - NSWindowDelegate

    public func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        clamped(frameSize, on: sender.screen)
    }

    public func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        enforceSizeLimits(on: window)
    }

    public func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              !isPresenting, !isEnforcing, !window.inLiveResize else { return }
        isEnforcing = true
        Task { @MainActor [weak self] in
            self?.enforceSizeLimits(on: window)
            self?.isEnforcing = false
        }
    }

    public func windowDidChangeScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        fitWithinScreen(window)
    }

    public func windowWillClose(_ notification: Notification) {
        _ = notification
        self.window = nil
        notifyCompleteIfNeeded()
    }
}

private final class GravOnboardingPanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Celebratory Desktop Finale (Notch Ascent & Dark Liquid Glass Arrival Pill)

@MainActor
private final class OnboardingFinaleOverlayController {
    private var panel: NSPanel?
    private let screen: NSScreen
    private let startScreenCenter: CGPoint
    private let targetNotchCenter: CGPoint
    private let menuBarHeight: CGFloat
    private let reduceMotion: Bool
    private let onArrival: () -> Void
    private let onFinish: () -> Void

    init(
        screen: NSScreen,
        startScreenCenter: CGPoint,
        targetNotchCenter: CGPoint,
        menuBarHeight: CGFloat,
        reduceMotion: Bool,
        onArrival: @escaping () -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.screen = screen
        self.startScreenCenter = startScreenCenter
        self.targetNotchCenter = targetNotchCenter
        self.menuBarHeight = menuBarHeight
        self.reduceMotion = reduceMotion
        self.onArrival = onArrival
        self.onFinish = onFinish
    }

    func present() {
        let screenFrame = screen.frame
        let startLocal = CGPoint(
            x: startScreenCenter.x - screenFrame.minX,
            y: screenFrame.maxY - startScreenCenter.y
        )
        let targetLocal = CGPoint(
            x: targetNotchCenter.x - screenFrame.minX,
            y: screenFrame.maxY - targetNotchCenter.y
        )

        let overlayPanel = OnboardingFinalePanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        overlayPanel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        overlayPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        overlayPanel.isOpaque = false
        overlayPanel.backgroundColor = .clear
        overlayPanel.hasShadow = false
        overlayPanel.ignoresMouseEvents = true
        overlayPanel.isReleasedWhenClosed = false
        overlayPanel.appearance = NSAppearance(named: .darkAqua)

        let hosting = NSHostingView(
            rootView: OnboardingFinaleOverlayView(
                screenSize: screenFrame.size,
                startPoint: startLocal,
                targetPoint: targetLocal,
                menuBarHeight: menuBarHeight,
                reduceMotion: reduceMotion,
                onArrival: onArrival
            ) { [weak self] in
                self?.teardown()
            }
        )
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.drawsAsynchronously = true
        overlayPanel.contentView = hosting

        overlayPanel.orderFrontRegardless()
        self.panel = overlayPanel
    }

    func teardown() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        onFinish()
    }
}

private final class OnboardingFinalePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct OnboardingFinaleOverlayView: View {
    let screenSize: CGSize
    let startPoint: CGPoint
    let targetPoint: CGPoint
    let menuBarHeight: CGFloat
    let reduceMotion: Bool
    let onArrival: () -> Void
    let onComplete: () -> Void

    @State private var flightProgress: CGFloat = 0
    @State private var iconOpacity: Double = 1
    @State private var ripplePrimary: CGFloat = 0
    @State private var rippleEcho: CGFloat = 0
    @State private var pillVisible = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            // Dual crisp optical precision ripples on notch dock (54pt + 36pt)
            if !reduceMotion {
                dockRippleRing(progress: ripplePrimary, maxDiameter: 54, lineWidth: 1.25, peakOpacity: 0.72)
                    .position(targetPoint)

                dockRippleRing(progress: rippleEcho, maxDiameter: 36, lineWidth: 0.9, peakOpacity: 0.44)
                    .position(targetPoint)

                // Ascending Grav icon gliding across the real macOS desktop into the notch
                Color.clear
                    .modifier(FinaleIconFlightModifier(
                        progress: flightProgress,
                        startPoint: startPoint,
                        targetPoint: targetPoint
                    ))
                    .opacity(iconOpacity)
            }

            // Native macOS Dark Liquid Glass Arrival Pill centered cleanly beneath the notch
            notchArrivalPill
                .position(
                    x: min(max(screenSize.width * 0.5, 190), screenSize.width - 190),
                    y: menuBarHeight + 31
                )
                .opacity(pillVisible ? 1 : 0)
                .scaleEffect(reduceMotion ? 1.0 : (pillVisible ? 1.0 : 0.94))
                .offset(y: reduceMotion ? 0 : (pillVisible ? 0 : -10))
                .animation(
                    reduceMotion
                        ? .easeInOut(duration: 0.22)
                        : .spring(response: 0.42, dampingFraction: 0.82),
                    value: pillVisible
                )
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .environment(\.colorScheme, .dark)
        .task {
            await runChoreography()
        }
    }

    private func dockRippleRing(
        progress: CGFloat,
        maxDiameter: CGFloat,
        lineWidth: CGFloat,
        peakOpacity: Double
    ) -> some View {
        let clamped = max(0, min(1, progress))
        let diameter = 14 + (maxDiameter - 14) * clamped
        let opacity = clamped > 0.001 ? peakOpacity * Double(pow(1 - clamped, 1.5)) : 0
        return Circle()
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(opacity),
                        GravPalette.glacialCyan.opacity(opacity * 0.85),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: lineWidth
            )
            .frame(width: diameter, height: diameter)
    }

    private var notchArrivalPill: some View {
        let shape = Capsule(style: .continuous)
        return HStack(spacing: 10) {
            Image(nsImage: GravOnboardingIconCache.appIcon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .clipShape(Radius.rect(Radius.controlXS))

            HStack(spacing: 6) {
                Text("Grav")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.white)

                Text("·")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.36))

                Text("Live Telemetry Ready")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.76))
            }

            GravKeycapChip(label: "⌘,", emphasis: true)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(height: 40)
        .background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.black.opacity(0.36))
            }
        }
        .overlay {
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.24),
                        Color.white.opacity(0.07),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.5
            )
        }
        .shadow(color: Color.black.opacity(0.34), radius: 18, y: 8)
        .shadow(color: Color.black.opacity(0.16), radius: 4, y: 2)
        .fixedSize()
    }

    @MainActor
    private func runChoreography() async {
        if reduceMotion {
            onArrival()
            pillVisible = true
            try? await Task.sleep(for: .milliseconds(2100))
            pillVisible = false
            try? await Task.sleep(for: .milliseconds(260))
            onComplete()
            return
        }

        // Beat 1: Silky 120fps arc ascent from the onboarding window directly into the MacBook notch
        withAnimation(.timingCurve(0.22, 0.0, 0.10, 1.0, duration: 0.70)) {
            flightProgress = 1.0
        }

        // Beat 2 (670ms): Dock into the live MacBook notch with dual optical ripples + trigger peek
        try? await Task.sleep(for: .milliseconds(670))
        onArrival()
        withAnimation(.timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.58)) {
            ripplePrimary = 1.0
        }
        withAnimation(.easeOut(duration: 0.12)) {
            iconOpacity = 0
        }

        try? await Task.sleep(for: .milliseconds(65))
        withAnimation(.timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.52)) {
            rippleEcho = 1.0
        }

        // Beat 3: Native Dark Liquid Glass arrival pill drops directly beneath the notch
        pillVisible = true

        try? await Task.sleep(for: .milliseconds(2500))
        pillVisible = false

        try? await Task.sleep(for: .milliseconds(420))
        onComplete()
    }
}

/// Pure GPU 120fps curved ascent of the 60.5pt Grav app icon landing pixel-for-pixel onto the
/// 19pt left-side Grav logo inside the collapsed Notch pill.
private struct FinaleIconFlightModifier: ViewModifier, Animatable {
    var progress: CGFloat
    let startPoint: CGPoint
    let targetPoint: CGPoint

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let t = max(0, min(1, progress))
        let arc = sin(t * .pi)

        // Graceful zero-gravity curved ascent straight into the left-side Grav logo
        let x = startPoint.x + (targetPoint.x - startPoint.x) * t - 26 * arc
        let y = startPoint.y + (targetPoint.y - startPoint.y) * t - 28 * arc

        let startSize: CGFloat = 60.5
        let endSize: CGFloat = 19.0
        let currentSize = startSize + (endSize - startSize) * t

        let startRadius: CGFloat = Radius.card * 1.08
        let endRadius: CGFloat = 19.0 * 0.225
        let currentRadius = startRadius + (endRadius - startRadius) * t
        let shape = RoundedRectangle(cornerRadius: currentRadius, style: .continuous)

        Image(nsImage: GravOnboardingIconCache.appIcon)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: currentSize, height: currentSize)
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.28),
                            Color.white.opacity(0.06),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
            )
            .shadow(
                color: Color.black.opacity(0.34 * (1.0 - Double(t) * 0.85)),
                radius: 14,
                y: 7
            )
            .position(x: x, y: y)
    }
}
