import AppKit
import SwiftUI

/// `@MainActor` controller managing Grav's borderless, resizable, dark-locked floating
/// Onboarding `NSWindow`, keyboard navigation (`ESC` / `Return`), and the Grand Completion Finale
/// flight directly into the live MacBook notch.
@MainActor
public final class OnboardingWindowController: NSObject, NSWindowDelegate {
    // MARK: - Window Geometry Constants (Snapzy Parity)

    public static let minWindowSize = NSSize(width: 1060, height: 720)
    public static let maxWindowSize = NSSize(width: 1280, height: 826)
    public static let screenMargin: CGFloat = 16
    public static let screenFillRatio: CGFloat = 0.92

    // MARK: - Public Callbacks

    /// Invoked once onboarding finishes or is dismissed.
    public var onComplete: (() -> Void)?

    /// Invoked at the exact instant the Grand Finale icon docks into the MacBook notch
    /// so the app delegate can trigger `presenter.peek()`.
    public var onTriggerNotchPeek: (() -> Void)?

    /// Optional provider returning the live MacBook notch center in global macOS screen coordinates
    /// (AppKit bottom-left origin). When nil, defaults to the top-center bezel of the active screen.
    public var notchTargetPointProvider: (() -> CGPoint)?

    // MARK: - Dependencies & State

    private let store: AntigravityTelemetryStore
    private let preferences: PreferencesStore
    private let flowModel = OnboardingFlowModel()

    private var window: OnboardingFloatingWindow?
    private var keyMonitor: Any?
    private var finaleOverlay: OnboardingFinaleOverlay?
    private var isCompletingFinale = false

    public var isVisible: Bool {
        window?.isVisible ?? false
    }

    public init(store: AntigravityTelemetryStore, preferences: PreferencesStore) {
        self.store = store
        self.preferences = preferences
        super.init()

        flowModel.onRequestSkipOrClose = { [weak self] in
            self?.dismissWithoutFinale()
        }
        flowModel.onRequestGrandFinale = { [weak self] logoCenterInWindow in
            self?.launchGrandFinale(fromWindowLocalPoint: logoCenterInWindow)
        }
    }

    // MARK: - Presentation Lifecycle

    /// Presents the Grav Welcome & Onboarding window.
    /// - Parameter replay: When `true`, resets cleanly to Beat 1 of the Welcome choreography even if previously completed.
    public func show(replay: Bool = false) {
        isCompletingFinale = false
        finaleOverlay?.close()
        finaleOverlay = nil

        if let existing = window, existing.isVisible, !replay {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        // Tear down any previous instance cleanly before re-presenting
        teardownWindow()

        flowModel.reset(startAtWelcome: true)
        store.refreshConnectionStatus()

        let screen = targetScreen()
        let initialFrame = Self.computeInitialFrame(for: screen)

        let onboardingWindow = OnboardingFloatingWindow(
            contentRect: initialFrame,
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        onboardingWindow.setFrame(initialFrame, display: false)
        onboardingWindow.minSize = Self.minWindowSize
        onboardingWindow.maxSize = Self.maxWindowSize
        onboardingWindow.isOpaque = false
        onboardingWindow.backgroundColor = .clear
        onboardingWindow.hasShadow = true
        onboardingWindow.isMovableByWindowBackground = true
        onboardingWindow.level = .floating
        onboardingWindow.appearance = NSAppearance(named: .darkAqua)
        onboardingWindow.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        onboardingWindow.isReleasedWhenClosed = false
        onboardingWindow.delegate = self

        let rootView = OnboardingRootView(
            store: store,
            preferences: preferences,
            model: flowModel
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = CGRect(origin: .zero, size: initialFrame.size)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        onboardingWindow.contentView = hostingView
        onboardingWindow.alphaValue = 0

        self.window = onboardingWindow
        installKeyMonitor()

        onboardingWindow.makeKeyAndOrderFront(nil)
        NSApp.activate()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            onboardingWindow.animator().alphaValue = 1.0
        }
    }

    /// Closes the onboarding window immediately and cleans up local keyboard monitors.
    public func close() {
        teardownWindow()
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        removeKeyMonitor()
    }

    // MARK: - Geometry Computation

    /// Computes initial window frame: 92% of the visible screen frame clamped to `[1060x720, 1280x826]`
    /// with a `16pt` screen safety margin, centered on the screen.
    public static func computeInitialFrame(for screen: NSScreen?) -> NSRect {
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxAvailableWidth = max(minWindowSize.width, visible.width - screenMargin * 2)
        let maxAvailableHeight = max(minWindowSize.height, visible.height - screenMargin * 2)

        let rawWidth = visible.width * screenFillRatio
        let rawHeight = visible.height * screenFillRatio

        let width = min(max(rawWidth, minWindowSize.width), min(maxWindowSize.width, maxAvailableWidth))
        let height = min(max(rawHeight, minWindowSize.height), min(maxWindowSize.height, maxAvailableHeight))

        let originX = floor(visible.midX - width * 0.5)
        let originY = floor(visible.midY - height * 0.5)

        return NSRect(x: originX, y: originY, width: floor(width), height: floor(height))
    }

    // MARK: - Dismissal & Grand Completion Finale

    private func dismissWithoutFinale() {
        guard !isCompletingFinale else { return }
        preferences.hasCompletedOnboarding = true

        guard let activeWindow = window else {
            onComplete?()
            return
        }

        removeKeyMonitor()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            activeWindow.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.teardownWindow()
                self.onComplete?()
            }
        })
    }

    private func launchGrandFinale(fromWindowLocalPoint localPoint: CGPoint) {
        guard !isCompletingFinale else { return }
        isCompletingFinale = true
        preferences.hasCompletedOnboarding = true
        removeKeyMonitor()

        guard let activeWindow = window else {
            onTriggerNotchPeek?()
            onComplete?()
            return
        }

        // Convert SwiftUI top-left window point into global AppKit screen coordinates
        let contentBounds = activeWindow.contentView?.bounds ?? activeWindow.contentLayoutRect
        let windowPoint = NSPoint(
            x: localPoint.x,
            y: contentBounds.height - localPoint.y
        )
        let startScreenPoint = activeWindow.convertPoint(toScreen: windowPoint)

        let targetScreen = activeWindow.screen ?? targetScreen()
        let fallbackTarget = CGPoint(
            x: (targetScreen?.frame.midX ?? startScreenPoint.x),
            y: (targetScreen?.frame.maxY ?? startScreenPoint.y) - 18
        )
        let targetScreenPoint = notchTargetPointProvider?() ?? fallbackTarget

        // Launch full-screen .screenSaver overlay before fading the onboarding window away
        let overlay = OnboardingFinaleOverlay()
        self.finaleOverlay = overlay
        overlay.launch(
            from: startScreenPoint,
            to: targetScreenPoint,
            on: targetScreen,
            onArrival: { [weak self] in
                self?.onTriggerNotchPeek?()
            },
            onFinished: { [weak self] in
                guard let self else { return }
                self.finaleOverlay = nil
                self.isCompletingFinale = false
                self.onComplete?()
            }
        )

        // Smoothly exhale & close the onboarding window underneath the flying icon
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            activeWindow.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.teardownWindow()
            }
        })
    }

    // MARK: - Keyboard Handling (`ESC` & `Return`)

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let keyCode = event.keyCode
            let hasBlockingModifiers = !event.modifierFlags
                .intersection([.command, .option, .control])
                .isEmpty
            let windowNumber = event.windowNumber

            let shouldConsume = MainActor.assumeIsolated {
                self.handleKeyDown(
                    keyCode: keyCode,
                    hasBlockingModifiers: hasBlockingModifiers,
                    windowNumber: windowNumber
                )
            }
            return shouldConsume ? nil : event
        }
    }

    private func handleKeyDown(
        keyCode: UInt16,
        hasBlockingModifiers: Bool,
        windowNumber: Int
    ) -> Bool {
        guard let activeWindow = window,
              activeWindow.isVisible,
              activeWindow.windowNumber == windowNumber,
              !hasBlockingModifiers
        else {
            return false
        }

        switch keyCode {
        case 53: // ESC
            flowModel.handleEscape()
            return true
        case 36, 76: // Return / Keypad Enter
            flowModel.handleReturn()
            return true
        default:
            return false
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func teardownWindow() {
        removeKeyMonitor()
        window?.delegate = nil
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
    }

    private func targetScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}

/// Custom borderless `NSWindow` subclass permitting key & main status for crisp keyboard navigation.
private final class OnboardingFloatingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
