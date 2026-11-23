import AppKit
import SwiftUI

/// Renders the crisp full-bleed Grav app logo at a given square size.
struct PreferencesAppIconImage: View {
    var size: CGFloat

    var body: some View {
        GravAppIconTile(size: size)
    }
}

/// System Settings–style account/profile header at the top of the Settings sidebar:
/// app icon, "Grav", live telemetry connection dot, and version subtitle. Clicking opens About.
struct SettingsSidebarProfileHeader: View {
    let store: AntigravityTelemetryStore
    let isSelected: Bool
    var onReplayWelcome: (() -> Void)? = nil
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private static let iconSize: CGFloat = 38
    private static let height: CGFloat = 56

    private var isTelemetryConnected: Bool {
        let status = store.connectionStatus
        return !store.isPaused && status.isBrainAccessible && (status.isAppRunning || !store.sessions.isEmpty)
    }

    private var liveSubtitle: String {
        if store.isPaused { return "Paused" }
        if store.state.isActive { return "Live · \(store.state.label)" }
        return isTelemetryConnected ? "\(appVersion) · Connected" : "\(appVersion) · Standby"
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "v\(version)"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                PreferencesAppIconImage(size: Self.iconSize)
                    .scaleEffect(!reduceMotion && isHovering ? 1.05 : 1.0)
                    .shadow(color: Color.black.opacity(0.20), radius: 5, y: 2)
                    .animation(reduceMotion ? nil : .spring(duration: 0.24, bounce: 0.26), value: isHovering)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Grav")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(store.isPaused ? Color.secondary : (isTelemetryConnected ? GravPalette.emerald : Color.orange))
                            .frame(width: 6, height: 6)

                        Text(liveSubtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: Self.height)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(isSelected ? 0.095 : (isHovering ? 0.055 : 0.025)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.primary.opacity(isSelected ? 0.12 : 0.06), lineWidth: 0.6)
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(PrecisionPressButtonStyle())
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
        .help("About Grav")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button("Refresh Telemetry Status") {
                store.refreshConnectionStatus()
            }

            Button(store.connectionStatus.isAppRunning ? "Focus Antigravity" : "Open Antigravity") {
                store.activateAntigravityApp()
            }

            if let onReplayWelcome {
                Divider()
                Button("Replay Welcome Screen") {
                    onReplayWelcome()
                }
            }
        }
    }
}
