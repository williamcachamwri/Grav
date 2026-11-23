import SwiftUI

/// Minimal monochrome segmented control (`Live | Files | Terminal`) with a spring-gliding
/// frosted selection thumb (`matchedGeometryEffect`, `GravMotion.railSpring`) and bare tabular counts.
public struct SegmentedModeRail: View {
    @Binding public var selection: NotchTab
    public var liveCount: Int
    public var replyCount: Int
    public var filesCount: Int
    public var terminalCount: Int
    public var swarmCount: Int
    public var hasStreamingReply: Bool
    public var hasRunningCommand: Bool
    public var hasActiveSwarm: Bool
    public var isTurboMode: Bool
    public var turboTheme: SuperSaiyanAuraTheme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var railNamespace
    @State private var hoveredTab: NotchTab?

    public init(
        selection: Binding<NotchTab>,
        liveCount: Int = 0,
        replyCount: Int = 0,
        filesCount: Int = 0,
        terminalCount: Int = 0,
        swarmCount: Int = 0,
        hasStreamingReply: Bool = false,
        hasRunningCommand: Bool = false,
        hasActiveSwarm: Bool = false,
        isTurboMode: Bool = false,
        turboTheme: SuperSaiyanAuraTheme = .superSaiyan
    ) {
        self._selection = selection
        self.liveCount = liveCount
        self.replyCount = replyCount
        self.filesCount = filesCount
        self.terminalCount = terminalCount
        self.swarmCount = swarmCount
        self.hasStreamingReply = hasStreamingReply
        self.hasRunningCommand = hasRunningCommand
        self.hasActiveSwarm = hasActiveSwarm
        self.isTurboMode = isTurboMode
        self.turboTheme = turboTheme
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(NotchTab.allCases) { tab in
                tabButton(for: tab)
            }
        }
        .padding(2.5)
        .background(
            RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                .fill(Color.white.opacity(0.042))
        )
    }

    private func tabButton(for tab: NotchTab) -> some View {
        let isSelected = selection == tab
        let isHovered = hoveredTab == tab
        let count = itemCount(for: tab)

        return Button {
            select(tab)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 10, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(isHovered ? 0.76 : 0.46))

                Text(tab.title)
                    .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                    .tracking(-0.15)
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(isHovered ? 0.82 : 0.56))
                    .lineLimit(1)

                if tab == .terminal && hasRunningCommand {
                    NotchSemanticDot(color: isTurboMode ? turboTheme.primaryColor : GravPalette.glacialCyan, size: 4.5, isPulsing: true)
                } else if tab == .reply && hasStreamingReply {
                    NotchSemanticDot(color: isTurboMode ? turboTheme.coreColor : GravPalette.thinking, size: 4.5, isPulsing: true)
                } else if tab == .swarm && hasActiveSwarm {
                    NotchSemanticDot(color: isTurboMode ? turboTheme.lightningColor : GravPalette.prismViolet, size: 4.5, isPulsing: true)
                } else if count > 0 {
                    Text(formatBadgeCount(count))
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Color.white.opacity(0.56) : Color.white.opacity(0.30))
                        .contentTransition(reduceMotion ? .identity : .numericText())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 23)
            .background {
                ZStack {
                    if isHovered && !isSelected {
                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                            .fill(Color.white.opacity(0.035))
                    }

                    if isSelected {
                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                            .fill(Color.white.opacity(isTurboMode ? 0.095 : 0.105))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: isTurboMode
                                                ? [
                                                    turboTheme.innerColor.opacity(0.42),
                                                    Color.white.opacity(0.04),
                                                ]
                                                : [
                                                    Color.white.opacity(0.18),
                                                    Color.white.opacity(0.03),
                                                ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 0.5
                                    )
                            )
                            .overlay(alignment: .bottom) {
                                if isTurboMode {
                                    Capsule(style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color.clear,
                                                    turboTheme.primaryColor,
                                                    turboTheme.coreColor,
                                                    turboTheme.primaryColor,
                                                    Color.clear,
                                                ],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(height: 1.4)
                                        .padding(.horizontal, 12)
                                        .shadow(color: turboTheme.primaryColor.opacity(0.78), radius: 3.5, y: 0)
                                }
                            }
                            .matchedGeometryEffect(id: "grav-notch-mode-rail-pill", in: railNamespace)
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredTab = tab
            } else if hoveredTab == tab {
                hoveredTab = nil
            }
        }
        .help("\(tab.title) (Press \(tab.shortcutLabel))")
        .accessibilityLabel("\(tab.title), \(count) items")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func formatBadgeCount(_ count: Int) -> String {
        count >= 99 ? "99+" : "\(count)"
    }

    private func select(_ tab: NotchTab) {
        guard selection != tab else { return }
        GravOnboardingWelcomeAudio.shared.playTabSwitch()
        if reduceMotion {
            selection = tab
        } else {
            withAnimation(GravMotion.railSpring) {
                selection = tab
            }
        }
    }

    private func itemCount(for tab: NotchTab) -> Int {
        switch tab {
        case .live:
            return liveCount
        case .reply:
            return replyCount
        case .files:
            return filesCount
        case .terminal:
            return terminalCount
        case .swarm:
            return swarmCount
        }
    }
}
