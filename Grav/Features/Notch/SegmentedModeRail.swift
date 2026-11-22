import SwiftUI

/// Precision 3-tab segmented rail (`Live | Files | Terminal`) with a spring-gliding
/// Dark Liquid Glass selection capsule (`matchedGeometryEffect`, `GravMotionSpec.settle.animation`).
public struct SegmentedModeRail: View {
    @Binding public var selection: NotchTab
    public var liveCount: Int
    public var filesCount: Int
    public var terminalCount: Int
    public var hasRunningCommand: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var railNamespace
    @State private var hoveredTab: NotchTab?

    public init(
        selection: Binding<NotchTab>,
        liveCount: Int = 0,
        filesCount: Int = 0,
        terminalCount: Int = 0,
        hasRunningCommand: Bool = false
    ) {
        self._selection = selection
        self.liveCount = liveCount
        self.filesCount = filesCount
        self.terminalCount = terminalCount
        self.hasRunningCommand = hasRunningCommand
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(NotchTab.allCases) { tab in
                tabButton(for: tab)
            }
        }
        .padding(2.5)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.038))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    private func tabButton(for tab: NotchTab) -> some View {
        let isSelected = selection == tab
        let isHovered = hoveredTab == tab
        let count = itemCount(for: tab)

        return Button {
            select(tab)
        } label: {
            HStack(spacing: 5.5) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(isHovered ? 0.78 : 0.52))

                Text(tab.title)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                    .tracking(-0.15)
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(isHovered ? 0.85 : 0.62))

                if tab == .terminal && hasRunningCommand {
                    NotchSemanticDot(color: GravPalette.glacialCyan, size: 5, isPulsing: true)
                } else if count > 0 {
                    Text(formatBadgeCount(count))
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Color.white.opacity(0.84) : Color.white.opacity(0.38))
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(isSelected ? 0.12 : 0.05))
                        )
                        .contentTransition(reduceMotion ? .identity : .numericText())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .background {
                ZStack {
                    if isHovered && !isSelected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.035))
                    }

                    if isSelected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.13),
                                        Color.white.opacity(0.08),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.24),
                                                Color.white.opacity(0.07),
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 0.5
                                    )
                            )
                            .shadow(color: Color.black.opacity(0.22), radius: 4, y: 1)
                            .matchedGeometryEffect(id: "grav-notch-mode-rail-pill", in: railNamespace)
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
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
        case .files:
            return filesCount
        case .terminal:
            return terminalCount
        }
    }
}
