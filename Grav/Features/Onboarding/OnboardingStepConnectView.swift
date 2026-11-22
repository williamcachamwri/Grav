import SwiftUI

/// Step 1 left-rail content: live local Antigravity & `~/.gemini/antigravity/brain` diagnostics.
/// Strictly backed by real `AntigravityTelemetryStore.connectionStatus` with zero mocked state.
public struct OnboardingStepConnectRail: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public let store: AntigravityTelemetryStore

    @State private var isRefreshing = false

    public init(store: AntigravityTelemetryStore) {
        self.store = store
    }

    public var body: some View {
        let status = store.connectionStatus

        VStack(alignment: .leading, spacing: 12) {
            // Live diagnostics checklist
            VStack(spacing: 10) {
                ConnectionDiagnosticRow(
                    icon: "app.badge.checkmark",
                    title: "Antigravity Application",
                    detail: status.appURL.path,
                    badgeTitle: appBadgeTitle(status),
                    badgeTint: appBadgeTint(status),
                    isHealthy: status.isAppInstalled && status.isAppRunning
                )

                ConnectionDiagnosticRow(
                    icon: "folder.badge.gearshape",
                    title: "Brain Telemetry Directory",
                    detail: abbreviatedBrainPath(status.brainDirectoryURL),
                    badgeTitle: status.isBrainAccessible ? "Accessible" : "Access Needed",
                    badgeTint: status.isBrainAccessible ? GravPalette.emerald : GravPalette.fileEdit,
                    isHealthy: status.isBrainAccessible
                )

                ConnectionDiagnosticRow(
                    icon: "waveform.path.ecg",
                    title: "Active Conversations",
                    detail: status.isBrainAccessible
                        ? "Live transcript directory detected"
                        : "Awaiting readable brain directory",
                    badgeTitle: "\(status.activeConversationCount) live",
                    badgeTint: status.activeConversationCount > 0 ? GravPalette.glacialCyan : GravPalette.inkTertiary,
                    isHealthy: status.activeConversationCount > 0,
                    monospacedBadge: true
                )
            }

            // Contextual actions
            HStack(spacing: 8) {
                if status.needsFolderAccess || !status.isBrainAccessible {
                    ConnectActionButton(
                        title: "Grant Folder Access",
                        systemImage: "lock.open",
                        prominent: true
                    ) {
                        store.requestBrainFolderAccess()
                    }
                }

                if status.isAppInstalled {
                    ConnectActionButton(
                        title: status.isAppRunning ? "Focus Antigravity" : "Open Antigravity",
                        systemImage: "arrow.up.forward.app",
                        prominent: status.isBrainAccessible && !status.isAppRunning
                    ) {
                        store.activateAntigravityApp()
                    }
                }

                ConnectActionButton(
                    title: "Refresh Check",
                    systemImage: "arrow.clockwise",
                    prominent: false,
                    isSpinning: isRefreshing && !reduceMotion
                ) {
                    triggerRefresh()
                }
            }
            .padding(.top, 4)
        }
        .onAppear {
            store.refreshConnectionStatus()
        }
    }

    private func triggerRefresh() {
        isRefreshing = true
        store.refreshConnectionStatus()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            isRefreshing = false
        }
    }

    private func appBadgeTitle(_ status: AntigravityConnectionStatus) -> String {
        if status.isAppRunning {
            return "Running"
        }
        return status.isAppInstalled ? "Installed" : "Not Found"
    }

    private func appBadgeTint(_ status: AntigravityConnectionStatus) -> Color {
        if status.isAppRunning {
            return GravPalette.emerald
        }
        return status.isAppInstalled ? GravPalette.glacialCyan : GravPalette.coral
    }

    private func abbreviatedBrainPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

/// Step 1 right-stage mock: cropped dark macOS desktop displaying the real-time
/// connection handshake between `/Applications/Antigravity.app`, `~/.gemini/antigravity/brain`,
/// and the Grav telemetry channel.
public struct OnboardingStepConnectStage: View {
    public let store: AntigravityTelemetryStore

    public init(store: AntigravityTelemetryStore) {
        self.store = store
    }

    public var body: some View {
        let status = store.connectionStatus
        let isChannelReady = status.isAppInstalled && status.isBrainAccessible

        OnboardingStageFrame(showMenuBar: true) {
            VStack(spacing: 0) {
                Spacer(minLength: 42)

                // Live Handshake Instrument Card
                OnboardingSpecularCard(elevation: .base, cornerRadius: GravRadius.card, padding: 20) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("LOCAL TELEMETRY HANDSHAKE")
                                    .font(GravTypography.monoMicro)
                                    .tracking(1.1)
                                    .foregroundStyle(GravPalette.inkTertiary)

                                Text(handshakeHeadline(status))
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(GravPalette.inkPrimary)
                            }

                            Spacer()

                            HStack(spacing: 6) {
                                Circle()
                                    .fill(isChannelReady ? GravPalette.emerald : GravPalette.fileEdit)
                                    .frame(width: 7, height: 7)
                                Text(isChannelReady ? "READY" : "CHECKING")
                                    .font(GravTypography.monoMicro)
                                    .foregroundStyle(isChannelReady ? GravPalette.emerald : GravPalette.fileEdit)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill((isChannelReady ? GravPalette.emerald : GravPalette.fileEdit).opacity(0.12))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder((isChannelReady ? GravPalette.emerald : GravPalette.fileEdit).opacity(0.32), lineWidth: 0.5)
                            )
                        }

                        // Three-node live pipeline: Antigravity.app -> brain -> Grav
                        VStack(spacing: 0) {
                            HandshakeNodeRow(
                                label: "/Applications/Antigravity.app",
                                subtitle: status.isAppRunning
                                    ? "Process active (com.google.antigravity)"
                                    : (status.isAppInstalled ? "Bundle verified — ready to launch" : "Bundle not detected at default path"),
                                stateLabel: status.isAppRunning ? "LIVE" : (status.isAppInstalled ? "FOUND" : "MISSING"),
                                stateColor: status.isAppRunning
                                    ? GravPalette.emerald
                                    : (status.isAppInstalled ? GravPalette.glacialCyan : GravPalette.coral)
                            ) {
                                AntigravityLogoView(icon: store.antigravityIcon, size: 28)
                            }

                            HandshakeConduit(isActive: status.isAppInstalled && status.isBrainAccessible)

                            HandshakeNodeRow(
                                label: "~/.gemini/antigravity/brain",
                                subtitle: status.isBrainAccessible
                                    ? "Read access verified · \(status.activeConversationCount) session\(status.activeConversationCount == 1 ? "" : "s")"
                                    : "Grant folder read permission to stream JSONL logs",
                                stateLabel: status.isBrainAccessible ? "READABLE" : "LOCKED",
                                stateColor: status.isBrainAccessible ? GravPalette.emerald : GravPalette.fileEdit
                            ) {
                                ZStack {
                                    RoundedRectangle.grav(GravRadius.controlS)
                                        .fill(GravPalette.cardFillElevated)
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            RoundedRectangle.grav(GravRadius.controlS)
                                                .strokeBorder(GravPalette.specularStroke, lineWidth: 0.5)
                                        )
                                    Image(systemName: "internaldrive")
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(status.isBrainAccessible ? GravPalette.glacialTeal : GravPalette.fileEdit)
                                }
                            }

                            HandshakeConduit(isActive: status.isBrainAccessible)

                            HandshakeNodeRow(
                                label: "Grav Notch Telemetry Channel",
                                subtitle: isChannelReady
                                    ? "Zero-network local reader ready for Notch HUD"
                                    : "Waiting for readable Antigravity telemetry source",
                                stateLabel: isChannelReady ? "LINKED" : "STANDBY",
                                stateColor: isChannelReady ? GravPalette.glacialTeal : GravPalette.inkTertiary
                            ) {
                                GravAppIconTile(size: 28)
                            }
                        }
                    }
                }
                .frame(maxWidth: 440)
                .padding(.horizontal, 28)

                Spacer(minLength: 82)
            }
        }
    }

    private func handshakeHeadline(_ status: AntigravityConnectionStatus) -> String {
        if status.isAppRunning && status.isBrainAccessible {
            return "Antigravity telemetry link verified"
        }
        if status.isAppInstalled && status.isBrainAccessible {
            return "Ready to monitor Antigravity sessions"
        }
        if !status.isBrainAccessible {
            return "Folder read access required"
        }
        return "Looking for Antigravity.app"
    }
}

// MARK: - Supporting Components

private struct ConnectionDiagnosticRow: View {
    let icon: String
    let title: String
    let detail: String
    let badgeTitle: String
    let badgeTint: Color
    let isHealthy: Bool
    var monospacedBadge: Bool = false

    var body: some View {
        OnboardingSpecularCard(elevation: .subtle, cornerRadius: GravRadius.card, isHighlighted: false, padding: 12) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle.grav(GravRadius.controlS)
                        .fill(GravPalette.cardFillBase)
                        .frame(width: 30, height: 30)
                        .overlay(
                            RoundedRectangle.grav(GravRadius.controlS)
                                .strokeBorder(GravPalette.specularStroke, lineWidth: 0.5)
                        )
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isHealthy ? GravPalette.glacialTeal : GravPalette.inkSecondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(GravTypography.bodyMedium)
                        .foregroundStyle(GravPalette.inkPrimary)

                    Text(detail)
                        .font(GravTypography.monoMicro)
                        .foregroundStyle(GravPalette.inkTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                Text(badgeTitle)
                    .font(monospacedBadge ? GravTypography.monoMicro : GravTypography.micro)
                    .monospacedDigit()
                    .foregroundStyle(badgeTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(badgeTint.opacity(0.12))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(badgeTint.opacity(0.28), lineWidth: 0.5)
                    )
            }
        }
    }
}

private struct HandshakeNodeRow<Icon: View>: View {
    let label: String
    let subtitle: String
    let stateLabel: String
    let stateColor: Color
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        HStack(spacing: 12) {
            icon()

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(GravTypography.monoCaption)
                    .foregroundStyle(GravPalette.inkPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(subtitle)
                    .font(GravTypography.caption)
                    .foregroundStyle(GravPalette.inkTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(stateLabel)
                .font(GravTypography.monoMicro)
                .foregroundStyle(stateColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle.grav(GravRadius.controlXS)
                        .fill(stateColor.opacity(0.12))
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle.grav(GravRadius.controlM)
                .fill(GravPalette.cardFillSubtle)
        )
        .overlay(
            RoundedRectangle.grav(GravRadius.controlM)
                .strokeBorder(GravPalette.specularStroke, lineWidth: 0.5)
        )
    }
}

private struct HandshakeConduit: View {
    let isActive: Bool

    var body: some View {
        HStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: isActive
                            ? [GravPalette.glacialTeal.opacity(0.85), GravPalette.glacialCyan.opacity(0.85)]
                            : [Color.white.opacity(0.14), Color.white.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 1.5, height: 18)
                .padding(.leading, 25)
            Spacer()
        }
        .accessibilityHidden(true)
    }
}

private struct ConnectActionButton: View {
    let title: String
    let systemImage: String
    let prominent: Bool
    var isSpinning: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(isSpinning ? 360 : 0))
                    .animation(isSpinning ? .easeInOut(duration: 0.42) : .default, value: isSpinning)

                Text(title)
                    .font(GravTypography.caption)
            }
            .foregroundStyle(prominent ? GravPalette.obsidianVoid : GravPalette.inkPrimary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle.grav(GravRadius.controlS)
                    .fill(
                        prominent
                            ? AnyShapeStyle(GravPalette.brandAccentGradient)
                            : AnyShapeStyle(isHovered ? GravPalette.cardFillElevated : GravPalette.cardFillBase)
                    )
            )
            .overlay(
                RoundedRectangle.grav(GravRadius.controlS)
                    .strokeBorder(
                        prominent ? Color.white.opacity(0.35) : GravPalette.specularStroke,
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(GravMotion.rowHover) {
                isHovered = hovering
            }
        }
    }
}
