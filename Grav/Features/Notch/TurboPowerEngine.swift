import SwiftUI

/// 120Hz GPU-accelerated procedural Super Saiyan / Solar Corona kinetic energy canvas
/// rendered strictly while Antigravity is running in Turbo Mode (`AGENT_PERMISSION_PRESET_TURBO`).
///
/// Pure OLED light physics — zero static orange boxes, zero emojis, zero readability washout:
/// 1. Rising curl-warped volumetric golden-solar ki plumes along the obsidian base & flanks.
/// 2. Upward-drifting zero-gravity luminous ki embers with harmonic lateral swirl.
/// 3. Intermittent razor-thin (`0.75pt`) high-voltage SSJ2 plasma lightning crackles along the rim.
/// 4. Continuous perimeter liquid-gold specular aura edge + radial ignition shockwave on entry.
public struct TurboKineticAuraCanvas: View {
    public enum SurfaceStyle {
        case collapsed
        case expanded
    }

    public var style: SurfaceStyle
    public var isPowerSurging: Bool
    public var reduceMotion: Bool

    @State private var ignitionBurstProgress: CGFloat = 0
    @State private var showIgnitionBurst: Bool = false

    public init(
        style: SurfaceStyle,
        isPowerSurging: Bool,
        reduceMotion: Bool = false
    ) {
        self.style = style
        self.isPowerSurging = isPowerSurging
        self.reduceMotion = reduceMotion
    }

    // Calibrated Super Saiyan / Solar Corona light spectrum (pure gold -> solar amber -> white-hot core)
    private static let kiGold = Color(red: 1.00, green: 0.84, blue: 0.14)      // #FFD624
    private static let kiSolar = Color(red: 1.00, green: 0.58, blue: 0.04)     // #FF940A
    private static let kiCrimson = Color(red: 1.00, green: 0.24, blue: 0.18)   // #FF3D2E
    private static let kiWhiteHot = Color(red: 1.00, green: 0.98, blue: 0.86)  // #FFFA DB
    private static let kiArcCyan = Color(red: 0.72, green: 0.94, blue: 1.00)   // Crisp electric discharge tint

    public var body: some View {
        ZStack {
            if reduceMotion {
                staticReducedAura
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { ctx, size in
                        guard size.width > 4, size.height > 4 else { return }
                        drawVolumetricKiPlumes(in: &ctx, size: size, time: t)
                        drawRisingKiEmbers(in: &ctx, size: size, time: t)
                        drawPerimeterEnergyFilament(in: &ctx, size: size, time: t)
                        if isPowerSurging {
                            drawIntermittentKiLightning(in: &ctx, size: size, time: t)
                        }
                    }
                }
            }

            if showIgnitionBurst && !reduceMotion {
                ignitionShockwaveLayer
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            triggerIgnitionShockwave()
        }
        .onChange(of: isPowerSurging) { _, surging in
            if surging {
                triggerIgnitionShockwave()
            }
        }
    }

    // MARK: - 1. Rising Volumetric Ki Plumes (Super Saiyan Golden Aura Waves)

    private func drawVolumetricKiPlumes(in ctx: inout GraphicsContext, size: CGSize, time t: TimeInterval) {
        let intensity: Double = isPowerSurging ? 1.0 : 0.56
        let speed: Double = isPowerSurging ? 2.65 : 1.35

        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter

            switch style {
            case .collapsed:
                // Undulating solar plasma cushion rising along the bottom edge of the Dynamic Island pill
                let plumeCount = 5
                for i in 0..<plumeCount {
                    let seed = Double(i) * 1.73 + 0.4
                    let frac = (Double(i) + 0.5) / Double(plumeCount)
                    let sway = sin(t * speed * 0.9 + seed) * size.width * 0.09
                    let cx = size.width * frac + sway
                    let surge = 0.78 + 0.22 * sin(t * speed * 1.4 + seed * 2.1)
                    let rx = size.width * (0.19 + 0.05 * sin(t * 1.3 + seed))
                    let ry = size.height * (0.72 * surge)
                    let cy = size.height * 1.04

                    let rect = CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)
                    let colorCore = (i % 2 == 0) ? Self.kiGold : Self.kiSolar
                    let grad = Gradient(stops: [
                        .init(color: Self.kiWhiteHot.opacity(0.20 * intensity), location: 0.0),
                        .init(color: colorCore.opacity(0.24 * intensity), location: 0.35),
                        .init(color: Self.kiCrimson.opacity(0.09 * intensity), location: 0.72),
                        .init(color: .clear, location: 1.0),
                    ])
                    layer.fill(
                        Path(ellipseIn: rect),
                        with: .radialGradient(grad, center: CGPoint(x: cx, y: cy), startRadius: 1, endRadius: max(rx, ry))
                    )
                }

            case .expanded:
                // Sweeping flame-tongue plumes hugging the bottom rim and outer flanks (leaving center 100% crisp for text)
                let plumeCount = 7
                for i in 0..<plumeCount {
                    let seed = Double(i) * 2.11 + 0.7
                    let frac = Double(i) / Double(plumeCount - 1)
                    // Concentrate aura strongly along left/right flanks and bottom U-curve
                    let edgeWeight = 0.55 + 0.45 * abs(frac * 2.0 - 1.0)
                    let sway = sin(t * speed * 0.85 + seed) * 28.0
                    let cx = size.width * frac + sway
                    let lift = (0.5 + 0.5 * sin(t * speed * 1.25 + seed * 1.6)) * 22.0 * edgeWeight
                    let rx = size.width * (0.14 + 0.04 * cos(t * 1.1 + seed))
                    let ry = (58.0 + lift * 1.8) * (isPowerSurging ? 1.18 : 0.78)
                    let cy = size.height + 16.0 - lift * 0.4

                    let rect = CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)
                    let primary = (i % 2 == 0) ? Self.kiGold : Self.kiSolar
                    let grad = Gradient(stops: [
                        .init(color: Self.kiWhiteHot.opacity(0.14 * intensity * edgeWeight), location: 0.0),
                        .init(color: primary.opacity(0.17 * intensity * edgeWeight), location: 0.34),
                        .init(color: Self.kiCrimson.opacity(0.06 * intensity), location: 0.68),
                        .init(color: .clear, location: 1.0),
                    ])
                    layer.fill(
                        Path(ellipseIn: rect),
                        with: .radialGradient(grad, center: CGPoint(x: cx, y: cy), startRadius: 2, endRadius: max(rx, ry))
                    )
                }

                // Subtle twin flank rising energy tongues along left & right bezels
                for side in [-1.0, 1.0] {
                    let phase = t * speed * 1.1 + (side > 0 ? 1.8 : 0.0)
                    let cx = side < 0 ? -12.0 : size.width + 12.0
                    let cy = size.height * (0.52 + 0.14 * sin(phase))
                    let rx: CGFloat = isPowerSurging ? 54 : 36
                    let ry: CGFloat = size.height * 0.48
                    let rect = CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)
                    let grad = Gradient(stops: [
                        .init(color: Self.kiGold.opacity(0.16 * intensity), location: 0.0),
                        .init(color: Self.kiSolar.opacity(0.07 * intensity), location: 0.48),
                        .init(color: .clear, location: 1.0),
                    ])
                    layer.fill(
                        Path(ellipseIn: rect),
                        with: .radialGradient(grad, center: CGPoint(x: cx, y: cy), startRadius: 1, endRadius: ry)
                    )
                }
            }
        }
    }

    // MARK: - 2. Rising Zero-Gravity Ki Embers (Upward Energy Motes)

    private func drawRisingKiEmbers(in ctx: inout GraphicsContext, size: CGSize, time t: TimeInterval) {
        let count = (style == .collapsed)
            ? (isPowerSurging ? 14 : 7)
            : (isPowerSurging ? 28 : 12)
        let speedMult: Double = isPowerSurging ? 1.0 : 0.52

        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter

            for i in 0..<count {
                // Deterministic pseudo-random per-particle orbital parameters
                let h1 = fract(sin(Double(i + 1) * 12.9898) * 43_758.5453)
                let h2 = fract(sin(Double(i + 1) * 78.233) * 29_183.1234)
                let h3 = fract(sin(Double(i + 1) * 45.164) * 19_482.7711)

                let cycleDuration = (style == .collapsed ? 1.15 : 2.1) + h2 * 1.5
                let rawProgress = fract((t * speedMult) / cycleDuration + h1)

                // Particles erupt upward from the bottom edge and dissolve before reaching top chrome
                let yStart = size.height + 2.0
                let riseSpan = (style == .collapsed) ? (size.height * 0.92) : (size.height * 0.72)
                let y = yStart - CGFloat(rawProgress) * riseSpan

                // In expanded mode, bias motes toward the flanks & perimeter so text stays crystal clear
                let baseXFrac: Double
                if style == .expanded {
                    let band = h3 < 0.5 ? (h3 * 0.36) : (1.0 - (1.0 - h3) * 0.36)
                    baseXFrac = (i % 4 == 0) ? h3 : band
                } else {
                    baseXFrac = 0.06 + h3 * 0.88
                }
                let swirl = sin(rawProgress * .pi * 2.5 + h1 * 12.0) * (style == .collapsed ? 4.0 : 11.0)
                let x = size.width * baseXFrac + swirl

                // Smooth fade-in at spawn, razor-sharp fade-out as it ascends
                let alphaEnvelope = sin(rawProgress * .pi) * pow(1.0 - rawProgress, 0.55)
                let alpha = alphaEnvelope * (isPowerSurging ? 0.92 : 0.52)
                guard alpha > 0.03 else { continue }

                let radius = CGFloat(style == .collapsed ? (0.9 + h2 * 1.1) : (1.1 + h2 * 1.6))
                let streakHeight = radius * CGFloat(isPowerSurging ? 3.2 : 1.8)

                // Tiny upward-streaking ki spark
                let sparkRect = CGRect(
                    x: x - radius * 0.7,
                    y: y - streakHeight * 0.5,
                    width: radius * 1.4,
                    height: streakHeight
                )
                let tint = (i % 3 == 0) ? Self.kiWhiteHot : ((i % 3 == 1) ? Self.kiGold : Self.kiSolar)
                layer.fill(Path(ellipseIn: sparkRect), with: .color(tint.opacity(alpha)))
            }
        }
    }

    // MARK: - 3. Continuous Perimeter Liquid-Gold Filament

    private func drawPerimeterEnergyFilament(in ctx: inout GraphicsContext, size: CGSize, time t: TimeInterval) {
        let period: Double = isPowerSurging ? 1.45 : 3.2
        let phase = fract(t / period)
        let center = 0.12 + 0.76 * (0.5 - 0.5 * cos(phase * .pi * 2.0))
        let spread = isPowerSurging ? 0.34 : 0.24

        let grad = Gradient(stops: [
            .init(color: .clear, location: max(0, center - spread * 1.5)),
            .init(color: Self.kiCrimson.opacity(0.65), location: max(0, center - spread * 0.95)),
            .init(color: Self.kiSolar.opacity(0.95), location: max(0, center - spread * 0.45)),
            .init(color: Self.kiGold, location: max(0, center - spread * 0.16)),
            .init(color: Self.kiWhiteHot, location: center),
            .init(color: Self.kiGold, location: min(1, center + spread * 0.16)),
            .init(color: Self.kiSolar.opacity(0.95), location: min(1, center + spread * 0.45)),
            .init(color: Self.kiCrimson.opacity(0.65), location: min(1, center + spread * 0.95)),
            .init(color: .clear, location: min(1, center + spread * 1.5)),
        ])

        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter

            let inset: CGFloat = style == .collapsed ? 14 : 20
            let y = size.height - 1.0
            var path = Path()
            path.move(to: CGPoint(x: inset, y: y))
            path.addLine(to: CGPoint(x: size.width - inset, y: y))

            let opacity = isPowerSurging ? 0.96 : 0.48
            layer.stroke(
                path,
                with: .linearGradient(grad, startPoint: CGPoint(x: 0, y: y), endPoint: CGPoint(x: size.width, y: y)),
                style: StrokeStyle(lineWidth: isPowerSurging ? 1.6 : 1.0, lineCap: .round)
            )
            // Soft micro-bloom directly over the filament
            if isPowerSurging {
                layer.opacity = opacity * 0.42
                layer.stroke(
                    path,
                    with: .linearGradient(grad, startPoint: CGPoint(x: 0, y: y), endPoint: CGPoint(x: size.width, y: y)),
                    style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                )
            }
        }
    }

    // MARK: - 4. Intermittent Razor-Thin SSJ2 Ki Lightning Crackles

    private func drawIntermittentKiLightning(in ctx: inout GraphicsContext, size: CGSize, time t: TimeInterval) {
        // Trigger a crisp 140ms electric crackle every ~1.7s
        let cycle = 1.72
        let slot = floor(t / cycle)
        let localT = t - slot * cycle
        guard localT < 0.16 else { return }

        let flashAlpha = sin((localT / 0.16) * .pi)
        guard flashAlpha > 0.08 else { return }

        let hStart = fract(sin(slot * 91.37) * 41_823.73)
        let hSide = fract(sin(slot * 37.19) * 18_472.11)

        var bolt = Path()
        if style == .collapsed {
            let x0 = size.width * (0.14 + hStart * 0.56)
            let span = size.width * 0.22
            let yBase = size.height - 3.0
            bolt.move(to: CGPoint(x: x0, y: yBase))
            let segs = 5
            for s in 1...segs {
                let f = Double(s) / Double(segs)
                let jitter = (fract(sin((slot * 13 + Double(s)) * 71.1) * 9182.3) - 0.5) * 7.5
                bolt.addLine(to: CGPoint(x: x0 + span * f, y: yBase - abs(jitter) - 1.0))
            }
        } else {
            // Arc along either the left or right vertical bezel of the expanded HUD
            let isLeft = hSide < 0.5
            let xBase: CGFloat = isLeft ? 4.5 : (size.width - 4.5)
            let dir: CGFloat = isLeft ? 1.0 : -1.0
            let yStart = size.height * (0.35 + hStart * 0.38)
            let arcHeight: CGFloat = 54.0
            bolt.move(to: CGPoint(x: xBase, y: yStart))
            let segs = 6
            for s in 1...segs {
                let f = Double(s) / Double(segs)
                let j = fract(sin((slot * 19 + Double(s)) * 63.7) * 5182.9)
                let dx = dir * CGFloat(j * 11.0 * sin(f * .pi))
                bolt.addLine(to: CGPoint(x: xBase + dx, y: yStart - CGFloat(f) * arcHeight))
            }
        }

        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter
            // Outer electric cyan-gold aura stroke
            layer.stroke(
                bolt,
                with: .color(Self.kiArcCyan.opacity(0.45 * flashAlpha)),
                style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)
            )
            // Razor-sharp white-hot lightning core
            layer.stroke(
                bolt,
                with: .color(Self.kiWhiteHot.opacity(0.95 * flashAlpha)),
                style: StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round)
            )
        }
    }

    // MARK: - 5. Radial Ignition Shockwave Ring

    private var ignitionShockwaveLayer: some View {
        GeometryReader { geo in
            let maxDim = max(geo.size.width, geo.size.height)
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [Self.kiWhiteHot, Self.kiGold, Self.kiSolar.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(0.8, 3.0 * (1.0 - ignitionBurstProgress))
                )
                .frame(width: maxDim * 0.25, height: maxDim * 0.25)
                .scaleEffect(0.4 + ignitionBurstProgress * 4.4)
                .opacity(Double(max(0, 1.0 - ignitionBurstProgress)) * 0.72)
                .position(
                    x: style == .collapsed ? 24 : geo.size.width * 0.5,
                    y: style == .collapsed ? geo.size.height * 0.5 : 18
                )
                .blendMode(.plusLighter)
        }
    }

    private func triggerIgnitionShockwave() {
        guard !reduceMotion else { return }
        showIgnitionBurst = true
        ignitionBurstProgress = 0
        withAnimation(.timingCurve(0.16, 1.0, 0.30, 1.0, duration: 0.56)) {
            ignitionBurstProgress = 1.0
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 580_000_000)
            showIgnitionBurst = false
        }
    }

    private var staticReducedAura: some View {
        LinearGradient(
            colors: [
                Color.clear,
                Self.kiGold.opacity(isPowerSurging ? 0.14 : 0.06),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func fract(_ value: Double) -> Double {
        value - floor(value)
    }
}

/// Borderless Super Saiyan solar-gold kinetic glyph & text readout for Turbo mode
/// (zero boxy AI-slop pill rectangles).
public struct TurboSolarEmblem: View {
    public var isSurging: Bool
    public var reduceMotion: Bool

    public init(isSurging: Bool, reduceMotion: Bool = false) {
        self.isSurging = isSurging
        self.reduceMotion = reduceMotion
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.96, blue: 0.78),
                            Color(red: 1.0, green: 0.80, blue: 0.14),
                            Color(red: 1.0, green: 0.45, blue: 0.06),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(
                    color: Color(red: 1.0, green: 0.72, blue: 0.12).opacity(isSurging ? 0.65 : 0.32),
                    radius: isSurging ? 4 : 2
                )

            NotchShimmerText(
                text: "TURBO",
                font: .system(size: 9, weight: .heavy, design: .rounded),
                tracking: 0.7,
                baseOpacity: 0.68,
                peakOpacity: 1.0,
                period: isSurging ? 1.15 : 2.1,
                turboMode: true,
                reduceMotion: reduceMotion
            )
        }
        .help("Antigravity Turbo Mode — Unrestricted high-velocity execution")
    }
}
