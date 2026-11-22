import AppKit
import Metal
import MetalKit
import SwiftUI

/// 120Hz Apple Silicon GPU Super Saiyan Power-Eruption Engine rendered strictly while
/// Antigravity is running in Turbo Mode (`AGENT_PERMISSION_PRESET_TURBO`).
///
/// Combines:
/// 1. Full-bleed runtime-compiled Apple Silicon Metal fragment shader (`SuperSaiyanMetalView`):
///    4-octave ridged FBM double-domain-warped roaring golden-white Ki flames + upward anime
///    speed-line wind streaks locked 0.0px to the exact outer Notch U-bezel.
/// 2. True recursive midpoint-displaced forked Super Saiyan 2 electric cyan-blue & white lightning arcs.
/// 3. Sharp upward-lancing diamond Ki shards erupting from the golden flame tips.
/// 4. Radial ignition shockwave burst on Turbo activation / power surge.
public struct TurboKineticAuraCanvas: View {
    public enum SurfaceStyle {
        case collapsed
        case expanded
    }

    public var style: SurfaceStyle
    public var isPowerSurging: Bool
    public var cornerRadius: CGFloat
    public var reduceMotion: Bool

    @State private var ignitionBurstProgress: CGFloat = 0
    @State private var showIgnitionBurst: Bool = false

    public init(
        style: SurfaceStyle,
        isPowerSurging: Bool,
        cornerRadius: CGFloat? = nil,
        reduceMotion: Bool = false
    ) {
        self.style = style
        self.isPowerSurging = isPowerSurging
        self.cornerRadius = cornerRadius ?? (style == .collapsed ? 16 : 22)
        self.reduceMotion = reduceMotion
    }

    private static let ssjGold = Color(red: 1.00, green: 0.90, blue: 0.18)
    private static let ssjWhiteHot = Color(red: 1.00, green: 0.995, blue: 0.92)
    private static let ssj2ElectricBlue = Color(red: 0.24, green: 0.86, blue: 1.00)

    public var body: some View {
        ZStack {
            if reduceMotion {
                staticReducedAura
            } else {
                // Layer 1: 120 FPS Native Metal GPU Fragment Shader — Roaring Super Saiyan Golden Ki Flames
                SuperSaiyanMetalView(
                    isCollapsed: style == .collapsed,
                    isPowerSurging: isPowerSurging,
                    cornerRadius: cornerRadius
                )

                // Layer 2: True Forked SSJ2 Electric Blue-White Lightning Bolts + Sharp Upward Ki Shards
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { ctx, size in
                        guard size.width > 4, size.height > 4 else { return }
                        drawSharpKiLances(in: &ctx, size: size, time: t)
                        drawSuperSaiyan2Lightning(in: &ctx, size: size, time: t)
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

    // MARK: - Sharp Upward-Lancing Golden Ki Shards (Zero Blurry Blobs)

    private func drawSharpKiLances(in ctx: inout GraphicsContext, size: CGSize, time t: TimeInterval) {
        let count = (style == .collapsed)
            ? (isPowerSurging ? 16 : 8)
            : (isPowerSurging ? 30 : 14)
        let speedMult = isPowerSurging ? 1.55 : 0.82

        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter

            for i in 0..<count {
                let h1 = fract(sin(Double(i + 1) * 12.9898) * 43_758.5453)
                let h2 = fract(sin(Double(i + 1) * 78.233) * 29_183.1234)
                let h3 = fract(sin(Double(i + 1) * 45.164) * 19_482.7711)

                let duration = (style == .collapsed ? 0.72 : 1.28) + h2 * 0.85
                let prog = fract((t * speedMult) / duration + h1)

                // Hug the exact outer left/right bezels & bottom rim so center text stays 100% razor-clean
                let x: CGFloat
                if style == .expanded {
                    let edgeSide = h3 < 0.5
                    let inset = CGFloat(2.0 + fract(h3 * 7.3) * (isPowerSurging ? 22.0 : 13.0))
                    x = edgeSide ? inset : (size.width - inset)
                } else {
                    x = size.width * CGFloat(0.05 + h3 * 0.90)
                }

                let riseSpan = (style == .collapsed) ? size.height * 0.95 : size.height * 0.84
                let y = size.height - CGFloat(prog) * riseSpan

                let alpha = sin(prog * .pi) * pow(1.0 - prog, 0.42) * (isPowerSurging ? 0.98 : 0.65)
                guard alpha > 0.04 else { continue }

                let halfW: CGFloat = style == .collapsed ? 0.8 : 1.05
                let halfH: CGFloat = CGFloat((style == .collapsed ? 5.0 : 9.0) + h2 * 7.5) * (isPowerSurging ? 1.35 : 0.85)

                var shard = Path()
                shard.move(to: CGPoint(x: x, y: y - halfH))
                shard.addLine(to: CGPoint(x: x + halfW, y: y))
                shard.addLine(to: CGPoint(x: x, y: y + halfH * 0.5))
                shard.addLine(to: CGPoint(x: x - halfW, y: y))
                shard.closeSubpath()

                let tint = (i % 3 == 0) ? Self.ssjWhiteHot : Self.ssjGold
                layer.fill(shard, with: .color(tint.opacity(alpha)))
            }
        }
    }

    // MARK: - True Forked Super Saiyan 2 Electric Blue-White Bio-Electricity

    private func drawSuperSaiyan2Lightning(in ctx: inout GraphicsContext, size: CGSize, time t: TimeInterval) {
        let channelCount = isPowerSurging ? 3 : 1
        for channel in 0..<channelCount {
            let cycle = isPowerSurging
                ? (channel == 0 ? 0.78 : (channel == 1 ? 1.19 : 1.63))
                : 2.35
            let offset = Double(channel) * 0.41
            let shifted = t + offset
            let slot = floor(shifted / cycle)
            let localT = shifted - slot * cycle
            let boltLife = isPowerSurging ? 0.18 : 0.14
            guard localT < boltLife else { continue }

            let norm = localT / boltLife
            let flicker = sin(norm * .pi) * (0.72 + 0.28 * sin(norm * .pi * 5.0))
            guard flicker > 0.08 else { continue }

            let seed = slot * 31.7 + Double(channel) * 97.3
            let (start, end, displacement) = lightningEndpoints(for: size, seed: seed)

            var mainBolt = Path()
            var branchBolt = Path()
            let points = displacedLightningChain(from: start, to: end, depth: 3, displacement: displacement, seed: seed)
            if let first = points.first {
                mainBolt.move(to: first)
                for pt in points.dropFirst() {
                    mainBolt.addLine(to: pt)
                }
            }

            if points.count >= 5 {
                let forkIdx = points.count / 2
                let forkOrigin = points[forkIdx]
                let dirX = (end.x - start.x) * 0.38
                let dirY = (end.y - start.y) * 0.38
                let perpSign: CGFloat = fract(sin(seed * 17.3) * 4123.1) > 0.5 ? 1.0 : -1.0
                let forkEnd = CGPoint(
                    x: forkOrigin.x + dirX - dirY * 0.55 * perpSign,
                    y: forkOrigin.y + dirY + dirX * 0.55 * perpSign
                )
                let branchPts = displacedLightningChain(
                    from: forkOrigin,
                    to: forkEnd,
                    depth: 2,
                    displacement: displacement * 0.55,
                    seed: seed + 51.9
                )
                if let bf = branchPts.first {
                    branchBolt.move(to: bf)
                    for pt in branchPts.dropFirst() {
                        branchBolt.addLine(to: pt)
                    }
                }
            }

            ctx.drawLayer { layer in
                layer.blendMode = .plusLighter

                layer.stroke(
                    mainBolt,
                    with: .color(Self.ssj2ElectricBlue.opacity(0.72 * flicker)),
                    style: StrokeStyle(lineWidth: style == .collapsed ? 3.2 : 4.2, lineCap: .round, lineJoin: .round)
                )
                layer.stroke(
                    branchBolt,
                    with: .color(Self.ssj2ElectricBlue.opacity(0.54 * flicker)),
                    style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                )
                layer.stroke(
                    mainBolt,
                    with: .color(Color.white.opacity(1.0 * flicker)),
                    style: StrokeStyle(lineWidth: style == .collapsed ? 1.0 : 1.2, lineCap: .round, lineJoin: .round)
                )
                layer.stroke(
                    branchBolt,
                    with: .color(Color.white.opacity(0.90 * flicker)),
                    style: StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    private func lightningEndpoints(for size: CGSize, seed: Double) -> (CGPoint, CGPoint, CGFloat) {
        let hA = fract(sin(seed * 12.7) * 43_123.9)
        let hB = fract(sin(seed * 67.3) * 19_481.2)

        if style == .collapsed {
            let x0 = size.width * CGFloat(0.08 + hA * 0.56)
            let span = size.width * CGFloat(0.24 + hB * 0.16)
            let y0 = size.height - 2.0
            let y1 = size.height - CGFloat(4.5 + hB * 11.0)
            return (CGPoint(x: x0, y: y0), CGPoint(x: min(size.width - 8, x0 + span), y: y1), 8.0)
        }

        let zone = Int(hA * 3.0) % 3
        switch zone {
        case 0: // Left outer wall
            let y0 = size.height * CGFloat(0.45 + hB * 0.46)
            let y1 = max(20, y0 - CGFloat(85 + hB * 60))
            return (CGPoint(x: 2.5, y: y0), CGPoint(x: 11.0, y: y1), 13.0)
        case 1: // Right outer wall
            let y0 = size.height * CGFloat(0.45 + hB * 0.46)
            let y1 = max(20, y0 - CGFloat(85 + hB * 60))
            return (CGPoint(x: size.width - 2.5, y: y0), CGPoint(x: size.width - 11.0, y: y1), 13.0)
        default: // Bottom outer curve
            let x0 = size.width * CGFloat(0.10 + hB * 0.56)
            let x1 = min(size.width - 24, x0 + CGFloat(95 + hB * 80))
            return (CGPoint(x: x0, y: size.height - 2.5), CGPoint(x: x1, y: size.height - 9.0), 12.0)
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

    // MARK: - Radial Super Saiyan Ignition Shockwave

    private var ignitionShockwaveLayer: some View {
        GeometryReader { geo in
            let maxDim = max(geo.size.width, geo.size.height)
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [Self.ssjWhiteHot, Self.ssjGold, Self.ssj2ElectricBlue.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(0.9, 3.4 * (1.0 - ignitionBurstProgress))
                )
                .frame(width: maxDim * 0.22, height: maxDim * 0.22)
                .scaleEffect(0.35 + ignitionBurstProgress * 4.8)
                .opacity(Double(max(0, 1.0 - ignitionBurstProgress)) * 0.82)
                .position(
                    x: style == .collapsed ? 24 : geo.size.width * 0.5,
                    y: style == .collapsed ? geo.size.height * 0.5 : geo.size.height * 0.85
                )
                .blendMode(.plusLighter)
        }
    }

    private func triggerIgnitionShockwave() {
        guard !reduceMotion else { return }
        showIgnitionBurst = true
        ignitionBurstProgress = 0
        withAnimation(.timingCurve(0.14, 1.0, 0.28, 1.0, duration: 0.52)) {
            ignitionBurstProgress = 1.0
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 550_000_000)
            showIgnitionBurst = false
        }
    }

    private var staticReducedAura: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [Color.clear, Self.ssjGold.opacity(isPowerSurging ? 0.72 : 0.40)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1.5
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
            cornerRadius: cornerRadius
        )
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.update(
            isCollapsed: isCollapsed,
            isPowerSurging: isPowerSurging,
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
    struct Uniforms {
        var size: SIMD2<Float>
        var time: Float
        var cornerRadius: Float
        var surge: Float
        var isCollapsed: Float
    }

    let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let pipelineState: MTLRenderPipelineState?
    private let startTime: CFTimeInterval = CACurrentMediaTime()

    private var isCollapsed: Bool = false
    private var targetSurge: Float = 0.0
    private var smoothedSurge: Float = 0.0
    private var cornerRadius: Float = 22.0

    override init() {
        let dev = MTLCreateSystemDefaultDevice()
        self.device = dev
        self.commandQueue = dev?.makeCommandQueue()
        self.pipelineState = dev.flatMap { Self.buildPipeline(device: $0) }
        super.init()
    }

    func update(isCollapsed: Bool, isPowerSurging: Bool, cornerRadius: CGFloat) {
        self.isCollapsed = isCollapsed
        self.targetSurge = isPowerSurging ? 1.0 : 0.0
        self.cornerRadius = Float(cornerRadius)
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

        // Smooth kinetic power-up ramp between standby and full Super Saiyan surge
        smoothedSurge += (targetSurge - smoothedSurge) * 0.08

        let elapsed = Float(CACurrentMediaTime() - startTime)
        let effectiveCorner = isCollapsed ? min(cornerRadius, Float(bounds.height) * 0.5) : cornerRadius
        var uniforms = Uniforms(
            size: SIMD2<Float>(Float(bounds.width), Float(bounds.height)),
            time: elapsed,
            cornerRadius: effectiveCorner,
            surge: smoothedSurge,
            isCollapsed: isCollapsed ? 1.0 : 0.0
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

    /// Apple Silicon MSL Super Saiyan Ki Power-Eruption Shader:
    /// - Exact U-shaped Notch outer rim SDF (0.0px flush to bezel, rounded bottom corners).
    /// - 4-octave ridged FBM double-domain-warped golden Ki flame tongues roaring upward.
    /// - High-luminance Super Saiyan electric lemon-gold -> incandescent white-hot ramp (ZERO brown mud).
    /// - Vertical anime power-up speed lines racing up both flanks.
    private static let mslSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float2 size;
        float time;
        float cornerRadius;
        float surge;
        float isCollapsed;
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
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
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

    static inline float ssjRidgedFBM(float2 p) {
        float value = 0.0;
        float amp = 0.55;
        const float2x2 rot = float2x2(0.80, -0.60, 0.60, 0.80);
        for (int i = 0; i < 4; ++i) {
            float n = ssjNoise(p);
            float ridge = 1.0 - abs(n * 2.0 - 1.0);
            value += amp * ridge * ridge;
            p = rot * p * 2.08 + float2(13.7, 7.3);
            amp *= 0.50;
        }
        return value;
    }

    static inline float notchInwardEdgeDist(float2 pos, float2 size, float cornerRadius) {
        float r = min(cornerRadius, min(size.x * 0.5, size.y * 0.95));
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
        float2 pos = in.uv * u.size;
        if (pos.x < 0.0 || pos.y < 0.0 || pos.x > u.size.x || pos.y > u.size.y) {
            return float4(0.0);
        }

        float edgeDist = notchInwardEdgeDist(pos, u.size, u.cornerRadius);
        float surge = clamp(u.surge, 0.0, 1.0);
        bool collapsed = u.isCollapsed > 0.5;

        // Violently upward-roaring vertically stretched Ki flame coordinates
        float flowSpeed = mix(2.5, 4.8, surge);
        float2 flameScale = collapsed ? float2(0.058, 0.032) : float2(0.030, 0.015);
        float2 p = pos * flameScale;
        p.y += u.time * flowSpeed;

        // Double domain warp produces fierce licking Super Saiyan flame sheets & jagged tips
        float warp1 = ssjRidgedFBM(p * 1.15 + float2(0.0, u.time * 1.8));
        float warp2 = ssjRidgedFBM(p * 1.90 + float2(warp1 * 1.65, u.time * 2.6));
        float flameTurb = mix(warp1, warp2, 0.65);

        float topFade = smoothstep(0.0, collapsed ? 4.5 : 26.0, pos.y);
        float bottomBoost = 0.72 + 0.38 * smoothstep(u.size.y * 0.25, u.size.y, pos.y);

        // Inward flame reach from the exact outer bezel wall
        float baseReach = collapsed ? mix(9.0, 17.5, surge) : mix(15.0, 34.0, surge);
        float flameHeight = baseReach * (0.30 + 1.48 * pow(flameTurb, 1.32)) * bottomBoost;

        // High-contrast anime flame silhouette (sharp licking outer tongue, never muddy blur!)
        float flameBody = 1.0 - smoothstep(flameHeight * 0.34, max(2.0, flameHeight), edgeDist);
        float flameInnerCore = 1.0 - smoothstep(flameHeight * 0.12, max(1.2, flameHeight * 0.52), edgeDist);
        flameBody *= topFade;
        flameInnerCore *= topFade;

        // Iconic Dragon Ball vertical speed-line wind streaks shooting upward along both outer walls
        float flankDist = min(pos.x, u.size.x - pos.x);
        float flankMask = 1.0 - smoothstep(0.0, collapsed ? 22.0 : 48.0, flankDist);
        float streakVal = ssjNoise(float2(pos.x * (collapsed ? 0.45 : 0.30), pos.y * 0.016 + u.time * flowSpeed * 2.5));
        float speedLines = smoothstep(0.68, 0.94, streakVal) * flankMask * topFade * mix(0.28, 0.90, surge);

        // Blinding incandescent Ki rim locked 0.0px to the outer U-bezel of the Notch
        float rimWave = 0.85 + 0.15 * sin(u.time * 11.0 + pos.x * 0.06 + warp1 * 6.5);
        float outerRim = exp(-edgeDist / mix(1.6, 2.8, surge)) * topFade * rimWave;
        float razorCore = exp(-edgeDist / mix(0.75, 1.35, surge)) * topFade;

        float energy = clamp(
            flameBody * (0.52 + 0.68 * warp2) +
            flameInnerCore * 0.45 +
            outerRim * 1.05 +
            speedLines * 0.58,
            0.0, 2.0
        );

        // Pure High-Luminance Super Saiyan Color Ramp (ZERO muddy brown!)
        float3 solarGold  = float3(1.00, 0.66, 0.04); // Blazing golden flame tips
        float3 ssjYellow  = float3(1.00, 0.89, 0.14); // Iconic Super Saiyan electric gold
        float3 ssjLemon   = float3(1.00, 0.97, 0.52); // High-voltage electric lemon
        float3 whiteHot   = float3(1.00, 1.00, 0.95); // Blinding white-hot Ki core

        float3 col = mix(solarGold, ssjYellow, smoothstep(0.12, 0.45, energy));
        col = mix(col, ssjLemon, smoothstep(0.45, 0.85, energy));
        col = mix(col, whiteHot, clamp(smoothstep(0.82, 1.35, energy) + razorCore * 0.90, 0.0, 1.0));

        float master = collapsed ? mix(0.76, 1.0, surge) : mix(0.72, 1.0, surge);
        float alpha = clamp(
            (flameBody * 0.58 + flameInnerCore * 0.35 + outerRim * 0.92 + razorCore * 0.62 + speedLines * 0.52) * master,
            0.0, 1.0
        );

        // Premultiplied alpha output
        return float4(col * alpha, alpha);
    }
    """
}

/// Borderless Super Saiyan solar-gold kinetic emblem for Turbo mode.
public struct TurboSolarEmblem: View {
    public var isSurging: Bool
    public var reduceMotion: Bool

    public init(isSurging: Bool, reduceMotion: Bool = false) {
        self.isSurging = isSurging
        self.reduceMotion = reduceMotion
    }

    public var body: some View {
        NotchShimmerText(
            text: "TURBO",
            font: .system(size: 9.5, weight: .heavy, design: .rounded),
            tracking: 0.9,
            baseOpacity: 0.72,
            peakOpacity: 1.0,
            period: isSurging ? 1.05 : 2.0,
            turboMode: true,
            reduceMotion: reduceMotion
        )
        .shadow(
            color: Color(red: 1.0, green: 0.88, blue: 0.18).opacity(isSurging ? 0.60 : 0.28),
            radius: isSurging ? 5 : 2
        )
        .help("Antigravity Turbo Mode — Unrestricted high-velocity execution")
    }
}
