import AVFoundation
import Foundation

/// Foley for the kitchen: what each chef clip sounds like, pinned to points in the clip so a
/// knife lands with its chop and a plate with its release. Sounds are CC0 clips from Kenney's
/// RPG Audio, Impact Sounds and Interface Sounds packs (assets/kitchen-sounds/README.md), bundled
/// as `Resources/KitchenSounds/<sound>-<n>.caf`; each play picks a variant at a slightly varied pitch.
nonisolated enum KitchenSound: String, CaseIterable, Sendable {
    case step, chop, clink, tap, page, pot, grab, plate, cloche, clatter, bell, error, cheer, ding, chair

    var variants: Int {
        switch self {
        case .step: 5
        case .chop, .clink, .tap, .page, .pot, .plate, .chair: 3
        case .grab, .cloche, .clatter, .bell: 2
        case .error, .cheer, .ding: 1
        }
    }
    /// Mixed so busy stations sit under the moments that call for attention (bell, error, serving).
    var volume: Float {
        switch self {
        case .step: 0.18
        case .chop: 0.35
        case .clink: 0.3
        case .tap: 0.35
        case .page: 0.6
        case .pot: 0.18
        case .grab: 1
        case .plate: 0.6
        case .cloche: 0.45
        case .clatter: 0.4
        case .bell: 0.7
        case .error: 0.3
        case .cheer: 0.3
        case .ding: 0.35
        case .chair: 0.6
        }
    }
    /// The same sound from several chefs within this many seconds plays once.
    var spacing: Double { self == .step ? 0.05 : 0.03 }

    /// Where in a clip each sound plays: a manifest marker (`ChefManifest.Clip.markers`) or a
    /// normalised 0…1 position. Footfalls are timed here because the rig has no step markers.
    enum At: Sendable { case marker(String), at(Float) }
    static let cues: [String: [(At, KitchenSound)]] = [
        "walk": [(.at(0.05), .step), (.at(0.55), .step)],
        "carry_walk": [(.at(0.05), .step), (.at(0.55), .step)],
        "run": [(.at(0.05), .step), (.at(0.55), .step)],
        "working_chop": [(.marker("impact"), .chop), (.marker("impact_2"), .chop)],
        "testing_dish": [(.marker("taste"), .clink)],
        "sit_sip": [(.marker("sip"), .clink)],
        "planning_recipe": [(.marker("tap"), .tap)],
        "researching_book": [(.at(0.15), .page)],
        "read_ticket": [(.at(0.2), .page)],
        "waiting_tool": [(.at(0.05), .pot)],
        "pickup": [(.marker("attach"), .grab)],
        "putdown": [(.marker("release"), .plate)],
        "present_review": [(.marker("release"), .plate)],
        "cover_dish": [(.marker("release"), .cloche)],
        "cancel_cleanup": [(.marker("release"), .clatter)],
        "request_input": [(.at(0.2), .bell)],
        "blocked_react": [(.at(0.1), .bell)],
        "error_react": [(.at(0), .error)],
        "celebrate_done": [(.at(0.1), .cheer)],
        "arrive_wave": [(.at(0), .ding)],
        "sit_down": [(.at(0.6), .chair)],
        "stand_up": [(.at(0.1), .chair)],
    ]

    /// Sounds whose cue falls in (`from`, `to`], both in clip fractions; a loop's `to` may run past 1
    /// on the frame it wraps. A clip that just started passes a negative `from` so cues at 0 play.
    static func crossed(_ clip: String, markers: [String: Float], from: Float, to: Float) -> [KitchenSound] {
        guard let cues = cues[clip], to > from else { return [] }
        return cues.compactMap { at, sound in
            let point: Float
            switch at {
            case let .marker(name): guard let value = markers[name] else { return nil }; point = value
            case let .at(value): point = value
            }
            return [point, point + 1].contains { $0 > from && $0 <= to } ? sound : nil
        }
    }
}

/// Plays kitchen foley on a small pool of voices, panned to where the chef stands on screen.
/// Called from SceneKit's render thread; all audio work happens on its own queue. The engine
/// starts with the first sound and pauses after a quiet spell so an idle kitchen costs nothing.
nonisolated final class KitchenAudio: @unchecked Sendable {
    static let shared = KitchenAudio()
    static let enabledKey = "kitchenSounds"
    static let voices = 10
    /// Test runs build kitchens too; they must stay silent.
    static let available = KitchenLog.enabled

    private let queue = DispatchQueue(label: "diorama.kitchen-audio", qos: .userInitiated)
    private let engine = AVAudioEngine()
    private var players: [(node: AVAudioPlayerNode, pitch: AVAudioUnitVarispeed, busy: Bool)] = []
    private var buffers: [KitchenSound: [AVAudioPCMBuffer]] = [:]
    private var lastPlayed: [KitchenSound: Double] = [:]
    private var lastVariant: [KitchenSound: Int] = [:]
    private var idleCheck: DispatchWorkItem?
    private var format: AVAudioFormat?
    private var bundle: Bundle?

    /// Where the sounds live; kitchens set it on the main thread before any chef can cue one.
    @MainActor func prepare(bundle: Bundle = WorkspaceCapybaraAsset.resourceBundle) {
        queue.async { [self] in if self.bundle == nil { self.bundle = bundle } }
    }

    var enabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }

    /// `pan` runs -1 (left) … 1 (right); `level` scales the sound's own volume (0…1).
    func play(_ sound: KitchenSound, pan: Float, level: Float = 1) {
        guard Self.available else { return }
        queue.async { [self] in
            guard enabled else { return }
            let now = CACurrentMediaTime()
            guard now - (lastPlayed[sound] ?? 0) >= sound.spacing else { return }
            guard let buffer = buffer(for: sound), prepare(), let index = players.firstIndex(where: { !$0.busy }) else { return }
            lastPlayed[sound] = now
            let voice = players[index]
            players[index].busy = true
            voice.node.pan = max(-1, min(1, pan)) * 0.7
            voice.node.volume = sound.volume * max(0, min(1, level))
            voice.pitch.rate = Float.random(in: 0.93...1.07)
            voice.node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                self?.queue.async { self?.players[index].busy = false; self?.scheduleIdleCheck() }
            }
            if !voice.node.isPlaying { voice.node.play() }
        }
    }

    /// A random variant, never the same one twice in a row.
    private func buffer(for sound: KitchenSound) -> AVAudioPCMBuffer? {
        if buffers[sound] == nil {
            buffers[sound] = (0..<sound.variants).compactMap { variant in
                guard let url = bundle?.url(forResource: "\(sound.rawValue)-\(variant)", withExtension: "caf", subdirectory: "KitchenSounds"),
                      let file = try? AVAudioFile(forReading: url),
                      let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                      (try? file.read(into: buffer)) != nil else { return nil }
                return buffer
            }
        }
        guard let options = buffers[sound], !options.isEmpty else { return nil }
        var pick = Int.random(in: 0..<options.count)
        if options.count > 1, pick == lastVariant[sound] { pick = (pick + 1) % options.count }
        lastVariant[sound] = pick
        return options[pick]
    }

    /// Builds the voices once and (re)starts the engine, e.g. after an output device change.
    private func prepare() -> Bool {
        if players.isEmpty {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else { return false }
            self.format = format
            for _ in 0..<Self.voices {
                let node = AVAudioPlayerNode(), pitch = AVAudioUnitVarispeed()
                engine.attach(node); engine.attach(pitch)
                engine.connect(node, to: pitch, format: format)
                engine.connect(pitch, to: engine.mainMixerNode, format: format)
                players.append((node, pitch, false))
            }
            engine.mainMixerNode.outputVolume = 0.8
        }
        if !engine.isRunning {
            engine.prepare()
            do { try engine.start() } catch { return false }
        }
        return true
    }

    private func scheduleIdleCheck() {
        idleCheck?.cancel()
        let check = DispatchWorkItem { [weak self] in
            guard let self, self.engine.isRunning, !self.players.contains(where: \.busy) else { return }
            self.players.forEach { $0.node.stop() }
            self.engine.pause()
        }
        idleCheck = check
        queue.asyncAfter(deadline: .now() + 4, execute: check)
    }
}
