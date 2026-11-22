import SwiftUI

public enum LiquidGlassActionEmphasis: Equatable, Sendable {
    case primary
    case secondary
    case destructive
    case contextPill
}

public struct LiquidGlassButtonStyle: ButtonStyle {
    public var emphasis: LiquidGlassActionEmphasis = .secondary
    public var capsule: Bool = false
    public var isActive: Bool = false

    public init(
        emphasis: LiquidGlassActionEmphasis = .secondary,
        capsule: Bool = false,
        isActive: Bool = false
    ) {
        self.emphasis = emphasis
        self.capsule = capsule
        self.isActive = isActive
    }

    public func makeBody(configuration: Configuration) -> some View {
        LiquidGlassButtonSurface(
            configuration: configuration,
            emphasis: emphasis,
            capsule: capsule,
            isActive: isActive
        )
    }
}

public struct LiquidGlassActionButton: View {
    public var title: String
    public var icon: String? = nil
    public var trailingKey: String? = nil
    public var emphasis: LiquidGlassActionEmphasis = .secondary
    public var capsule: Bool = true
    public var action: () -> Void

    public init(
        title: String,
        icon: String? = nil,
        trailingKey: String? = nil,
        emphasis: LiquidGlassActionEmphasis = .secondary,
        capsule: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.trailingKey = trailingKey
        self.emphasis = emphasis
        self.capsule = capsule
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if let trailingKey {
                    Text(trailingKey)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(LiquidGlassTokens.veilFill.opacity(0.12))
                        .clipShape(Radius.rect(Radius.ornament))
                }
            }
        }
        .buttonStyle(LiquidGlassButtonStyle(emphasis: emphasis, capsule: capsule))
    }
}

public extension ButtonStyle where Self == LiquidGlassButtonStyle {
    static func liquidGlass(
        emphasis: LiquidGlassActionEmphasis = .secondary,
        capsule: Bool = false,
        isActive: Bool = false
    ) -> LiquidGlassButtonStyle {
        LiquidGlassButtonStyle(emphasis: emphasis, capsule: capsule, isActive: isActive)
    }
}
