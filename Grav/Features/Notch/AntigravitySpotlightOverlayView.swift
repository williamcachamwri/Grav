import AppKit
import SwiftUI

// MARK: - Profile, Usage & Models Drawer (`⌘U`)

/// Swiss-precision Account, Usage & Models drawer inside Grav's Expanded Notch.
/// Strict anti-AI-slop standard: zero filler badges, zero apologetic callout boxes,
/// zero empty "Unused" rows — pure tabular typographic hierarchy, a single 3pt proportional
/// model-share hairline, and 120Hz `matchedGeometryEffect` spring transitions.
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
    @State private var animateBars: Bool = false
    @State private var isRefreshing: Bool = false
    @State private var hoveredModelID: String?
    @State private var copiedModelID: String?

    public init(
        store: AntigravityTelemetryStore,
        onDismiss: @escaping () -> Void
    ) {
        self.store = store
        self.onDismiss = onDismiss
    }

    private var snapshot: AntigravityProfileSnapshot {
        store.profileSnapshot ?? AntigravityProfileSnapshot(
            displayName: NSFullUserName().isEmpty ? "Antigravity User" : NSFullUserName()
        )
    }

    private var activeModelsWithUsage: [AntigravityAvailableModel] {
        snapshot.availableModels.filter { $0.recentTokens7d > 0 || $0.recentTurns7d > 0 || isCurrentActiveModel($0) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            accountHeaderBar

            Rectangle()
                .fill(Color.white.opacity(0.07))
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
            .animation(reduceMotion ? nil : .spring(duration: 0.26, bounce: 0.05), value: selectedSection)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.068, green: 0.072, blue: 0.084).opacity(0.985))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.11), lineWidth: 0.6)
                )
        )
        .shadow(color: Color.black.opacity(0.48), radius: 16, y: 6)
        .onAppear {
            store.refreshProfileSnapshot()
            if reduceMotion {
                animateBars = true
            } else {
                animateBars = false
                withAnimation(.spring(duration: 0.50, bounce: 0.06).delay(0.04)) {
                    animateBars = true
                }
            }
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    // MARK: - Minimal Account Header Bar

    private var accountHeaderBar: some View {
        HStack(spacing: 9) {
            avatarBadge

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(snapshot.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(-0.18)
                        .foregroundStyle(Color.white.opacity(0.94))
                        .lineLimit(1)

                    if let planName = snapshot.planName, !planName.isEmpty {
                        Text(planName)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.62))
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.075))
                            )
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                if let email = snapshot.email, !email.isEmpty {
                    Text(email)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 6)

            sectionSegmentedPill

            Button {
                GravOnboardingWelcomeAudio.shared.playButtonTap()
                store.activateAntigravityApp()
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.50))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(NotchChromeButtonStyle(isActive: false, cornerRadius: 6))
            .help("Open Antigravity")

            Button {
                triggerRefresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.48))
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(NotchChromeButtonStyle(isActive: false, cornerRadius: 6))
            .help("Refresh")

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.48))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(NotchChromeButtonStyle(isActive: false, cornerRadius: 6))
            .help("Close (Esc)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var avatarBadge: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.075))

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
        .frame(width: 26, height: 26)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        )
    }

    private var initialsText: some View {
        Text(snapshot.initials)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.78))
    }

    private var sectionSegmentedPill: some View {
        HStack(spacing: 2) {
            ForEach(ProfileSection.allCases) { section in
                let isSelected = selectedSection == section
                Button {
                    GravOnboardingWelcomeAudio.shared.playTabSwitch()
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.26, bounce: 0.08)) {
                        selectedSection = section
                    }
                } label: {
                    HStack(spacing: 3.5) {
                        Text(section.rawValue)
                            .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.46))

                        if section == .models && !snapshot.availableModels.isEmpty {
                            Text("\(snapshot.availableModels.count)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(isSelected ? Color.white.opacity(0.60) : Color.white.opacity(0.28))
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 21)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                .fill(Color.white.opacity(0.11))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
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
                .fill(Color.white.opacity(0.04))
        )
    }

    // MARK: - Tab 1: Swiss Precision Usage Overview

    private var usageContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                if snapshot.hasFreshServerQuota {
                    serverQuotaSection
                } else {
                    heroTelemetryStrip
                    if !activeModelsWithUsage.isEmpty {
                        modelDistributionSection
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    /// Clean two-column Swiss metric strip (`5h Window` | `7-Day Total`) — zero boxed cards.
    private var heroTelemetryStrip: some View {
        HStack(alignment: .top, spacing: 0) {
            metricColumn(
                eyebrow: "5H WINDOW",
                value: TokenMetrics.formatCompact(snapshot.totalTokens5h),
                unit: "tokens",
                subtext: "\(snapshot.totalTurns5h.formatted()) turns"
            )

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 0.5, height: 42)
                .padding(.horizontal, 18)

            metricColumn(
                eyebrow: "7-DAY TOTAL",
                value: TokenMetrics.formatCompact(snapshot.totalTokens7d),
                unit: "tokens",
                subtext: "\(snapshot.totalTurns7d.formatted()) turns"
            )

            Spacer(minLength: 10)

            if let credits = snapshot.availableCredits {
                metricColumn(
                    eyebrow: "CREDITS",
                    value: credits.formatted(),
                    unit: "",
                    subtext: "available",
                    alignment: .trailing
                )
            } else if let active = store.activeModel, !active.isEmpty {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("ACTIVE MODEL")
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(Color.white.opacity(0.34))

                    HStack(spacing: 5) {
                        Circle()
                            .fill(GravPalette.emerald)
                            .frame(width: 5, height: 5)
                        Text(AntigravityProfileProbe.prettifyModelIdentifier(active))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.86))
                            .lineLimit(1)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private func metricColumn(
        eyebrow: String,
        value: String,
        unit: String,
        subtext: String,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(eyebrow)
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Color.white.opacity(0.34))

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .tracking(-0.4)
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.95))
                    .contentTransition(reduceMotion ? .identity : .numericText())

                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.36))
                }
            }

            Text(subtext)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.42))
        }
    }

    /// Razor-thin 3pt multi-segment proportional bar + cleanly aligned per-model breakdown.
    private var modelDistributionSection: some View {
        let items = activeModelsWithUsage
        let totalTokens = max(1, items.reduce(0) { $0 + $1.recentTokens7d })

        return VStack(alignment: .leading, spacing: 10) {
            // Single 3pt proportional distribution hairline
            GeometryReader { geo in
                let totalW = max(20, geo.size.width)
                let gap: CGFloat = items.count > 1 ? 2 : 0
                let usableW = max(10, totalW - gap * CGFloat(max(0, items.count - 1)))

                HStack(spacing: gap) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, model in
                        let share = Double(model.recentTokens7d) / Double(totalTokens)
                        let w = max(4, usableW * CGFloat(animateBars ? share : 0))
                        Capsule(style: .continuous)
                            .fill(seriesColor(for: idx))
                            .frame(width: w)
                    }
                }
            }
            .frame(height: 3)

            VStack(spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, model in
                    let sharePct = Int(((Double(model.recentTokens7d) / Double(totalTokens)) * 100.0).rounded())
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(seriesColor(for: idx))
                            .frame(width: 6, height: 6)

                        Text(model.displayName)
                            .font(.system(size: 11.5, weight: isCurrentActiveModel(model) ? .medium : .regular))
                            .foregroundStyle(Color.white.opacity(isCurrentActiveModel(model) ? 0.92 : 0.72))
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text(TokenMetrics.formatCompact(model.recentTokens7d))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(Color.white.opacity(0.84))
                            .frame(width: 44, alignment: .trailing)

                        Text("\(model.recentTurns7d)t")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(Color.white.opacity(0.38))
                            .frame(width: 42, alignment: .trailing)

                        Text("\(sharePct)%")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(Color.white.opacity(0.46))
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
        }
    }

    /// Rendered only when Antigravity provides verified, fresh, matching-account server quota rings.
    private var serverQuotaSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(snapshot.usageGroups) { group in
                let activeWindows = group.windows.filter { $0.serverRemainingFraction != nil || $0.turnsCount > 0 }
                if !activeWindows.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .tracking(-0.15)
                            .foregroundStyle(Color.white.opacity(0.92))

                        ForEach(activeWindows) { window in
                            if let remaining = window.serverRemainingFraction, let pct = window.remainingPercent {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1.5) {
                                        Text(window.label)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color.white.opacity(0.68))
                                        if let reset = window.resetCountdownLabel() {
                                            Text("Resets in \(reset)")
                                                .font(.system(size: 9.5))
                                                .foregroundStyle(Color.white.opacity(0.38))
                                        }
                                    }
                                    Spacer()
                                    HStack(spacing: 7) {
                                        Text("\(pct)% left")
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                            .monospacedDigit()
                                            .foregroundStyle(Color.white.opacity(0.72))
                                        QuotaCircularRing(
                                            progress: animateBars ? remaining : 0,
                                            color: quotaRingColor(for: remaining),
                                            size: 15,
                                            lineWidth: 2.1
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tab 2: Clean Models List (Click to Copy Model ID)

    private var modelsContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if snapshot.availableModels.isEmpty {
                VStack(spacing: 4) {
                    Text("No models observed yet")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.46))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 44)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(snapshot.availableModels.enumerated()), id: \.element.id) { idx, model in
                        modelRow(model, index: idx)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
    }

    private func modelRow(_ model: AntigravityAvailableModel, index: Int) -> some View {
        let isActive = isCurrentActiveModel(model)
        let isHovered = hoveredModelID == model.id
        let isCopied = copiedModelID == model.id

        return Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(model.rawIdentifier, forType: .string)
            GravOnboardingWelcomeAudio.shared.playButtonTap()
            copiedModelID = model.id
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                if copiedModelID == model.id {
                    copiedModelID = nil
                }
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(isActive ? GravPalette.emerald : seriesColor(for: index).opacity(0.55))
                    .frame(width: 5.5, height: 5.5)

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.displayName)
                        .font(.system(size: 11.5, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(Color.white.opacity(isActive ? 0.96 : 0.80))
                        .lineLimit(1)

                    Text(model.rawIdentifier)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.32))
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                if isCopied {
                    Text("Copied")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(GravPalette.emerald)
                } else if let remaining = model.serverRemainingFraction, let pct = model.remainingPercent {
                    HStack(spacing: 6) {
                        Text("\(pct)%")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(Color.white.opacity(0.46))
                        QuotaCircularRing(
                            progress: animateBars ? remaining : 0,
                            color: quotaRingColor(for: remaining),
                            size: 12.5,
                            lineWidth: 1.8
                        )
                    }
                } else if model.recentTurns7d > 0 {
                    Text("\(TokenMetrics.formatCompact(model.recentTokens7d)) · \(model.recentTurns7d) turns")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.44))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6.5)
            .background(
                RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                    .fill(isHovered ? Color.white.opacity(0.065) : (isActive ? Color.white.opacity(0.04) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7.5, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredModelID = hovering ? model.id : (hoveredModelID == model.id ? nil : hoveredModelID)
        }
        .help("Click to copy model identifier")
    }

    private func seriesColor(for index: Int) -> Color {
        switch index {
        case 0: return Color.white.opacity(0.82)
        case 1: return GravPalette.glacialCyan.opacity(0.85)
        case 2: return Color.white.opacity(0.38)
        default: return Color.white.opacity(0.24)
        }
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
        return Color(red: 0.31, green: 0.67, blue: 0.36)
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
