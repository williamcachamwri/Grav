import AVFoundation
import Foundation

/// Procedural 44.1 kHz stereo DSP Super Saiyan Turbo Audio Engine.
///
/// Synthesizes cinematic, physically-modeled Dragon Ball Super Saiyan soundscapes off the main actor
/// with zero external audio files:
/// - **Power-Up Eruption** (`playPowerUpEruption`): Sub-bass seismic Ki drop, sweeping 31Hz-fluttering
///   roaring plasma flame turbine, form-specific harmonic resonance (SSJ / God / Blue / Rosé / Ultra
///   Instinct / Legendary), and stereo SSJ2 high-voltage bio-electric lightning crackles.
/// - **Lightning Surge** (`playLightningSurge`): Crisp ionized arc snap + tight Ki burst on streaming /
///   command surges and transformation color switches.
/// - **Living Aura Loop** (`setAuraLoopActive`): Seamless looping atmospheric Ki resonance hum while
///   Antigravity is actively executing in Turbo mode, with smooth exponential fade-in/out.
/// - **Power-Down Settle** (`playPowerDownSettle`): Descending Ki dispersion whoosh when a turn completes.
@MainActor
public final class SuperSaiyanAudioEngine {
    public static let shared = SuperSaiyanAudioEngine()

    private enum CueKind: Hashable, Sendable {
        case eruption(SuperSaiyanAuraTheme)
        case surge(SuperSaiyanAuraTheme)
        case settle(SuperSaiyanAuraTheme)
        case auraLoop(SuperSaiyanAuraTheme)
    }

    private var cachedWAVs: [CueKind: Data] = [:]
    private let effectPool = TurboEffectVoicePool()

    private var loopPlayer: AVAudioPlayer?
    private var loopTheme: SuperSaiyanAuraTheme?
    private var loopTargetActive: Bool = false
    private var loopFadeTask: Task<Void, Never>?
    private var loopSynthTask: Task<Void, Never>?

    private var lastEruptionAt: Date = .distantPast
    private var lastSurgeAt: Date = .distantPast
    private var lastSettleAt: Date = .distantPast

    private init() {}

    nonisolated deinit {}

    private var isTestEnvironment: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Plays the full seismic Super Saiyan power-up eruption roar (throttled unless `force` is true).
    public func playPowerUpEruption(
        theme: SuperSaiyanAuraTheme,
        volume: Float = 0.78,
        force: Bool = false
    ) {
        guard !isTestEnvironment else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastEruptionAt) < 2.2 {
            return
        }
        lastEruptionAt = now

        playCue(.eruption(theme), volume: volume) {
            SuperSaiyanDSP.renderPowerUpEruptionWAV(theme: theme)
        }
    }

    /// Plays a razor-sharp SSJ2 bio-electric lightning crackle & Ki surge.
    public func playLightningSurge(
        theme: SuperSaiyanAuraTheme,
        volume: Float = 0.62,
        force: Bool = false
    ) {
        guard !isTestEnvironment else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastSurgeAt) < 3.2 {
            return
        }
        lastSurgeAt = now

        playCue(.surge(theme), volume: volume) {
            SuperSaiyanDSP.renderLightningSurgeWAV(theme: theme)
        }
    }

    /// Plays a smooth descending Ki dispersion whoosh when a Turbo turn finishes.
    public func playPowerDownSettle(
        theme: SuperSaiyanAuraTheme,
        volume: Float = 0.50
    ) {
        guard !isTestEnvironment else { return }
        let now = Date()
        guard now.timeIntervalSince(lastSettleAt) >= 1.8 else { return }
        lastSettleAt = now

        playCue(.settle(theme), volume: volume) {
            SuperSaiyanDSP.renderPowerDownSettleWAV(theme: theme)
        }
    }

    /// Smoothly fades in or out the continuous living Super Saiyan Ki hum while Turbo is actively working.
    public func setAuraLoopActive(_ active: Bool, theme: SuperSaiyanAuraTheme) {
        guard !isTestEnvironment else { return }
        let themeChanged = loopTheme != theme
        loopTargetActive = active

        if !active {
            loopSynthTask?.cancel()
            loopSynthTask = nil
            fadeOutAndStopLoop(duration: 0.75)
            return
        }

        if let player = loopPlayer, player.isPlaying, !themeChanged {
            fadeLoop(player: player, to: 0.24, duration: 0.35, stopOnComplete: false)
            return
        }

        if themeChanged {
            fadeOutAndStopLoop(duration: 0.30)
        }

        loopTheme = theme
        let key = CueKind.auraLoop(theme)
        if let wav = cachedWAVs[key] {
            startLoopPlayer(with: wav, targetVolume: 0.24)
            return
        }

        loopSynthTask?.cancel()
        loopSynthTask = Task { [weak self] in
            let wav = await Task.detached(priority: .utility) {
                SuperSaiyanDSP.renderSeamlessAuraLoopWAV(theme: theme)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.cachedWAVs[key] = wav
            guard self.loopTargetActive, self.loopTheme == theme else { return }
            self.startLoopPlayer(with: wav, targetVolume: 0.24)
        }
    }

    /// Immediately fades out any active continuous Turbo aura loop.
    public func stopAllLoops() {
        loopTargetActive = false
        loopSynthTask?.cancel()
        loopSynthTask = nil
        fadeOutAndStopLoop(duration: 0.35)
    }

    // MARK: - Internal Playback

    private func playCue(
        _ key: CueKind,
        volume: Float,
        render: @escaping @Sendable () -> Data
    ) {
        if let cached = cachedWAVs[key] {
            effectPool.play(key: key, data: cached, volume: volume)
            return
        }

        Task { [weak self] in
            let wav = await Task.detached(priority: .userInitiated) {
                render()
            }.value
            guard let self else { return }
            self.cachedWAVs[key] = wav
            self.effectPool.play(key: key, data: wav, volume: volume)
        }
    }

    private func startLoopPlayer(with data: Data, targetVolume: Float) {
        loopFadeTask?.cancel()
        loopPlayer?.stop()
        do {
            let player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
            player.numberOfLoops = -1
            player.volume = 0.0
            player.prepareToPlay()
            player.play()
            loopPlayer = player
            fadeLoop(player: player, to: targetVolume, duration: 0.55, stopOnComplete: false)
        } catch {
            loopPlayer = nil
        }
    }

    private func fadeOutAndStopLoop(duration: TimeInterval) {
        guard let player = loopPlayer else { return }
        fadeLoop(player: player, to: 0.0, duration: duration, stopOnComplete: true)
    }

    private func fadeLoop(
        player: AVAudioPlayer,
        to targetVolume: Float,
        duration: TimeInterval,
        stopOnComplete: Bool
    ) {
        loopFadeTask?.cancel()
        let startVol = player.volume
        let steps = max(12, Int(duration * 60.0))
        let stepNs = UInt64((duration / Double(steps)) * 1_000_000_000)

        loopFadeTask = Task { @MainActor [weak self] in
            for step in 1...steps {
                try? await Task.sleep(nanoseconds: stepNs)
                guard !Task.isCancelled else { return }
                let u = Double(step) / Double(steps)
                let eased = u * u * (3.0 - 2.0 * u)
                player.volume = startVol + (targetVolume - startVol) * Float(eased)
            }
            player.volume = targetVolume
            if stopOnComplete {
                player.stop()
                if self?.loopPlayer === player {
                    self?.loopPlayer = nil
                }
            }
        }
    }
}

// MARK: - Dedicated Turbo Voice Pool

private final class TurboEffectVoicePool: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.grav.turbo.audio", qos: .userInteractive)
    private var voices: [AnyHashable: [AVAudioPlayer]] = [:]
    private var releaseWork: DispatchWorkItem?
    private let maxVoicesPerCue = 2
    private let idleRelease: TimeInterval = 14

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
                let active = pool.filter(\.isPlaying)
                return active.isEmpty ? nil : active
            }
            if !self.voices.isEmpty { self.scheduleRelease() }
        }
        releaseWork = work
        queue.asyncAfter(deadline: .now() + idleRelease, execute: work)
    }
}

// MARK: - Procedural Stereo Super Saiyan DSP Synthesizer (44.1 kHz 16-bit PCM)

private enum SuperSaiyanDSP {
    private static let sampleRate: Double = 44_100
    private static let twoPi: Double = 2.0 * Double.pi

    // MARK: - 1. Seismic Power-Up Eruption (~2.40s)

    static func renderPowerUpEruptionWAV(theme: SuperSaiyanAuraTheme) -> Data {
        let duration = 2.40
        let count = Int(duration * sampleRate)
        var left = [Double](repeating: 0, count: count)
        var right = [Double](repeating: 0, count: count)

        let root = theme.audioRootHz
        let isBroly = theme == .legendary
        let isUI = theme == .ultraInstinct

        // Layer A: Seismic Sub-Bass Ki Ignition Impact (0.00s - 0.58s)
        // Chest-thumping drop that announces raw Super Saiyan pressure
        var subPhase = 0.0
        let impactFrames = min(count, Int(0.62 * sampleRate))
        for i in 0..<impactFrames {
            let t = Double(i) / sampleRate
            let attack = min(1.0, t / 0.008)
            let decay = exp(-t * (isBroly ? 4.4 : 5.8))
            let startHz = isBroly ? 132.0 : 118.0
            let endHz = isBroly ? 29.0 : 36.0
            let freq = endHz + (startHz - endHz) * exp(-t * 14.0)
            subPhase += twoPi * freq / sampleRate

            let punch = tanh((sin(subPhase) * 1.45 + 0.35 * sin(2.0 * subPhase)) * (isBroly ? 1.55 : 1.25))
            let s = punch * attack * decay * (isBroly ? 0.68 : 0.56)
            left[i] += s
            right[i] += s
        }

        // Layer B: Iconic Dragon Ball Roaring Plasma Ki Flame Whoosh (0.02s - 2.35s)
        // Resonant sweeping dual-bandpass flame wind + 31Hz anime aura throb flutter!
        var rngL: UInt64 = 0x9E37_79B9_7F4A_7C15 ^ UInt64(theme.rawValue.hashValue & 0xFFFF)
        var rngR: UInt64 = 0xBF58_476D_1CE4_E5B9 ^ UInt64(theme.rawValue.hashValue & 0xFFFF)
        var lp1L = 0.0, lp2L = 0.0, hpL = 0.0
        var lp1R = 0.0, lp2R = 0.0, hpR = 0.0

        for i in 0..<count {
            let t = Double(i) / sampleRate
            let env: Double
            if t < 0.14 {
                let u = t / 0.14
                env = u * u * (3.0 - 2.0 * u)
            } else if t < 1.25 {
                env = 1.0 - 0.14 * ((t - 0.14) / 1.11)
            } else {
                let u = min(1.0, (t - 1.25) / 1.12)
                env = 0.86 * pow(1.0 - u, 1.9)
            }

            // Iconic DBZ rising roar pitch sweep: surges sharply upward then stabilizes into roaring wind
            let sweepPeak = exp(-pow((t - 0.34) / 0.36, 2.0))
            let cutoff = (isUI ? 520.0 : 340.0) + (isUI ? 2700.0 : 2150.0) * sweepPeak + 480.0 * env
            let alpha = min(0.55, (twoPi * cutoff) / sampleRate)

            let nL = nextNoise(&rngL)
            let nR = nextNoise(&rngR)

            // 2-pole resonant low-pass + high-pass shapes raw wind into fiery roaring plasma
            lp1L += alpha * (nL - lp1L)
            lp2L += alpha * (lp1L - lp2L)
            hpL += 0.028 * (lp2L - hpL)

            lp1R += alpha * (nR - lp1R)
            lp2R += alpha * (lp1R - lp2R)
            hpR += 0.028 * (lp2R - hpR)

            // Signature Dragon Ball 28-36 Hz undulating Ki flame throb!
            let flutterRate = isBroly ? 24.0 : (isUI ? 34.0 : 31.0)
            let flutterL = 0.72 + 0.28 * sin(twoPi * flutterRate * t)
            let flutterR = 0.72 + 0.28 * sin(twoPi * (flutterRate + 1.4) * t + 0.9)

            let roarGain = isUI ? 0.38 : 0.48
            left[i] += (lp2L - hpL) * env * flutterL * roarGain
            right[i] += (lp2R - hpR) * env * flutterR * roarGain
        }

        // Layer C: Harmonic Ki Turbine Power Chord (Detuned FM / Overdriven Brass-Plasma Swell)
        // Gives each Super Saiyan form its unmistakable musical energy signature
        let ratios: [Double]
        switch theme {
        case .superSaiyan:
            ratios = [1.0, 1.5, 2.0, 3.0, 4.0] // Fierce golden power fifth + octaves
        case .god:
            ratios = [1.0, 1.5, 2.0, 2.5, 4.0] // Fiery major divine blaze
        case .blue:
            ratios = [1.0, 1.5, 2.0, 3.0, 4.5] // Glacial godly maj9 resonance
        case .rose:
            ratios = [1.0, 1.5, 2.0, 2.4, 3.6] // Regal dark crimson minor-9th
        case .ultraInstinct:
            ratios = [1.0, 1.5, 2.0, 3.0, 4.5, 6.0, 8.0] // Iconic shimmering transcendent UI harmonic halo!
        case .legendary:
            ratios = [1.0, 1.414, 2.0, 2.5, 3.0] // Ferocious Broly tension sub-power
        }

        for (idx, ratio) in ratios.enumerated() {
            let baseFreq = root * ratio
            let pan = (idx % 2 == 0 ? -1.0 : 1.0) * min(0.55, 0.12 + Double(idx) * 0.09)
            let panL = sqrt(0.5 * (1.0 - pan))
            let panR = sqrt(0.5 * (1.0 + pan))
            let weight = (isUI && idx >= 4 ? 0.14 : 0.20) / sqrt(Double(idx + 1))

            var ph1 = Double(idx) * 1.13
            var ph2 = Double(idx) * 2.41
            for i in 0..<count {
                let t = Double(i) / sampleRate
                let attack = min(1.0, t / (0.12 + Double(idx) * 0.025))
                let release = t > 1.10 ? pow(max(0.0, 1.0 - (t - 1.10) / 1.28), 1.85) : 1.0
                // Rising Ki pitch surge right at transformation peak!
                let pitchLift = 1.0 + 0.08 * exp(-pow((t - 0.30) / 0.25, 2.0)) - 0.04 * exp(-t * 7.5)
                let f1 = baseFreq * pitchLift * 0.996
                let f2 = baseFreq * pitchLift * 1.005

                ph1 += twoPi * f1 / sampleRate
                ph2 += twoPi * f2 / sampleRate

                let mod = sin(ph1 * 2.0) * (isUI ? 0.18 : 0.42) * exp(-t * 0.8)
                let osc = tanh((sin(ph1 + mod) + sin(ph2 - mod * 0.6)) * (isUI ? 0.85 : 1.35))
                let throb = 0.84 + 0.16 * sin(twoPi * 18.0 * t + Double(idx))
                let sample = osc * attack * release * throb * weight

                left[i] += sample * panL
                right[i] += sample * panR
            }
        }

        // Layer D: Stereo SSJ2 High-Voltage Bio-Electric Lightning Crackles (3 jagged discharges!)
        addElectricCrackle(at: 0.16, duration: 0.24, pan: -0.58, gain: 0.56, seed: 0x11A4_8921, left: &left, right: &right)
        addElectricCrackle(at: 0.52, duration: 0.28, pan: 0.64, gain: 0.64, seed: 0x77C2_301F, left: &left, right: &right)
        addElectricCrackle(at: 1.02, duration: 0.22, pan: -0.32, gain: 0.46, seed: 0x45E9_BB12, left: &left, right: &right)

        applyCinemaSpaceReverb(left: &left, right: &right, wetMix: isUI ? 0.34 : 0.24, feedback: isUI ? 0.52 : 0.42)
        applyMasterLimiter(left: &left, right: &right, targetPeak: 0.86, tailFadeSeconds: 0.35)
        return encodeStereoWAV(left: left, right: right)
    }

    // MARK: - 2. SSJ2 Lightning Surge (~0.62s)

    static func renderLightningSurgeWAV(theme: SuperSaiyanAuraTheme) -> Data {
        let duration = 0.64
        let count = Int(duration * sampleRate)
        var left = [Double](repeating: 0, count: count)
        var right = [Double](repeating: 0, count: count)

        let root = theme.audioRootHz

        // Punchy short Ki burst whoosh
        var rng: UInt64 = 0x51A7_E012_4491_C38B
        var lpL = 0.0, lpR = 0.0, hpL = 0.0, hpR = 0.0
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let env = min(1.0, t / 0.015) * exp(-t * 6.4)
            let cutoff = 420.0 + 2400.0 * exp(-t * 8.0)
            let alpha = min(0.5, (twoPi * cutoff) / sampleRate)
            let nL = nextNoise(&rng)
            let nR = nextNoise(&rng)
            lpL += alpha * (nL - lpL); hpL += 0.04 * (lpL - hpL)
            lpR += alpha * (nR - lpR); hpR += 0.04 * (lpR - hpR)

            left[i] += (lpL - hpL) * env * 0.42
            right[i] += (lpR - hpR) * env * 0.42
        }

        // Crisp harmonic Ki flash tuned to the selected form
        var ph = 0.0
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let env = min(1.0, t / 0.006) * exp(-t * 7.5)
            let f = root * 4.0 * (1.0 + 0.14 * exp(-t * 16.0))
            ph += twoPi * f / sampleRate
            let s = (sin(ph) * 0.65 + sin(ph * 1.5) * 0.35) * env * 0.24
            left[i] += s
            right[i] += s
        }

        // Double stereo high-voltage SSJ2 arc crackle
        addElectricCrackle(at: 0.005, duration: 0.22, pan: -0.45, gain: 0.66, seed: 0xA812_9F40, left: &left, right: &right)
        addElectricCrackle(at: 0.14, duration: 0.18, pan: 0.52, gain: 0.48, seed: 0x33D0_771E, left: &left, right: &right)

        applyCinemaSpaceReverb(left: &left, right: &right, wetMix: 0.22, feedback: 0.36)
        applyMasterLimiter(left: &left, right: &right, targetPeak: 0.80, tailFadeSeconds: 0.12)
        return encodeStereoWAV(left: left, right: right)
    }

    // MARK: - 3. Power-Down Ki Settle (~0.92s)

    static func renderPowerDownSettleWAV(theme: SuperSaiyanAuraTheme) -> Data {
        let duration = 0.92
        let count = Int(duration * sampleRate)
        var left = [Double](repeating: 0, count: count)
        var right = [Double](repeating: 0, count: count)

        let root = theme.audioRootHz
        var rng: UInt64 = 0x229A_4F10_8C1E_67D1
        var lpL = 0.0, lpR = 0.0, hpL = 0.0, hpR = 0.0

        for i in 0..<count {
            let t = Double(i) / sampleRate
            let env = min(1.0, t / 0.04) * pow(max(0.0, 1.0 - t / duration), 1.8)
            // Descending warm air-dispersion sweep
            let cutoff = 220.0 + 1850.0 * pow(max(0.0, 1.0 - t / duration), 2.1)
            let alpha = min(0.48, (twoPi * cutoff) / sampleRate)
            lpL += alpha * (nextNoise(&rng) - lpL); hpL += 0.03 * (lpL - hpL)
            lpR += alpha * (nextNoise(&rng) - lpR); hpR += 0.03 * (lpR - hpR)

            left[i] += (lpL - hpL) * env * 0.34
            right[i] += (lpR - hpR) * env * 0.34
        }

        // Resolving warm harmonic chime
        let notes = [root * 4.0, root * 6.0, root * 8.0]
        for (idx, freq) in notes.enumerated() {
            let start = Double(idx) * 0.035
            let startIdx = Int(start * sampleRate)
            let pan = Double(idx - 1) * 0.25
            let panL = sqrt(0.5 * (1.0 - pan))
            let panR = sqrt(0.5 * (1.0 + pan))
            for i in startIdx..<count {
                let t = Double(i - startIdx) / sampleRate
                let env = min(1.0, t / 0.012) * exp(-t * 4.2)
                let s = (sin(twoPi * freq * t) + 0.22 * sin(twoPi * freq * 2.0 * t)) * env * 0.16
                left[i] += s * panL
                right[i] += s * panR
            }
        }

        applyCinemaSpaceReverb(left: &left, right: &right, wetMix: 0.28, feedback: 0.44)
        applyMasterLimiter(left: &left, right: &right, targetPeak: 0.72, tailFadeSeconds: 0.22)
        return encodeStereoWAV(left: left, right: right)
    }

    // MARK: - 4. Seamless Living Super Saiyan Aura Hum Loop (~3.20s)

    static func renderSeamlessAuraLoopWAV(theme: SuperSaiyanAuraTheme) -> Data {
        let duration = 3.20
        let count = Int(duration * sampleRate)
        var rawL = [Double](repeating: 0, count: count)
        var rawR = [Double](repeating: 0, count: count)

        let root = theme.audioRootHz
        let isUI = theme == .ultraInstinct

        // Quantize frequencies to exact integer cycles over `duration` so loop wrap is 100% clickless!
        func quantize(_ hz: Double) -> Double {
            max(1.0, (hz * duration).rounded()) / duration
        }

        let f1 = quantize(root)
        let f2 = quantize(root * 1.5)
        let f3 = quantize(root * 2.0)
        let f4 = quantize(root * (isUI ? 6.0 : 3.0))
        let throbHz = quantize(isUI ? 22.0 : 26.0)
        let slowBreathHz = quantize(0.625) // exactly 2 cycles per 3.2s

        var rng: UInt64 = 0x77C1_9402_5E3B_A110
        var lpL = 0.0, lpR = 0.0, hpL = 0.0, hpR = 0.0

        for i in 0..<count {
            let t = Double(i) / sampleRate
            let breath = 0.80 + 0.20 * sin(twoPi * slowBreathHz * t)
            let throbL = 0.74 + 0.26 * sin(twoPi * throbHz * t)
            let throbR = 0.74 + 0.26 * sin(twoPi * throbHz * t + 0.7)

            let drone =
                0.38 * sin(twoPi * f1 * t) +
                0.24 * sin(twoPi * f2 * t + 0.4) +
                0.18 * sin(twoPi * f3 * t + 1.1) +
                (isUI ? 0.14 : 0.08) * sin(twoPi * f4 * t + 2.0)

            let cutoff = (isUI ? 780.0 : 560.0) + 280.0 * breath
            let alpha = min(0.35, (twoPi * cutoff) / sampleRate)
            lpL += alpha * (nextNoise(&rng) - lpL); hpL += 0.025 * (lpL - hpL)
            lpR += alpha * (nextNoise(&rng) - lpR); hpR += 0.025 * (lpR - hpR)

            rawL[i] = (drone * 0.42 + (lpL - hpL) * 0.58) * throbL * breath
            rawR[i] = (drone * 0.42 + (lpR - hpR) * 0.58) * throbR * breath
        }

        // Subtle periodic electric plasma micro-sparks inside the loop
        addElectricCrackle(at: 0.72, duration: 0.14, pan: -0.50, gain: 0.22, seed: 0x9103_44A1, left: &rawL, right: &rawR)
        addElectricCrackle(at: 2.18, duration: 0.15, pan: 0.48, gain: 0.20, seed: 0x3F82_C019, left: &rawL, right: &rawR)

        // Seamless overlap-add crossfade over the last 0.25s onto the first 0.25s
        let xfade = Int(0.25 * sampleRate)
        var outL = rawL
        var outR = rawR
        for i in 0..<xfade {
            let u = Double(i) / Double(xfade)
            let fadeIn = sin(u * Double.pi * 0.5)
            let fadeOut = cos(u * Double.pi * 0.5)
            let tailIdx = count - xfade + i
            outL[i] = rawL[i] * fadeIn + rawL[tailIdx] * fadeOut
            outR[i] = rawR[i] * fadeIn + rawR[tailIdx] * fadeOut
        }
        let loopCount = count - xfade
        var finalL = Array(outL.prefix(loopCount))
        var finalR = Array(outR.prefix(loopCount))

        // Normalize gently without end-fading (so loop stays seamless!)
        var peak = 0.001
        for i in 0..<loopCount {
            finalL[i] = tanh(finalL[i] * 1.15)
            finalR[i] = tanh(finalR[i] * 1.15)
            peak = max(peak, max(abs(finalL[i]), abs(finalR[i])))
        }
        let scale = 0.65 / peak
        for i in 0..<loopCount {
            finalL[i] *= scale
            finalR[i] *= scale
        }

        return encodeStereoWAV(left: finalL, right: finalR)
    }

    // MARK: - Physically-Modeled High-Voltage SSJ2 Electric Crackle Generator

    private static func addElectricCrackle(
        at start: Double,
        duration: Double,
        pan: Double,
        gain: Double,
        seed: UInt64,
        left: inout [Double],
        right: inout [Double]
    ) {
        let startIdx = max(0, Int(start * sampleRate))
        let endIdx = min(left.count, startIdx + Int(duration * sampleRate))
        guard endIdx > startIdx else { return }

        var rng = seed ^ 0xA5A5_1234_5678_9ABC
        let panL = sqrt(0.5 * (1.0 - pan))
        let panR = sqrt(0.5 * (1.0 + pan))

        // 3 micro-arcs per lightning discharge ("BZZ-KRAAK!")
        var bp = 0.0
        var hp = 0.0
        var zapPhase = 0.0

        for i in startIdx..<endIdx {
            let t = Double(i - startIdx) / sampleRate
            let norm = t / max(0.01, duration)

            // Rapid jagged stutter envelope simulating real electrical arc re-strikes
            let burst1 = exp(-t * 28.0)
            let burst2 = t > 0.042 ? exp(-(t - 0.042) * 34.0) * 0.85 : 0.0
            let burst3 = t > 0.095 ? exp(-(t - 0.095) * 40.0) * 0.60 : 0.0
            let stutter = burst1 + burst2 + burst3
            guard stutter > 0.002 else { continue }

            let n = nextNoise(&rng)
            // High-frequency crisp electric spark impulse (3.4kHz - 6.8kHz)
            let sparkSpike = abs(n) > 0.74 ? n * 2.4 : n * 0.45
            bp += 0.46 * (sparkSpike - bp)
            hp += 0.22 * (bp - hp)
            let crackle = bp - hp

            // Metallic ionized buzz pitch-sweep (1.9kHz -> 620Hz)
            let zapHz = 620.0 + 1450.0 * (1.0 - norm)
            zapPhase += twoPi * zapHz / sampleRate
            let buzz = tanh(sin(zapPhase) * 2.2) * 0.24

            let out = (crackle * 0.85 + buzz) * stutter * gain
            left[i] += out * panL
            right[i] += out * panR
        }
    }

    // MARK: - Spatial Reverb, Master Limiter & WAV Encoder

    @inline(__always)
    private static func nextNoise(_ state: inout UInt64) -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return (Double(z & 0xFFFF) / 32768.0) - 1.0
    }

    private static func applyCinemaSpaceReverb(
        left: inout [Double],
        right: inout [Double],
        wetMix: Double,
        feedback: Double
    ) {
        let count = left.count
        let delaysL = [1129, 1481, 1877]
        let delaysR = [1187, 1543, 1931]
        var wetL = [Double](repeating: 0, count: count)
        var wetR = [Double](repeating: 0, count: count)

        for c in 0..<delaysL.count {
            let dL = delaysL[c]
            let dR = delaysR[c]
            var bufL = [Double](repeating: 0, count: dL)
            var bufR = [Double](repeating: 0, count: dR)
            var idxL = 0, idxR = 0
            var dampL = 0.0, dampR = 0.0

            for i in 0..<count {
                let oL = bufL[idxL]
                let oR = bufR[idxR]
                dampL = oL * 0.68 + dampL * 0.32
                dampR = oR * 0.68 + dampR * 0.32

                bufL[idxL] = left[i] * 0.78 + right[i] * 0.22 + dampL * feedback
                bufR[idxR] = right[i] * 0.78 + left[i] * 0.22 + dampR * feedback

                wetL[i] += oL * 0.33
                wetR[i] += oR * 0.33

                idxL += 1; if idxL == dL { idxL = 0 }
                idxR += 1; if idxR == dR { idxR = 0 }
            }
        }

        let dry = 1.0 - wetMix * 0.35
        for i in 0..<count {
            left[i] = left[i] * dry + wetL[i] * wetMix
            right[i] = right[i] * dry + wetR[i] * wetMix
        }
    }

    private static func applyMasterLimiter(
        left: inout [Double],
        right: inout [Double],
        targetPeak: Double,
        tailFadeSeconds: Double
    ) {
        let count = left.count
        guard count > 0 else { return }

        var peak = 0.0001
        for i in 0..<count {
            let l = tanh(left[i] * 1.18)
            let r = tanh(right[i] * 1.18)
            left[i] = l
            right[i] = r
            peak = max(peak, max(abs(l), abs(r)))
        }

        let scale = targetPeak / peak
        let fadeIn = min(count / 8, Int(0.006 * sampleRate))
        let fadeOut = min(count / 2, Int(tailFadeSeconds * sampleRate))

        for i in 0..<count {
            var env = 1.0
            if i < fadeIn {
                let u = Double(i) / Double(max(1, fadeIn))
                env *= 0.5 - 0.5 * cos(Double.pi * u)
            }
            let fromEnd = count - 1 - i
            if fromEnd < fadeOut {
                let u = Double(fromEnd) / Double(max(1, fadeOut))
                let raised = 0.5 - 0.5 * cos(Double.pi * u)
                env *= raised * raised
            }
            left[i] *= scale * env
            right[i] *= scale * env
        }
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
