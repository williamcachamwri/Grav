import SwiftUI

public struct LiquidGlassButtonSurface: View {
    let configuration: ButtonStyleConfiguration
    let emphasis: LiquidGlassActionEmphasis
    let capsule: Bool
    let isActive: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.liquidGlassRenderMode) private var renderMode
    @AppStorage(GravPreferenceKeys.useLiquidGlass) private var isLiquidGlassEnabled = true
    @State private var isHovered = false

    private var usesNativeGlass: Bool {
        LiquidGlassCapabilities.usesNativeGlass(for: renderMode, userEnabled: isLiquidGlassEnabled)
    }

    private var isVisuallyActive: Bool { (isHovered && isEnabled) || isActive }
    private var isPressed: Bool { configuration.isPressed && isEnabled }

    public var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, capsule ? 14 : 12)
            .padding(.vertical, capsule ? 7 : 6)
            .modifier(
                LiquidGlassButtonBackground(
                    capsule: capsule,
                    substrate: currentSubstrate,
                    tint: currentTint,
                    glassTint: currentGlassTint,
                    isEnabled: isEnabled,
                    isActive: isVisuallyActive
                )
            )
            .overlay { borderLayer }
            .contentShape(hitShape)
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .onHover { hovering in
                guard isEnabled else {
                    isHovered = false
                    return
                }
                withAnimation(LiquidGlassTokens.hoverSpring) {
                    isHovered = hovering
                }
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled { isHovered = false }
            }
            .animation(LiquidGlassTokens.hoverSpring, value: isHovered)
            .animation(LiquidGlassTokens.hoverSpring, value: isActive)
            .animation(LiquidGlassTokens.pressSpring, value: configuration.isPressed)
    }

    @ViewBuilder
    private var borderLayer: some View {
        if !usesNativeGlass {
            if capsule {
                LiquidGlassRimBorder(
                    shape: Capsule(style: .continuous),
                    isHovered: isVisuallyActive,
                    isEnabled: isEnabled,
                    emphasis: emphasis
                )
            } else {
                LiquidGlassRimBorder(
                    shape: RoundedRectangle(cornerRadius: LiquidGlassTokens.controlRadius, style: .continuous),
                    isHovered: isVisuallyActive,
                    isEnabled: isEnabled,
                    emphasis: emphasis
                )
            }
        }
    }

    private var hitShape: AnyShape {
        capsule
            ? AnyShape(Capsule(style: .continuous))
            : AnyShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.controlRadius, style: .continuous))
    }

    private var currentSubstrate: CGFloat {
        guard isEnabled else { return 0 }
        switch emphasis {
        case .primary: return isPressed ? 0.72 : (isVisuallyActive ? 0.60 : 0.50)
        case .secondary: return isPressed ? 0.72 : (isVisuallyActive ? 0.60 : 0.45)
        case .destructive: return isPressed ? 0.72 : (isVisuallyActive ? 0.60 : 0.50)
        case .contextPill:
            return isPressed
                ? LiquidGlassTokens.controlSubstratePressed
                : (isVisuallyActive
                    ? LiquidGlassTokens.controlSubstrateHover
                    : LiquidGlassTokens.controlSubstrateResting)
        }
    }

    private var currentTint: CGFloat {
        guard isEnabled else { return 0.04 }
        switch emphasis {
        case .primary: return isPressed ? 0.22 : (isVisuallyActive ? 0.16 : 0.12)
        case .secondary: return isPressed ? 0.12 : (isVisuallyActive ? 0.08 : 0.03)
        case .destructive: return isPressed ? 0.28 : (isVisuallyActive ? 0.18 : 0.08)
        case .contextPill: return isPressed ? 0.12 : (isVisuallyActive ? 0.08 : 0.04)
        }
    }

    private var currentGlassTint: Color? {
        guard isEnabled else { return nil }
        switch emphasis {
        case .primary: return .accentColor
        case .destructive: return .red
        case .secondary, .contextPill: return isActive ? .accentColor : nil
        }
    }

    private var foreground: Color {
        guard isEnabled else { return LiquidGlassTokens.inkFaint }
        switch emphasis {
        case .primary, .destructive:
            return LiquidGlassTokens.ink(onTint: currentGlassTint, renderMode: renderMode)
        case .secondary:
            return LiquidGlassTokens.ink(
                onTint: currentGlassTint,
                renderMode: renderMode,
                otherwise: isVisuallyActive ? LiquidGlassTokens.inkPrimary : LiquidGlassTokens.inkBody
            )
        case .contextPill:
            return LiquidGlassTokens.ink(
                onTint: currentGlassTint,
                renderMode: renderMode,
                otherwise: isVisuallyActive ? LiquidGlassTokens.inkPrimary : LiquidGlassTokens.inkMuted
            )
        }
    }
}

private struct LiquidGlassButtonBackground: ViewModifier {
    let capsule: Bool
    let substrate: CGFloat
    let tint: CGFloat
    let glassTint: Color?
    let isEnabled: Bool
    let isActive: Bool

    @Environment(\.liquidGlassRenderMode) private var renderMode
    @AppStorage(GravPreferenceKeys.useLiquidGlass) private var isLiquidGlassEnabled = true

    private var usesNativeGlass: Bool {
        LiquidGlassCapabilities.usesNativeGlass(for: renderMode, userEnabled: isLiquidGlassEnabled)
    }

    func body(content: Content) -> some View {
        if capsule {
            apply(content, shape: Capsule(style: .continuous))
        } else {
            apply(
                content,
                shape: RoundedRectangle(cornerRadius: LiquidGlassTokens.controlRadius, style: .continuous)
            )
        }
    }

    private func apply<S: InsettableShape>(_ content: Content, shape: S) -> some View {
        content
            .liquidGlassSurface(
                shape: shape,
                substrate: substrate,
                tint: tint,
                highlight: .none,
                withRimLighting: false,
                isInteractive: isEnabled,
                glassTint: glassTint
            )
            .shadow(color: shadowColor, radius: isActive ? 4 : 2, x: 0, y: isActive ? 2 : 1)
    }

    private var shadowColor: Color {
        guard isEnabled, !usesNativeGlass else { return .clear }
        return Color.black.opacity(isActive ? 0.24 : 0.12)
    }
}
