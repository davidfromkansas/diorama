import AVFoundation
import Foundation

/// Home's navigation sounds, synthesized (Diorama owns them; nothing to license): a muted glass
/// tick for moving between cards, a two-note chime for changing section (rising going down,
/// falling going up), and a soft three-note chord for selecting. The chimes ring through a short
/// echo, as on the listening page they were chosen from. Rendered once, then played on a few
/// voices; the engine pauses when quiet.
@MainActor final class HomeSound {
    static let shared = HomeSound()
    /// Turns Home's sounds off (they're on unless set to false).
    static let enabledKey = "homeSounds"
    /// Test runs build Home too; they must stay silent.
    static let available = KitchenLog.enabled
    var enabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }

    private static let rate = 44_100.0
    private let engine = AVAudioEngine()
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private var moves: [AVAudioPCMBuffer] = []
    private var sectionDown: AVAudioPCMBuffer?
    private var sectionUp: AVAudioPCMBuffer?
    private var chord: AVAudioPCMBuffer?
    private var idle: Task<Void, Never>?

    /// Moving to the next (1) or previous (-1) card.
    func move(_ direction: Int) {
        guard let buffer = ready() ? moves.randomElement() : nil else { return }
        play(buffer, pan: Float(direction) * 0.25)
    }
    /// Changing section: down the list (↓) rises, up the list (↑) falls.
    func section(down: Bool) {
        guard ready(), let buffer = down ? sectionDown : sectionUp else { return }
        play(buffer, pan: 0)
    }
    /// Space on a card, or one of Home's round buttons.
    func select() {
        guard ready(), let chord else { return }
        play(chord, pan: 0)
    }

    private func ready() -> Bool {
        guard Self.available, enabled else { return false }
        if voices.isEmpty {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.rate, channels: 1) else { return false }
            for _ in 0..<4 {
                let voice = AVAudioPlayerNode()
                engine.attach(voice); engine.connect(voice, to: engine.mainMixerNode, format: format)
                voices.append(voice)
            }
            engine.mainMixerNode.outputVolume = 0.7
            render(format)
        }
        if !engine.isRunning {
            engine.prepare()
            do { try engine.start() } catch { return false }
        }
        return true
    }
    private func play(_ buffer: AVAudioPCMBuffer, pan: Float) {
        let voice = voices[nextVoice]; nextVoice = (nextVoice + 1) % voices.count
        voice.pan = pan
        voice.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !voice.isPlaying { voice.play() }
        idle?.cancel()
        idle = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            self.voices.forEach { $0.stop() }
            self.engine.pause()
        }
    }

    // MARK: Synthesis

    /// One sine note with an exponential attack and decay (Web Audio's ramps), added at `start` seconds.
    private struct Note { var freq: Double; var start = 0.0; var attack = 0.004; var peak: Double; var decay: Double }

    private func render(_ format: AVAudioFormat) {
        // The card tick: 700 Hz with a quiet overtone through the echo; five slightly detuned takes.
        moves = (0..<5).compactMap { _ in
            let f = 700 * Double.random(in: 0.975...1.025)
            return buffer(format, dry: [Note(freq: f, peak: 0.164, decay: 0.087)], wet: [Note(freq: f * 2.01, peak: 0.025, decay: 0.03)])
        }
        sectionDown = buffer(format, dry: [], wet: [Note(freq: 880, peak: 0.12, decay: 0.14), Note(freq: 1318.5, start: 0.07, peak: 0.12, decay: 0.22)])
        sectionUp = buffer(format, dry: [], wet: [Note(freq: 1318.5, peak: 0.12, decay: 0.14), Note(freq: 880, start: 0.07, peak: 0.12, decay: 0.22)])
        chord = buffer(format, dry: [], wet: [1046.5, 1318.5, 1568].enumerated().map { Note(freq: $1, start: Double($0) * 0.035, peak: 0.1, decay: 0.35) })
    }
    /// `dry` notes play as they are; `wet` notes play only through the echo (a 90 ms delay fed
    /// back at 0.28 through a gentle low-pass), as the listening page's "room" did.
    private func buffer(_ format: AVAudioFormat, dry: [Note], wet: [Note]) -> AVAudioPCMBuffer? {
        let length = 1.2, count = Int(length * Self.rate)
        var direct = [Double](repeating: 0, count: count), send = [Double](repeating: 0, count: count)
        func add(_ note: Note, into samples: inout [Double]) {
            let first = Int(note.start * Self.rate), floor = 0.0001
            let attack = Int(note.attack * Self.rate), total = Int((note.attack + note.decay) * Self.rate)
            for i in 0..<total where first + i < count {
                let t = Double(i) / Self.rate
                let gain = i < attack ? floor * pow(note.peak / floor, Double(i) / Double(max(1, attack)))
                    : note.peak * pow(floor / note.peak, Double(i - attack) / Double(max(1, total - attack)))
                samples[first + i] += gain * sin(2 * .pi * note.freq * t)
            }
        }
        dry.forEach { add($0, into: &direct) }
        wet.forEach { add($0, into: &send) }
        // Echo: y = lowpass(x delayed + feedback · y delayed); only y reaches the output.
        let delay = Int(0.09 * Self.rate), cutoff = 1 - exp(-2 * .pi * 3500 / Self.rate)
        var loop = [Double](repeating: 0, count: count), low = 0.0
        for i in 0..<count {
            let input = (i >= delay ? send[i - delay] + loop[i - delay] * 0.28 : 0)
            low += cutoff * (input - low)
            loop[i] = low
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(count)
        for i in 0..<count { channel[i] = Float(max(-1, min(1, direct[i] + loop[i]))) }
        return buffer
    }
}
