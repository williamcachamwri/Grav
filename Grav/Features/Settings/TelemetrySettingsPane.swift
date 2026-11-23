import AppKit
import SwiftUI

/// Precision Canvas Telemetry pane with a live 3-metric Flight Deck strip (Live State, Active Model,
/// Rolling Token Flow & Context Meter) plus Antigravity Runtime and Session Monitoring cards.
struct TelemetrySettingsPane: View {
    @Bindable var preferences: PreferencesStore
    let store: AntigravityTelemetryStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didCopyBrainPath = false

    var body: some View {
        let status = store.connectionStatus

        SettingsPageCanvas(
            tab: .telemetry,
            subtitle: "Zero-polling local kqueue & SQLite WAL bridge to Google Antigravity."
        ) {
            HStack(spacing: 6) {
                SettingsActionPill(title: "Refresh", systemImage: "arrow.clockwise") {
                    store.refreshConnectionStatus()
                }
                SettingsActionPill(
                    title: status.isAppRunning ? "Focus Antigravity" : "Open Antigravity",
                    systemImage: "arrow.up.forward.app"
                ) {
                    store.activateAntigravityApp()
                }
            }
        } content: {
            // Live Telemetry Flight-Deck Strip (pure precision instrumentation)
            SettingsCardGroup(
                title: "Live Session Flight Deck",
                badge: store.isPaused ? "PAUSED" : (store.state.isActive ? "STREAMING" : "IDLE"),
                staggerIndex: 0,
                contentPadding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        SettingsMetricTile(
                            label: "State",
                            value: store.isPaused ? "Paused" : store.state.label,
                            detail: store.executionMode.rawValue,
                            accentDot: runtimeDotColor(for: status)
                        )

                        SettingsMetricTile(
                            label: "Active Model",
                            value: shortModelName,
                            detail: store.tokenMetrics.lastTurnTokensPerSecond.map { "\(Int($0.rounded())) tok/s" } ?? "Waiting"
                        )

                        SettingsMetricTile(
                            label: "Token Flow",
                            value: TokenMetrics.formatCompact(store.tokenMetrics.totalTokens),
                            detail: "↓\(TokenMetrics.formatCompact(store.tokenMetrics.inputTokens)) · ↑\(TokenMetrics.formatCompact(store.tokenMetrics.outputTokens))"
                        )
                    }

                    if store.tokenMetrics.latestContextTokens > 0 {
                        let ratio = store.tokenMetrics.contextFillRatio
                        let pct = Int((ratio * 100.0).rounded())
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("Context Window")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(
                                    verbatim: "\(TokenMetrics.formatCompact(store.tokenMetrics.latestContextTokens)) / \(TokenMetrics.formatCompact(store.tokenMetrics.contextWindowLimit)) (\(pct)%)"
                                )
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(store.tokenMetrics.isContextNearCompaction ? GravPalette.fileEdit : .secondary)
                            }

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule(style: .continuous)
                                        .fill(Color.primary.opacity(0.08))
                                    Capsule(style: .continuous)
                                        .fill(store.tokenMetrics.isContextNearCompaction ? GravPalette.fileEdit : GravPalette.glacialCyan)
                                        .frame(width: max(6, geo.size.width * ratio))
                                        .animation(reduceMotion ? nil : .spring(duration: 0.42, bounce: 0.08), value: ratio)
                                }
                            }
                            .frame(height: 4)
                        }
                        .padding(.horizontal, 2)
                    }
                }
            }

            SettingsCardGroup(title: "Antigravity Runtime", staggerIndex: 1) {
                SettingRow(
                    title: "Antigravity App",
                    description: runtimeDescription(for: status),
                    descriptionStyle: .subtitle
                ) {
                    HStack(spacing: 8) {
                        AntigravityLogoView(icon: store.antigravityIcon, size: 19)

                        HStack(spacing: 5) {
                            Circle()
                                .fill(runtimeDotColor(for: status))
                                .frame(width: 6, height: 6)

                            Text(runtimeStatusLabel(for: status))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SettingsRowDivider()

                SettingRow(
                    title: "Brain Directory",
                    description: abbreviatedPath(status.brainDirectoryURL),
                    descriptionStyle: .subtitle
                ) {
                    HStack(spacing: 6) {
                        SettingsActionPill(
                            title: didCopyBrainPath ? "Copied" : "Copy",
                            systemImage: didCopyBrainPath ? "checkmark" : "doc.on.doc"
                        ) {
                            copyBrainPath(status.brainDirectoryURL.path)
                        }

                        if status.needsFolderAccess {
                            SettingsActionPill(title: "Grant Access", systemImage: "lock.open", prominent: true) {
                                store.requestBrainFolderAccess()
                            }
                        }

                        SettingsActionPill(title: "Reveal", systemImage: "folder") {
                            revealBrainFolder(status.brainDirectoryURL)
                        }
                    }
                }
            }

            SettingsCardGroup(title: "Sessions & Monitoring", staggerIndex: 2) {
                SettingRow(
                    title: "Active Conversations",
                    description: conversationSummary(for: status),
                    descriptionStyle: .subtitle
                ) {
                    Text("\(conversationCount(for: status))")
                        .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                }

                if !store.sessions.isEmpty {
                    SettingsRowDivider()

                    SettingRow(
                        title: "Active Session",
                        description: "Pin a specific local conversation to stream into the Notch HUD."
                    ) {
                        Picker("", selection: activeSessionBinding) {
                            ForEach(store.sessions) { session in
                                Text(cleanSessionTitle(session.title))
                                    .tag(session.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: 220)
                    }
                }

                SettingsRowDivider()

                SettingRow(
                    title: "Pause Telemetry",
                    description: "Stop watching local transcripts and task logs until resumed."
                ) {
                    Toggle("", isOn: pauseTelemetryBinding)
                        .labelsHidden()
                }
            }
        }
        .onAppear {
            store.refreshConnectionStatus()
        }
    }

    // MARK: - Bindings & Helpers

    private var shortModelName: String {
        guard let raw = store.activeModel, !raw.isEmpty else { return "Standby" }
        return raw
    }

    private func cleanSessionTitle(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "<USER_REQUEST>", with: "")
            .replacingOccurrences(of: "</USER_REQUEST>", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Active Session" : cleaned
    }

    private var pauseTelemetryBinding: Binding<Bool> {
        Binding(
            get: { store.isPaused || preferences.isTelemetryPaused },
            set: { paused in
                preferences.isTelemetryPaused = paused
                store.setPaused(paused)
            }
        )
    }

    private var activeSessionBinding: Binding<String> {
        Binding(
            get: { store.activeSession?.id ?? store.sessions.first?.id ?? "" },
            set: { selectedID in
                if let match = store.sessions.first(where: { $0.id == selectedID }) {
                    store.selectSession(match)
                }
            }
        )
    }

    private func conversationCount(for status: AntigravityConnectionStatus) -> Int {
        max(status.activeConversationCount, store.sessions.count)
    }

    private func conversationSummary(for status: AntigravityConnectionStatus) -> String {
        if !status.isBrainAccessible {
            return "Grant access to ~/.gemini/antigravity/brain to discover conversations."
        }
        let count = conversationCount(for: status)
        if count == 0 { return "No local transcript logs found yet." }
        return count == 1 ? "1 local conversation workspace indexed." : "\(count) local conversation workspaces indexed."
    }

    private func runtimeStatusLabel(for status: AntigravityConnectionStatus) -> String {
        if store.isPaused || preferences.isTelemetryPaused { return "Paused" }
        if status.isAppRunning { return "Running" }
        if status.isAppInstalled { return "Installed" }
        return "Not Found"
    }

    private func runtimeDotColor(for status: AntigravityConnectionStatus) -> Color {
        if store.isPaused || preferences.isTelemetryPaused { return .secondary }
        if status.isAppRunning && status.isBrainAccessible { return GravPalette.emerald }
        if status.isAppInstalled { return .orange }
        return .red
    }

    private func runtimeDescription(for status: AntigravityConnectionStatus) -> String {
        if status.isAppRunning {
            return "Detected at \(status.appURL.path) · Event-driven kqueue + SQLite WAL"
        }
        if status.isAppInstalled {
            return "Installed at \(status.appURL.path) · Launch Antigravity for live streaming"
        }
        return "Expected at /Applications/Antigravity.app"
    }

    private func abbreviatedPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }

    private func revealBrainFolder(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            let parent = url.deletingLastPathComponent()
            NSWorkspace.shared.open(FileManager.default.fileExists(atPath: parent.path) ? parent : FileManager.default.homeDirectoryForCurrentUser)
        }
    }

    private func copyBrainPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        didCopyBrainPath = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            didCopyBrainPath = false
        }
    }
}
