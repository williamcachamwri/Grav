import AppKit
import SwiftUI

// MARK: - Precision Setting Row

/// Where a setting row's description is rendered.
enum SettingRowDescriptionStyle: Sendable {
    /// Clean inline subtitle rendered directly under the title for immediate scannability.
    case hint
    /// Live telemetry state or path rendered directly under the title.
    case subtitle
}

/// Precision settings row used inside `SettingsCardGroup`:
/// clean two-line editorial typography, subtle hover wash, small macOS switch alignment,
/// and animated search-jump highlight flash.
struct SettingRow<Content: View>: View {
    let title: String
    let description: String?
    var descriptionStyle: SettingRowDescriptionStyle = .hint
    var tooltip: String? = nil
    /// Use `.top` for tall trailing content (such as visual thumbnail pickers).
    var alignment: VerticalAlignment = .center
    @ViewBuilder let content: () -> Content

    @Environment(\.preferencesHighlightedSetting) private var highlightedSetting
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var isHighlighted: Bool {
        highlightedSetting == title
    }

    var body: some View {
        HStack(alignment: alignment, spacing: 16) {
            VStack(alignment: .leading, spacing: 2.5) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 12.8, weight: .medium))
                        .foregroundStyle(.primary)

                    if let tooltip, !tooltip.isEmpty {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .help(tooltip)
                    }
                }

                if let description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 11.2, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            content()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .id(title)
        .background {
            if isHighlighted {
                Color.accentColor.opacity(0.14)
            } else if isHovering {
                Color.primary.opacity(0.024)
            } else {
                Color.clear
            }
        }
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: isHighlighted)
        .onHover { isHovering = $0 }
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
