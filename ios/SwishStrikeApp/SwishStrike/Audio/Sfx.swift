import AVFoundation
import SwishStrikeCore
import os

/// Synthesized game sounds — the Swift mirror of web-prototype/js/sfx.js. Every
/// effect is rendered ONCE at init into a PCM buffer (44.1 kHz mono); the repo
/// and the app bundle ship zero audio files, the same license-clean stance as
/// the generated art. The audio session is `.ambient`, so Swish Strike never interrupts
/// the user's music. Every public path is guarded: if the engine fails, the app
/// plays nothing and never crashes.
@MainActor
final class Sfx {
    static let shared = Sfx()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
    private var buffers: [Effect: AVAudioPCMBuffer] = [:]
    private var started = false
    private let log = Logger(subsystem: Log.subsystem, category: "sfx")

    enum Effect: CaseIterable {
        case swish, rim, pop, miss, streak, personalBest
    }

    private init() {
        guard let format else { return }
        // Deterministic xorshift noise, local to the render (no global state —
        // Swift 6 forbids mutable statics, and the render must be reproducible).
        var noiseState: UInt64 = 0x9E37_79B9_7F4A_7C15
        func noise() -> Double {
            noiseState ^= noiseState << 13
            noiseState ^= noiseState >> 7
            noiseState ^= noiseState << 17
            return Double(noiseState % 2_000_001) / 1_000_000 - 1
        }
        buffers[.swish] = Synth.render(format: format, duration: 0.34) { t, k in
            // Filtered-noise whoosh: noise shaped by a falling tone, fading out.
            let sweepHz = 2_800 - 2_150 * k
            let tone = 0.4 + 0.6 * abs(sin(2 * Double.pi * sweepHz * t))
            return Float(noise() * 0.5 * (1 - k) * tone)
        }
        buffers[.rim] = Synth.sequence(format: format, notes: [
            (freq: 430, dur: 0.07, wave: .square, peak: 0.16),
            (freq: 360, dur: 0.08, wave: .square, peak: 0.14),
        ])
        buffers[.pop] = Synth.sequence(format: format, notes: [
            (freq: 520, dur: 0.10, wave: .triangle, peak: 0.18),
        ])
        buffers[.miss] = Synth.render(format: format, duration: 0.32) { t, k in
            let saw = Double(Synth.saw(t, freq: 300 - 180 * k))
            return Float(saw * 0.16 * (1 - k))
        }
        buffers[.streak] = Synth.sequence(format: format, notes: [
            (freq: 660, dur: 0.12, wave: .triangle, peak: 0.20),
            (freq: 990, dur: 0.18, wave: .triangle, peak: 0.20),
        ])
        buffers[.personalBest] = Synth.sequence(format: format, notes: [
            (freq: 523, dur: 0.14, wave: .triangle, peak: 0.22),
            (freq: 659, dur: 0.14, wave: .triangle, peak: 0.22),
            (freq: 784, dur: 0.22, wave: .triangle, peak: 0.22),
        ])
    }

    func play(_ effect: Effect) {
        guard PersistenceStore.shared.soundOn, let buffer = buffers[effect] else { return }
        if !started { start() }
        guard started else { return }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        player.play()
    }

    private func start() {
        do {
            #if os(iOS)
            // Ambient: Swish Strike never interrupts the user's music.
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            try engine.start()
            started = true
        } catch {
            log.error("audio engine unavailable: \(error.localizedDescription)")
            started = false
        }
    }
}

/// Tiny offline synthesizer: renders closures / note sequences into PCM buffers.
enum Synth {
    enum Wave { case triangle, square }

    static func saw(_ t: Double, freq: Double) -> Float {
        let phase = (t * freq).truncatingRemainder(dividingBy: 1)
        return Float(2 * phase - 1)
    }

    /// Render `sample(t, k)` (t seconds, k progress 0...1) into a buffer.
    static func render(format: AVAudioFormat, duration: Double,
                       sample: (Double, Double) -> Float) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(duration * format.sampleRate)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = frames
        for i in 0..<Int(frames) {
            let t = Double(i) / format.sampleRate
            data[i] = sample(t, t / duration)
        }
        return buf
    }

    /// Render a short sequence of plucked notes back to back.
    static func sequence(format: AVAudioFormat,
                         notes: [(freq: Double, dur: Double, wave: Wave, peak: Float)]) -> AVAudioPCMBuffer? {
        let total = notes.reduce(0) { $0 + $1.dur } + 0.02
        return render(format: format, duration: total) { t, _ in
            var start = 0.0
            for note in notes {
                if t >= start && t < start + note.dur {
                    let local = t - start
                    let envelope = Float(1 - local / note.dur) // linear pluck decay
                    let phase = (local * note.freq).truncatingRemainder(dividingBy: 1)
                    let raw: Float = switch note.wave {
                    case .triangle: Float(abs(4 * phase - 2) - 1)
                    case .square: phase < 0.5 ? 1 : -1
                    }
                    return raw * note.peak * envelope
                }
                start += note.dur
            }
            return 0
        }
    }
}
