//
//  SoundEngine.swift
//  Procedurally synthesised sound effects.
//
//  Every sound in the game is generated as PCM at launch rather than shipped as
//  an audio file. Three reasons that's the right call here:
//
//   1. A card sound *is* a synthesis problem — a flick is a short burst of
//      band-passed noise with a fast decay; a chip click is a damped sine. Files
//      would just be recordings of these formulas.
//   2. Zero bundle weight, zero licensing questions, and no attribution debt.
//   3. Parameters are tunable in code, so the tally tick can be pitched by how
//      close the tally is to 99 — impossible with a fixed file.
//
//  Buffers are built once on a background queue and cached; playback is a
//  scheduled buffer on a player node, which is cheap enough to fire on every
//  card.
//

import Foundation
import AVFoundation

@MainActor
final class SoundEngine {
    static let shared = SoundEngine()

    var isEnabled: Bool = true {
        didSet { if isEnabled { activate() } else { deactivate() } }
    }

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    /// A small pool of player nodes so overlapping sounds don't cut each other
    /// off — dealing fires eight flicks in half a second.
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var isRunning = false

    private let sampleRate: Double = 44_100
    private lazy var format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

    private init() {}

    // MARK: - Vocabulary

    enum Sound: Hashable, CaseIterable {
        /// Card sliding off the hand.
        case cardFlick
        /// Card landing on the pile.
        case cardLand
        /// Card being picked up.
        case cardLift
        /// Shuffling the deck.
        case shuffle
        /// The tally ticking. Pitch rises with pressure, so this is parameterised.
        case tickLow
        case tickMid
        case tickHigh
        /// A 9 slamming home — a struck gong.
        case slam
        /// Reaching 100.
        case hundred
        /// Suit lock — a metallic latch.
        case lock
        /// Turn order reversing — a rising then falling sweep.
        case reverse
        /// Snackoo — a bright triple chime.
        case snackoo
        /// A queen being poisoned — a dark descending tone.
        case poison
        /// Well reveal drum roll.
        case wellRoll
        /// Surviving the well.
        case wellSurvive
        /// Elimination.
        case eliminated
        /// Victory fanfare.
        case victory
        /// Illegal tap.
        case reject
        /// UI tap.
        case tap
    }

    // MARK: - Lifecycle

    func warmUp() {
        guard buffers.isEmpty else { return }
        // Synthesis is pure maths over a few thousand samples per sound; doing it
        // off the main thread keeps launch smooth.
        let format = self.format
        let sampleRate = self.sampleRate
        Task.detached(priority: .utility) {
            var built: [Sound: AVAudioPCMBuffer] = [:]
            for sound in Sound.allCases {
                if let buffer = Synthesiser.render(sound, format: format, sampleRate: sampleRate) {
                    built[sound] = buffer
                }
            }
            await MainActor.run { [built] in
                self.buffers = built
                if self.isEnabled { self.activate() }
            }
        }
    }

    private func activate() {
        guard !isRunning, !buffers.isEmpty else { return }
        do {
            // .ambient with mixWithOthers: this is a card game, not a music app —
            // it must never interrupt whatever the player is listening to, and it
            // must respect the physical silent switch.
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)

            engine.attach(mixer)
            engine.connect(mixer, to: engine.mainMixerNode, format: format)

            for _ in 0..<6 {
                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: mixer, format: format)
                players.append(player)
            }
            mixer.outputVolume = 0.85

            try engine.start()
            for player in players { player.play() }
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    private func deactivate() {
        guard isRunning else { return }
        for player in players { player.stop() }
        engine.stop()
        players.removeAll()
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    // MARK: - Playback

    func play(_ sound: Sound, volume: Float = 1.0) {
        guard isEnabled, isRunning, let buffer = buffers[sound], !players.isEmpty else { return }
        let player = players[nextPlayer % players.count]
        nextPlayer += 1
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }

    /// The tally tick, pitched by how close the tally now is to the ceiling.
    /// Rising pitch as the tally climbs is a second, wordless channel telling the
    /// player how much trouble they're in.
    func playTick(pressure: Double) {
        let p = min(max(pressure, 0), 1)
        switch p {
        case ..<0.4: play(.tickLow, volume: 0.7)
        case ..<0.78: play(.tickMid, volume: 0.8)
        default: play(.tickHigh, volume: 0.95)
        }
    }
}

// MARK: - Synthesis

/// Pure DSP. Each sound is a short additive/subtractive recipe rendered into a
/// stereo PCM buffer.
private enum Synthesiser {

    static func render(_ sound: Sound, format: AVAudioFormat, sampleRate: Double) -> AVAudioPCMBuffer? {
        let samples = voice(sound, sampleRate: sampleRate)
        guard !samples.isEmpty else { return nil }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)

        guard let channels = buffer.floatChannelData else { return nil }
        let channelCount = Int(format.channelCount)
        for index in 0..<samples.count {
            let value = max(-1, min(1, samples[index]))
            for channel in 0..<channelCount {
                channels[channel][index] = value
            }
        }
        return buffer
    }

    typealias Sound = SoundEngine.Sound

    // MARK: Recipes

    private static func voice(_ sound: Sound, sampleRate: Double) -> [Float] {
        switch sound {
        case .cardFlick:
            // Band-passed noise with a very fast decay: the sound of a card edge
            // sliding across another card.
            return noise(duration: 0.085, sampleRate: sampleRate, decay: 42, bandpass: 2600, q: 1.4, gain: 0.34)

        case .cardLand:
            // Lower, softer noise burst plus a faint low thud for the impact.
            var out = noise(duration: 0.12, sampleRate: sampleRate, decay: 30, bandpass: 1300, q: 1.1, gain: 0.30)
            mix(&out, sine(frequency: 96, duration: 0.10, sampleRate: sampleRate, decay: 45, gain: 0.16))
            return out

        case .cardLift:
            return noise(duration: 0.055, sampleRate: sampleRate, decay: 60, bandpass: 3400, q: 1.8, gain: 0.18)

        case .shuffle:
            // Seven overlapping flicks at irregular intervals reads as a riffle.
            var out = [Float](repeating: 0, count: Int(0.62 * sampleRate))
            var generator = SeededGenerator(seed: 0x5EED)
            for index in 0..<9 {
                let offset = Int((0.02 + Double(index) * 0.062) * sampleRate)
                let jitter = Double(generator.next() % 900) / 100_000.0
                let burst = noise(
                    duration: 0.07, sampleRate: sampleRate,
                    decay: 46, bandpass: 2200 + Double(generator.next() % 1400), q: 1.3, gain: 0.22
                )
                mix(&out, burst, at: offset + Int(jitter * sampleRate))
            }
            return out

        case .tickLow: return tick(frequency: 520, sampleRate: sampleRate)
        case .tickMid: return tick(frequency: 720, sampleRate: sampleRate)
        case .tickHigh: return tick(frequency: 1_020, sampleRate: sampleRate)

        case .slam:
            // A struck gong: a low fundamental with inharmonic partials and a long
            // decay, plus a noise transient for the strike itself.
            var out = noise(duration: 0.06, sampleRate: sampleRate, decay: 70, bandpass: 3000, q: 1.0, gain: 0.30)
            let partials: [(Double, Double, Float)] = [
                (110, 2.2, 0.28), (164, 2.8, 0.20), (247, 3.6, 0.14),
                (293, 4.4, 0.10), (417, 5.6, 0.07),
            ]
            for (frequency, decay, gain) in partials {
                mix(&out, sine(
                    frequency: frequency, duration: 1.1, sampleRate: sampleRate,
                    decay: decay, gain: gain
                ))
            }
            return out

        case .hundred:
            // Bright, slightly unsettling: a major triad with a tritone on top.
            var out = [Float](repeating: 0, count: Int(1.3 * sampleRate))
            for (index, frequency) in [523.25, 659.25, 783.99, 1_108.73].enumerated() {
                mix(&out, sine(
                    frequency: frequency, duration: 1.2, sampleRate: sampleRate,
                    decay: 3.0, gain: 0.16
                ), at: Int(Double(index) * 0.035 * sampleRate))
            }
            return out

        case .lock:
            // Metallic latch: two short inharmonic clicks.
            var out = noise(duration: 0.04, sampleRate: sampleRate, decay: 90, bandpass: 4200, q: 2.2, gain: 0.26)
            mix(&out, sine(frequency: 1_760, duration: 0.09, sampleRate: sampleRate, decay: 40, gain: 0.14))
            mix(&out, sine(frequency: 2_640, duration: 0.06, sampleRate: sampleRate, decay: 55, gain: 0.08))
            mix(&out, noise(duration: 0.05, sampleRate: sampleRate, decay: 70, bandpass: 3200, q: 2.0, gain: 0.20),
                at: Int(0.055 * sampleRate))
            return out

        case .reverse:
            // A pitch sweep up then down — the clearest possible "direction
            // changed" cue without words.
            return sweep(
                from: 420, to: 980, duration: 0.16, sampleRate: sampleRate, gain: 0.18
            ) + sweep(
                from: 980, to: 420, duration: 0.18, sampleRate: sampleRate, gain: 0.18
            )

        case .snackoo:
            // Three rising bells — playful, because Snackoo is the fun rule.
            var out = [Float](repeating: 0, count: Int(0.8 * sampleRate))
            for (index, frequency) in [880.0, 1_174.66, 1_567.98].enumerated() {
                mix(&out, bell(
                    frequency: frequency, duration: 0.5, sampleRate: sampleRate, gain: 0.20
                ), at: Int(Double(index) * 0.085 * sampleRate))
            }
            return out

        case .poison:
            // Descending, detuned, and slightly sour.
            var out = sweep(from: 340, to: 120, duration: 0.42, sampleRate: sampleRate, gain: 0.17)
            mix(&out, sweep(from: 347, to: 123, duration: 0.42, sampleRate: sampleRate, gain: 0.12))
            return out

        case .wellRoll:
            // Accelerating low thuds — a drum roll that resolves on the reveal.
            var out = [Float](repeating: 0, count: Int(0.95 * sampleRate))
            var time = 0.0
            var interval = 0.085
            while time < 0.78 {
                mix(&out, sine(
                    frequency: 78, duration: 0.09, sampleRate: sampleRate, decay: 40, gain: 0.22
                ), at: Int(time * sampleRate))
                time += interval
                interval *= 0.86 // accelerate
            }
            return out

        case .wellSurvive:
            var out = [Float](repeating: 0, count: Int(0.9 * sampleRate))
            for (index, frequency) in [659.25, 830.61, 987.77].enumerated() {
                mix(&out, bell(
                    frequency: frequency, duration: 0.65, sampleRate: sampleRate, gain: 0.19
                ), at: Int(Double(index) * 0.07 * sampleRate))
            }
            return out

        case .eliminated:
            // A low, dead thud with a long downward sweep under it.
            var out = sine(frequency: 88, duration: 0.9, sampleRate: sampleRate, decay: 4.5, gain: 0.30)
            mix(&out, sweep(from: 220, to: 55, duration: 0.85, sampleRate: sampleRate, gain: 0.16))
            mix(&out, noise(duration: 0.09, sampleRate: sampleRate, decay: 34, bandpass: 700, q: 0.9, gain: 0.22))
            return out

        case .victory:
            // Rising arpeggio into a sustained major chord.
            var out = [Float](repeating: 0, count: Int(1.9 * sampleRate))
            let arpeggio: [Double] = [523.25, 659.25, 783.99, 1_046.50]
            for (index, frequency) in arpeggio.enumerated() {
                mix(&out, bell(
                    frequency: frequency, duration: 0.5, sampleRate: sampleRate, gain: 0.17
                ), at: Int(Double(index) * 0.11 * sampleRate))
            }
            for frequency in [523.25, 659.25, 783.99] {
                mix(&out, sine(
                    frequency: frequency, duration: 1.3, sampleRate: sampleRate, decay: 2.4, gain: 0.13
                ), at: Int(0.46 * sampleRate))
            }
            return out

        case .reject:
            // Short, low, and blunt. Deliberately not a buzzer.
            var out = sine(frequency: 150, duration: 0.10, sampleRate: sampleRate, decay: 34, gain: 0.22)
            mix(&out, sine(frequency: 142, duration: 0.10, sampleRate: sampleRate, decay: 34, gain: 0.16),
                at: Int(0.055 * sampleRate))
            return out

        case .tap:
            return sine(frequency: 1_180, duration: 0.035, sampleRate: sampleRate, decay: 110, gain: 0.13)
        }
    }

    // MARK: Primitives

    private static func tick(frequency: Double, sampleRate: Double) -> [Float] {
        var out = sine(frequency: frequency, duration: 0.07, sampleRate: sampleRate, decay: 65, gain: 0.16)
        mix(&out, noise(duration: 0.02, sampleRate: sampleRate, decay: 160, bandpass: frequency * 3, q: 2.0, gain: 0.10))
        return out
    }

    /// Exponentially decaying sine.
    private static func sine(
        frequency: Double, duration: Double, sampleRate: Double,
        decay: Double, gain: Float
    ) -> [Float] {
        let count = Int(duration * sampleRate)
        var out = [Float](repeating: 0, count: count)
        let increment = 2 * Double.pi * frequency / sampleRate
        for index in 0..<count {
            let time = Double(index) / sampleRate
            let envelope = exp(-decay * time)
            out[index] = Float(sin(increment * Double(index)) * envelope) * gain
        }
        return applyFadeOut(out)
    }

    /// Struck-bell timbre: fundamental plus stretched inharmonic partials.
    private static func bell(frequency: Double, duration: Double, sampleRate: Double, gain: Float) -> [Float] {
        var out = sine(frequency: frequency, duration: duration, sampleRate: sampleRate, decay: 5.0, gain: gain)
        mix(&out, sine(frequency: frequency * 2.76, duration: duration * 0.6, sampleRate: sampleRate,
                       decay: 9.0, gain: gain * 0.35))
        mix(&out, sine(frequency: frequency * 5.40, duration: duration * 0.35, sampleRate: sampleRate,
                       decay: 15.0, gain: gain * 0.18))
        return out
    }

    /// Linear frequency sweep.
    private static func sweep(
        from start: Double, to end: Double, duration: Double,
        sampleRate: Double, gain: Float
    ) -> [Float] {
        let count = Int(duration * sampleRate)
        var out = [Float](repeating: 0, count: count)
        var phase = 0.0
        for index in 0..<count {
            let t = Double(index) / Double(max(1, count - 1))
            let frequency = start + (end - start) * t
            phase += 2 * Double.pi * frequency / sampleRate
            // Gentle bell-shaped envelope so sweeps don't click at either end.
            let envelope = sin(Double.pi * t)
            out[index] = Float(sin(phase) * envelope) * gain
        }
        return applyFadeOut(out)
    }

    /// Band-passed white noise with an exponential decay — the workhorse for
    /// every card and paper sound.
    private static func noise(
        duration: Double, sampleRate: Double, decay: Double,
        bandpass frequency: Double, q: Double, gain: Float
    ) -> [Float] {
        let count = Int(duration * sampleRate)
        var out = [Float](repeating: 0, count: count)
        var generator = SeededGenerator(seed: UInt32(truncatingIfNeeded: Int(frequency) &* 2_654_435_761))

        // Two-pole state-variable band-pass.
        let f = 2 * sin(Double.pi * min(frequency, sampleRate * 0.45) / sampleRate)
        let damping = 1.0 / max(0.5, q)
        var low = 0.0, band = 0.0

        for index in 0..<count {
            let time = Double(index) / sampleRate
            let white = Double(generator.next() % 20_001) / 10_000.0 - 1.0
            let high = white - low - damping * band
            band += f * high
            low += f * band
            let envelope = exp(-decay * time)
            out[index] = Float(band * envelope) * gain
        }
        return applyFadeOut(out)
    }

    /// Every buffer gets a short fade-out. Without it, a truncated waveform
    /// produces an audible click on every playback.
    private static func applyFadeOut(_ samples: [Float]) -> [Float] {
        var out = samples
        let fade = min(220, out.count / 4)
        guard fade > 1 else { return out }
        for index in 0..<fade {
            let scale = Float(fade - index) / Float(fade)
            out[out.count - fade + index] *= scale
        }
        return out
    }

    private static func mix(_ destination: inout [Float], _ source: [Float], at offset: Int = 0) {
        if destination.count < offset + source.count {
            destination.append(contentsOf: [Float](repeating: 0, count: offset + source.count - destination.count))
        }
        for index in 0..<source.count {
            destination[offset + index] += source[index]
        }
    }
}
