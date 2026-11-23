import AppKit
import SwiftUI

/// Root Settings window view ported 1:1 from Snapzy's `PreferencesView`:
/// native macOS System Settings `NavigationSplitView` with a fixed non-collapsible 220pt sidebar,
/// grouped-form detail panes, search-jump scrolling, and ⌘[/⌘] history navigation.
public struct SettingsView: View {
    @Bindable public var preferences: PreferencesStore
    public let store: AntigravityTelemetryStore
    public let navigationState: SettingsNavigationState
    public var onReplayWelcome: (() -> Void)?
    public var onToggleNotch: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastTabOrderIndex: Int = 0
    @State private var tabSlideSign: CGFloat = 1

    /// Fixed sidebar width prevents divider dragging and accidental collapsing.
    private static let fixedSidebarWidth: CGFloat = 224

    public init(
        preferences: PreferencesStore,
        store: AntigravityTelemetryStore,
        navigationState: SettingsNavigationState = SettingsNavigationState(),
        onReplayWelcome: (() -> Void)? = nil,
        onToggleNotch: (() -> Void)? = nil
    ) {
        self.preferences = preferences
        self.store = store
        self.navigationState = navigationState
        self.onReplayWelcome = onReplayWelcome
        self.onToggleNotch = onToggleNotch
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: columnVisibilityBinding) {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(preferences.appearanceMode.colorScheme)
        .frame(
            minWidth: SettingsWindowController.minimumContentSize.width,
            minHeight: SettingsWindowController.minimumContentSize.height
        )
        .background(NonCollapsibleSplitViewModifier())
        .onAppear {
            preferences.refreshLaunchAtLoginStatus()
            store.refreshConnectionStatus()
        }
    }

    /// Locks column visibility to `.all` so the sidebar stays permanently visible.
    private var columnVisibilityBinding: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { .all },
            set: { _ in }
        )
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        SettingsSidebarView(
            navigationState: navigationState,
            store: store,
            onReplayWelcome: onReplayWelcome
        )
        .modifier(SidebarToggleRemovalModifier())
        .navigationSplitViewColumnWidth(
            min: Self.fixedSidebarWidth,
            ideal: Self.fixedSidebarWidth,
            max: Self.fixedSidebarWidth
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings Sidebar")
    }

    // MARK: - Detail

    private var detail: some View {
        ScrollViewReader { proxy in
            page
                .environment(\.preferencesHighlightedSetting, navigationState.highlightedSetting)
                .onChange(of: navigationState.revealRequest) { _, request in
                    guard let request else { return }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(150))
                        if request.scrolls {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(request.title, anchor: .center)
                            }
                        }
                        navigationState.didReveal(request)
                    }
                }
        }
        .navigationTitle(navigationState.title)
        .navigationSplitViewColumnWidth(min: 480, ideal: 580)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    navigationState.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!navigationState.canGoBack)
                .help("Back")
                .keyboardShortcut("[", modifiers: .command)

                Button {
                    navigationState.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!navigationState.canGoForward)
                .help("Forward")
                .keyboardShortcut("]", modifiers: .command)
            }
        }
    }

    private var page: some View {
        Group {
            switch navigationState.selectedTab {
            case .general:
                SettingsLazyView {
                    GeneralSettingsPane(
                        preferences: preferences,
                        onReplayWelcome: onReplayWelcome
                    )
                }
            case .notchHUD:
                SettingsLazyView {
                    NotchHUDSettingsPane(
                        preferences: preferences,
                        store: store,
                        onToggleNotch: onToggleNotch
                    )
                }
            case .miniPet:
                SettingsLazyView {
                    MiniPetSettingsPane(
                        preferences: preferences
                    )
                }
            case .telemetry:
                SettingsLazyView {
                    TelemetrySettingsPane(
                        preferences: preferences,
                        store: store
                    )
                }
            case .menuBar:
                SettingsLazyView {
                    MenuBarSettingsPane(
                        preferences: preferences,
                        store: store
                    )
                }
            case .shortcuts:
                SettingsLazyView {
                    ShortcutsSettingsPane(preferences: preferences)
                }
            case .permissions:
                SettingsLazyView {
                    PermissionsSettingsPane(
                        preferences: preferences,
                        store: store
                    )
                }
            case .about:
                SettingsLazyView {
                    AboutSettingsPane(
                        store: store,
                        onReplayWelcome: onReplayWelcome
                    )
                }
            }
        }
        .id(navigationState.selectedTab)
        .transition(
            reduceMotion
                ? .opacity
                : .asymmetric(
                    insertion: .opacity.combined(with: .offset(y: tabSlideSign * 10)),
                    removal: .opacity.combined(with: .offset(y: -tabSlideSign * 6))
                )
        )
        .animation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.06), value: navigationState.selectedTab)
        .onChange(of: navigationState.selectedTab) { oldTab, newTab in
            let order = SettingsTab.sidebarOrder
            let oldIdx = order.firstIndex(of: oldTab) ?? 0
            let newIdx = order.firstIndex(of: newTab) ?? 0
            tabSlideSign = newIdx >= oldIdx ? 1 : -1
            lastTabOrderIndex = newIdx
        }
    }
}

// MARK: - Lazy Page Wrapper

private struct SettingsLazyView<Content: View>: View {
    let build: () -> Content

    init(@ViewBuilder build: @escaping () -> Content) {
        self.build = build
    }

    var body: some View {
        build()
    }
}

// MARK: - Sidebar Toggle Removal

private struct SidebarToggleRemovalModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar(removing: .sidebarToggle)
    }
}

// MARK: - Non-Collapsible Split View Modifier

/// Enforces non-collapsible behavior on the underlying AppKit `NSSplitViewItem` for the sidebar,
/// preventing collapsing via shortcuts (⌘⌥S), divider dragging, or divider double-clicking.
private struct NonCollapsibleSplitViewModifier: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in
            configure(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in
            configure(from: nsView)
        }
    }

    @MainActor
    private func configure(from view: NSView) {
        guard let window = view.window,
              let splitView = window.contentView?.firstDescendant(ofType: NSSplitView.self),
              let splitViewController = splitView.delegate as? NSSplitViewController,
              let sidebarItem = splitViewController.splitViewItems.first
        else {
            return
        }

        if sidebarItem.canCollapse {
            sidebarItem.canCollapse = false
        }
        if sidebarItem.isCollapsed {
            sidebarItem.isCollapsed = false
        }
    }
}
