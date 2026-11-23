import SwiftUI

// MARK: - Precision Settings Design System (Anti-AI-Slop macOS Craft)

/// Unified editorial page canvas for every Grav Settings pane.
/// Replaces rigid macOS `Form(.grouped)` tables with a fluid `ScrollView`, centered optical measure,
/// crisp page header with duotone tab icon, and subtle staggered 120Hz entrance choreography.
struct SettingsPageCanvas<Trailing: View, Content: View>: View {
    let tab: SettingsTab
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    init(
        tab: SettingsTab,
        title: String? = nil,
        subtitle: String,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.tab = tab
        self.title = title ?? tab.title
        self.subtitle = subtitle
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                pageHeader
                    .opacity(hasAppeared || reduceMotion ? 1 : 0)
                    .offset(y: hasAppeared || reduceMotion ? 0 : 6)
                    .animation(
                        reduceMotion ? nil : .spring(duration: 0.30, bounce: 0.08),
                        value: hasAppeared
                    )

                content()
            }
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 26)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .onAppear {
            hasAppeared = true
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            PreferencesSidebarIcon(tab: tab, size: 30, duotone: true)
                .shadow(color: Color.black.opacity(0.18), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 18.5, weight: .semibold))
                    .tracking(-0.35)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .layoutPriority(0)

            Spacer(minLength: 8)

            trailing()
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .padding(.bottom, 2)
    }
}

extension SettingsPageCanvas where Trailing == EmptyView {
    init(
        tab: SettingsTab,
        title: String? = nil,
        subtitle: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(tab: tab, title: title, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }
}

// MARK: - Precision Section Card Group

/// Matte layered card group with subtle top specular hairline, optional badge, and staggered spring reveal.
struct SettingsCardGroup<Content: View>: View {
    let title: String?
    var badge: String? = nil
    var staggerIndex: Int = 0
    var contentPadding: EdgeInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title, !title.isEmpty {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .tracking(0.1)
                        .foregroundStyle(.secondary)

                    if let badge, !badge.isEmpty {
                        Text(badge)
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.85))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 2)
            }

            VStack(spacing: 0) {
                content()
            }
            .padding(contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12.5, style: .continuous))
            .overlay(cardBorder)
        }
        .opacity(revealed || reduceMotion ? 1 : 0)
        .offset(y: revealed || reduceMotion ? 0 : 8)
        .animation(
            reduceMotion
                ? nil
                : .spring(duration: 0.34, bounce: 0.08).delay(Double(min(staggerIndex, 6)) * 0.028),
            value: revealed
        )
        .onAppear {
            revealed = true
        }
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12.5, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.036 : 0.028))

            // Delicate top architectural sheen (never neon, pure light-on-glass physics)
            RoundedRectangle(cornerRadius: 12.5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.028 : 0.35),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 12.5, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.09),
                        Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.05),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.75
            )
    }
}

/// Hairline divider indented neatly inside `SettingsCardGroup`.
struct SettingsRowDivider: View {
    var leadingInset: CGFloat = 14

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.068))
            .frame(height: 0.5)
            .padding(.leading, leadingInset)
    }
}

// MARK: - Tactile Precision Action Pill

/// Cohesive, single-line tactile button replacing clunky macOS default `.bordered` rectangles.
struct SettingsActionPill: View {
    let title: String
    var systemImage: String? = nil
    var prominent: Bool = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10.5, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(prominent ? Color.white : Color.primary.opacity(0.90))
            .padding(.horizontal, 11)
            .padding(.vertical, 5.5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        prominent
                            ? Color.accentColor.opacity(isHovering ? 0.92 : 1.0)
                            : Color.primary.opacity(isHovering ? 0.105 : 0.062)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                prominent ? Color.white.opacity(0.16) : Color.primary.opacity(isHovering ? 0.16 : 0.10),
                                lineWidth: 0.75
                            )
                    )
            )
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(PrecisionPressButtonStyle())
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
    }
}

/// Smooth 120Hz tactile press-scale feedback for precision buttons.
struct PrecisionPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.86 : 1.0)
            .animation(reduceMotion ? nil : .spring(duration: 0.18, bounce: 0.20), value: configuration.isPressed)
    }
}

// MARK: - Sliding Spring Segmented Pill

/// Ultra-smooth `matchedGeometryEffect` segmented pill control replacing rigid macOS Picker segments.
struct SettingsSegmentedPill<Option: Hashable & Identifiable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pillNamespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.26, bounce: 0.14)) {
                        selection = option
                    }
                } label: {
                    Text(label(option))
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                    .fill(Color.primary.opacity(0.12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                            .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.6)
                                    )
                                    .matchedGeometryEffect(id: "segmentedPill", in: pillNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2.5)
        .background(
            RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                .fill(Color.primary.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6)
                )
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Compact architectural telemetry metric tile used inside Telemetry & About hero strips.
struct SettingsMetricTile: View {
    let label: String
    let value: String
    var detail: String? = nil
    var accentDot: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if let accentDot {
                    Circle()
                        .fill(accentDot)
                        .frame(width: 5.5, height: 5.5)
                }
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.6)
                )
        )
    }
}
