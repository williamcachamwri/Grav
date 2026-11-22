import SwiftUI

/// 36-segment, 4-harmonic polar Catmull-Rom spline shape that blooms from a central
/// liquid orb (`progress: 0 -> 0.27`) and unfolds smoothly edge-to-edge (`0.27 -> 1.0`).
public struct OrganicPortalShape: Shape {
    public var progress: CGFloat
    public var phase: CGFloat

    public init(progress: CGFloat, phase: CGFloat = 0) {
        self.progress = progress
        self.phase = phase
    }

    public nonisolated var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, phase) }
        set {
            progress = newValue.first
            phase = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        let clamped = max(0, min(1, progress))
        guard clamped > 0.0005, rect.width > 0, rect.height > 0 else {
            return Path()
        }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let minDim = min(rect.width, rect.height)
        let maxReach = hypot(rect.width, rect.height) * 0.58

        // Non-linear radius mapping:
        // progress = 0.27 -> sculptural orb (~23% of min dimension)
        // progress = 1.00 -> edge-to-edge full coverage beyond all four corners
        let orbRadius = minDim * 0.23
        let baseRadius: CGFloat
        if clamped <= 0.27 {
            let t = clamped / 0.27
            let eased = 1 - pow(1 - t, 2.2)
            baseRadius = orbRadius * eased
        } else {
            let t = (clamped - 0.27) / 0.73
            let eased = t * t * (3 - 2 * t)
            baseRadius = orbRadius + (maxReach - orbRadius) * eased
        }

        // Organic 4-harmonic wobble peaks during orb hover and settles cleanly before edge lock
        let wobbleEnvelope: CGFloat
        if clamped < 0.08 {
            wobbleEnvelope = clamped / 0.08
        } else if clamped <= 0.55 {
            wobbleEnvelope = 1.0
        } else {
            let t = (clamped - 0.55) / 0.45
            wobbleEnvelope = max(0, 1 - t * t)
        }
        let wobbleAmplitude = 0.095 * wobbleEnvelope

        let segmentCount = 36
        var points: [CGPoint] = []
        points.reserveCapacity(segmentCount)

        for index in 0..<segmentCount {
            let theta = (CGFloat(index) / CGFloat(segmentCount)) * (.pi * 2)
            let h1 = 0.42 * sin(2 * theta + phase)
            let h2 = 0.28 * sin(3 * theta - 1.3 * phase)
            let h3 = 0.19 * cos(5 * theta + 0.7 * phase)
            let h4 = 0.11 * sin(7 * theta - 1.9 * phase)
            let harmonic = h1 + h2 + h3 + h4

            let radius = max(1, baseRadius * (1 + wobbleAmplitude * harmonic))
            let x = center.x + cos(theta) * radius
            let y = center.y + sin(theta) * radius
            points.append(CGPoint(x: x, y: y))
        }

        // Closed Catmull-Rom spline converted to smooth cubic Bezier segments
        var path = Path()
        path.move(to: points[0])

        for i in 0..<segmentCount {
            let p0 = points[(i - 1 + segmentCount) % segmentCount]
            let p1 = points[i]
            let p2 = points[(i + 1) % segmentCount]
            let p3 = points[(i + 2) % segmentCount]

            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6.0,
                y: p1.y + (p2.y - p0.y) / 6.0
            )
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6.0,
                y: p2.y - (p3.y - p1.y) / 6.0
            )
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }

        path.closeSubpath()
        return path
    }
}

/// Soft glacial cyan-teal ambient corona radiating around the blooming portal orb
/// inside the `#05080C` obsidian void during Beats 1–2.
public struct PortalAmbientCorona: View {
    public var progress: CGFloat
    public var phase: CGFloat

    public init(progress: CGFloat, phase: CGFloat = 0) {
        self.progress = progress
        self.phase = phase
    }

    public var body: some View {
        GeometryReader { proxy in
            let minDim = min(proxy.size.width, proxy.size.height)
            let clamped = max(0, min(1, progress))
            let presence = clamped <= 0.35
                ? min(1, clamped / 0.22)
                : max(0, 1 - (clamped - 0.35) / 0.45)
            let breathe = 1.0 + 0.035 * sin(phase * 1.4)
            let diameter = minDim * (0.62 + clamped * 0.85) * breathe

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: GravPalette.glacialCyan.opacity(0.32 * presence), location: 0.0),
                                .init(color: GravPalette.glacialTeal.opacity(0.22 * presence), location: 0.38),
                                .init(color: GravPalette.glacialTeal.opacity(0.06 * presence), location: 0.68),
                                .init(color: Color.clear, location: 1.0),
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: diameter * 0.5
                        )
                    )
                    .frame(width: diameter, height: diameter)
                    .blur(radius: 36)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Glacial Aerospace Teal (`#14B8A6`), Aerospace Cyan (`#38BDF8`), Crystalline Mist,
/// and Silk-White animated atmospheric aurora backdrop.
public struct GlacialAuroraView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var isPaused: Bool

    public init(isPaused: Bool = false) {
        self.isPaused = isPaused
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion || isPaused)) { timeline in
            let t = reduceMotion ? 0.0 : timeline.date.timeIntervalSinceReferenceDate
            GlacialAuroraCanvas(time: t)
        }
        .accessibilityHidden(true)
    }
}

private struct GlacialAuroraCanvas: View {
    let time: TimeInterval

    private static let deepPolarBase = Color(red: 0x05 / 255.0, green: 0x16 / 255.0, blue: 0x20 / 255.0)
    private static let polarSlate = Color(red: 0x0A / 255.0, green: 0x2E / 255.0, blue: 0x3F / 255.0)
    private static let crystallineMist = Color(red: 0xC8 / 255.0, green: 0xEC / 255.0, blue: 0xF7 / 255.0)
    private static let glacialDeepTeal = Color(red: 0x0D / 255.0, green: 0x7A / 255.0, blue: 0x7E / 255.0)

    var body: some View {
        Canvas(opaque: true, colorMode: .linear, rendersAsynchronously: false) { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let w = size.width
            let h = size.height
            let diag = hypot(w, h)

            // 1. Deep polar atmospheric substrate
            context.fill(
                Path(rect),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Self.deepPolarBase, location: 0.0),
                        .init(color: Self.polarSlate, location: 0.52),
                        .init(color: Color(red: 0x06 / 255.0, green: 0x1B / 255.0, blue: 0x26 / 255.0), location: 1.0),
                    ]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: w, y: h)
                )
            )

            // Slow, laminar orbital drift phases
            let p1 = time * 0.24
            let p2 = time * 0.19 + 1.8
            let p3 = time * 0.15 + 3.4
            let p4 = time * 0.21 + 5.1

            // 2. Primary Glacial Teal atmospheric sweep (upper-left to center)
            drawRadialBloom(
                in: &context,
                center: CGPoint(
                    x: w * (0.28 + 0.08 * cos(p1)),
                    y: h * (0.30 + 0.07 * sin(p1 * 0.9))
                ),
                radius: diag * 0.54,
                stops: [
                    .init(color: GravPalette.glacialTeal.opacity(0.62), location: 0.0),
                    .init(color: Self.glacialDeepTeal.opacity(0.32), location: 0.45),
                    .init(color: Color.clear, location: 1.0),
                ]
            )

            // 3. Aerospace Cyan horizon stream (upper-right)
            drawRadialBloom(
                in: &context,
                center: CGPoint(
                    x: w * (0.76 + 0.07 * sin(p2)),
                    y: h * (0.24 + 0.08 * cos(p2 * 0.8))
                ),
                radius: diag * 0.52,
                stops: [
                    .init(color: GravPalette.glacialCyan.opacity(0.56), location: 0.0),
                    .init(color: GravPalette.glacialTeal.opacity(0.24), location: 0.50),
                    .init(color: Color.clear, location: 1.0),
                ]
            )

            // 4. Crystalline Mist refracted band (lower-right upwelling)
            drawRadialBloom(
                in: &context,
                center: CGPoint(
                    x: w * (0.66 + 0.09 * cos(p3)),
                    y: h * (0.78 + 0.06 * sin(p3))
                ),
                radius: diag * 0.44,
                stops: [
                    .init(color: Self.crystallineMist.opacity(0.34), location: 0.0),
                    .init(color: GravPalette.glacialCyan.opacity(0.18), location: 0.42),
                    .init(color: Color.clear, location: 1.0),
                ]
            )

            // 5. Silk-White glacial specular crest (soft top-center luminescence)
            drawRadialBloom(
                in: &context,
                center: CGPoint(
                    x: w * (0.48 + 0.10 * sin(p4)),
                    y: h * (0.14 + 0.05 * cos(p4 * 1.1))
                ),
                radius: diag * 0.34,
                stops: [
                    .init(color: GravPalette.titaniumWhite.opacity(0.30), location: 0.0),
                    .init(color: Self.crystallineMist.opacity(0.16), location: 0.38),
                    .init(color: Color.clear, location: 1.0),
                ]
            )

            // 6. Subtle obsidian edge vignette for crisp editorial typography contrast
            context.fill(
                Path(rect),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color.clear, location: 0.42),
                        .init(color: GravPalette.obsidianVoid.opacity(0.42), location: 1.0),
                    ]),
                    center: CGPoint(x: w * 0.5, y: h * 0.48),
                    startRadius: diag * 0.14,
                    endRadius: diag * 0.64
                )
            )
        }
    }

    private func drawRadialBloom(
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        stops: [Gradient.Stop]
    ) {
        let bloomRect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.fill(
            Path(ellipseIn: bloomRect),
            with: .radialGradient(
                Gradient(stops: stops),
                center: center,
                startRadius: 0,
                endRadius: radius
            )
        )
    }
}
