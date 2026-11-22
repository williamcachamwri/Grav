//
//  GravMockDesktopCanvas.swift
//  Grav
//
//  Faithful macOS desktop canvas & shared scene primitives ported 1:1 from Snapzy's
//  `SnapzyMockDesktopCanvas.swift` and `SnapzyMockScene.swift`: studio ambient wallpaper
//  with per-step monospaced watermark grid and authentic Apple Silicon menu bar with flush
//  camera notch.
//

import SwiftUI

// MARK: - Mock App Identity

enum GravMockApp: String, Equatable, Sendable {
    case antigravity
    case notchHud
    case settings

    var menuTitle: String {
        switch self {
        case .antigravity: "Antigravity"
        case .notchHud: "Grav"
        case .settings: "System Settings"
        }
    }

    var menus: [String] {
        switch self {
        case .antigravity: ["File", "Edit", "View", "Agent", "Help"]
        case .notchHud: ["Telemetry", "Notch", "View", "Window", "Help"]
        case .settings: ["Edit", "View", "Window", "Help"]
        }
    }

    var watermarks: [GravWatermark] {
        switch self {
        case .antigravity:
            return [
                .init(text: "Antigravity"),
                .init(text: "Grav"),
                .init(text: "kqueue · 0% CPU", size: 28, weight: .heavy, opacity: 0.040),
                .init(text: "Telemetry"),
                .init(text: "Studio", opacity: 0.040),
                .init(text: "macOS"),
            ]
        case .notchHud:
            return [
                .init(text: "Notch HUD"),
                .init(text: "Grav", size: 32, weight: .heavy, opacity: 0.042),
                .init(text: "Thinking"),
                .init(text: "File Diffs", opacity: 0.040),
                .init(text: "Terminal"),
                .init(text: "120Hz", opacity: 0.040),
            ]
        case .settings:
            return [
                .init(text: "Settings"),
                .init(text: "Preferences"),
                .init(text: "Grav", size: 32, weight: .heavy, opacity: 0.042),
                .init(text: "Liquid Glass"),
                .init(text: "macOS", opacity: 0.040),
                .init(text: "Auto-Peek", opacity: 0.040),
            ]
        }
    }
}

struct GravWatermark: Equatable, Sendable {
    var text: String
    var size: CGFloat = 34
    var weight: Font.Weight = .black
    var opacity: Double = 0.045
}

// MARK: - Lit macOS Desktop Palette

enum GravMockPalette {
    /// Text and rules drawn on the light desktop surfaces.
    static let ink = Color(red: 0.12, green: 0.13, blue: 0.15)
    static let inkSecondary = Color(red: 0.34, green: 0.36, blue: 0.40)
    static let inkTertiary = Color(red: 0.55, green: 0.57, blue: 0.61)
    /// Window bodies and the menu bar.
    static let chrome = Color(red: 0.985, green: 0.987, blue: 0.992)
    static let chromeBar = Color(red: 0.94, green: 0.945, blue: 0.955)
    static let chromeEdge = Color(red: 0.80, green: 0.81, blue: 0.83)
    static let chromeRule = Color.black.opacity(0.08)
    /// The notch and the display bezel it sits in.
    static let bezel = Color(red: 0.04, green: 0.045, blue: 0.055)
    /// Traffic lights, kept at their real macOS system hues (`#FF5F57`, `#FEBC2E`, `#28C840`).
    static let trafficRed = Color(red: 1.00, green: 0.373, blue: 0.341)
    static let trafficYellow = Color(red: 0.996, green: 0.737, blue: 0.180)
    static let trafficGreen = Color(red: 0.157, green: 0.784, blue: 0.251)
    /// Native macOS & Grav accents inside simulated desktop windows.
    static let macBlue = Color(red: 0.00, green: 0.478, blue: 1.00)
    static let gravTeal = Color(red: 0.102, green: 0.557, blue: 0.992)
    static let gravEmerald = Color(red: 0.12, green: 0.68, blue: 0.48)
    static let gravAmber = Color(red: 0.88, green: 0.58, blue: 0.08)
    static let gravCoral = Color(red: 0.88, green: 0.32, blue: 0.30)
}

// MARK: - Studio Watermark Wallpaper

struct GravMockWallpaper: View, Equatable {
    var app: GravMockApp = .antigravity

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.945, green: 0.950, blue: 0.960),
                    Color(red: 0.885, green: 0.895, blue: 0.915),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: 38) {
                    ForEach(0..<8, id: \.self) { row in
                        HStack(spacing: 44) {
                            ForEach(0..<6, id: \.self) { col in
                                let mark = app.watermarks[(row * 3 + col) % app.watermarks.count]
                                Text(mark.text)
                                    .font(.system(size: mark.size, weight: mark.weight, design: .monospaced))
                                    .foregroundStyle(Color.black.opacity(mark.opacity))
                                    .rotationEffect(.degrees(-14))
                            }
                        }
                    }
                }
                .frame(width: proxy.size.width * 1.8, height: proxy.size.height * 1.8)
                .offset(x: -80, y: -60)
            }
            .clipped()
        }
        .drawingGroup(opaque: true)
        .accessibilityHidden(true)
    }
}

// MARK: - Authentic MacBook Hardware Notch Shape

/// Real MacBook Pro / Air display notch: flush with `y = 0`, subtle concave top-corner shoulders
/// meeting the screen top bezel seamlessly, and smooth rounded bottom corners.
struct MacBookNotchShape: Shape {
    var shoulderRadius: CGFloat = 5
    var bottomRadius: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        let s = min(shoulderRadius, rect.width * 0.12)
        let r = min(bottomRadius, rect.height * 0.5, (rect.width - s * 2) * 0.5)
        let leftX = rect.minX + s
        let rightX = rect.maxX - s

        var path = Path()
        // Top edge spanning across both concave shoulders
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

        // Top-right concave shoulder curving down into the right vertical side
        path.addQuadCurve(
            to: CGPoint(x: rightX, y: rect.minY + s),
            control: CGPoint(x: rightX, y: rect.minY)
        )

        // Right vertical side + smooth bottom-right corner
        path.addLine(to: CGPoint(x: rightX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rightX - r, y: rect.maxY),
            control: CGPoint(x: rightX, y: rect.maxY)
        )

        // Bottom edge + smooth bottom-left corner
        path.addLine(to: CGPoint(x: leftX + r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: leftX, y: rect.maxY - r),
            control: CGPoint(x: leftX, y: rect.maxY)
        )

        // Left vertical side + top-left concave shoulder returning to top edge
        path.addLine(to: CGPoint(x: leftX, y: rect.minY + s))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: leftX, y: rect.minY)
        )

        path.closeSubpath()
        return path
    }
}

// MARK: - Menu Bar (Cropped Real-Scale MacBook Display)

struct GravMockMenuBar: View, Equatable {
    var app: GravMockApp = .antigravity
    var showsCameraNotch: Bool = true

    static let barHeight: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let visibleWidth = proxy.size.width
            // The right-column stage is a cropped frame onto a full-width Mac screen, so the camera
            // notch sits shifted toward the virtual display center and right status icons crop naturally.
            let notchShift = max(100, visibleWidth * 0.21)
            let notchCenterX = (visibleWidth / 2) + notchShift
            let notchWidth: CGFloat = 96
            let notchRightEdge = notchCenterX + (notchWidth / 2)

            ZStack(alignment: .topLeading) {
                // Translucent frosted menu bar strip
                Rectangle()
                    .fill(Color.white.opacity(0.84))
                    .frame(height: Self.barHeight)
                    .overlay(
                        Rectangle()
                            .fill(Color.black.opacity(0.06))
                            .frame(height: 0.5),
                        alignment: .bottom
                    )

                // 1. Left Menu Items ( + App Title + full macOS menus at real scale)
                leadingCluster
                    .padding(.leading, 18)
                    .frame(height: Self.barHeight, alignment: .leading)

                // 2. Camera Notch (shifted right to virtual display center, flush at y = 0)
                cameraNotch
                    .position(x: notchCenterX, y: 10.5)
                    .opacity(showsCameraNotch ? 1 : 0)
                    .animation(.easeInOut(duration: 0.22), value: showsCameraNotch)

                // 3. Right Status Bar Items (extending naturally past the cropped right edge)
                trailingCluster
                    .frame(height: Self.barHeight, alignment: .leading)
                    .offset(x: notchRightEdge + 22)
            }
        }
        .frame(height: Self.barHeight)
        .accessibilityHidden(true)
    }

    private var leadingCluster: some View {
        HStack(spacing: 11) {
            Image(systemName: "apple.logo")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.90))
                .offset(y: -0.5)

            HStack(spacing: 11) {
                Text(app.menuTitle)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.92))

                ForEach(app.menus, id: \.self) { menu in
                    Text(menu)
                }
            }
            .id(app)
            .transition(.opacity.combined(with: .offset(y: 2)))
            .animation(.timingCurve(0.20, 0.0, 0.12, 1.0, duration: 0.34), value: app)
        }
        .font(.system(size: 11.5, weight: .regular))
        .foregroundStyle(Color.black.opacity(0.82))
        .fixedSize()
    }

    private var trailingCluster: some View {
        HStack(spacing: 11) {
            GravOrbitalMark(size: 11, tint: Color.black.opacity(0.84))

            Image(systemName: "wifi")
                .font(.system(size: 10.5, weight: .semibold))

            MacOSMenuBarBattery()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))

            MacOSControlCenterGlyph()

            Text("Sun Nov 22  9:41")
                .font(.system(size: 10.5, weight: .medium))
                .tracking(-0.1)
                .monospacedDigit()
        }
        .foregroundStyle(Color.black.opacity(0.84))
        .fixedSize()
    }

    private var cameraNotch: some View {
        ZStack {
            MacBookNotchShape(shoulderRadius: 5, bottomRadius: 6.5)
                .fill(GravMockPalette.bezel)

            Circle()
                .fill(Color(white: 0.12))
                .frame(width: 4.5, height: 4.5)
                .overlay(
                    Circle()
                        .fill(Color(red: 0.04, green: 0.05, blue: 0.08))
                        .frame(width: 2.5, height: 2.5)
                )
                .offset(y: -0.5)
        }
        .frame(width: 96, height: 21)
    }
}

private struct MacOSMenuBarBattery: View {
    var body: some View {
        HStack(spacing: 1) {
            RoundedRectangle(cornerRadius: 2.3, style: .continuous)
                .fill(.primary)
                .frame(width: 16.5, height: 8.5)

            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 1.2,
                topTrailingRadius: 1.2
            )
            .fill(.primary.opacity(0.75))
            .frame(width: 1.4, height: 3.4)
        }
    }
}

private struct MacOSControlCenterGlyph: View {
    var body: some View {
        VStack(spacing: 1.8) {
            ZStack(alignment: .trailing) {
                Capsule(style: .continuous)
                    .strokeBorder(.primary, lineWidth: 1.0)
                    .frame(width: 11, height: 4.4)
                Circle()
                    .fill(.primary)
                    .frame(width: 3.2, height: 3.2)
                    .padding(.trailing, 0.7)
            }

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.primary)
                    .frame(width: 11, height: 4.4)
                Circle()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: 2.6, height: 2.6)
                    .padding(.leading, 1.0)
            }
        }
    }
}

// MARK: - Shared Scene Vocabulary & Environment

@MainActor
enum GravMockScene {
    static let windowInset: CGFloat = 22
    static let windowTopInset: CGFloat = 40

    static var windowTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity),
            removal: .scale(scale: 0.97, anchor: .top).combined(with: .opacity)
        )
    }

    static var cardTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.94)),
            removal: .move(edge: .bottom).combined(with: .opacity)
        )
    }

    static var hudTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.94).combined(with: .opacity),
            removal: .opacity
        )
    }
}

private struct GravMockSceneIsLiveKey: EnvironmentKey {
    static let defaultValue = true
}

private struct GravMockSceneIsSettledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var gravMockSceneIsLive: Bool {
        get { self[GravMockSceneIsLiveKey.self] }
        set { self[GravMockSceneIsLiveKey.self] = newValue }
    }

    var gravMockSceneIsSettled: Bool {
        get { self[GravMockSceneIsSettledKey.self] }
        set { self[GravMockSceneIsSettledKey.self] = newValue }
    }
}

struct GravMockTrafficLights: View {
    var size: CGFloat = 10
    var spacing: CGFloat = 6.5

    var body: some View {
        HStack(spacing: spacing) {
            dot(GravMockPalette.trafficRed)
            dot(GravMockPalette.trafficYellow)
            dot(GravMockPalette.trafficGreen)
        }
        .accessibilityHidden(true)
    }

    private func dot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5)
            )
    }
}

struct GravMockSceneButton: View {
    var title: String
    var symbol: String?
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                }

                Text(title)
                    .font(.system(size: GravOnboardingType.body, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background {
                LiquidGlassSurface(
                    shape: Capsule(style: .continuous),
                    substrate: GravSurfaceGlass.baseDarkness + (isHovered ? 0.06 : 0),
                    tint: isHovered ? 0.16 : 0.10
                )
            }
            .clipShape(Capsule(style: .continuous))
            .shadow(
                color: GravGlassShadow.controlColor,
                radius: GravGlassShadow.controlRadius,
                y: GravGlassShadow.controlY
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(GravMotionPreferences.shared.spec(.hover).animation) {
                isHovered = hovering
            }
        }
    }
}
