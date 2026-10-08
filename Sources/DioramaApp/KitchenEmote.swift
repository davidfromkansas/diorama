import AppKit
import DioramaCore
import QuartzCore

/// A pixel emote that pops up above a chef, Stardew-style: brief reactions to notable moments
/// (a step done, tests passing, a long think) and lasting states (needing you, a dish ready).
enum ChefEmote: String, CaseIterable, Comparable {
    case alert, question, wrench, angry, star, check, note, idea, plus, thinking

    /// Lower shows first when several happen at once.
    var priority: Int { Self.allCases.firstIndex(of: self)! }
    static func < (a: Self, b: Self) -> Bool { a.priority < b.priority }

    var color: NSColor {
        switch self {
        case .alert, .question: NSColor(red: 0.96, green: 0.62, blue: 0.13, alpha: 1)
        case .angry, .wrench: NSColor(red: 0.88, green: 0.27, blue: 0.23, alpha: 1)
        case .star: NSColor(red: 0.93, green: 0.66, blue: 0.1, alpha: 1)
        case .check: NSColor(red: 0.18, green: 0.64, blue: 0.35, alpha: 1)
        case .note: NSColor(red: 0.12, green: 0.6, blue: 0.55, alpha: 1)
        case .idea: NSColor(red: 0.96, green: 0.77, blue: 0.15, alpha: 1)
        case .plus: NSColor(red: 0.56, green: 0.36, blue: 0.79, alpha: 1)
        case .thinking: NSColor(white: 0.3, alpha: 1)
        }
    }
    var spoken: String {
        switch self {
        case .alert: "needs you"
        case .question: "has a question"
        case .angry: "hit a failure"
        case .wrench: "needs a fix"
        case .star: "has a dish ready"
        case .check: "tests passed"
        case .note: "finished a step"
        case .idea: "made a plan"
        case .plus: "fetched from the pantry"
        case .thinking: "is thinking"
        }
    }
    /// 9×9 glyph rows: X in the emote's colour, o in outline ink.
    var glyph: [String] {
        switch self {
        case .alert: ["...XXX...", "...XXX...", "...XXX...", "...XXX...", "....X....", "....X....", ".........", "...XXX...", "...XXX..."]
        case .question: ["..XXXXX..", ".XX...XX.", "......XX.", ".....XX..", "....XX...", "....XX...", ".........", "....XX...", "....XX..."]
        case .wrench: [".....XX..", "....X..X.", "....X.XX.", "...XXXX..", "..XXX....", ".XXX.....", "XXX......", "XX.......", "........."]
        case .angry: ["..X...X..", ".XX...XX.", "XX.....XX", ".........", ".........", ".........", "XX.....XX", ".XX...XX.", "..X...X.."]
        case .star: [".........", "....X....", "...XXX...", "XXXXXXXXX", ".XXXXXXX.", "..XXXXX..", ".XXX.XXX.", ".XX...XX.", "........."]
        case .check: [".........", ".......XX", "......XX.", ".....XX..", "XX..XX...", ".XXXX....", "..XX.....", ".........", "........."]
        case .note: ["....XXXX.", "....X..X.", "....X..X.", "....X....", "....X....", "..XXX....", ".XXXX....", ".XXX.....", "........."]
        case .idea: ["...XXX...", "..XXXXX..", ".XXXXXXX.", ".XXXXXXX.", ".XXXXXXX.", "..XXXXX..", "...XXX...", "...ooo...", "...ooo..."]
        case .plus: [".........", "...XXX...", "...XXX...", "XXXXXXXXX", "XXXXXXXXX", "XXXXXXXXX", "...XXX...", "...XXX...", "........."]
        case .thinking: Self.dots(3)
        }
    }
    static func dots(_ count: Int) -> [String] {
        let row = (0..<3).map { $0 < count ? "XX" : ".." }.joined(separator: ".")
        return [".........", ".........", ".........", ".........", row, row, ".........", ".........", "........."]
    }

    /// The emote that stays up while a state lasts: needing you, or a dish at the pass.
    static func lasting(_ agent: SpatialAgent, review: KitchenReviews.State?) -> ChefEmote? {
        let value = agent.value
        if agent.needsAttention || value.status == .failed || value.status == .waiting {
            return value.status == .waiting && value.attentionReason == .input ? .question : .alert
        }
        // A pull request: a wrench while it needs a fix, a check once it's ready to merge.
        if review == .needsFix, value.status != .working { return .wrench }
        if review == .shipped, value.status != .working { return .check }
        return KitchenLayout.work(for: value, review: review).area == "serving" ? .star : nil
    }

    // MARK: Pixels
    private static var cache: [String: CGImage] = [:]
    /// The emote in a white speech bubble with a dark outline and a tail, one image pixel per
    /// emote pixel (drawn with nearest-neighbour scaling).
    static func image(_ glyph: [String], color: NSColor) -> CGImage? {
        let key = glyph.joined() + color.description
        if let cached = cache[key] { return cached }
        let width = 13, height = 14
        var pixels = Array(repeating: Array(repeating: Character("."), count: width), count: height)
        // Bubble: rows 0…11 with cut corners, then a two-row tail.
        for y in 0..<12 { for x in 0..<width where !((y == 0 || y == 11) && (x == 0 || x == width - 1)) { pixels[y][x] = (y == 0 || y == 11 || x == 0 || x == width - 1) ? "o" : "w" } }
        pixels[0][1] = "."; pixels[0][width - 2] = "."; pixels[11][1] = "."; pixels[11][width - 2] = "."
        pixels[1][1] = "o"; pixels[1][width - 2] = "o"; pixels[10][1] = "o"; pixels[10][width - 2] = "o"
        for x in 5...7 { pixels[11][x] = "w" }
        pixels[12][5] = "o"; pixels[12][6] = "w"; pixels[12][7] = "o"; pixels[13][6] = "o"
        for (y, row) in glyph.enumerated() { for (x, c) in row.enumerated() where c != "." { pixels[y + 2][x + 2] = c } }
        let ink = NSColor(red: 0.16, green: 0.13, blue: 0.11, alpha: 1)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        for (y, row) in pixels.enumerated() {
            for (x, c) in row.enumerated() {
                let fill: NSColor? = switch c { case "o": ink; case "w": .white; case "X": color; default: nil }
                guard let fill else { continue }
                context.setFillColor(fill.cgColor)
                context.fill(CGRect(x: x, y: height - 1 - y, width: 1, height: 1))
            }
        }
        let image = context.makeImage()
        cache[key] = image
        return image
    }
}

/// What changed between two looks at an agent that deserves a reaction.
enum ChefMoment {
    static func detect(previous: WorkspaceAgent?, current: WorkspaceAgent) -> [ChefEmote] {
        guard let previous else { return [] }
        var moments: [ChefEmote] = []
        let attention = { (agent: WorkspaceAgent) in agent.status == .waiting || agent.status == .failed }
        if attention(current), !attention(previous) || current.attentionReason != previous.attentionReason {
            moments.append(current.status == .waiting && current.attentionReason == .input ? .question : .alert)
        }
        if current.status == .done, previous.status != .done { moments.append(.star) }
        let before = previous.turnWork, after = current.turnWork
        func count(_ work: TurnWork, _ outcome: TurnWork.Outcome) -> Int { work.tests.filter { $0.outcome == outcome }.count }
        // Counts restart with each turn; only growth within the turn is a moment.
        if count(after, .failed) > count(before, .failed) || after.failedCommands > before.failedCommands { moments.append(.angry) }
        if count(after, .passed) > count(before, .passed) { moments.append(.check) }
        func kept(_ plan: AgentPlan?) -> AgentPlan? { plan.flatMap { $0.hasTasks && !$0.tasksPreviousTurn && $0.checklist.count > 1 ? $0 : nil } }
        if let now = kept(current.plan) {
            if let then = kept(previous.plan) { if now.completedTaskCount > then.completedTaskCount { moments.append(.note) } }
            else { moments.append(.idea) }
        }
        if after.resources.count > before.resources.count { moments.append(.plus) }
        return moments
    }
    /// Seconds without a tool call or a note before a working agent reads as thinking (composing a
    /// long file, planning) and how often the thought bubble repeats while it stays quiet.
    static let thinkingAfter: TimeInterval = 20
    static let thinkingEvery: TimeInterval = 8
    static func silent(_ agent: WorkspaceAgent, now: Date) -> Bool {
        guard agent.isWorking, let last = [agent.lastToolAt, agent.lastCommentaryAt].compactMap({ $0 }).max() else { return false }
        return now.timeIntervalSince(last) >= thinkingAfter
    }
}

/// The emote above one chef: a queue of brief reactions, then the lasting state (if any).
final class ChefEmoteView: NSView {
    static let pixel: CGFloat = 2
    static let size = NSSize(width: 13 * pixel, height: 14 * pixel)
    private let sprite = CALayer()
    private(set) var showing: ChefEmote?
    private(set) var lasting: ChefEmote?
    private var queue: [(emote: ChefEmote, at: Date)] = []
    private var lastPlayed: [ChefEmote: Date] = [:]
    private var playing = false
    private var generation = 0
    var reducedMotion = false
    var name = ""
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    static let hold: TimeInterval = 1.8, exit: TimeInterval = 0.35, stale: TimeInterval = 4, repeatGap: TimeInterval = 3

    override init(frame: NSRect) {
        super.init(frame: NSRect(origin: frame.origin, size: Self.size))
        wantsLayer = true
        sprite.magnificationFilter = .nearest
        sprite.contentsGravity = .resize
        sprite.anchorPoint = CGPoint(x: 0.5, y: 1)
        isHidden = true
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func makeBackingLayer() -> CALayer { let layer = CALayer(); layer.addSublayer(sprite); return layer }
    override func layout() { super.layout(); CATransaction.begin(); CATransaction.setDisableActions(true); sprite.frame = bounds; CATransaction.commit() }

    /// Brief reactions, highest priority first; repeats within a few seconds are dropped.
    func react(_ emotes: [ChefEmote], now: Date = Date()) {
        for emote in emotes.sorted() where now.timeIntervalSince(lastPlayed[emote] ?? .distantPast) >= Self.repeatGap {
            lastPlayed[emote] = now
            queue.append((emote, now))
        }
        queue.sort { $0.emote < $1.emote }
        next(now: now)
    }
    func setLasting(_ emote: ChefEmote?) {
        guard emote != lasting else { return }
        lasting = emote
        if !playing { show(emote, pop: emote != nil) }
    }

    private func next(now: Date = Date()) {
        guard !playing else { return }
        queue.removeAll { now.timeIntervalSince($0.at) > Self.stale }
        guard !queue.isEmpty else { show(lasting, pop: false); return }
        let emote = queue.removeFirst().emote
        playing = true; generation += 1
        let token = generation
        show(emote, pop: true)
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: "\(name) \(emote.spoken)", .priority: NSAccessibilityPriorityLevel.low.rawValue])
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hold) { [weak self] in
            guard let self, self.generation == token else { return }
            self.leave {
                guard self.generation == token else { return }
                self.playing = false
                self.next()
            }
        }
    }

    private func show(_ emote: ChefEmote?, pop: Bool) {
        sprite.removeAllAnimations()
        showing = emote
        guard let emote else { alphaValue = 0; return }
        alphaValue = 1
        CATransaction.begin(); CATransaction.setDisableActions(true)
        sprite.opacity = 1; sprite.transform = CATransform3DIdentity
        sprite.contents = ChefEmote.image(emote.glyph, color: emote.color)
        CATransaction.commit()
        if emote == .thinking {
            let frames = CAKeyframeAnimation(keyPath: "contents")
            frames.values = (1...3).compactMap { ChefEmote.image(ChefEmote.dots($0), color: emote.color) }
            frames.calculationMode = .discrete; frames.duration = 0.9; frames.repeatCount = .infinity
            if !reducedMotion { sprite.add(frames, forKey: "dots") }
        }
        if pop {
            if reducedMotion {
                let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.2
                sprite.add(fade, forKey: "in")
            } else {
                let scale = CAKeyframeAnimation(keyPath: "transform.scale")
                scale.values = [0.4, 1.15, 1]; scale.keyTimes = [0, 0.6, 1]; scale.duration = 0.18
                let bounce = CAKeyframeAnimation(keyPath: "transform.translation.y")
                bounce.values = [0, -3, 0]; bounce.keyTimes = [0, 0.5, 1]; bounce.duration = 0.3; bounce.beginTime = CACurrentMediaTime() + 0.18
                sprite.add(scale, forKey: "pop"); sprite.add(bounce, forKey: "bounce")
            }
        }
        // Needing you pulses gently until it's resolved.
        if [.alert, .question].contains(emote), emote == lasting, !reducedMotion {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1; pulse.toValue = 0.45; pulse.duration = 0.7; pulse.autoreverses = true; pulse.repeatCount = .infinity
            pulse.beginTime = CACurrentMediaTime() + 0.3
            sprite.add(pulse, forKey: "pulse")
        }
    }
    /// The reaction drifts up and fades, unless the lasting emote is the same picture.
    private func leave(_ done: @escaping () -> Void) {
        if showing == lasting || (queue.isEmpty && lasting == nil && reducedMotion) { done(); return }
        CATransaction.begin()
        CATransaction.setCompletionBlock(done)
        let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 1; fade.toValue = 0
        let rise = CABasicAnimation(keyPath: "transform.translation.y"); rise.fromValue = 0; rise.toValue = reducedMotion ? 0 : -6
        let group = CAAnimationGroup(); group.animations = [fade, rise]; group.duration = Self.exit
        group.fillMode = .forwards; group.isRemovedOnCompletion = false
        sprite.add(group, forKey: "leave")
        CATransaction.commit()
    }
}
