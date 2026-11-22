import AppKit
import SwiftUI

/// Apple Icon Composer–inspired 3D layered frosted-glass sculptural mark for Grav
/// (modeled after the macOS Sequoia / Tahoe App Store, Podcasts, and Shazam 3D layered icons).
///
/// Features concentric translucent glass depth waves and three interlocking, pill-rounded 3D
/// frosted-white beams forming an ascending Antigravity Delta-Arc with contact shadows and
/// top-lit specular highlights.
public struct GravOrbitalMark: View {
    public var size: CGFloat
    public var tint: Color

    public init(size: CGFloat = 24, tint: Color = GravPalette.titaniumWhite) {
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            let cx = canvasSize.width * 0.5
            let cy = canvasSize.height * 0.5

            // 1. Concentric translucent frosted-glass aura rings (Apple Podcasts-style spatial depth)
            let outerHaloR = s * 0.44
            let midHaloR = s * 0.31
            context.fill(
                Path(ellipseIn: CGRect(x: cx - outerHaloR, y: cy - outerHaloR, width: outerHaloR * 2, height: outerHaloR * 2)),
                with: .color(tint.opacity(0.11))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: cx - midHaloR, y: cy - midHaloR, width: midHaloR * 2, height: midHaloR * 2)),
                with: .color(tint.opacity(0.17))
            )

            let beamThickness = max(1.6, s * 0.145)
            let shadowOffset = max(0.5, s * 0.035)

            // Helper to draw a 3D frosted-white rounded capsule beam between two points with contact shadow
            func drawSculptedBeam(from p1: CGPoint, to p2: CGPoint, alpha: Double = 1.0) {
                var shadowPath = Path()
                shadowPath.move(to: CGPoint(x: p1.x, y: p1.y + shadowOffset))
                shadowPath.addLine(to: CGPoint(x: p2.x, y: p2.y + shadowOffset))
                context.stroke(
                    shadowPath,
                    with: .color(Color.black.opacity(0.26 * alpha)),
                    style: StrokeStyle(lineWidth: beamThickness * 1.05, lineCap: .round)
                )

                var beamPath = Path()
                beamPath.move(to: p1)
                beamPath.addLine(to: p2)
                context.stroke(
                    beamPath,
                    with: .linearGradient(
                        Gradient(colors: [
                            tint.opacity(1.0 * alpha),
                            Color(red: 0.84, green: 0.94, blue: 1.0).opacity(0.92 * alpha),
                        ]),
                        startPoint: CGPoint(x: cx, y: cy - s * 0.38),
                        endPoint: CGPoint(x: cx, y: cy + s * 0.38)
                    ),
                    style: StrokeStyle(lineWidth: beamThickness, lineCap: .round)
                )
            }

            // 2. Back Layer: Sweeping horizontal orbital crossbar capsule (slightly recessed)
            let barLeft = CGPoint(x: cx - s * 0.30, y: cy + s * 0.13)
            let barRight = CGPoint(x: cx + s * 0.30, y: cy + s * 0.13)
            drawSculptedBeam(from: barLeft, to: barRight, alpha: 0.90)

            // 3. Mid Layer: Left ascending Delta beam (passes over crossbar, under right apex beam)
            let leftBottom = CGPoint(x: cx - s * 0.24, y: cy + s * 0.31)
            let leftTop = CGPoint(x: cx + s * 0.05, y: cy - s * 0.33)
            drawSculptedBeam(from: leftBottom, to: leftTop, alpha: 0.96)

            // 4. Front Layer: Right ascending Delta beam (interlocks over left beam at apex like Apple App Store)
            let rightTop = CGPoint(x: cx - s * 0.05, y: cy - s * 0.33)
            let rightBottom = CGPoint(x: cx + s * 0.24, y: cy + s * 0.31)
            drawSculptedBeam(from: rightTop, to: rightBottom, alpha: 1.0)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Apple Icon Composer–style 3D squircle app tile for Grav:
/// Vibrant sky-cyan to deep ocean-azure gradient, soft top inner glow, 3D layered frosted-white
/// interlocking Delta-Arc mark, and crisp top-lit specular glass rim.
public struct GravAppIconTile: View {
    public var size: CGFloat

    public init(size: CGFloat = 26) {
        self.size = size
    }

    public var body: some View {
        let cornerRadius = size * 0.235
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            // 1. Vibrant Apple Sky-Cyan -> Electric Azure -> Deep Ocean Cobalt squircle substrate
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.22, green: 0.77, blue: 0.99), location: 0.0),
                        .init(color: Color(red: 0.07, green: 0.56, blue: 0.95), location: 0.52),
                        .init(color: Color(red: 0.04, green: 0.36, blue: 0.84), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // 2. Top-center luminous sky bloom
            shape.fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.34),
                        Color(red: 0.45, green: 0.88, blue: 1.0).opacity(0.14),
                        Color.clear,
                    ],
                    center: UnitPoint(x: 0.5, y: 0.12),
                    startRadius: 0,
                    endRadius: size * 0.78
                )
            )

            // 3. Sculptural 3D Layered Frosted-White Mark
            GravOrbitalMark(size: size * 0.74, tint: .white)

            // 4. Apple Icon Composer specular glass rim
            shape.strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.52), location: 0.0),
                        .init(color: Color.white.opacity(0.18), location: 0.45),
                        .init(color: Color.white.opacity(0.26), location: 1.0),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: max(0.5, size * 0.024)
            )
        }
        .frame(width: size, height: size)
    }
}

/// Renders Grav's Apple-style 3D layered squircle badge inside the Notch HUD and headers.
public struct AntigravityLogoView: View {
    public var icon: NSImage?
    public var size: CGFloat

    public init(icon: NSImage?, size: CGFloat = 16) {
        self.icon = icon
        self.size = size
    }

    public var body: some View {
        GravAppIconTile(size: size)
            .frame(width: size, height: size)
    }
}
