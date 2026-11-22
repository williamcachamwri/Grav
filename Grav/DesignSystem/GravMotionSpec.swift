import AppKit
import SwiftUI

/// Motion and animation token specifications ported 1:1 from Snapzy's `SnapzyMotionSpec`.
public struct GravMotionSpec: Equatable, Sendable {
    public var duration: Double
    public var curve: Curve

    public enum Curve: Equatable, Sendable {
        case custom(Double, Double, Double, Double)
        case spring(bounce: Double)
        case easeInOut
        case easeOut
        case easeIn
        case linear
    }

    public init(duration: Double, curve: Curve) {
        self.duration = duration
        self.curve = curve
    }

    public var animation: Animation {
        switch curve {
        case let .custom(a, b, c, d):
            return .timingCurve(a, b, c, d, duration: duration)
        case let .spring(bounce):
            return .spring(duration: duration, bounce: bounce)
        case .easeInOut:
            return .easeInOut(duration: duration)
        case .easeOut:
            return .easeOut(duration: duration)
        case .easeIn:
            return .easeIn(duration: duration)
        case .linear:
            return .linear(duration: duration)
        }
    }

    public func respectingReduceMotion(_ reduce: Bool) -> GravMotionSpec {
        reduce ? GravMotionSpec(duration: 0, curve: .linear) : self
    }

    public var timingFunction: CAMediaTimingFunction? {
        switch curve {
        case let .custom(a, b, c, d):
            CAMediaTimingFunction(controlPoints: Float(a), Float(b), Float(c), Float(d))
        case .easeInOut:
            CAMediaTimingFunction(name: .easeInEaseOut)
        case .easeOut:
            CAMediaTimingFunction(name: .easeOut)
        case .easeIn:
            CAMediaTimingFunction(name: .easeIn)
        case .linear:
            CAMediaTimingFunction(name: .linear)
        case .spring:
            nil
        }
    }

    // MARK: - Named Vocabulary (Exact Snapzy Parity)

    public static let morph = GravMotionSpec(duration: 0.42, curve: .spring(bounce: 0.45))
    public static let anticipation = GravMotionSpec(duration: 0.13, curve: .easeOut)
    public static let glide = GravMotionSpec(duration: 0.45, curve: .custom(0.22, 0.9, 0.24, 1))
    public static let contentIn = GravMotionSpec(duration: 0.22, curve: .easeOut)
    public static let contentOut = GravMotionSpec(duration: 0.12, curve: .easeIn)
    public static let hover = GravMotionSpec(duration: 0.12, curve: .easeOut)
    public static let settle = GravMotionSpec(duration: 0.4, curve: .spring(bounce: 0.22))
    public static let instant = GravMotionSpec(duration: 0, curve: .linear)

    /// Staged entrances: strong ease-out arriving quickly and landing softly.
    public static let rise = GravMotionSpec(duration: 0.26, curve: .custom(0.23, 1, 0.32, 1))
    /// Marker state changes — circle filling, number becoming a check.
    public static let pop = GravMotionSpec(duration: 0.3, curve: .spring(bounce: 0.3))
}

@MainActor
public final class GravMotionPreferences {
    public static let shared = GravMotionPreferences()
    public static var reduceMotionOverride: Bool?

    public var reduceMotion: Bool {
        Self.reduceMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    public func spec(_ base: GravMotionSpec) -> GravMotionSpec {
        base.respectingReduceMotion(reduceMotion)
    }

    public func stagger(_ index: Int, step: Double = 0.035) -> Double {
        reduceMotion ? 0 : Double(max(index, 0)) * step
    }
}
