import SwiftUI

/// Native grouped-form General preferences pane matching Snapzy's `GeneralSettingsView`.
struct GeneralSettingsPane: View {
    @Bindable var preferences: PreferencesStore
    var onReplayWelcome: (() -> Void)?

    var body: some View {
        Form {
            Section("Startup") {
                SettingRow(
                    title: "Launch at Login",
                    description: "Start Grav automatically in your menu bar when you sign in to macOS."
                ) {
                    Toggle("", isOn: $preferences.launchAtLogin)
                        .labelsHidden()
                }

                if let errorMessage = preferences.launchAtLoginError, !errorMessage.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                SettingRow(
                    title: "Show Menu Bar Icon",
                    description: "Display Grav's orbital telemetry status icon in the macOS menu bar."
                ) {
                    Toggle("", isOn: $preferences.showMenuBarIcon)
                        .labelsHidden()
                }
            }

            Section("Appearance") {
                SettingRow(
                    title: "Appearance",
                    description: "Choose System to match macOS automatically, or pin Grav to Light or Dark mode.",
                    alignment: .top
                ) {
                    AppearanceModePicker(selection: $preferences.appearanceMode)
                }

                SettingRow(
                    title: "Liquid Glass",
                    description: "Enable translucent Liquid Glass materials across Grav surfaces and controls."
                ) {
                    Toggle("", isOn: $preferences.useLiquidGlass)
                        .labelsHidden()
                }

                SettingRow(
                    title: "Sound Effects",
                    description: "Play ambient soundscape and subtle tactile glass cues during the welcome experience."
                ) {
                    Toggle("", isOn: $preferences.playSounds)
                        .labelsHidden()
                }
            }

            Section("Help") {
                SettingRow(
                    title: "Restart Onboarding",
                    description: "Revisit the welcome screen, live Antigravity connection check, and Notch HUD walkthrough."
                ) {
                    Button("Restart") {
                        onReplayWelcome?()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            preferences.refreshLaunchAtLoginStatus()
        }
    }
}
