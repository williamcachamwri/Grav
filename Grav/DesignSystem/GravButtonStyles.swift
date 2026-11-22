import SwiftUI

/// Precision monochrome glass button style with subtle magnetic hover response
/// and `0.5pt` top-lit specular hairline border.
public struct GravGlassButtonStyle: ButtonStyle {
    public var radius: CGFloat
    public var horizontalPadding: CGFloat
    public var verticalPadding: CGFloat
    public var adaptive: Bool

    public init(
        radius: CGFloat = GravRadius.controlS,
        horizontalPadding: CGFloat = 12,
        verticalPadding: CGFloat = 6,
        adaptive: Bool = true
    ) {
        self.radius = radius
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.adaptive = adaptive
    }

    public func makeBody(configuration: Configuration) -> some View {
        GravGlassButtonBody(
            configuration: configuration,
            radius: radius,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            adaptive: adaptive
        )
    }
}

private struct GravGlassButtonBody: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    let configuration: ButtonStyle.Configuration
    let radius: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let adaptive: Bool

    @State private var isHovered = false

    var body: some View {
        let palette = GravAdaptivePalette(colorScheme: adaptive ? colorScheme : .dark)
        let shape = RoundedRectangle.grav(radius)

        let fillColor: Color = {
            if !isEnabled {
                return palette.fillSubtle
            }
            if configuration.isPressed {
                return palette.pressedFill
            }
            if isHovered {
                return palette.fillElevated
            }
            return palette.fillBase
        }()

        let scale: CGFloat = {
            guard !reduceMotion, isEnabled else { return 1.0 }
            if configuration.isPressed { return 0.975 }
            if isHovered { return 1.012 }
            return 1.0
        }()

        configuration.label
            .font(GravTypography.bodyMedium)
            .foregroundStyle(isEnabled ? palette.inkPrimary : palette.inkTertiary)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(shape.fill(fillColor))
            .overlay {
                shape.strokeBorder(
                    palette.specularStroke,
                    lineWidth: isHovered && isEnabled ? 0.75 : 0.5
                )
            }
            .shadow(
                color: adaptive && !palette.isDark && isEnabled
                    ? Color.black.opacity(isHovered ? 0.07 : 0.04)
                    : .clear,
                radius: isHovered ? 3 : 1.5,
                x: 0,
                y: 1
            )
            .scaleEffect(scale)
            .opacity(isEnabled ? 1.0 : 0.6)
            .contentShape(shape)
            .onHover { hovering in
                isHovered = hovering
            }
            .animation(reduceMotion ? nil : GravMotion.rowHover, value: isHovered)
            .animation(reduceMotion ? nil : GravMotion.rowHover, value: configuration.isPressed)
    }
}

/// Primary action button rendered in Grav's Glacial Teal-Cyan brand gradient
/// with calibrated contrast for both Dark Liquid Glass and Light Mode surfaces.
public struct GravPrimaryActionButtonStyle: ButtonStyle {
    public var radius: CGFloat
    public var horizontalPadding: CGFloat
    public var verticalPadding: CGFloat
    public var adaptive: Bool

    public init(
        radius: CGFloat = GravRadius.controlM,
        horizontalPadding: CGFloat = 14,
        verticalPadding: CGFloat = 7,
        adaptive: Bool = true
    ) {
        self.radius = radius
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.adaptive = adaptive
    }

    public func makeBody(configuration: Configuration) -> some View {
        GravPrimaryActionButtonBody(
            configuration: configuration,
            radius: radius,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            adaptive: adaptive
        )
    }
}

private struct GravPrimaryActionButtonBody: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    let configuration: ButtonStyle.Configuration
    let radius: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let adaptive: Bool

    @State private var isHovered = false

    var body: some View {
        let isDark = !adaptive || colorScheme == .dark
        let shape = RoundedRectangle.grav(radius)

        let gradient = isDark
            ? LinearGradient(
                colors: [GravPalette.glacialTeal, GravPalette.glacialCyan],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            : LinearGradient(
                colors: [
                    Color(red: 0x0E / 255.0, green: 0x8F / 255.0, blue: 0x83 / 255.0),
                    Color(red: 0x08 / 255.0, green: 0x8A / 255.0, blue: 0xBD / 255.0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

        let foregroundColor = isDark ? GravPalette.obsidianVoid : GravPalette.titaniumWhite

        let scale: CGFloat = {
            guard !reduceMotion, isEnabled else { return 1.0 }
            if configuration.isPressed { return 0.975 }
            if isHovered { return 1.015 }
            return 1.0
        }()

        configuration.label
            .font(GravTypography.bodyMedium)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background {
                ZStack {
                    shape.fill(gradient)
                    if isHovered && isEnabled {
                        shape.fill(Color.white.opacity(configuration.isPressed ? 0.0 : 0.10))
                    }
                    if configuration.isPressed {
                        shape.fill(Color.black.opacity(0.12))
                    }
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.36), Color.white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
            }
            .scaleEffect(scale)
            .opacity(isEnabled ? 1.0 : 0.45)
            .contentShape(shape)
            .onHover { hovering in
                isHovered = hovering
            }
            .animation(reduceMotion ? nil : GravMotion.rowHover, value: isHovered)
            .animation(reduceMotion ? nil : GravMotion.rowHover, value: configuration.isPressed)
    }
}

/// Minimal monochrome ghost icon button with calm hover fill and magnetic tactile response.
public struct GravGhostIconButtonStyle: ButtonStyle {
    public var size: CGFloat
    public var radius: CGFloat
    public var isActive: Bool
    public var adaptive: Bool

    public init(
        size: CGFloat = 26,
        radius: CGFloat = GravRadius.controlS,
        isActive: Bool = false,
        adaptive: Bool = true
    ) {
        self.size = size
        self.radius = radius
        self.isActive = isActive
        self.adaptive = adaptive
    }

    public func makeBody(configuration: Configuration) -> some View {
        GravGhostIconButtonBody(
            configuration: configuration,
            size: size,
            radius: radius,
            isActive: isActive,
            adaptive: adaptive
        )
    }
}

private struct GravGhostIconButtonBody: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    let configuration: ButtonStyle.Configuration
    let size: CGFloat
    let radius: CGFloat
    let isActive: Bool
    let adaptive: Bool

    @State private var isHovered = false

    var body: some View {
        let palette = GravAdaptivePalette(colorScheme: adaptive ? colorScheme : .dark)
        let shape = RoundedRectangle.grav(radius)

        let fillColor: Color = {
            guard isEnabled else { return .clear }
            if configuration.isPressed { return palette.pressedFill }
            if isHovered { return palette.hoverFill }
            if isActive { return palette.fillBase }
            return .clear
        }()

        let foregroundColor: Color = {
            if !isEnabled { return palette.inkQuaternary }
            if isActive { return palette.accentTeal }
            if isHovered { return palette.inkPrimary }
            return palette.inkSecondary
        }()

        let scale: CGFloat = {
            guard !reduceMotion, isEnabled else { return 1.0 }
            if configuration.isPressed { return 0.93 }
            if isHovered { return 1.03 }
            return 1.0
        }()

        configuration.label
            .foregroundStyle(foregroundColor)
            .frame(width: size, height: size)
            .background(shape.fill(fillColor))
            .overlay {
                if (isHovered || isActive) && isEnabled {
                    shape.strokeBorder(palette.specularStroke, lineWidth: 0.5)
                }
            }
            .scaleEffect(scale)
            .contentShape(shape)
            .onHover { hovering in
                isHovered = hovering
            }
            .animation(reduceMotion ? nil : GravMotion.rowHover, value: isHovered)
            .animation(reduceMotion ? nil : GravMotion.rowHover, value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == GravGlassButtonStyle {
    static var gravGlass: GravGlassButtonStyle { GravGlassButtonStyle() }

    static func gravGlass(
        radius: CGFloat = GravRadius.controlS,
        horizontalPadding: CGFloat = 12,
        verticalPadding: CGFloat = 6,
        adaptive: Bool = true
    ) -> GravGlassButtonStyle {
        GravGlassButtonStyle(
            radius: radius,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            adaptive: adaptive
        )
    }
}

public extension ButtonStyle where Self == GravPrimaryActionButtonStyle {
    static var gravPrimaryAction: GravPrimaryActionButtonStyle { GravPrimaryActionButtonStyle() }

    static func gravPrimaryAction(
        radius: CGFloat = GravRadius.controlM,
        horizontalPadding: CGFloat = 14,
        verticalPadding: CGFloat = 7,
        adaptive: Bool = true
    ) -> GravPrimaryActionButtonStyle {
        GravPrimaryActionButtonStyle(
            radius: radius,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            adaptive: adaptive
        )
    }
}

public extension ButtonStyle where Self == GravGhostIconButtonStyle {
    static var gravGhostIcon: GravGhostIconButtonStyle { GravGhostIconButtonStyle() }

    static func gravGhostIcon(
        size: CGFloat = 26,
        radius: CGFloat = GravRadius.controlS,
        isActive: Bool = false,
        adaptive: Bool = true
    ) -> GravGhostIconButtonStyle {
        GravGhostIconButtonStyle(
            size: size,
            radius: radius,
            isActive: isActive,
            adaptive: adaptive
        )
    }
}
