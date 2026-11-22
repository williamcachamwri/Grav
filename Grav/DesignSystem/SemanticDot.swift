import SwiftUI

/// Semantic status tone for Grav's 6pt flight-telemetry indicators.
public enum SemanticDotTone: Sendable, Equatable {
    case thinking
    case fileEdit
    case success
    case error
    case running
    case idle
    case custom(Color)

    public init(telemetryState: TelemetryState) {
        switch telemetryState {
        case .idle:
            self = .idle
        case .working:
            self = .custom(Color.white.opacity(0.84))
        case .compacting:
            self = .custom(GravPalette.prismViolet)
        case .thinking, .inspecting:
            self = .thinking
        case let .editing(event):
            self = event.kind == .delete ? .error : .fileEdit
        case .runningCommand:
            self = .running
        }
    }

    public func resolvedColor(in palette: GravAdaptivePalette) -> Color {
        switch self {
        case .thinking:
            return GravPalette.thinking
        case .fileEdit:
            return palette.isDark ? GravPalette.fileEdit : palette.fileEditText
        case .success:
            return palette.isDark ? GravPalette.emerald : palette.emeraldText
        case .error:
            return palette.isDark ? GravPalette.coral : palette.coralText
        case .running:
            return palette.isDark ? GravPalette.commandRunning : palette.accentTeal
        case .idle:
            return palette.idleDot
        case let .custom(color):
            return color
        }
    }
}

/// Crisp `6pt` semantic telemetry indicator dot with an optional subtle optical
/// hairline pulse ring that mounts only while `isActive && !reduceMotion` (zero idle CPU).
public struct SemanticDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    public var tone: SemanticDotTone
    public var size: CGFloat
    public var isActive: Bool
    public var showPulse: Bool
    public var adaptive: Bool

    public init(
        tone: SemanticDotTone,
        size: CGFloat = 6,
        isActive: Bool = false,
        showPulse: Bool = true,
        adaptive: Bool = true
    ) {
        self.tone = tone
        self.size = size
        self.isActive = isActive
        self.showPulse = showPulse
        self.adaptive = adaptive
    }

    public init(
        color: Color,
        size: CGFloat = 6,
        isActive: Bool = false,
        showPulse: Bool = true
    ) {
        self.tone = .custom(color)
        self.size = size
        self.isActive = isActive
        self.showPulse = showPulse
        self.adaptive = false
    }

    public init(
        state: TelemetryState,
        size: CGFloat = 6,
        showPulse: Bool = true,
        adaptive: Bool = true
    ) {
        self.tone = SemanticDotTone(telemetryState: state)
        self.size = size
        self.isActive = state.isActive
        self.showPulse = showPulse
        self.adaptive = adaptive
    }

    public var body: some View {
        let palette = GravAdaptivePalette(colorScheme: adaptive ? colorScheme : .dark)
        let dotColor = tone.resolvedColor(in: palette)

        ZStack {
            if isActive && showPulse && !reduceMotion {
                OpticalPulseRing(color: dotColor, diameter: size)
            }

            Circle()
                .fill(dotColor)
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Self-tearing optical hairline ring that only exists in the hierarchy while active.
private struct OpticalPulseRing: View {
    let color: Color
    let diameter: CGFloat

    @State private var isExpanded = false

    var body: some View {
        Circle()
            .stroke(color.opacity(isExpanded ? 0.0 : 0.52), lineWidth: 1)
            .frame(width: diameter, height: diameter)
            .scaleEffect(isExpanded ? 2.2 : 1.0)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(
                    .easeOut(duration: 1.6)
                        .repeatForever(autoreverses: false)
                ) {
                    isExpanded = true
                }
            }
            .onDisappear {
                isExpanded = false
            }
    }
}
