import AppKit
import SwiftUI

/// Precision editorial About pane with subtle interactive app icon elevation, live diagnostics strip,
/// architecture ledger, and quick folder/onboarding actions.
struct AboutSettingsPane: View {
    let store: AntigravityTelemetryStore
    var onReplayWelcome: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHoveringIcon = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }

    private var petsFolderURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport.appendingPathComponent("Grav/Pets", isDirectory: true)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 20) {
                heroSection

                // Live Diagnostic Strip
                HStack(spacing: 10) {
                    SettingsMetricTile(
                        label: "Notch Engine",
                        value: "NotchKit",
                        detail: "v1.3.0 · 120Hz"
                    )
                    SettingsMetricTile(
                        label: "Installed Pets",
                        value: "\(CodexPetsStore.shared.installedPets.count)",
                        detail: "codex-pets.net"
                    )
                    SettingsMetricTile(
                        label: "Bridge",
                        value: store.connectionStatus.isBrainAccessible ? "Ready" : "Standby",
                        detail: "kqueue · 0% idle",
                        accentDot: store.connectionStatus.isBrainAccessible ? GravPalette.emerald : .orange
                    )
                }
                .frame(maxWidth: 520)

                SettingsCardGroup(title: "Architecture", staggerIndex: 1) {
                    infoRow(label: "Platform", value: "macOS 14+ Native SwiftUI / AppKit")
                    SettingsRowDivider()
                    infoRow(label: "Telemetry Source", value: "Local kqueue + SQLite WAL")
                    SettingsRowDivider()
                    infoRow(label: "Interface", value: "Liquid Glass & Precision Craft")
                    SettingsRowDivider()
                    infoRow(label: "Global Hotkeys", value: "Carbon RegisterEventHotKey")
                }
                .frame(maxWidth: 520)

                SettingsCardGroup(title: "Resources & Walkthrough", staggerIndex: 2) {
                    SettingRow(
                        title: "Welcome Experience",
                        description: "Revisit the animated aurora welcome, Notch HUD demo, and Mini Pet setup."
                    ) {
                        SettingsActionPill(title: "Replay Welcome", systemImage: "arrow.counterclockwise") {
                            onReplayWelcome?()
                        }
                    }

                    SettingsRowDivider()

                    SettingRow(
                        title: "Antigravity Brain Directory",
                        description: "~/.gemini/antigravity/brain"
                    ) {
                        SettingsActionPill(title: "Reveal", systemImage: "folder") {
                            revealFolder(store.connectionStatus.brainDirectoryURL)
                        }
                    }

                    SettingsRowDivider()

                    SettingRow(
                        title: "Installed Pets Folder",
                        description: "~/Library/Application Support/Grav/Pets"
                    ) {
                        SettingsActionPill(title: "Reveal", systemImage: "pawprint") {
                            revealFolder(petsFolderURL)
                        }
                    }
                }
                .frame(maxWidth: 520)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 26)
            .padding(.vertical, 26)
        }
    }

    private var heroSection: some View {
        VStack(spacing: 11) {
            GravAppIconTile(size: 86)
                .scaleEffect(!reduceMotion && isHoveringIcon ? 1.05 : 1.0)
                .rotation3DEffect(
                    .degrees(!reduceMotion && isHoveringIcon ? 5 : 0),
                    axis: (x: -1, y: 1, z: 0),
                    perspective: 0.55
                )
                .shadow(color: Color.black.opacity(0.28), radius: 16, y: 8)
                .animation(reduceMotion ? nil : .spring(duration: 0.30, bounce: 0.28), value: isHoveringIcon)
                .onHover { isHoveringIcon = $0 }

            VStack(spacing: 3) {
                Text(verbatim: "Grav")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .tracking(-0.4)

                Text("Live flight-deck telemetry & desktop companion for Google Antigravity")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            HStack(spacing: 6) {
                Text(appVersion)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(store.connectionStatus.isBrainAccessible ? "Local Telemetry Ready" : "Standby")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6)
                    )
            )
        }
        .padding(.bottom, 4)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .center) {
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 20)
            Text(value)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10.5)
    }

    private func revealFolder(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            let parent = url.deletingLastPathComponent()
            NSWorkspace.shared.open(FileManager.default.fileExists(atPath: parent.path) ? parent : FileManager.default.homeDirectoryForCurrentUser)
        }
    }
}
