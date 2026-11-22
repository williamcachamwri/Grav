import SwiftUI

/// Corner-radius scale ported 1:1 from Snapzy's `RadiusTokens`.
/// Roundness is proportional to control height (`~0.36 × height`), while containers use fixed semantic values.
public enum Radius {
    // MARK: Controls (proportional — ~0.36 × height)

    /// h ≤ 19 — keycaps, inline badges, mini toggles.
    public static let controlXS: CGFloat = 6
    /// h 20–25 — property-bar chips, segment buttons, small selects.
    public static let controlS: CGFloat = 8
    /// h 26–30 — toolbar and bottom-bar icon buttons, selects, text fields.
    public static let controlM: CGFloat = 10
    /// h 31–36 — prominent actions, sidebar rows.
    public static let controlL: CGFloat = 12
    /// h ≥ 37 — oversized touch targets and action tiles.
    public static let controlXL: CGFloat = 14

    public static let controlRamp: [CGFloat] = [controlXS, controlS, controlM, controlL, controlXL]
    public static let controlRoundness: CGFloat = 0.36

    // MARK: Containers (semantic — fixed)

    /// Badges, keycap plates, hairline frames.
    public static let ornament: CGFloat = 4
    /// Grid thumbnails, preset tiles, inline previews.
    public static let tile: CGFloat = 8
    /// Cards, list rows, floating bars.
    public static let card: CGFloat = 14
    /// Popovers, inspectors, sheets.
    public static let panel: CGFloat = 20
    /// Window backdrops.
    public static let window: CGFloat = 26

    // MARK: Lookup

    public static func control(forHeight height: CGFloat) -> CGFloat {
        let target = height * controlRoundness
        guard let first = controlRamp.first else { return controlM }
        return controlRamp.dropFirst().reduce(first) { best, candidate in
            abs(candidate - target) < abs(best - target) ? candidate : best
        }
    }

    public static func rect(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    public static func controlRect(forHeight height: CGFloat) -> RoundedRectangle {
        rect(control(forHeight: height))
    }
}

/// Shared chrome control heights paired with `Radius`.
public enum ControlMetrics {
    public static let toolbarButton: CGFloat = 28
    public static let propertyChip: CGFloat = 24
    public static let bottomBarControl: CGFloat = toolbarButton
}
