import NotchKit
import SwiftUI

/// Native grouped-form Notch HUD preferences pane with a 1:1 live macOS Liquid Glass Notch HUD
/// mockup (embedding the real `ExpandedNotchView` + live collapsed pill), Interaction,
/// Smart Attention Rules, Display & Feedback, and Quick Actions.
struct NotchHUDSettingsPane: View {
    private struct DurationOption: Identifiable, Hashable {
        let value: Double
        let label: String
        var id: Double { value }
    }

    private static let durationOptions: [DurationOption] = [
        .init(value: 0.0, label: "Always"),
        .init(value: 10.0, label: "> 10s"),
        .init(value: 30.0, label: "> 30s"),
        .init(value: 60.0, label: "> 60s"),
    ]

    @Bindable var preferences: PreferencesStore
    let store: AntigravityTelemetryStore
    var onToggleNotch: (() -> Void)?

    private var selectedDurationOption: Binding<DurationOption> {
        Binding(
            get: {
                Self.durationOptions.first(where: { abs($0.value - preferences.smartAlertMinDurationSeconds) < 0.5 })
                    ?? Self.durationOptions[0]
            },
            set: { preferences.smartAlertMinDurationSeconds = $0.value }
        )
    }

    var body: some View {
        SettingsPageCanvas(
            tab: .notchHUD,
            subtitle: "120Hz hardware notch telemetry, hover physics, Smart Attention rules, and display density."
        ) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 6, height: 6)
                    Text(statusLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )

                if let onToggleNotch {
                    SettingsActionPill(title: "Toggle Notch", systemImage: "rectangle.topthird.inset.filled") {
                        onToggleNotch()
                    }
                }
            }
        } content: {
            SettingsCardGroup(
                title: "Live 1:1 Preview",
                badge: "MACOS NOTCH",
                staggerIndex: 0,
                contentPadding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
            ) {
                GravNotchHUDLivePreviewCard(
                    preferences: preferences,
                    store: store
                )
            }

            SettingsCardGroup(title: "Interaction & Trigger", staggerIndex: 1) {
                SettingRow(
                    title: "Hover to Expand",
                    description: "Resting the pointer over the notch smoothly expands live telemetry."
                ) {
                    Toggle("", isOn: $preferences.hoverToExpand)
                        .labelsHidden()
                }

                SettingsRowDivider()

                SettingRow(
                    title: "Pin Notch Open",
                    description: "Keep the expanded telemetry panel visible until dismissed manually."
                ) {
                    Toggle("", isOn: $preferences.isNotchPinned)
                        .labelsHidden()
                }

                SettingsRowDivider()

                SettingRow(
                    title: "Auto-Peek on Events",
                    description: "Briefly surface the notch on new thinking bursts, file edits, and completed commands."
                ) {
                    Toggle("", isOn: $preferences.autoPeekOnEvents)
                        .labelsHidden()
                }

                SettingsRowDivider()

                SettingRow(
                    title: "Auto-Expand on Input Needed",
                    description: "Automatically expand the Notch HUD when Antigravity asks a question or waits for approval."
                ) {
                    Toggle("", isOn: $preferences.autoExpandOnNeedsInput)
                        .labelsHidden()
                }

                SettingsRowDivider()

                SettingRow(
                    title: "Hover Open Delay",
                    description: "How long the pointer must rest over the notch before expanding."
                ) {
                    HStack(spacing: 8) {
                        Slider(value: $preferences.hoverOpenDelay, in: 0.05...0.50, step: 0.05)
                            .frame(width: 124)
                        Text("\(Int((preferences.hoverOpenDelay * 1000).rounded())) ms")
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                .disabled(!preferences.hoverToExpand)
                .opacity(preferences.hoverToExpand ? 1.0 : 0.45)
            }

            SettingsCardGroup(title: "Smart Attention Rules", badge: "SMART", staggerIndex: 2) {
                SettingRow(
                    title: "Minimum Turn Duration",
                    description: "Only chime or peek on turn completion if Antigravity worked longer than this threshold."
                ) {
                    SettingsSegmentedPill(
                        options: Self.durationOptions,
                        selection: selectedDurationOption,
                        label: \.label
                    )
                }

                SettingsRowDivider()

                SettingRow(
                    title: "Urgent Alert When Backgrounded",
                    description: "Automatically expand the Notch and alert when Antigravity fails or asks for input while you're in another app."
                ) {
                    Toggle("", isOn: $preferences.urgentAlertWhenBackgrounded)
                        .labelsHidden()
                }

                SettingsRowDivider()

                SettingRow(
                    title: "Notify on Turn Completion",
                    description: "Surface a subtle peek & completion chime when Antigravity finishes a response."
                ) {
                    Toggle("", isOn: $preferences.notifyOnTurnCompleted)
                        .labelsHidden()
                }

                SettingsRowDivider()

                SettingRow(
                    title: "Notify on Failures",
                    description: "Alert immediately when a shell command or tool execution fails."
                ) {
                    Toggle("", isOn: $preferences.notifyOnFailure)
                        .labelsHidden()
                }
            }

            SettingsCardGroup(title: "Display & Feedback", staggerIndex: 3) {
                SettingRow(
                    title: "Show Live Focus",
                    description: "Show Antigravity's live task focus headline inside the collapsed Notch pill."
                ) {
                    Toggle("", isOn: $preferences.showCollapsedFocus)
                        .labelsHidden()
                }

                SettingsRowDivider()

                SettingRow(
                    title: "Show Step Progress Ring",
                    description: "Display the circular N/M step progress indicator in the collapsed pill."
                ) {
                    Toggle("", isOn: $preferences.showCollapsedStepProgress)
                        .labelsHidden()
                }

                SettingsRowDivider()

                SettingRow(
                    title: "Show Idle Token Count",
                    description: "Display live rolling ↓In / ↑Out token odometers inside the collapsed Notch pill."
                ) {
                    Toggle("", isOn: $preferences.showCollapsedTokens)
                        .labelsHidden()
                }

                SettingsRowDivider()

                SettingRow(
                    title: "Haptic Feedback",
                    description: "Trigger subtle Force Touch haptics when the Notch HUD opens on hover."
                ) {
                    Toggle("", isOn: $preferences.hapticsEnabled)
                        .labelsHidden()
                }

                SettingsRowDivider()

                SettingRow(
                    title: "Play Sounds",
                    description: "Play crisp audio cues for turn completions, command failures, and Mini Pet interactions."
                ) {
                    Toggle("", isOn: $preferences.playSounds)
                        .labelsHidden()
                }
            }
        }
    }

    private var isPaused: Bool {
        store.isPaused || preferences.isTelemetryPaused
    }

    private var statusLabel: String {
        if isPaused { return "Paused" }
        return store.state.label
    }

    private var statusDotColor: Color {
        if isPaused { return .secondary }
        switch store.state {
        case .idle:
            return store.connectionStatus.isBrainAccessible ? .green : .orange
        case .working:
            return .primary
        case .compacting:
            return .purple
        case .thinking, .replying, .inspecting, .toolActivity:
            return .cyan
        case .editing:
            return .orange
        case .runningCommand:
            return .green
        case .waitingForInput:
            return .yellow
        }
    }

    private var statusSubtitle: String {
        if isPaused {
            return "Telemetry is paused — resume from Telemetry settings or the menu bar."
        }
        let triggerText = preferences.hoverToExpand ? "Hover-to-expand active" : "Click-only trigger active"
        let pinText = preferences.isNotchPinned ? "Pinned open" : "Auto-collapses on exit"
        return "\(triggerText) · \(pinText)"
    }
}

// MARK: - 1:1 macOS Liquid Glass Hardware Notch HUD Live Mockup

/// 1:1 pixel-faithful macOS desktop & hardware Notch HUD mockup embedding the ACTUAL live
/// `ExpandedNotchView` + real reactive collapsed pill over Apple's Pro Black wallpaper &
/// Liquid Glass macOS menu bar. Updates in real time with every preference toggle!
private struct GravNotchHUDLivePreviewCard: View {
    let preferences: PreferencesStore
    let store: AntigravityTelemetryStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded: Bool = true
    @State private var hoverExpandTask: Task<Void, Never>?

    private var formattedClock: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    var body: some View {
        GeometryReader { geo in
            let availableWidth = max(320, geo.size.width)
            let realExpandedWidth = NotchHUDCoordinator.expandedPanelSize.width
            let realExpandedHeight = NotchHUDCoordinator.expandedPanelSize.height
            let scale = min(0.86, max(0.68, (availableWidth - 28) / realExpandedWidth))
            let scaledExpandedW = realExpandedWidth * scale
            let scaledExpandedH = realExpandedHeight * scale

            ZStack(alignment: .top) {
                // 1. Authentic Apple Pro Black macOS dark desktop wallpaper
                GravMockWallpaper(app: .notchHud).equatable()

                // 2. Authentic macOS Tahoe Liquid Glass Menu Bar
                HStack(spacing: 11) {
                    HStack(spacing: 10) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text("Antigravity")
                            .font(.system(size: 11, weight: .semibold))
                        Text("File")
                            .font(.system(size: 11))
                            .opacity(0.76)
                        Text("Edit")
                            .font(.system(size: 11))
                            .opacity(0.76)
                        Text("View")
                            .font(.system(size: 11))
                            .opacity(0.76)
                    }
                    .foregroundStyle(.white.opacity(0.90))

                    Spacer(minLength: 0)

                    HStack(spacing: 9) {
                        GravOrbitalMark(size: 12, tint: .white.opacity(0.86))
                        Image(systemName: "switch.2")
                            .font(.system(size: 10.5, weight: .medium))
                        Image(systemName: "wifi")
                            .font(.system(size: 10.5, weight: .medium))
                        Image(systemName: "battery.100percent")
                            .font(.system(size: 11, weight: .medium))
                        Text(formattedClock)
                            .font(.system(size: 10.5, weight: .medium))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.white.opacity(0.88))
                }
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(.ultraThinMaterial)
                .background(Color.black.opacity(0.18))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.white.opacity(0.11))
                        .frame(height: 0.5)
                }

                // 3. Flush-at-y=0 Authentic Hardware `NotchShape` Hosting REAL Live Notch HUD
                let notchShape = NotchShape(
                    topCornerRadius: 6,
                    bottomCornerRadius: isExpanded ? 20 : 11
                )

                ZStack(alignment: .top) {
                    if !isExpanded {
                        liveCollapsedPillPreview
                            .transition(.opacity)
                    } else {
                        ExpandedNotchView(
                            store: store,
                            preferences: preferences,
                            onCollapse: {
                                withAnimation(reduceMotion ? nil : .timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.24)) {
                                    isExpanded = false
                                }
                            },
                            onOpenSettings: {}
                        )
                        .padding(.top, 10)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .frame(width: realExpandedWidth, height: realExpandedHeight)
                        .scaleEffect(scale, anchor: .top)
                        .frame(width: scaledExpandedW, height: scaledExpandedH, alignment: .top)
                        .transition(.opacity)
                    }
                }
                .frame(
                    width: isExpanded ? scaledExpandedW : 268,
                    height: isExpanded ? scaledExpandedH : 30,
                    alignment: .top
                )
                .background(notchShape.fill(Color.black))
                .clipShape(notchShape)
                .overlay(
                    notchShape.stroke(
                        Color.white.opacity(isExpanded ? 0.10 : 0.06),
                        lineWidth: 0.5
                    )
                    .allowsHitTesting(false)
                )
                .shadow(
                    color: Color.black.opacity(isExpanded ? 0.58 : 0.22),
                    radius: isExpanded ? 26 : 6,
                    y: isExpanded ? 12 : 3
                )
                .onHover { hovering in
                    hoverExpandTask?.cancel()
                    if hovering && !isExpanded && preferences.hoverToExpand {
                        let delay = preferences.hoverOpenDelay
                        hoverExpandTask = Task { @MainActor in
                            try? await Task.sleep(for: .seconds(delay))
                            guard !Task.isCancelled else { return }
                            withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84)) {
                                isExpanded = true
                            }
                        }
                    } else if !hovering && isExpanded && preferences.hoverToExpand && !preferences.isNotchPinned {
                        hoverExpandTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(220))
                            guard !Task.isCancelled else { return }
                            withAnimation(reduceMotion ? nil : .timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.24)) {
                                isExpanded = false
                            }
                        }
                    }
                }

                // 4. Liquid Glass State Toggle Pill (bottom-right of desktop preview)
                VStack {
                    Spacer()
                    HStack {
                        Text(isExpanded ? "1:1 Live Expanded HUD" : "1:1 Live Collapsed Pill")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.54))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .liquidGlassSurface(
                                shape: Capsule(style: .continuous),
                                substrate: 0.22,
                                tint: 0.10,
                                highlight: .custom(top: 0.24, bottom: 0.06),
                                nativeGlassTint: Color.black.opacity(0.25),
                                nativeVariant: .clear
                            )

                        Spacer()

                        HStack(spacing: 2) {
                            modePillButton(title: "Collapsed", active: !isExpanded) {
                                withAnimation(reduceMotion ? nil : .timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.24)) {
                                    isExpanded = false
                                }
                            }
                            modePillButton(title: "Expanded", active: isExpanded) {
                                withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84)) {
                                    isExpanded = true
                                }
                            }
                        }
                        .padding(2.5)
                        .liquidGlassSurface(
                            shape: Capsule(style: .continuous),
                            substrate: 0.24,
                            tint: 0.12,
                            highlight: .custom(top: 0.28, bottom: 0.08),
                            nativeGlassTint: Color.black.opacity(0.28),
                            nativeVariant: .clear
                        )
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(
                reduceMotion
                    ? nil
                    : (isExpanded
                        ? .spring(response: 0.34, dampingFraction: 0.84)
                        : .timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.24)),
                value: isExpanded
            )
        }
        .environment(\.colorScheme, .dark)
        .frame(height: 332)
        .clipShape(Radius.rect(Radius.card))
        .overlay(
            Radius.rect(Radius.card)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.6)
        )
        .onDisappear {
            hoverExpandTask?.cancel()
        }
    }

    private var liveCollapsedPillPreview: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                GravAppIconTile(size: 18)
                if store.state.isActive && !store.isPaused {
                    NotchBars(
                        reduceMotion
                            ? .steady([0.4, 0.85, 0.55], barWidth: 1.5, spacing: 1.6, height: 9, tint: GravPalette.thinking)
                            : .wave(count: 3, low: 0.24, high: 0.96, barWidth: 1.5, spacing: 1.6, height: 9, period: 0.72, stagger: 0.12, tint: GravPalette.thinking)
                    )
                } else {
                    Text("Grav")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.78))
                }
            }

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                if store.state.isActive && !store.isPaused {
                    if preferences.showCollapsedFocus, let focus = store.currentFocus, !focus.isEmpty {
                        Text(focus)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.88))
                            .lineLimit(1)
                    } else {
                        Text(store.state.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.86))
                            .lineLimit(1)
                    }

                    if preferences.showCollapsedStepProgress, let steps = store.stepsProgress, !steps.isAllDone {
                        Text("\(steps.completedCount)/\(steps.totalCount)")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.66))
                    }
                } else {
                    if preferences.showCollapsedTokens && store.tokenMetrics.totalTokens > 0 {
                        NotchTokenFlowDisplay(
                            metrics: store.tokenMetrics,
                            isStreaming: false,
                            style: .collapsedIdle(compact: false),
                            reduceMotion: reduceMotion
                        )
                    } else if preferences.showCollapsedFocus {
                        Text("Ready")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.46))
                    }

                    Circle()
                        .fill(store.connectionStatus.isAppRunning ? GravPalette.emerald.opacity(0.85) : GravPalette.idleDot)
                        .frame(width: 5, height: 5)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84)) {
                isExpanded = true
            }
        }
    }

    private func modePillButton(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? .white : Color.white.opacity(0.60))
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(
                    Capsule(style: .continuous)
                        .fill(active ? Color.white.opacity(0.18) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}
