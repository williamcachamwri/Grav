import SwiftUI

public enum LiquidGlassChromeEmphasis: Sendable, Equatable {
    case standard
    case overlay

    public var restingSubstrate: CGFloat {
        switch self {
        case .standard: 0.14
        case .overlay: 0.34
        }
    }

    public var activeSubstrate: CGFloat {
        switch self {
        case .standard: 0.24
        case .overlay: 0.44
        }
    }

    public var restingTint: CGFloat {
        switch self {
        case .standard: 0.05
        case .overlay: 0.08
        }
    }

    public var activeTint: CGFloat {
        switch self {
        case .standard: 0.10
        case .overlay: 0.14
        }
    }

    public func glassTint(isActive: Bool) -> Color? {
        switch self {
        case .standard:
            nil
        case .overlay:
            .black.opacity(isActive ? Self.overlayTintActive : Self.overlayTintResting)
        }
    }

    public static let overlayTintResting: Double = 0.38
    public static let overlayTintActive: Double = 0.52
}

public extension View {
    func liquidGlassControl(
        isActive: Bool,
        cornerRadius: CGFloat = Radius.control(forHeight: ControlMetrics.propertyChip),
        activeGlassTint: Color? = .accentColor
    ) -> some View {
        liquidGlassControl(
            isActive: isActive,
            in: Radius.rect(cornerRadius),
            activeGlassTint: activeGlassTint
        )
    }

    func liquidGlassControl<S: InsettableShape>(
        isActive: Bool,
        in shape: S,
        emphasis: LiquidGlassChromeEmphasis = .standard,
        showsRestingSurface: Bool = false,
        activeGlassTint: Color? = .accentColor
    ) -> some View {
        modifier(LiquidGlassControlChrome(
            isActive: isActive,
            shape: shape,
            emphasis: emphasis,
            showsRestingSurface: showsRestingSurface,
            activeGlassTint: activeGlassTint
        ))
    }

    func liquidGlassChrome<S: InsettableShape>(
        shape: S,
        isVisible: Bool,
        isActive: Bool = false,
        emphasis: LiquidGlassChromeEmphasis = .standard,
        glassTint: Color? = nil
    ) -> some View {
        liquidGlassSurface(
            shape: shape,
            isVisible: isVisible,
            substrate: isActive ? emphasis.activeSubstrate : emphasis.restingSubstrate,
            tint: isActive ? emphasis.activeTint : emphasis.restingTint,
            highlight: .none,
            withRimLighting: isVisible,
            isInteractive: true,
            glassTint: glassTint ?? emphasis.glassTint(isActive: isActive)
        )
        .contentShape(shape)
    }
}

private struct LiquidGlassControlChrome<S: InsettableShape>: ViewModifier {
    let isActive: Bool
    let shape: S
    let emphasis: LiquidGlassChromeEmphasis
    let showsRestingSurface: Bool
    let activeGlassTint: Color?

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .liquidGlassChrome(
                shape: shape,
                isVisible: showsGlass,
                isActive: isLit,
                emphasis: emphasis,
                glassTint: isActive ? activeGlassTint : nil
            )
            .onHover { hovering in
                withAnimation(LiquidGlassTokens.hoverSpring) {
                    isHovering = isEnabled && hovering
                }
            }
            .animation(LiquidGlassTokens.hoverSpring, value: isActive)
    }

    private var showsGlass: Bool {
        isEnabled && (showsRestingSurface || isActive || isHovering)
    }

    private var isLit: Bool {
        isActive || (showsRestingSurface && isHovering)
    }
}
