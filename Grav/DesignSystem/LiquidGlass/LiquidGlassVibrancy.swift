import AppKit
import SwiftUI

/// AppKit visual effect view bridge for HUD window vibrancy and borderless glass backdrops.
public struct LiquidGlassVibrancyBackdrop: NSViewRepresentable {
    public var material: NSVisualEffectView.Material = .hudWindow
    public var blending: NSVisualEffectView.BlendingMode = .behindWindow

    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blending: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blending = blending
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        if nsView.material != material {
            nsView.material = material
        }
        if nsView.blendingMode != blending {
            nsView.blendingMode = blending
        }
        if nsView.state != .active {
            nsView.state = .active
        }
    }
}
