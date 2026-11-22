import SwiftUI

/// Primary telemetry inspection tabs inside Grav's expanded Notch HUD (`Live | Reply | Files | Terminal`).
public enum NotchTab: Int, CaseIterable, Identifiable, Sendable, Hashable {
    case live = 0
    case reply = 1
    case files = 2
    case terminal = 3

    public var id: Int { rawValue }

    /// Concise monochrome label rendered in the segmented mode rail.
    public var title: String {
        switch self {
        case .live:
            return "Live"
        case .reply:
            return "Reply"
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
        case .reply:
            return "text.bubble"
        case .files:
            return "doc.text"
        case .terminal:
            return "terminal"
        }
    }

    /// 1-based numeric keyboard shortcut index (`1`, `2`, `3`, `4`).
    public var shortcutIndex: Int {
        rawValue + 1
    }

    /// Display string for tooltips and shortcuts.
    public var shortcutLabel: String {
        "\(shortcutIndex)"
    }

    /// Key equivalent used for single-key tab switching while the notch is expanded.
    public var keyEquivalent: KeyEquivalent {
        switch self {
        case .live:
            return "1"
        case .reply:
            return "2"
        case .files:
            return "3"
        case .terminal:
            return "4"
        }
    }
}
