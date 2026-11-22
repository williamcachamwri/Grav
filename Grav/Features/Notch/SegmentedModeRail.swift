import SwiftUI

/// Precision 3-tab segmented rail (`Live | Files | Terminal`) with a spring-gliding
/// Dark Liquid Glass selection pill (`matchedGeometryEffect`, `GravMotion.railSpring`).
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
        .padding(3)
        .notchGlassSurface(.subtle, cornerRadius: GravRadius.controlM)
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
                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? GravPalette.inkPrimary : GravPalette.inkTertiary)

                Text(tab.title)
                    .font(GravTypography.caption)
                    .foregroundStyle(isSelected ? GravPalette.inkPrimary : GravPalette.inkSecondary.opacity(isHovered ? 0.92 : 0.72))

                if tab == .terminal && hasRunningCommand {
                    NotchSemanticDot(color: GravPalette.commandRunning, size: 5, isPulsing: true)
                } else if count > 0 {
                    Text("\(count)")
                        .font(GravTypography.monoMicro)
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? GravPalette.inkSecondary : GravPalette.inkQuaternary)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background {
                ZStack {
                    if isHovered && !isSelected {
                        RoundedRectangle.grav(GravRadius.controlS)
                            .fill(GravPalette.cardFillSubtle)
                    }

                    if isSelected {
                        RoundedRectangle.grav(GravRadius.controlS)
                            .fill(GravPalette.cardFillElevated)
                            .overlay(
                                RoundedRectangle.grav(GravRadius.controlS)
                                    .strokeBorder(GravPalette.specularStroke, lineWidth: 0.5)
                            )
                            .matchedGeometryEffect(id: "grav-notch-mode-rail-pill", in: railNamespace)
                    }
                }
            }
            .contentShape(RoundedRectangle.grav(GravRadius.controlS))
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
