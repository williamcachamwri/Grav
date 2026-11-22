import AppKit
import SwiftUI

/// Onboarding spacing ramp ported 1:1 from Snapzy's `SnapzySpace`.
public enum GravSpace {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 6
    public static let md: CGFloat = 8
    public static let lg: CGFloat = 10
    public static let xl: CGFloat = 12
    public static let xxl: CGFloat = 16
    public static let xxxl: CGFloat = 20
    public static let huge: CGFloat = 24
    public static let giant: CGFloat = 32
    public static let hero: CGFloat = 44
}

/// Dark-locked onboarding ink and card fill ramp ported 1:1 from Snapzy's `SnapzyGlassInk`.
public enum GravGlassInk {
    public static let primary = Color.white
    public static let body = Color.white.opacity(0.80)
    public static let muted = Color.white.opacity(0.58)
    public static let faint = Color.white.opacity(0.36)

    public static let hairline = Color.white.opacity(0.10)
    public static let hairlineStrong = Color.white.opacity(0.18)

    public static let fillQuiet = Color.white.opacity(0.045)
    public static let fillRaised = Color.white.opacity(0.075)
    public static let fillHover = Color.white.opacity(0.105)
}

/// Surface glass constants ported 1:1 from Snapzy's `SnapzySurfaceGlass`.
public enum GravSurfaceGlass {
    public static let baseDarkness: CGFloat = 0.28
    public static let specularLineWidth: CGFloat = 0.5
    public static let specularTopColor: Color = .white.opacity(0.16)
    public static let specularBottomColor: Color = .white.opacity(0.04)

    public static let stageEdgeColors: [Color] = [
        .white.opacity(0.24),
        .white.opacity(0.09),
        .white.opacity(0.02),
    ]
    public static let stageEdgeWidth: CGFloat = 0.75

    public static let controlSubstrateResting: CGFloat = 0.20
    public static let controlSubstrateHover: CGFloat = 0.28
    public static let controlSubstratePressed: CGFloat = 0.36

    public static let controlStrokeResting: CGFloat = 0.08
    public static let controlStrokeHover: CGFloat = 0.22

    public static let fallbackSubstrateScale: CGFloat = 0.4
    public static let fallbackControlSheenTop: Double = 0.10
    public static let fallbackControlSheenBottom: Double = 0.02
}

/// Shadow stacks ported 1:1 from Snapzy's `SnapzyGlassShadow`.
public enum GravGlassShadow {
    public static let stageColor = Color.black.opacity(0.40)
    public static let stageRadius: CGFloat = 34
    public static let stageY: CGFloat = 16
    public static let stageAmbientColor = Color.black.opacity(0.18)
    public static let stageAmbientRadius: CGFloat = 7

    public static let controlColor = Color.black.opacity(0.22)
    public static let controlRadius: CGFloat = 14
    public static let controlY: CGFloat = 6
}

/// Exact onboarding window & column metrics ported 1:1 from Snapzy's `SnapzyOnboardingMetrics`.
public enum GravOnboardingMetrics {
    public static let windowRadius = Radius.window
    public static let screenFill: CGFloat = 0.92
    public static let screenMargin: CGFloat = 16
    public static let minSize = CGSize(width: 1060, height: 720)
    public static let maxSize = CGSize(width: 1280, height: 826)
    public static let gutter: CGFloat = 36
    public static let railWidth: CGFloat = 420
    public static let columnGap: CGFloat = 32
    public static let headerHeight: CGFloat = 44
    public static let footerHeight: CGFloat = 44
    public static let stageRadius = Radius.panel
}

/// Type ramp ported 1:1 from Snapzy's `SnapzyOnboardingType`.
public enum GravOnboardingType {
    public static let display: CGFloat = 31
    public static let displayTracking: CGFloat = -0.7
    public static let title: CGFloat = 26
    public static let lede: CGFloat = 14.5
    public static let sectionLabel: CGFloat = 10.5
    public static let sectionTracking: CGFloat = 0.7
    public static let challenge: CGFloat = 13.5
    public static let body: CGFloat = 13
    public static let caption: CGFloat = 12
    public static let keycap: CGFloat = 10
}

/// Caches `NSApp.applicationIconImage` once on `@MainActor` for 120Hz `Animatable` flights.
@MainActor
public enum GravOnboardingIconCache {
    public static let appIcon: NSImage = NSApp.applicationIconImage
}
