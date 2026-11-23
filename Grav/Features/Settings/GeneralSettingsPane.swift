import SwiftUI

/// Precision Canvas General preferences pane: Startup, Appearance, Liquid Glass & Onboarding.
struct GeneralSettingsPane: View {
    @Bindable var preferences: PreferencesStore
    var onReplayWelcome: (() -> Void)?

    var body: some View {
        SettingsPageCanvas(
            tab: .general,
            subtitle: "Startup behavior, window appearance, Liquid Glass chrome, and welcome walkthrough."
        ) {
            SettingsCardGroup(title: "Startup & Integration", staggerIndex: 0) {
                SettingRow(
                    title: "Launch at Login",
                    description: "Start Grav automatically in your menu bar when you sign in to macOS."
                ) {
                    Toggle("", isOn: $preferences.launchAtLogin)
                        .labelsHidden()
                }

                if let errorMessage = preferences.launchAtLoginError, !errorMessage.isEmpty {
                    HStack(alignment: .center, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Text(errorMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }

                SettingsRowDivider()

                SettingRow(
                    title: "Show Menu Bar Icon",
                    description: "Display Grav's orbital telemetry status icon and quick menu in the macOS menu bar."
                ) {
                    Toggle("", isOn: $preferences.showMenuBarIcon)
                        .labelsHidden()
                }
            }

            SettingsCardGroup(title: "Appearance & Feedback", staggerIndex: 1) {
                SettingRow(
                    title: "Appearance",
                    description: "Choose System to match macOS automatically, or pin Grav to Light or Dark mode.",
                    alignment: .top
                ) {
                    AppearanceModePicker(selection: $preferences.appearanceMode)
                }

                SettingsRowDivider()

                SettingRow(
                    title: "Liquid Glass",
                    description: "Use macOS translucent Liquid Glass optical refraction across Grav surfaces and previews."
                ) {
                    Toggle("", isOn: $preferences.useLiquidGlass)
                        .labelsHidden()
                }

                SettingsRowDivider()

                SettingRow(
                    title: "Sound Effects",
                    description: "Play subtle tactile chimes for completions, failures, and onboarding transitions."
                ) {
                    Toggle("", isOn: $preferences.playSounds)
                        .labelsHidden()
                }
            }

            SettingsCardGroup(title: "Walkthrough", staggerIndex: 2) {
                SettingRow(
                    title: "Restart Onboarding",
                    description: "Reopen the interactive welcome experience, Notch HUD demo, and Mini Pet studio."
                ) {
                    SettingsActionPill(title: "Replay Welcome", systemImage: "arrow.counterclockwise") {
                        onReplayWelcome?()
                    }
                }
            }
        }
        .onAppear {
            preferences.refreshLaunchAtLoginStatus()
        }
    }
}
