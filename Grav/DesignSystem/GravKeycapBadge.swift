import SwiftUI

/// Minimal monochrome keyboard shortcut cap (e.g. `ESC`, `↩`, `1`, `2`, `3`, `⌘C`)
/// rendered with continuous `controlXS` geometry and a `0.5pt` top-lit specular hairline.
public struct GravKeycapBadge: View {
    public enum Size: Sendable, Equatable {
        case compact
        case regular

        var font: Font {
            switch self {
            case .compact: return GravTypography.monoMicro
            case .regular: return GravTypography.monoCaption
            }
        }

        var minWidth: CGFloat {
            switch self {
            case .compact: return 18
            case .regular: return 22
            }
        }

        var height: CGFloat {
            switch self {
            case .compact: return 18
            case .regular: return 20
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .compact: return 5
            case .regular: return 6
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    public var key: String
    public var size: Size
    public var adaptive: Bool

    public init(
        _ key: String,
        size: Size = .regular,
        adaptive: Bool = true
    ) {
        self.key = key
        self.size = size
        self.adaptive = adaptive
    }

    public var body: some View {
        let palette = GravAdaptivePalette(colorScheme: adaptive ? colorScheme : .dark)
        let shape = RoundedRectangle.grav(GravRadius.controlXS)

        Text(key)
            .font(size.font)
            .monospacedDigit()
            .foregroundStyle(palette.inkSecondary)
            .lineLimit(1)
            .padding(.horizontal, size.horizontalPadding)
            .frame(minWidth: size.minWidth, minHeight: size.height, maxHeight: size.height)
            .background {
                shape.fill(palette.isDark ? GravPalette.cardFillBase : Color.white.opacity(0.92))
            }
            .overlay {
                shape.strokeBorder(palette.specularStroke, lineWidth: 0.5)
            }
            .shadow(
                color: palette.isDark ? Color.black.opacity(0.35) : Color.black.opacity(0.08),
                radius: 0.5,
                x: 0,
                y: 1
            )
            .accessibilityLabel("Key \(key)")
    }
}

/// Horizontal monochrome shortcut legend pairing one or more keycaps with a concise label.
public struct GravKeycapHint: View {
    @Environment(\.colorScheme) private var colorScheme

    public var keys: [String]
    public var label: String
    public var size: GravKeycapBadge.Size
    public var adaptive: Bool

    public init(
        keys: [String],
        label: String,
        size: GravKeycapBadge.Size = .compact,
        adaptive: Bool = true
    ) {
        self.keys = keys
        self.label = label
        self.size = size
        self.adaptive = adaptive
    }

    public init(
        key: String,
        label: String,
        size: GravKeycapBadge.Size = .compact,
        adaptive: Bool = true
    ) {
        self.keys = [key]
        self.label = label
        self.size = size
        self.adaptive = adaptive
    }

    public var body: some View {
        let palette = GravAdaptivePalette(colorScheme: adaptive ? colorScheme : .dark)

        HStack(spacing: GravSpacing.xs) {
            HStack(spacing: 3) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    GravKeycapBadge(key, size: size, adaptive: adaptive)
                }
            }

            Text(label)
                .font(GravTypography.caption)
                .foregroundStyle(palette.inkTertiary)
        }
    }
}
