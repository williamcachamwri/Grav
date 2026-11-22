//
//  GravOnboardingWelcomeAudio.swift
//  Grav
//
//  Original procedural stereo Antigravity soundscape & physically-modeled tactile micro-foley.
//  - Welcome Score: Zero-G F#-Lydian levitation pad (F#maj9#11 → Bmaj9#11 → D#m11 → F#maj9),
//    upward harmonic lift sweep, celesta-glass prism chimes, and diffused Schroeder all-pass hall reverb.
//  - Tactile UI Foley: Physically-modeled Force-Touch / ceramic-glass micro-transients
//    (pitch-swept actuator body + bandpass contact impulse — zero synthetic sine beeps).
//  Gated by `GravPreferenceKeys.playSounds` and synthesized off the main actor.
//

import AVFoundation
import Foundation

@MainActor
final class GravOnboardingWelcomeAudio {
    static let shared = GravOnboardingWelcomeAudio()

    private enum CueKey: Hashable, Sendable {
        case hoverTick
        case confirmChime
        case completionChime
        case stepForward
        case stepBackward
        case stepComplete
        case buttonTap
        case tabSwitch
        case challengeTick
        case shutterSnap
    }

    private var ambientPlayer: AVAudioPlayer?
    private var fadingPlayers: [ObjectIdentifier: (player: AVAudioPlayer, task: Task<Void, Never>)] = [:]
    private let effectVoices = OnboardingEffectVoicePool()
    private var synthesisTask: Task<Void, Never>?
    private var prewarmTask: Task<Void, Never>?

    private var cachedFullScoreWAV: Data?
    private var cachedReducedScoreWAV: Data?
    private var cachedCueWAVs: [CueKey: Data] = [:]

    private init() {}

    nonisolated deinit {}

    private var soundsEnabled: Bool {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return false
        }
        return UserDefaults.standard.object(forKey: GravPreferenceKeys.playSounds) as? Bool ?? true
    }

    // MARK: - Public API

    /// Starts the zero-gravity Antigravity welcome soundscape synced to the visual choreography.
    func playWelcomeScore(reducedMotion: Bool) {
        guard soundsEnabled else { return }
        stopAmbient(fadeDuration: 0.35)
        synthesisTask?.cancel()

        if reducedMotion, let data = cachedReducedScoreWAV {
            startAmbientPlayer(with: data, volume: 0.62)
            return
        }
        if !reducedMotion, let data = cachedFullScoreWAV {
            startAmbientPlayer(with: data, volume: 0.72)
            return
        }

        synthesisTask = Task { [weak self] in
            let wavData = await Task.detached(priority: .userInitiated) {
                reducedMotion
                    ? AntigravityAudioSynthesizer.renderReducedWelcomeScoreWAV()
                    : AntigravityAudioSynthesizer.renderFullWelcomeScoreWAV()
            }.value

            guard !Task.isCancelled, let self, self.soundsEnabled else { return }
            if reducedMotion {
                self.cachedReducedScoreWAV = wavData
                self.startAmbientPlayer(with: wavData, volume: 0.62)
            } else {
                self.cachedFullScoreWAV = wavData
                self.startAmbientPlayer(with: wavData, volume: 0.72)
            }
            self.prewarmInteractionEffects()
        }
    }

    /// Pre-renders all tactile UI micro-foley WAV buffers off the main actor.
    func prewarmInteractionEffects() {
        guard soundsEnabled else { return }
        guard prewarmTask == nil, cachedCueWAVs.count < 10 else { return }

        prewarmTask = Task { [weak self] in
            let built = await Task.detached(priority: .utility) { () -> [(CueKey, Data)] in
                [
                    (.hoverTick, AntigravityAudioSynthesizer.renderHoverTickWAV()),
                    (.confirmChime, AntigravityAudioSynthesizer.renderConfirmChimeWAV()),
                    (.completionChime, AntigravityAudioSynthesizer.renderCompletionChimeWAV()),
                    (.stepForward, AntigravityAudioSynthesizer.renderStepForwardWAV()),
                    (.stepBackward, AntigravityAudioSynthesizer.renderStepBackwardWAV()),
                    (.stepComplete, AntigravityAudioSynthesizer.renderStepCompleteWAV()),
                    (.buttonTap, AntigravityAudioSynthesizer.renderButtonTapWAV()),
                    (.tabSwitch, AntigravityAudioSynthesizer.renderTabSwitchWAV()),
                    (.challengeTick, AntigravityAudioSynthesizer.renderChallengeTickWAV()),
                    (.shutterSnap, AntigravityAudioSynthesizer.renderShutterSnapWAV()),
                ]
            }.value

            guard let self else { return }
            for (key, wav) in built {
                if self.cachedCueWAVs[key] == nil {
                    self.cachedCueWAVs[key] = wav
                }
            }
            self.prewarmTask = nil
        }
    }

    /// Ultra-delicate precision titanium/ceramic micro-detent on pointer hover.
    func playHoverTick() {
        playCue(.hoverTick, volume: 0.24) {
            AntigravityAudioSynthesizer.renderHoverTickWAV()
        }
    }

    /// Physically-modeled Taptic click + zero-G Lydian crystal bloom when entering onboarding.
    func playConfirmChime() {
        guard soundsEnabled else { return }
        stopAmbient(fadeDuration: 2.0)
        playCue(.confirmChime, volume: 0.60) {
            AntigravityAudioSynthesizer.renderConfirmChimeWAV()
        }
    }

    /// Zero-G upward levitation launch (0.0s) + magnetic Taptic dock lock chime (0.67s).
    func playCompletionChime() {
        guard soundsEnabled else { return }
        stopAmbient(fadeDuration: 0.55)
        playCue(.completionChime, volume: 0.62) {
            AntigravityAudioSynthesizer.renderCompletionChimeWAV()
        }
    }

    /// Crisp tactile detent + ascending F#-Lydian orbital glass interval.
    func playStepForward() {
        playCue(.stepForward, volume: 0.40) {
            AntigravityAudioSynthesizer.renderStepForwardWAV()
        }
    }

    /// Soft tactile detent + descending orbital glass settle.
    func playStepBackward() {
        playCue(.stepBackward, volume: 0.34) {
            AntigravityAudioSynthesizer.renderStepBackwardWAV()
        }
    }

    /// Radiant three-note Lydian arrival chord when completing all onboarding steps.
    func playStepComplete() {
        playCue(.stepComplete, volume: 0.44) {
            AntigravityAudioSynthesizer.renderStepCompleteWAV()
        }
    }

    /// Physically-modeled Apple Taptic / ceramic tactile click for interactive buttons.
    func playButtonTap() {
        playCue(.buttonTap, volume: 0.34) {
            AntigravityAudioSynthesizer.renderButtonTapWAV()
        }
    }

    /// Whisper-crisp mechanical glass slide click for Notch tab switches and mode toggles.
    func playTabSwitch() {
        playCue(.tabSwitch, volume: 0.26) {
            AntigravityAudioSynthesizer.renderTabSwitchWAV()
        }
    }

    /// Magnetic lock-in snap + crystalline confirmation harmonic for checklist milestones.
    func playChallengeComplete() {
        playCue(.challengeTick, volume: 0.36) {
            AntigravityAudioSynthesizer.renderChallengeTickWAV()
        }
    }

    /// Precision damped dual-leaf shutter click.
    func playShutterSnap() {
        playCue(.shutterSnap, volume: 0.30) {
            AntigravityAudioSynthesizer.renderShutterSnapWAV()
        }
    }

    private func playCue(
        _ key: CueKey,
        volume: Float,
        render: @escaping @Sendable () -> Data
    ) {
        guard soundsEnabled else { return }

        if let data = cachedCueWAVs[key] {
            effectVoices.play(key: key, data: data, volume: volume)
            return
        }

        Task { [weak self] in
            let wav = await Task.detached(priority: .userInitiated) {
                render()
            }.value
            guard let self, self.soundsEnabled else { return }
            self.cachedCueWAVs[key] = wav
            self.effectVoices.play(key: key, data: wav, volume: volume)
        }
    }

    /// Smooth perceptual exponential fade-out (never hard-cuts).
    func stopAmbient(fadeDuration: TimeInterval = 1.25) {
        synthesisTask?.cancel()
        synthesisTask = nil

        guard let player = ambientPlayer else { return }
        ambientPlayer = nil

        if fadeDuration <= 0.02 || !player.isPlaying {
            player.stop()
            return
        }

        let id = ObjectIdentifier(player)
        let startVolume = player.volume
        let steps = max(24, Int(fadeDuration * 60.0))
        let stepDurationNs = UInt64((fadeDuration / Double(steps)) * 1_000_000_000)

        let fadeTask = Task { @MainActor [weak self] in
            for step in 1...steps {
                try? await Task.sleep(nanoseconds: stepDurationNs)
                guard !Task.isCancelled, player.isPlaying else { break }
                let progress = Double(step) / Double(steps)
                let remaining = pow(max(0.0, 1.0 - progress), 2.3)
                player.volume = startVolume * Float(remaining)
            }
            player.volume = 0
            player.stop()
            self?.fadingPlayers.removeValue(forKey: id)
        }

        fadingPlayers[id] = (player: player, task: fadeTask)
    }

    private func startAmbientPlayer(with data: Data, volume: Float) {
        do {
            let player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
            player.volume = volume
            player.prepareToPlay()
            player.play()
            ambientPlayer = player
        } catch {
            // Silently ignore unavailable audio hardware
        }
    }
}

// MARK: - Effect Voice Pool

private final class OnboardingEffectVoicePool: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.grav.onboarding.effect-audio", qos: .userInteractive)
    private var voices: [AnyHashable: [AVAudioPlayer]] = [:]
    private var releaseWork: DispatchWorkItem?
    private let maxVoicesPerCue = 3
    private let idleRelease: TimeInterval = 10

    func play(key: AnyHashable, data: Data, volume: Float) {
        queue.async { [self] in
            var pool = voices[key] ?? []
            let player: AVAudioPlayer
            if let idle = pool.first(where: { !$0.isPlaying }) {
                player = idle
            } else if pool.count >= maxVoicesPerCue {
                player = pool.removeFirst()
                pool.append(player)
                voices[key] = pool
            } else {
                do {
                    let created = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
                    created.prepareToPlay()
                    player = created
                    pool.append(created)
                    voices[key] = pool
                } catch {
                    return
                }
            }
            player.currentTime = 0
            player.volume = volume
            player.play()
            scheduleRelease()
        }
    }

    private func scheduleRelease() {
        releaseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.voices = self.voices.compactMapValues { pool in
                let playing = pool.filter(\.isPlaying)
                return playing.isEmpty ? nil : playing
            }
            if !self.voices.isEmpty { self.scheduleRelease() }
        }
        releaseWork = work
        queue.asyncAfter(deadline: .now() + idleRelease, execute: work)
    }
}

// MARK: - Antigravity Procedural Stereo DSP Engine (44.1 kHz 16-bit PCM)

private enum AntigravityAudioSynthesizer {
    private static let sampleRate: Double = 44_100

    private struct PadChord {
        let start: Double
        let duration: Double
        let attack: Double
        let release: Double
        let gain: Double
        let brightness: Double
        let notes: [Double] // Hz
    }

    private struct CrystalBell {
        let start: Double
        let duration: Double
        let frequency: Double
        let gain: Double
        let pan: Double // -1...1
    }

    // MARK: - Full Antigravity Welcome Score (~18.0s Zero-G F#-Lydian Levitation)

    /// Timeline aligned directly to `GravOnboardingWelcome.playTimeline()`:
    /// - 0.00s – 1.45s: Deep sub-orbital F#sus2 drone + upward zero-G harmonic levitation glide
    /// - 1.45s – 4.50s: Lush F#maj9#11 (Lydian) weightless prism bloom + shimmering upward arpeggio
    /// - 2.28s:         Crystalline celesta fifth/octave chord as the white Grav emblem focuses
    /// - 4.25s – 7.40s: Soaring Bmaj9#11 harmonic lift as "Meet Grav." unfolds word by word
    /// - 4.70s:         Diamond high crystal spark for the trailing "."
    /// - 6.80s – 11.0s: Floating D#m11 zero-gravity suspension while admiring the flowing aurora
    /// - 9.80s – 18.0s: Serene F#maj9 resolution melting into a velvety diffused hall reverb tail
    static func renderFullWelcomeScoreWAV() -> Data {
        let totalDuration = 18.0
        let frameCount = Int(totalDuration * sampleRate)
        var left = [Double](repeating: 0, count: frameCount)
        var right = [Double](repeating: 0, count: frameCount)

        let chords: [PadChord] = [
            // Beat 1 (0.04s): Sub-orbital F#sus2 weightless awakening in the obsidian void
            PadChord(
                start: 0.04, duration: 2.35, attack: 1.05, release: 1.25,
                gain: 0.25, brightness: 0.36,
                notes: [92.50, 185.00, 277.18, 415.30, 554.37] // F#2, F#3, C#4, G#4, C#5
            ),
            // Beat 2 (1.40s): Zero-G F#maj9#11 (Lydian!) prism aurora bloom
            PadChord(
                start: 1.40, duration: 3.15, attack: 0.78, release: 1.65,
                gain: 0.44, brightness: 0.76,
                notes: [92.50, 185.00, 233.08, 277.18, 369.99, 415.30, 523.25, 554.37] // F#2 F#3 A#3 C#4 F#4 G#4 B#4 C#5
            ),
            // Beat 4 (4.22s): Soaring Bmaj9#11 emotional lift for "Meet Grav."
            PadChord(
                start: 4.22, duration: 3.25, attack: 0.62, release: 1.85,
                gain: 0.42, brightness: 0.80,
                notes: [123.47, 185.00, 246.94, 277.18, 311.13, 369.99, 466.16, 554.37] // B2 F#3 B3 C#4 D#4 F#4 A#4 C#5
            ),
            // Beat 6 (6.80s): Weightless orbital D#m11 suspension
            PadChord(
                start: 6.80, duration: 3.45, attack: 0.90, release: 2.30,
                gain: 0.32, brightness: 0.54,
                notes: [77.78, 155.56, 233.08, 277.18, 369.99, 415.30, 554.37] // D#2 D#3 A#3 C#4 F#4 G#4 C#5
            ),
            // Beat 7 (9.85s): Serene zero-G F#maj9 horizon breathing effortlessly into silence
            PadChord(
                start: 9.85, duration: 2.40, attack: 1.15, release: 3.80,
                gain: 0.26, brightness: 0.40,
                notes: [92.50, 185.00, 277.18, 369.99, 415.30, 554.37] // F#2 F#3 C#4 F#4 G#4 C#5
            ),
        ]

        for chord in chords {
            addOrbitalPadChord(chord, left: &left, right: &right)
        }

        // Signature Antigravity upward levitation harmonic sweep synced to orb → full-screen bloom
        addAntigravityLift(
            start: 0.55,
            duration: 1.95,
            startFreq: 185.00, // F#3
            endFreq: 554.37,   // C#5 (rising fifth + octave)
            gain: 0.085,
            left: &left,
            right: &right
        )
        addAirBloomSwell(start: 0.70, peak: 1.62, end: 2.80, gain: 0.046, left: &left, right: &right)

        // Refracted prism glass-celesta sparkles locked to visual choreography
        let bells: [CrystalBell] = [
            // Soft ascending prism shimmer as the aurora opens (1.65s – 1.98s)
            CrystalBell(start: 1.66, duration: 1.85, frequency: 554.37, gain: 0.042, pan: -0.45), // C#5
            CrystalBell(start: 1.80, duration: 1.95, frequency: 739.99, gain: 0.046, pan: 0.15),  // F#5
            CrystalBell(start: 1.94, duration: 2.05, frequency: 1046.50, gain: 0.036, pan: 0.48), // B#5 (#11 shimmer!)
            // White Grav emblem pulls out of optical blur (~2.28s)
            CrystalBell(start: 2.28, duration: 2.40, frequency: 739.99, gain: 0.072, pan: -0.20), // F#5
            CrystalBell(start: 2.36, duration: 2.30, frequency: 1108.73, gain: 0.052, pan: 0.24), // C#6
            // "Meet Grav." trailing period diamond spark (~4.70s)
            CrystalBell(start: 4.70, duration: 2.10, frequency: 932.33, gain: 0.068, pan: 0.20),  // A#5
            CrystalBell(start: 4.76, duration: 1.95, frequency: 1479.98, gain: 0.038, pan: -0.22), // F#6
            // Airy crystal shimmer as arrow button materializes (~5.20s)
            CrystalBell(start: 5.20, duration: 2.00, frequency: 830.61, gain: 0.048, pan: 0.0),   // G#5
            // Distant weightless orbital harmonics on final horizon (~10.5s)
            CrystalBell(start: 10.50, duration: 2.80, frequency: 739.99, gain: 0.030, pan: -0.18), // F#5
            CrystalBell(start: 10.90, duration: 2.60, frequency: 1108.73, gain: 0.024, pan: 0.22), // C#6
        ]

        for bell in bells {
            addCrystalBell(bell, left: &left, right: &right)
        }

        applyWarmLowPassSweep(left: &left, right: &right, isFullScore: true)
        applyDiffusedHallReverb(left: &left, right: &right, wetMix: 0.38, feedback: 0.60)
        applyMasterPolish(left: &left, right: &right, targetPeak: 0.80, tailFadeSeconds: 4.8)

        return encodeStereoWAV(left: left, right: right)
    }

    // MARK: - Reduced Motion Welcome Score (~6.8s calm F#maj9#11 bloom)

    static func renderReducedWelcomeScoreWAV() -> Data {
        let totalDuration = 6.8
        let frameCount = Int(totalDuration * sampleRate)
        var left = [Double](repeating: 0, count: frameCount)
        var right = [Double](repeating: 0, count: frameCount)

        addOrbitalPadChord(
            PadChord(
                start: 0.02, duration: 2.45, attack: 0.45, release: 3.30,
                gain: 0.38, brightness: 0.62,
                notes: [92.50, 185.00, 277.18, 369.99, 415.30, 523.25, 554.37]
            ),
            left: &left,
            right: &right
        )
        addCrystalBell(
            CrystalBell(start: 0.12, duration: 2.20, frequency: 739.99, gain: 0.056, pan: 0.0),
            left: &left,
            right: &right
        )

        applyWarmLowPassSweep(left: &left, right: &right, isFullScore: false)
        applyDiffusedHallReverb(left: &left, right: &right, wetMix: 0.34, feedback: 0.54)
        applyMasterPolish(left: &left, right: &right, targetPeak: 0.74, tailFadeSeconds: 2.8)

        return encodeStereoWAV(left: left, right: right)
    }

    // MARK: - Physically-Modeled Tactile Hover Tick (~22ms Precision Titanium Micro-Detent)

    static func renderHoverTickWAV() -> Data {
        let totalDuration = 0.026
        let frameCount = Int(totalDuration * sampleRate)
        var left = [Double](repeating: 0, count: frameCount)
        var right = [Double](repeating: 0, count: frameCount)

        addTactileMicroImpulse(
            at: 0.0,
            bodyStartHz: 340,
            bodyEndHz: 155,
            clickCenterHz: 3150,
            bodyGain: 0.34,
            clickGain: 0.58,
            decayRate: 240.0,
            seed: 0x41D9_8A2F_1104_C93B,
            left: &left,
            right: &right
        )

        applyMasterPolish(left: &left, right: &right, targetPeak: 0.62, tailFadeSeconds: 0.008)
        return encodeStereoWAV(left: left, right: right)
    }

    // MARK: - Physically-Modeled Taptic Button Tap (~34ms Apple Force-Touch Ceramic Click)

    static func renderButtonTapWAV() -> Data {
        let totalDuration = 0.038
        let frameCount = Int(totalDuration * sampleRate)
        var left = [Double](repeating: 0, count: frameCount)
        var right = [Double](repeating: 0, count: frameCount)

        // Primary physical press transient (damped actuator thump + crisp ceramic contact snap)
        addTactileMicroImpulse(
            at: 0.0,
            bodyStartHz: 290,
            bodyEndHz: 94,
            clickCenterHz: 2450,
            bodyGain: 0.68,
            clickGain: 0.74,
            decayRate: 165.0,
            seed: 0x91B2_E451_88C3_0F7A,
            left: &left,
            right: &right
        )
        // Subtle 7ms micro-bottoming resonance for authentic physical switch realism
        addTactileMicroImpulse(
            at: 0.0065,
            bodyStartHz: 185,
            bodyEndHz: 85,
            clickCenterHz: 1850,
            bodyGain: 0.24,
            clickGain: 0.20,
            decayRate: 210.0,
            seed: 0x22C4_77A9_0E12_55FD,
            left: &left,
            right: &right
        )

        applyMasterPolish(left: &left, right: &right, targetPeak: 0.74, tailFadeSeconds: 0.010)
        return encodeStereoWAV(left: left, right: right)
    }

    // MARK: - Precision Glass Tab Switch Click (~28ms Crisp Mechanical-Glass Slide Detent)

    static func renderTabSwitchWAV() -> Data {
        let totalDuration = 0.030
        let frameCount = Int(totalDuration * sampleRate)
        var left = [Double](repeating: 0, count: frameCount)
        var right = [Double](repeating: 0, count: frameCount)

        addTactileMicroImpulse(
            at: 0.0,
            bodyStartHz: 320,
            bodyEndHz: 120,
            clickCenterHz: 2850,
            bodyGain: 0.50,
            clickGain: 0.68,
            decayRate: 195.0,
            seed: 0x7A4F_19B3_C821_E04D,
            left: &left,
            right: &right
        )

        applyMasterPolish(left: &left, right: &right, targetPeak: 0.68, tailFadeSeconds: 0.009)
        return encodeStereoWAV(left: left, right: right)
    }

    // MARK: - Confirm Click Bloom (Taptic Click + Ascending Zero-G Lydian Crystal Bloom)

    static func renderConfirmChimeWAV() -> Data {
        let totalDuration = 1.45
        let frameCount = Int(totalDuration * sampleRate)
        var left = [Double](repeating: 0, count: frameCount)
        var right = [Double](repeating: 0, count: frameCount)

        // Authentic physical Taptic press at t = 0
        addTactileMicroImpulse(
            at: 0.0,
            bodyStartHz: 280,
            bodyEndHz: 96,
            clickCenterHz: 2400,
            bodyGain: 0.52,
            clickGain: 0.58,
            decayRate: 170.0,
            seed: 0x551A_99E1_7420_B3C8,
            left: &left,
            right: &right
        )

        let notes: [CrystalBell] = [
            CrystalBell(start: 0.008, duration: 0.92, frequency: 369.99, gain: 0.18, pan: -0.18), // F#4
            CrystalBell(start: 0.018, duration: 0.98, frequency: 554.37, gain: 0.24, pan: -0.14), // C#5
            CrystalBell(start: 0.052, duration: 1.12, frequency: 739.99, gain: 0.26, pan: 0.16),  // F#5
            CrystalBell(start: 0.088, duration: 1.10, frequency: 1046.50, gain: 0.14, pan: 0.28), // B#5 Lydian sparkle
        ]
        for bell in notes {
            addCrystalBell(bell, left: &left, right: &right)
        }

        applyDiffusedHallReverb(left: &left, right: &right, wetMix: 0.30, feedback: 0.46)
        applyMasterPolish(left: &left, right: &right, targetPeak: 0.80, tailFadeSeconds: 0.32)
        return encodeStereoWAV(left: left, right: right)
    }

    // MARK: - Completion Zero-G Ascent & Left-Notch Magnetic Dock Lock (~2.35s)

    static func renderCompletionChimeWAV() -> Data {
        let totalDuration = 2.35
        let frameCount = Int(totalDuration * sampleRate)
        var left = [Double](repeating: 0, count: frameCount)
        var right = [Double](repeating: 0, count: frameCount)

        // Beat 1 (0.00s): Tactile launch press + zero-G upward levitation chord
        addTactileMicroImpulse(
            at: 0.0,
            bodyStartHz: 270,
            bodyEndHz: 92,
            clickCenterHz: 2300,
            bodyGain: 0.48,
            clickGain: 0.50,
            decayRate: 165.0,
            seed: 0x18E7_33F0_9A21_441B,
            left: &left,
            right: &right
        )

        addOrbitalPadChord(
            PadChord(
                start: 0.01, duration: 0.78, attack: 0.12, release: 0.95,
                gain: 0.24, brightness: 0.60,
                notes: [246.94, 311.13, 369.99, 466.16, 554.37] // Bmaj9 lift
            ),
            left: &left,
            right: &right
        )

        addAntigravityLift(
            start: 0.04,
            duration: 0.65,
            startFreq: 369.99,
            endFreq: 739.99,
            gain: 0.068,
            left: &left,
            right: &right
        )

        // Beat 2 (0.67s — exact frame the Grav icon snaps onto the left-side Notch logo!):
        // Crisp magnetic Taptic dock lock + pure Lydian diamond harmonic
        addTactileMicroImpulse(
            at: 0.67,
            bodyStartHz: 310,
            bodyEndHz: 108,
            clickCenterHz: 2950,
            bodyGain: 0.54,
            clickGain: 0.62,
            decayRate: 185.0,
            seed: 0xC490_61B7_E210_99D2,
            left: &left,
            right: &right
        )

        let dockNotes: [CrystalBell] = [
            CrystalBell(start: 0.67, duration: 1.38, frequency: 739.99, gain: 0.26, pan: -0.16),  // F#5
            CrystalBell(start: 0.705, duration: 1.35, frequency: 1108.73, gain: 0.20, pan: 0.14), // C#6
            CrystalBell(start: 0.74, duration: 1.25, frequency: 1479.98, gain: 0.09, pan: 0.24),  // F#6
        ]
        for bell in dockNotes {
            addCrystalBell(bell, left: &left, right: &right)
        }

        applyDiffusedHallReverb(left: &left, right: &right, wetMix: 0.34, feedback: 0.50)
        applyMasterPolish(left: &left, right: &right, targetPeak: 0.80, tailFadeSeconds: 0.52)
        return encodeStereoWAV(left: left, right: right)
    }

    // MARK: - Step Forward / Backward / Complete / Challenge / Shutter

    static func renderStepForwardWAV() -> Data {
        let totalDuration = 0.34
        let frameCount = Int(totalDuration * sampleRate)
        var left = [Double](repeating: 0, count: frameCount)
        var right = [Double](repeating: 0, count: frameCount)

        addTactileMicroImpulse(
            at: 0.0,
            bodyStartHz: 295,
            bodyEndHz: 105,
            clickCenterHz: 2550,
            bodyGain: 0.46,
            clickGain: 0.54,
            decayRate: 185.0,
            seed: 0x33A1_F890_120B_77C4,
            left: &left,
            right: &right
        )
        addCrystalBell(CrystalBell(start: 0.01, duration: 0.22, frequency: 554.37, gain: 0.17, pan: -0.14), left: &left, right: &right)
        addCrystalBell(CrystalBell(start: 0.042, duration: 0.26, frequency: 739.99, gain: 0.21, pan: 0.16), left: &left, right: &right)

        applyDiffusedHallReverb(left: &left, right: &right, wetMix: 0.18, feedback: 0.34)
        applyMasterPolish(left: &left, right: &right, targetPeak: 0.74, tailFadeSeconds: 0.09)
        return encodeStereoWAV(left: left, right: right)
    }

    static func renderStepBackwardWAV() -> Data {
        let totalDuration = 0.32
        let frameCount = Int(totalDuration * sampleRate)
        var left = [Double](repeating: 0, count: frameCount)
        var right = [Double](repeating: 0, count: frameCount)

        addTactileMicroImpulse(
            at: 0.0,
            bodyStartHz: 260,
            bodyEndHz: 95,
            clickCenterHz: 2250,
            bodyGain: 0.42,
            clickGain: 0.46,
            decayRate: 185.0,
            seed: 0x66B2_D014_55E1_39A0,
            left: &left,
            right: &right
        )
        addCrystalBell(CrystalBell(start: 0.01, duration: 0.20, frequency: 739.99, gain: 0.16, pan: 0.14), left: &left, right: &right)
        addCrystalBell(CrystalBell(start: 0.042, duration: 0.24, frequency: 554.37, gain: 0.19, pan: -0.16), left: &left, right: &right)

        applyDiffusedHallReverb(left: &left, right: &right, wetMix: 0.16, feedback: 0.32)
        applyMasterPolish(left: &left, right: &right, targetPeak: 0.70, tailFadeSeconds: 0.09)
        return encodeStereoWAV(left: left, right: right)
    }

    static func renderStepCompleteWAV() -> Data {
        let totalDuration = 0.74
        let frameCount = Int(totalDuration * sampleRate)
        var left = [Double](repeating: 0, count: frameCount)
        var right = [Double](repeating: 0, count: frameCount)

        addTactileMicroImpulse(
            at: 0.0,
            bodyStartHz: 290,
            bodyEndHz: 100,
            clickCenterHz: 2600,
            bodyGain: 0.42,
            clickGain: 0.48,
            decayRate: 180.0,
            seed: 0x89F1_04C2_71B5_22EA,
            left: &left,
            right: &right
        )
        let notes: [CrystalBell] = [
            CrystalBell(start: 0.008, duration: 0.56, frequency: 554.37, gain: 0.19, pan: -0.18), // C#5
            CrystalBell(start: 0.048, duration: 0.58, frequency: 739.99, gain: 0.22, pan: 0.04),  // F#5
            CrystalBell(start: 0.088, duration: 0.62, frequency: 932.33, gain: 0.24, pan: 0.20),  // A#5
        ]
        for bell in notes {
            addCrystalBell(bell, left: &left, right: &right)
        }

        applyDiffusedHallReverb(left: &left, right: &right, wetMix: 0.24, feedback: 0.42)
        applyMasterPolish(left: &left, right: &right, targetPeak: 0.78, tailFadeSeconds: 0.18)
        return encodeStereoWAV(left: left, right: right)
    }

    static func renderChallengeTickWAV() -> Data {
        let totalDuration = 0.26
        let frameCount = Int(totalDuration * sampleRate)
        var left = [Double](repeating: 0, count: frameCount)
        var right = [Double](repeating: 0, count: frameCount)

        addTactileMicroImpulse(
            at: 0.0,
            bodyStartHz: 320,
            bodyEndHz: 118,
            clickCenterHz: 3000,
            bodyGain: 0.45,
            clickGain: 0.55,
            decayRate: 205.0,
            seed: 0xAB19_4F82_30C5_912D,
            left: &left,
            right: &right
        )
        addCrystalBell(CrystalBell(start: 0.012, duration: 0.18, frequency: 739.99, gain: 0.16, pan: -0.08), left: &left, right: &right)
        addCrystalBell(CrystalBell(start: 0.036, duration: 0.21, frequency: 1108.73, gain: 0.20, pan: 0.12), left: &left, right: &right)

        applyDiffusedHallReverb(left: &left, right: &right, wetMix: 0.15, feedback: 0.30)
        applyMasterPolish(left: &left, right: &right, targetPeak: 0.72, tailFadeSeconds: 0.06)
        return encodeStereoWAV(left: left, right: right)
    }

    static func renderShutterSnapWAV() -> Data {
        let totalDuration = 0.085
        let frameCount = Int(totalDuration * sampleRate)
        var left = [Double](repeating: 0, count: frameCount)
        var right = [Double](repeating: 0, count: frameCount)

        addTactileMicroImpulse(
            at: 0.0,
            bodyStartHz: 250,
            bodyEndHz: 88,
            clickCenterHz: 2700,
            bodyGain: 0.62,
            clickGain: 0.75,
            decayRate: 185.0,
            seed: 0x71E9_23B5_4C0A_D81F,
            left: &left,
            right: &right
        )
        addTactileMicroImpulse(
            at: 0.020,
            bodyStartHz: 210,
            bodyEndHz: 80,
            clickCenterHz: 2200,
            bodyGain: 0.34,
            clickGain: 0.44,
            decayRate: 195.0,
            seed: 0x44A2_9F11_80CE_317B,
            left: &left,
            right: &right
        )

        applyMasterPolish(left: &left, right: &right, targetPeak: 0.70, tailFadeSeconds: 0.02)
        return encodeStereoWAV(left: left, right: right)
    }

    // MARK: - Physically-Modeled Tactile Impulse Generator

    /// Synthesizes an authentic physical Force-Touch / ceramic-glass tactile transient:
    /// - Damped pitch-drop actuator body (`bodyStartHz → bodyEndHz` in ~5ms)
    /// - Bandpass-filtered ceramic contact micro-noise burst (`clickCenterHz`)
    /// Produces crisp, organic real-world switch feel with zero synthetic sine-wave beepiness.
    private static func addTactileMicroImpulse(
        at startTime: Double,
        bodyStartHz: Double,
        bodyEndHz: Double,
        clickCenterHz: Double,
        bodyGain: Double,
        clickGain: Double,
        decayRate: Double,
        seed: UInt64,
        left: inout [Double],
        right: inout [Double]
    ) {
        let startIdx = max(0, Int(startTime * sampleRate))
        let duration = 0.032
        let endIdx = min(left.count, startIdx + Int(duration * sampleRate))
        guard endIdx > startIdx else { return }

        var rng = seed
        @inline(__always)
        func nextNoise() -> Double {
            rng &+= 0x9E37_79B9_7F4A_7C15
            var z = rng
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z = z ^ (z >> 31)
            return (Double(z & 0xFFFF) / 32768.0) - 1.0
        }

        // Biquad bandpass coefficients around `clickCenterHz` (Q = 2.6 for natural ceramic timbre)
        let w0 = 2.0 * Double.pi * clickCenterHz / sampleRate
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)
        let q = 2.6
        let alpha = sinW0 / (2.0 * q)
        let b0 = alpha
        let b1 = 0.0
        let b2 = -alpha
        let a0 = 1.0 + alpha
        let a1 = -2.0 * cosW0
        let a2 = 1.0 - alpha

        let nb0 = b0 / a0
        let nb1 = b1 / a0
        let nb2 = b2 / a0
        let na1 = a1 / a0
        let na2 = a2 / a0

        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        var bodyPhase = 0.0
        let twoPi = 2.0 * Double.pi

        for i in startIdx..<endIdx {
            let t = Double(i - startIdx) / sampleRate
            // Sharp 0.7ms physical impact attack
            let attack = min(1.0, t / 0.0007)

            // 1. Actuator body: fast exponential pitch drop simulating physical mass displacement
            let pitchDecay = exp(-t * 320.0)
            let instHz = bodyEndHz + (bodyStartHz - bodyEndHz) * pitchDecay
            bodyPhase += twoPi * instHz / sampleRate
            let bodyEnv = attack * exp(-t * decayRate)
            let body = sin(bodyPhase) * bodyEnv * bodyGain

            // 2. Ceramic/glass micro-contact transient (very short 3.5ms envelope)
            let rawNoise = nextNoise()
            let filtered = nb0 * rawNoise + nb1 * x1 + nb2 * x2 - na1 * y1 - na2 * y2
            x2 = x1; x1 = rawNoise
            y2 = y1; y1 = filtered
            let clickEnv = attack * exp(-t * (decayRate * 2.6))
            let click = filtered * clickEnv * clickGain * 2.4

            let sample = body + click
            left[i] += sample * 0.98
            right[i] += sample * 1.00
        }
    }

    // MARK: - Antigravity Orbital DSP Building Blocks

    /// Weightless upward pitch-gliding harmonic silk ribbon evoking zero-gravity lift.
    private static func addAntigravityLift(
        start: Double,
        duration: Double,
        startFreq: Double,
        endFreq: Double,
        gain: Double,
        left: inout [Double],
        right: inout [Double]
    ) {
        let startIdx = max(0, Int(start * sampleRate))
        let endIdx = min(left.count, startIdx + Int(duration * sampleRate))
        guard endIdx > startIdx else { return }

        let twoPi = 2.0 * Double.pi
        var phaseL = 0.0
        var phaseR = 0.7

        for i in startIdx..<endIdx {
            let t = Double(i - startIdx) / sampleRate
            let u = max(0.0, min(1.0, t / duration))
            let smoothU = u * u * (3.0 - 2.0 * u)
            // Raised bell envelope peaking around 55% of lift
            let env = sin(Double.pi * pow(u, 0.85))
            let freq = startFreq * pow(endFreq / startFreq, smoothU)

            phaseL += twoPi * (freq * 0.9985) / sampleRate
            phaseR += twoPi * (freq * 1.0015) / sampleRate

            let lSig = (sin(phaseL) * 0.72 + sin(2.0 * phaseL) * 0.28) * env * gain
            let rSig = (sin(phaseR) * 0.72 + sin(2.0 * phaseR) * 0.28) * env * gain
            left[i] += lSig
            right[i] += rSig
        }
    }

    private static func addOrbitalPadChord(_ chord: PadChord, left: inout [Double], right: inout [Double]) {
        let startIdx = max(0, Int(chord.start * sampleRate))
        let totalSamples = Int((chord.duration + chord.release) * sampleRate)
        let endIdx = min(left.count, startIdx + totalSamples)
        guard endIdx > startIdx else { return }

        let twoPi = 2.0 * Double.pi
        let noteScale = chord.gain / max(1.0, sqrt(Double(chord.notes.count)))
        let h2Gain = 0.24 * chord.brightness
        let h3Gain = 0.10 * chord.brightness
        let h4Gain = 0.04 * chord.brightness

        let detuneFactors: [(ratio: Double, panL: Double, panR: Double)] = [
            (0.9965, 0.84, 0.26),
            (1.0000, 0.62, 0.62),
            (1.0035, 0.26, 0.84),
        ]

        for (noteIdx, freq) in chord.notes.enumerated() {
            let basePhase = Double(noteIdx) * 1.17
            let panBias = (Double(noteIdx % 3) - 1.0) * 0.15

            for (voiceIdx, voice) in detuneFactors.enumerated() {
                let f = freq * voice.ratio
                let phase0 = basePhase + Double(voiceIdx) * 2.03
                let lGain = noteScale * (voice.panL - panBias) * 0.56
                let rGain = noteScale * (voice.panR + panBias) * 0.56

                let vibRate = 0.30 + Double((noteIdx + voiceIdx) % 4) * 0.09
                let vibDepth = 0.0016

                var phase = phase0
                for i in startIdx..<endIdx {
                    let localT = Double(i - startIdx) / sampleRate
                    let env = smoothEnvelope(
                        t: localT,
                        attack: chord.attack,
                        sustainEnd: chord.duration,
                        release: chord.release
                    )
                    if env <= 0.00001 { continue }

                    let instFreq = f * (1.0 + vibDepth * sin(twoPi * vibRate * localT + phase0))
                    phase += twoPi * instFreq / sampleRate

                    var sample = sin(phase)
                    if freq < 340 {
                        sample += h2Gain * sin(2.0 * phase)
                        sample += h3Gain * sin(3.0 * phase)
                        sample += h4Gain * sin(4.0 * phase)
                    } else {
                        sample += (h2Gain * 0.62) * sin(2.0 * phase)
                        sample += (h3Gain * 0.30) * sin(3.0 * phase)
                    }

                    let out = sample * env
                    left[i] += out * lGain
                    right[i] += out * rGain
                }
            }
        }
    }

    private static func addCrystalBell(_ bell: CrystalBell, left: inout [Double], right: inout [Double]) {
        let startIdx = max(0, Int(bell.start * sampleRate))
        let endIdx = min(left.count, startIdx + Int(bell.duration * sampleRate))
        guard endIdx > startIdx else { return }

        let twoPi = 2.0 * Double.pi
        let panL = sqrt(0.5 * (1.0 - bell.pan))
        let panR = sqrt(0.5 * (1.0 + bell.pan))

        for i in startIdx..<endIdx {
            let t = Double(i - startIdx) / sampleRate
            let attack = min(1.0, t / 0.008)
            let env1 = exp(-t * (2.5 / max(0.3, bell.duration)))
            let env2 = exp(-t * (6.0 / max(0.3, bell.duration)))

            let fundamental = sin(twoPi * bell.frequency * t) * env1
            let octave = sin(twoPi * bell.frequency * 2.0 * t) * 0.25 * env2
            let shimmer = sin(twoPi * bell.frequency * 3.001 * t) * 0.08 * exp(-t * 12.0)

            let sample = (fundamental + octave + shimmer) * attack * bell.gain
            left[i] += sample * panL
            right[i] += sample * panR
        }
    }

    private static func addAirBloomSwell(
        start: Double,
        peak: Double,
        end: Double,
        gain: Double,
        left: inout [Double],
        right: inout [Double]
    ) {
        let startIdx = max(0, Int(start * sampleRate))
        let endIdx = min(left.count, Int(end * sampleRate))
        guard endIdx > startIdx else { return }

        var rng: UInt64 = 0x3C6E_F372_FE94_F82B
        var lpL = 0.0, lpR = 0.0, hpL = 0.0, hpR = 0.0

        @inline(__always)
        func nextNoise() -> Double {
            rng &+= 0x9E37_79B9_7F4A_7C15
            var z = rng
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z = z ^ (z >> 31)
            return (Double(z & 0xFFFF) / 32768.0) - 1.0
        }

        for i in startIdx..<endIdx {
            let t = Double(i) / sampleRate
            let env: Double
            if t < peak {
                let u = (t - start) / max(0.01, peak - start)
                env = u * u * (3.0 - 2.0 * u)
            } else {
                let u = (t - peak) / max(0.01, end - peak)
                env = pow(max(0, 1.0 - u), 1.8)
            }

            let cutoff = 340.0 + 1450.0 * env
            let alpha = min(0.45, (2.0 * Double.pi * cutoff) / sampleRate)
            lpL += alpha * (nextNoise() - lpL)
            lpR += alpha * (nextNoise() - lpR)
            hpL += 0.025 * (lpL - hpL)
            hpR += 0.025 * (lpR - hpR)

            left[i] += (lpL - hpL) * env * gain
            right[i] += (lpR - hpR) * env * gain
        }
    }

    private static func applyWarmLowPassSweep(left: inout [Double], right: inout [Double], isFullScore: Bool) {
        var yL = 0.0
        var yR = 0.0
        let twoPiOverSR = (2.0 * Double.pi) / sampleRate

        for i in 0..<left.count {
            let t = Double(i) / sampleRate
            let cutoff: Double
            if isFullScore {
                if t < 1.35 {
                    let u = t / 1.35
                    cutoff = 560.0 + 640.0 * u
                } else if t < 2.60 {
                    let u = (t - 1.35) / 1.25
                    let eased = u * u * (3.0 - 2.0 * u)
                    cutoff = 1200.0 + 3200.0 * eased
                } else if t < 7.40 {
                    cutoff = 4400.0
                } else {
                    let u = min(1.0, (t - 7.40) / 9.40)
                    let eased = u * u * (3.0 - 2.0 * u)
                    cutoff = 4400.0 - 3350.0 * eased
                }
            } else {
                cutoff = 3600.0
            }

            let rc = 1.0 / (twoPiOverSR * cutoff)
            let alpha = 1.0 / (rc + 1.0)
            yL += alpha * (left[i] - yL)
            yR += alpha * (right[i] - yR)
            left[i] = yL
            right[i] = yR
        }
    }

    /// Studio-grade stereo hall reverb: 4 damped comb filters + 2 cascaded Schroeder all-pass
    /// diffusers per channel for silky, velvety zero-gravity spatial depth with zero metallic ringing.
    private static func applyDiffusedHallReverb(
        left: inout [Double],
        right: inout [Double],
        wetMix: Double,
        feedback: Double
    ) {
        let count = left.count
        let combDelaysL = [1427, 1693, 1987, 2441]
        let combDelaysR = [1483, 1747, 2053, 2503]

        var wetL = [Double](repeating: 0, count: count)
        var wetR = [Double](repeating: 0, count: count)

        for c in 0..<combDelaysL.count {
            let dL = combDelaysL[c]
            let dR = combDelaysR[c]
            var bufL = [Double](repeating: 0, count: dL)
            var bufR = [Double](repeating: 0, count: dR)
            var idxL = 0
            var idxR = 0
            var dampL = 0.0
            var dampR = 0.0
            let dampCoeff = 0.34

            for i in 0..<count {
                let outL = bufL[idxL]
                let outR = bufR[idxR]
                dampL = outL * (1.0 - dampCoeff) + dampL * dampCoeff
                dampR = outR * (1.0 - dampCoeff) + dampR * dampCoeff

                bufL[idxL] = left[i] * 0.76 + right[i] * 0.24 + dampL * feedback
                bufR[idxR] = right[i] * 0.76 + left[i] * 0.24 + dampR * feedback

                wetL[i] += outL * 0.25
                wetR[i] += outR * 0.25

                idxL += 1; if idxL == dL { idxL = 0 }
                idxR += 1; if idxR == dR { idxR = 0 }
            }
        }

        // Two cascaded all-pass diffusers smooth early reflections into liquid cinematic air
        let allPassDelaysL = [225, 556]
        let allPassDelaysR = [241, 577]
        let g = 0.52

        for stage in 0..<allPassDelaysL.count {
            let dL = allPassDelaysL[stage]
            let dR = allPassDelaysR[stage]
            var apL = [Double](repeating: 0, count: dL)
            var apR = [Double](repeating: 0, count: dR)
            var iL = 0, iR = 0

            for i in 0..<count {
                let inL = wetL[i]
                let bufOutL = apL[iL]
                let outL = -g * inL + bufOutL
                apL[iL] = inL + g * bufOutL
                wetL[i] = outL
                iL += 1; if iL == dL { iL = 0 }

                let inR = wetR[i]
                let bufOutR = apR[iR]
                let outR = -g * inR + bufOutR
                apR[iR] = inR + g * bufOutR
                wetR[i] = outR
                iR += 1; if iR == dR { iR = 0 }
            }
        }

        let dryMix = 1.0 - wetMix * 0.44
        for i in 0..<count {
            left[i] = left[i] * dryMix + wetL[i] * wetMix
            right[i] = right[i] * dryMix + wetR[i] * wetMix
        }
    }

    private static func applyMasterPolish(
        left: inout [Double],
        right: inout [Double],
        targetPeak: Double,
        tailFadeSeconds: Double = 0.08
    ) {
        let count = left.count
        guard count > 0 else { return }

        var peak = 0.0001
        for i in 0..<count {
            let l = tanh(left[i] * 1.12)
            let r = tanh(right[i] * 1.12)
            left[i] = l
            right[i] = r
            peak = max(peak, max(abs(l), abs(r)))
        }

        let scale = targetPeak / peak
        let fadeInSamples = min(count / 4, Int(0.008 * sampleRate))
        let fadeOutSamples = min(count / 2, Int(tailFadeSeconds * sampleRate))

        for i in 0..<count {
            var env = 1.0
            if i < fadeInSamples {
                let u = Double(i) / Double(max(1, fadeInSamples))
                env *= 0.5 - 0.5 * cos(Double.pi * u)
            }
            let fromEnd = count - 1 - i
            if fromEnd < fadeOutSamples {
                let u = Double(fromEnd) / Double(max(1, fadeOutSamples))
                let raised = 0.5 - 0.5 * cos(Double.pi * u)
                env *= raised * raised
            }
            left[i] *= scale * env
            right[i] *= scale * env
        }
    }

    private static func smoothEnvelope(t: Double, attack: Double, sustainEnd: Double, release: Double) -> Double {
        if t < 0 { return 0 }
        if t < attack {
            let u = t / max(0.001, attack)
            return 0.5 - 0.5 * cos(Double.pi * u)
        }
        if t < sustainEnd { return 1.0 }
        let relT = t - sustainEnd
        if relT < release {
            let u = relT / max(0.001, release)
            return 0.5 + 0.5 * cos(Double.pi * u)
        }
        return 0
    }

    private static func encodeStereoWAV(left: [Double], right: [Double]) -> Data {
        let frameCount = min(left.count, right.count)
        let channels: UInt16 = 2
        let bitsPerSample: UInt16 = 16
        let sr = UInt32(sampleRate)
        let byteRate = sr * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(frameCount * Int(blockAlign))
        let chunkSize = 36 + dataSize

        var data = Data(capacity: 44 + Int(dataSize))

        func appendASCII(_ str: String) { data.append(contentsOf: str.utf8) }
        func appendLE(_ value: UInt32) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        func appendLE(_ value: UInt16) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }

        appendASCII("RIFF"); appendLE(chunkSize); appendASCII("WAVE")
        appendASCII("fmt "); appendLE(UInt32(16)); appendLE(UInt16(1))
        appendLE(channels); appendLE(sr); appendLE(byteRate)
        appendLE(blockAlign); appendLE(bitsPerSample)
        appendASCII("data"); appendLE(dataSize)

        data.reserveCapacity(44 + Int(dataSize))
        for i in 0..<frameCount {
            let lInt = Int16(max(-32_767, min(32_767, Int((left[i] * 32_767.0).rounded()))))
            let rInt = Int16(max(-32_767, min(32_767, Int((right[i] * 32_767.0).rounded()))))
            var lLE = lInt.littleEndian
            var rLE = rInt.littleEndian
            withUnsafeBytes(of: &lLE) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &rLE) { data.append(contentsOf: $0) }
        }

        return data
    }
}
