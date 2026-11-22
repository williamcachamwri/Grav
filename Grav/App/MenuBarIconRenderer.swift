import AppKit

/// Programmatic monochrome template icon renderer for Grav's macOS menu bar `NSStatusItem`.
/// Mirrors `GravOrbitalMark`'s Apple-style interlocking 3-beam Delta-Arc silhouette using
/// `isTemplate = true` so macOS renders crisp vibrancy across Light and Dark menu bars.
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

            let cx = rect.midX
            let cy = rect.midY
            let unit = min(rect.width, rect.height)
            let alphaScale: CGFloat = state == .paused ? 0.48 : 1.0
            let beamWidth = max(1.4, unit * 0.13)

            let primaryInk = NSColor.black.withAlphaComponent(alphaScale).cgColor
            let secondaryInk = NSColor.black.withAlphaComponent(0.76 * alphaScale).cgColor

            context.setLineCap(.round)
            context.setLineJoin(.round)

            // 1. Horizontal crossbar beam
            context.setStrokeColor(secondaryInk)
            context.setLineWidth(beamWidth * 0.92)
            context.beginPath()
            context.move(to: CGPoint(x: cx - unit * 0.30, y: cy - unit * 0.12))
            context.addLine(to: CGPoint(x: cx + unit * 0.30, y: cy - unit * 0.12))
            context.strokePath()

            // 2. Left ascending Delta beam
            context.setStrokeColor(primaryInk)
            context.setLineWidth(beamWidth)
            context.beginPath()
            context.move(to: CGPoint(x: cx - unit * 0.24, y: cy - unit * 0.30))
            context.addLine(to: CGPoint(x: cx + unit * 0.05, y: cy + unit * 0.32))
            context.strokePath()

            // 3. Right ascending Delta beam
            context.beginPath()
            context.move(to: CGPoint(x: cx - unit * 0.05, y: cy + unit * 0.32))
            context.addLine(to: CGPoint(x: cx + unit * 0.24, y: cy - unit * 0.30))
            context.strokePath()

            // 4. Active telemetry beacon dot at top-right when streaming
            if state == .active {
                let dotR = max(1.5, unit * 0.11)
                context.setFillColor(primaryInk)
                context.fillEllipse(
                    in: CGRect(
                        x: cx + unit * 0.24,
                        y: cy + unit * 0.22,
                        width: dotR * 2,
                        height: dotR * 2
                    )
                )
            }

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
