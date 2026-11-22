import AppKit
import SwiftUI

/// Native grouped-form Telemetry preferences pane backed by live `AntigravityTelemetryStore` state.
struct TelemetrySettingsPane: View {
    @Bindable var preferences: PreferencesStore
    let store: AntigravityTelemetryStore

    @State private var didCopyBrainPath = false

    var body: some View {
        let status = store.connectionStatus

        Form {
            Section("Antigravity Runtime") {
                SettingRow(
                    title: "Antigravity App",
                    description: runtimeDescription(for: status),
                    descriptionStyle: .subtitle
                ) {
                    HStack(spacing: 8) {
                        AntigravityLogoView(icon: store.antigravityIcon, size: 20)

                        HStack(spacing: 5) {
                            Circle()
                                .fill(runtimeDotColor(for: status))
                                .frame(width: 6, height: 6)

                            Text(runtimeStatusLabel(for: status))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            store.refreshConnectionStatus()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh Antigravity connection status")

                        Button(status.isAppRunning ? "Focus" : "Open") {
                            store.activateAntigravityApp()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                }

                SettingRow(
                    title: "Brain Directory",
                    description: abbreviatedPath(status.brainDirectoryURL),
                    descriptionStyle: .subtitle
                ) {
                    HStack(spacing: 6) {
                        Button {
                            copyBrainPath(status.brainDirectoryURL.path)
                        } label: {
                            Image(systemName: didCopyBrainPath ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderless)
                        .help(didCopyBrainPath ? "Copied" : "Copy brain directory path")

                        if status.needsFolderAccess {
                            Button("Grant Access") {
                                store.requestBrainFolderAccess()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                        }

                        Button("Reveal") {
                            revealBrainFolder(status.brainDirectoryURL)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                }
            }

            Section("Sessions & Monitoring") {
                SettingRow(
                    title: "Active Conversations",
                    description: conversationSummary(for: status),
                    descriptionStyle: .subtitle
                ) {
                    Text("\(conversationCount(for: status))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }

                if !store.sessions.isEmpty {
                    SettingRow(
                        title: "Active Session",
                        description: "Pin a specific local conversation to stream into the Notch HUD."
                    ) {
                        Picker("", selection: activeSessionBinding) {
                            ForEach(store.sessions) { session in
                                Text(session.title)
                                    .tag(session.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: 220)
                    }
                }

                SettingRow(
                    title: "Pause Telemetry",
                    description: "Stop watching local transcripts and task logs until resumed."
                ) {
                    Toggle("", isOn: pauseTelemetryBinding)
                        .labelsHidden()
                }
            }

            Section("Session Metrics") {
                SettingRow(
                    title: "Active Model",
                    description: "Model reported by the most recent Antigravity planner step."
                ) {
                    Text(store.activeModel ?? "Waiting for activity")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(store.activeModel == nil ? .secondary : .primary)
                        .lineLimit(1)
                }

                SettingRow(
                    title: "Token Totals",
                    description: tokenBreakdownSubtitle,
                    descriptionStyle: .subtitle
                ) {
                    Text(TokenMetrics.formatCompact(store.tokenMetrics.totalTokens))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            store.refreshConnectionStatus()
        }
    }

    // MARK: - Bindings

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

    // MARK: - Formatting

    private func conversationCount(for status: AntigravityConnectionStatus) -> Int {
        max(status.activeConversationCount, store.sessions.count)
    }

    private func conversationSummary(for status: AntigravityConnectionStatus) -> String {
        if !status.isBrainAccessible {
            return "Grant access to ~/.gemini/antigravity/brain to discover conversations."
        }
        let count = conversationCount(for: status)
        if count == 0 {
            return "No local transcript logs found yet."
        }
        return count == 1
            ? "1 local conversation workspace indexed."
            : "\(count) local conversation workspaces indexed."
    }

    private func runtimeStatusLabel(for status: AntigravityConnectionStatus) -> String {
        if store.isPaused || preferences.isTelemetryPaused {
            return "Paused"
        }
        if status.isAppRunning {
            return "Running"
        }
        if status.isAppInstalled {
            return "Installed"
        }
        return "Not Found"
    }

    private func runtimeDotColor(for status: AntigravityConnectionStatus) -> Color {
        if store.isPaused || preferences.isTelemetryPaused {
            return .secondary
        }
        if status.isAppRunning && status.isBrainAccessible {
            return .green
        }
        if status.isAppInstalled {
            return .orange
        }
        return .red
    }

    private func runtimeDescription(for status: AntigravityConnectionStatus) -> String {
        if status.isAppRunning {
            return "Detected at \(status.appURL.path) · Event-driven kqueue observation"
        }
        if status.isAppInstalled {
            return "Installed at \(status.appURL.path) · Launch Antigravity for live streaming"
        }
        return "Expected at /Applications/Antigravity.app"
    }

    private var tokenBreakdownSubtitle: String {
        let metrics = store.tokenMetrics
        guard metrics.totalTokens > 0 else {
            return "Input, cache read, and output counts populate as planner steps arrive."
        }
        let input = TokenMetrics.formatCompact(metrics.inputTokens)
        let cache = TokenMetrics.formatCompact(metrics.cacheReadTokens)
        let output = TokenMetrics.formatCompact(metrics.outputTokens)
        return "Input \(input) · Cache \(cache) · Output \(output)"
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
        didCopyBrainPath = true

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            didCopyBrainPath = false
        }
    }
}
