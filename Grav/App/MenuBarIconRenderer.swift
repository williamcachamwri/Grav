import AppKit

/// Template icon renderer for Grav's macOS menu bar `NSStatusItem`.
/// Uses the exact sweeping G/A silhouette extracted from Grav's app logo (`GravMarkTemplate`)
/// with `isTemplate = true` so macOS renders crisp native vibrancy across Light & Dark menu bars.
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
        let templateAsset = NSImage(named: "GravMarkTemplate")

        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }

            context.saveGState()
            defer { context.restoreGState() }

            let alphaScale: CGFloat = state == .paused ? 0.45 : 1.0
            let inset = rect.width * 0.08
            let glyphRect = rect.insetBy(dx: inset, dy: inset)

            if let templateAsset {
                templateAsset.draw(
                    in: glyphRect,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: alphaScale,
                    respectFlipped: true,
                    hints: [.interpolation: NSImageInterpolation.high]
                )
            } else {
                // Clean vector fallback for unit-test environments without asset catalog
                let s = glyphRect.width
                let ox = glyphRect.minX
                let oy = glyphRect.minY
                context.setStrokeColor(NSColor.black.withAlphaComponent(alphaScale).cgColor)
                context.setLineWidth(max(1.8, s * 0.16))
                context.setLineCap(.round)
                context.setLineJoin(.round)

                context.beginPath()
                context.move(to: CGPoint(x: ox + s * 0.14, y: oy + s * 0.18))
                context.addQuadCurve(
                    to: CGPoint(x: ox + s * 0.80, y: oy + s * 0.64),
                    control: CGPoint(x: ox + s * 0.42, y: oy + s * 0.92)
                )
                context.strokePath()

                context.beginPath()
                context.move(to: CGPoint(x: ox + s * 0.50, y: oy + s * 0.44))
                context.addLine(to: CGPoint(x: ox + s * 0.82, y: oy + s * 0.44))
                context.addQuadCurve(
                    to: CGPoint(x: ox + s * 0.68, y: oy + s * 0.18),
                    control: CGPoint(x: ox + s * 0.84, y: oy + s * 0.28)
                )
                context.strokePath()
            }

            // Quiet active telemetry dot at top-right corner strictly when active
            if state == .active {
                let dotSize = max(2.8, rect.width * 0.18)
                context.setFillColor(NSColor.black.withAlphaComponent(alphaScale).cgColor)
                context.fillEllipse(
                    in: CGRect(
                        x: rect.maxX - dotSize - 0.5,
                        y: rect.maxY - dotSize - 0.5,
                        width: dotSize,
                        height: dotSize
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
