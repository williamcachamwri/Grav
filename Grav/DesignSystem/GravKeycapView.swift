import SwiftUI

/// Physical Mac keycap chip ported 1:1 from Snapzy's `SnapzyKeycapChip`.
public struct GravKeycapChip: View {
    public var label: String
    public var emphasis: Bool = false

    private var height: CGFloat { 19 }

    public init(label: String, emphasis: Bool = false) {
        self.label = label
        self.emphasis = emphasis
    }

    public var body: some View {
        Text(label)
            .font(.system(size: GravOnboardingType.keycap + 1, weight: .semibold, design: .rounded))
            .foregroundStyle(emphasis ? GravGlassInk.primary : GravGlassInk.muted)
            .padding(.horizontal, 5.5)
            .frame(minWidth: height, minHeight: height)
            .background {
                ZStack {
                    Radius.rect(Radius.ornament)
                        .fill(Color.black.opacity(0.24))

                    Radius.rect(Radius.ornament)
                        .fill(Color.white.opacity(emphasis ? 0.20 : 0.08))

                    Radius.rect(Radius.ornament)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(emphasis ? 0.36 : 0.16),
                                    Color.white.opacity(emphasis ? 0.10 : 0.04),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: GravSurfaceGlass.specularLineWidth
                        )
                }
            }
            .fixedSize()
    }
}

/// Multi-keycap row ported 1:1 from Snapzy's `SnapzyKeycapRow`.
public struct GravKeycapRow: View {
    public var keys: [String]
    public var emphasis: Bool = false

    public init(keys: [String], emphasis: Bool = false) {
        self.keys = keys
        self.emphasis = emphasis
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                GravKeycapChip(label: key, emphasis: emphasis)
            }
        }
    }
}
