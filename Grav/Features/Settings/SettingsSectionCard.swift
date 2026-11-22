import SwiftUI

/// Adaptive Light/Dark grouped card container for Grav's native macOS Settings UI.
public struct SettingsSectionCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    public var title: String
    public var systemImage: String?
    public var footer: String?
    private let content: Content

    public init(
        title: String,
        systemImage: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.footer = footer
        self.content = content()
    }

    public var body: some View {
        let palette = GravAdaptivePalette(colorScheme: colorScheme)

        VStack(alignment: .leading, spacing: GravSpacing.sm) {
            HStack(spacing: GravSpacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.inkTertiary)
                }

                Text(title)
                    .font(GravTypography.caption)
                    .foregroundStyle(palette.inkSecondary)
                    .textCase(.uppercase)
                    .tracking(0.45)
            }
            .padding(.horizontal, GravSpacing.xxs)

            VStack(spacing: 0) {
                content
            }
            .liquidGlassSurface(
                elevation: .base,
                radius: GravRadius.card,
                adaptive: true,
                includeBorder: true
            )

            if let footer, !footer.isEmpty {
                Text(footer)
                    .font(GravTypography.caption)
                    .foregroundStyle(palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, GravSpacing.xxs)
            }
        }
    }
}

/// Crisp `0.5pt` hairline separator between rows inside a `SettingsSectionCard`.
public struct SettingsRowDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    public var inset: CGFloat

    public init(inset: CGFloat = 14) {
        self.inset = inset
    }

    public var body: some View {
        let palette = GravAdaptivePalette(colorScheme: colorScheme)
        Rectangle()
            .fill(palette.divider)
            .frame(height: 0.5)
            .padding(.horizontal, inset)
    }
}

/// Generic two-column settings row with title, optional subtitle, and trailing control.
public struct SettingsControlRow<Control: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    public var title: String
    public var subtitle: String?
    private let control: Control

    public init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.subtitle = subtitle
        self.control = control()
    }

    public var body: some View {
        let palette = GravAdaptivePalette(colorScheme: colorScheme)

        HStack(alignment: .center, spacing: GravSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(GravTypography.bodyMedium)
                    .foregroundStyle(palette.inkPrimary)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(GravTypography.caption)
                        .foregroundStyle(palette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: GravSpacing.sm)

            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

/// Native macOS toggle row bound directly to a `Bool` preference.
public struct SettingsToggleRow: View {
    @Environment(\.colorScheme) private var colorScheme

    public var title: String
    public var subtitle: String?
    @Binding public var isOn: Bool

    public init(
        title: String,
        subtitle: String? = nil,
        isOn: Binding<Bool>
    ) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    public var body: some View {
        let palette = GravAdaptivePalette(colorScheme: colorScheme)

        SettingsControlRow(title: title, subtitle: subtitle) {
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .tint(palette.accentTeal)
        }
    }
}

/// Quiet inline status notice anchored with a `6pt` semantic dot and zero pill clutter.
public struct SettingsInlineNotice: View {
    @Environment(\.colorScheme) private var colorScheme

    public var tone: SemanticDotTone
    public var message: String

    public init(tone: SemanticDotTone, message: String) {
        self.tone = tone
        self.message = message
    }

    public var body: some View {
        let palette = GravAdaptivePalette(colorScheme: colorScheme)

        HStack(alignment: .firstTextBaseline, spacing: GravSpacing.sm) {
            SemanticDot(tone: tone, size: 6, isActive: false, showPulse: false, adaptive: true)
                .padding(.top, 2)

            Text(message)
                .font(GravTypography.caption)
                .foregroundStyle(palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(palette.fillSubtle)
    }
}
