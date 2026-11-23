import AppKit
import Foundation
import NotchKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Coordinates Grav's NotchKit 1.3.0 interactive HUD lifecycle, display-adaptive geometry,
/// `PreferencesStore` synchronization, and telemetry-driven peeks.
@MainActor
@Observable
public final class NotchHUDCoordinator {
    // MARK: - Constants

    public static let expandedPanelSize = CGSize(width: 564, height: 324)
    public static let notchedCollapsedReserve: CGFloat = 112
    public static let standaloneCollapsedWidth: CGFloat = 280

    // MARK: - Dependencies & State

    public let presenter: NotchPresenter
    public let store: AntigravityTelemetryStore
    public let preferences: PreferencesStore

    /// Invoked when the user clicks the quick Settings gear inside the expanded HUD header.
    public var onOpenSettings: (() -> Void)?

    public private(set) var isInstalled: Bool = false

    @ObservationIgnored private var isObservingPreferences: Bool = false
    @ObservationIgnored private var lastTrackedPinnedState: Bool = false
    @ObservationIgnored private var lastTelemetryPeekAt: Date = .distantPast
    @ObservationIgnored private var accessibilityObserver: NSObjectProtocol?
    @ObservationIgnored private var spotlightObserver: NSObjectProtocol?
    @ObservationIgnored private var trayObserver: NSObjectProtocol?
    @ObservationIgnored private var globalMouseDownMonitor: Any?
    @ObservationIgnored private var globalDragMonitor: Any?
    @ObservationIgnored private var globalMouseUpMonitor: Any?
    @ObservationIgnored private var localDragMonitor: Any?
    @ObservationIgnored private var dragMouseDownChangeCount: Int = -1
    @ObservationIgnored private var lastObservedDragChangeCount: Int = -1
    @ObservationIgnored private var isMouseDragging: Bool = false
    @ObservationIgnored private var isContentDragging: Bool = false
    @ObservationIgnored private var hasEnteredNotchRegion: Bool = false
    @ObservationIgnored private var openedByDragDetector: Bool = false
    @ObservationIgnored private var cachedDragHasImage: Bool = false
    @ObservationIgnored private var cachedDragItemCount: Int = 0
    @ObservationIgnored private var dragAutoCollapsePauseActive: Bool = false
    @ObservationIgnored private var dragExitDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var dragCleanupTask: Task<Void, Never>?

    // MARK: - Init

    public init(
        store: AntigravityTelemetryStore,
        preferences: PreferencesStore,
        preferredScreenID: String? = nil,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.store = store
        self.preferences = preferences
        self.onOpenSettings = onOpenSettings
        self.lastTrackedPinnedState = preferences.isNotchPinned

        let gravMotion = Self.makeNotchMotion()
        let initialPresenter = NotchPresenter(
            configuration: Self.makeConfiguration(
                hasPhysicalNotch: true,
                hoverToExpand: preferences.hoverToExpand,
                isPinned: preferences.isNotchPinned,
                hoverOpenDelay: preferences.hoverOpenDelay,
                hapticsEnabled: preferences.hapticsEnabled
            ),
            motion: .resolved(gravMotion),
            style: .standard,
            preferredScreenID: preferredScreenID
        )
        initialPresenter.configuration = Self.makeConfiguration(
            hasPhysicalNotch: initialPresenter.geometry.hasPhysicalNotch,
            hoverToExpand: preferences.hoverToExpand,
            isPinned: preferences.isNotchPinned,
            hoverOpenDelay: preferences.hoverOpenDelay,
            hapticsEnabled: preferences.hapticsEnabled
        )
        self.presenter = initialPresenter
    }

    // MARK: - Lifecycle

    /// Installs the collapsed and expanded Notch HUD views and wires live telemetry & preference sync.
    public func install() {
        guard !isInstalled else { return }

        syncPreferences()
        startAccessibilityObserver()
        startPreferenceObservation()
        wireTelemetryPeeks()

        let storeRef = store
        let presenterRef = presenter
        let preferencesRef = preferences

        presenter.install {
            CollapsedNotchView(
                store: storeRef,
                presenter: presenterRef,
                preferences: preferencesRef
            )
        } expanded: { [weak self] in
            ExpandedNotchView(
                store: storeRef,
                preferences: preferencesRef,
                onCollapse: { [weak self] in
                    self?.collapseFromUserAction()
                },
                onOpenSettings: { [weak self] in
                    self?.onOpenSettings?()
                }
            )
        }

        isInstalled = true
        syncPreferences()
        startSpotlightObserver()
        startGlobalDragMonitor()

        if preferences.isNotchPinned {
            presenter.expand(reason: .programmatic)
        }
    }

    private func startSpotlightObserver() {
        if let spotlightObserver {
            NotificationCenter.default.removeObserver(spotlightObserver)
        }
        spotlightObserver = NotificationCenter.default.addObserver(
            forName: .gravOpenNotchProfile,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.presenter.phase != .expanded {
                    self.presenter.expand(reason: .programmatic)
                    try? await Task.sleep(for: .milliseconds(80))
                    NotificationCenter.default.post(name: .gravOpenNotchProfile, object: self)
                }
            }
        }

        if let trayObserver {
            NotificationCenter.default.removeObserver(trayObserver)
        }
        trayObserver = NotificationCenter.default.addObserver(
            forName: .gravOpenNotchTray,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.presenter.phase != .expanded {
                    self.presenter.expand(reason: .programmatic)
                    try? await Task.sleep(for: .milliseconds(80))
                    NotificationCenter.default.post(name: .gravOpenNotchTray, object: self)
                }
            }
        }
    }

    /// Tears down the Notch HUD panel and detaches all observers.
    public func uninstall() {
        guard isInstalled else { return }

        isObservingPreferences = false
        store.onPeekRequested = nil

        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
            self.accessibilityObserver = nil
        }
        if let spotlightObserver {
            NotificationCenter.default.removeObserver(spotlightObserver)
            self.spotlightObserver = nil
        }
        if let trayObserver {
            NotificationCenter.default.removeObserver(trayObserver)
            self.trayObserver = nil
        }
        stopGlobalDragMonitor()

        presenter.uninstall()
        isInstalled = false
    }

    // MARK: - Controls

    /// Toggles the Notch HUD between collapsed and expanded states.
    public func toggle() {
        if !isInstalled {
            install()
        }
        if presenter.phase == .expanded && preferences.isNotchPinned {
            preferences.isNotchPinned = false
            syncPreferences()
        }
        presenter.toggle()
    }

    /// Explicitly expands the Notch HUD.
    public func expand(reason: NotchExpandReason = .programmatic) {
        if !isInstalled {
            install()
        }
        presenter.expand(reason: reason)
    }

    /// Explicitly collapses the Notch HUD.
    public func collapse() {
        presenter.collapse()
    }

    /// Triggers a welcoming subtle notch peek (used upon onboarding completion finale).
    public func triggerWelcomePeek() {
        if !isInstalled {
            install()
        }
        presenter.peek()
    }

    /// Returns the exact AppKit screen-space center of the left-side Grav app logo inside
    /// the collapsed Notch pill so the onboarding completion finale docks pixel-for-pixel onto it.
    public func notchTargetScreenPoint() -> CGPoint {
        presenter.refreshPlacement()
        let geometry = presenter.geometry
        let hasPhysicalNotch = geometry.hasPhysicalNotch
        let pillWidth = presenter.collapsedSurfaceWidth > 0
            ? presenter.collapsedSurfaceWidth
            : (hasPhysicalNotch ? (geometry.notchWidth + Self.notchedCollapsedReserve * 2) : Self.standaloneCollapsedWidth)
        let logoInsetFromPillLeft: CGFloat = hasPhysicalNotch ? (11.0 + 9.0) : (12.0 + 9.5)

        if geometry.screenFrame != .zero {
            let centerX = geometry.notchRect.midX
            let pillLeftX = centerX - (pillWidth * 0.5)
            let logoCenterX = pillLeftX + logoInsetFromPillLeft
            let logoCenterY = geometry.screenFrame.maxY - (geometry.collapsedHeight * 0.5)
            return CGPoint(x: logoCenterX, y: logoCenterY)
        }
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let pillLeftX = screen.frame.midX - (Self.standaloneCollapsedWidth * 0.5)
            return CGPoint(
                x: pillLeftX + 21.5,
                y: screen.frame.maxY - (NotchGeometry.simulatedNotchHeight * 0.5)
            )
        }
        return .zero
    }

    /// Reconciles `NotchPresenter.configuration` with current `PreferencesStore` and display geometry.
    public func syncPreferences() {
        let updated = Self.makeConfiguration(
            hasPhysicalNotch: presenter.geometry.hasPhysicalNotch,
            hoverToExpand: preferences.hoverToExpand,
            isPinned: preferences.isNotchPinned || dragAutoCollapsePauseActive,
            hoverOpenDelay: preferences.hoverOpenDelay,
            hapticsEnabled: preferences.hapticsEnabled
        )

        if presenter.configuration != updated {
            presenter.configuration = updated
        }

        let pinnedNow = preferences.isNotchPinned
        if pinnedNow && !lastTrackedPinnedState && isInstalled && presenter.phase != .expanded {
            presenter.expand(reason: .programmatic)
        }
        lastTrackedPinnedState = pinnedNow
    }

    // MARK: - Private Wiring

    private func collapseFromUserAction() {
        if preferences.isNotchPinned {
            preferences.isNotchPinned = false
            syncPreferences()
        }
        presenter.collapse()
    }

    private func wireTelemetryPeeks() {
        store.onPeekRequested = { [weak self] event in
            self?.handlePeekRequest(event)
        }
    }

    private var isAntigravityBackgrounded: Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return true }
        let bundleID = (frontmost.bundleIdentifier ?? "").lowercased()
        let name = (frontmost.localizedName ?? "").lowercased()
        return !bundleID.contains("antigravity") && !name.contains("antigravity")
    }

    private func handlePeekRequest(_ event: NotchPeekEvent) {
        guard isInstalled else { return }

        if case .welcome = event {
            presenter.peek()
            return
        }

        guard !store.isPaused else { return }

        let now = Date()
        let backgrounded = isAntigravityBackgrounded

        switch event {
        case .needsInput:
            let shouldAutoExpand = preferences.autoExpandOnNeedsInput
                || (preferences.urgentAlertWhenBackgrounded && backgrounded)
            guard shouldAutoExpand || preferences.autoPeekOnEvents else { return }
            guard now.timeIntervalSince(lastTelemetryPeekAt) >= 1.2 else { return }
            lastTelemetryPeekAt = now
            if preferences.playSounds {
                GravOnboardingWelcomeAudio.shared.playStepComplete()
            }
            if shouldAutoExpand {
                presenter.expand(reason: .programmatic)
            } else if presenter.phase == .collapsed {
                presenter.peek()
            }
            return

        case .commandFailed:
            guard preferences.notifyOnFailure else { return }
            let urgentExpand = preferences.urgentAlertWhenBackgrounded && backgrounded
            guard urgentExpand || preferences.autoPeekOnEvents else { return }
            guard now.timeIntervalSince(lastTelemetryPeekAt) >= 1.2 else { return }
            lastTelemetryPeekAt = now
            if preferences.playSounds {
                GravOnboardingWelcomeAudio.shared.playShutterSnap()
            }
            if urgentExpand {
                presenter.expand(reason: .programmatic)
            } else if presenter.phase == .collapsed {
                presenter.peek()
            }
            return

        case .turnCompleted:
            guard preferences.notifyOnTurnCompleted, preferences.autoPeekOnEvents else { return }
            if preferences.smartAlertMinDurationSeconds > 0 {
                let dur = store.lastTurnDuration ?? 0
                if dur < preferences.smartAlertMinDurationSeconds {
                    return
                }
            }
            guard presenter.phase == .collapsed else { return }
            guard now.timeIntervalSince(lastTelemetryPeekAt) >= 1.2 else { return }
            lastTelemetryPeekAt = now
            if preferences.playSounds {
                GravOnboardingWelcomeAudio.shared.playChallengeComplete()
            }
            presenter.peek()
            return

        default:
            guard preferences.autoPeekOnEvents, presenter.phase == .collapsed else { return }
            guard now.timeIntervalSince(lastTelemetryPeekAt) >= 1.2 else { return }
            lastTelemetryPeekAt = now
            presenter.peek()
        }
    }

    private func startPreferenceObservation() {
        guard !isObservingPreferences else { return }
        isObservingPreferences = true
        observePreferencesAndGeometry()
    }

    private func observePreferencesAndGeometry() {
        guard isObservingPreferences else { return }
        withObservationTracking {
            _ = preferences.hoverToExpand
            _ = preferences.isNotchPinned
            _ = preferences.autoPeekOnEvents
            _ = preferences.hoverOpenDelay
            _ = preferences.hapticsEnabled
            _ = preferences.autoExpandOnNeedsInput
            _ = presenter.geometry.hasPhysicalNotch
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isObservingPreferences else { return }
                self.syncPreferences()
                self.observePreferencesAndGeometry()
            }
        }
    }

    private func startAccessibilityObserver() {
        guard accessibilityObserver == nil else { return }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.presenter.motion = .resolved(Self.makeNotchMotion())
            }
        }
    }

    // MARK: - Global Drag-to-Notch Detector (Modeled on boring.notch's DragDetector)

    private static let supportedDragTypes: Set<NSPasteboard.PasteboardType> = [
        .fileURL,
        .png,
        .tiff,
        NSPasteboard.PasteboardType(UTType.url.identifier),
        NSPasteboard.PasteboardType("NSFilenamesPboardType"),
        NSPasteboard.PasteboardType("public.image"),
        NSPasteboard.PasteboardType("public.jpeg"),
        NSPasteboard.PasteboardType("public.heic"),
        NSPasteboard.PasteboardType("org.webmproject.webp"),
        NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
        NSPasteboard.PasteboardType("com.apple.NSFilePromiseReceiver"),
    ]

    private static let imageDragExtensions: Set<String> = [
        "png", "jpg", "jpeg", "webp", "gif", "heic", "tiff", "bmp",
    ]

    private func startGlobalDragMonitor() {
        stopGlobalDragMonitor()

        // 1. Snapshot NSPasteboard(name: .drag).changeCount on every mouse-down (exact boring.notch pattern)
        //    so normal window drags / text highlights never false-trigger from a stale drag pasteboard.
        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleDragMouseDown()
            }
        }

        // 2. Track global drag movement & check intersection with the FULL expanded Notch region (564×324pt).
        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDragged]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleDragMouseMoved()
            }
        }

        // 3. Clean up drag session on global mouse-up (keeping Notch open if a drop landed).
        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseUp]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleDragMouseUp()
            }
        }

        // 4. Mirror locally so drags that enter our own window also settle cleanly on mouse-up.
        localDragMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                switch event.type {
                case .leftMouseDown: self?.handleDragMouseDown()
                case .leftMouseDragged: self?.handleDragMouseMoved()
                case .leftMouseUp: self?.handleDragMouseUp()
                default: break
                }
            }
            return event
        }
    }

    private func stopGlobalDragMonitor() {
        dragExitDebounceTask?.cancel()
        dragExitDebounceTask = nil
        dragCleanupTask?.cancel()
        dragCleanupTask = nil
        for monitor in [globalMouseDownMonitor, globalDragMonitor, globalMouseUpMonitor, localDragMonitor] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        globalMouseDownMonitor = nil
        globalDragMonitor = nil
        globalMouseUpMonitor = nil
        localDragMonitor = nil
        isMouseDragging = false
        isContentDragging = false
        hasEnteredNotchRegion = false
        openedByDragDetector = false
        dragAutoCollapsePauseActive = false
        let tray = NotchTrayStore.shared
        tray.isGlobalDragActive = false
        tray.isGlobalDragNearNotch = false
    }

    private func handleDragMouseDown() {
        let dragPB = NSPasteboard(name: .drag)
        dragMouseDownChangeCount = dragPB.changeCount
        isMouseDragging = true
        isContentDragging = false
        hasEnteredNotchRegion = false
    }

    private func handleDragMouseMoved() {
        guard isInstalled else { return }
        let tray = NotchTrayStore.shared
        let dragPB = NSPasteboard(name: .drag)
        let currentChangeCount = dragPB.changeCount

        // Detect new drag content (works both when mouseDown was observed AND when drag originated in a sandboxed app).
        let pasteboardAdvanced: Bool = {
            if isMouseDragging {
                return currentChangeCount != dragMouseDownChangeCount
            }
            return currentChangeCount != lastObservedDragChangeCount
        }()

        if pasteboardAdvanced && !isContentDragging {
            lastObservedDragChangeCount = currentChangeCount
            if inspectDragPasteboard(dragPB) {
                isMouseDragging = true
                isContentDragging = true
                dragCleanupTask?.cancel()
                tray.isGlobalDragActive = true
                tray.globalDragHasImage = cachedDragHasImage
                tray.globalDragItemCount = cachedDragItemCount
            }
        }

        guard isContentDragging else { return }

        // Exact boring.notch region geometry: the FULL expanded Notch footprint at top-center of screen!
        let notchRegion = expandedNotchDragCaptureRegion()
        guard notchRegion != .zero else { return }

        let mouse = NSEvent.mouseLocation
        let containsMouse = notchRegion.contains(mouse)

        if containsMouse && !hasEnteredNotchRegion {
            hasEnteredNotchRegion = true
            dragExitDebounceTask?.cancel()
            handleDragEnteredNotchRegion()
        } else if !containsMouse && hasEnteredNotchRegion {
            hasEnteredNotchRegion = false
            handleDragExitedNotchRegion()
        }
    }

    private func handleDragEnteredNotchRegion() {
        let tray = NotchTrayStore.shared
        tray.isGlobalDragNearNotch = true
        tray.isTrayOpenRequested = true

        if !dragAutoCollapsePauseActive {
            dragAutoCollapsePauseActive = true
            syncPreferences()
        }

        if preferences.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }

        if presenter.phase != .expanded {
            openedByDragDetector = true
            presenter.expand(reason: .programmatic)
        }
        NotificationCenter.default.post(name: .gravOpenNotchTray, object: self)
    }

    private func handleDragExitedNotchRegion() {
        let tray = NotchTrayStore.shared
        tray.isGlobalDragNearNotch = false
        tray.isDropTargeted = false

        // Smooth 480ms debounce just like boring.notch (`anyDropDebounceTask`) before collapsing.
        dragExitDebounceTask?.cancel()
        dragExitDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(480))
            guard !Task.isCancelled, let self else { return }
            let tray = NotchTrayStore.shared
            guard !self.hasEnteredNotchRegion,
                  !tray.isDropTargeted
            else { return }

            let justDropped = Date().timeIntervalSince(tray.lastDropCompletedAt) < 1.5
            if !justDropped && self.openedByDragDetector && !self.preferences.isNotchPinned {
                self.openedByDragDetector = false
                self.dragAutoCollapsePauseActive = false
                self.syncPreferences()
                self.presenter.collapse()
            }
        }
    }

    private func handleDragMouseUp() {
        let wasActive = isMouseDragging || isContentDragging || hasEnteredNotchRegion || dragAutoCollapsePauseActive
        isMouseDragging = false
        isContentDragging = false
        hasEnteredNotchRegion = false
        dragMouseDownChangeCount = -1

        guard wasActive else { return }

        dragCleanupTask?.cancel()
        dragCleanupTask = Task { @MainActor [weak self] in
            // Allow AppKit `performDragOperation` to finish cleanly before releasing drag state.
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled, let self else { return }
            let tray = NotchTrayStore.shared
            tray.isGlobalDragActive = false
            tray.isGlobalDragNearNotch = false
            tray.isDropTargeted = false

            if self.dragAutoCollapsePauseActive {
                self.dragAutoCollapsePauseActive = false
                self.syncPreferences()
            }

            let justDropped = Date().timeIntervalSince(tray.lastDropCompletedAt) < 1.5
            if justDropped {
                // Keep Notch open on the Drop Shelf + Composer so user can type or send immediately!
                self.openedByDragDetector = false
            } else if self.openedByDragDetector && !self.preferences.isNotchPinned {
                // User released mouse outside the Notch without dropping -> gracefully collapse.
                self.openedByDragDetector = false
                self.presenter.collapse()
            }
        }
    }

    /// Computes the top-center expanded Notch region (`564 × 324pt` + generous horizontal shoulder padding)
    /// on the Notch's display, matching `boring.notch`'s `setupDragDetectorForScreen`.
    private func expandedNotchDragCaptureRegion() -> CGRect {
        let screenFrame: NSRect = {
            if presenter.geometry.screenFrame != .zero {
                return presenter.geometry.screenFrame
            }
            return (NSScreen.main ?? NSScreen.screens.first)?.frame ?? .zero
        }()
        guard screenFrame != .zero else { return .zero }

        let captureWidth = Self.expandedPanelSize.width + 64
        let captureHeight = Self.expandedPanelSize.height + 24
        let centerX = presenter.geometry.notchRect != .zero
            ? presenter.geometry.notchRect.midX
            : screenFrame.midX

        return CGRect(
            x: centerX - (captureWidth / 2),
            y: screenFrame.maxY - captureHeight,
            width: captureWidth,
            height: captureHeight
        )
    }

    @discardableResult
    private func inspectDragPasteboard(_ dragPB: NSPasteboard) -> Bool {
        let types = Set(dragPB.types ?? [])
        let hasSupported = !types.isDisjoint(with: Self.supportedDragTypes)
        guard hasSupported else {
            cachedDragHasImage = false
            cachedDragItemCount = 0
            return false
        }

        if let urls = dragPB.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            cachedDragItemCount = urls.count
            cachedDragHasImage = urls.contains {
                Self.imageDragExtensions.contains($0.pathExtension.lowercased())
            }
            return true
        }

        cachedDragItemCount = max(1, dragPB.pasteboardItems?.count ?? 1)
        cachedDragHasImage = types.contains(.png)
            || types.contains(.tiff)
            || types.contains(NSPasteboard.PasteboardType("public.image"))
            || types.contains(NSPasteboard.PasteboardType("public.jpeg"))
            || types.contains(NSPasteboard.PasteboardType("public.heic"))
        return true
    }

    private static func makeNotchMotion() -> NotchMotion {
        NotchMotion(
            expand: .spring(response: 0.34, dampingFraction: 0.84, blendDuration: 0),
            collapse: .timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.24),
            peek: .spring(response: 0.32, dampingFraction: 0.66),
            hover: .spring(response: 0.28, dampingFraction: 0.82),
            contentMorph: .timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.26),
            highlight: .easeOut(duration: 0.14)
        )
    }

    private static func makeConfiguration(
        hasPhysicalNotch: Bool,
        hoverToExpand: Bool,
        isPinned: Bool,
        hoverOpenDelay: Double,
        hapticsEnabled: Bool
    ) -> NotchConfiguration {
        let collapsedWidth: NotchCollapsedWidth = hasPhysicalNotch
            ? .wrapCutout(reserve: notchedCollapsedReserve)
            : .fixed(standaloneCollapsedWidth)

        return NotchConfiguration(
            expandedSize: expandedPanelSize,
            collapsedWidth: collapsedWidth,
            collapsedHitPadding: 8,
            collapsedTopCornerRadius: 6,
            expandedTopCornerRadius: 22,
            expandedBottomCornerRadius: 22,
            expandedTopReserve: .cutoutOnly,
            expandsOnHover: hoverToExpand,
            hoverOpenDelay: min(0.50, max(0.05, hoverOpenDelay)),
            hoverCancelGrace: 0.10,
            collapsesOnPointerExit: isPinned ? false : hoverToExpand,
            collapsesOnOutsideClick: !isPinned,
            hapticOnHoverOpen: hapticsEnabled
        )
    }
}
