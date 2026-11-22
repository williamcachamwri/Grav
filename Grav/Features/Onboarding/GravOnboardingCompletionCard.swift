//
//  GravOnboardingCompletionCard.swift
//  Grav
//
//  Completion screen: the Grav app mark framed by Leica viewfinder brackets, what just became
//  possible in a 2×2 capability grid, and the launch button into the MacBook notch finale,
//  ported 1:1 from Snapzy's `SnapzyOnboardingCompletionCard.swift`.
//

import AppKit
import SwiftUI

struct GravOnboardingCompletionCard: View {
    var externalLaunchTrigger: Int = 0
    var onBeginLaunch: () -> Void = {}
    var onFinish: (_ iconWindowFrame: CGRect?) -> Void
    var onBack: (() -> Void)?

    @State private var hasAppeared = false
    @State private var isLaunching = false
    @State private var didHandOffIcon = false
    @State private var iconWindowFrame: CGRect?
    @Environment(\.accessibilityReduceMotion) private var envReduceMotion

    private var reduceMotion: Bool {
        GravMotionPreferences.shared.reduceMotion || envReduceMotion
    }

    var body: some View {
        VStack(spacing: GravSpace.giant) {
            hero
                .gravEntrance(0, appeared: hasAppeared, step: 0.06)

            capabilitiesGrid
                .gravEntrance(1, appeared: hasAppeared, step: 0.06)
                .opacity(isLaunching ? 0 : 1)
                .scaleEffect(isLaunching && !reduceMotion ? 0.97 : 1.0)
                .offset(y: isLaunching && !reduceMotion ? 14 : 0)
                .animation(reduceMotion ? nil : .timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.24), value: isLaunching)

            primaryActionRow
                .gravEntrance(2, appeared: hasAppeared, step: 0.06)
                .opacity(isLaunching ? 0 : 1)
                .scaleEffect(isLaunching && !reduceMotion ? 0.96 : 1.0)
                .offset(y: isLaunching && !reduceMotion ? 10 : 0)
                .animation(reduceMotion ? nil : .timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.20), value: isLaunching)
        }
        .frame(maxWidth: 760)
        .allowsHitTesting(!isLaunching)
        .onAppear { hasAppeared = true }
        .onChange(of: externalLaunchTrigger) { _, _ in
            triggerLaunch()
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: GravSpace.xxl) {
            ZStack {
                // Minimalist Leica-inspired precision viewfinder brackets that briefly frame the icon
                // right before it ascends to the MacBook notch (pure hairline vector, zero glow).
                CompletionViewfinderBrackets()
                    .stroke(
                        Color.white.opacity(isLaunching && !didHandOffIcon ? 0.72 : 0),
                        style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 72, height: 72)
                    .scaleEffect(isLaunching ? 1.0 : 1.24)
                    .animation(
                        reduceMotion ? nil : .timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.22),
                        value: isLaunching
                    )

                Image(nsImage: GravOnboardingIconCache.appIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 56, height: 56)
                    .clipShape(Radius.rect(Radius.card))
                    .scaleEffect(isLaunching && !reduceMotion ? 1.08 : 1.0)
                    .opacity(didHandOffIcon ? 0 : 1)
                    .animation(
                        reduceMotion ? nil : .timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.22),
                        value: isLaunching
                    )
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { iconWindowFrame = geo.frame(in: .global) }
                                .onChange(of: geo.frame(in: .global)) { _, newFrame in
                                    if newFrame.width > 0 && newFrame.height > 0 && !isLaunching {
                                        iconWindowFrame = newFrame
                                    }
                                }
                        }
                    )
            }
            .frame(width: 56, height: 56)

            VStack(spacing: GravSpace.lg) {
                GravOnboardingOverline("All Set")

                Text("Grav is ready in your notch")
                    .font(.system(size: GravOnboardingType.title, weight: .bold))
                    .tracking(GravOnboardingType.displayTracking + 0.2)
                    .foregroundStyle(GravGlassInk.primary)

                Text("Your live Antigravity telemetry bridge is armed. Hover your MacBook notch anytime to inspect reasoning, file diffs, and shell logs.")
                    .font(.system(size: GravOnboardingType.lede))
                    .foregroundStyle(GravGlassInk.body)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 580)
            }
            .opacity(isLaunching ? 0 : 1)
            .offset(y: isLaunching && !reduceMotion ? 10 : 0)
            .animation(reduceMotion ? nil : .timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.22), value: isLaunching)
        }
    }

    private func triggerLaunch() {
        guard !isLaunching else { return }
        isLaunching = true
        onBeginLaunch()

        if reduceMotion {
            didHandOffIcon = true
            onFinish(iconWindowFrame)
            return
        }

        Task { @MainActor in
            // Hold one crisp 220ms framing beat as the cards release and viewfinder brackets lock on,
            // then hand the icon seamlessly to the desktop overlay for its 120fps ascent to the notch.
            try? await Task.sleep(for: .milliseconds(220))
            didHandOffIcon = true
            onFinish(iconWindowFrame)
        }
    }

    // MARK: - Capabilities (2×2 Grid)

    private var capabilitiesGrid: some View {
        VStack(spacing: GravSpace.lg) {
            HStack(spacing: GravSpace.lg) {
                CapabilityCard(
                    icon: "brain",
                    shortcut: "1",
                    title: "Live Thinking",
                    detail: "Follow Antigravity's streaming reasoning steps right from your notch."
                )

                CapabilityCard(
                    icon: "doc.badge.gearshape",
                    shortcut: "2",
                    title: "File Diffs",
                    detail: "Inspect modified files and line-level additions the instant they land."
                )
            }

            HStack(spacing: GravSpace.lg) {
                CapabilityCard(
                    icon: "terminal",
                    shortcut: "3",
                    title: "Terminal Logs",
                    detail: "Stream active shell commands, elapsed time, and exit codes in real time."
                )

                CapabilityCard(
                    icon: "slider.horizontal.3",
                    shortcut: "⌘,",
                    title: "Settings",
                    detail: "Tune startup, hover sensitivity, auto-peek alerts, and Liquid Glass chrome."
                )
            }
        }
    }

    // MARK: - Primary Action

    private var primaryActionRow: some View {
        VStack(spacing: GravSpace.xl) {
            GravOnboardingActionBar(
                continueTitle: "Start Using Grav",
                continueKey: "\u{21A9}",
                isContinueEnabled: true,
                isHinted: true,
                onContinue: triggerLaunch
            )

            if let onBack {
                Button(action: onBack) {
                    Text("Review previous step")
                        .font(.system(size: GravOnboardingType.caption))
                        .foregroundStyle(GravGlassInk.faint)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Capability Card

private struct CapabilityCard: View {
    var icon: String
    var shortcut: String
    var title: String
    var detail: String

    @State private var isHovered = false

    private var shape: RoundedRectangle {
        Radius.rect(Radius.card)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GravSpace.lg) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(GravGlassInk.body)
                    .frame(width: 26, height: 26)
                    .background(Radius.rect(Radius.tile).fill(GravGlassInk.fillRaised))
                    .accessibilityHidden(true)

                Spacer(minLength: 0)

                GravKeycapChip(label: shortcut, emphasis: isHovered)
            }

            VStack(alignment: .leading, spacing: GravSpace.xxs) {
                Text(title)
                    .font(.system(size: GravOnboardingType.body, weight: .semibold))
                    .foregroundStyle(GravGlassInk.primary)

                Text(detail)
                    .font(.system(size: GravOnboardingType.caption))
                    .foregroundStyle(GravGlassInk.muted)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(GravSpace.xxl)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(shape.fill(isHovered ? GravGlassInk.fillHover : GravGlassInk.fillQuiet))
        .overlay(
            shape.strokeBorder(
                isHovered ? GravGlassInk.hairlineStrong : GravGlassInk.hairline,
                lineWidth: GravSurfaceGlass.specularLineWidth
            )
        )
        .onHover { hovering in
            withAnimation(GravMotionPreferences.shared.spec(.hover).animation) { isHovered = hovering }
        }
    }
}

// MARK: - Leica Precision Viewfinder Brackets

private struct CompletionViewfinderBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let arm: CGFloat = 12
        let r: CGFloat = 6
        var path = Path()

        // Top-leading
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + arm))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))

        // Top-trailing
        path.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))

        // Bottom-trailing
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))

        // Bottom-leading
        path.move(to: CGPoint(x: rect.minX + arm, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - arm))

        return path
    }
}
