import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Menu Bar Settings Pane

/// Native grouped-form Menu Bar pane with a live macOS status bar preview card.
struct MenuBarSettingsPane: View {
    @Bindable var preferences: PreferencesStore
    let store: AntigravityTelemetryStore

    var body: some View {
        Form {
            Section("Preview") {
                GravMenuBarPreviewCard(
                    showIcon: preferences.showMenuBarIcon,
                    isPaused: store.isPaused || preferences.isTelemetryPaused,
                    statusLabel: store.state.label,
                    isAppRunning: store.connectionStatus.isAppRunning
                )
                .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            }

            Section("Menu Bar") {
                SettingRow(
                    title: "Show Menu Bar Icon",
                    description: "Display Grav's orbital telemetry icon and quick controls in the macOS menu bar."
                ) {
                    Toggle("", isOn: $preferences.showMenuBarIcon)
                        .labelsHidden()
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Clean live preview of the top-right macOS menu bar corner and Grav's status menu.
private struct GravMenuBarPreviewCard: View {
    let showIcon: Bool
    let isPaused: Bool
    let statusLabel: String
    let isAppRunning: Bool

    @State private var hoveredRow: String?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Subtle slate-indigo desktop backdrop matching Snapzy's menu bar preview aesthetic
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.14, blue: 0.22),
                    Color(red: 0.06, green: 0.09, blue: 0.15),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .trailing, spacing: 6) {
                // Miniature macOS menu bar strip
                HStack(spacing: 10) {
                    Spacer(minLength: 0)

                    Image(systemName: "cloud")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))

                    if showIcon {
                        GravOrbitalMark(size: 13, tint: .white)
                            .frame(width: 26, height: 18)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.white.opacity(0.22))
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }

                    Image(systemName: "wifi")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))

                    Image(systemName: "battery.75percent")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))

                    Text("9:41")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(Color.black.opacity(0.32))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(height: 0.5)
                }

                // Miniature dropdown menu panel anchored beneath the Grav icon
                if showIcon {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(isPaused ? Color.secondary : (isAppRunning ? Color.green : Color.orange))
                                .frame(width: 6, height: 6)
                            Text(isPaused ? "Telemetry Paused" : "Antigravity · \(statusLabel)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.92))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)

                        menuDivider
                        previewRow(id: "toggle", symbol: "rectangle.topthird.inset.filled", title: "Toggle Notch", shortcut: nil)
                        previewRow(
                            id: "pause",
                            symbol: isPaused ? "play.circle" : "pause.circle",
                            title: isPaused ? "Resume Telemetry" : "Pause Telemetry",
                            shortcut: nil
                        )
                        menuDivider
                        previewRow(id: "prefs", symbol: "gearshape", title: "Preferences…", shortcut: "⌘,")
                        previewRow(id: "quit", symbol: "power", title: "Quit Grav", shortcut: "⌘Q")
                    }
                    .padding(5)
                    .frame(width: 210)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(white: 0.12).opacity(0.92))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                    .padding(.trailing, 54)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    HStack {
                        Spacer()
                        Text("Menu bar icon hidden — Grav remains accessible via the Notch HUD.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.68))
                        Spacer()
                    }
                    .padding(.top, 52)
                }

                Spacer(minLength: 0)
            }
        }
        .frame(height: 196)
        .clipShape(Radius.rect(Radius.card))
        .overlay(
            Radius.rect(Radius.card)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.18), value: showIcon)
    }

    private var menuDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(height: 0.5)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
    }

    private func previewRow(id: String, symbol: String, title: String, shortcut: String?) -> some View {
        let isHovered = hoveredRow == id
        return HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10.5))
                .frame(width: 14)

            Text(title)
                .font(.system(size: 11.5))
                .lineLimit(1)

            Spacer(minLength: 8)

            if let shortcut {
                Text(shortcut)
                    .font(.system(size: 11))
                    .foregroundStyle(isHovered ? .white.opacity(0.85) : .white.opacity(0.45))
            }
        }
        .foregroundStyle(isHovered ? .white : .white.opacity(0.88))
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isHovered ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredRow = id
            } else if hoveredRow == id {
                hoveredRow = nil
            }
        }
    }
}

// MARK: - Shortcuts Settings Pane

/// Native grouped-form Shortcuts reference pane using `GravKeycapChip` and `GravKeycapRow`.
struct ShortcutsSettingsPane: View {
    var body: some View {
        Form {
            Section("Notch HUD") {
                SettingRow(
                    title: "Live Tab",
                    description: "Jump to the live thinking and activity stream while the Notch HUD is focused."
                ) {
                    SettingsKeycapPlate(keys: ["1"])
                }

                SettingRow(
                    title: "Files Tab",
                    description: "Jump to modified files and inline diff previews in the Notch HUD."
                ) {
                    SettingsKeycapPlate(keys: ["2"])
                }

                SettingRow(
                    title: "Terminal Tab",
                    description: "Jump to running commands and streaming task logs in the Notch HUD."
                ) {
                    SettingsKeycapPlate(keys: ["3"])
                }

                SettingRow(
                    title: "Collapse Notch",
                    description: "Dismiss the expanded Notch HUD back to its compact pill."
                ) {
                    SettingsKeycapPlate(keys: ["Esc"])
                }

                SettingRow(
                    title: "Copy Log or Diff",
                    description: "Copy the active command log or selected file diff to the clipboard."
                ) {
                    SettingsKeycapPlate(keys: ["⌘", "C"])
                }
            }

            Section("Settings Window") {
                SettingRow(
                    title: "Search Settings",
                    description: "Focus the sidebar search field from anywhere inside Settings."
                ) {
                    SettingsKeycapPlate(keys: ["⌘", "F"])
                }

                SettingRow(
                    title: "Navigate Back",
                    description: "Return to the previous Settings pane in navigation history."
                ) {
                    SettingsKeycapPlate(keys: ["⌘", "["])
                }

                SettingRow(
                    title: "Navigate Forward",
                    description: "Move forward to the next Settings pane in navigation history."
                ) {
                    SettingsKeycapPlate(keys: ["⌘", "]"])
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Renders `GravKeycapChip` / `GravKeycapRow` with high contrast in both Light and Dark appearances.
private struct SettingsKeycapPlate: View {
    @Environment(\.colorScheme) private var colorScheme
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                GravKeycapChip(label: key, emphasis: true)
                    .background {
                        if colorScheme == .light {
                            Radius.rect(Radius.ornament)
                                .fill(Color(white: 0.16))
                        }
                    }
            }
        }
    }
}

// MARK: - Permissions Settings Pane

/// Native grouped-form Permissions pane inspecting real brain directory readability and `SMAppService` status.
struct PermissionsSettingsPane: View {
    @Bindable var preferences: PreferencesStore
    let store: AntigravityTelemetryStore

    @Environment(\.preferencesHighlightedSetting) private var highlightedSetting
    @State private var loginItemStatus: SMAppService.Status = SMAppService.mainApp.status
    @State private var hasAppeared = false

    private static let loginItemsSettingsURL =
        "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"

    var body: some View {
        let status = store.connectionStatus
        let brainReadable = status.isBrainAccessible && !status.needsFolderAccess

        Form {
            Section("Permissions") {
                Text("Grav observes local Antigravity transcript logs directly on disk with zero network traffic or background idle polling.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                permissionRow(
                    anchorTitle: "Antigravity Brain Directory",
                    icon: "folder.fill",
                    name: "Antigravity Brain Directory",
                    description: brainReadable
                        ? abbreviatedPath(status.brainDirectoryURL)
                        : "Required to read local Antigravity transcripts at ~/.gemini/antigravity/brain.",
                    statusLabel: brainReadable ? "Granted" : "Access Needed",
                    statusDotColor: brainReadable ? .green : .orange,
                    isRequired: true,
                    actionTitle: brainReadable ? "Reveal" : "Grant Folder Access"
                ) {
                    if brainReadable {
                        revealBrainFolder(status.brainDirectoryURL)
                    } else {
                        store.requestBrainFolderAccess()
                    }
                }

                permissionRow(
                    anchorTitle: "Launch at Login",
                    icon: "power.circle.fill",
                    name: "Launch at Login",
                    description: loginItemDescription,
                    statusLabel: loginItemStatusLabel,
                    statusDotColor: loginItemDotColor,
                    isRequired: false,
                    actionTitle: "Open Login Items"
                ) {
                    openLoginItemsSettings()
                }

                HStack {
                    Spacer()
                    Button {
                        refreshPermissions()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh Status")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            hasAppeared = true
            refreshPermissions()
        }
        .onDisappear {
            hasAppeared = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard hasAppeared else { return }
            refreshPermissions()
        }
    }

    private func permissionRow(
        anchorTitle: String,
        icon: String,
        name: String,
        description: String,
        statusLabel: String,
        statusDotColor: Color,
        isRequired: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .fontWeight(.medium)
                    if isRequired {
                        Text("Required")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 6, height: 6)
                Text(statusLabel)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)

            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .id(anchorTitle)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(highlightedSetting == anchorTitle ? 0.16 : 0))
                .padding(.horizontal, -6)
                .padding(.vertical, -4)
                .animation(.easeInOut(duration: 0.35), value: highlightedSetting == anchorTitle)
        }
    }

    // MARK: - Helpers

    private func refreshPermissions() {
        store.refreshConnectionStatus()
        preferences.refreshLaunchAtLoginStatus()
        loginItemStatus = SMAppService.mainApp.status
    }

    private var loginItemStatusLabel: String {
        switch loginItemStatus {
        case .enabled: return "Enabled"
        case .requiresApproval: return "Needs Approval"
        case .notRegistered, .notFound: return "Not Enabled"
        @unknown default: return "Unknown"
        }
    }

    private var loginItemDotColor: Color {
        switch loginItemStatus {
        case .enabled: return .green
        case .requiresApproval: return .orange
        case .notRegistered, .notFound: return .secondary
        @unknown default: return .secondary
        }
    }

    private var loginItemDescription: String {
        switch loginItemStatus {
        case .enabled:
            return "Registered with macOS Service Management to start automatically at sign-in."
        case .requiresApproval:
            return "Approve Grav in System Settings → General → Login Items."
        case .notRegistered, .notFound:
            return "Optional. Enable Launch at Login in General settings to start with macOS."
        @unknown default:
            return "Managed via macOS Service Management (SMAppService)."
        }
    }

    private func openLoginItemsSettings() {
        if let url = URL(string: Self.loginItemsSettingsURL) {
            NSWorkspace.shared.open(url)
        }
    }

    private func abbreviatedPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func revealBrainFolder(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            let parent = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: parent.path) {
                NSWorkspace.shared.activateFileViewerSelecting([parent])
            } else {
                NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser)
            }
        }
    }
}
