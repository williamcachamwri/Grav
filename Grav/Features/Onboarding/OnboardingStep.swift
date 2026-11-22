import Foundation

/// Top-level onboarding presentation phase separating the full-bleed welcome choreography
/// from the structured three-step Dark Liquid Glass setup shell.
public enum OnboardingPhase: String, Sendable, Equatable {
    case welcome
    case steps
}

/// Navigational direction used to drive directional transitions between onboarding steps.
public enum OnboardingFlowDirection: Sendable, Equatable {
    case forward
    case backward
}

/// Ordered setup steps within the Grav onboarding shell.
public enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable, Equatable {
    case connect = 0
    case notchPreview = 1
    case preferences = 2

    public var id: Int { rawValue }

    /// Zero-based index for progress layout math.
    public var index: Int { rawValue }

    /// One-based step number for user-facing labels.
    public var stepNumber: Int { rawValue + 1 }

    public var title: String {
        switch self {
        case .connect:
            return "Connect to Antigravity"
        case .notchPreview:
            return "Meet Your Notch HUD"
        case .preferences:
            return "Preferences & Startup"
        }
    }

    public var shortTitle: String {
        switch self {
        case .connect:
            return "Connect"
        case .notchPreview:
            return "Notch HUD"
        case .preferences:
            return "Preferences"
        }
    }

    public var subtitle: String {
        switch self {
        case .connect:
            return "Verify your local Antigravity installation and live telemetry channel from ~/.gemini/antigravity/brain."
        case .notchPreview:
            return "Grav fuses into your MacBook notch to surface reasoning, file diffs, and live command logs without breaking flow."
        case .preferences:
            return "Tune startup behavior, automatic telemetry peeks, and how your notch responds to pointer focus."
        }
    }

    public var primaryActionTitle: String {
        switch self {
        case .connect, .notchPreview:
            return "Continue"
        case .preferences:
            return "Start Using Grav"
        }
    }

    public var isFirst: Bool {
        self == Self.allCases.first
    }

    public var isLast: Bool {
        self == Self.allCases.last
    }

    public var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    public var previous: OnboardingStep? {
        OnboardingStep(rawValue: rawValue - 1)
    }
}
