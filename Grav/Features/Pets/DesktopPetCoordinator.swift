import AppKit
import Observation
import SwiftUI

/// Manages Grav's Codex-style floating desktop Mini Pet (`NSPanel` overlay).
/// Floats cleanly above windows across macOS Spaces without stealing focus, supports smooth
/// drag-anywhere positioning, snap corners, live resize, and instant Tuck Away / Show.
@MainActor
@Observable
public final class DesktopPetCoordinator {
    public let store: AntigravityTelemetryStore
    public let preferences: PreferencesStore
    public let petsStore: CodexPetsStore

    public var onOpenPetSettings: (() -> Void)?
    public var onFocusAntigravity: (() -> Void)?
    public var onToggleNotch: (() -> Void)?

    public private(set) var perchedAppName: String?
    public private(set) var perchCandidateAppName: String?

    private var panel: NSPanel?
    private var isInstalled = false
    private var isHiddenForFullscreen = false
    @ObservationIgnored private var isObserving = false
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var dragStartMouseLocation: NSPoint = .zero
    @ObservationIgnored private var dragStartWindowOrigin: NSPoint = .zero
    @ObservationIgnored private var lastTrackedPlacement: MiniPetPlacement = .topRight
    @ObservationIgnored private var perchedWindowID: CGWindowID?
    @ObservationIgnored private var perchedOffsetXRatio: CGFloat = 0.78
    @ObservationIgnored private var perchCandidate: WindowEdgeCandidate?
    @ObservationIgnored private var perchTrackingTask: Task<Void, Never>?

    private struct WindowEdgeCandidate {
        let windowID: CGWindowID
        let appName: String
        let appKitMinX: CGFloat
        let appKitWidth: CGFloat
        let appKitTopY: CGFloat
        let offsetXRatio: CGFloat
    }

    public init(
        store: AntigravityTelemetryStore,
        preferences: PreferencesStore,
        petsStore: CodexPetsStore = .shared,
        onOpenPetSettings: (() -> Void)? = nil,
        onFocusAntigravity: (() -> Void)? = nil,
        onToggleNotch: (() -> Void)? = nil
    ) {
        self.store = store
        self.preferences = preferences
        self.petsStore = petsStore
        self.onOpenPetSettings = onOpenPetSettings
        self.onFocusAntigravity = onFocusAntigravity
        self.onToggleNotch = onToggleNotch
        self.lastTrackedPlacement = preferences.miniPetPlacement
    }

    public func install() {
        guard !isInstalled else { return }
        isInstalled = true
        installFullscreenObservers()
        refreshFullscreenState()
        syncPanelState(animated: false)
        startObservation()
    }

    public func uninstall() {
        isInstalled = false
        isObserving = false
        clearPerch()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }

    public func syncPanelState(animated: Bool = true) {
        guard isInstalled else { return }

        if !preferences.miniPetEnabled || (preferences.miniPetAutoHideFullscreen && isHiddenForFullscreen) {
            hidePanel(animated: animated)
            return
        }

        let targetPanel = ensurePanel()
        targetPanel.level = preferences.miniPetAlwaysOnTop ? .floating : .normal

        let newSize = computePanelSize()
        let placementChanged = preferences.miniPetPlacement != lastTrackedPlacement
        lastTrackedPlacement = preferences.miniPetPlacement

        if placementChanged && preferences.miniPetPlacement != .free {
            preferences.miniPetOriginX = nil
            preferences.miniPetOriginY = nil
        }

        let targetOrigin = resolvedOrigin(for: newSize)
        let targetFrame = NSRect(origin: targetOrigin, size: newSize)

        if targetPanel.isVisible {
            if targetPanel.frame != targetFrame {
                if animated {
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.24
                        ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        targetPanel.animator().setFrame(targetFrame, display: true)
                    }
                } else {
                    targetPanel.setFrame(targetFrame, display: true)
                }
            }
        } else {
            targetPanel.setFrame(targetFrame, display: false)
            targetPanel.alphaValue = 0
            targetPanel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = animated ? 0.24 : 0.0
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                targetPanel.animator().alphaValue = 1
            }
        }
    }

    // MARK: - Dragging, Resizing & Window-Edge Perching Handlers

    func beginWindowDrag() {
        guard let panel else { return }
        clearPerch()
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = panel.frame.origin
    }

    func updateWindowDrag() {
        guard let panel else { return }
        let currentMouse = NSEvent.mouseLocation
        let dx = currentMouse.x - dragStartMouseLocation.x
        let dy = currentMouse.y - dragStartMouseLocation.y
        let rawOrigin = NSPoint(x: dragStartWindowOrigin.x + dx, y: dragStartWindowOrigin.y + dy)
        let clamped = clampOrigin(rawOrigin, size: panel.frame.size)
        panel.setFrameOrigin(clamped)

        if preferences.miniPetWindowPerching {
            let previousCandidateID = perchCandidate?.windowID
            let candidate = findNearestWindowTopEdge(forPanelFrame: panel.frame)
            perchCandidate = candidate
            perchCandidateAppName = candidate?.appName
            if candidate?.windowID != nil && candidate?.windowID != previousCandidateID {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        } else {
            perchCandidate = nil
            perchCandidateAppName = nil
        }
    }

    func endWindowDrag() {
        guard let panel else { return }

        if preferences.miniPetWindowPerching, let candidate = perchCandidate {
            perchCandidate = nil
            perchCandidateAppName = nil
            attachPerch(to: candidate, animated: true)
            return
        }

        perchCandidate = nil
        perchCandidateAppName = nil
        let origin = panel.frame.origin
        preferences.miniPetOriginX = Double(origin.x)
        preferences.miniPetOriginY = Double(origin.y)
        if preferences.miniPetPlacement != .free {
            lastTrackedPlacement = .free
            preferences.miniPetPlacement = .free
        }
    }

    func snapToPlacement(_ placement: MiniPetPlacement) {
        clearPerch()
        preferences.miniPetOriginX = nil
        preferences.miniPetOriginY = nil
        preferences.miniPetPlacement = placement
        syncPanelState(animated: true)
    }

    /// Perches the Mini Pet onto the top edge of Antigravity's main window (or frontmost non-Grav window).
    public func perchOnAntigravityWindow() {
        guard preferences.miniPetEnabled else { return }
        _ = ensurePanel()
        let candidates = listPerchableWindows()
        let target = candidates.first(where: { $0.appName.localizedCaseInsensitiveContains("Antigravity") })
            ?? candidates.first
        guard let target else { return }
        attachPerch(
            to: WindowEdgeCandidate(
                windowID: target.windowID,
                appName: target.appName,
                appKitMinX: target.appKitMinX,
                appKitWidth: target.appKitWidth,
                appKitTopY: target.appKitTopY,
                offsetXRatio: 0.80
            ),
            animated: true
        )
    }

    public func clearPerch() {
        perchTrackingTask?.cancel()
        perchTrackingTask = nil
        perchedWindowID = nil
        perchedAppName = nil
        perchCandidate = nil
        perchCandidateAppName = nil
    }

    private func attachPerch(to candidate: WindowEdgeCandidate, animated: Bool) {
        perchedWindowID = candidate.windowID
        perchedAppName = candidate.appName
        perchedOffsetXRatio = min(0.92, max(0.08, candidate.offsetXRatio))
        if preferences.miniPetPlacement != .free {
            lastTrackedPlacement = .free
            preferences.miniPetPlacement = .free
        }
        positionPanelOnPerch(
            appKitMinX: candidate.appKitMinX,
            appKitWidth: candidate.appKitWidth,
            appKitTopY: candidate.appKitTopY,
            animated: animated
        )
        startPerchTrackingLoop()
    }

    private func startPerchTrackingLoop() {
        perchTrackingTask?.cancel()
        guard let targetID = perchedWindowID else { return }
        perchTrackingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled, let self, self.perchedWindowID == targetID else { break }
                guard self.preferences.miniPetEnabled, self.preferences.miniPetWindowPerching else {
                    self.clearPerch()
                    break
                }
                if let bounds = Self.readAppKitBounds(forWindowID: targetID) {
                    self.positionPanelOnPerch(
                        appKitMinX: bounds.minX,
                        appKitWidth: bounds.width,
                        appKitTopY: bounds.maxY,
                        animated: false
                    )
                } else {
                    // Host window closed or minimized — gracefully stay put on desktop
                    self.clearPerch()
                    break
                }
            }
        }
    }

    private func positionPanelOnPerch(
        appKitMinX: CGFloat,
        appKitWidth: CGFloat,
        appKitTopY: CGFloat,
        animated: Bool
    ) {
        guard let panel else { return }
        let petSize = CGFloat(min(144.0, max(48.0, preferences.miniPetSize)))
        let feetOffsetFromPanelTop: CGFloat = 30.0 + petSize - 4.0
        let desiredOriginY = (appKitTopY + feetOffsetFromPanelTop) - panel.frame.height
        let desiredCenterX = appKitMinX + (appKitWidth * perchedOffsetXRatio)
        let desiredOriginX = desiredCenterX - (panel.frame.width / 2.0)
        let clamped = clampOrigin(NSPoint(x: desiredOriginX, y: desiredOriginY), size: panel.frame.size)

        guard abs(panel.frame.origin.x - clamped.x) > 0.5 || abs(panel.frame.origin.y - clamped.y) > 0.5 else {
            return
        }

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrameOrigin(clamped)
            }
        } else {
            panel.setFrameOrigin(clamped)
        }
        preferences.miniPetOriginX = Double(clamped.x)
        preferences.miniPetOriginY = Double(clamped.y)
    }

    private func findNearestWindowTopEdge(forPanelFrame frame: NSRect) -> WindowEdgeCandidate? {
        let petSize = CGFloat(min(144.0, max(48.0, preferences.miniPetSize)))
        let feetY = frame.maxY - (30.0 + petSize)
        let feetCenterX = frame.midX

        for win in listPerchableWindows() {
            let verticalDistance = abs(feetY - win.appKitTopY)
            guard verticalDistance <= 32.0 else { continue }
            guard feetCenterX >= win.appKitMinX + 20.0 && feetCenterX <= (win.appKitMinX + win.appKitWidth - 20.0) else {
                continue
            }
            let ratio = (feetCenterX - win.appKitMinX) / max(1.0, win.appKitWidth)
            return WindowEdgeCandidate(
                windowID: win.windowID,
                appName: win.appName,
                appKitMinX: win.appKitMinX,
                appKitWidth: win.appKitWidth,
                appKitTopY: win.appKitTopY,
                offsetXRatio: ratio
            )
        }
        return nil
    }

    private func listPerchableWindows() -> [WindowEdgeCandidate] {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        let myPID = ProcessInfo.processInfo.processIdentifier
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 900.0
        var results: [WindowEdgeCandidate] = []

        for dict in infoList {
            guard let layer = dict[kCGWindowLayer as String] as? Int, layer == 0,
                  let ownerPID = dict[kCGWindowOwnerPID as String] as? Int32, ownerPID != myPID,
                  let windowID = dict[kCGWindowNumber as String] as? CGWindowID,
                  let ownerName = dict[kCGWindowOwnerName as String] as? String, !ownerName.isEmpty,
                  let boundsDict = dict[kCGWindowBounds as String] as? NSDictionary,
                  let cgRect = CGRect(dictionaryRepresentation: boundsDict)
            else { continue }

            guard cgRect.width >= 240, cgRect.height >= 140 else { continue }
            let appKitTopY = primaryHeight - cgRect.origin.y
            // Skip fullscreen / menu-bar-flush windows where the pet would clip above the top edge
            guard appKitTopY < primaryHeight - 28 else { continue }

            results.append(
                WindowEdgeCandidate(
                    windowID: windowID,
                    appName: ownerName,
                    appKitMinX: cgRect.origin.x,
                    appKitWidth: cgRect.width,
                    appKitTopY: appKitTopY,
                    offsetXRatio: 0.78
                )
            )
        }
        return results
    }

    private static func readAppKitBounds(forWindowID windowID: CGWindowID) -> NSRect? {
        guard let infoList = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]],
              let dict = infoList.first,
              let boundsDict = dict[kCGWindowBounds as String] as? NSDictionary,
              let cgRect = CGRect(dictionaryRepresentation: boundsDict),
              cgRect.width >= 100, cgRect.height >= 60
        else { return nil }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 900.0
        let appKitMinY = primaryHeight - (cgRect.origin.y + cgRect.height)
        return NSRect(x: cgRect.origin.x, y: appKitMinY, width: cgRect.width, height: cgRect.height)
    }

    // MARK: - Private Panel Construction

    private func ensurePanel() -> NSPanel {
        if let existing = panel {
            return existing
        }

        let size = computePanelSize()
        let origin = resolvedOrigin(for: size)
        let created = DesktopPetPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = false
        created.isMovable = false
        created.isFloatingPanel = true
        created.hidesOnDeactivate = false
        created.worksWhenModal = true
        created.level = preferences.miniPetAlwaysOnTop ? .floating : .normal
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        created.ignoresMouseEvents = false

        let rootView = DesktopPetOverlayView(
            store: store,
            preferences: preferences,
            petsStore: petsStore,
            coordinator: self,
            onDragBegan: { [weak self] in self?.beginWindowDrag() },
            onDragChanged: { [weak self] in self?.updateWindowDrag() },
            onDragEnded: { [weak self] in self?.endWindowDrag() },
            onSnapPlacement: { [weak self] placement in self?.snapToPlacement(placement) },
            onTuckAway: { [weak self] in
                self?.preferences.miniPetEnabled = false
            },
            onOpenSettings: { [weak self] in
                self?.onOpenPetSettings?()
            },
            onFocusAntigravity: { [weak self] in
                self?.onFocusAntigravity?()
            },
            onToggleNotch: { [weak self] in
                self?.onToggleNotch?()
            }
        )

        let hosting = NSHostingView(rootView: rootView)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        created.contentView = hosting

        self.panel = created
        return created
    }

    private func hidePanel(animated: Bool) {
        guard let panel, panel.isVisible else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            } completionHandler: { [weak panel] in
                Task { @MainActor in
                    panel?.orderOut(nil)
                }
            }
        } else {
            panel.orderOut(nil)
        }
    }

    private func computePanelSize() -> CGSize {
        let petSize = CGFloat(min(144.0, max(48.0, preferences.miniPetSize)))
        let width = max(256, petSize + 108)
        let height = petSize + 154
        return CGSize(width: width, height: height)
    }

    private func resolvedOrigin(for size: CGSize) -> NSPoint {
        if preferences.miniPetPlacement == .free,
           let x = preferences.miniPetOriginX,
           let y = preferences.miniPetOriginY
        {
            return clampOrigin(NSPoint(x: x, y: y), size: size)
        }

        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin: CGFloat = 18

        switch preferences.miniPetPlacement {
        case .topRight, .free:
            return NSPoint(
                x: visible.maxX - size.width - margin,
                y: visible.maxY - size.height - margin
            )
        case .bottomRight:
            return NSPoint(
                x: visible.maxX - size.width - margin,
                y: visible.minY + margin
            )
        case .bottomLeft:
            return NSPoint(
                x: visible.minX + margin,
                y: visible.minY + margin
            )
        }
    }

    private func clampOrigin(_ origin: NSPoint, size: CGSize) -> NSPoint {
        let screens = NSScreen.screens
        let containing = screens.first { $0.visibleFrame.intersects(NSRect(origin: origin, size: size)) }
            ?? NSScreen.main
            ?? screens.first
        guard let visible = containing?.visibleFrame else { return origin }

        let minX = visible.minX - 24
        let maxX = visible.maxX - size.width + 24
        let minY = visible.minY - 24
        let maxY = visible.maxY - size.height + 16
        return NSPoint(
            x: min(maxX, max(minX, origin.x)),
            y: min(maxY, max(minY, origin.y))
        )
    }

    private func startObservation() {
        guard !isObserving else { return }
        isObserving = true
        observePreferences()
    }

    private func observePreferences() {
        guard isObserving else { return }
        withObservationTracking {
            _ = preferences.miniPetEnabled
            _ = preferences.miniPetSize
            _ = preferences.miniPetPlacement
            _ = preferences.miniPetAlwaysOnTop
            _ = preferences.miniPetAutoHideFullscreen
            _ = preferences.activeMiniPetID
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isObserving else { return }
                self.syncPanelState(animated: true)
                self.observePreferences()
            }
        }
    }

    private func installFullscreenObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        let spaceObs = nc.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshFullscreenState()
            }
        }
        let appObs = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshFullscreenState()
            }
        }
        workspaceObservers = [spaceObs, appObs]
    }

    private func refreshFullscreenState() {
        let nowFullscreen = Self.detectFullscreenSpace()
        if nowFullscreen != isHiddenForFullscreen {
            isHiddenForFullscreen = nowFullscreen
            syncPanelState(animated: true)
        }
    }

    /// Detects native macOS Fullscreen Space (where the menu bar auto-hides and `visibleFrame.maxY == frame.maxY`).
    private static func detectFullscreenSpace() -> Bool {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return false }
        let frame = screen.frame
        let visible = screen.visibleFrame
        let topBarHeight = frame.maxY - visible.maxY
        // On a normal desktop Space, topBarHeight >= 24pt (menu bar / notch); in Fullscreen Space it collapses to ~0.
        return topBarHeight < 4.0 && abs(visible.width - frame.width) < 4.0
    }
}

private final class DesktopPetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
