import SwiftUI

public extension View {
    /// Groups sibling Liquid Glass surfaces into a single `GlassEffectContainer` on macOS 26+.
    func liquidGlassGroup(spacing: CGFloat? = nil) -> some View {
        modifier(LiquidGlassGroupModifier(spacing: spacing))
    }

    /// Assigns a morphing glass identity so sibling controls smoothly morph on macOS 26+.
    func liquidGlassID(_ id: some Hashable & Sendable, in namespace: Namespace.ID) -> some View {
        modifier(LiquidGlassIDModifier(id: id, namespace: namespace))
    }
}

private struct LiquidGlassGroupModifier: ViewModifier {
    let spacing: CGFloat?
    @Environment(\.liquidGlassRenderMode) private var renderMode
    @AppStorage(GravPreferenceKeys.useLiquidGlass) private var isLiquidGlassEnabled = true

    private var usesNativeGlass: Bool {
        LiquidGlassCapabilities.usesNativeGlass(for: renderMode, userEnabled: isLiquidGlassEnabled)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), usesNativeGlass {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

private struct LiquidGlassIDModifier<ID: Hashable & Sendable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID
    @Environment(\.liquidGlassRenderMode) private var renderMode
    @AppStorage(GravPreferenceKeys.useLiquidGlass) private var isLiquidGlassEnabled = true

    private var usesNativeGlass: Bool {
        LiquidGlassCapabilities.usesNativeGlass(for: renderMode, userEnabled: isLiquidGlassEnabled)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), usesNativeGlass {
            content.glassEffectID(id, in: namespace)
        } else {
            content
        }
    }
}
