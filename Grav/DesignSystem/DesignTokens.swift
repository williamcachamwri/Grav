import AppKit
import SwiftUI

// MARK: - Spacing (8pt Grid)

public enum Spacing {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
}

// MARK: - Sizing

public enum Size {
    public static let gridItem: CGFloat = 48
    public static let gridItemSmall: CGFloat = 40
    public static let colorSwatch: CGFloat = 32
    public static let colorSwatchSmall: CGFloat = 24

    public static let radiusXs = Radius.ornament
    public static let radiusSm: CGFloat = 6
    public static let radiusMd = Radius.tile
    public static let radiusLg = Radius.controlL

    public static let strokeDefault: CGFloat = 1
    public static let strokeSelected: CGFloat = 2
}

// MARK: - Typography

public enum Typography {
    public static let labelSmall: Font = .system(size: 10)
    public static let labelMedium: Font = .system(size: 11, weight: .medium)
    public static let sectionHeader: Font = .system(size: 11, weight: .semibold)
    public static let body: Font = .system(size: 12)
}

// MARK: - Semantic Sidebar Colors

public enum SidebarColors {
    public static let itemDefault = Color.primary.opacity(0.05)
    public static let itemHover = Color.primary.opacity(0.10)
    public static let itemSelected = Color.accentColor.opacity(0.15)

    public static let borderDefault = Color.secondary.opacity(0.3)
    public static let borderHover = Color.secondary.opacity(0.5)
    public static let borderSelected = Color.accentColor

    public static let labelPrimary = Color.primary
    public static let labelSecondary = Color.secondary
    public static let labelTertiary = Color.secondary.opacity(0.7)

    public static let actionButton = Color.primary.opacity(0.08)
    public static let actionButtonHover = Color.primary.opacity(0.15)
}

// MARK: - AppKit View Hierarchy Helper

public extension NSView {
    /// Depth-first search for the first descendant of the requested `NSView` subclass.
    func firstDescendant<T: NSView>(ofType type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T {
                return match
            }
            if let match = subview.firstDescendant(ofType: type) {
                return match
            }
        }
        return nil
    }
}
