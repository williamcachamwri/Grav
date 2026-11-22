import AppKit
import SwiftUI

/// Live Antigravity Telemetry settings section displaying real-time connection status,
/// local brain directory path, pause/resume control, and quick actions.
public struct AntigravityTelemetrySettingsSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Bindable public var preferences: PreferencesStore
    public var store: AntigravityTelemetryStore

    @State private var didCopyBrainPath = false

    public init(
        preferences: PreferencesStore,
        store: AntigravityTelemetryStore
    ) {
        self.preferences = preferences
        self.store = store
    }

    public var body: some View {
        let palette = GravAdaptivePalette(colorScheme: colorScheme)
        let status = store.connectionStatus
        let statusInfo = resolvedConnectionSummary(status: status)

        SettingsSectionCard(
            title: "Antigravity Telemetry",
            systemImage: "waveform.path.ecg",
            footer: "Grav reads local Antigravity transcripts directly from disk. No network calls or background polling timers are used when idle."
        ) {
            // Connection status row
            HStack(spacing: GravSpacing.md) {
                AntigravityLogoView(icon: store.antigravityIcon, size: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Antigravity Runtime")
                        .font(GravTypography.bodyMedium)
                        .foregroundStyle(palette.inkPrimary)

                    Text(statusInfo.detail)
                        .font(GravTypography.caption)
                        .foregroundStyle(palette.inkTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: GravSpacing.sm)

                HStack(spacing: GravSpacing.xs) {
                    SemanticDot(
                        tone: statusInfo.tone,
                        size: 6,
                        isActive: statusInfo.isActive,
                        showPulse: true,
                        adaptive: true
                    )

                    Text(statusInfo.label)
                        .font(GravTypography.caption)
                        .foregroundStyle(palette.inkSecondary)
                }

                Button {
                    store.refreshConnectionStatus()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.gravGhostIcon(size: 24, radius: GravRadius.controlXS))
                .help("Refresh Antigravity connection status")
                .accessibilityLabel("Refresh Antigravity connection status")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            SettingsRowDivider()

            // Brain directory path row
            VStack(alignment: .leading, spacing: GravSpacing.xs) {
                HStack(spacing: GravSpacing.sm) {
                    Text("Brain Directory")
                        .font(GravTypography.bodyMedium)
                        .foregroundStyle(palette.inkPrimary)

                    Spacer(minLength: GravSpacing.sm)

                    Button {
                        copyBrainPath(status.brainDirectoryURL.path)
                    } label: {
                        Image(systemName: didCopyBrainPath ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.gravGhostIcon(size: 24, radius: GravRadius.controlXS, isActive: didCopyBrainPath))
                    .help("Copy brain directory path")
                    .accessibilityLabel("Copy brain directory path")
                }

                Text(abbreviatedPath(status.brainDirectoryURL))
                    .font(GravTypography.monoCaption)
                    .foregroundStyle(palette.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(status.brainDirectoryURL.path)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlassSurface(
                        elevation: .subtle,
                        radius: GravRadius.controlS,
                        adaptive: true,
                        includeBorder: true
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            if status.needsFolderAccess {
                SettingsRowDivider()

                HStack(spacing: GravSpacing.sm) {
                    SettingsInlineNotice(
                        tone: .fileEdit,
                        message: "Folder access is needed to read Antigravity transcripts."
                    )

                    Button("Grant Access") {
                        store.requestBrainFolderAccess()
                    }
                    .buttonStyle(.gravGlass(horizontalPadding: 10, verticalPadding: 5))
                    .padding(.trailing, 14)
                }
                .background(palette.fillSubtle)
            }

            SettingsRowDivider()

            // Pause / Resume telemetry row
            SettingsControlRow(
                title: "Telemetry Monitoring",
                subtitle: isPaused
                    ? "Paused — live transcript updates are muted until resumed."
                    : "Streaming local thinking, file diffs, and command output."
            ) {
                Button(isPaused ? "Resume" : "Pause") {
                    let nextPaused = !isPaused
                    preferences.isTelemetryPaused = nextPaused
                    store.setPaused(nextPaused)
                }
                .buttonStyle(.gravGlass(horizontalPadding: 12, verticalPadding: 5))
            }

            SettingsRowDivider()

            // Quick actions row
            HStack(spacing: GravSpacing.sm) {
                Button {
                    store.activateAntigravityApp()
                } label: {
                    HStack(spacing: GravSpacing.xs) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 11, weight: .medium))
                        Text("Open Antigravity")
                    }
                }
                .buttonStyle(.gravGlass(horizontalPadding: 11, verticalPadding: 6))

                Button {
                    revealBrainFolder(status.brainDirectoryURL)
                } label: {
                    HStack(spacing: GravSpacing.xs) {
                        Image(systemName: "folder")
                            .font(.system(size: 11, weight: .medium))
                        Text("Reveal Brain Folder")
                    }
                }
                .buttonStyle(.gravGlass(horizontalPadding: 11, verticalPadding: 6))

                Spacer(minLength: 0)

                if store.tokenMetrics.totalTokens > 0 {
                    Text("\(TokenMetrics.formatCompact(store.tokenMetrics.totalTokens)) tok")
                        .font(GravTypography.monoCaption)
                        .monospacedDigit()
                        .foregroundStyle(palette.inkTertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .onAppear {
            store.refreshConnectionStatus()
        }
    }

    private var isPaused: Bool {
        store.isPaused || preferences.isTelemetryPaused
    }

    private struct ConnectionSummary {
        let label: String
        let detail: String
        let tone: SemanticDotTone
        let isActive: Bool
    }

    private func resolvedConnectionSummary(status: AntigravityConnectionStatus) -> ConnectionSummary {
        if isPaused {
            return ConnectionSummary(
                label: "Paused",
                detail: "Telemetry capture is paused by user preference",
                tone: .idle,
                isActive: false
            )
        }

        if status.needsFolderAccess {
            return ConnectionSummary(
                label: "Access Needed",
                detail: "Grant read permission to ~/.gemini/antigravity/brain",
                tone: .fileEdit,
                isActive: false
            )
        }

        if status.isAppRunning && status.isBrainAccessible {
            let count = max(status.activeConversationCount, store.sessions.count)
            let sessionText = count == 1 ? "1 conversation" : "\(count) conversations"
            let stateText = store.state.isActive ? store.state.label : "Monitoring"
            return ConnectionSummary(
                label: stateText,
                detail: "Running · \(sessionText) indexed",
                tone: store.state.isActive ? SemanticDotTone(telemetryState: store.state) : .success,
                isActive: store.state.isActive
            )
        }

        if status.isAppInstalled {
            if status.isBrainAccessible {
                let count = max(status.activeConversationCount, store.sessions.count)
                let sessionText = count == 1 ? "1 conversation" : "\(count) conversations"
                return ConnectionSummary(
                    label: "Standby",
                    detail: "Installed · \(sessionText) available locally",
                    tone: .thinking,
                    isActive: false
                )
            }
            return ConnectionSummary(
                label: "Installed",
                detail: "Launch Antigravity to initialize local telemetry",
                tone: .idle,
                isActive: false
            )
        }

        return ConnectionSummary(
            label: "Not Found",
            detail: "Expected at /Applications/Antigravity.app",
            tone: .error,
            isActive: false
        )
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

    private func copyBrainPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)

        if reduceMotion {
            didCopyBrainPath = true
        } else {
            withAnimation(GravMotion.subtleFade) {
                didCopyBrainPath = true
            }
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if reduceMotion {
                didCopyBrainPath = false
            } else {
                withAnimation(GravMotion.subtleFade) {
                    didCopyBrainPath = false
                }
            }
        }
    }
}
