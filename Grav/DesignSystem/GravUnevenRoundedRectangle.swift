import SwiftUI

/// Per-corner radii ported 1:1 from Snapzy's `SnapzyCornerRadii`.
public struct GravCornerRadii: Equatable, Sendable {
    public var topLeading: CGFloat
    public var bottomLeading: CGFloat
    public var bottomTrailing: CGFloat
    public var topTrailing: CGFloat

    public init(
        topLeading: CGFloat = 0,
        bottomLeading: CGFloat = 0,
        bottomTrailing: CGFloat = 0,
        topTrailing: CGFloat = 0
    ) {
        self.topLeading = topLeading
        self.bottomLeading = bottomLeading
        self.bottomTrailing = bottomTrailing
        self.topTrailing = topTrailing
    }
}

/// Custom `InsettableShape` with independent per-corner radii, matching Snapzy's `SnapzyUnevenRoundedRectangle`.
public struct GravUnevenRoundedRectangle: Shape, InsettableShape {
    public var cornerRadii: GravCornerRadii
    public var insetAmount: CGFloat = 0

    public init(cornerRadii: GravCornerRadii) {
        self.cornerRadii = cornerRadii
    }

    public func inset(by amount: CGFloat) -> GravUnevenRoundedRectangle {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    public func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let w = insetRect.width
        let h = insetRect.height

        let tl = max(0, min(cornerRadii.topLeading - insetAmount, min(w, h) / 2))
        let tr = max(0, min(cornerRadii.topTrailing - insetAmount, min(w, h) / 2))
        let br = max(0, min(cornerRadii.bottomTrailing - insetAmount, min(w, h) / 2))
        let bl = max(0, min(cornerRadii.bottomLeading - insetAmount, min(w, h) / 2))

        var path = Path()
        path.move(to: CGPoint(x: insetRect.minX + tl, y: insetRect.minY))

        path.addLine(to: CGPoint(x: insetRect.maxX - tr, y: insetRect.minY))
        if tr > 0 {
            path.addArc(
                center: CGPoint(x: insetRect.maxX - tr, y: insetRect.minY + tr),
                radius: tr,
                startAngle: Angle(degrees: -90),
                endAngle: Angle(degrees: 0),
                clockwise: false
            )
        }

        path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.maxY - br))
        if br > 0 {
            path.addArc(
                center: CGPoint(x: insetRect.maxX - br, y: insetRect.maxY - br),
                radius: br,
                startAngle: Angle(degrees: 0),
                endAngle: Angle(degrees: 90),
                clockwise: false
            )
        }

        path.addLine(to: CGPoint(x: insetRect.minX + bl, y: insetRect.maxY))
        if bl > 0 {
            path.addArc(
                center: CGPoint(x: insetRect.minX + bl, y: insetRect.maxY - bl),
                radius: bl,
                startAngle: Angle(degrees: 90),
                endAngle: Angle(degrees: 180),
                clockwise: false
            )
        }

        path.addLine(to: CGPoint(x: insetRect.minX, y: insetRect.minY + tl))
        if tl > 0 {
            path.addArc(
                center: CGPoint(x: insetRect.minX + tl, y: insetRect.minY + tl),
                radius: tl,
                startAngle: Angle(degrees: 180),
                endAngle: Angle(degrees: 270),
                clockwise: false
            )
        }

        path.closeSubpath()
        return path
    }
}
