import AppKit
import Foundation
import NotchKit
import Observation
import SwiftUI

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
                isPinned: preferences.isNotchPinned
            ),
            motion: .resolved(gravMotion),
            style: .standard,
            preferredScreenID: preferredScreenID
        )
        initialPresenter.configuration = Self.makeConfiguration(
            hasPhysicalNotch: initialPresenter.geometry.hasPhysicalNotch,
            hoverToExpand: preferences.hoverToExpand,
            isPinned: preferences.isNotchPinned
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
            CollapsedNotchView(store: storeRef, presenter: presenterRef)
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

        if preferences.isNotchPinned {
            presenter.expand(reason: .programmatic)
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

    /// Returns the AppKit screen-space target point at the center of the physical notch
    /// (or standalone collapsed island) for onboarding finale trajectories.
    public func notchTargetScreenPoint() -> CGPoint {
        presenter.refreshPlacement()
        let geometry = presenter.geometry
        if geometry.screenFrame != .zero {
            let rect = geometry.notchRect
            return CGPoint(x: rect.midX, y: rect.midY)
        }
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            return CGPoint(
                x: screen.frame.midX,
                y: screen.frame.maxY - NotchGeometry.simulatedNotchHeight / 2
            )
        }
        return .zero
    }

    /// Reconciles `NotchPresenter.configuration` with current `PreferencesStore` and display geometry.
    public func syncPreferences() {
        let updated = Self.makeConfiguration(
            hasPhysicalNotch: presenter.geometry.hasPhysicalNotch,
            hoverToExpand: preferences.hoverToExpand,
            isPinned: preferences.isNotchPinned
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

    private func handlePeekRequest(_ event: NotchPeekEvent) {
        guard isInstalled else { return }

        if case .welcome = event {
            presenter.peek()
            return
        }

        guard preferences.autoPeekOnEvents, !store.isPaused else { return }
        guard presenter.phase == .collapsed else { return }

        let now = Date()
        guard now.timeIntervalSince(lastTelemetryPeekAt) >= 1.2 else { return }
        lastTelemetryPeekAt = now
        presenter.peek()
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
        isPinned: Bool
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
            hoverOpenDelay: 0.15,
            hoverCancelGrace: 0.10,
            collapsesOnPointerExit: isPinned ? false : hoverToExpand,
            collapsesOnOutsideClick: !isPinned,
            hapticOnHoverOpen: true
        )
    }
}
