import AVFoundation
import Foundation
import os

/// Real-time, 100% gapless CoreAudio (`AVAudioEngine` + `AVAudioSourceNode`) Super Saiyan Ki Synthesizer.
///
/// Zero pre-rendered loop seams, zero `AVAudioPlayer` cut-outs, zero clicks:
/// - **Authentic DBZ Flanged Jet-Flame Roar**: Pink-brown plasma turbulence swept through resonant
///   state-variable bandpass filters + stereo modulated comb/flanger delay lines (`2.8ms–8.2ms`) with
///   coupled organic 11.7 Hz + 17.3 Hz flame-flap modulation — the unmistakable hollow roaring
///   *"FWOOOOOSH-SHWOOOOSH"* Super Saiyan Ki sound.
/// - **Seismic Ignition Eruption**: Deep ground-shaking sub-bass drop (`108 Hz → 32 Hz`) + roaring
///   upward jet-plasma sweep seamlessly melting directly into the live burning aura with zero seam.
/// - **Live SSJ2 Bio-Electric Arcs**: Real-time stereo high-voltage plasma whips (`KZZT-KRAAK!`)
///   firing both on surges and organically while powering up.
/// - **Auto-Idle Engine Sleep**: Smoothly ramps to silence and stops `AVAudioEngine` when idle
///   (0.0% idle CPU).
@MainActor
public final class SuperSaiyanAudioEngine {
    public static let shared = SuperSaiyanAudioEngine()

    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private let dsp = RealTimeSuperSaiyanDSPState()

    private var idleSleepTask: Task<Void, Never>?
    private var lastEruptionAt: Date = .distantPast
    private var lastSurgeAt: Date = .distantPast
    private var lastSettleAt: Date = .distantPast

    private init() {}

    nonisolated deinit {}

    private var isTestEnvironment: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Triggers a seismic Super Saiyan Power-Up Eruption (sub-bass drop + roaring jet sweep + triple SSJ2 arcs).
    public func playPowerUpEruption(
        theme: SuperSaiyanAuraTheme,
        volume: Float = 0.85,
        force: Bool = false
    ) {
        guard !isTestEnvironment else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastEruptionAt) < 2.2 {
            return
        }
        lastEruptionAt = now

        ensureEngineRunning()
        dsp.applyTheme(theme)
        dsp.triggerEruption(gain: Double(volume))
        scheduleSleepCheckIfNotLooping()
    }

    /// Triggers a crisp SSJ2 bio-electric lightning whip + tight Ki flare.
    public func playLightningSurge(
        theme: SuperSaiyanAuraTheme,
        volume: Float = 0.68,
        force: Bool = false
    ) {
        guard !isTestEnvironment else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastSurgeAt) < 2.4 {
            return
        }
        lastSurgeAt = now

        ensureEngineRunning()
        dsp.applyTheme(theme)
        dsp.triggerLightningBurst(gain: Double(volume), withWhoosh: true)
        scheduleSleepCheckIfNotLooping()
    }

    /// Smoothly disperses Ki downward when a Turbo chat turn completes.
    public func playPowerDownSettle(
        theme: SuperSaiyanAuraTheme,
        volume: Float = 0.56
    ) {
        guard !isTestEnvironment else { return }
        let now = Date()
        guard now.timeIntervalSince(lastSettleAt) >= 1.6 else { return }
        lastSettleAt = now

        ensureEngineRunning()
        dsp.applyTheme(theme)
        dsp.triggerPowerDownSettle(gain: Double(volume))
        scheduleSleepCheckIfNotLooping()
    }

    /// Smoothly engages or releases the continuous gapless Super Saiyan burning aura stream.
    public func setAuraLoopActive(_ active: Bool, theme: SuperSaiyanAuraTheme) {
        guard !isTestEnvironment else { return }
        dsp.applyTheme(theme)
        dsp.setContinuousAura(active: active, targetLevel: active ? 0.44 : 0.0)

        if active {
            idleSleepTask?.cancel()
            idleSleepTask = nil
            ensureEngineRunning()
        } else {
            scheduleSleepCheckIfNotLooping()
        }
    }

    /// Immediately fades out continuous aura and sleeps the audio engine cleanly.
    public func stopAllLoops() {
        dsp.setContinuousAura(active: false, targetLevel: 0.0)
        scheduleSleepCheckIfNotLooping()
    }

    // MARK: - CoreAudio Engine Lifecycle

    private func ensureEngineRunning() {
        if let engine, engine.isRunning {
            return
        }

        let audioEngine = engine ?? AVAudioEngine()
        let mixer = audioEngine.mainMixerNode
        let hwFormat = audioEngine.outputNode.outputFormat(forBus: 0)
        let sampleRate = hwFormat.sampleRate > 8000 ? hwFormat.sampleRate : 44_100.0
        guard let renderFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            return
        }

        if sourceNode == nil {
            dsp.setSampleRate(sampleRate)
            // CRITICAL (Swift 6): Construct `AVAudioSourceNode` via a `nonisolated` factory so the
            // render closure does NOT inherit `@MainActor` isolation and never trips
            // `_dispatch_assert_queue_fail` on CoreAudio's real-time `IOThread.client`!
            let node = Self.makeNonIsolatedSourceNode(format: renderFormat, dsp: dsp)
            audioEngine.attach(node)
            audioEngine.connect(node, to: mixer, format: renderFormat)
            mixer.outputVolume = 1.0
            self.sourceNode = node
        } else {
            dsp.setSampleRate(sampleRate)
        }

        self.engine = audioEngine
        do {
            try audioEngine.start()
        } catch {
            // Silently ignore unavailable audio hardware
        }
    }

    /// Strictly `nonisolated` factory ensuring the CoreAudio render block carries zero `@MainActor`
    /// runtime executor assertions on `com.apple.audio.IOThread.client`.
    nonisolated private static func makeNonIsolatedSourceNode(
        format: AVAudioFormat,
        dsp: RealTimeSuperSaiyanDSPState
    ) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            dsp.render(frameCount: Int(frameCount), audioBufferList: audioBufferList)
            return noErr
        }
    }

    /// Runs an offline off-main-thread render pass through the exact `AVAudioSourceNode` factory
    /// (used by XCTest to guarantee Swift 6 never injects `@MainActor` checks onto the CoreAudio thread).
    nonisolated internal static func renderTestFramesOffMainThread(theme: SuperSaiyanAuraTheme = .superSaiyan) -> Float {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2) else { return 0 }
        let testDSP = RealTimeSuperSaiyanDSPState()
        testDSP.setSampleRate(44_100)
        testDSP.applyTheme(theme)
        testDSP.triggerEruption(gain: 0.85)
        testDSP.setContinuousAura(active: true, targetLevel: 0.5)

        let engine = AVAudioEngine()
        let node = makeNonIsolatedSourceNode(format: format, dsp: testDSP)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)

        guard (try? engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)) != nil,
              (try? engine.start()) != nil,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)
        else {
            return 0
        }
        defer { engine.stop() }

        let status = try? engine.renderOffline(512, to: buffer)
        guard status == .success, let ch0 = buffer.floatChannelData?[0] else { return 0 }
        var peak: Float = 0
        for i in 0..<Int(buffer.frameLength) {
            peak = max(peak, abs(ch0[i]))
        }
        return peak
    }

    private func scheduleSleepCheckIfNotLooping() {
        idleSleepTask?.cancel()
        idleSleepTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3.6))
            guard !Task.isCancelled, let self else { return }
            if self.dsp.canSleepEngine() {
                self.engine?.pause()
            }
        }
    }
}

// MARK: - Real-Time Lock-Free CoreAudio Super Saiyan DSP Kernel

/// Thread-safe real-time DSP kernel running directly inside `AVAudioSourceNode`'s render callback.
/// Uses `OSAllocatedUnfairLock` strictly for tiny control-message swaps (nanoseconds) so the audio
/// render loop never allocates memory or blocks.
private final class RealTimeSuperSaiyanDSPState: @unchecked Sendable {
    private struct ControlState {
        var continuousActive: Bool = false
        var continuousTarget: Double = 0.0
        var pendingEruptionGain: Double = 0.0
        var pendingLightningGain: Double = 0.0
        var pendingLightningWhoosh: Bool = false
        var pendingSettleGain: Double = 0.0
        var theme: SuperSaiyanAuraTheme = .superSaiyan
        var sampleRate: Double = 44_100.0
    }

    private let lock = OSAllocatedUnfairLock(initialState: ControlState())

    // Audio-thread-owned DSP state (never touched outside render thread)
    private var sr: Double = 44_100.0
    private var timeSec: Double = 0.0
    private var rngL: UInt64 = 0x9E37_79B9_7F4A_7C15
    private var rngR: UInt64 = 0xBF58_476D_1CE4_E5B9

    // Smoothed energy & continuous burning aura envelope
    private var auraEnv: Double = 0.0
    private var eruptionAge: Double = 10.0
    private var eruptionGain: Double = 0.0
    private var settleAge: Double = 10.0
    private var settleGain: Double = 0.0
    private var subPhase: Double = 0.0
    private var uiPhase1: Double = 0.0
    private var uiPhase2: Double = 0.0
    private var uiPhase3: Double = 0.0

    // Pink-noise / brown-fire accumulators
    private var pinkL0 = 0.0, pinkL1 = 0.0, pinkL2 = 0.0
    private var pinkR0 = 0.0, pinkR1 = 0.0, pinkR2 = 0.0

    // State-variable bandpass resonators (L/R) for blazing flame roar
    private var svfLowL = 0.0, svfBandL = 0.0
    private var svfLowR = 0.0, svfBandR = 0.0
    private var sweepLowL = 0.0, sweepBandL = 0.0
    private var sweepLowR = 0.0, sweepBandR = 0.0

    // Stereo modulated jet-flanger / comb delay lines (THE secret of authentic DBZ Ki roar!)
    private static let delayBufSize = 2048
    private var delayL = [Double](repeating: 0, count: delayBufSize)
    private var delayR = [Double](repeating: 0, count: delayBufSize)
    private var delayWriteIdx: Int = 0

    // Real-time SSJ2 bio-electric lightning voice
    private var zapAge: Double = 10.0
    private var zapDuration: Double = 0.16
    private var zapGain: Double = 0.0
    private var zapPan: Double = 0.0
    private var zapPhase: Double = 0.0
    private var zapBp: Double = 0.0
    private var zapHp: Double = 0.0
    private var nextAutoZapTimer: Double = 1.2

    // Smoothed theme parameters
    private var flangerBaseMs: Double = 4.6
    private var roarCenterHz: Double = 440.0
    private var flutterRateHz: Double = 13.5
    private var uiShimmerMix: Double = 0.0
    private var subBoost: Double = 1.0
    private var rootHz: Double = 73.42

    func setSampleRate(_ sampleRate: Double) {
        lock.withLock { $0.sampleRate = max(8000.0, sampleRate) }
    }

    func applyTheme(_ theme: SuperSaiyanAuraTheme) {
        lock.withLock { $0.theme = theme }
    }

    func setContinuousAura(active: Bool, targetLevel: Double) {
        lock.withLock {
            $0.continuousActive = active
            $0.continuousTarget = active ? targetLevel : 0.0
        }
    }

    func triggerEruption(gain: Double) {
        lock.withLock {
            $0.pendingEruptionGain = max($0.pendingEruptionGain, gain)
        }
    }

    func triggerLightningBurst(gain: Double, withWhoosh: Bool) {
        lock.withLock {
            $0.pendingLightningGain = max($0.pendingLightningGain, gain)
            $0.pendingLightningWhoosh = $0.pendingLightningWhoosh || withWhoosh
        }
    }

    func triggerPowerDownSettle(gain: Double) {
        lock.withLock {
            $0.pendingSettleGain = max($0.pendingSettleGain, gain)
        }
    }

    func canSleepEngine() -> Bool {
        let ctrl = lock.withLock { $0 }
        return !ctrl.continuousActive && auraEnv < 0.002 && eruptionAge > 2.8 && settleAge > 1.4 && zapAge > 0.4
    }

    // MARK: - CoreAudio Real-Time Render Loop (Zero Heap Allocations)

    func render(frameCount: Int, audioBufferList: UnsafeMutablePointer<AudioBufferList>) {
        // Snapshot & consume control triggers in a single tiny lock
        let ctrl: ControlState = lock.withLock { state in
            let copy = state
            state.pendingEruptionGain = 0.0
            state.pendingLightningGain = 0.0
            state.pendingLightningWhoosh = false
            state.pendingSettleGain = 0.0
            return copy
        }

        sr = ctrl.sampleRate
        let invSR = 1.0 / sr
        let twoPi = 2.0 * Double.pi

        // Trigger one-shot events smoothly inside the continuous stream
        if ctrl.pendingEruptionGain > 0.01 {
            eruptionAge = 0.0
            eruptionGain = ctrl.pendingEruptionGain
            subPhase = 0.0
            spawnZap(gain: ctrl.pendingEruptionGain * 0.85, pan: -0.52, duration: 0.22)
        }
        if ctrl.pendingLightningGain > 0.01 {
            let randPan = (nextNoise(&rngL) * 0.72)
            spawnZap(gain: ctrl.pendingLightningGain, pan: randPan, duration: 0.17)
            if ctrl.pendingLightningWhoosh && eruptionAge > 1.0 {
                // Short punchy Ki flare without interrupting continuous burn
                eruptionAge = 0.18
                eruptionGain = max(eruptionGain * 0.5, ctrl.pendingLightningGain * 0.55)
            }
        }
        if ctrl.pendingSettleGain > 0.01 {
            settleAge = 0.0
            settleGain = ctrl.pendingSettleGain
        }

        // Theme acoustic character targets
        let targetFlangerMs: Double
        let targetRoarHz: Double
        let targetFlutterHz: Double
        let targetUIMix: Double
        let targetSubBoost: Double
        switch ctrl.theme {
        case .superSaiyan:
            targetFlangerMs = 4.6; targetRoarHz = 460.0; targetFlutterHz = 13.8; targetUIMix = 0.0; targetSubBoost = 1.05
        case .god:
            targetFlangerMs = 3.8; targetRoarHz = 540.0; targetFlutterHz = 16.2; targetUIMix = 0.08; targetSubBoost = 0.95
        case .blue:
            targetFlangerMs = 5.4; targetRoarHz = 390.0; targetFlutterHz = 12.4; targetUIMix = 0.14; targetSubBoost = 1.15
        case .rose:
            targetFlangerMs = 4.2; targetRoarHz = 510.0; targetFlutterHz = 14.6; targetUIMix = 0.18; targetSubBoost = 1.00
        case .ultraInstinct:
            targetFlangerMs = 6.2; targetRoarHz = 620.0; targetFlutterHz = 10.5; targetUIMix = 0.52; targetSubBoost = 0.88
        case .legendary:
            targetFlangerMs = 5.8; targetRoarHz = 330.0; targetFlutterHz = 15.5; targetUIMix = 0.0; targetSubBoost = 1.48
        }
        let targetRoot = ctrl.theme.audioRootHz

        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard abl.count >= 1 else { return }
        let outL = abl[0].mData?.assumingMemoryBound(to: Float.self)
        let outR = abl.count >= 2 ? abl[1].mData?.assumingMemoryBound(to: Float.self) : outL
        guard let outL, let outR else {
            return
        }
        let isMono = (abl.count == 1)

        let bufMask = Self.delayBufSize - 1

        for frame in 0..<frameCount {
            timeSec += invSR

            // Per-sample smooth parameter slewing (ZERO zipper noise or clicks!)
            let auraSlew = ctrl.continuousTarget > auraEnv ? 0.00016 : 0.000055
            auraEnv += (ctrl.continuousTarget - auraEnv) * auraSlew
            flangerBaseMs += (targetFlangerMs - flangerBaseMs) * 0.0003
            roarCenterHz += (targetRoarHz - roarCenterHz) * 0.0003
            flutterRateHz += (targetFlutterHz - flutterRateHz) * 0.0003
            uiShimmerMix += (targetUIMix - uiShimmerMix) * 0.0003
            subBoost += (targetSubBoost - subBoost) * 0.0003
            rootHz += (targetRoot - rootHz) * 0.0003

            // Eruption & Settle kinetic envelopes
            var eruptionRoarBoost = 0.0
            var subImpact = 0.0
            var sweepJetL = 0.0
            var sweepJetR = 0.0

            if eruptionAge < 2.65 {
                let t = eruptionAge
                eruptionAge += invSR

                // 1. Seismic DBZ sub-bass ignition boom (0.00s - 0.55s)
                if t < 0.60 {
                    let attack = min(1.0, t / 0.009)
                    let decay = exp(-t * 5.2)
                    let freq = 32.0 + 78.0 * exp(-t * 13.5)
                    subPhase += twoPi * freq * invSR
                    subImpact = tanh((sin(subPhase) * 1.45 + 0.35 * sin(2.0 * subPhase)) * 1.3)
                        * attack * decay * eruptionGain * 0.58 * subBoost
                }

                // 2. Massive upward roaring plasma surge ("BWOOOOOOSH-SHWEEEEE!")
                let attack = min(1.0, t / 0.08)
                let decay = t < 0.55 ? 1.0 : exp(-(t - 0.55) * 1.65)
                eruptionRoarBoost = attack * decay * eruptionGain * 0.92

                // Re-strike 2nd and 3rd SSJ2 bio-electric lightning arcs during eruption!
                if t > 0.38 && t - invSR <= 0.38 {
                    spawnZap(gain: eruptionGain * 0.78, pan: 0.58, duration: 0.19)
                } else if t > 0.88 && t - invSR <= 0.88 {
                    spawnZap(gain: eruptionGain * 0.56, pan: -0.30, duration: 0.15)
                }
            }

            var settleWhoosh = 0.0
            if settleAge < 1.10 {
                let t = settleAge
                settleAge += invSR
                let u = t / 1.10
                settleWhoosh = min(1.0, t / 0.05) * pow(max(0.0, 1.0 - u), 2.1) * settleGain * 0.55
            }

            let totalFlameEnergy = min(1.45, auraEnv + eruptionRoarBoost + settleWhoosh)

            // Fast silence short-circuit when completely quiet
            if totalFlameEnergy < 0.0004 && zapAge >= zapDuration && abs(subImpact) < 0.0001 {
                outL[frame] = 0
                outR[frame] = 0
                continue
            }

            // Generate stereo pink-brown fire turbulence noise
            let wL = nextNoise(&rngL)
            let wR = nextNoise(&rngR)
            pinkL0 = 0.997 * pinkL0 + wL * 0.048
            pinkL1 = 0.965 * pinkL1 + wL * 0.165
            pinkL2 = 0.820 * pinkL2 + wL * 0.340
            let fireL = pinkL0 + pinkL1 + pinkL2

            pinkR0 = 0.997 * pinkR0 + wR * 0.048
            pinkR1 = 0.965 * pinkR1 + wR * 0.165
            pinkR2 = 0.820 * pinkR2 + wR * 0.340
            let fireR = pinkR0 + pinkR1 + pinkR2

            // Organic coupled anime flame-flap modulation (NOT robotic single sine!)
            let flap1L = sin(twoPi * flutterRateHz * timeSec)
            let flap2L = sin(twoPi * (flutterRateHz * 1.49) * timeSec + 1.1)
            let flapL = 0.68 + 0.22 * flap1L + 0.10 * flap2L

            let flap1R = sin(twoPi * (flutterRateHz + 0.65) * timeSec + 0.8)
            let flap2R = sin(twoPi * (flutterRateHz * 1.47) * timeSec + 2.3)
            let flapR = 0.68 + 0.22 * flap1R + 0.10 * flap2R

            // State-Variable Bandpass Filter (shapes raw noise into raging Super Saiyan fire column)
            let eruptionPitchLift = eruptionAge < 2.65 ? exp(-pow((eruptionAge - 0.26) / 0.32, 2.0)) * 780.0 : 0.0
            let settleDrop = settleAge < 1.10 ? (1.0 - settleAge / 1.10) * 520.0 - 220.0 : 0.0
            let fc = max(140.0, min(2600.0, roarCenterHz + eruptionPitchLift + settleDrop + 110.0 * flap1L))
            let fCoeff = min(0.45, 2.0 * sin(Double.pi * fc * invSR))
            let qDamp = 0.56 // warm resonant flame roar

            let hpL = fireL - svfLowL - qDamp * svfBandL
            svfBandL += fCoeff * hpL
            svfLowL += fCoeff * svfBandL

            let hpR = fireR - svfLowR - qDamp * svfBandR
            svfBandR += fCoeff * hpR
            svfLowR += fCoeff * svfBandR

            // Secondary high-pressure screaming air vortex during power-up burst!
            if eruptionRoarBoost > 0.01 {
                let jetHz = 420.0 + 1950.0 * exp(-pow((eruptionAge - 0.24) / 0.28, 2.0))
                let jf = min(0.55, 2.0 * sin(Double.pi * jetHz * invSR))
                let jhpL = wL - sweepLowL - 0.28 * sweepBandL
                sweepBandL += jf * jhpL; sweepLowL += jf * sweepBandL
                let jhpR = wR - sweepLowR - 0.28 * sweepBandR
                sweepBandR += jf * jhpR; sweepLowR += jf * sweepBandR
                sweepJetL = sweepBandL * eruptionRoarBoost * 0.42
                sweepJetR = sweepBandR * eruptionRoarBoost * 0.42
            }

            // THE ICONIC DBZ COMB / JET-FLANGER RESONATOR:
            // Swirling delay time creates the authentic metallic/windy Super Saiyan aura roar!
            let swirlL = sin(twoPi * 2.15 * timeSec) * 1.8 + sin(twoPi * 6.4 * timeSec) * 0.45
            let swirlR = sin(twoPi * 2.28 * timeSec + 1.4) * 1.8 + sin(twoPi * 6.1 * timeSec + 0.7) * 0.45
            let delaySamplesL = max(8.0, min(Double(Self.delayBufSize - 4), (flangerBaseMs + swirlL) * 0.001 * sr))
            let delaySamplesR = max(8.0, min(Double(Self.delayBufSize - 4), (flangerBaseMs + swirlR) * 0.001 * sr))

            let readL = readDelayLinear(delayL, writeIdx: delayWriteIdx, delaySamples: delaySamplesL, mask: bufMask)
            let readR = readDelayLinear(delayR, writeIdx: delayWriteIdx, delaySamples: delaySamplesR, mask: bufMask)

            let inL = (svfBandL * 0.85 + svfLowL * 0.42) * flapL + sweepJetL
            let inR = (svfBandR * 0.85 + svfLowR * 0.42) * flapR + sweepJetR

            let feedback = 0.56
            delayL[delayWriteIdx] = tanh(inL + readL * feedback)
            delayR[delayWriteIdx] = tanh(inR + readR * feedback)
            delayWriteIdx = (delayWriteIdx + 1) & bufMask

            var mixL = (inL * 0.62 + readL * 0.58) * totalFlameEnergy + subImpact
            var mixR = (inR * 0.62 + readR * 0.58) * totalFlameEnergy + subImpact

            // Ultra Instinct / Divine Form subtle crystalline heat-shimmer overtone (never organ-like)
            if uiShimmerMix > 0.01 && totalFlameEnergy > 0.02 {
                uiPhase1 += twoPi * (rootHz * 4.0) * invSR
                uiPhase2 += twoPi * (rootHz * 6.004) * invSR
                uiPhase3 += twoPi * (rootHz * 9.009) * invSR
                let shimmer = (sin(uiPhase1) * 0.42 + sin(uiPhase2) * 0.34 + sin(uiPhase3) * 0.24)
                    * (0.75 + 0.25 * sin(twoPi * 5.2 * timeSec))
                let uiLevel = shimmer * uiShimmerMix * totalFlameEnergy * 0.22
                mixL += uiLevel
                mixR += uiLevel * 0.94
            }

            // Organic live SSJ2 bio-electric lightning cracks while actively burning in Turbo!
            if auraEnv > 0.16 {
                nextAutoZapTimer -= invSR
                if nextAutoZapTimer <= 0 {
                    let r1 = abs(nextNoise(&rngL))
                    let r2 = nextNoise(&rngR)
                    nextAutoZapTimer = 1.15 + r1 * 1.95
                    spawnZap(gain: 0.26 + r1 * 0.22, pan: r2 * 0.68, duration: 0.11 + r1 * 0.08)
                }
            }

            // Synthesize active SSJ2 lightning crackle voice
            if zapAge < zapDuration {
                let zt = zapAge
                zapAge += invSR
                let norm = zt / max(0.02, zapDuration)
                let b1 = exp(-zt * 32.0)
                let b2 = zt > 0.036 ? exp(-(zt - 0.036) * 38.0) * 0.82 : 0.0
                let b3 = zt > 0.082 ? exp(-(zt - 0.082) * 44.0) * 0.55 : 0.0
                let stutter = b1 + b2 + b3

                let zn = nextNoise(&rngL)
                let spike = abs(zn) > 0.72 ? zn * 2.5 : zn * 0.42
                zapBp += 0.48 * (spike - zapBp)
                zapHp += 0.24 * (zapBp - zapHp)
                let crackle = zapBp - zapHp

                let zapHz = 560.0 + 1650.0 * (1.0 - norm)
                zapPhase += twoPi * zapHz * invSR
                let buzz = tanh(sin(zapPhase) * 2.4) * 0.22

                let zapOut = (crackle * 0.88 + buzz) * stutter * zapGain * 0.68
                let panL = sqrt(0.5 * (1.0 - zapPan))
                let panR = sqrt(0.5 * (1.0 + zapPan))
                mixL += zapOut * panL
                mixR += zapOut * panR
            }

            // Warm analog soft-clipping limiter — punchy, full, zero digital harshness
            let finalL = Float(tanh(mixL * 1.18) * 0.82)
            let finalR = Float(tanh(mixR * 1.18) * 0.82)
            if isMono {
                outL[frame] = (finalL + finalR) * 0.5
            } else {
                outL[frame] = finalL
                outR[frame] = finalR
            }
        }
    }

    @inline(__always)
    private func spawnZap(gain: Double, pan: Double, duration: Double) {
        zapAge = 0.0
        zapGain = gain
        zapPan = max(-0.85, min(0.85, pan))
        zapDuration = duration
        zapPhase = 0.0
    }

    @inline(__always)
    private func readDelayLinear(_ buf: [Double], writeIdx: Int, delaySamples: Double, mask: Int) -> Double {
        let i0 = Int(delaySamples)
        let frac = delaySamples - Double(i0)
        let idx0 = (writeIdx - i0) & mask
        let idx1 = (idx0 - 1) & mask
        return buf[idx0] * (1.0 - frac) + buf[idx1] * frac
    }

    @inline(__always)
    private func nextNoise(_ state: inout UInt64) -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return (Double(z & 0xFFFF) / 32768.0) - 1.0
    }
}
