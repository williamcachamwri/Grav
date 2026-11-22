import SwiftUI

/// Minimal monochrome segmented control (`Live | Files | Terminal`) with a spring-gliding
/// frosted selection thumb (`matchedGeometryEffect`, `GravMotion.railSpring`) and bare tabular counts.
public struct SegmentedModeRail: View {
    @Binding public var selection: NotchTab
    public var liveCount: Int
    public var replyCount: Int
    public var filesCount: Int
    public var terminalCount: Int
    public var hasStreamingReply: Bool
    public var hasRunningCommand: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var railNamespace
    @State private var hoveredTab: NotchTab?

    public init(
        selection: Binding<NotchTab>,
        liveCount: Int = 0,
        replyCount: Int = 0,
        filesCount: Int = 0,
        terminalCount: Int = 0,
        hasStreamingReply: Bool = false,
        hasRunningCommand: Bool = false
    ) {
        self._selection = selection
        self.liveCount = liveCount
        self.replyCount = replyCount
        self.filesCount = filesCount
        self.terminalCount = terminalCount
        self.hasStreamingReply = hasStreamingReply
        self.hasRunningCommand = hasRunningCommand
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
            HStack(spacing: 5) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 10.5, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(isHovered ? 0.76 : 0.46))

                Text(tab.title)
                    .font(.system(size: 11.5, weight: isSelected ? .medium : .regular))
                    .tracking(-0.15)
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(isHovered ? 0.82 : 0.56))

                if tab == .terminal && hasRunningCommand {
                    NotchSemanticDot(color: GravPalette.glacialCyan, size: 4.5, isPulsing: true)
                } else if tab == .reply && hasStreamingReply {
                    NotchSemanticDot(color: GravPalette.thinking, size: 4.5, isPulsing: true)
                } else if count > 0 {
                    Text(formatBadgeCount(count))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
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
                            .fill(Color.white.opacity(0.105))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
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
        }
    }
}
