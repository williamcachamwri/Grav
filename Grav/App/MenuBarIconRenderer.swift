import AppKit

/// Programmatic monochrome template icon renderer for Grav's macOS menu bar `NSStatusItem`.
/// Mirrors `GravOrbitalMark`'s industrial geometric silhouette using `isTemplate = true`
/// so macOS renders crisp vibrancy across Light Mode, Dark Mode, and desktop wallpapers.
public enum MenuBarIconRenderer {
    public enum VisualState: Sendable, Equatable {
        case idle
        case active
        case paused
    }

    public static func makeIcon(
        state: VisualState = .idle,
        pointSize: CGFloat = 18
    ) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }

            context.saveGState()
            defer { context.restoreGState() }

            let center = CGPoint(x: rect.midX, y: rect.midY)
            let unit = min(rect.width, rect.height)
            let alphaScale: CGFloat = state == .paused ? 0.48 : 1.0
            let strokeWidth = max(1.25, unit * 0.082)

            let primaryInk = NSColor.black.withAlphaComponent(alphaScale).cgColor
            let secondaryInk = NSColor.black.withAlphaComponent(0.80 * alphaScale).cgColor

            // Outer 270-degree precision telemetry arc (matching GravOrbitalMark)
            context.setStrokeColor(primaryInk)
            context.setLineWidth(strokeWidth)
            context.setLineCap(.round)

            let outerRadius = unit * 0.40
            // Non-flipped Core Graphics coordinates (positive angles counter-clockwise)
            context.beginPath()
            context.addArc(
                center: center,
                radius: outerRadius,
                startAngle: -.pi * 0.92,
                endAngle: .pi * 0.75,
                clockwise: false
            )
            context.strokePath()

            // Inner tilted orbital ellipse
            context.saveGState()
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: .pi / 5.5)
            context.setStrokeColor(secondaryInk)
            context.setLineWidth(strokeWidth * 0.82)

            let ellipseRect = CGRect(
                x: -unit * 0.27,
                y: -unit * 0.135,
                width: unit * 0.54,
                height: unit * 0.27
            )
            context.strokeEllipse(in: ellipseRect)
            context.restoreGState()

            // Core gravity singularity dot
            context.setFillColor(primaryInk)
            let coreRadius = unit * (state == .active ? 0.125 : 0.105)
            let coreRect = CGRect(
                x: center.x - coreRadius,
                y: center.y - coreRadius,
                width: coreRadius * 2,
                height: coreRadius * 2
            )
            context.fillEllipse(in: coreRect)

            // Orbital telemetry satellite node at arc terminus
            let satAngle: CGFloat = .pi * 0.75
            let satCenter = CGPoint(
                x: center.x + cos(satAngle) * outerRadius,
                y: center.y + sin(satAngle) * outerRadius
            )
            let satRadius = max(1.25, unit * (state == .active ? 0.085 : 0.068))
            let satRect = CGRect(
                x: satCenter.x - satRadius,
                y: satCenter.y - satRadius,
                width: satRadius * 2,
                height: satRadius * 2
            )
            context.fillEllipse(in: satRect)

            return true
        }

        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription(for: state)
        return image
    }

    private static func accessibilityDescription(for state: VisualState) -> String {
        switch state {
        case .idle: return "Grav Telemetry Idle"
        case .active: return "Grav Telemetry Active"
        case .paused: return "Grav Telemetry Paused"
        }
    }
}
