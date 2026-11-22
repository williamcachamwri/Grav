import SwiftUI

/// Staged entrance modifier ported 1:1 from Snapzy's `SnapzyEntranceModifier`.
public struct GravEntranceModifier: ViewModifier {
    public var index: Int
    public var appeared: Bool
    public var step: Double = 0.035

    private var motion: GravMotionPreferences {
        GravMotionPreferences.shared
    }

    public func body(content: Content) -> some View {
        if motion.reduceMotion {
            content
        } else {
            content
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)
                .animation(
                    motion.spec(.rise).animation.delay(motion.stagger(index, step: step)),
                    value: appeared
                )
        }
    }
}

public extension View {
    func gravEntrance(_ index: Int, appeared: Bool, step: Double = 0.035) -> some View {
        modifier(GravEntranceModifier(index: index, appeared: appeared, step: step))
    }
}
