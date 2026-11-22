import AppKit
import SwiftUI

/// Renders the exact silhouette of Grav's sweeping G/A prism emblem as a razor-sharp tinted template
/// (extracted directly from the Grav app logo artwork, `GravMarkTemplate.imageset`).
/// Used in the Welcome Screen solo reveal, onboarding mock scenes, and monochrome controls.
public struct GravOrbitalMark: View {
    public var size: CGFloat
    public var tint: Color

    public init(size: CGFloat = 24, tint: Color = GravPalette.titaniumWhite) {
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        Group {
            if let nsImage = NSImage(named: "GravMarkTemplate") {
                Image(nsImage: nsImage)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(tint)
            } else {
                // Clean geometric fallback when rendered outside the main asset bundle (e.g. XCTest).
                fallbackGlyph
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var fallbackGlyph: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            let stroke = max(1.6, s * 0.16)
            var arc = Path()
            arc.move(to: CGPoint(x: s * 0.16, y: s * 0.80))
            arc.addQuadCurve(
                to: CGPoint(x: s * 0.78, y: s * 0.36),
                control: CGPoint(x: s * 0.42, y: s * 0.10)
            )
            context.stroke(
                arc,
                with: .color(tint),
                style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)
            )
            var spur = Path()
            spur.move(to: CGPoint(x: s * 0.52, y: s * 0.54))
            spur.addLine(to: CGPoint(x: s * 0.82, y: s * 0.54))
            spur.addQuadCurve(
                to: CGPoint(x: s * 0.68, y: s * 0.80),
                control: CGPoint(x: s * 0.84, y: s * 0.72)
            )
            context.stroke(
                spur,
                with: .color(tint),
                style: StrokeStyle(lineWidth: stroke * 0.92, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

/// Renders the exact Grav app logo (`GravLogo.imageset`) edge-to-edge at Retina fidelity
/// across the Notch HUD, Onboarding, Settings, and About surfaces.
public struct GravAppIconTile: View {
    public var size: CGFloat

    public init(size: CGFloat = 26) {
        self.size = size
    }

    public var body: some View {
        let cornerRadius = size * 0.225
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        Group {
            if let nsImage = Self.cachedLogoImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.18),
                        Color.white.opacity(0.05),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.5
            )
        )
    }

    @MainActor
    private static let cachedLogoImage: NSImage? = NSImage(named: "GravLogo")
}

/// Renders Grav's unified brand icon inside the Notch HUD, headers, and Settings panes.
public struct AntigravityLogoView: View {
    public var icon: NSImage?
    public var size: CGFloat

    public init(icon: NSImage?, size: CGFloat = 16) {
        self.icon = icon
        self.size = size
    }

    private var resolvedIcon: NSImage? {
        let icnsPath = "/Applications/Antigravity.app/Contents/Resources/icon.icns"
        if let icns = NSImage(contentsOfFile: icnsPath) {
            return icns
        }
        if let bundled = NSImage(named: "AntigravityAppIcon") {
            return bundled
        }
        if let icon {
            return icon
        }
        let defaultPath = "/Applications/Antigravity.app"
        if FileManager.default.fileExists(atPath: defaultPath) {
            return NSWorkspace.shared.icon(forFile: defaultPath)
        }
        return nil
    }

    public var body: some View {
        if let nsImage = resolvedIcon {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: size * 0.65, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.60))
                .frame(width: size, height: size)
        }
    }
}
