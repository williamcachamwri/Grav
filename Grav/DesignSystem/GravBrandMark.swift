import AppKit
import SwiftUI

/// Crisp monochrome geometric orbital brand mark for Grav (and fallback when Antigravity is not installed).
/// Strict industrial geometry — zero sparkles, stars, or neon glows.
public struct GravOrbitalMark: View {
    public var size: CGFloat
    public var tint: Color

    public init(size: CGFloat = 24, tint: Color = GravPalette.titaniumWhite) {
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let unit = min(rect.width, rect.height)
            let strokeWidth = max(1.1, unit * 0.082)

            // Outer precision telemetry ring (broken arc at 270 deg sweep)
            var outerArc = Path()
            outerArc.addArc(
                center: center,
                radius: unit * 0.41,
                startAngle: .degrees(-135),
                endAngle: .degrees(165),
                clockwise: false
            )
            context.stroke(
                outerArc,
                with: .color(tint),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
            )

            // Inner tilted orbital ellipse
            let ellipseRect = CGRect(
                x: center.x - unit * 0.28,
                y: center.y - unit * 0.14,
                width: unit * 0.56,
                height: unit * 0.28
            )
            var orbit = Path(ellipseIn: ellipseRect)
            let rotation = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: -.pi / 5.5)
                .translatedBy(x: -center.x, y: -center.y)
            orbit = orbit.applying(rotation)
            context.stroke(
                orbit,
                with: .color(tint.opacity(0.86)),
                style: StrokeStyle(lineWidth: strokeWidth * 0.85, lineCap: .round)
            )

            // Core gravity singularity dot
            let coreRadius = unit * 0.11
            let coreRect = CGRect(
                x: center.x - coreRadius,
                y: center.y - coreRadius,
                width: coreRadius * 2,
                height: coreRadius * 2
            )
            context.fill(Path(ellipseIn: coreRect), with: .color(tint))

            // Orbital telemetry satellite node at arc terminus
            let satAngle = CGFloat(-135.0 * .pi / 180.0)
            let satCenter = CGPoint(
                x: center.x + cos(satAngle) * unit * 0.41,
                y: center.y + sin(satAngle) * unit * 0.41
            )
            let satRadius = max(1.2, unit * 0.068)
            let satRect = CGRect(
                x: satCenter.x - satRadius,
                y: satCenter.y - satRadius,
                width: satRadius * 2,
                height: satRadius * 2
            )
            context.fill(Path(ellipseIn: satRect), with: .color(GravPalette.glacialTeal))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Grav app icon squircle tile (obsidian substrate + subtle glacial teal rim + geometric orbital mark).
public struct GravAppIconTile: View {
    public var size: CGFloat

    public init(size: CGFloat = 26) {
        self.size = size
    }

    public var body: some View {
        let cornerRadius = size * 0.25
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0x0B / 255.0, green: 0x16 / 255.0, blue: 0x1E / 255.0),
                            GravPalette.obsidianVoid,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            GravPalette.glacialTeal.opacity(0.24),
                            Color.clear,
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: size * 0.9
                    )
                )

            GravOrbitalMark(size: size * 0.64, tint: GravPalette.titaniumWhite)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(GravPalette.specularStroke, lineWidth: max(0.5, size * 0.02))
        }
        .frame(width: size, height: size)
    }
}

/// Renders the real macOS Antigravity app icon when available, falling back cleanly
/// to the monochrome geometric orbital mark if Antigravity is not installed.
public struct AntigravityLogoView: View {
    public var icon: NSImage?
    public var size: CGFloat

    public init(icon: NSImage?, size: CGFloat = 16) {
        self.icon = icon
        self.size = size
    }

    public var body: some View {
        let cornerRadius = size * 0.24
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                GravAppIconTile(size: size)
            }
        }
        .frame(width: size, height: size)
    }
}
