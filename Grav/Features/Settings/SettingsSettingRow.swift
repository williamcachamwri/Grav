import AppKit
import SwiftUI

// MARK: - Setting Row (Ported 1:1 from Snapzy's PreferencesSettingRow)

/// Where a setting row's description is rendered.
enum SettingRowDescriptionStyle: Sendable {
    /// Static explanation revealed by hovering the ⓘ badge beside the title. Keeps rows single-line.
    case hint
    /// Live state the user should see at a glance (a path, a session count, a live metric).
    case subtitle
}

/// Reusable compact settings row: title with optional hover info popover or live subtitle,
/// trailing control content, and search-jump scroll anchor with accent highlight flash.
struct SettingRow<Content: View>: View {
    let title: String
    let description: String?
    var descriptionStyle: SettingRowDescriptionStyle = .hint
    var tooltip: String? = nil
    /// Use `.top` for tall trailing content (such as visual thumbnail pickers).
    var alignment: VerticalAlignment = .center
    @ViewBuilder let content: () -> Content

    @Environment(\.preferencesHighlightedSetting) private var highlightedSetting

    var body: some View {
        row
            .id(title)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(highlightedSetting == title ? 0.16 : 0))
                    .padding(.horizontal, -6)
                    .padding(.vertical, -4)
                    .animation(.easeInOut(duration: 0.35), value: highlightedSetting == title)
            }
    }

    private var row: some View {
        HStack(alignment: alignment, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let hintText {
                    Text(title)
                        .settingsHint(hintText, variant: .icon(.info))
                } else {
                    Text(title)
                }

                if descriptionStyle == .subtitle, let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
            content()
        }
    }

    private var hintText: String? {
        let hinted = descriptionStyle == .hint ? description : nil
        let parts = [hinted, tooltip].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }
}

// MARK: - Search Highlight Environment

private struct PreferencesHighlightedSettingKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// Title of the setting row currently flashing after a sidebar search jump.
    var preferencesHighlightedSetting: String? {
        get { self[PreferencesHighlightedSettingKey.self] }
        set { self[PreferencesHighlightedSettingKey.self] = newValue }
    }
}

// MARK: - Hover Hint Popover (Ported 1:1 from Snapzy's TooltipView)

enum SettingsHintIconStyle: Sendable {
    case info

    var systemImage: String {
        switch self {
        case .info: return "info.circle.fill"
        }
    }
}

enum SettingsHintVariant: Sendable {
    case inline
    case icon(SettingsHintIconStyle)
}

extension View {
    func settingsHint(_ text: String, variant: SettingsHintVariant = .inline) -> some View {
        modifier(SettingsHintModifier(text: text, variant: variant))
    }
}

private struct SettingsHintModifier: ViewModifier {
    let text: String
    let variant: SettingsHintVariant

    @State private var isHovering = false

    func body(content: Content) -> some View {
        switch variant {
        case .inline:
            content
                .onHover { hovering in isHovering = hovering }
                .popover(isPresented: $isHovering, arrowEdge: .bottom) {
                    SettingsHintPopoverContent(text: text)
                }

        case .icon(let style):
            HStack(spacing: 6) {
                content

                Image(systemName: style.systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .onHover { hovering in isHovering = hovering }
                    .popover(isPresented: $isHovering, arrowEdge: .bottom) {
                        SettingsHintPopoverContent(text: text)
                    }
            }
        }
    }
}

private struct SettingsHintPopoverContent: View {
    let text: String

    private static let fontSize: CGFloat = 11
    private static let maxTextWidth: CGFloat = 240
    private static let horizontalPadding: CGFloat = 10
    private static let verticalPadding: CGFloat = 6

    var body: some View {
        Text(text)
            .font(.system(size: Self.fontSize))
            .foregroundStyle(.primary)
            .lineLimit(nil)
            .frame(width: Self.textWidth(for: text), alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .fixedSize()
    }

    private static func textWidth(for text: String) -> CGFloat {
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: fontSize)]
        )
        return min(ceil(rect.width) + 2, maxTextWidth)
    }
}
