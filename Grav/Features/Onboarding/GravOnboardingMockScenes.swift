//
//  GravOnboardingMockScenes.swift
//  Grav
//
//  Three interactive macOS Desktop Spaces hosted inside `GravOnboardingMockHost`:
//  - Space 0: Live Antigravity connection & local telemetry bridge verifier (`store.connectionStatus`)
//  - Space 1: Interactive miniature MacBook Notch HUD morphing between collapsed pill & 3-tab HUD
//  - Space 2: Mock macOS System Settings window bound live to `PreferencesStore`
//

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
            // Window Titlebar
            HStack(spacing: 10) {
                GravMockTrafficLights(size: 9.5, spacing: 6)

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    GravOrbitalMark(size: 12, tint: GravMockPalette.gravTeal)
                    Text("Antigravity Telemetry Bridge")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GravMockPalette.ink)
                }

                Spacer(minLength: 0)

                // Live connection badge
                HStack(spacing: 4.5) {
                    Circle()
                        .fill(isFullyConnected ? GravMockPalette.gravEmerald : GravMockPalette.gravAmber)
                        .frame(width: 6, height: 6)

                    Text(isFullyConnected ? "Connected" : "Checking")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(GravMockPalette.inkSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.05))
                )
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(GravMockPalette.chromeBar)

            Rectangle()
                .fill(GravMockPalette.chromeRule)
                .frame(height: 0.5)

            // Diagnostic rows
            VStack(spacing: 10) {
                // Row 1: Antigravity App Detection
                diagnosticCard {
                    HStack(spacing: 11) {
                        AntigravityLogoView(icon: store.antigravityIcon, size: 24)
                            .frame(width: 30, height: 30)
                            .background(
                                Radius.rect(Radius.tile)
                                    .fill(Color.black.opacity(0.04))
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Antigravity Application")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(GravMockPalette.ink)

                            Text(status.appURL.path)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(GravMockPalette.inkTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer(minLength: 8)

                        statusPill(
                            label: status.isAppRunning ? "Running" : (status.isAppInstalled ? "Installed" : "Not Found"),
                            isPositive: status.isAppInstalled
                        )
                    }
                }

                // Row 2: Brain Directory Access
                diagnosticCard {
                    HStack(spacing: 11) {
                        Image(systemName: status.isBrainAccessible ? "folder.fill.badge.person.crop" : "lock.shield")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(status.isBrainAccessible ? GravMockPalette.gravTeal : GravMockPalette.gravAmber)
                            .frame(width: 30, height: 30)
                            .background(
                                Radius.rect(Radius.tile)
                                    .fill((status.isBrainAccessible ? GravMockPalette.gravTeal : GravMockPalette.gravAmber).opacity(0.10))
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Local Telemetry Directory")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(GravMockPalette.ink)

                            Text("~/.gemini/antigravity/brain/")
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(GravMockPalette.inkTertiary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        statusPill(
                            label: status.isBrainAccessible ? "Readable" : "Needs Access",
                            isPositive: status.isBrainAccessible
                        )
                    }
                }

                // Row 3: Live Discovered Conversations
                diagnosticCard {
                    HStack(spacing: 11) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(GravMockPalette.gravTeal)
                            .frame(width: 30, height: 30)
                            .background(
                                Radius.rect(Radius.tile)
                                    .fill(GravMockPalette.gravTeal.opacity(0.10))
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Discovered Conversations")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(GravMockPalette.ink)

                            Text(
                                store.activeSession?.title
                                    ?? (status.activeConversationCount > 0
                                        ? "Kernel kqueue watcher active"
                                        : "Start a chat in Antigravity to stream live")
                            )
                            .font(.system(size: 9.5))
                            .foregroundStyle(GravMockPalette.inkTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        }

                        Spacer(minLength: 8)

                        Text("\(status.activeConversationCount)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(GravMockPalette.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.black.opacity(0.06))
                            )
                    }
                }
            }
            .padding(14)
            .background(Color(red: 0.962, green: 0.965, blue: 0.972))

            Rectangle()
                .fill(GravMockPalette.chromeRule)
                .frame(height: 0.5)

            // Window Footer Bar
            HStack(spacing: 8) {
                // Refresh Button
                Button {
                    store.refreshConnectionStatus()
                    state.recordConnectionRefresh(store.connectionStatus)
                } label: {
                    HStack(spacing: 4.5) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Refresh")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(GravMockPalette.ink.opacity(0.88))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Radius.rect(Radius.controlXS)
                            .fill(isRefreshHovered ? Color(white: 0.94) : Color.white)
                            .overlay(
                                Radius.rect(Radius.controlXS)
                                    .strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5)
                            )
                            .shadow(color: Color.black.opacity(0.06), radius: 1, y: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .onHover { isRefreshHovered = $0 }

                if !status.isBrainAccessible || status.needsFolderAccess {
                    Button {
                        store.requestBrainFolderAccess()
                        state.recordConnectionRefresh(store.connectionStatus)
                    } label: {
                        HStack(spacing: 4.5) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Grant Access")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Radius.rect(Radius.controlXS)
                                .fill(isGrantHovered ? GravMockPalette.gravAmber.opacity(0.90) : GravMockPalette.gravAmber)
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { isGrantHovered = $0 }
                }

                Spacer(minLength: 0)

                if status.isAppInstalled {
                    Button {
                        store.activateAntigravityApp()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Open Antigravity")
                                .font(.system(size: 10, weight: .semibold))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Radius.rect(Radius.controlXS)
                                .fill(isOpenHovered ? GravMockPalette.gravTeal.opacity(0.88) : GravMockPalette.gravTeal)
                                .shadow(color: Color.black.opacity(0.12), radius: 1, y: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { isOpenHovered = $0 }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(GravMockPalette.chromeBar)
        }
        .frame(maxWidth: 512)
        .clipShape(Radius.rect(Radius.card))
        .overlay(
            Radius.rect(Radius.card)
                .strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.24), radius: 22, x: 0, y: 10)
        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
    }

    private func diagnosticCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Radius.rect(Radius.controlM)
                    .fill(Color.white)
                    .overlay(
                        Radius.rect(Radius.controlM)
                            .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5)
                    )
            )
    }

    private func statusPill(label: String, isPositive: Bool) -> some View {
        HStack(spacing: 4.5) {
            Circle()
                .fill(isPositive ? GravMockPalette.gravEmerald : GravMockPalette.gravAmber)
                .frame(width: 5.5, height: 5.5)

            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(isPositive ? GravMockPalette.gravEmerald : GravMockPalette.gravAmber)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(
            Capsule(style: .continuous)
                .fill((isPositive ? GravMockPalette.gravEmerald : GravMockPalette.gravAmber).opacity(0.11))
        )
        .fixedSize()
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

            // Calm Antigravity IDE background card framing the interactive notch HUD above
            workspaceBackdropWindow
                .padding(.top, 96)
                .padding(.horizontal, 30)
                .opacity(isExpanded ? 0.54 : 0.94)
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

    private var workspaceBackdropWindow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                GravMockTrafficLights(size: 8.5, spacing: 5.5)
                Spacer()
                Text("NotchHUDCoordinator.swift — Antigravity")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(GravMockPalette.inkSecondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(GravMockPalette.chromeBar)

            Rectangle()
                .fill(GravMockPalette.chromeRule)
                .frame(height: 0.5)

            VStack(alignment: .leading, spacing: 7) {
                codeLine("01", "import NotchKit", accent: GravMockPalette.gravTeal)
                codeLine("02", "import SwiftUI", accent: GravMockPalette.gravTeal)
                codeLine("03", "", accent: GravMockPalette.inkTertiary)
                codeLine("04", "@MainActor final class NotchHUDCoordinator {", accent: GravMockPalette.ink)
                codeLine("05", "    func triggerWelcomePeek() {", accent: GravMockPalette.inkSecondary)
                codeLine("06", "        presenter.peek(duration: 2.6)", accent: GravMockPalette.gravTeal)
                codeLine("07", "    }", accent: GravMockPalette.inkSecondary)
                codeLine("08", "}", accent: GravMockPalette.ink)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
        }
        .frame(maxWidth: 486)
        .clipShape(Radius.rect(Radius.card))
        .overlay(
            Radius.rect(Radius.card)
                .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 16, y: 6)
    }

    private func codeLine(_ number: String, _ text: String, accent: Color) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(GravMockPalette.inkTertiary.opacity(0.75))
                .frame(width: 16, alignment: .trailing)

            Text(text)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(accent)
        }
    }
}

/// Interactive miniature MacBook Notch HUD rendered flush at `y = 0` directly above the frosted
/// menu bar on Step 2 so the pure obsidian hardware bezel stays razor-sharp and interactive.
struct GravMockNotchOverlay: View {
    @ObservedObject var state: GravOnboardingState
    @Environment(\.gravMockSceneIsLive) private var isLive

    @State private var isNotchHovered = false
    @State private var pulsePhase = false

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
                .foregroundStyle(GravMockPalette.inkSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.90))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.08), radius: 6, y: 2)
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

    // MARK: - Interactive Miniature MacBook Notch

    private var interactiveNotch: some View {
        let shape = MacBookNotchShape(
            shoulderRadius: isExpanded ? 12 : 7,
            bottomRadius: isExpanded ? 18 : 10
        )

        return VStack(spacing: 0) {
            // Top Bezel Strip (always visible; flanks hardware camera dot)
            HStack(spacing: 0) {
                // Left telemetry status
                HStack(spacing: 6) {
                    Circle()
                        .fill(GravPalette.thinking)
                        .frame(width: 6.5, height: 6.5)
                        .scaleEffect(pulsePhase && isLive ? 1.18 : 0.90)
                        .animation(
                            isLive && !GravMotionPreferences.shared.reduceMotion
                                ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                                : nil,
                            value: pulsePhase
                        )

                    if isExpanded {
                        GravOrbitalMark(size: 12, tint: .white)
                        Text("Grav")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Color.white)
                        Text("gemini-2.5-pro")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.50))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                    } else {
                        Text("Thinking")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.92))
                    }
                }
                .padding(.leading, isExpanded ? 18 : 14)

                Spacer(minLength: 8)

                // Hardware Camera Lens Dot (center anchor)
                Circle()
                    .fill(Color(white: 0.14))
                    .frame(width: 6, height: 6)
                    .overlay(
                        Circle()
                            .fill(Color(red: 0.04, green: 0.08, blue: 0.14))
                            .frame(width: 3, height: 3)
                    )

                Spacer(minLength: 8)

                // Right cluster: collapse button when expanded, or compact token indicator when collapsed
                if isExpanded {
                    Button {
                        state.setMockNotchExpanded(false)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.65))
                            .frame(width: 20, height: 20)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.10))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 18)
                } else {
                    HStack(spacing: 4) {
                        Text("18.4k")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.68))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(GravPalette.glacialTeal)
                    }
                    .padding(.trailing, 14)
                }
            }
            .frame(height: 30)
            .contentShape(Rectangle())
            .onTapGesture {
                state.toggleMockNotchExpanded()
            }

            // Expanded 3-Tab Telemetry Content
            if isExpanded {
                VStack(spacing: 10) {
                    // Segmented 3-Tab Switcher
                    HStack(spacing: 4) {
                        ForEach(GravMockNotchTab.allCases) { tab in
                            let selected = state.selectedMockNotchTab == tab
                            Button {
                                state.selectMockNotchTab(tab)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: tab.symbol)
                                        .font(.system(size: 10, weight: .semibold))
                                    Text(tab.title)
                                        .font(.system(size: 10.5, weight: selected ? .semibold : .medium))
                                    Text(tab.keyLabel)
                                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color.white.opacity(selected ? 0.78 : 0.42))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(
                                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                .fill(Color.white.opacity(selected ? 0.16 : 0.06))
                                        )
                                }
                                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.60))
                                .padding(.horizontal, 10)
                                .frame(maxWidth: .infinity)
                                .frame(height: 26)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(selected ? GravPalette.glacialTeal.opacity(0.28) : Color.clear)
                                        .overlay(
                                            Capsule(style: .continuous)
                                                .strokeBorder(
                                                    selected ? GravPalette.glacialTeal.opacity(0.55) : Color.clear,
                                                    lineWidth: 0.6
                                                )
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )

                    // Active Tab Telemetry Preview
                    notchTabBody
                        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
                        .id(state.selectedMockNotchTab)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: isExpanded ? 446 : 244)
        .background(
            shape.fill(GravPalette.notchBlack)
        )
        .overlay(
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isNotchHovered ? 0.24 : 0.14),
                        Color.white.opacity(0.04),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.6
            )
            .allowsHitTesting(false)
        )
        .clipShape(shape)
        .shadow(color: Color.black.opacity(isExpanded ? 0.45 : 0.24), radius: isExpanded ? 26 : 10, y: isExpanded ? 12 : 4)
        .animation(GravMotionPreferences.shared.spec(.morph).animation, value: isExpanded)
        .animation(GravMotionPreferences.shared.spec(.settle).animation, value: state.selectedMockNotchTab)
    }

    @ViewBuilder
    private var notchTabBody: some View {
        switch state.selectedMockNotchTab {
        case .thinking:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("STEP 14 · REASONING")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(GravPalette.thinking)
                    Spacer()
                    Text("18.4k in · 412 out")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.48))
                }

                Text("Evaluating 5×5 fold-free MeshGradient vertex bounds so Coons patches remain diffeomorphic at 120Hz. Next, binding Step 3 System Settings toggles directly to PreferencesStore…")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.86))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(GravPalette.emerald)
                    Text("Zero background polling · kqueue active")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.white.opacity(0.52))
                }
                .padding(.top, 2)
            }
            .padding(12)
            .background(
                Radius.rect(Radius.controlM)
                    .fill(Color.white.opacity(0.055))
                    .overlay(
                        Radius.rect(Radius.controlM)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )

        case .diffs:
            VStack(spacing: 7) {
                mockDiffRow(file: "GravOnboardingWelcome.swift", path: "Grav/Features/Onboarding", added: 148, removed: 12)
                mockDiffRow(file: "GravOnboardingMockHost.swift", path: "Grav/Features/Onboarding", added: 86, removed: 4)
                mockDiffRow(file: "OnboardingWindowController.swift", path: "Grav/Features/Onboarding", added: 64, removed: 29)
            }

        case .logs:
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("$ swift build --target Grav")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.92))
                    Spacer()
                    Text("EXIT 0 · 1.4s")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(GravPalette.emerald)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(GravPalette.emerald.opacity(0.16))
                        )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Compiling GravOnboardingWelcome.swift…")
                    Text("Compiling GravOnboardingMockHost.swift…")
                    Text("Build complete! (0 warnings, Swift 6 strict)")
                        .foregroundStyle(GravPalette.emerald.opacity(0.92))
                }
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.66))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Radius.rect(Radius.controlM)
                    .fill(Color.white.opacity(0.055))
                    .overlay(
                        Radius.rect(Radius.controlM)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
        }
    }

    private func mockDiffRow(file: String, path: String, added: Int, removed: Int) -> some View {
        let total = max(1, added + removed)
        let addedRatio = CGFloat(added) / CGFloat(total)

        return HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 10.5))
                .foregroundStyle(GravPalette.fileEdit)

            VStack(alignment: .leading, spacing: 1) {
                Text(file)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
                Text(path)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            HStack(spacing: 4) {
                Text("+\(added)")
                    .foregroundStyle(GravPalette.emerald)
                Text("-\(removed)")
                    .foregroundStyle(GravPalette.coral)
            }
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))

            HStack(spacing: 1) {
                Capsule().fill(GravPalette.emerald).frame(width: max(6, 34 * addedRatio), height: 4)
                Capsule().fill(GravPalette.coral).frame(width: max(4, 34 * (1 - addedRatio)), height: 4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Radius.rect(Radius.controlS)
                .fill(Color.white.opacity(0.055))
                .overlay(
                    Radius.rect(Radius.controlS)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                )
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
                        .foregroundStyle(Color.black.opacity(0.42))
                    Text("Search")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.black.opacity(0.42))
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3.5)
                .background(
                    Radius.rect(Radius.controlXS)
                        .fill(Color.black.opacity(0.06))
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
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 0.5)
                    .padding(.horizontal, 8)

                VStack(spacing: 2) {
                    sidebarItem(icon: "gearshape.fill", title: "Startup & HUD", badgeColor: GravMockPalette.gravTeal, isSelected: true)
                    sidebarItem(icon: "macbook", title: "Notch Behavior", badgeColor: GravMockPalette.macBlue, isSelected: false)
                    sidebarItem(icon: "sparkles", title: "Liquid Glass", badgeColor: Color(white: 0.45), isSelected: false)
                    sidebarItem(icon: "hand.raised.fill", title: "Local Telemetry", badgeColor: GravMockPalette.gravEmerald, isSelected: false)
                }

                Spacer()
            }
            .frame(width: 140)
            .background(Color(red: 0.942, green: 0.946, blue: 0.955))

            Rectangle()
                .fill(Color.black.opacity(0.09))
                .frame(width: 0.5)

            // Right Detail Pane bound LIVE to PreferencesStore
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(Color.black.opacity(0.45))
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Color.black.opacity(0.18))
                    }
                    .font(.system(size: 9.5, weight: .semibold))

                    Text("Startup & HUD")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(GravMockPalette.ink)

                    Spacer()

                    Text("Live")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(GravMockPalette.gravTeal)
                        .padding(.horizontal, 6.5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(GravMockPalette.gravTeal.opacity(0.12))
                        )
                }
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Color(red: 0.968, green: 0.970, blue: 0.976))

                Rectangle()
                    .fill(Color.black.opacity(0.06))
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
                .background(Color.white)
                .clipShape(Radius.rect(Radius.controlM))
                .overlay(
                    Radius.rect(Radius.controlM)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                )
                .padding(.horizontal, 14)
                .padding(.top, 12)

                Spacer(minLength: 8)

                Rectangle()
                    .fill(Color.black.opacity(0.07))
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
                                    .fill(isRestoreHovered ? Color(white: 0.94) : Color.white)
                                    .overlay(
                                        Radius.rect(Radius.controlXS)
                                            .strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5)
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
                                    .shadow(color: Color.black.opacity(0.12), radius: 1, y: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { isDoneHovered = $0 }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(red: 0.955, green: 0.958, blue: 0.965))
            }
            .background(Color(red: 0.962, green: 0.965, blue: 0.972))
        }
        .frame(width: 512, height: 322)
        .clipShape(Radius.rect(Radius.card))
        .overlay(
            Radius.rect(Radius.card)
                .strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.24), radius: 22, x: 0, y: 10)
        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.06))
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
                    .fill(isOn ? GravMockPalette.gravTeal : Color.black.opacity(0.16))
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
