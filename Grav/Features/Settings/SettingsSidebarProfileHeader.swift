import AppKit
import SwiftUI

/// Renders the running application icon at a given square size.
struct PreferencesAppIconImage: View {
    var size: CGFloat

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

/// System Settings–style account/profile header at the top of the Settings sidebar:
/// app icon, "Grav", live telemetry connection dot, and version subtitle. Clicking opens About.
struct SettingsSidebarProfileHeader: View {
    let store: AntigravityTelemetryStore
    let isSelected: Bool
    var onReplayWelcome: (() -> Void)? = nil
    let action: () -> Void

    @State private var isHovering = false

    private static let iconSize: CGFloat = 40
    private static let height: CGFloat = 54

    private var isTelemetryConnected: Bool {
        let status = store.connectionStatus
        return !store.isPaused && status.isBrainAccessible && (status.isAppRunning || !store.sessions.isEmpty)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "v\(version)"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                PreferencesAppIconImage(size: Self.iconSize)
                    .shadow(color: Color.black.opacity(0.15), radius: 3, y: 1)

                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: "Grav")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(isTelemetryConnected ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)

                        Text(verbatim: "\(appVersion) · Telemetry")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: Self.height)
            .background {
                Radius.rect(Radius.card)
                    .fill(Color.primary.opacity(isSelected ? 0.08 : (isHovering ? 0.045 : 0)))
            }
            .contentShape(Radius.rect(Radius.card))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
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
