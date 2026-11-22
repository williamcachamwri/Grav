import SwiftUI

/// The three real telemetry modes surfaced by Grav inside the MacBook notch HUD.
public enum NotchPreviewMode: String, CaseIterable, Identifiable, Sendable {
    case thinking
    case fileEdits
    case commandLogs

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .thinking:
            return "Thinking"
        case .fileEdits:
            return "File Edits & Deletes"
        case .commandLogs:
            return "Live Command Logs"
        }
    }

    public var description: String {
        switch self {
        case .thinking:
            return "Real-time reasoning stream, active model indicator, and elapsed step duration."
        case .fileEdits:
            return "Instant file create, edit, and delete alerts with compact +added / -removed line diffs."
        case .commandLogs:
            return "Live shell execution status, exit codes, and streaming monospaced stdout tail."
        }
    }

    public var symbolName: String {
        switch self {
        case .thinking:
            return "waveform.path.ecg"
        case .fileEdits:
            return "doc.badge.plus"
        case .commandLogs:
            return "terminal"
        }
    }

    public var accentColor: Color {
        switch self {
        case .thinking:
            return GravPalette.thinking
        case .fileEdits:
            return GravPalette.fileEdit
        case .commandLogs:
            return GravPalette.glacialCyan
        }
    }

    public var collapsedBadgeText: String {
        switch self {
        case .thinking:
            return "Thinking · 4.2s"
        case .fileEdits:
            return "2 files · +18 -4"
        case .commandLogs:
            return "swift test · 0"
        }
    }
}

/// Step 2 left-rail content: interactive selector rows for the 3 Notch HUD telemetry modes.
public struct OnboardingStepNotchPreviewRail: View {
    @Binding public var selectedMode: NotchPreviewMode
    @Binding public var isPreviewPinnedExpanded: Bool

    public init(
        selectedMode: Binding<NotchPreviewMode>,
        isPreviewPinnedExpanded: Binding<Bool>
    ) {
        self._selectedMode = selectedMode
        self._isPreviewPinnedExpanded = isPreviewPinnedExpanded
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(NotchPreviewMode.allCases) { mode in
                NotchModeSelectorRow(
                    mode: mode,
                    isSelected: selectedMode == mode
                ) {
                    withAnimation(GravMotion.railSpring) {
                        selectedMode = mode
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "cursorarrow.motionlines")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GravPalette.glacialTeal)

                Text("Hover the MacBook notch on the right to feel single-shape morphing.")
                    .font(GravTypography.caption)
                    .foregroundStyle(GravPalette.inkTertiary)

                Spacer(minLength: 4)

                Button {
                    withAnimation(GravMotion.railSpring) {
                        isPreviewPinnedExpanded.toggle()
                    }
                } label: {
                    Text(isPreviewPinnedExpanded ? "Collapse" : "Pin Open")
                        .font(GravTypography.micro)
                        .foregroundStyle(isPreviewPinnedExpanded ? GravPalette.glacialCyan : GravPalette.inkSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(GravPalette.cardFillBase)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(GravPalette.specularStroke, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)
        }
    }
}

/// Step 2 right-stage mock: miniature MacBook display bezel with a real hover-to-morph
/// hardware notch housing demonstrating Thinking, File Edits & Deletes, and Live Command Logs.
public struct OnboardingStepNotchPreviewStage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var selectedMode: NotchPreviewMode
    @Binding public var isPinnedExpanded: Bool

    @State private var isHovered = false

    public init(
        selectedMode: NotchPreviewMode,
        isPinnedExpanded: Binding<Bool>
    ) {
        self.selectedMode = selectedMode
        self._isPinnedExpanded = isPinnedExpanded
    }

    private var isExpanded: Bool {
        isHovered || isPinnedExpanded
    }

    public var body: some View {
        OnboardingStageFrame(showMenuBar: false) {
            VStack(spacing: 0) {
                Spacer(minLength: 26)

                // Miniature MacBook Pro hardware bezel & display
                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        // Inner MacBook desktop canvas
                        RoundedRectangle.grav(16)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0x09 / 255.0, green: 0x17 / 255.0, blue: 0x22 / 255.0),
                                        Color(red: 0x05 / 255.0, green: 0x0B / 255.0, blue: 0x11 / 255.0),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        // Subtle desktop top bar under bezel
                        HStack {
                            HStack(spacing: 10) {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(GravPalette.inkTertiary)
                                Text("Antigravity")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(GravPalette.inkSecondary)
                            }
                            Spacer()
                            HStack(spacing: 7) {
                                Image(systemName: "wifi")
                                    .font(.system(size: 9))
                                    .foregroundStyle(GravPalette.inkTertiary)
                                Text("9:41")
                                    .font(GravTypography.monoMicro)
                                    .foregroundStyle(GravPalette.inkTertiary)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 24)
                        .background(Color.black.opacity(0.28))

                        // Subtle background editor window silhouette to emphasize floating notch HUD
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 5) {
                                Circle().fill(Color.white.opacity(0.14)).frame(width: 6, height: 6)
                                Circle().fill(Color.white.opacity(0.14)).frame(width: 6, height: 6)
                                Circle().fill(Color.white.opacity(0.14)).frame(width: 6, height: 6)
                                Spacer()
                                Text("AntigravityTelemetryStore.swift")
                                    .font(GravTypography.monoMicro)
                                    .foregroundStyle(GravPalette.inkQuaternary)
                                Spacer()
                            }
                            Divider().background(Color.white.opacity(0.06))
                            VStack(alignment: .leading, spacing: 6) {
                                RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.06)).frame(width: 170, height: 5)
                                RoundedRectangle(cornerRadius: 2).fill(GravPalette.glacialTeal.opacity(0.14)).frame(width: 240, height: 5)
                                RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.05)).frame(width: 205, height: 5)
                                RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.04)).frame(width: 145, height: 5)
                            }
                            .padding(.top, 4)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle.grav(GravRadius.controlM)
                                .fill(Color.white.opacity(0.025))
                        )
                        .overlay(
                            RoundedRectangle.grav(GravRadius.controlM)
                                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                        )
                        .padding(.horizontal, 24)
                        .padding(.top, 92)
                        .opacity(isExpanded ? 0.35 : 0.85)

                        // Single-shape morphing hardware matte-black Notch HUD
                        MorphingNotchHousing(
                            mode: selectedMode,
                            isExpanded: isExpanded
                        )
                        .onHover { hovering in
                            let anim = reduceMotion ? GravMotion.subtleFade : GravMotion.railSpring
                            withAnimation(anim) {
                                isHovered = hovering
                            }
                        }
                        .onTapGesture {
                            let anim = reduceMotion ? GravMotion.subtleFade : GravMotion.railSpring
                            withAnimation(anim) {
                                isPinnedExpanded.toggle()
                            }
                        }
                    }
                    .frame(height: 318)
                    .clipShape(RoundedRectangle.grav(16))
                    .padding(10)
                    .background(
                        RoundedRectangle.grav(22)
                            .fill(GravPalette.notchBlack)
                    )
                    .overlay(
                        RoundedRectangle.grav(22)
                            .strokeBorder(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.white.opacity(0.26), location: 0.0),
                                        .init(color: Color.white.opacity(0.08), location: 0.45),
                                        .init(color: Color.white.opacity(0.04), location: 1.0),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1.0
                            )
                    )
                    .shadow(color: Color.black.opacity(0.55), radius: 26, y: 14)

                    // Subtle status readout below display bezel
                    HStack(spacing: 8) {
                        Circle()
                            .fill(isExpanded ? selectedMode.accentColor : GravPalette.inkQuaternary)
                            .frame(width: 6, height: 6)
                        Text(isExpanded ? "Expanded Telemetry HUD · \(selectedMode.title)" : "Collapsed Notch Pill · Hover or click notch to morph")
                            .font(GravTypography.monoMicro)
                            .foregroundStyle(GravPalette.inkTertiary)
                    }
                    .padding(.top, 14)
                }
                .padding(.horizontal, 26)

                Spacer(minLength: 78)
            }
        }
    }
}

// MARK: - Single-Shape Morphing Notch Housing

private struct MorphingNotchHousing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let mode: NotchPreviewMode
    let isExpanded: Bool

    var body: some View {
        let width: CGFloat = isExpanded ? 396 : 216
        let height: CGFloat = isExpanded ? 176 : 32
        let earRadius: CGFloat = isExpanded ? 12 : 8
        let bottomRadius: CGFloat = isExpanded ? 18 : 11

        ZStack(alignment: .top) {
            NotchHardwareMorphShape(earRadius: earRadius, bottomRadius: bottomRadius)
                .fill(GravPalette.notchBlack)
                .overlay(
                    NotchHardwareMorphShape(earRadius: earRadius, bottomRadius: bottomRadius)
                        .strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.clear, location: 0.0),
                                    .init(color: Color.white.opacity(isExpanded ? 0.14 : 0.08), location: 0.65),
                                    .init(color: Color.white.opacity(isExpanded ? 0.18 : 0.06), location: 1.0),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: Color.black.opacity(isExpanded ? 0.65 : 0.35), radius: isExpanded ? 20 : 8, y: isExpanded ? 10 : 4)

            VStack(spacing: 0) {
                // Collapsed top wing row (always present inside the single housing)
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        GravOrbitalMark(size: 13, tint: GravPalette.titaniumWhite)
                        if isExpanded {
                            Text("Grav")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(GravPalette.inkPrimary)
                        }
                    }

                    Spacer()

                    // Hardware camera lens indicator centered in collapsed state
                    if !isExpanded {
                        Circle()
                            .fill(Color(red: 0x10 / 255.0, green: 0x15 / 255.0, blue: 0x1C / 255.0))
                            .frame(width: 7, height: 7)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                        Spacer()
                    }

                    HStack(spacing: 5) {
                        Circle()
                            .fill(mode.accentColor)
                            .frame(width: 6, height: 6)
                        Text(mode.collapsedBadgeText)
                            .font(GravTypography.monoMicro)
                            .monospacedDigit()
                            .foregroundStyle(GravPalette.inkSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, isExpanded ? 24 : 18)
                .frame(height: 32)

                // Expanded telemetry payload
                if isExpanded {
                    Divider()
                        .background(Color.white.opacity(0.08))
                        .padding(.horizontal, 18)

                    expandedContent
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
        }
        .frame(width: width, height: height, alignment: .top)
        .animation(reduceMotion ? GravMotion.subtleFade : GravMotion.railSpring, value: isExpanded)
        .animation(reduceMotion ? GravMotion.subtleFade : GravMotion.contentSlide, value: mode)
    }

    @ViewBuilder
    private var expandedContent: some View {
        switch mode {
        case .thinking:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("REASONING · STEP 14")
                        .font(GravTypography.monoMicro)
                        .foregroundStyle(GravPalette.thinking)
                    Spacer()
                    Text("gemini-2.5-pro · 4.2s")
                        .font(GravTypography.monoMicro)
                        .monospacedDigit()
                        .foregroundStyle(GravPalette.inkTertiary)
                }

                Text("Tracing JSONL byte offset incremental tailing to ensure partial UTF-8 lines defer until newline flush without dropping step_index ordering...")
                    .font(GravTypography.body)
                    .foregroundStyle(GravPalette.inkSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    telemetryPill("18.4k in", tint: GravPalette.inkTertiary)
                    telemetryPill("12.1k cache", tint: GravPalette.glacialTeal)
                    telemetryPill("1.9k out", tint: GravPalette.glacialCyan)
                }
            }

        case .fileEdits:
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("FILE MUTATIONS")
                        .font(GravTypography.monoMicro)
                        .foregroundStyle(GravPalette.fileEdit)
                    Spacer()
                    Text("2 recent changes")
                        .font(GravTypography.monoMicro)
                        .foregroundStyle(GravPalette.inkTertiary)
                }

                fileDiffPreviewRow(
                    badge: "EDIT",
                    badgeColor: GravPalette.fileEdit,
                    fileName: "TranscriptTailer.swift",
                    added: "+18",
                    removed: "-4"
                )

                fileDiffPreviewRow(
                    badge: "DEL",
                    badgeColor: GravPalette.coral,
                    fileName: "LegacyPoller.swift",
                    added: "+0",
                    removed: "-62"
                )
            }

        case .commandLogs:
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("$ swift test --filter TelemetryTests")
                        .font(GravTypography.monoMicro)
                        .foregroundStyle(GravPalette.inkPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text("EXIT 0")
                        .font(GravTypography.monoMicro)
                        .foregroundStyle(GravPalette.emerald)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle.grav(4)
                                .fill(GravPalette.emerald.opacity(0.14))
                        )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Test Suite 'TranscriptTailerTests' passed (0.042s)")
                        .foregroundStyle(GravPalette.inkSecondary)
                    Text("Test Suite 'DiffExtractorTests' passed (0.019s)")
                        .foregroundStyle(GravPalette.inkSecondary)
                    Text("Executed 14 tests, with 0 failures in 0.061 seconds")
                        .foregroundStyle(GravPalette.emerald)
                }
                .font(GravTypography.monoMicro)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle.grav(GravRadius.controlS)
                        .fill(Color.white.opacity(0.04))
                )
            }
        }
    }

    private func telemetryPill(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(GravTypography.monoMicro)
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle.grav(GravRadius.controlXS)
                    .fill(Color.white.opacity(0.05))
            )
    }

    private func fileDiffPreviewRow(
        badge: String,
        badgeColor: Color,
        fileName: String,
        added: String,
        removed: String
    ) -> some View {
        HStack(spacing: 8) {
            Text(badge)
                .font(GravTypography.monoMicro)
                .foregroundStyle(badgeColor)
                .frame(width: 34)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle.grav(4)
                        .fill(badgeColor.opacity(0.14))
                )

            Text(fileName)
                .font(GravTypography.monoCaption)
                .foregroundStyle(GravPalette.inkPrimary)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 6) {
                Text(added)
                    .foregroundStyle(GravPalette.emerald)
                Text(removed)
                    .foregroundStyle(GravPalette.coral)
            }
            .font(GravTypography.monoMicro)
            .monospacedDigit()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle.grav(GravRadius.controlS)
                .fill(Color.white.opacity(0.045))
        )
    }
}

/// Authentic MacBook notch silhouette with concave top ears and continuous bottom corners,
/// morphing smoothly as a single unified hardware shape.
private struct NotchHardwareMorphShape: InsettableShape {
    var earRadius: CGFloat
    var bottomRadius: CGFloat
    var insetAmount: CGFloat = 0

    nonisolated var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(earRadius, bottomRadius) }
        set {
            earRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func inset(by amount: CGFloat) -> Self {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: 0)
        let ear = min(earRadius, insetRect.width * 0.14, insetRect.height * 0.45)
        let bottom = min(bottomRadius, (insetRect.width - ear * 2) * 0.45, insetRect.height - ear)

        let left = insetRect.minX
        let right = insetRect.maxX
        let top = insetRect.minY
        let bottomY = insetRect.maxY - insetAmount

        var path = Path()
        path.move(to: CGPoint(x: left, y: top))
        // Left concave ear sweeping into left wall
        path.addQuadCurve(
            to: CGPoint(x: left + ear, y: top + ear),
            control: CGPoint(x: left + ear, y: top)
        )
        // Left sidewall
        path.addLine(to: CGPoint(x: left + ear, y: bottomY - bottom))
        // Bottom-left continuous curve
        path.addQuadCurve(
            to: CGPoint(x: left + ear + bottom, y: bottomY),
            control: CGPoint(x: left + ear, y: bottomY)
        )
        // Bottom edge
        path.addLine(to: CGPoint(x: right - ear - bottom, y: bottomY))
        // Bottom-right continuous curve
        path.addQuadCurve(
            to: CGPoint(x: right - ear, y: bottomY - bottom),
            control: CGPoint(x: right - ear, y: bottomY)
        )
        // Right sidewall
        path.addLine(to: CGPoint(x: right - ear, y: top + ear))
        // Right concave ear back to top bezel
        path.addQuadCurve(
            to: CGPoint(x: right, y: top),
            control: CGPoint(x: right - ear, y: top)
        )
        path.closeSubpath()
        return path
    }
}

private struct NotchModeSelectorRow: View {
    let mode: NotchPreviewMode
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            OnboardingSpecularCard(
                elevation: isHovered ? .elevated : .subtle,
                cornerRadius: GravRadius.card,
                isHighlighted: isSelected,
                padding: 13
            ) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle.grav(GravRadius.controlS)
                            .fill(isSelected ? mode.accentColor.opacity(0.18) : GravPalette.cardFillBase)
                            .frame(width: 30, height: 30)
                            .overlay(
                                RoundedRectangle.grav(GravRadius.controlS)
                                    .strokeBorder(
                                        isSelected ? AnyShapeStyle(mode.accentColor.opacity(0.45)) : AnyShapeStyle(GravPalette.specularStroke),
                                        lineWidth: 0.5
                                    )
                            )
                        Image(systemName: mode.symbolName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isSelected ? mode.accentColor : GravPalette.inkSecondary)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(mode.title)
                                .font(GravTypography.bodyMedium)
                                .foregroundStyle(GravPalette.inkPrimary)

                            Spacer()

                            if isSelected {
                                Circle()
                                    .fill(mode.accentColor)
                                    .frame(width: 6, height: 6)
                            }
                        }

                        Text(mode.description)
                            .font(GravTypography.caption)
                            .foregroundStyle(GravPalette.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(GravMotion.rowHover) {
                isHovered = hovering
            }
        }
    }
}
