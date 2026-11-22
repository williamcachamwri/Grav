import SwiftUI

// MARK: - Visual Option Tile (Ported 1:1 from Snapzy's PreferencesVisualOptionTile)

/// Selectable thumbnail + caption tile with an outer accent selection ring separated by a hairline gap.
struct PreferencesVisualOptionTile<Thumbnail: View>: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let thumbnail: () -> Thumbnail

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    static var thumbnailSize: CGSize { CGSize(width: 72, height: 52) }
    private static var ringInset: CGFloat { 3.5 }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                thumbnail()
                    .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
                    .clipShape(Radius.rect(Radius.tile))
                    .overlay { Radius.rect(Radius.tile).strokeBorder(hairlineColor, lineWidth: 0.5) }
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .brightness(isHovering && !isSelected ? 0.04 : 0)
                    .padding(Self.ringInset)
                    .overlay {
                        Radius.rect(Radius.tile + Self.ringInset)
                            .strokeBorder(Color.accentColor, lineWidth: 2.5)
                            .opacity(isSelected ? 1 : 0)
                    }

                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var hairlineColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
    }
}

// MARK: - Appearance Mode Thumbnails (Ported 1:1 from Snapzy's AppearanceThumbnailView)

/// Individual System / Light / Dark miniature macOS window preview thumbnail.
struct AppearanceThumbnailView: View {
    let mode: GravAppearanceMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        PreferencesVisualOptionTile(title: mode.displayName, isSelected: isSelected, action: action) {
            thumbnailPreview
        }
    }

    @ViewBuilder
    private var thumbnailPreview: some View {
        switch mode {
        case .system:
            splitThumbnail
        case .light:
            windowPreview(isDark: false)
        case .dark:
            windowPreview(isDark: true)
        }
    }

    private var splitThumbnail: some View {
        HStack(spacing: 0) {
            windowPreview(isDark: false)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 8,
                        bottomLeadingRadius: 8,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                )

            windowPreview(isDark: true)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 8,
                        topTrailingRadius: 8
                    )
                )
        }
    }

    private func windowPreview(isDark: Bool) -> some View {
        VStack(spacing: 0) {
            // Miniature title bar with macOS traffic lights
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.red.opacity(0.9))
                    .frame(width: 6, height: 6)
                Circle()
                    .fill(Color.yellow.opacity(0.9))
                    .frame(width: 6, height: 6)
                Circle()
                    .fill(Color.green.opacity(0.9))
                    .frame(width: 6, height: 6)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(isDark ? Color(white: 0.22) : Color(white: 0.92))

            // Miniature split sidebar + grouped content area
            HStack(spacing: 0) {
                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.08))
                            .frame(height: 4)
                    }
                    Spacer(minLength: 0)
                }
                .padding(4)
                .frame(width: 22)
                .background(isDark ? Color(white: 0.18) : Color(white: 0.95))

                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.06))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                        .frame(height: 4)
                    Spacer(minLength: 0)
                }
                .padding(6)
                .frame(maxWidth: .infinity)
                .background(isDark ? Color(white: 0.14) : Color.white)
            }
        }
        .background(isDark ? Color(white: 0.14) : Color.white)
    }
}

/// Horizontal System / Light / Dark visual picker matching macOS System Settings and Snapzy.
struct AppearanceModePicker: View {
    @Binding var selection: GravAppearanceMode

    var body: some View {
        HStack(spacing: 10) {
            ForEach(GravAppearanceMode.allCases) { mode in
                AppearanceThumbnailView(
                    mode: mode,
                    isSelected: selection == mode
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = mode
                    }
                }
            }
        }
    }
}
