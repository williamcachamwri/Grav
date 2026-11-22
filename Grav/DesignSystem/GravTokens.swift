import SwiftUI

/// Strict continuous corner geometry tokens.
public enum GravRadius {
    public static let controlXS: CGFloat = 6
    public static let controlS: CGFloat = 8
    public static let controlM: CGFloat = 10
    public static let card: CGFloat = 14
    public static let panel: CGFloat = 20
    public static let window: CGFloat = 26
}

/// Precision spacing and layout metrics.
public enum GravSpacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 6
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let onboardingGutter: CGFloat = 36
    public static let onboardingGap: CGFloat = 32
    public static let onboardingLeftRailWidth: CGFloat = 420
}

/// Typography tokens pairing SF Pro / SF Rounded headings with tabular SF Mono telemetry data.
public enum GravTypography {
    public static let heroTitle = Font.system(size: 46, weight: .semibold, design: .rounded)
    public static let onboardingTitle = Font.system(size: 28, weight: .semibold, design: .rounded)
    public static let onboardingSubtitle = Font.system(size: 14, weight: .regular, design: .default)
    public static let sectionHeader = Font.system(size: 13, weight: .semibold, design: .default)
    public static let body = Font.system(size: 12.5, weight: .regular, design: .default)
    public static let bodyMedium = Font.system(size: 12.5, weight: .medium, design: .default)
    public static let caption = Font.system(size: 11, weight: .medium, design: .default)
    public static let micro = Font.system(size: 10, weight: .medium, design: .default)

    public static let monoTitle = Font.system(size: 12, weight: .semibold, design: .monospaced)
    public static let monoBody = Font.system(size: 11.5, weight: .regular, design: .monospaced)
    public static let monoCaption = Font.system(size: 10.5, weight: .medium, design: .monospaced)
    public static let monoMicro = Font.system(size: 9.5, weight: .medium, design: .monospaced)
}

/// Shared 120Hz motion vocabulary calibrated for flight-deck precision.
public enum GravMotion {
    public static let railSpring = Animation.spring(response: 0.28, dampingFraction: 0.82)
    public static let rowHover = Animation.spring(response: 0.22, dampingFraction: 0.86)
    public static let contentSlide = Animation.spring(response: 0.30, dampingFraction: 0.86)
    public static let subtleFade = Animation.easeOut(duration: 0.16)
    public static let numericTick = Animation.snappy(duration: 0.22)
}

/// Convenience helper for continuous rounded rectangles.
public extension RoundedRectangle {
    static func grav(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}
