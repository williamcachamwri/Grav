//
//  GravMockDesktopCanvas.swift
//  Grav
//
//  Faithful macOS desktop canvas & shared scene primitives ported 1:1 from Snapzy's
//  `SnapzyMockDesktopCanvas.swift` and `SnapzyMockScene.swift`: studio ambient wallpaper
//  with per-step monospaced watermark grid and authentic Apple Silicon menu bar with flush
//  camera notch.
//

import AppKit
import ImageIO
import SwiftUI

// MARK: - Mock App Identity

enum GravMockApp: String, Equatable, Sendable {
    case antigravity
    case notchHud
    case miniPet
    case settings

    var menuTitle: String {
        switch self {
        case .antigravity: "Antigravity"
        case .notchHud: "Grav"
        case .miniPet: "Grav Pets"
        case .settings: "System Settings"
        }
    }

    var menus: [String] {
        switch self {
        case .antigravity: ["File", "Edit", "View", "Agent", "Help"]
        case .notchHud: ["Telemetry", "Notch", "View", "Window", "Help"]
        case .miniPet: ["Stage", "Export", "Gallery", "Window", "Help"]
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
        case .miniPet:
            return [
                .init(text: "Mini Pet"),
                .init(text: "codex-pets.net", size: 28, weight: .heavy, opacity: 0.040),
                .init(text: "Grav", size: 32, weight: .heavy, opacity: 0.042),
                .init(text: "Pixel Art"),
                .init(text: "120 ms · GIF", opacity: 0.040),
                .init(text: "Notch Companion", size: 26, weight: .heavy, opacity: 0.038),
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
    /// Authentic Dark Mode macOS ink ramp.
    static let ink = Color.white.opacity(0.92)
    static let inkSecondary = Color.white.opacity(0.58)
    static let inkTertiary = Color.white.opacity(0.36)
    /// Authentic macOS Sequoia/Tahoe Dark Mode window surfaces (`#1C1D22` body, `#24252B` titlebar, `#16171C` sidebar).
    static let chrome = Color(red: 0.110, green: 0.114, blue: 0.132)
    static let chromeBar = Color(red: 0.145, green: 0.149, blue: 0.172)
    static let chromeCard = Color.white.opacity(0.052)
    static let chromeSidebar = Color(red: 0.095, green: 0.098, blue: 0.115)
    static let chromeEdge = Color.white.opacity(0.14)
    static let chromeRule = Color.white.opacity(0.08)
    /// The notch and the display bezel it sits in.
    static let bezel = Color.black
    /// Traffic lights, kept at their real macOS system hues (`#FF5F57`, `#FEBC2E`, `#28C840`).
    static let trafficRed = Color(red: 1.00, green: 0.373, blue: 0.341)
    static let trafficYellow = Color(red: 0.996, green: 0.737, blue: 0.180)
    static let trafficGreen = Color(red: 0.157, green: 0.784, blue: 0.251)
    /// Native macOS & Grav accents inside simulated desktop windows.
    static let macBlue = Color(red: 0.102, green: 0.557, blue: 0.992)
    static let gravTeal = Color(red: 0.102, green: 0.557, blue: 0.992)
    static let gravEmerald = Color(red: 0.204, green: 0.827, blue: 0.600)
    static let gravAmber = Color(red: 0.960, green: 0.620, blue: 0.043)
    static let gravCoral = Color(red: 0.973, green: 0.443, blue: 0.443)
}

// MARK: - Real Built-In macOS Dark Wallpaper Loader (Cached Once for 120Hz Spaces)

@MainActor
private enum GravMacOSWallpaperCache {
    static let darkWallpaper: NSImage? = loadBestDarkMacOSWallpaper()

    private static func loadBestDarkMacOSWallpaper() -> NSImage? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates: [URL] = [
            URL(fileURLWithPath: "\(home)/Library/Application Support/com.apple.mobileAssetDesktop/Pro Black.heic"),
            URL(fileURLWithPath: "/System/Library/Desktop Pictures/.thumbnails/Motion Blue Dark.heic"),
            URL(fileURLWithPath: "/System/Library/Desktop Pictures/.thumbnails/The Beach Dark.heic"),
            URL(fileURLWithPath: "/System/Library/Desktop Pictures/.thumbnails/Catalina Evening.heic"),
            URL(fileURLWithPath: "/System/Library/Desktop Pictures/.thumbnails/Grid Magenta Dark.heic"),
            URL(fileURLWithPath: "/System/Library/Desktop Pictures/Mac Blue.heic"),
        ]

        if let screen = NSScreen.main ?? NSScreen.screens.first,
           let currentURL = NSWorkspace.shared.desktopImageURL(for: screen),
           FileManager.default.fileExists(atPath: currentURL.path)
        {
            candidates.insert(currentURL, at: 1)
        }

        for url in candidates {
            if let img = decodeDownsampledImage(at: url, maxPixelSize: 1440) {
                return img
            }
        }
        return nil
    }

    private static func decodeDownsampledImage(at url: URL, maxPixelSize: Int) -> NSImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

// MARK: - Authentic Built-In macOS Dark Desktop Wallpaper

struct GravMockWallpaper: View, Equatable {
    var app: GravMockApp = .antigravity

    var body: some View {
        ZStack {
            // Deep Pro Black studio fallback substrate
            LinearGradient(
                colors: [
                    Color(red: 0.045, green: 0.050, blue: 0.068),
                    Color(red: 0.025, green: 0.028, blue: 0.040),
                    Color(red: 0.015, green: 0.017, blue: 0.024),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let wallpaper = GravMacOSWallpaperCache.darkWallpaper {
                GeometryReader { proxy in
                    Image(nsImage: wallpaper)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
            } else {
                // Refined dark Apple Pro-style subtle radial silk sheen if no system wallpaper file exists
                RadialGradient(
                    colors: [
                        Color(red: 0.10, green: 0.24, blue: 0.44).opacity(0.32),
                        Color(red: 0.04, green: 0.06, blue: 0.12).opacity(0.18),
                        Color.clear,
                    ],
                    center: UnitPoint(x: 0.65, y: 0.30),
                    startRadius: 20,
                    endRadius: 420
                )
            }

            // Subtle dark vignette for crisp macOS Dark Mode window legibility
            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.24),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
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

    static let barHeight: CGFloat = 25

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d  h:mm a"
        return f
    }()

    var body: some View {
        GeometryReader { proxy in
            let visibleWidth = proxy.size.width
            let notchShift = max(100, visibleWidth * 0.21)
            let notchCenterX = (visibleWidth / 2) + notchShift
            let notchWidth: CGFloat = 96
            let notchRightEdge = notchCenterX + (notchWidth / 2)

            ZStack(alignment: .topLeading) {
                // Authentic macOS Dark Mode frosted translucent menu bar
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color(red: 0.04, green: 0.045, blue: 0.06).opacity(0.45))
                    .frame(height: Self.barHeight)
                    .overlay(
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
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
                .foregroundStyle(Color.white.opacity(0.94))
                .offset(y: -0.5)

            HStack(spacing: 11) {
                Text(app.menuTitle)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.96))

                ForEach(app.menus, id: \.self) { menu in
                    Text(menu)
                }
            }
            .id(app)
            .transition(.opacity.combined(with: .offset(y: 2)))
            .animation(.timingCurve(0.20, 0.0, 0.12, 1.0, duration: 0.34), value: app)
        }
        .font(.system(size: 11.5, weight: .regular))
        .foregroundStyle(Color.white.opacity(0.86))
        .fixedSize()
    }

    private var trailingCluster: some View {
        HStack(spacing: 11) {
            GravOrbitalMark(size: 11.5, tint: Color.white.opacity(0.90))

            Image(systemName: "wifi")
                .font(.system(size: 10.5, weight: .semibold))

            MacOSMenuBarBattery()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))

            MacOSControlCenterGlyph()

            Text(Self.clockFormatter.string(from: Date()))
                .font(.system(size: 10.5, weight: .medium))
                .tracking(-0.1)
                .monospacedDigit()
        }
        .foregroundStyle(Color.white.opacity(0.88))
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
                    .fill(Color.black.opacity(0.85))
                    .frame(width: 2.6, height: 2.6)
                    .padding(.leading, 1.0)
            }
        }
    }
}

// MARK: - Authentic macOS Translucent Glass Dock (Real System App Icons)

@MainActor
private enum GravMacOSDockIcons {
    struct Item: Identifiable {
        let id: String
        let icon: NSImage?
        let isGrav: Bool
        let isRunning: Bool
    }

    static let items: [Item] = {
        let specs: [(id: String, path: String, running: Bool)] = [
            ("finder", "/System/Library/CoreServices/Finder.app", true),
            ("safari", "/Applications/Safari.app", false),
            ("terminal", "/System/Applications/Utilities/Terminal.app", true),
            ("antigravity", "/Applications/Antigravity.app", true),
            ("settings", "/System/Applications/System Settings.app", false),
        ]
        var list: [Item] = []
        for spec in specs {
            if FileManager.default.fileExists(atPath: spec.path) {
                let img = NSWorkspace.shared.icon(forFile: spec.path)
                list.append(Item(id: spec.id, icon: img, isGrav: false, isRunning: spec.running))
            }
            if spec.id == "antigravity" {
                list.append(Item(id: "grav", icon: nil, isGrav: true, isRunning: true))
            }
        }
        return list
    }()
}

struct GravMockMacOSDock: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        HStack(spacing: 8) {
            ForEach(GravMacOSDockIcons.items) { item in
                VStack(spacing: 2.5) {
                    if item.isGrav {
                        GravAppIconTile(size: 30)
                            .shadow(color: Color.black.opacity(0.32), radius: 3, y: 1.5)
                    } else if let nsImage = item.icon {
                        Image(nsImage: nsImage)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 34, height: 34)
                            .shadow(color: Color.black.opacity(0.30), radius: 3, y: 1.5)
                    }

                    Circle()
                        .fill(Color.white.opacity(item.isRunning ? 0.72 : 0.0))
                        .frame(width: 3, height: 3)
                }
                .frame(width: 34)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 5)
        .padding(.bottom, 3)
        .background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.black.opacity(0.26))
            }
        }
        .overlay(
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.24),
                        Color.white.opacity(0.08),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.5
            )
        )
        .shadow(color: Color.black.opacity(0.45), radius: 18, y: 8)
        .accessibilityHidden(true)
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
