import SwiftUI

/// Native grouped-form Notch HUD preferences pane for hover, pin, auto-peek, and quick actions.
struct NotchHUDSettingsPane: View {
    @Bindable var preferences: PreferencesStore
    let store: AntigravityTelemetryStore
    var onToggleNotch: (() -> Void)?

    var body: some View {
        Form {
            Section("Interaction") {
                SettingRow(
                    title: "Hover to Expand",
                    description: "Resting the pointer over the notch smoothly expands live telemetry."
                ) {
                    Toggle("", isOn: $preferences.hoverToExpand)
                        .labelsHidden()
                }

                SettingRow(
                    title: "Pin Notch Open",
                    description: "Keep the expanded telemetry panel visible until dismissed manually."
                ) {
                    Toggle("", isOn: $preferences.isNotchPinned)
                        .labelsHidden()
                }

                SettingRow(
                    title: "Auto-Peek on Events",
                    description: "Briefly surface the notch on new thinking bursts, file edits, and completed commands."
                ) {
                    Toggle("", isOn: $preferences.autoPeekOnEvents)
                        .labelsHidden()
                }
            }

            Section("Quick Actions") {
                SettingRow(
                    title: "Notch Status",
                    description: statusSubtitle,
                    descriptionStyle: .subtitle
                ) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusDotColor)
                            .frame(width: 6, height: 6)

                        Text(statusLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                SettingRow(
                    title: "Toggle Notch HUD",
                    description: "Immediately expand or collapse the Notch HUD panel on the active display."
                ) {
                    Button("Toggle Notch") {
                        onToggleNotch?()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(onToggleNotch == nil)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var isPaused: Bool {
        store.isPaused || preferences.isTelemetryPaused
    }

    private var statusLabel: String {
        if isPaused { return "Paused" }
        return store.state.label
    }

    private var statusDotColor: Color {
        if isPaused { return .secondary }
        switch store.state {
        case .idle:
            return store.connectionStatus.isBrainAccessible ? .green : .orange
        case .thinking:
            return .cyan
        case .editing:
            return .orange
        case .runningCommand:
            return .green
        }
    }

    private var statusSubtitle: String {
        if isPaused {
            return "Telemetry is paused — resume from Telemetry settings or the menu bar."
        }
        let triggerText = preferences.hoverToExpand ? "Hover-to-expand active" : "Click-only trigger active"
        let pinText = preferences.isNotchPinned ? "Pinned open" : "Auto-collapses on exit"
        return "\(triggerText) · \(pinText)"
    }
}
