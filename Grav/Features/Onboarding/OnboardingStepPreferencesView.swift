import Observation
import SwiftUI

/// Step 3 left-rail content: Dark Liquid Glass preference cards bound directly to `PreferencesStore`.
public struct OnboardingStepPreferencesRail: View {
    @Bindable public var preferences: PreferencesStore

    public init(preferences: PreferencesStore) {
        self.preferences = preferences
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            // 1. Launch at Login (SMAppService.mainApp)
            PreferenceToggleCard(
                icon: "power",
                title: "Launch at Login",
                subtitle: "Start Grav automatically in the background when you sign in to macOS.",
                isOn: $preferences.launchAtLogin,
                footnote: preferences.launchAtLoginError
            )

            // 2. Auto-Peek on Command Failure & Completion
            PreferenceToggleCard(
                icon: "bell.badge.waveform",
                title: "Auto-Peek on Command Events",
                subtitle: "Briefly peek the notch when shell commands finish, fail, or delete files.",
                isOn: $preferences.autoPeekOnEvents
            )

            // 3. Notch Interaction Mode (Hover to Expand vs Click-Only)
            OnboardingSpecularCard(elevation: .subtle, cornerRadius: GravRadius.card, padding: 14) {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle.grav(GravRadius.controlS)
                                .fill(GravPalette.cardFillBase)
                                .frame(width: 30, height: 30)
                                .overlay(
                                    RoundedRectangle.grav(GravRadius.controlS)
                                        .strokeBorder(GravPalette.specularStroke, lineWidth: 0.5)
                                )
                            Image(systemName: preferences.hoverToExpand ? "cursorarrow.motionlines" : "cursorarrow.click")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(GravPalette.glacialTeal)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notch Interaction Mode")
                                .font(GravTypography.bodyMedium)
                                .foregroundStyle(GravPalette.inkPrimary)

                            Text("Choose how you open the expanded telemetry panel.")
                                .font(GravTypography.caption)
                                .foregroundStyle(GravPalette.inkTertiary)
                        }
                    }

                    HStack(spacing: 8) {
                        InteractionModePill(
                            title: "Hover to Expand",
                            symbolName: "cursorarrow.motionlines",
                            isSelected: preferences.hoverToExpand
                        ) {
                            withAnimation(GravMotion.railSpring) {
                                preferences.hoverToExpand = true
                            }
                        }

                        InteractionModePill(
                            title: "Click-Only",
                            symbolName: "cursorarrow.click",
                            isSelected: !preferences.hoverToExpand
                        ) {
                            withAnimation(GravMotion.railSpring) {
                                preferences.hoverToExpand = false
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            preferences.refreshLaunchAtLoginStatus()
        }
    }
}

/// Step 3 right-stage mock: live desktop preview reflecting the user's selected notch trigger behavior
/// and startup flight-deck readiness checklist.
public struct OnboardingStepPreferencesStage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public let store: AntigravityTelemetryStore
    public let preferences: PreferencesStore

    public init(store: AntigravityTelemetryStore, preferences: PreferencesStore) {
        self.store = store
        self.preferences = preferences
    }

    public var body: some View {
        OnboardingStageFrame(showMenuBar: true) {
            VStack(spacing: 16) {
                Spacer(minLength: 36)

                // Live Notch Trigger & Auto-Peek Preview
                OnboardingSpecularCard(elevation: .base, cornerRadius: GravRadius.card, padding: 18) {
                    VStack(spacing: 14) {
                        HStack {
                            Text("NOTCH TRIGGER PROFILE")
                                .font(GravTypography.monoMicro)
                                .tracking(1.1)
                                .foregroundStyle(GravPalette.inkTertiary)
                            Spacer()
                            Text(preferences.hoverToExpand ? "HOVER ARMED" : "CLICK ARMED")
                                .font(GravTypography.monoMicro)
                                .foregroundStyle(GravPalette.glacialCyan)
                        }

                        // Miniature notch housing responding live to preference switches
                        VStack(spacing: 10) {
                            HStack(spacing: 10) {
                                GravOrbitalMark(size: 14, tint: GravPalette.titaniumWhite)

                                Text(preferences.hoverToExpand ? "Glide pointer into notch to expand" : "Click notch pill to expand")
                                    .font(GravTypography.monoCaption)
                                    .foregroundStyle(GravPalette.inkPrimary)

                                Spacer()

                                Image(systemName: preferences.hoverToExpand ? "cursorarrow.motionlines" : "cursorarrow.click")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(GravPalette.glacialTeal)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle.grav(GravRadius.card)
                                    .fill(GravPalette.notchBlack)
                            )
                            .overlay(
                                RoundedRectangle.grav(GravRadius.card)
                                    .strokeBorder(GravPalette.specularStroke, lineWidth: 0.5)
                            )

                            // Auto-Peek indicator strip
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(preferences.autoPeekOnEvents ? GravPalette.emerald : GravPalette.inkQuaternary)
                                    .frame(width: 6, height: 6)

                                Text(
                                    preferences.autoPeekOnEvents
                                        ? "Auto-Peek active for exit status & file deletes"
                                        : "Auto-Peek muted — open notch manually anytime"
                                )
                                .font(GravTypography.caption)
                                .foregroundStyle(preferences.autoPeekOnEvents ? GravPalette.inkSecondary : GravPalette.inkTertiary)

                                Spacer()
                            }
                        }
                    }
                }
                .frame(maxWidth: 440)

                // Flight-Deck Readiness Checklist
                OnboardingSpecularCard(elevation: .subtle, cornerRadius: GravRadius.card, padding: 18) {
                    VStack(alignment: .leading, spacing: 11) {
                        Text("FLIGHT-DECK READINESS")
                            .font(GravTypography.monoMicro)
                            .tracking(1.1)
                            .foregroundStyle(GravPalette.inkTertiary)

                        ReadinessRow(
                            label: "Antigravity Brain Link",
                            value: store.connectionStatus.isBrainAccessible ? "Verified" : "Pending Access",
                            isReady: store.connectionStatus.isBrainAccessible
                        )

                        ReadinessRow(
                            label: "Launch at Login",
                            value: preferences.launchAtLogin ? "Enabled" : "Manual Launch",
                            isReady: preferences.launchAtLogin
                        )

                        ReadinessRow(
                            label: "Event Auto-Peek",
                            value: preferences.autoPeekOnEvents ? "Enabled" : "Muted",
                            isReady: preferences.autoPeekOnEvents
                        )

                        ReadinessRow(
                            label: "Notch Trigger",
                            value: preferences.hoverToExpand ? "Hover to Expand" : "Click-Only",
                            isReady: true
                        )
                    }
                }
                .frame(maxWidth: 440)
                .animation(reduceMotion ? GravMotion.subtleFade : GravMotion.railSpring, value: preferences.hoverToExpand)
                .animation(reduceMotion ? GravMotion.subtleFade : GravMotion.railSpring, value: preferences.autoPeekOnEvents)
                .animation(reduceMotion ? GravMotion.subtleFade : GravMotion.railSpring, value: preferences.launchAtLogin)

                Spacer(minLength: 82)
            }
            .padding(.horizontal, 28)
        }
    }
}

// MARK: - Supporting Controls

private struct PreferenceToggleCard: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var footnote: String? = nil

    var body: some View {
        OnboardingSpecularCard(
            elevation: .subtle,
            cornerRadius: GravRadius.card,
            isHighlighted: isOn,
            padding: 14
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 11) {
                    ZStack {
                        RoundedRectangle.grav(GravRadius.controlS)
                            .fill(isOn ? GravPalette.glacialTeal.opacity(0.18) : GravPalette.cardFillBase)
                            .frame(width: 30, height: 30)
                            .overlay(
                                RoundedRectangle.grav(GravRadius.controlS)
                                    .strokeBorder(
                                        isOn ? GravPalette.glacialTeal.opacity(0.42) : GravPalette.specularStroke,
                                        lineWidth: 0.5
                                    )
                            )
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isOn ? GravPalette.glacialCyan : GravPalette.inkSecondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(GravTypography.bodyMedium)
                            .foregroundStyle(GravPalette.inkPrimary)

                        Text(subtitle)
                            .font(GravTypography.caption)
                            .foregroundStyle(GravPalette.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Toggle("", isOn: $isOn)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .tint(GravPalette.glacialTeal)
                        .accessibilityLabel(title)
                }

                if let footnote, !footnote.isEmpty {
                    Text(footnote)
                        .font(GravTypography.monoMicro)
                        .foregroundStyle(GravPalette.fileEdit)
                        .padding(.leading, 41)
                }
            }
        }
    }
}

private struct InteractionModePill: View {
    let title: String
    let symbolName: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbolName)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(GravTypography.caption)
            }
            .foregroundStyle(isSelected ? GravPalette.obsidianVoid : GravPalette.inkSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle.grav(GravRadius.controlS)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(GravPalette.brandAccentGradient)
                            : AnyShapeStyle(isHovered ? GravPalette.cardFillElevated : GravPalette.cardFillBase)
                    )
            )
            .overlay(
                RoundedRectangle.grav(GravRadius.controlS)
                    .strokeBorder(
                        isSelected ? Color.white.opacity(0.35) : GravPalette.specularStroke,
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

private struct ReadinessRow: View {
    let label: String
    let value: String
    let isReady: Bool

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: isReady ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isReady ? GravPalette.emerald : GravPalette.inkQuaternary)
                Text(label)
                    .font(GravTypography.body)
                    .foregroundStyle(GravPalette.inkSecondary)
            }

            Spacer()

            Text(value)
                .font(GravTypography.monoMicro)
                .foregroundStyle(isReady ? GravPalette.inkPrimary : GravPalette.inkTertiary)
        }
    }
}
