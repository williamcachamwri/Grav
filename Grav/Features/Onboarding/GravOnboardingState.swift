//
//  GravOnboardingState.swift
//  Grav
//
//  Step models, interactive challenges, and observable state manager for Grav onboarding,
//  ported 1:1 from Snapzy's `SnapzyOnboardingStep` + `SnapzyOnboardingState`.
//

import Combine
import Foundation
import SwiftUI

// MARK: - Steps & Challenges

enum GravOnboardingStep: String, CaseIterable, Identifiable, Hashable, Sendable {
    case connect
    case notchHud
    case miniPet
    case preferences

    var id: String { rawValue }

    var stepNumber: Int {
        switch self {
        case .connect: return 1
        case .notchHud: return 2
        case .miniPet: return 3
        case .preferences: return 4
        }
    }

    var shortTitle: String {
        switch self {
        case .connect: return "Connect"
        case .notchHud: return "Notch HUD"
        case .miniPet: return "Mini Pet"
        case .preferences: return "Preferences"
        }
    }

    var title: String {
        switch self {
        case .connect: return "Connect to Antigravity"
        case .notchHud: return "Meet Your Notch HUD"
        case .miniPet: return "Customize Your Mini Pet"
        case .preferences: return "Preferences & Startup"
        }
    }

    var subtitle: String {
        switch self {
        case .connect:
            return "Grav reads Antigravity's local telemetry stream directly from disk — zero proxies, zero background polling, zero overhead."
        case .notchHud:
            return "Live agent reasoning, file diffs, and shell output stay tucked inside your MacBook notch until you glance or hover."
        case .miniPet:
            return "Float a crisp pixel companion from codex-pets.net right on your desktop — reacting live with a status bubble as Antigravity works."
        case .preferences:
            return "Tune how Grav starts up, peeks on telemetry events, and renders macOS Liquid Glass chrome."
        }
    }

    var symbol: String {
        switch self {
        case .connect: return "antenna.radiowaves.left.and.right"
        case .notchHud: return "macbook"
        case .miniPet: return "pawprint.fill"
        case .preferences: return "slider.horizontal.3"
        }
    }

    var examplePrompt: String {
        switch self {
        case .connect:
            return "Click Refresh on the right to verify Antigravity and local telemetry access."
        case .notchHud:
            return "Hover or click the miniature MacBook notch on the right to expand the 3-tab HUD."
        case .miniPet:
            return "Test a live pet animation state or tweak placement & size on the right."
        case .preferences:
            return "Toggle any preference in System Settings on the right — changes apply live."
        }
    }

    var tip: String {
        switch self {
        case .connect:
            return "Grav watches ~/.gemini/antigravity/brain/ using kernel kqueue events so idle CPU stays at 0%."
        case .notchHud:
            return "While the Notch HUD is open, press 1, 2, or 3 to jump straight between Thinking, File Diffs, and Terminal Logs."
        case .miniPet:
            return "Search and download new pets from codex-pets.net or export transparent GIFs anytime in Settings → Mini Pet."
        case .preferences:
            return "You can adjust any of these later from the menu bar icon or by pressing ⌘,."
        }
    }

    var challenges: [GravOnboardingChallenge] {
        switch self {
        case .connect:
            return [.detectAntigravity, .verifyBrainAccess]
        case .notchHud:
            return [.expandNotchPreview, .inspectTelemetryTabs]
        case .miniPet:
            return [.testMiniPetAnimation, .customizeMiniPet]
        case .preferences:
            return [.reviewPreferences]
        }
    }
}

enum GravOnboardingChallenge: String, CaseIterable, Identifiable, Hashable, Sendable {
    case detectAntigravity
    case verifyBrainAccess
    case expandNotchPreview
    case inspectTelemetryTabs
    case testMiniPetAnimation
    case customizeMiniPet
    case reviewPreferences

    var id: String { rawValue }

    var label: String {
        switch self {
        case .detectAntigravity:
            return "Detect Antigravity installation"
        case .verifyBrainAccess:
            return "Confirm read access to local telemetry"
        case .expandNotchPreview:
            return "Expand the interactive Notch HUD"
        case .inspectTelemetryTabs:
            return "Explore Thinking, File Diffs & Logs"
        case .testMiniPetAnimation:
            return "Preview a live Mini Pet animation state"
        case .customizeMiniPet:
            return "Tune position, size, or status bubble"
        case .reviewPreferences:
            return "Review startup & HUD behavior"
        }
    }

    var keys: [String] {
        switch self {
        case .detectAntigravity: return ["⌘R"]
        case .verifyBrainAccess: return []
        case .expandNotchPreview: return ["Space"]
        case .inspectTelemetryTabs: return ["1", "2", "3"]
        case .testMiniPetAnimation: return []
        case .customizeMiniPet: return []
        case .reviewPreferences: return ["⌘,"]
        }
    }
}

enum GravMockNotchTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case live
    case reply
    case files
    case terminal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: return "Live"
        case .reply: return "Reply"
        case .files: return "Files"
        case .terminal: return "Terminal"
        }
    }

    var shortTitle: String { title }

    var symbol: String {
        switch self {
        case .live: return "waveform.path.ecg"
        case .reply: return "text.bubble"
        case .files: return "doc.text"
        case .terminal: return "terminal"
        }
    }

    var badgeCount: String {
        switch self {
        case .live: return "24"
        case .reply: return "8"
        case .files: return "12"
        case .terminal: return "6"
        }
    }

    var keyLabel: String {
        switch self {
        case .live: return "1"
        case .reply: return "2"
        case .files: return "3"
        case .terminal: return "4"
        }
    }
}

// MARK: - Observable State

@MainActor
final class GravOnboardingState: ObservableObject {
    enum NavigationDirection { case forward, backward }

    @Published var currentStep: GravOnboardingStep = .connect
    @Published var completedSteps: Set<GravOnboardingStep> = []
    @Published var completedChallenges: Set<GravOnboardingChallenge> = []
    private(set) var navigationDirection: NavigationDirection = .forward
    private(set) var navigationDistance: Int = 1
    @Published var isStageInFlight: Bool = false

    // Step 1: Connect feedback state
    @Published var lastRefreshTimestamp: Date?

    // Step 2: Interactive 1:1 MacBook Notch state
    @Published var isMockNotchExpanded: Bool = false
    @Published var selectedMockNotchTab: GravMockNotchTab = .live
    @Published var visitedMockTabs: Set<GravMockNotchTab> = []

    // Step 3: Mini Pet live preview state
    @Published var miniPetPreviewState: CodexPetAnimationState = .idle

    // Step 4: Preferences feedback state
    @Published var hasReviewedPreferences: Bool = false

    var isCurrentStepComplete: Bool {
        let required = currentStep.challenges
        return required.allSatisfy { completedChallenges.contains($0) }
    }

    var canGoBack: Bool {
        currentStep.stepNumber > 1
    }

    var canGoForward: Bool {
        currentStep.stepNumber < GravOnboardingStep.allCases.count
    }

    func reset() {
        currentStep = .connect
        completedSteps = []
        completedChallenges = []
        navigationDirection = .forward
        navigationDistance = 1
        isStageInFlight = false
        lastRefreshTimestamp = nil
        isMockNotchExpanded = false
        selectedMockNotchTab = .live
        visitedMockTabs = []
        miniPetPreviewState = .idle
        hasReviewedPreferences = false
    }

    func markCurrentStepVisited() {
        withAnimation(GravMotionPreferences.shared.spec(.settle).animation) {
            _ = completedSteps.insert(currentStep)
        }
    }

    func completeChallenge(_ challenge: GravOnboardingChallenge) {
        let wasCompleted = completedChallenges.contains(challenge)
        withAnimation(GravMotionPreferences.shared.spec(.settle).animation) {
            completedChallenges.insert(challenge)
            if isCurrentStepComplete {
                completedSteps.insert(currentStep)
            }
        }
        if !wasCompleted {
            GravOnboardingWelcomeAudio.shared.playChallengeComplete()
        }
    }

    func setChallenge(_ challenge: GravOnboardingChallenge, completed: Bool) {
        guard completedChallenges.contains(challenge) != completed else { return }
        withAnimation(GravMotionPreferences.shared.spec(.settle).animation) {
            if completed {
                completedChallenges.insert(challenge)
                if isCurrentStepComplete {
                    completedSteps.insert(currentStep)
                }
            } else {
                completedChallenges.remove(challenge)
                completedSteps.remove(currentStep)
            }
        }
    }

    func nextStep() {
        guard let currentIndex = GravOnboardingStep.allCases.firstIndex(of: currentStep),
              currentIndex + 1 < GravOnboardingStep.allCases.count else { return }
        transition(to: GravOnboardingStep.allCases[currentIndex + 1])
    }

    func previousStep() {
        guard let currentIndex = GravOnboardingStep.allCases.firstIndex(of: currentStep),
              currentIndex > 0 else { return }
        transition(to: GravOnboardingStep.allCases[currentIndex - 1])
    }

    func transition(to step: GravOnboardingStep) {
        guard step != currentStep else { return }
        navigationDirection = step.stepNumber < currentStep.stepNumber ? .backward : .forward
        navigationDistance = abs(step.stepNumber - currentStep.stepNumber)

        if navigationDirection == .forward {
            GravOnboardingWelcomeAudio.shared.playStepForward()
        } else {
            GravOnboardingWelcomeAudio.shared.playStepBackward()
        }

        var resetTx = Transaction()
        resetTx.disablesAnimations = true
        withTransaction(resetTx) {
            isStageInFlight = true
            resetTransientState(for: step)
        }

        withAnimation(GravMotionPreferences.shared.spec(.morph).animation) {
            currentStep = step
        }
    }

    private func resetTransientState(for step: GravOnboardingStep) {
        switch step {
        case .connect:
            break
        case .notchHud:
            isMockNotchExpanded = false
            selectedMockNotchTab = .live
        case .miniPet:
            break
        case .preferences:
            break
        }
    }

    // MARK: - Live Step Actions

    func syncConnectionStatus(_ status: AntigravityConnectionStatus) {
        setChallenge(.detectAntigravity, completed: status.isAppInstalled)
        setChallenge(.verifyBrainAccess, completed: status.isBrainAccessible)
    }

    func recordConnectionRefresh(_ status: AntigravityConnectionStatus) {
        lastRefreshTimestamp = Date()
        syncConnectionStatus(status)
    }

    func toggleMockNotchExpanded() {
        withAnimation(GravMotionPreferences.shared.spec(.morph).animation) {
            isMockNotchExpanded.toggle()
            if isMockNotchExpanded {
                completeChallenge(.expandNotchPreview)
                visitedMockTabs.insert(selectedMockNotchTab)
            }
        }
    }

    func setMockNotchExpanded(_ expanded: Bool) {
        guard isMockNotchExpanded != expanded else { return }
        withAnimation(GravMotionPreferences.shared.spec(.morph).animation) {
            isMockNotchExpanded = expanded
            if expanded {
                completeChallenge(.expandNotchPreview)
                visitedMockTabs.insert(selectedMockNotchTab)
            }
        }
    }

    func selectMockNotchTab(_ tab: GravMockNotchTab) {
        withAnimation(GravMotionPreferences.shared.spec(.settle).animation) {
            if !isMockNotchExpanded {
                isMockNotchExpanded = true
                completeChallenge(.expandNotchPreview)
            }
            selectedMockNotchTab = tab
            visitedMockTabs.insert(tab)
            if visitedMockTabs.count >= 2 {
                completeChallenge(.inspectTelemetryTabs)
            }
        }
    }

    func advanceMockNotchDemo() {
        if !isMockNotchExpanded {
            setMockNotchExpanded(true)
            return
        }
        let all = GravMockNotchTab.allCases
        if let idx = all.firstIndex(of: selectedMockNotchTab) {
            let next = all[(idx + 1) % all.count]
            selectMockNotchTab(next)
        }
    }

    func selectMiniPetPreviewState(_ newState: CodexPetAnimationState) {
        miniPetPreviewState = newState
        completeChallenge(.testMiniPetAnimation)
    }

    func markMiniPetCustomized() {
        completeChallenge(.customizeMiniPet)
    }

    func markPreferencesReviewed() {
        hasReviewedPreferences = true
        completeChallenge(.reviewPreferences)
    }
}
