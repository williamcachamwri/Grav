import SwiftUI

// MARK: - C-Infinity Cubic Bezier Arc Evaluator

/// Smooth cubic Bezier trajectory evaluator shared by the Welcome -> Header logo handoff
/// and the full-screen Grand Completion Finale flight into the MacBook notch.
public struct CubicBezierArc: Sendable, Equatable {
    public let start: CGPoint
    public let control1: CGPoint
    public let control2: CGPoint
    public let end: CGPoint

    public init(start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint) {
        self.start = start
        self.control1 = control1
        self.control2 = control2
        self.end = end
    }

    /// Constructs a naturally lifted aerospace arc between `start` and `end`.
    public static func liftedArc(
        from start: CGPoint,
        to end: CGPoint,
        lift: CGFloat = 110,
        lateralBias: CGFloat = 0.22
    ) -> CubicBezierArc {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let c1 = CGPoint(
            x: start.x + dx * lateralBias,
            y: start.y - lift + dy * 0.12
        )
        let c2 = CGPoint(
            x: end.x - dx * lateralBias * 0.65,
            y: min(start.y, end.y) - lift * 0.55
        )
        return CubicBezierArc(start: start, control1: c1, control2: c2, end: end)
    }

    /// Evaluates the cubic Bezier curve at parameter `t` in `[0, 1]`.
    public func point(at rawT: CGFloat) -> CGPoint {
        let t = max(0, min(1, rawT))
        let inv = 1 - t
        let inv2 = inv * inv
        let inv3 = inv2 * inv
        let t2 = t * t
        let t3 = t2 * t

        let x = inv3 * start.x
            + 3 * inv2 * t * control1.x
            + 3 * inv * t2 * control2.x
            + t3 * end.x

        let y = inv3 * start.y
            + 3 * inv2 * t * control1.y
            + 3 * inv * t2 * control2.y
            + t3 * end.y

        return CGPoint(x: x, y: y)
    }

    /// Quintic smootherstep (`6t^5 - 15t^4 + 10t^3`) with zero velocity and acceleration at endpoints.
    public static func smoothStep(_ rawT: CGFloat) -> CGFloat {
        let t = max(0, min(1, rawT))
        return t * t * t * (t * (t * 6 - 15) + 10)
    }
}

// MARK: - Coordinate Handoff Preference Key

/// Reports the exact center point of the docked `26x26` header icon inside the shared onboarding root space.
struct OnboardingLogoCenterPreferenceKey: PreferenceKey {
    static let defaultValue: CGPoint? = nil

    static func reduce(value: inout CGPoint?, nextValue: () -> CGPoint?) {
        if let next = nextValue() {
            value = next
        }
    }
}

/// Shared coordinate space name used for pixel-exact Welcome -> Shell logo flight handoff.
enum OnboardingCoordinateSpace {
    static let root = "gravOnboardingRoot"
}

// MARK: - Optical Hairline Arrival Ring

/// Crisp `1pt` optical hairline ring emitted on logo docking (single) or notch arrival (dual).
public struct OnboardingOpticalRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var triggerID: Int
    public var baseSize: CGFloat
    public var maxScale: CGFloat
    public var tint: Color
    public var isDual: Bool

    @State private var primaryProgress: CGFloat = 0
    @State private var secondaryProgress: CGFloat = 0
    @State private var isAnimating = false

    public init(
        triggerID: Int,
        baseSize: CGFloat = 26,
        maxScale: CGFloat = 2.6,
        tint: Color = GravPalette.glacialCyan,
        isDual: Bool = false
    ) {
        self.triggerID = triggerID
        self.baseSize = baseSize
        self.maxScale = maxScale
        self.tint = tint
        self.isDual = isDual
    }

    public var body: some View {
        ZStack {
            if isAnimating {
                Circle()
                    .strokeBorder(tint.opacity(max(0, 1 - primaryProgress) * 0.85), lineWidth: 1.0)
                    .frame(width: baseSize, height: baseSize)
                    .scaleEffect(1.0 + (maxScale - 1.0) * primaryProgress)

                if isDual {
                    Circle()
                        .strokeBorder(GravPalette.titaniumWhite.opacity(max(0, 1 - secondaryProgress) * 0.72), lineWidth: 1.0)
                        .frame(width: baseSize, height: baseSize)
                        .scaleEffect(1.0 + (maxScale * 1.28 - 1.0) * secondaryProgress)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: triggerID) { _, newValue in
            guard newValue > 0 else { return }
            fireRing()
        }
        .onAppear {
            if triggerID > 0 {
                fireRing()
            }
        }
    }

    private func fireRing() {
        primaryProgress = 0
        secondaryProgress = 0
        isAnimating = true

        let duration = reduceMotion ? 0.24 : 0.62
        withAnimation(.easeOut(duration: duration)) {
            primaryProgress = 1
        }
        if isDual {
            let delay = reduceMotion ? 0.04 : 0.11
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                withAnimation(.easeOut(duration: duration * 1.12)) {
                    secondaryProgress = 1
                }
            }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration + (isDual ? 0.28 : 0.08)))
            isAnimating = false
        }
    }
}

// MARK: - Dark Liquid Glass Surface Primitives

/// Calm 3-step Dark Liquid Glass surface fill levels.
public enum OnboardingGlassElevation: Sendable {
    case subtle
    case base
    case elevated

    var fillColor: Color {
        switch self {
        case .subtle: return GravPalette.cardFillSubtle
        case .base: return GravPalette.cardFillBase
        case .elevated: return GravPalette.cardFillElevated
        }
    }
}

/// Dark Liquid Glass card with continuous corner geometry and a `0.5pt` top-lit specular border.
public struct OnboardingSpecularCard<Content: View>: View {
    public var elevation: OnboardingGlassElevation
    public var cornerRadius: CGFloat
    public var isHighlighted: Bool
    public var padding: CGFloat
    @ViewBuilder public var content: () -> Content

    public init(
        elevation: OnboardingGlassElevation = .base,
        cornerRadius: CGFloat = GravRadius.card,
        isHighlighted: Bool = false,
        padding: CGFloat = 14,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.elevation = elevation
        self.cornerRadius = cornerRadius
        self.isHighlighted = isHighlighted
        self.padding = padding
        self.content = content
    }

    public var body: some View {
        content()
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle.grav(cornerRadius)
                        .fill(isHighlighted ? GravPalette.cardFillElevated : elevation.fillColor)

                    if isHighlighted {
                        RoundedRectangle.grav(cornerRadius)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        GravPalette.glacialTeal.opacity(0.14),
                                        GravPalette.glacialCyan.opacity(0.05),
                                        Color.clear,
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
            )
            .overlay(
                RoundedRectangle.grav(cornerRadius)
                    .strokeBorder(
                        isHighlighted
                            ? LinearGradient(
                                stops: [
                                    .init(color: GravPalette.glacialCyan.opacity(0.55), location: 0.0),
                                    .init(color: GravPalette.glacialTeal.opacity(0.26), location: 0.5),
                                    .init(color: Color.white.opacity(0.08), location: 1.0),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            : GravPalette.specularStroke,
                        lineWidth: 0.5
                    )
            )
    }
}

/// Hardware-styled keyboard hint badge (`ESC`, `↩`) rendered in Dark Liquid Glass.
public struct OnboardingKeycapBadge: View {
    public var label: String

    public init(_ label: String) {
        self.label = label
    }

    public var body: some View {
        Text(label)
            .font(GravTypography.monoMicro)
            .foregroundStyle(GravPalette.inkSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle.grav(GravRadius.controlXS)
                    .fill(GravPalette.cardFillBase)
            )
            .overlay(
                RoundedRectangle.grav(GravRadius.controlXS)
                    .strokeBorder(GravPalette.specularStroke, lineWidth: 0.5)
            )
    }
}

/// Right-column cropped macOS desktop mock stage (`GravRadius.panel` = 20pt)
/// with a 3-stop top-lit specular rim and restrained glacial aerospace obsidian wallpaper.
public struct OnboardingStageFrame<Content: View>: View {
    public var showMenuBar: Bool
    @ViewBuilder public var content: () -> Content

    public init(
        showMenuBar: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.showMenuBar = showMenuBar
        self.content = content
    }

    public var body: some View {
        ZStack(alignment: .top) {
            // Cropped dark macOS desktop aerospace substrate
            RoundedRectangle.grav(GravRadius.panel)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(red: 0x07 / 255.0, green: 0x10 / 255.0, blue: 0x18 / 255.0), location: 0.0),
                            .init(color: Color(red: 0x06 / 255.0, green: 0x0C / 255.0, blue: 0x12 / 255.0), location: 0.55),
                            .init(color: GravPalette.obsidianVoid, location: 1.0),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Subtle glacial atmospheric horizon sheen (zero neon/AI-slop)
            RadialGradient(
                stops: [
                    .init(color: GravPalette.glacialTeal.opacity(0.16), location: 0.0),
                    .init(color: GravPalette.glacialCyan.opacity(0.07), location: 0.45),
                    .init(color: Color.clear, location: 1.0),
                ],
                center: UnitPoint(x: 0.72, y: 0.14),
                startRadius: 10,
                endRadius: 360
            )
            .allowsHitTesting(false)

            // Precision faint aerospace coordinate grid
            StageGridOverlay()
                .allowsHitTesting(false)

            // Optional cropped macOS menu bar strip
            if showMenuBar {
                HStack(spacing: 12) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(GravPalette.inkTertiary)
                    Text("Antigravity")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(GravPalette.inkSecondary)
                    Text("Workspace")
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(GravPalette.inkQuaternary)
                    Spacer()
                    HStack(spacing: 8) {
                        GravOrbitalMark(size: 11, tint: GravPalette.inkSecondary)
                        Image(systemName: "wifi")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(GravPalette.inkTertiary)
                        Text("9:41")
                            .font(GravTypography.monoMicro)
                            .foregroundStyle(GravPalette.inkTertiary)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 26)
                .background(Color.black.opacity(0.32))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 0.5)
                }
            }

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipShape(RoundedRectangle.grav(GravRadius.panel))
        .overlay(
            // 3-stop top-lit specular rim
            RoundedRectangle.grav(GravRadius.panel)
                .strokeBorder(GravPalette.specularStroke, lineWidth: 0.5)
        )
    }
}

private struct StageGridOverlay: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 32
            var path = Path()
            var x: CGFloat = step
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = step
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(path, with: .color(Color.white.opacity(0.024)), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Editorial Magnetic Pill Button

/// Editorial magnetic arrow pill CTA used at Beat 7 of the Welcome choreography.
public struct OnboardingMagneticPillButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var title: String
    public var action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false
    @State private var magneticOffset: CGSize = .zero

    public init(title: String = "Get Started", action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(GravPalette.obsidianVoid)

                Image(systemName: "arrow.right")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(GravPalette.obsidianVoid)
                    .offset(x: isHovered && !reduceMotion ? 3 : 0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                GravPalette.titaniumWhite,
                                Color(red: 0xE6 / 255.0, green: 0xF5 / 255.0, blue: 0xF8 / 255.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 0.5)
            )
            .shadow(color: GravPalette.obsidianVoid.opacity(isHovered ? 0.42 : 0.28), radius: isHovered ? 20 : 12, y: isHovered ? 8 : 5)
            .scaleEffect(isPressed ? 0.965 : (isHovered ? 1.025 : 1.0))
            .offset(reduceMotion ? .zero : magneticOffset)
        }
        .buttonStyle(.plain)
        .onContinuousHover { phase in
            switch phase {
            case let .active(location):
                if !isHovered {
                    withAnimation(GravMotion.rowHover) {
                        isHovered = true
                    }
                }
                guard !reduceMotion else { return }
                // Subtle magnetic attraction capped within +/- 5pt
                let clampedX = max(-5, min(5, (location.x - 76) * 0.08))
                let clampedY = max(-3.5, min(3.5, (location.y - 21) * 0.12))
                withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.78)) {
                    magneticOffset = CGSize(width: clampedX, height: clampedY)
                }
            case .ended:
                withAnimation(GravMotion.railSpring) {
                    isHovered = false
                    magneticOffset = .zero
                }
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        withAnimation(.easeOut(duration: 0.1)) { isPressed = true }
                    }
                }
                .onEnded { _ in
                    withAnimation(GravMotion.railSpring) { isPressed = false }
                }
        )
        .accessibilityLabel(title)
        .accessibilityHint("Proceed to Antigravity connection setup")
    }
}
