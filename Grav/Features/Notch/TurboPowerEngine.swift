import AppKit
import Metal
import MetalKit
import SwiftUI

/// 120Hz Apple Silicon GPU Super Saiyan Power-Eruption Engine rendered strictly while
/// Antigravity is running in Turbo Mode (`AGENT_PERMISSION_PRESET_TURBO`) and enabled in Settings.
///
/// Combines:
/// 1. Full-bleed runtime-compiled Apple Silicon Metal fragment shader (`SuperSaiyanMetalView`):
///    - 5-octave anisotropic ridged FBM double-domain-warped roaring Ki flame tongues.
///    - Crisp anime double-wall aura cel-contour rim (DBS: Broly / DBZ energy silhouette).
///    - Inner hyper-velocity white-hot plasma flame core locked 0.0px to the exact outer Notch U-bezel.
///    - Atmospheric thermal Ki pressure waves + vertical anime speed-line wind streaks.
///    - GPU toroidal power-up shockwave blast on ignition / form switch / surge.
///    - 6 authentic Dragon Ball transformation palettes (SSJ, God, Blue, Rosé, Ultra Instinct, Legendary).
/// 2. Multi-forked recursive midpoint-displaced SSJ2 bio-electric lightning arcs with junction sparks.
/// 3. Sharp upward-lancing diamond Ki shards + luminous rising stardust embers.
public struct TurboKineticAuraCanvas: View {
    public enum SurfaceStyle {
        case collapsed
        case expanded
    }

    public var style: SurfaceStyle
    public var isPowerSurging: Bool
    public var theme: SuperSaiyanAuraTheme
    public var burstTrigger: Int
    public var cornerRadius: CGFloat
    public var reduceMotion: Bool

    @State private var localBurstNonce: Int = 0

    public init(
        style: SurfaceStyle,
        isPowerSurging: Bool,
        theme: SuperSaiyanAuraTheme = .superSaiyan,
        burstTrigger: Int = 0,
        cornerRadius: CGFloat? = nil,
        reduceMotion: Bool = false
    ) {
        self.style = style
        self.isPowerSurging = isPowerSurging
        self.theme = theme
        self.burstTrigger = burstTrigger
        self.cornerRadius = cornerRadius ?? (style == .collapsed ? 16 : 22)
        self.reduceMotion = reduceMotion
    }

    public var body: some View {
        ZStack {
            if reduceMotion {
                staticReducedAura
            } else {
                // Layer 1: 120 FPS Native Apple Silicon Metal GPU Fragment Shader
                SuperSaiyanMetalView(
                    isCollapsed: style == .collapsed,
                    isPowerSurging: isPowerSurging,
                    theme: theme,
                    burstNonce: localBurstNonce &+ burstTrigger,
                    cornerRadius: cornerRadius
                )

                // Layer 2: Multi-Forked SSJ2 Bio-Electric Lightning + Sharp Ki Lances & Energy Sparks
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { ctx, size in
                        guard size.width > 4, size.height > 4 else { return }
                        drawRisingEnergySparks(in: &ctx, size: size, time: t)
                        drawSharpKiLances(in: &ctx, size: size, time: t)
                        drawSuperSaiyan2Lightning(in: &ctx, size: size, time: t)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            localBurstNonce &+= 1
        }
        .onChange(of: isPowerSurging) { _, surging in
            if surging {
                localBurstNonce &+= 1
            }
        }
        .onChange(of: theme) { _, _ in
            localBurstNonce &+= 1
        }
    }

    // MARK: - Luminous Rising Ki Sparks & Ultra Instinct Stardust Orbs

    private func drawRisingEnergySparks(in ctx: inout GraphicsContext, size: CGSize, time t: TimeInterval) {
        let isUI = theme == .ultraInstinct
        let count: Int
        if style == .collapsed {
            count = isPowerSurging ? (isUI ? 22 : 14) : (isUI ? 12 : 7)
        } else {
            count = isPowerSurging ? (isUI ? 42 : 28) : (isUI ? 20 : 12)
        }

        let speedMult = isPowerSurging ? 1.48 : 0.76
        let outerTint = theme.primaryColor
        let coreTint = theme.coreColor
        let accentTint = theme.lightningColor

        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter

            for i in 0..<count {
                let h1 = fract(sin(Double(i + 11) * 19.193) * 52_911.431)
                let h2 = fract(sin(Double(i + 11) * 83.719) * 31_415.926)
                let h3 = fract(sin(Double(i + 11) * 41.273) * 27_182.818)
                let h4 = fract(sin(Double(i + 11) * 63.511) * 14_142.135)

                let duration = (style == .collapsed ? 0.95 : 1.75) + h2 * 1.15
                let prog = fract((t * speedMult) / duration + h1)

                let baseX: CGFloat
                if style == .expanded {
                    // Cluster along left/right flanks and bottom rim so center text stays crystal-clear
                    if h4 < 0.72 {
                        let leftSide = h3 < 0.5
                        let inset = CGFloat(2.0 + fract(h3 * 9.7) * (isPowerSurging ? 30.0 : 18.0))
                        baseX = leftSide ? inset : (size.width - inset)
                    } else {
                        baseX = size.width * CGFloat(0.10 + h3 * 0.80)
                    }
                } else {
                    baseX = size.width * CGFloat(0.04 + h3 * 0.92)
                }

                // Gentle heat-convection horizontal flutter as spark accelerates upward
                let flutter = CGFloat(sin(t * (5.5 + h2 * 4.0) + h1 * 25.0)) * (style == .collapsed ? 2.2 : 4.2)
                let x = baseX + flutter
                let riseSpan: CGFloat
                if style == .expanded && h4 >= 0.72 {
                    riseSpan = size.height * (isPowerSurging ? 0.24 : 0.14)
                } else {
                    riseSpan = size.height * (style == .collapsed ? 0.96 : 0.88)
                }
                let y = size.height - 2.0 - CGFloat(pow(prog, 0.82)) * riseSpan

                let fade = sin(prog * .pi) * pow(1.0 - prog, 0.35)
                let alpha = fade * (isPowerSurging ? 0.96 : 0.62)
                guard alpha > 0.04 else { continue }

                let radius = CGFloat((style == .collapsed ? 0.9 : 1.15) + h4 * (isUI ? 1.6 : 1.25)) * (isPowerSurging ? 1.15 : 0.85)
                let glowRadius = radius * (isUI ? 3.4 : 2.6)

                let glowRect = CGRect(x: x - glowRadius, y: y - glowRadius, width: glowRadius * 2, height: glowRadius * 2)
                let orbTint = (i % 4 == 0) ? accentTint : outerTint
                layer.fill(Path(ellipseIn: glowRect), with: .color(orbTint.opacity(alpha * 0.42)))

                let coreRect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                layer.fill(Path(ellipseIn: coreRect), with: .color(coreTint.opacity(alpha)))
            }
        }
    }

    // MARK: - Sharp Upward-Lancing Diamond Ki Shards

    private func drawSharpKiLances(in ctx: inout GraphicsContext, size: CGSize, time t: TimeInterval) {
        let count = (style == .collapsed)
            ? (isPowerSurging ? 18 : 9)
            : (isPowerSurging ? 36 : 16)
        let speedMult = isPowerSurging ? 1.72 : 0.88
        let primaryTint = theme.primaryColor
        let innerTint = theme.innerColor
        let coreTint = theme.coreColor

        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter

            for i in 0..<count {
                let h1 = fract(sin(Double(i + 1) * 12.9898) * 43_758.5453)
                let h2 = fract(sin(Double(i + 1) * 78.233) * 29_183.1234)
                let h3 = fract(sin(Double(i + 1) * 45.164) * 19_482.7711)

                let duration = (style == .collapsed ? 0.62 : 1.12) + h2 * 0.72
                let prog = fract((t * speedMult) / duration + h1)

                let x: CGFloat
                if style == .expanded {
                    let edgeSide = h3 < 0.5
                    let inset = CGFloat(1.5 + fract(h3 * 7.3) * (isPowerSurging ? 25.0 : 14.0))
                    x = edgeSide ? inset : (size.width - inset)
                } else {
                    x = size.width * CGFloat(0.05 + h3 * 0.90)
                }

                let riseSpan = (style == .collapsed) ? size.height * 0.98 : size.height * 0.86
                let y = size.height - CGFloat(pow(prog, 0.88)) * riseSpan

                let alpha = sin(prog * .pi) * pow(1.0 - prog, 0.36) * (isPowerSurging ? 1.0 : 0.68)
                guard alpha > 0.04 else { continue }

                let halfW: CGFloat = style == .collapsed ? 0.85 : 1.15
                let halfH: CGFloat = CGFloat((style == .collapsed ? 5.5 : 10.5) + h2 * 9.0) * (isPowerSurging ? 1.45 : 0.88)

                var shard = Path()
                shard.move(to: CGPoint(x: x, y: y - halfH))
                shard.addLine(to: CGPoint(x: x + halfW, y: y))
                shard.addLine(to: CGPoint(x: x, y: y + halfH * 0.45))
                shard.addLine(to: CGPoint(x: x - halfW, y: y))
                shard.closeSubpath()

                let tint = (i % 3 == 0) ? coreTint : ((i % 3 == 1) ? innerTint : primaryTint)
                layer.fill(shard, with: .color(tint.opacity(alpha)))
            }
        }
    }

    // MARK: - Multi-Forked Super Saiyan 2 Bio-Electric Lightning

    private func drawSuperSaiyan2Lightning(in ctx: inout GraphicsContext, size: CGSize, time t: TimeInterval) {
        let channelCount = isPowerSurging ? 4 : 2
        let boltGlow = theme.lightningColor
        let boltCore = theme.coreColor

        for channel in 0..<channelCount {
            let cycle: Double
            if isPowerSurging {
                switch channel {
                case 0: cycle = 0.64
                case 1: cycle = 0.97
                case 2: cycle = 1.31
                default: cycle = 1.73
                }
            } else {
                cycle = channel == 0 ? 1.95 : 3.15
            }

            let offset = Double(channel) * 0.37
            let shifted = t + offset
            let slot = floor(shifted / cycle)
            let localT = shifted - slot * cycle
            let boltLife = isPowerSurging ? 0.21 : 0.15
            guard localT < boltLife else { continue }

            let norm = localT / boltLife
            // High-voltage double-strobe anime lightning flicker
            let flicker = sin(norm * .pi) * (0.68 + 0.32 * sin(norm * .pi * 6.0))
            guard flicker > 0.08 else { continue }

            let seed = slot * 31.7 + Double(channel) * 97.3
            let (start, end, displacement) = lightningEndpoints(for: size, seed: seed)

            var mainBolt = Path()
            var branchBolt = Path()
            var subBranchBolt = Path()

            let points = displacedLightningChain(from: start, to: end, depth: 4, displacement: displacement, seed: seed)
            if let first = points.first {
                mainBolt.move(to: first)
                for pt in points.dropFirst() {
                    mainBolt.addLine(to: pt)
                }
            }

            var sparkVertices: [CGPoint] = []
            if points.count >= 9 {
                let fork1Idx = points.count / 3
                let fork2Idx = (points.count * 2) / 3
                let forkIndices = [fork1Idx, fork2Idx]

                for (bIdx, fIdx) in forkIndices.enumerated() {
                    let origin = points[fIdx]
                    sparkVertices.append(origin)
                    let dirX = (end.x - start.x) * (bIdx == 0 ? 0.42 : 0.30)
                    let dirY = (end.y - start.y) * (bIdx == 0 ? 0.42 : 0.30)
                    let perpSign: CGFloat = fract(sin((seed + Double(bIdx) * 19.0) * 17.3) * 4123.1) > 0.5 ? 1.0 : -1.0
                    let forkEnd = CGPoint(
                        x: origin.x + dirX - dirY * 0.62 * perpSign,
                        y: origin.y + dirY + dirX * 0.62 * perpSign
                    )
                    let branchPts = displacedLightningChain(
                        from: origin,
                        to: forkEnd,
                        depth: 2,
                        displacement: displacement * (bIdx == 0 ? 0.58 : 0.44),
                        seed: seed + 51.9 + Double(bIdx) * 23.1
                    )
                    if let bf = branchPts.first {
                        if bIdx == 0 {
                            branchBolt.move(to: bf)
                            for pt in branchPts.dropFirst() { branchBolt.addLine(to: pt) }
                        } else {
                            subBranchBolt.move(to: bf)
                            for pt in branchPts.dropFirst() { subBranchBolt.addLine(to: pt) }
                        }
                    }
                }
            }

            ctx.drawLayer { layer in
                layer.blendMode = .plusLighter

                // Wide electric plasma bloom
                layer.stroke(
                    mainBolt,
                    with: .color(boltGlow.opacity(0.32 * flicker)),
                    style: StrokeStyle(lineWidth: style == .collapsed ? 6.5 : 8.5, lineCap: .round, lineJoin: .round)
                )
                // Crisp inner colored lightning sheath
                layer.stroke(
                    mainBolt,
                    with: .color(boltGlow.opacity(0.84 * flicker)),
                    style: StrokeStyle(lineWidth: style == .collapsed ? 2.8 : 3.6, lineCap: .round, lineJoin: .round)
                )
                layer.stroke(
                    branchBolt,
                    with: .color(boltGlow.opacity(0.66 * flicker)),
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                )
                layer.stroke(
                    subBranchBolt,
                    with: .color(boltGlow.opacity(0.48 * flicker)),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                )
                // Blinding white-hot ionized arc core
                layer.stroke(
                    mainBolt,
                    with: .color(boltCore.opacity(1.0 * flicker)),
                    style: StrokeStyle(lineWidth: style == .collapsed ? 1.05 : 1.3, lineCap: .round, lineJoin: .round)
                )
                layer.stroke(
                    branchBolt,
                    with: .color(boltCore.opacity(0.92 * flicker)),
                    style: StrokeStyle(lineWidth: 0.85, lineCap: .round, lineJoin: .round)
                )
                layer.stroke(
                    subBranchBolt,
                    with: .color(boltCore.opacity(0.76 * flicker)),
                    style: StrokeStyle(lineWidth: 0.65, lineCap: .round, lineJoin: .round)
                )

                // Hot ionized crackle flashes at fork vertices
                for vertex in sparkVertices {
                    let r: CGFloat = style == .collapsed ? 2.2 : 3.2
                    let rect = CGRect(x: vertex.x - r, y: vertex.y - r, width: r * 2, height: r * 2)
                    layer.fill(Path(ellipseIn: rect), with: .color(boltCore.opacity(0.85 * flicker)))
                }
            }
        }
    }

    private func lightningEndpoints(for size: CGSize, seed: Double) -> (CGPoint, CGPoint, CGFloat) {
        let hA = fract(sin(seed * 12.7) * 43_123.9)
        let hB = fract(sin(seed * 67.3) * 19_481.2)

        if style == .collapsed {
            let x0 = size.width * CGFloat(0.06 + hA * 0.56)
            let span = size.width * CGFloat(0.24 + hB * 0.22)
            let y0 = size.height - 1.5
            let y1 = size.height - CGFloat(5.0 + hB * 13.0)
            return (CGPoint(x: x0, y: y0), CGPoint(x: min(size.width - 6, x0 + span), y: y1), 9.0)
        }

        let zone = Int(hA * 4.0) % 4
        switch zone {
        case 0: // Left outer wall surging upward
            let y0 = size.height * CGFloat(0.42 + hB * 0.50)
            let y1 = max(14, y0 - CGFloat(95 + hB * 75))
            return (CGPoint(x: 2.0, y: y0), CGPoint(x: 13.0, y: y1), 15.0)
        case 1: // Right outer wall surging upward
            let y0 = size.height * CGFloat(0.42 + hB * 0.50)
            let y1 = max(14, y0 - CGFloat(95 + hB * 75))
            return (CGPoint(x: size.width - 2.0, y: y0), CGPoint(x: size.width - 13.0, y: y1), 15.0)
        case 2: // Bottom-left / bottom-right corner arc wrap
            let leftCorner = hB < 0.5
            let x0: CGFloat = leftCorner ? 4.0 : (size.width - 4.0)
            let x1: CGFloat = leftCorner ? CGFloat(68 + hB * 85) : (size.width - CGFloat(68 + hB * 85))
            return (CGPoint(x: x0, y: size.height - 32.0), CGPoint(x: x1, y: size.height - 3.0), 13.0)
        default: // Bottom outer curve
            let x0 = size.width * CGFloat(0.10 + hB * 0.52)
            let x1 = min(size.width - 20, x0 + CGFloat(105 + hB * 90))
            return (CGPoint(x: x0, y: size.height - 2.0), CGPoint(x: x1, y: size.height - 11.0), 13.5)
        }
    }

    private func displacedLightningChain(
        from start: CGPoint,
        to end: CGPoint,
        depth: Int,
        displacement: CGFloat,
        seed: Double
    ) -> [CGPoint] {
        var pts = [start, end]
        var disp = displacement
        var iterSeed = seed
        for _ in 0..<depth {
            var next: [CGPoint] = []
            next.reserveCapacity(pts.count * 2 - 1)
            for idx in 0..<(pts.count - 1) {
                let a = pts[idx]
                let b = pts[idx + 1]
                next.append(a)
                let mid = CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
                let dx = b.x - a.x
                let dy = b.y - a.y
                let len = max(1.0, hypot(dx, dy))
                let nx = -dy / len
                let ny = dx / len
                iterSeed += 7.13
                let rand = (fract(sin(iterSeed * 91.7) * 28_341.7) - 0.5) * 2.0
                next.append(CGPoint(x: mid.x + nx * CGFloat(rand) * disp, y: mid.y + ny * CGFloat(rand) * disp))
            }
            if let last = pts.last {
                next.append(last)
            }
            pts = next
            disp *= 0.54
        }
        return pts
    }

    private var staticReducedAura: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [Color.clear, theme.primaryColor.opacity(isPowerSurging ? 0.78 : 0.44)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1.6
            )
    }

    private func fract(_ value: Double) -> Double {
        value - floor(value)
    }
}

// MARK: - Runtime-Compiled Apple Silicon 120Hz Metal Super Saiyan Flame Renderer

private struct SuperSaiyanMetalView: NSViewRepresentable {
    var isCollapsed: Bool
    var isPowerSurging: Bool
    var theme: SuperSaiyanAuraTheme
    var burstNonce: Int
    var cornerRadius: CGFloat

    func makeCoordinator() -> SuperSaiyanMetalRenderer {
        SuperSaiyanMetalRenderer()
    }

    func makeNSView(context: Context) -> MTKView {
        let view = TransparentMTKView(frame: .zero, device: context.coordinator.device)
        view.delegate = context.coordinator
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 120
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        context.coordinator.update(
            isCollapsed: isCollapsed,
            isPowerSurging: isPowerSurging,
            theme: theme,
            burstNonce: burstNonce,
            cornerRadius: cornerRadius
        )
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.update(
            isCollapsed: isCollapsed,
            isPowerSurging: isPowerSurging,
            theme: theme,
            burstNonce: burstNonce,
            cornerRadius: cornerRadius
        )
    }

    static func dismantleNSView(_ nsView: MTKView, coordinator: SuperSaiyanMetalRenderer) {
        nsView.isPaused = true
        nsView.delegate = nil
    }
}

/// Non-interactive transparent `MTKView` so pointer hover/clicks pass straight through to SwiftUI HUD controls.
private final class TransparentMTKView: MTKView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

@MainActor
private final class SuperSaiyanMetalRenderer: NSObject, MTKViewDelegate {
    /// Strictly 16-byte aligned `float4` uniform layout guaranteed identical between Swift & MSL.
    struct Uniforms {
        var outerColor: SIMD4<Float>     // xyz = outerFlameRGB, w = isUltraInstinct (0 or 1)
        var primaryColor: SIMD4<Float>   // xyz = primaryAuraRGB, w = burstAge (-1 if inactive)
        var innerColor: SIMD4<Float>     // xyz = innerFlareRGB, w = surge (0...1 smoothed)
        var coreColor: SIMD4<Float>      // xyz = coreWhiteRGB, w = isCollapsed (0 or 1)
        var lightningColor: SIMD4<Float> // xyz = lightningRGB, w = cornerRadius
        var viewport: SIMD4<Float>       // x = width, y = height, z = time, w = formHueShift
    }

    let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let pipelineState: MTLRenderPipelineState?
    private let startTime: CFTimeInterval = CACurrentMediaTime()

    private var isCollapsed: Bool = false
    private var targetSurge: Float = 0.0
    private var smoothedSurge: Float = 0.0
    private var cornerRadius: Float = 22.0
    private var theme: SuperSaiyanAuraTheme = .superSaiyan

    // Smoothly interpolated RGB vectors so switching Super Saiyan forms morphs like a live transformation!
    private var currentOuter: SIMD3<Float> = SuperSaiyanAuraTheme.superSaiyan.outerFlameRGB
    private var currentPrimary: SIMD3<Float> = SuperSaiyanAuraTheme.superSaiyan.primaryAuraRGB
    private var currentInner: SIMD3<Float> = SuperSaiyanAuraTheme.superSaiyan.innerFlareRGB
    private var currentCore: SIMD3<Float> = SuperSaiyanAuraTheme.superSaiyan.coreWhiteRGB
    private var currentLightning: SIMD3<Float> = SuperSaiyanAuraTheme.superSaiyan.lightningRGB

    private var lastBurstNonce: Int = 0
    private var lastBurstTimestamp: CFTimeInterval = -10.0

    override init() {
        let dev = MTLCreateSystemDefaultDevice()
        self.device = dev
        self.commandQueue = dev?.makeCommandQueue()
        self.pipelineState = dev.flatMap { Self.buildPipeline(device: $0) }
        super.init()
    }

    func update(
        isCollapsed: Bool,
        isPowerSurging: Bool,
        theme: SuperSaiyanAuraTheme,
        burstNonce: Int,
        cornerRadius: CGFloat
    ) {
        self.isCollapsed = isCollapsed
        self.targetSurge = isPowerSurging ? 1.0 : 0.0
        self.theme = theme
        self.cornerRadius = Float(cornerRadius)
        if burstNonce != lastBurstNonce {
            lastBurstNonce = burstNonce
            lastBurstTimestamp = CACurrentMediaTime()
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pipelineState,
              let commandQueue,
              let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor
        else {
            return
        }

        let bounds = view.bounds.size
        guard bounds.width > 2, bounds.height > 2 else { return }

        let now = CACurrentMediaTime()
        let elapsed = Float(now - startTime)

        // Smooth kinetic power-up ramp + real-time color morphing when transforming forms
        smoothedSurge += (targetSurge - smoothedSurge) * 0.085
        let colorLerp: Float = 0.14
        currentOuter += (theme.outerFlameRGB - currentOuter) * colorLerp
        currentPrimary += (theme.primaryAuraRGB - currentPrimary) * colorLerp
        currentInner += (theme.innerFlareRGB - currentInner) * colorLerp
        currentCore += (theme.coreWhiteRGB - currentCore) * colorLerp
        currentLightning += (theme.lightningRGB - currentLightning) * colorLerp

        let rawBurstAge = Float(now - lastBurstTimestamp)
        let burstAge: Float = (rawBurstAge >= 0 && rawBurstAge < 0.85) ? rawBurstAge : -1.0

        let effectiveCorner = isCollapsed ? min(cornerRadius, Float(bounds.height) * 0.5) : cornerRadius
        let isUltraInstinct: Float = theme == .ultraInstinct ? 1.0 : 0.0

        var uniforms = Uniforms(
            outerColor: SIMD4<Float>(currentOuter.x, currentOuter.y, currentOuter.z, isUltraInstinct),
            primaryColor: SIMD4<Float>(currentPrimary.x, currentPrimary.y, currentPrimary.z, burstAge),
            innerColor: SIMD4<Float>(currentInner.x, currentInner.y, currentInner.z, smoothedSurge),
            coreColor: SIMD4<Float>(currentCore.x, currentCore.y, currentCore.z, isCollapsed ? 1.0 : 0.0),
            lightningColor: SIMD4<Float>(currentLightning.x, currentLightning.y, currentLightning.z, effectiveCorner),
            viewport: SIMD4<Float>(Float(bounds.width), Float(bounds.height), elapsed, 1.0)
        )

        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].storeAction = .store

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private static func buildPipeline(device: MTLDevice) -> MTLRenderPipelineState? {
        guard let library = try? device.makeLibrary(source: mslSource, options: nil),
              let vert = library.makeFunction(name: "ssjFullscreenVertex"),
              let frag = library.makeFunction(name: "ssjPowerEruptionFragment")
        else {
            return nil
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vert
        desc.fragmentFunction = frag
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].rgbBlendOperation = .add
        desc.colorAttachments[0].alphaBlendOperation = .add
        desc.colorAttachments[0].sourceRGBBlendFactor = .one
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .one
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        return try? device.makeRenderPipelineState(descriptor: desc)
    }

    /// Next-Gen Apple Silicon MSL Super Saiyan Ki Eruption Shader (DBS: Broly / DBZ Kai Grade):
    /// - Exact 0.0px U-shaped Notch outer rim SDF with continuous rounded bottom corner wrapping.
    /// - 5-octave anisotropic ridged FBM double-domain-warped jagged flame tongues + crisp anime cel-aura contour rim!
    /// - Fast inner incandescent core flame sheet + thermal Ki atmospheric shockwave ripples.
    /// - Dual-scale upward anime hurricane speed-line wind streaks along both flanks.
    /// - Real GPU toroidal shockwave blast when transforming or igniting a Turbo chat turn.
    /// - Ultra Instinct prismatic cosmic iridescence & shimmering stardust mode.
    private static let mslSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float4 outerColor;     // xyz = outerFlameRGB, w = isUltraInstinct
        float4 primaryColor;   // xyz = primaryAuraRGB, w = burstAge (-1 if inactive)
        float4 innerColor;     // xyz = innerFlareRGB, w = surge (0...1)
        float4 coreColor;      // xyz = coreWhiteRGB, w = isCollapsed
        float4 lightningColor; // xyz = lightningRGB, w = cornerRadius
        float4 viewport;       // x = width, y = height, z = time, w = intensityBoost
    };

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut ssjFullscreenVertex(uint vid [[vertex_id]]) {
        float2 pos[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };
        float2 uv[3] = {
            float2(0.0, 1.0),
            float2(2.0, 1.0),
            float2(0.0, -1.0)
        };
        VertexOut out;
        out.position = float4(pos[vid], 0.0, 1.0);
        out.uv = uv[vid];
        return out;
    }

    static inline float ssjHash(float2 p) {
        p = fract(p * float2(127.1, 311.7));
        p += dot(p, p + 34.53);
        return fract(p.x * p.y);
    }

    static inline float ssjNoise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        float2 u = f * f * (3.0 - 2.0 * f);
        float a = ssjHash(i);
        float b = ssjHash(i + float2(1.0, 0.0));
        float c = ssjHash(i + float2(0.0, 1.0));
        float d = ssjHash(i + float2(1.0, 1.0));
        return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
    }

    /// 5-octave sharp ridged turbulence — creates razor-sharp jagged Super Saiyan Ki flame tongues.
    static inline float ssjRidgedFBM(float2 p) {
        float value = 0.0;
        float amp = 0.54;
        float weight = 1.0;
        const float2x2 rot = float2x2(0.82, -0.57, 0.57, 0.82);
        for (int i = 0; i < 5; ++i) {
            float n = ssjNoise(p);
            float ridge = 1.0 - abs(n * 2.0 - 1.0);
            ridge = ridge * ridge * weight;
            weight = clamp(ridge * 1.85, 0.25, 1.0);
            value += amp * ridge;
            p = rot * p * 2.12 + float2(11.3, 17.9);
            amp *= 0.49;
        }
        return value;
    }

    /// Exact inward distance from the Notch U-shaped outer bezel (0.0px flush to left, right & rounded bottom).
    static inline float notchInwardEdgeDist(float2 pos, float2 size, float cornerRadius) {
        float r = min(cornerRadius, min(size.x * 0.5, size.y * 0.96));
        float halfW = size.x * 0.5;
        float px = abs(pos.x - halfW);
        float py = pos.y;

        float dSide = max(0.0, halfW - px);
        float dBottom = max(0.0, size.y - py);

        float2 cornerCenter = float2(halfW - r, size.y - r);
        if (px > cornerCenter.x && py > cornerCenter.y) {
            float distFromCornerCenter = length(float2(px, py) - cornerCenter);
            return max(0.0, r - distFromCornerCenter);
        }
        return min(dSide, dBottom);
    }

    fragment float4 ssjPowerEruptionFragment(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
        float2 size = u.viewport.xy;
        float time = u.viewport.z;
        float2 pos = in.uv * size;
        if (pos.x < 0.0 || pos.y < 0.0 || pos.x > size.x || pos.y > size.y) {
            return float4(0.0);
        }

        float cornerRadius = u.lightningColor.w;
        float surge = clamp(u.innerColor.w, 0.0, 1.0);
        bool collapsed = u.coreColor.w > 0.5;
        float isUI = u.outerColor.w;
        float burstAge = u.primaryColor.w;

        float edgeDist = notchInwardEdgeDist(pos, size, cornerRadius);

        // GPU Power-Up Shockwave Boost (briefly supercharges flame height & blasts an energy ring outward)
        float burstFlash = 0.0;
        float shockRing = 0.0;
        if (burstAge >= 0.0 && burstAge < 0.85) {
            float bn = burstAge / 0.85;
            burstFlash = pow(1.0 - bn, 2.2) * 0.85;

            float2 burstOrigin = collapsed ? float2(24.0, size.y * 0.5) : float2(size.x * 0.5, size.y * 0.92);
            float maxSpan = max(size.x, size.y) * 0.95;
            float ringRadius = (0.04 + pow(bn, 0.58) * 1.15) * maxSpan;
            float distToOrigin = length(pos - burstOrigin);
            float ringThick = collapsed ? 9.0 : 18.0;
            float ringBand = exp(-pow((distToOrigin - ringRadius) / ringThick, 2.0));
            shockRing = ringBand * pow(1.0 - bn, 1.45) * 0.95;
        }

        float effSurge = clamp(surge + burstFlash * 0.65, 0.0, 1.35);

        // Anisotropic upward-roaring Ki flame field (tall sharp licking spikes!)
        float flowSpeed = mix(3.1, 6.2, min(1.0, effSurge));
        float2 flameScale = collapsed ? float2(0.068, 0.026) : float2(0.036, 0.013);
        float2 p = pos * flameScale;
        p.y += time * flowSpeed;

        // Triple-coupled domain warp creates fierce serrated DBS: Broly flame tongues
        float w1 = ssjRidgedFBM(p * 1.05 + float2(0.0, time * 1.6));
        float w2 = ssjRidgedFBM(p * 1.95 + float2((w1 - 0.5) * 2.1, time * 3.1));
        float w3 = ssjNoise(float2(pos.x * (collapsed ? 0.14 : 0.075), pos.y * 0.018 + time * flowSpeed * 1.9));

        float flameSpikes = clamp(mix(w1, w2, 0.62) * 0.85 + w3 * 0.30, 0.0, 1.4);

        // Smooth top fade so flames erupt from the bottom & flanks and lick violently upward
        float topFade = smoothstep(0.0, collapsed ? 4.0 : 22.0, pos.y);
        float bottomWeight = 0.76 + 0.42 * smoothstep(size.y * 0.20, size.y, pos.y);

        // Outer flame envelope reach (hugs the outer perimeter so center content remains 100% readable)
        float outerBase = collapsed ? mix(10.5, 20.5, min(1.0, effSurge)) : mix(18.0, 42.0, min(1.0, effSurge));
        float outerHeight = outerBase * (0.26 + 1.55 * pow(flameSpikes, 1.38)) * bottomWeight * (1.0 + burstFlash * 0.35);

        // Inner hyper-velocity white-hot flame core (moves 1.75x faster!)
        float2 pInner = pos * (flameScale * 1.45) + float2((w2 - 0.5) * 0.9, time * flowSpeed * 1.75);
        float innerTurb = ssjRidgedFBM(pInner);
        float innerHeight = outerHeight * (0.34 + 0.38 * innerTurb);

        // Sharp anime silhouette edges (NOT muddy Gaussian blobs!)
        float outerMask = (1.0 - smoothstep(outerHeight * 0.56, max(2.2, outerHeight), edgeDist)) * topFade;
        float innerMask = (1.0 - smoothstep(innerHeight * 0.25, max(1.4, innerHeight), edgeDist)) * topFade;

        // Signature Dragon Ball Cel-Animated Luminous Aura Contour Outline right on the outer flame boundary!
        float contourWidth = collapsed ? 1.8 : 2.9;
        float contourDist = abs(edgeDist - outerHeight * 0.82);
        float celContour = exp(-pow(contourDist / contourWidth, 2.0))
                         * smoothstep(0.32, 0.82, flameSpikes)
                         * topFade
                         * mix(0.42, 1.05, min(1.0, effSurge));

        // Atmospheric Thermal Heat-Pressure Ripples pulsing inward from the bezel when surging
        float rippleWave = 0.5 + 0.5 * sin(edgeDist * (collapsed ? 0.55 : 0.36) - time * 17.0 + w1 * 5.2);
        float heatRipples = pow(rippleWave, 3.0)
                          * exp(-edgeDist / (collapsed ? 14.0 : 32.0))
                          * topFade
                          * mix(0.10, 0.48, min(1.0, effSurge));

        // Dual-scale vertical Dragon Ball anime hurricane speed-line wind streaks along both walls
        float flankDist = min(pos.x, size.x - pos.x);
        float flankMask = 1.0 - smoothstep(0.0, collapsed ? 26.0 : 58.0, flankDist);
        float fineStreak = ssjNoise(float2(pos.x * (collapsed ? 0.58 : 0.36), pos.y * 0.013 + time * flowSpeed * 2.8));
        float boldStreak = ssjNoise(float2(pos.x * (collapsed ? 0.28 : 0.17) + 4.2, pos.y * 0.009 + time * flowSpeed * 2.1));
        float speedLines = (smoothstep(0.70, 0.94, fineStreak) * 0.72 + smoothstep(0.74, 0.95, boldStreak) * 0.55)
                         * flankMask * topFade * mix(0.28, 0.95, min(1.0, effSurge));

        // Blinding white-hot ionized Ki filament locked 0.0px flush to the outer U-bezel
        float rimPulse = 0.84 + 0.16 * sin(time * 13.5 + pos.x * 0.075 + w1 * 7.0);
        float outerRim = exp(-edgeDist / mix(1.7, 3.3, min(1.0, effSurge))) * topFade * rimPulse;
        float razorCore = exp(-edgeDist / mix(0.75, 1.55, min(1.0, effSurge))) * topFade;

        // Ultra Instinct Cosmic Prismatic Heat-Shimmer & Glittering Silver Stardust
        float uiShimmer = 0.0;
        if (isUI > 0.5) {
            float2 starCell = floor(pos * float2(0.14, 0.14) + float2(0.0, time * 2.6));
            float starRand = ssjHash(starCell);
            float twinkle = 0.5 + 0.5 * sin(time * 9.0 + starRand * 40.0);
            float starDot = step(0.955, starRand) * twinkle * outerMask;
            uiShimmer = starDot * 1.15;
        }

        // Composite total thermal Ki energy
        float energy = clamp(
            outerMask * (0.48 + 0.72 * w2) +
            innerMask * 0.58 +
            celContour * 0.82 +
            outerRim * 1.12 +
            heatRipples * 0.45 +
            speedLines * 0.62 +
            shockRing * 1.15 +
            uiShimmer,
            0.0, 2.4
        );

        // Dynamic 4-stop Super Saiyan Theme Color Ramp (ZERO muddy darkness!)
        float3 cOuter = u.outerColor.xyz;
        float3 cPrimary = u.primaryColor.xyz;
        float3 cInner = u.innerColor.xyz;
        float3 cCore = u.coreColor.xyz;
        float3 cLightning = u.lightningColor.xyz;

        // In Ultra Instinct, shift outer corona slightly toward cosmic indigo-cyan shimmer
        if (isUI > 0.5) {
            float iridescence = 0.5 + 0.5 * sin(pos.x * 0.045 - time * 4.5 + w1 * 4.0);
            cOuter = mix(cOuter, cLightning, iridescence * 0.48);
        }

        float3 col = mix(cOuter, cPrimary, smoothstep(0.10, 0.44, energy));
        col = mix(col, cInner, smoothstep(0.44, 0.88, energy));
        col = mix(col, cCore, clamp(smoothstep(0.86, 1.42, energy) + razorCore * 0.92 + burstFlash * 0.35, 0.0, 1.0));

        // Subtle electric fringe tint along the cel contour & shockwave ring for hyper-authentic SSJ2 / UI energy
        col = mix(col, mix(cInner, cLightning, 0.42), clamp(celContour * 0.40 + shockRing * 0.55, 0.0, 0.65));

        float master = collapsed ? mix(0.80, 1.0, min(1.0, effSurge)) : mix(0.76, 1.0, min(1.0, effSurge));
        float alpha = clamp(
            (outerMask * 0.60 +
             innerMask * 0.38 +
             celContour * 0.62 +
             outerRim * 0.94 +
             razorCore * 0.68 +
             heatRipples * 0.32 +
             speedLines * 0.54 +
             shockRing * 0.72 +
             uiShimmer * 0.85) * master,
            0.0, 1.0
        );

        // Premultiplied alpha output
        return float4(col * alpha, alpha);
    }
    """
}

/// Borderless Super Saiyan kinetic emblem for Turbo mode, dynamically tinted to the selected transformation form.
public struct TurboSolarEmblem: View {
    public var isSurging: Bool
    public var theme: SuperSaiyanAuraTheme
    public var reduceMotion: Bool

    public init(
        isSurging: Bool,
        theme: SuperSaiyanAuraTheme = .superSaiyan,
        reduceMotion: Bool = false
    ) {
        self.isSurging = isSurging
        self.theme = theme
        self.reduceMotion = reduceMotion
    }

    public var body: some View {
        NotchShimmerText(
            text: "TURBO",
            font: .system(size: 9.5, weight: .heavy, design: .rounded),
            tracking: 0.9,
            baseOpacity: 0.76,
            peakOpacity: 1.0,
            period: isSurging ? 1.0 : 1.9,
            turboMode: true,
            turboTheme: theme,
            reduceMotion: reduceMotion
        )
        .shadow(
            color: theme.primaryColor.opacity(isSurging ? 0.68 : 0.30),
            radius: isSurging ? 5.5 : 2.2
        )
        .help("Antigravity Turbo Mode (\(theme.displayName)) — Unrestricted high-velocity execution")
    }
}
