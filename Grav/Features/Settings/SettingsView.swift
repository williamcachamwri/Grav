import Observation
import SwiftUI

/// Primary navigation sections for Grav's native macOS Settings window.
public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general
    case notchHUD
    case telemetry

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return "General"
        case .notchHUD: return "Notch HUD"
        case .telemetry: return "Telemetry"
        }
    }

    public var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .notchHUD: return "rectangle.topthird.inset.filled"
        case .telemetry: return "waveform.path.ecg"
        }
    }
}

/// Shared navigation model allowing `SettingsWindowController` to focus a specific tab.
@MainActor
@Observable
public final class SettingsNavigationModel {
    public var selectedTab: SettingsTab

    public init(selectedTab: SettingsTab = .general) {
        self.selectedTab = selectedTab
    }
}

/// Native macOS Settings interface supporting both Light and Dark appearances.
public struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var tabNamespace

    @Bindable public var preferences: PreferencesStore
    public var store: AntigravityTelemetryStore
    @Bindable public var navigation: SettingsNavigationModel
    public var onReplayWelcome: (() -> Void)?

    public init(
        preferences: PreferencesStore,
        store: AntigravityTelemetryStore,
        navigation: SettingsNavigationModel = SettingsNavigationModel(),
        onReplayWelcome: (() -> Void)? = nil
    ) {
        self.preferences = preferences
        self.store = store
        self.navigation = navigation
        self.onReplayWelcome = onReplayWelcome
    }

    public var body: some View {
        let palette = GravAdaptivePalette(colorScheme: colorScheme)

        VStack(spacing: 0) {
            headerBar(palette: palette)

            Rectangle()
                .fill(palette.divider)
                .frame(height: 0.5)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: GravSpacing.lg) {
                    switch navigation.selectedTab {
                    case .general:
                        generalContent(palette: palette)
                    case .notchHUD:
                        notchHUDContent(palette: palette)
                    case .telemetry:
                        AntigravityTelemetrySettingsSection(
                            preferences: preferences,
                            store: store
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
        }
        .frame(minWidth: 520, idealWidth: 520, minHeight: 440, idealHeight: 440)
        .background(palette.windowBackground)
        .onAppear {
            preferences.refreshLaunchAtLoginStatus()
            store.refreshConnectionStatus()
        }
    }

    // MARK: - Header & Segmented Tab Rail

    private func headerBar(palette: GravAdaptivePalette) -> some View {
        HStack(spacing: GravSpacing.md) {
            HStack(spacing: GravSpacing.sm) {
                GravAppIconTile(size: 24)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Grav")
                        .font(GravTypography.sectionHeader)
                        .foregroundStyle(palette.inkPrimary)

                    Text("v\(appVersionString)")
                        .font(GravTypography.monoMicro)
                        .monospacedDigit()
                        .foregroundStyle(palette.inkTertiary)
                }
            }

            Spacer(minLength: GravSpacing.md)

            tabRail(palette: palette)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(palette.isDark ? GravPalette.obsidianVoid.opacity(0.45) : Color.white.opacity(0.55))
    }

    private func tabRail(palette: GravAdaptivePalette) -> some View {
        HStack(spacing: 2) {
            ForEach(SettingsTab.allCases) { tab in
                let isSelected = navigation.selectedTab == tab
                Button {
                    if reduceMotion {
                        navigation.selectedTab = tab
                    } else {
                        withAnimation(GravMotion.railSpring) {
                            navigation.selectedTab = tab
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 11, weight: .medium))
                        Text(tab.title)
                            .font(GravTypography.caption)
                    }
                    .foregroundStyle(isSelected ? palette.inkPrimary : palette.inkTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        if isSelected {
                            LiquidGlassBackground(
                                elevation: .elevated,
                                radius: GravRadius.controlS,
                                adaptive: true,
                                includeBorder: true
                            )
                            .matchedGeometryEffect(id: "settings-tab-pill", in: tabNamespace)
                        }
                    }
                    .contentShape(RoundedRectangle.grav(GravRadius.controlS))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .liquidGlassSurface(
            elevation: .subtle,
            radius: GravRadius.controlM,
            adaptive: true,
            includeBorder: true
        )
    }

    // MARK: - General Tab

    @ViewBuilder
    private func generalContent(palette: GravAdaptivePalette) -> some View {
        SettingsSectionCard(
            title: "Startup & Onboarding",
            systemImage: "power"
        ) {
            SettingsToggleRow(
                title: "Launch at Login",
                subtitle: "Start Grav automatically in your menu bar when signing in to macOS.",
                isOn: $preferences.launchAtLogin
            )

            if let errorMessage = preferences.launchAtLoginError, !errorMessage.isEmpty {
                SettingsRowDivider()
                SettingsInlineNotice(tone: .error, message: errorMessage)
            }

            SettingsRowDivider()

            SettingsControlRow(
                title: "Welcome Screen",
                subtitle: "Revisit the Antigravity connection check and interactive Notch HUD walkthrough."
            ) {
                Button("Replay Welcome") {
                    onReplayWelcome?()
                }
                .buttonStyle(.gravGlass(horizontalPadding: 11, verticalPadding: 5))
            }
        }

        SettingsSectionCard(
            title: "Runtime",
            systemImage: "cpu"
        ) {
            SettingsControlRow(
                title: "Telemetry Channel",
                subtitle: "Event-driven local filesystem observation with zero idle polling."
            ) {
                HStack(spacing: GravSpacing.xs) {
                    SemanticDot(
                        tone: store.isPaused ? .idle : .success,
                        size: 6,
                        isActive: store.state.isActive && !store.isPaused,
                        showPulse: true,
                        adaptive: true
                    )
                    Text(store.isPaused ? "Paused" : "Local Disk")
                        .font(GravTypography.monoCaption)
                        .foregroundStyle(palette.inkSecondary)
                }
            }

            SettingsRowDivider()

            SettingsControlRow(
                title: "Version",
                subtitle: "Grav for Antigravity on macOS"
            ) {
                Text("\(appVersionString) (\(appBuildString))")
                    .font(GravTypography.monoCaption)
                    .monospacedDigit()
                    .foregroundStyle(palette.inkTertiary)
            }
        }
    }

    // MARK: - Notch HUD Tab

    @ViewBuilder
    private func notchHUDContent(palette: GravAdaptivePalette) -> some View {
        SettingsSectionCard(
            title: "Interaction",
            systemImage: "cursorarrow.click.2"
        ) {
            SettingsControlRow(
                title: "Expansion Trigger",
                subtitle: preferences.hoverToExpand
                    ? "Resting the pointer over the notch smoothly expands live telemetry."
                    : "Click the collapsed notch pill to expand or collapse telemetry."
            ) {
                triggerModeControl(palette: palette)
            }

            SettingsRowDivider()

            SettingsToggleRow(
                title: "Auto-Peek on Events",
                subtitle: "Briefly surface the notch on new thinking bursts, file deletes, and completed commands.",
                isOn: $preferences.autoPeekOnEvents
            )

            SettingsRowDivider()

            SettingsToggleRow(
                title: "Pin Notch Open",
                subtitle: "Keep the expanded telemetry panel visible until dismissed manually.",
                isOn: $preferences.isNotchPinned
            )
        }

        SettingsSectionCard(
            title: "HUD Shortcuts",
            systemImage: "keyboard"
        ) {
            HStack(spacing: GravSpacing.lg) {
                GravKeycapHint(keys: ["1", "2", "3"], label: "Switch tabs")
                GravKeycapHint(key: "ESC", label: "Collapse")
                GravKeycapHint(key: "⌘C", label: "Copy log or diff")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private func triggerModeControl(palette: GravAdaptivePalette) -> some View {
        HStack(spacing: 2) {
            triggerOptionButton(
                title: "Hover",
                isSelected: preferences.hoverToExpand,
                palette: palette
            ) {
                setHoverToExpand(true)
            }

            triggerOptionButton(
                title: "Click-Only",
                isSelected: !preferences.hoverToExpand,
                palette: palette
            ) {
                setHoverToExpand(false)
            }
        }
        .padding(2)
        .liquidGlassSurface(
            elevation: .subtle,
            radius: GravRadius.controlS,
            adaptive: true,
            includeBorder: true
        )
    }

    private func triggerOptionButton(
        title: String,
        isSelected: Bool,
        palette: GravAdaptivePalette,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(GravTypography.caption)
                .foregroundStyle(isSelected ? palette.inkPrimary : palette.inkTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background {
                    if isSelected {
                        LiquidGlassBackground(
                            elevation: .elevated,
                            radius: GravRadius.controlXS,
                            adaptive: true,
                            includeBorder: true
                        )
                    }
                }
                .contentShape(RoundedRectangle.grav(GravRadius.controlXS))
        }
        .buttonStyle(.plain)
    }

    private func setHoverToExpand(_ enabled: Bool) {
        if reduceMotion {
            preferences.hoverToExpand = enabled
        } else {
            withAnimation(GravMotion.rowHover) {
                preferences.hoverToExpand = enabled
            }
        }
    }

    private var appVersionString: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0.0"
    }

    private var appBuildString: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "1"
    }
}
