//
//  GravOnboardingMockScenes.swift
//  Grav
//
//  Three interactive macOS Desktop Spaces hosted inside `GravOnboardingMockHost`:
//  - Space 0: Live Antigravity connection & local telemetry bridge verifier (`store.connectionStatus`)
//  - Space 1: Interactive miniature MacBook Notch HUD morphing between collapsed pill & 3-tab HUD
//  - Space 2: Mock macOS System Settings window bound live to `PreferencesStore`
//

import NotchKit
import SwiftUI

// MARK: - Space 0: Connect to Antigravity (Live Telemetry Handshake)

struct GravMockConnectScene: View {
    @ObservedObject var state: GravOnboardingState
    let store: AntigravityTelemetryStore

    @State private var isRefreshHovered = false
    @State private var isOpenHovered = false
    @State private var isGrantHovered = false

    private var status: AntigravityConnectionStatus {
        store.connectionStatus
    }

    private var isFullyConnected: Bool {
        status.isAppInstalled && status.isBrainAccessible
    }

    var body: some View {
        ZStack {
            GravMockWallpaper(app: .antigravity).equatable()

            VStack(spacing: 0) {
                connectWindow
                    .padding(.top, GravMockScene.windowTopInset + 18)
                    .padding(.horizontal, GravMockScene.windowInset)

                Spacer(minLength: 0)
            }
        }
        .onAppear {
            store.refreshConnectionStatus()
            state.syncConnectionStatus(store.connectionStatus)
        }
        .onChange(of: store.connectionStatus) { _, updated in
            state.syncConnectionStatus(updated)
        }
    }

    private var connectWindow: some View {
        VStack(spacing: 0) {
            // Ultra-clean macOS Instrument Titlebar
            HStack(spacing: 10) {
                GravMockTrafficLights(size: 8.5, spacing: 5.5)

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    NotchSemanticDot(
                        color: isFullyConnected ? GravPalette.emerald : GravPalette.fileEdit,
                        size: 5,
                        isPulsing: isFullyConnected && !GravMotionPreferences.shared.reduceMotion
                    )
                    Text(isFullyConnected ? "LOCAL BRIDGE ACTIVE" : "AWAITING BRIDGE")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(Color.white.opacity(0.62))
                }

                Spacer(minLength: 0)

                Button {
                    GravOnboardingWelcomeAudio.shared.playButtonTap()
                    store.refreshConnectionStatus()
                    state.recordConnectionRefresh(store.connectionStatus)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(isRefreshHovered ? 0.90 : 0.44))
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(isRefreshHovered ? Color.white.opacity(0.08) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .onHover { isRefreshHovered = $0 }
                .help("Re-scan Antigravity bridge")
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Color(red: 0.064, green: 0.068, blue: 0.080))

            Rectangle()
                .fill(Color.white.opacity(0.075))
                .frame(height: 0.5)

            // Centerpiece: Live Optical Signal Conduit (Antigravity Node ──▶ Grav Notch Node)
            VStack(spacing: 16) {
                HStack(alignment: .center, spacing: 0) {
                    // Source Node: Antigravity Desktop
                    bridgeHardwareNode(
                        title: "Antigravity",
                        subtitle: status.isAppRunning ? "Running" : (status.isAppInstalled ? "Installed" : "Not Found"),
                        isPositive: status.isAppInstalled
                    ) {
                        AntigravityLogoView(icon: store.antigravityIcon, size: 30)
                    }

                    // Live Animated Optical Fiber Conduit
                    opticalSignalConduit
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 18)

                    // Target Node: Grav Notch HUD
                    bridgeHardwareNode(
                        title: "Grav Notch",
                        subtitle: isFullyConnected ? "Streaming" : "Standby",
                        isPositive: isFullyConnected
                    ) {
                        GravAppIconTile(size: 30)
                    }
                }
                .padding(.top, 18)
                .padding(.horizontal, 20)

                // Hairline Divider
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 0.5)
                    .padding(.horizontal, 16)

                // Precision 3-Column Apple Instruments Metric Strip (Zero Repetitive Cards!)
                HStack(spacing: 0) {
                    bridgeMetricColumn(
                        label: "RUNTIME",
                        value: status.isAppRunning ? "Active" : (status.isAppInstalled ? "Ready" : "Missing"),
                        accent: status.isAppRunning ? GravPalette.emerald : (status.isAppInstalled ? Color.white.opacity(0.84) : GravPalette.fileEdit)
                    )

                    bridgeVerticalRule

                    bridgeMetricColumn(
                        label: "BRAIN ACCESS",
                        value: status.isBrainAccessible ? "kqueue R/O" : "Locked",
                        accent: status.isBrainAccessible ? Color.white.opacity(0.88) : GravPalette.fileEdit
                    )

                    bridgeVerticalRule

                    bridgeMetricColumn(
                        label: "CONVERSATIONS",
                        value: "\(status.activeConversationCount)",
                        accent: Color.white.opacity(0.94),
                        isNumeric: true
                    )
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
            .background(
                ZStack {
                    Color(red: 0.048, green: 0.052, blue: 0.062)
                    RadialGradient(
                        colors: [
                            (isFullyConnected ? GravPalette.glacialCyan : GravPalette.fileEdit).opacity(0.065),
                            Color.clear,
                        ],
                        center: .top,
                        startRadius: 10,
                        endRadius: 210
                    )
                }
            )

            Rectangle()
                .fill(Color.white.opacity(0.075))
                .frame(height: 0.5)

            // Whisper-Quiet Live Session Footer + Subtle Dark Glass Action
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(isFullyConnected ? GravPalette.glacialCyan : Color.white.opacity(0.32))

                    Text(
                        store.activeSession?.title
                            ?? (status.isBrainAccessible
                                ? "~/.gemini/antigravity/brain/"
                                : "Grant read access to ~/.gemini/antigravity/brain/")
                    )
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.56))
                    .lineLimit(1)
                    .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                if !status.isBrainAccessible || status.needsFolderAccess {
                    Button {
                        GravOnboardingWelcomeAudio.shared.playButtonTap()
                        store.requestBrainFolderAccess()
                        state.recordConnectionRefresh(store.connectionStatus)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Grant Access")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(Color.white.opacity(0.94))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(GravPalette.fileEdit.opacity(isGrantHovered ? 0.90 : 0.78))
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { isGrantHovered = $0 }
                } else if status.isAppInstalled {
                    Button {
                        GravOnboardingWelcomeAudio.shared.playButtonTap()
                        store.activateAntigravityApp()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Open Antigravity")
                                .font(.system(size: 10, weight: .medium))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.56))
                        }
                        .foregroundStyle(Color.white.opacity(0.90))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isOpenHovered ? Color.white.opacity(0.13) : Color.white.opacity(0.075))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { isOpenHovered = $0 }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(Color(red: 0.060, green: 0.064, blue: 0.075))
        }
        .frame(maxWidth: 496)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.16), Color.white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: Color.black.opacity(0.62), radius: 30, x: 0, y: 16)
        .shadow(color: Color.black.opacity(0.24), radius: 5, x: 0, y: 2)
    }

    private func bridgeHardwareNode<Icon: View>(
        title: String,
        subtitle: String,
        isPositive: Bool,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.white.opacity(0.045))
                    .frame(width: 52, height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.16), Color.white.opacity(0.04)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.5
                            )
                    )
                icon()
            }

            VStack(spacing: 1.5) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(-0.15)
                    .foregroundStyle(Color.white.opacity(0.92))
                Text(subtitle)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(isPositive ? GravPalette.emerald.opacity(0.86) : Color.white.opacity(0.40))
            }
        }
        .frame(width: 88)
    }

    private var opticalSignalConduit: some View {
        let reduced = GravMotionPreferences.shared.reduceMotion
        return VStack(spacing: 7) {
            Text("~/.gemini/antigravity/brain")
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.34))
                .lineLimit(1)

            GeometryReader { geo in
                let width = max(1, geo.size.width)
                ZStack(alignment: .leading) {
                    // Hairline optical rail
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .frame(height: 1.5)

                    if isFullyConnected && !reduced {
                        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                            let t = context.date.timeIntervalSinceReferenceDate
                            let p1 = (t.truncatingRemainder(dividingBy: 2.2)) / 2.2
                            let p2 = ((t + 1.1).truncatingRemainder(dividingBy: 2.2)) / 2.2
                            let pulseWidth: CGFloat = 46

                            ZStack(alignment: .leading) {
                                conduitPulse(progress: p1, trackWidth: width, pulseWidth: pulseWidth)
                                conduitPulse(progress: p2, trackWidth: width, pulseWidth: pulseWidth)
                            }
                        }
                    } else if isFullyConnected {
                        Capsule(style: .continuous)
                            .fill(GravPalette.glacialCyan.opacity(0.55))
                            .frame(height: 1.5)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .clipped()
            }
            .frame(height: 8)

            Text(isFullyConnected ? "0% idle CPU · event-driven" : "Waiting for permissions")
                .font(.system(size: 8.5, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.32))
                .lineLimit(1)
        }
    }

    private func conduitPulse(progress: Double, trackWidth: CGFloat, pulseWidth: CGFloat) -> some View {
        let x = -pulseWidth + CGFloat(progress) * (trackWidth + pulseWidth)
        return Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.clear,
                        GravPalette.glacialCyan.opacity(0.75),
                        Color.white.opacity(0.95),
                        Color.clear,
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: pulseWidth, height: 2)
            .offset(x: x)
    }

    private var bridgeVerticalRule: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(width: 0.5, height: 28)
    }

    private func bridgeMetricColumn(
        label: String,
        value: String,
        accent: Color,
        isNumeric: Bool = false
    ) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(Color.white.opacity(0.34))

            Text(verbatim: value)
                .font(
                    isNumeric
                        ? .system(size: 13.5, weight: .semibold, design: .monospaced)
                        : .system(size: 11.5, weight: .medium)
                )
                .monospacedDigit()
                .foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Space 1: Meet Your Notch HUD (Interactive Miniature MacBook Notch)

struct GravMockNotchScene: View {
    @ObservedObject var state: GravOnboardingState

    private var isExpanded: Bool {
        state.isMockNotchExpanded
    }

    var body: some View {
        ZStack(alignment: .top) {
            GravMockWallpaper(app: .notchHud).equatable()

            // 1:1 Antigravity Desktop Window framing the interactive Notch HUD above
            workspaceBackdropWindow
                .padding(.top, 64)
                .padding(.horizontal, 18)
                .opacity(isExpanded ? 0.42 : 0.98)
                .scaleEffect(isExpanded ? 0.985 : 1.0)
                .animation(GravMotionPreferences.shared.spec(.morph).animation, value: isExpanded)

            // Bottom-leading interactive stage button (keeps clear of bottom-right action bar)
            VStack {
                Spacer()
                HStack {
                    GravMockSceneButton(
                        title: isExpanded ? "Next Telemetry Tab" : "Expand Notch HUD",
                        symbol: isExpanded ? "arrow.right.circle.fill" : "macbook"
                    ) {
                        state.advanceMockNotchDemo()
                    }
                    .padding(.leading, GravMockScene.windowInset)
                    .padding(.bottom, GravOnboardingMetrics.gutter - 10)

                    Spacer()
                }
            }
        }
    }

    /// 1:1 pixel-faithful macOS Antigravity desktop application window matching the real
    /// Antigravity dark obsidian shell, sidebar, step rail, Analyzed/Edited timeline, and composer.
    private var workspaceBackdropWindow: some View {
        VStack(spacing: 0) {
            // Top Window Titlebar
            HStack(spacing: 8) {
                GravMockTrafficLights(size: 8, spacing: 5)

                HStack(spacing: 7) {
                    Image(systemName: "sidebar.left")
                    Image(systemName: "arrow.left")
                    Image(systemName: "arrow.right")
                        .opacity(0.45)
                    Image(systemName: "magnifyingglass")
                }
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.56))
                .padding(.leading, 4)

                Text("Grav Telemetry Companion App")
                    .font(.system(size: 9.5, weight: .medium))
                    .tracking(-0.1)
                    .foregroundStyle(Color.white.opacity(0.84))
                    .lineLimit(1)
                    .padding(.leading, 18)

                Spacer(minLength: 6)

                HStack(spacing: 8) {
                    Image(systemName: "ellipsis")
                        .rotationEffect(.degrees(90))
                    Image(systemName: "list.bullet.rectangle")
                    Image(systemName: "sidebar.right")
                }
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.52))
            }
            .padding(.horizontal, 11)
            .frame(height: 27)
            .background(Color(red: 0.062, green: 0.066, blue: 0.078))

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)

            // Main Split Body: Left Antigravity Sidebar + Pure Obsidian Conversation Canvas
            HStack(spacing: 0) {
                antigravitySidebar

                Rectangle()
                    .fill(Color.white.opacity(0.075))
                    .frame(width: 0.5)

                antigravityChatCanvas
            }
        }
        .frame(maxWidth: 534, maxHeight: 374)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.white.opacity(0.11), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.62), radius: 28, y: 14)
        .shadow(color: Color.black.opacity(0.28), radius: 5, y: 2)
    }

    private var antigravitySidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            // `+ New Conversation` dark bordered pill
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .semibold))
                Text("New Conversation")
                    .font(.system(size: 8.5, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.white.opacity(0.86))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            )

            VStack(alignment: .leading, spacing: 5.5) {
                sidebarNavRow(icon: "clock", label: "Automations")
                sidebarNavRow(icon: "shippingbox", label: "Customizations")
            }
            .padding(.top, 2)

            // Projects Header
            HStack(spacing: 4) {
                Text("Projects")
                    .font(.system(size: 7.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.42))
                Spacer()
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 7.5))
                    .foregroundStyle(Color.white.opacity(0.36))
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 7.5))
                    .foregroundStyle(Color.white.opacity(0.36))
            }
            .padding(.top, 6)
            .padding(.horizontal, 2)

            // Project Tree
            VStack(alignment: .leading, spacing: 5) {
                sidebarProjectRow("Snapzy")
                HStack(spacing: 4) {
                    Text("Codebase Analysis…")
                        .font(.system(size: 8, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.50))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text("2h")
                        .font(.system(size: 7.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.30))
                }
                .padding(.leading, 8)
                .padding(.trailing, 3)

                sidebarProjectRow("Grav")
                    .padding(.top, 2)

                // Active highlighted conversation row
                HStack(spacing: 4) {
                    Text("Grav Telemetry Com…")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Image(systemName: "circle.grid.2x2.fill")
                        .font(.system(size: 6.5))
                        .foregroundStyle(Color.white.opacity(0.54))
                }
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.085))
                )
            }

            Spacer(minLength: 0)

            sidebarNavRow(icon: "gearshape", label: "Settings")
                .padding(.bottom, 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(width: 124)
        .background(Color(red: 0.072, green: 0.076, blue: 0.090))
    }

    private func sidebarNavRow(icon: String, label: String) -> some View {
        HStack(spacing: 5.5) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.46))
                .frame(width: 10)
            Text(label)
                .font(.system(size: 8.5, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.68))
                .lineLimit(1)
        }
        .padding(.horizontal, 3)
    }

    private func sidebarProjectRow(_ name: String) -> some View {
        HStack(spacing: 4.5) {
            Image(systemName: "folder")
                .font(.system(size: 7.5))
                .foregroundStyle(Color.white.opacity(0.42))
            Text(name)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.56))
        }
        .padding(.horizontal, 2)
    }

    private var antigravityChatCanvas: some View {
        HStack(alignment: .center, spacing: 0) {
            // Signature Antigravity miniature step progress dot rail
            VStack(spacing: 4.5) {
                ForEach(0..<10, id: \.self) { idx in
                    Circle()
                        .fill(idx == 9 ? Color.white.opacity(0.86) : Color.white.opacity(0.18))
                        .frame(width: idx == 9 ? 3.5 : 2.5, height: idx == 9 ? 3.5 : 2.5)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)

            VStack(alignment: .leading, spacing: 0) {
                // Top-right user request bubble
                HStack {
                    Spacer(minLength: 36)
                    Text("Stream live Thinking, Analyzed files, running tasks & /swarm telemetry into the Notch HUD")
                        .font(.system(size: 8.2, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .lineSpacing(1.5)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6.5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(red: 0.11, green: 0.115, blue: 0.132))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                                )
                        )
                }
                .padding(.top, 9)

                // Authentic Antigravity Agent Timeline
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Text("Thinking")
                            .foregroundStyle(Color.white.opacity(0.52))
                        Text("2m 45s")
                            .foregroundStyle(Color.white.opacity(0.38))
                            .monospacedDigit()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 6.5, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.36))
                    }
                    .font(.system(size: 8.2, weight: .medium))
                    .padding(.top, 9)

                    // Highlighted blue-bordered `Ran ...` step exactly matching Antigravity
                    HStack(spacing: 4) {
                        Text("Ran inspect brain directory for swarm & subagent artifacts")
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 6.5, weight: .semibold))
                            .opacity(0.55)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 8.2, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.76))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(red: 0.08, green: 0.12, blue: 0.20).opacity(0.52))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(Color(red: 0.22, green: 0.44, blue: 0.78).opacity(0.72), lineWidth: 0.75)
                            )
                    )

                    antigravityTimelineRanRow("Ran read members.json, plan.json, and board.jsonl")
                    antigravityTimelineAnalyzedRow(file: "ExpandedNotchView.swift", range: "#L1-250")
                    antigravityTimelineAnalyzedRow(file: "AntigravityTelemetryStore.swift", range: "#L1-120")
                    antigravityTimelineEditedRow(file: "SwarmModels.swift", added: 323, removed: 0)
                    antigravityTimelineAnalyzedRow(file: "project.yml", range: "#L1-80")

                    NotchShimmerText(
                        text: "Thinking for 20s",
                        font: .system(size: 8.3, weight: .medium),
                        tracking: -0.1,
                        baseOpacity: 0.44,
                        peakOpacity: 0.94,
                        period: 1.85,
                        reduceMotion: GravMotionPreferences.shared.reduceMotion
                    )
                    .monospacedDigit()
                    .padding(.top, 2)
                }
                .padding(.horizontal, 8)

                Spacer(minLength: 6)

                // Exact Antigravity Bottom Composer Bar
                VStack(alignment: .leading, spacing: 7) {
                    Text("Ask anything, @ to mention, / for workflows")
                        .font(.system(size: 8.2, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.32))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.56))

                        HStack(spacing: 3) {
                            Text("Gemini 4 Neon High")
                                .font(.system(size: 7.8, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.66))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 6, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.40))
                        }

                        Spacer(minLength: 4)

                        HStack(spacing: 3) {
                            Image(systemName: "lightbulb")
                                .font(.system(size: 7.5))
                                .foregroundStyle(Color.white.opacity(0.48))
                            Text("Turbo")
                                .font(.system(size: 7.8, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.60))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 6, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.40))
                        }

                        Image(systemName: "mic")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.white.opacity(0.46))

                        Circle()
                            .fill(Color(red: 0.24, green: 0.53, blue: 0.96))
                            .frame(width: 16, height: 16)
                            .overlay(
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 7.5, weight: .bold))
                                    .foregroundStyle(Color.white)
                            )
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(red: 0.082, green: 0.086, blue: 0.100))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 9)
            }
            .padding(.trailing, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.038, green: 0.040, blue: 0.048))
    }

    private func antigravityTimelineRanRow(_ text: String) -> some View {
        HStack(spacing: 3.5) {
            Text(text)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 6.2, weight: .semibold))
                .opacity(0.45)
        }
        .font(.system(size: 8.1, weight: .regular))
        .foregroundStyle(Color.white.opacity(0.46))
        .padding(.horizontal, 2)
    }

    private func antigravityTimelineAnalyzedRow(file: String, range: String) -> some View {
        HStack(spacing: 4) {
            Text("Analyzed")
                .foregroundStyle(Color.white.opacity(0.44))
            LanguageIconView(path: file, changeKind: nil, size: 10)
            Text(file)
                .foregroundStyle(Color.white.opacity(0.68))
                .lineLimit(1)
            Text(range)
                .font(.system(size: 7.8, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.44))
        }
        .font(.system(size: 8.1, weight: .regular))
        .padding(.horizontal, 2)
    }

    private func antigravityTimelineEditedRow(file: String, added: Int, removed: Int) -> some View {
        HStack(spacing: 4) {
            Text("Created")
                .foregroundStyle(Color.white.opacity(0.44))
            LanguageIconView(path: file, changeKind: .create, size: 10)
            Text(file)
                .foregroundStyle(Color.white.opacity(0.74))
                .lineLimit(1)
            HStack(spacing: 2.5) {
                Text("+\(added)")
                    .foregroundStyle(GravPalette.emerald.opacity(0.88))
                Text("-\(removed)")
                    .foregroundStyle(GravPalette.coral.opacity(0.88))
            }
            .font(.system(size: 7.8, weight: .medium, design: .monospaced))
            .monospacedDigit()
        }
        .font(.system(size: 8.1, weight: .regular))
        .padding(.horizontal, 2)
    }
}

/// Interactive 1:1 MacBook Notch HUD rendered flush at `y = 0` directly above the macOS menu bar
/// on Step 2 — mirroring Grav's real Collapsed Dynamic Island Pill and 4-Tab Expanded Notch HUD
/// pixel-for-pixel (pure `#000000` bezel ink, zero outer stroke, real `NotchBars`, real Devicon SVGs).
struct GravMockNotchOverlay: View {
    @ObservedObject var state: GravOnboardingState
    @Environment(\.gravMockSceneIsLive) private var isLive
    @Environment(\.accessibilityReduceMotion) private var envReduceMotion
    @Namespace private var mockRailNamespace

    @State private var isNotchHovered = false
    @State private var pulsePhase = false

    private var reduceMotion: Bool {
        GravMotionPreferences.shared.reduceMotion || envReduceMotion
    }

    private var isExpanded: Bool {
        state.isMockNotchExpanded
    }

    var body: some View {
        VStack(spacing: 12) {
            interactiveNotch
                .onHover { hovering in
                    isNotchHovered = hovering
                    if hovering && !isExpanded {
                        state.setMockNotchExpanded(true)
                    }
                }

            if !isExpanded {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text("Hover or click the notch to expand")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(Color.white.opacity(0.84))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(red: 0.10, green: 0.11, blue: 0.14).opacity(0.88))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.36), radius: 10, y: 4)
                )
                .allowsHitTesting(false)
                .transition(GravMockScene.hudTransition)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if isLive {
                pulsePhase = true
            }
        }
        .onChange(of: isLive) { _, live in
            pulsePhase = live
        }
    }

    // MARK: - 1:1 Interactive MacBook Notch (Collapsed Pill ↔ Expanded 4-Tab HUD)

    private var interactiveNotch: some View {
        let shape = MacBookNotchShape(
            shoulderRadius: isExpanded ? 14 : 6,
            bottomRadius: isExpanded ? 22 : 12
        )

        return ZStack(alignment: .top) {
            if !isExpanded {
                collapsedMockContent
                    .transition(.opacity)
            } else {
                expandedMockContent
                    .transition(.opacity)
            }
        }
        .frame(width: isExpanded ? 492 : 276)
        .background(shape.fill(Color.black))
        .clipShape(shape)
        .shadow(
            color: Color.black.opacity(isExpanded ? 0.52 : 0.0),
            radius: isExpanded ? 28 : 0,
            y: isExpanded ? 14 : 0
        )
        .shadow(
            color: Color.black.opacity(isExpanded ? 0.24 : 0.0),
            radius: isExpanded ? 6 : 0,
            y: isExpanded ? 3 : 0
        )
        .animation(
            reduceMotion
                ? nil
                : (isExpanded
                    ? .spring(response: 0.34, dampingFraction: 0.84)
                    : .timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.24)),
            value: isExpanded
        )
        .animation(reduceMotion ? nil : GravMotion.railSpring, value: state.selectedMockNotchTab)
    }

    // MARK: - 1:1 Collapsed Pill (Matches `CollapsedNotchView`)

    private var collapsedMockContent: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                GravAppIconTile(size: 19)
                NotchBars(mockCommandWaveStyle)
            }

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                NotchPingPongMarqueeText(
                    text: "Run full 20-test XCTest suite",
                    font: .system(size: 11.5, weight: .medium),
                    color: Color.white.opacity(0.88),
                    alignment: .trailing,
                    reduceMotion: reduceMotion || !isLive
                )

                Text("23s")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.48))
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .contentShape(Rectangle())
        .onTapGesture {
            GravOnboardingWelcomeAudio.shared.playTabSwitch()
            state.toggleMockNotchExpanded()
        }
    }

    private var mockCommandWaveStyle: NotchBarsStyle {
        if reduceMotion || !isLive {
            return .steady([0.45, 0.9, 0.55], barWidth: 1.6, spacing: 1.7, height: 9.5, tint: Color.white.opacity(0.85))
        }
        return .wave(
            count: 3,
            low: 0.26,
            high: 1.0,
            barWidth: 1.6,
            spacing: 1.7,
            height: 9.5,
            period: 0.56,
            stagger: 0.12,
            tint: Color.white.opacity(0.85)
        )
    }

    // MARK: - 1:1 Expanded 4-Tab HUD (Matches `ExpandedNotchView`)

    private var expandedMockContent: some View {
        VStack(spacing: 8) {
            // 1:1 Header Bar
            HStack(spacing: 7) {
                HStack(spacing: 6) {
                    GravAppIconTile(size: 19)

                    HStack(spacing: 3.5) {
                        Text("Build a native macOS 14+ SwiftUI...")
                            .font(.system(size: 11.5, weight: .medium))
                            .tracking(-0.18)
                            .foregroundStyle(Color.white.opacity(0.92))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 156, alignment: .leading)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 7.5, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.36))
                    }

                    HStack(spacing: 4) {
                        NotchSemanticDot(color: GravPalette.thinking, size: 4.5, isPulsing: isLive)
                        Text("Thinking")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.72))
                    }
                }

                Spacer(minLength: 4)

                HStack(spacing: 5) {
                    HStack(spacing: 6) {
                        Text("↓2.1M")
                            .foregroundStyle(Color.white.opacity(0.52))
                        Text("↑342k")
                            .foregroundStyle(GravPalette.glacialCyan.opacity(0.92))
                    }
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .monospacedDigit()

                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 0.5, height: 10)

                    Button {
                        GravOnboardingWelcomeAudio.shared.playButtonTap()
                        state.setMockNotchExpanded(false)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.52))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(NotchChromeButtonStyle(cornerRadius: 5.5))
                    .help("Collapse Preview")
                }
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .onTapGesture {
                GravOnboardingWelcomeAudio.shared.playTabSwitch()
                state.setMockNotchExpanded(false)
            }

            // 1:1 4-Tab Monochrome Segmented Rail (`Live | Reply | Files | Terminal`)
            HStack(spacing: 2) {
                ForEach(GravMockNotchTab.allCases) { tab in
                    let selected = state.selectedMockNotchTab == tab
                    Button {
                        GravOnboardingWelcomeAudio.shared.playTabSwitch()
                        state.selectMockNotchTab(tab)
                    } label: {
                        HStack(spacing: 4.5) {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 9.5, weight: selected ? .medium : .regular))
                                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.46))

                            Text(tab.title)
                                .font(.system(size: 10.5, weight: selected ? .medium : .regular))
                                .tracking(-0.12)
                                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.56))

                            Text(tab.badgeCount)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(selected ? Color.white.opacity(0.56) : Color.white.opacity(0.28))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.white.opacity(0.105))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(
                                                LinearGradient(
                                                    colors: [
                                                        Color.white.opacity(0.18),
                                                        Color.white.opacity(0.03),
                                                    ],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                ),
                                                lineWidth: 0.5
                                            )
                                    )
                                    .matchedGeometryEffect(id: "mock-notch-rail-thumb", in: mockRailNamespace)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2.5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.042))
            )

            // 1:1 Active Tab Viewport
            notchTabBody
                .frame(maxWidth: .infinity, minHeight: 162, maxHeight: 162, alignment: .topLeading)
                .id(state.selectedMockNotchTab)
                .transition(.opacity)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 13)
    }

    @ViewBuilder
    private var notchTabBody: some View {
        switch state.selectedMockNotchTab {
        case .live:
            VStack(spacing: 6) {
                // 1:1 Editorial Thinking Sheet
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5.5) {
                        NotchSemanticDot(color: GravPalette.thinking, size: 4.5, isPulsing: isLive)
                        Text("Thinking")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.94))
                        Text("gemini-4-neon-high")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.36))
                        Spacer()
                        Text("18s")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(GravPalette.thinking.opacity(0.90))
                    }

                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 0.5)

                    Text("Correlating edit_file line diffs from GENERIC result summaries so the Files tab matches Antigravity's exact +29 -29 counts in real time.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .lineSpacing(2.5)
                        .lineLimit(2)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.042))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                        )
                )

                // Clean Activity Rows with Real Official Devicon Language SVGs
                VStack(spacing: 2) {
                    mockActivityRow(path: "Grav/Features/Onboarding/GravOnboardingWelcome.swift", added: 29, removed: 29)
                    mockActivityRow(path: "Grav/Features/Notch/NotchHUDCoordinator.swift", added: 16, removed: 6)
                }
            }

        case .reply:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4.5) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.32))
                    Text("Fix diff counts and stream AI replies in the notch")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.44))
                        .lineLimit(1)
                    Spacer()
                    Text("1/8")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.36))
                }

                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 0.5)

                Text("Real-time Reply Streaming")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.95))

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle().fill(GravPalette.glacialCyan.opacity(0.8)).frame(width: 3.5, height: 3.5)
                    Text("Streams Markdown responses & code blocks at 120Hz with optical focus reveal.")
                        .font(.system(size: 10.8))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .lineSpacing(2)
                }

                HStack {
                    Text("swift test --parallel  // 20/20 passed")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(GravPalette.emerald.opacity(0.92))
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.45))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                )
            }
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.038))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )

        case .files:
            VStack(spacing: 4) {
                HStack(spacing: 10) {
                    Text("All 12").font(.system(size: 10, weight: .medium)).foregroundStyle(Color.white.opacity(0.90))
                    Text("Edited 9").font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.36))
                    Text("Created 3").font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.36))
                    Spacer()
                }
                .padding(.horizontal, 6)

                mockDiffRow(path: "Grav/Core/Telemetry/TelemetryModels.swift", added: 3, removed: 3)
                mockDiffRow(path: "Grav/Features/Notch/ResponseTelemetryTabView.swift", added: 63, removed: 0)
                mockDiffRow(path: "web/src/components/NotchPreview.tsx", added: 49, removed: 4)
            }

        case .terminal:
            HStack(spacing: 7) {
                VStack(spacing: 3) {
                    mockCommandRailRow(title: "Run 20 unit tests", status: "Exit 0", time: "2.6s", selected: true, running: false)
                    mockCommandRailRow(title: "Build Release app", status: "Running", time: "14s", selected: false, running: true)
                }
                .frame(width: 146, alignment: .top)

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("$ xcodebuild test -scheme Grav")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.74))
                            .lineLimit(1)
                        Spacer()
                        Text("20L")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.30))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)

                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)

                    VStack(alignment: .leading, spacing: 2.5) {
                        Text("Test Suite 'TelemetryStateMachineTests' passed")
                        Text("Executed 20 tests, with 0 failures (0.046s)")
                        Text("** TEST SUCCEEDED **")
                            .foregroundStyle(GravPalette.emerald.opacity(0.92))
                    }
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .padding(7)

                    Spacer(minLength: 0)
                }
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.035))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.075), lineWidth: 0.5)
                        )
                )
            }
        }
    }

    private func mockActivityRow(path: String, added: Int, removed: Int) -> some View {
        let url = URL(fileURLWithPath: path)
        return HStack(spacing: 7) {
            LanguageIconView(path: path, changeKind: .edit, size: 14)
            Text(url.lastPathComponent)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
            Text("…/" + url.deletingLastPathComponent().lastPathComponent)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.34))
                .lineLimit(1)
            Spacer(minLength: 6)
            HStack(spacing: 4) {
                Text("+\(added)").foregroundStyle(GravPalette.emerald)
                if removed > 0 {
                    Text("-\(removed)").foregroundStyle(GravPalette.coral)
                }
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
    }

    private func mockDiffRow(path: String, added: Int, removed: Int) -> some View {
        let url = URL(fileURLWithPath: path)
        return HStack(spacing: 8) {
            LanguageIconView(path: path, changeKind: removed == 0 ? .create : .edit, size: 15)

            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
                Text("…/" + url.deletingLastPathComponent().lastPathComponent)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.white.opacity(0.36))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            NotchProportionalDiffMicroBar(
                added: added,
                removed: removed,
                isDeleted: false,
                showBar: true,
                barWidth: 26,
                barHeight: 2.5
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5.5)
    }

    private func mockCommandRailRow(title: String, status: String, time: String, selected: Bool, running: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                NotchSemanticDot(color: running ? GravPalette.glacialCyan : GravPalette.emerald, size: 4.5, isPulsing: running && isLive)
                Text(title)
                    .font(.system(size: 10, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.76))
                    .lineLimit(1)
            }
            HStack {
                Text(status)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(running ? GravPalette.glacialCyan : Color.white.opacity(0.38))
                Spacer()
                Text(time)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.36))
            }
            .padding(.leading, 13)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                .fill(selected ? Color.white.opacity(0.085) : Color.clear)
        )
    }
}

// MARK: - Space 2: Preferences & Startup (Live Bound to PreferencesStore)

struct GravMockPreferencesScene: View {
    @ObservedObject var state: GravOnboardingState
    let preferences: PreferencesStore

    @State private var isRestoreHovered = false
    @State private var isDoneHovered = false

    var body: some View {
        ZStack {
            GravMockWallpaper(app: .settings).equatable()

            VStack(spacing: 0) {
                settingsWindow
                    .padding(.top, GravMockScene.windowTopInset + 16)
                    .padding(.horizontal, GravMockScene.windowInset)

                Spacer(minLength: 0)
            }
        }
    }

    private var settingsWindow: some View {
        HStack(spacing: 0) {
            // Left Full-Height macOS System Settings Sidebar
            VStack(alignment: .leading, spacing: 6) {
                GravMockTrafficLights(size: 9.5, spacing: 6)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 2)

                // Search Field
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 8.5))
                        .foregroundStyle(Color.white.opacity(0.38))
                    Text("Search")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.white.opacity(0.38))
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3.5)
                .background(
                    Radius.rect(Radius.controlXS)
                        .fill(Color.white.opacity(0.07))
                )
                .padding(.horizontal, 8)

                // Grav App Identity Row
                HStack(spacing: 7) {
                    GravAppIconTile(size: 20)
                    VStack(alignment: .leading, spacing: 0.5) {
                        Text("Grav")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(GravMockPalette.ink)
                        Text("Telemetry HUD")
                            .font(.system(size: 7.5))
                            .foregroundStyle(GravMockPalette.inkTertiary)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.top, 3)

                Rectangle()
                    .fill(GravMockPalette.chromeRule)
                    .frame(height: 0.5)
                    .padding(.horizontal, 8)

                VStack(spacing: 2) {
                    sidebarItem(icon: "gearshape.fill", title: "Startup & HUD", badgeColor: GravMockPalette.gravTeal, isSelected: true)
                    sidebarItem(icon: "macbook", title: "Notch Behavior", badgeColor: GravMockPalette.macBlue, isSelected: false)
                    sidebarItem(icon: "square.on.square.dashed", title: "Liquid Glass", badgeColor: Color(white: 0.42), isSelected: false)
                    sidebarItem(icon: "waveform.path.ecg", title: "Local Telemetry", badgeColor: GravMockPalette.gravEmerald, isSelected: false)
                }

                Spacer()
            }
            .frame(width: 140)
            .background(GravMockPalette.chromeSidebar)

            Rectangle()
                .fill(GravMockPalette.chromeRule)
                .frame(width: 0.5)

            // Right Detail Pane bound LIVE to PreferencesStore
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(Color.white.opacity(0.42))
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Color.white.opacity(0.16))
                    }
                    .font(.system(size: 9.5, weight: .semibold))

                    Text("Startup & HUD")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(GravMockPalette.ink)

                    Spacer()

                    HStack(spacing: 4) {
                        Circle()
                            .fill(GravMockPalette.gravEmerald)
                            .frame(width: 5, height: 5)
                        Text("Live")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.56))
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(GravMockPalette.chromeBar)

                Rectangle()
                    .fill(GravMockPalette.chromeRule)
                    .frame(height: 0.5)

                VStack(spacing: 0) {
                    preferenceRow(
                        title: "Launch at Login",
                        detail: "Start Grav silently in your menu bar when macOS boots.",
                        isOn: Binding(
                            get: { preferences.launchAtLogin },
                            set: { newValue in
                                preferences.launchAtLogin = newValue
                                state.markPreferencesReviewed()
                            }
                        )
                    )

                    rowDivider

                    preferenceRow(
                        title: "Auto-Peek on Events",
                        detail: "Briefly glance the notch on thinking bursts, edits, and command exits.",
                        isOn: Binding(
                            get: { preferences.autoPeekOnEvents },
                            set: { newValue in
                                preferences.autoPeekOnEvents = newValue
                                state.markPreferencesReviewed()
                            }
                        )
                    )

                    rowDivider

                    preferenceRow(
                        title: "Hover to Expand Notch",
                        detail: "Open the 3-tab telemetry HUD when resting your pointer on the notch.",
                        isOn: Binding(
                            get: { preferences.hoverToExpand },
                            set: { newValue in
                                preferences.hoverToExpand = newValue
                                state.markPreferencesReviewed()
                            }
                        )
                    )

                    rowDivider

                    preferenceRow(
                        title: "Liquid Glass Chrome",
                        detail: "Use native macOS glass refraction across controls and settings.",
                        isOn: Binding(
                            get: { preferences.useLiquidGlass },
                            set: { newValue in
                                preferences.useLiquidGlass = newValue
                                state.markPreferencesReviewed()
                            }
                        )
                    )
                }
                .background(GravMockPalette.chromeCard)
                .clipShape(Radius.rect(Radius.controlM))
                .overlay(
                    Radius.rect(Radius.controlM)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .padding(.horizontal, 14)
                .padding(.top, 12)

                Spacer(minLength: 8)

                Rectangle()
                    .fill(GravMockPalette.chromeRule)
                    .frame(height: 0.5)

                // Footer
                HStack(spacing: 8) {
                    Button {
                        withAnimation(GravMotionPreferences.shared.spec(.hover).animation) {
                            preferences.autoPeekOnEvents = true
                            preferences.hoverToExpand = true
                            preferences.useLiquidGlass = true
                            state.markPreferencesReviewed()
                        }
                    } label: {
                        Text("Restore Defaults")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(GravMockPalette.ink.opacity(0.86))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                Radius.rect(Radius.controlXS)
                                    .fill(isRestoreHovered ? Color.white.opacity(0.14) : Color.white.opacity(0.08))
                                    .overlay(
                                        Radius.rect(Radius.controlXS)
                                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { isRestoreHovered = $0 }

                    Spacer()

                    Button {
                        state.markPreferencesReviewed()
                    } label: {
                        Text("Looks Good")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(
                                Radius.rect(Radius.controlXS)
                                    .fill(isDoneHovered ? GravMockPalette.gravTeal.opacity(0.88) : GravMockPalette.gravTeal)
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { isDoneHovered = $0 }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(GravMockPalette.chromeBar)
            }
            .background(GravMockPalette.chrome)
        }
        .frame(width: 512, height: 322)
        .clipShape(Radius.rect(Radius.card))
        .overlay(
            Radius.rect(Radius.card)
                .strokeBorder(GravMockPalette.chromeEdge, lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.55), radius: 28, x: 0, y: 14)
        .shadow(color: Color.black.opacity(0.22), radius: 5, x: 0, y: 2)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(GravMockPalette.chromeRule)
            .frame(height: 0.5)
            .padding(.leading, 12)
    }

    private func sidebarItem(icon: String, title: String, badgeColor: Color, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 15, height: 15)
                .background(
                    Radius.rect(Radius.ornament)
                        .fill(isSelected ? Color.white.opacity(0.24) : badgeColor)
                )
            Text(title)
                .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : GravMockPalette.ink.opacity(0.82))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            Radius.rect(Radius.controlXS)
                .fill(isSelected ? GravMockPalette.gravTeal : Color.clear)
        )
        .padding(.horizontal, 7)
    }

    private func preferenceRow(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1.5) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(GravMockPalette.ink)
                Text(detail)
                    .font(.system(size: 8.5))
                    .foregroundStyle(GravMockPalette.inkTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            // Pure-SwiftUI macOS switch so 3D Spaces transitions stay 120fps with zero AppKit layout thrash
            MockMacOSToggle(isOn: isOn)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct MockMacOSToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.80)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(isOn ? GravMockPalette.gravTeal : Color.white.opacity(0.16))
                    .frame(width: 28, height: 16)

                Circle()
                    .fill(Color.white)
                    .frame(width: 12.5, height: 12.5)
                    .shadow(color: Color.black.opacity(0.18), radius: 1.5, y: 0.5)
                    .padding(1.75)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}
