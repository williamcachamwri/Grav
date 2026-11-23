import AppKit
import SwiftUI

// MARK: - Profile, Usage & Available Models Drawer (`⌘U`)

/// Precision macOS Craft inline Profile, Usage & Available Models drawer inside Grav's Expanded Notch.
/// Anti-AI-slop design: pure obsidian matte surfaces, `0.5px` hairlines, tabular monospaced figures,
/// animated circular quota rings, and `matchedGeometryEffect` spring tab switching.
public struct AntigravityProfileDrawerView: View {
    public var store: AntigravityTelemetryStore
    public var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var profileTabNamespace

    private enum ProfileSection: String, CaseIterable, Identifiable {
        case usage = "Usage"
        case models = "Models"
        var id: String { rawValue }
    }

    @State private var selectedSection: ProfileSection = .usage
    @State private var animateRings: Bool = false
    @State private var isRefreshing: Bool = false

    public init(
        store: AntigravityTelemetryStore,
        onDismiss: @escaping () -> Void
    ) {
        self.store = store
        self.onDismiss = onDismiss
    }

    private var snapshot: AntigravityProfileSnapshot {
        store.profileSnapshot ?? AntigravityProfileSnapshot(
            displayName: NSFullUserName().isEmpty ? "Antigravity User" : NSFullUserName(),
            planName: "Antigravity"
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            accountHeaderBar

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)

            ZStack {
                switch selectedSection {
                case .usage:
                    usageContent
                        .id(ProfileSection.usage)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .leading)),
                                    removal: .opacity.combined(with: .move(edge: .leading))
                                )
                        )

                case .models:
                    modelsContent
                        .id(ProfileSection.models)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                                    removal: .opacity.combined(with: .move(edge: .trailing))
                                )
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.06), value: selectedSection)

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)

            footerSummaryStrip
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.072, green: 0.076, blue: 0.090).opacity(0.985))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.65)
                )
        )
        .shadow(color: Color.black.opacity(0.50), radius: 16, y: 6)
        .onAppear {
            store.refreshProfileSnapshot()
            if reduceMotion {
                animateRings = true
            } else {
                animateRings = false
                withAnimation(.spring(duration: 0.55, bounce: 0.08).delay(0.04)) {
                    animateRings = true
                }
            }
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    // MARK: - Account Header Bar

    private var accountHeaderBar: some View {
        HStack(spacing: 9) {
            avatarBadge

            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 6) {
                    Text(snapshot.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(-0.15)
                        .foregroundStyle(Color.white.opacity(0.95))
                        .lineLimit(1)

                    if let planName = snapshot.planName, !planName.isEmpty {
                        Text(planName)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.085))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                                    )
                            )
                            .fixedSize(horizontal: true, vertical: false)
                    } else {
                        Text("Active Account")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.56))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                if let email = snapshot.email, !email.isEmpty {
                    Text(email)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.46))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 6)

            sectionSegmentedPill

            Button {
                triggerRefresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.52))
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.055))
                    )
            }
            .buttonStyle(.plain)
            .help("Refresh Usage & Models")

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.52))
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.055))
                    )
            }
            .buttonStyle(.plain)
            .help("Close Profile (Esc)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8.5)
    }

    private var avatarBadge: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.09))

            if let url = snapshot.avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        initialsText
                    }
                }
            } else {
                initialsText
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.6)
        )
    }

    private var initialsText: some View {
        Text(snapshot.initials)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.84))
    }

    private var sectionSegmentedPill: some View {
        HStack(spacing: 2) {
            ForEach(ProfileSection.allCases) { section in
                let isSelected = selectedSection == section
                Button {
                    GravOnboardingWelcomeAudio.shared.playTabSwitch()
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.10)) {
                        selectedSection = section
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(section.rawValue)
                            .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.50))

                        if section == .models && !snapshot.availableModels.isEmpty {
                            Text("\(snapshot.availableModels.count)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(isSelected ? Color.white.opacity(0.66) : Color.white.opacity(0.32))
                        }
                    }
                    .padding(.horizontal, 8.5)
                    .frame(height: 21)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                                )
                                .matchedGeometryEffect(id: "grav-profile-section-pill", in: profileTabNamespace)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }

    // MARK: - Tab 1: Usage Quota Groups (Clean Circular Rings)

    private var usageContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 11) {
                ForEach(snapshot.usageGroups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title)
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(-0.15)
                            .foregroundStyle(Color.white.opacity(0.94))

                        VStack(spacing: 6) {
                            ForEach(group.windows) { window in
                                usageWindowRow(window)
                            }
                        }
                    }
                }

                if !snapshot.hasFreshServerQuota {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.white.opacity(0.42))

                        Text("Antigravity keeps server quota % in-app only. Showing verified local token & turn volume.")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.46))
                            .lineLimit(2)

                        Spacer(minLength: 4)

                        Button {
                            GravOnboardingWelcomeAudio.shared.playButtonTap()
                            store.activateAntigravityApp()
                        } label: {
                            HStack(spacing: 3.5) {
                                Text("Live Quota")
                                    .font(.system(size: 10, weight: .medium))
                                Image(systemName: "arrow.up.forward")
                                    .font(.system(size: 8.5, weight: .semibold))
                            }
                            .foregroundStyle(Color.white.opacity(0.84))
                            .padding(.horizontal, 7.5)
                            .padding(.vertical, 3.5)
                            .background(
                                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                    .fill(Color.white.opacity(0.085))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.032))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                            )
                    )
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
        }
    }

    private func usageWindowRow(_ window: AntigravityUsageWindow) -> some View {
        let resetText = window.resetCountdownLabel()

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1.5) {
                if window.inlineResetCaption, let resetText {
                    Text("\(window.label), resets in \(resetText)")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.58))
                } else {
                    Text(window.label)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.68))

                    if let resetText {
                        Text("Resets in \(resetText)")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.40))
                    }
                }
            }

            Spacer(minLength: 8)

            if let remaining = window.serverRemainingFraction, let pct = window.remainingPercent {
                HStack(spacing: 8) {
                    Text("\(pct)% left")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.68))
                        .contentTransition(reduceMotion ? .identity : .numericText())

                    QuotaCircularRing(
                        progress: animateRings ? remaining : 0,
                        color: quotaRingColor(for: remaining),
                        size: 15.5,
                        lineWidth: 2.2
                    )
                }
            } else if window.turnsCount > 0 || window.tokensUsed > 0 {
                HStack(spacing: 6) {
                    Text("\(TokenMetrics.formatCompact(window.tokensUsed)) tok")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.80))

                    Text("·")
                        .foregroundStyle(Color.white.opacity(0.28))

                    Text("\(window.turnsCount) turn\(window.turnsCount == 1 ? "" : "s")")
                        .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.46))
                }
            } else {
                Text("Unused")
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.32))
            }
        }
    }

    // MARK: - Tab 2: Available Models Catalog

    private var modelsContent: some View {
        let families = AntigravityAvailableModel.Family.allCases.filter { fam in
            snapshot.availableModels.contains { $0.family == fam }
        }

        return ScrollView(.vertical, showsIndicators: false) {
            if snapshot.availableModels.isEmpty {
                VStack(spacing: 5) {
                    Image(systemName: "cpu")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(Color.white.opacity(0.28))
                    Text("No models discovered yet")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.46))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(families, id: \.self) { family in
                        let items = snapshot.availableModels.filter { $0.family == family }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(family.rawValue.uppercased())
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .tracking(0.6)
                                .foregroundStyle(Color.white.opacity(0.40))
                                .padding(.horizontal, 2)

                            VStack(spacing: 2.5) {
                                ForEach(items) { model in
                                    modelRow(model)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
        }
    }

    private func modelRow(_ model: AntigravityAvailableModel) -> some View {
        let isActive = isCurrentActiveModel(model)

        return HStack(spacing: 8) {
            Circle()
                .fill(isActive ? GravPalette.emerald : Color.white.opacity(0.20))
                .frame(width: 5.5, height: 5.5)

            Text(model.displayName)
                .font(.system(size: 11.5, weight: isActive ? .semibold : .regular))
                .foregroundStyle(Color.white.opacity(isActive ? 0.96 : 0.78))
                .lineLimit(1)

            if isActive {
                modelPillTag("Active", tint: GravPalette.emerald)
            } else if let tag = model.tag, !tag.isEmpty {
                modelPillTag(tag, tint: Color.white.opacity(0.65))
            }

            Spacer(minLength: 6)

            if let remaining = model.serverRemainingFraction, let pct = model.remainingPercent {
                HStack(spacing: 6) {
                    Text("\(pct)%")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.44))

                    QuotaCircularRing(
                        progress: animateRings ? remaining : 0,
                        color: quotaRingColor(for: remaining),
                        size: 12.5,
                        lineWidth: 1.8
                    )
                }
            } else if model.recentTurns7d > 0 {
                Text("\(TokenMetrics.formatCompact(model.recentTokens7d)) · \(model.recentTurns7d)t")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.46))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5.5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isActive ? Color.white.opacity(0.075) : Color.white.opacity(0.028))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isActive ? Color.white.opacity(0.11) : Color.clear, lineWidth: 0.5)
                )
        )
    }

    private func modelPillTag(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.14))
            )
    }

    // MARK: - Footer Summary Strip

    private var footerSummaryStrip: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text("5h")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.36))
                Text(TokenMetrics.formatCompact(snapshot.totalTokens5h))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.62))
            }

            HStack(spacing: 4) {
                Text("7d")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.36))
                Text(TokenMetrics.formatCompact(snapshot.totalTokens7d))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.62))
            }

            if let credits = snapshot.availableCredits {
                HStack(spacing: 4) {
                    Text("Credits")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.36))
                    Text("\(credits)")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.62))
                }
            }

            Spacer()

            if let activeModel = store.activeModel, !activeModel.isEmpty {
                Text(AntigravityProfileProbe.prettifyModelIdentifier(activeModel))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 6.5)
    }

    private func isCurrentActiveModel(_ model: AntigravityAvailableModel) -> Bool {
        guard let active = store.activeModel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !active.isEmpty
        else { return false }
        return model.rawIdentifier.caseInsensitiveCompare(active) == .orderedSame
            || model.displayName.caseInsensitiveCompare(AntigravityProfileProbe.prettifyModelIdentifier(active)) == .orderedSame
    }

    private func quotaRingColor(for fraction: Double) -> Color {
        if fraction <= 0.15 { return GravPalette.coral }
        if fraction <= 0.35 { return Color(red: 0.96, green: 0.72, blue: 0.28) }
        return Color(red: 0.31, green: 0.67, blue: 0.36) // Crisp Antigravity emerald ring
    }

    private func triggerRefresh() {
        GravOnboardingWelcomeAudio.shared.playButtonTap()
        store.refreshProfileSnapshot()
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.45)) {
            isRefreshing.toggle()
        }
    }
}

/// Crisp circular progress ring matching Antigravity's native Usage panel.
private struct QuotaCircularRing: View {
    let progress: Double
    let color: Color
    let size: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: CGFloat(min(1.0, max(0.0, progress))))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Feature #2 & A2: Approval, Question & Quota/Model Incident Banner Strip

/// Compact, anti-AI-slop matte alert strip shown only when Antigravity needs user approval/answer
/// or hits a Quota / HTTP 429 Rate-Limit / Capacity / Model Fallback event.
public struct AntigravityRadarBannerView: View {
    public let alert: AntigravityRadarAlert
    public let onFocusAntigravity: () -> Void
    public let onDismiss: () -> Void

    public init(
        alert: AntigravityRadarAlert,
        onFocusAntigravity: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.alert = alert
        self.onFocusAntigravity = onFocusAntigravity
        self.onDismiss = onDismiss
    }

    private var accentColor: Color {
        switch alert.severity {
        case .approval:
            return Color(red: 0.96, green: 0.72, blue: 0.28)
        case .modelIncident:
            return GravPalette.coral
        case .modelFallback:
            return GravPalette.glacialCyan
        }
    }

    private var symbolName: String {
        switch alert.severity {
        case .approval:
            return "hand.raised.fill"
        case .modelIncident:
            return "exclamationmark.octagon.fill"
        case .modelFallback:
            return "arrow.triangle.branch"
        }
    }

    public var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(accentColor)
                .frame(width: 2.5, height: 22)

            Image(systemName: symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accentColor)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(alert.badge)
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule(style: .continuous)
                                .fill(accentColor.opacity(0.14))
                        )

                    Text(alert.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineLimit(1)
                }

                Text(alert.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.54))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 6)

            Button {
                GravOnboardingWelcomeAudio.shared.playButtonTap()
                onFocusAntigravity()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text("Focus")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .foregroundStyle(Color.white.opacity(0.92))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Dismiss alert")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                .fill(Color.white.opacity(0.048))
                .overlay(
                    RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                        .strokeBorder(accentColor.opacity(0.26), lineWidth: 0.65)
                )
        )
    }
}
