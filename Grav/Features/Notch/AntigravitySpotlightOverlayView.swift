import AppKit
import SwiftUI

// MARK: - Inline Native Profile & Usage View (Flush Inside Notch, Zero Popover)

/// Pure borderless native macOS Notch view for Account, Activity & Models.
/// Sits directly on the pitch-black Notch surface — zero nested popover card, zero outer border,
/// zero KPI dashboard eyebrows, zero stacked rainbow bars, zero redundant sub-tabs.
public struct AntigravityProfileDrawerView: View {
    public var store: AntigravityTelemetryStore
    public var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hoveredModelID: String?
    @State private var copiedModelID: String?
    @State private var animateRing: Bool = false

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

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            accountStrip

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)
                .padding(.vertical, 8)

            HStack(alignment: .top, spacing: 14) {
                activityColumn
                    .frame(width: 224, alignment: .leading)

                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 0.5)
                    .padding(.vertical, 2)

                modelsColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            store.refreshProfileSnapshot()
            if reduceMotion {
                animateRing = true
            } else {
                animateRing = false
                withAnimation(.spring(duration: 0.50, bounce: 0.06).delay(0.04)) {
                    animateRing = true
                }
            }
        }
    }

    // MARK: - Quiet Account Line (Flush, Borderless)

    private var accountStrip: some View {
        HStack(spacing: 8) {
            avatarCircle

            VStack(alignment: .leading, spacing: 0.5) {
                HStack(spacing: 6) {
                    Text(snapshot.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineLimit(1)

                    if let planName = snapshot.planName, !planName.isEmpty {
                        Text("· \(planName)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.42))
                            .lineLimit(1)
                    }
                }

                if let email = snapshot.email, !email.isEmpty {
                    Text(email)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.white.opacity(0.38))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            Button {
                GravOnboardingWelcomeAudio.shared.playButtonTap()
                store.activateAntigravityApp()
            } label: {
                HStack(spacing: 3) {
                    Text("Open Antigravity")
                        .font(.system(size: 10.5, weight: .regular))
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 8.5, weight: .medium))
                }
                .foregroundStyle(Color.white.opacity(0.50))
            }
            .buttonStyle(.plain)
            .help("Open Antigravity to view live server quota")
        }
    }

    private var avatarCircle: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))

            if let url = snapshot.avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Text(snapshot.initials)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.76))
                    }
                }
            } else {
                Text(snapshot.initials)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.76))
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(Circle())
    }

    // MARK: - Left Column: Quiet Native Activity Rows

    private var activityColumn: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Usage")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.45))

            if snapshot.hasFreshServerQuota {
                ForEach(snapshot.usageGroups) { group in
                    let active = group.windows.filter { $0.serverRemainingFraction != nil }
                    ForEach(active) { window in
                        if let frac = window.serverRemainingFraction, let pct = window.remainingPercent {
                            HStack(spacing: 6) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(group.title)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Color.white.opacity(0.84))
                                    if let reset = window.resetCountdownLabel() {
                                        Text("Resets in \(reset)")
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(Color.white.opacity(0.36))
                                    }
                                }
                                Spacer()
                                Text("\(pct)%")
                                    .font(.system(size: 11, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundStyle(Color.white.opacity(0.68))
                                QuotaCircularRing(
                                    progress: frac,
                                    color: quotaRingColor(for: frac),
                                    size: 13,
                                    lineWidth: 1.9
                                )
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    nativeKeyValueRow(
                        label: "Last 5 hours",
                        primary: TokenMetrics.formatCompact(snapshot.totalTokens5h),
                        secondary: "\(snapshot.totalTurns5h) turns"
                    )
                    nativeKeyValueRow(
                        label: "Last 7 days",
                        primary: TokenMetrics.formatCompact(snapshot.totalTokens7d),
                        secondary: "\(snapshot.totalTurns7d) turns"
                    )
                    nativeKeyValueRow(
                        label: "This session",
                        primary: TokenMetrics.formatCompact(store.tokenMetrics.totalTokens),
                        secondary: "↑\(TokenMetrics.formatCompact(store.tokenMetrics.outputTokens))"
                    )
                    if store.tokenMetrics.latestContextTokens > 0 {
                        let fillRatio = min(1.0, max(0.0, store.tokenMetrics.contextFillRatio))
                        let remainingRatio = max(0.0, 1.0 - fillRatio)
                        let ctxPct = Int((fillRatio * 100.0).rounded())
                        HStack(alignment: .center, spacing: 6) {
                            Text("Context")
                                .font(.system(size: 11.5, weight: .regular))
                                .foregroundStyle(Color.white.opacity(0.56))
                                .lineLimit(1)

                            Spacer(minLength: 4)

                            Text("\(ctxPct)%")
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(Color.white.opacity(0.90))
                                .contentTransition(reduceMotion ? .identity : .numericText())

                            Text(TokenMetrics.formatCompact(store.tokenMetrics.latestContextTokens))
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(Color.white.opacity(0.34))

                            QuotaCircularRing(
                                progress: animateRing ? remainingRatio : 0,
                                color: quotaRingColor(for: remainingRatio),
                                size: 13.5,
                                lineWidth: 2.0
                            )
                        }
                    }
                }
            }
        }
    }

    private func nativeKeyValueRow(label: String, primary: String, secondary: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.56))
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(primary)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.90))

            Text(secondary)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.34))
                .frame(minWidth: 46, alignment: .trailing)
        }
    }

    // MARK: - Right Column: Borderless Native Models List

    private var modelsColumn: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Models")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.45))

            if snapshot.availableModels.isEmpty {
                Text("No models active yet")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.36))
                    .padding(.top, 2)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 1) {
                        ForEach(snapshot.availableModels) { model in
                            inlineModelRow(model)
                        }
                    }
                }
            }
        }
    }

    private func inlineModelRow(_ model: AntigravityAvailableModel) -> some View {
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
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isActive ? Color.white.opacity(0.90) : .clear)
                    .frame(width: 11)

                Text(model.displayName)
                    .font(.system(size: 11.5, weight: isActive ? .medium : .regular))
                    .foregroundStyle(Color.white.opacity(isActive ? 0.94 : 0.68))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                if isCopied {
                    Text("Copied")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(GravPalette.emerald)
                } else if let remaining = model.serverRemainingFraction, let pct = model.remainingPercent {
                    HStack(spacing: 5) {
                        Text("\(pct)%")
                            .font(.system(size: 10, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(Color.white.opacity(0.46))
                        QuotaCircularRing(
                            progress: remaining,
                            color: quotaRingColor(for: remaining),
                            size: 11.5,
                            lineWidth: 1.7
                        )
                    }
                } else if model.recentTokens7d > 0 {
                    Text(TokenMetrics.formatCompact(model.recentTokens7d))
                        .font(.system(size: 10.5, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.38))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.white.opacity(0.065) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredModelID = hovering ? model.id : (hoveredModelID == model.id ? nil : hoveredModelID)
        }
        .help("Copy \(model.rawIdentifier)")
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
