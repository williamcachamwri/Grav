import SwiftUI

/// Primary telemetry inspection tabs inside Grav's expanded Notch HUD.
public enum NotchTab: Int, CaseIterable, Identifiable, Sendable, Hashable {
    case live = 0
    case files = 1
    case terminal = 2

    public var id: Int { rawValue }

    /// Concise monochrome label rendered in the segmented mode rail.
    public var title: String {
        switch self {
        case .live:
            return "Live"
        case .files:
            return "Files"
        case .terminal:
            return "Terminal"
        }
    }

    /// Monochrome SF Symbol identifier paired with the tab label.
    public var symbolName: String {
        switch self {
        case .live:
            return "waveform.path.ecg"
        case .files:
            return "doc.text"
        case .terminal:
            return "terminal"
        }
    }

    /// 1-based numeric keyboard shortcut index (`1`, `2`, `3`).
    public var shortcutIndex: Int {
        rawValue + 1
    }

    /// Display string for the numeric keycap indicator.
    public var shortcutLabel: String {
        "\(shortcutIndex)"
    }

    /// Key equivalent used for single-key tab switching while the notch is expanded.
    public var keyEquivalent: KeyEquivalent {
        switch self {
        case .live:
            return "1"
        case .files:
            return "2"
        case .terminal:
            return "3"
        }
    }
}
