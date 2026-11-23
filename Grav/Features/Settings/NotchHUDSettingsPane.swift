import SwiftUI

/// Native grouped-form Notch HUD preferences pane for hover, pin, auto-peek,
/// Super Saiyan Turbo aura & transformation color picker, Turbo audio, and quick actions.
struct NotchHUDSettingsPane: View {
    @Bindable var preferences: PreferencesStore
    let store: AntigravityTelemetryStore
    var onToggleNotch: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var previewBurstNonce: Int = 0
    @State private var isPreviewSurging: Bool = true
    @State private var previewSurgeResetTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Interaction") {
                SettingRow(
                    title: "Hover to Expand",
                    description: "Resting the pointer over the notch smoothly expands live telemetry."
                ) {
                    Toggle("", isOn: $preferences.hoverToExpand)
                        .labelsHidden()
                }

                SettingRow(
                    title: "Pin Notch Open",
                    description: "Keep the expanded telemetry panel visible until dismissed manually."
                ) {
                    Toggle("", isOn: $preferences.isNotchPinned)
                        .labelsHidden()
                }

                SettingRow(
                    title: "Auto-Peek on Events",
                    description: "Briefly surface the notch on new thinking bursts, file edits, and completed commands."
                ) {
                    Toggle("", isOn: $preferences.autoPeekOnEvents)
                        .labelsHidden()
                }
            }

            Section("Turbo Mode (Super Saiyan)") {
                SettingRow(
                    title: "Super Saiyan Aura",
                    description: "Ignite the 120Hz Metal GPU Super Saiyan Ki aura on the Notch while Antigravity runs in Turbo mode."
                ) {
                    Toggle("", isOn: $preferences.turboAuraEnabled)
                        .labelsHidden()
                }

                if preferences.turboAuraEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        liveSuperSaiyanPreviewBar
                        transformationColorGrid
                    }
                    .padding(.vertical, 4)
                    .id("Transformation Color")
                }

                SettingRow(
                    title: "Turbo Power-Up Audio",
                    description: "Play seismic Super Saiyan power-up eruptions, SSJ2 lightning surges, and Ki settle soundscapes when chatting in Turbo mode."
                ) {
                    Toggle("", isOn: $preferences.turboAudioEnabled)
                        .labelsHidden()
                        .disabled(!preferences.playSounds)
                }

                SettingRow(
                    title: "Continuous Aura Resonance",
                    description: "Sustain a subtle atmospheric Super Saiyan Ki hum while Antigravity is actively thinking or replying in Turbo mode."
                ) {
                    Toggle("", isOn: $preferences.turboAuraLoopEnabled)
                        .labelsHidden()
                        .disabled(!preferences.playSounds || !preferences.turboAudioEnabled)
                }
            }

            Section("Quick Actions") {
                SettingRow(
                    title: "Notch Status",
                    description: statusSubtitle,
                    descriptionStyle: .subtitle
                ) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusDotColor)
                            .frame(width: 6, height: 6)

                        Text(statusLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                SettingRow(
                    title: "Toggle Notch HUD",
                    description: "Immediately expand or collapse the Notch HUD panel on the active display."
                ) {
                    Button("Toggle Notch") {
                        onToggleNotch?()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(onToggleNotch == nil)
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear {
            previewSurgeResetTask?.cancel()
        }
    }

    // MARK: - Live Metal Super Saiyan Preview Bar

    private var liveSuperSaiyanPreviewBar: some View {
        let theme = preferences.turboAuraTheme
        return HStack(spacing: 12) {
            // 1:1 miniature collapsed Notch pill rendering the real 120Hz Metal GPU shader
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.black)

                TurboKineticAuraCanvas(
                    style: .collapsed,
                    isPowerSurging: isPreviewSurging,
                    theme: theme,
                    burstTrigger: previewBurstNonce,
                    cornerRadius: 15,
                    reduceMotion: reduceMotion
                )
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        GravAppIconTile(size: 17)
                        TurboSolarEmblem(
                            isSurging: isPreviewSurging,
                            theme: theme,
                            reduceMotion: reduceMotion
                        )
                    }

                    Spacer(minLength: 8)

                    NotchShimmerText(
                        text: theme.displayName,
                        font: .system(size: 11, weight: .medium),
                        tracking: -0.15,
                        baseOpacity: 0.56,
                        peakOpacity: 1.0,
                        period: 1.55,
                        turboMode: true,
                        turboTheme: theme,
                        reduceMotion: reduceMotion
                    )
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 36)
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: theme.primaryColor.opacity(0.22), radius: 10, y: 2)

            Button {
                triggerPowerUpPreview(for: theme, fullEruption: true)
            } label: {
                Label("Power Up", systemImage: "bolt.fill")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help("Preview full Super Saiyan GPU shockwave and stereo power-up audio")
        }
    }

    // MARK: - 6-Form Transformation Color Picker Grid

    private var transformationColorGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ]

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Transformation Form")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                Text(preferences.turboAuraTheme.subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(SuperSaiyanAuraTheme.allCases) { theme in
                    let isSelected = preferences.turboAuraTheme == theme
                    Button {
                        selectTheme(theme)
                    } label: {
                        HStack(spacing: 8) {
                            transformationOrb(for: theme, isSelected: isSelected)

                            Text(theme.displayName)
                                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .lineLimit(1)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? theme.primaryColor.opacity(0.14) : Color.primary.opacity(0.035))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(
                                    isSelected ? theme.primaryColor.opacity(0.85) : Color.primary.opacity(0.09),
                                    lineWidth: isSelected ? 1.2 : 0.6
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func transformationOrb(for theme: SuperSaiyanAuraTheme, isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            theme.coreColor,
                            theme.primaryColor,
                            theme.outerColor,
                        ],
                        center: .center,
                        startRadius: 0.5,
                        endRadius: 8
                    )
                )
                .frame(width: 14, height: 14)
                .overlay(
                    Circle()
                        .strokeBorder(theme.lightningColor.opacity(isSelected ? 0.95 : 0.55), lineWidth: 1.0)
                )
                .shadow(color: theme.primaryColor.opacity(isSelected ? 0.72 : 0.30), radius: isSelected ? 4.5 : 2)
        }
    }

    private func selectTheme(_ theme: SuperSaiyanAuraTheme) {
        preferences.turboAuraTheme = theme
        triggerPowerUpPreview(for: theme, fullEruption: false)
    }

    private func triggerPowerUpPreview(for theme: SuperSaiyanAuraTheme, fullEruption: Bool) {
        previewBurstNonce &+= 1
        isPreviewSurging = true

        if preferences.playSounds && preferences.turboAudioEnabled {
            if fullEruption {
                SuperSaiyanAudioEngine.shared.playPowerUpEruption(theme: theme, volume: 0.80, force: true)
            } else {
                SuperSaiyanAudioEngine.shared.playLightningSurge(theme: theme, volume: 0.62, force: true)
            }
        } else {
            GravOnboardingWelcomeAudio.shared.playButtonTap()
        }

        previewSurgeResetTask?.cancel()
        previewSurgeResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.2))
            guard !Task.isCancelled else { return }
            isPreviewSurging = true
        }
    }

    // MARK: - Status Helpers

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
        case .thinking, .replying, .inspecting:
            return .cyan
        case .editing:
            return .orange
        case .runningCommand:
            return .green
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
