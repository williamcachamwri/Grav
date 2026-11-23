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

    private var panel: NSPanel?
    private var isInstalled = false
    private var isHiddenForFullscreen = false
    @ObservationIgnored private var isObserving = false
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var dragStartMouseLocation: NSPoint = .zero
    @ObservationIgnored private var dragStartWindowOrigin: NSPoint = .zero
    @ObservationIgnored private var lastTrackedPlacement: MiniPetPlacement = .topRight

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

    // MARK: - Dragging & Resizing Handlers

    func beginWindowDrag() {
        guard let panel else { return }
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
    }

    func endWindowDrag() {
        guard let panel else { return }
        let origin = panel.frame.origin
        preferences.miniPetOriginX = Double(origin.x)
        preferences.miniPetOriginY = Double(origin.y)
        if preferences.miniPetPlacement != .free {
            lastTrackedPlacement = .free
            preferences.miniPetPlacement = .free
        }
    }

    func snapToPlacement(_ placement: MiniPetPlacement) {
        preferences.miniPetOriginX = nil
        preferences.miniPetOriginY = nil
        preferences.miniPetPlacement = placement
        syncPanelState(animated: true)
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
