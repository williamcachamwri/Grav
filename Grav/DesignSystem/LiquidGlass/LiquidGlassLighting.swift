import SwiftUI

/// Renders a crisp 0.5pt top-lit specular perimeter hairline for macOS Liquid Glass controls.
public struct LiquidGlassRimBorder<S: InsettableShape>: View {
    public var shape: S
    public var isHovered: Bool
    public var isEnabled: Bool = true
    public var emphasis: LiquidGlassActionEmphasis = .secondary

    public init(
        shape: S,
        isHovered: Bool,
        isEnabled: Bool = true,
        emphasis: LiquidGlassActionEmphasis = .secondary
    ) {
        self.shape = shape
        self.isHovered = isHovered
        self.isEnabled = isEnabled
        self.emphasis = emphasis
    }

    public var body: some View {
        shape.strokeBorder(specularGradient, lineWidth: LiquidGlassTokens.specularLineWidth)
    }

    private var specularGradient: LinearGradient {
        guard isEnabled else {
            return LinearGradient(colors: [.white.opacity(0.04)], startPoint: .top, endPoint: .bottom)
        }
        let (top, bottom): (Double, Double) = switch emphasis {
        case .primary: isHovered ? (0.32, 0.12) : (0.22, 0.06)
        case .secondary: isHovered ? (0.24, 0.06) : (0.12, 0.03)
        case .destructive: isHovered ? (0.34, 0.12) : (0.18, 0.04)
        case .contextPill: isHovered ? (0.24, 0.08) : (0.12, 0.03)
        }
        return LinearGradient(
            colors: [.white.opacity(top), .white.opacity(bottom)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
