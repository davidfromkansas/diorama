import AppKit
import DioramaCore
import QuartzCore

/// What a chef's tag shows: its name, one terminal line of what it is doing now, and how far
/// along it is (a segmented bar). Selected, a short log of recent steps opens above it.
struct ChefTagContent: Equatable {
    /// The state the tag's colour and symbol stand for.
    enum Phase: Equatable {
        case starting, working, thinking, waiting, approval, failed, stopped, done, checking, needsFix, shipped, idle

        var symbol: String {
            switch self {
            case .starting, .working: "›"
            case .thinking: "…"
            case .waiting: "?"
            case .approval: "!"
            case .failed, .needsFix: "✗"
            case .stopped: "■"
            case .done: "★"
            case .checking: "◷"
            case .shipped: "✓"
            case .idle: "–"
            }
        }
        var color: NSColor {
            switch self {
            case .starting, .working, .checking: ChefTagPalette.run
            case .thinking, .stopped, .idle: ChefTagPalette.idle
            case .waiting: ChefTagPalette.wait
            case .approval: ChefTagPalette.ask
            case .failed, .needsFix: ChefTagPalette.fail
            case .done: ChefTagPalette.star
            case .shipped: ChefTagPalette.ok
            }
        }
        /// States that need you: they keep their full tag when another chef is selected, pulse,
        /// and win when tags crowd.
        var needsYou: Bool { [.waiting, .approval, .failed, .needsFix].contains(self) }
        /// Work in progress: the tag bobs, the dot breathes and a cursor blinks.
        var running: Bool { [.starting, .working].contains(self) }
        var spoken: String {
            switch self {
            case .starting: "starting"
            case .working: "working"
            case .thinking: "thinking"
            case .waiting: "waiting for you"
            case .approval: "needs approval"
            case .failed: "failed"
            case .stopped: "stopped"
            case .done: "done"
            case .checking: "checks running"
            case .needsFix: "needs a fix"
            case .shipped: "ready to merge"
            case .idle: "idle"
            }
        }
        /// Crowded tags keep the most important one open: lower comes first.
        var priority: Int {
            switch self {
            case .waiting, .approval, .failed, .needsFix: 0
            case .starting, .working, .thinking, .checking: 2
            case .done, .shipped: 3
            case .stopped, .idle: 4
            }
        }
    }
    enum Check: String, Codable, Equatable { case passed, failed, running }
    enum Progress: Equatable {
        /// A checklist kept this turn: one block per step.
        case steps(done: Int, total: Int)
        /// Working without a list: a sweep, never an invented fraction.
        case sweep
        /// A pull request's checks, one block each.
        case checks([Check])
    }

    var name: String
    /// The model it runs on ("GPT-6-Astra", "Claude Opus 5.5"), as the agent panel names it.
    var model: String = ""
    var phase: Phase
    /// The terminal line: the live step, a question, a failure.
    var line: String
    var progress: Progress?
    /// A four-word summary of the task, updated each turn: the terminal's first line, and the
    /// agent panel's title.
    var text: String
    /// The whole task, for the tooltip and accessibility.
    var fullText: String
    /// Last known rather than live: drawn faded.
    var stale: Bool
    /// Resting in the break room: shown only on hover.
    var resting: Bool
    /// Recent steps, oldest first, for the selected log.
    var log: [String] = []
    var footer: String = ""

    var spoken: String {
        var parts = ["\(name), \(phase.spoken)"]
        if !line.isEmpty { parts.append(line) }
        switch progress {
        case .steps(let done, let total): parts.append("\(done) of \(total) steps done")
        case .checks(let checks): parts.append("\(checks.filter { $0 == .passed }.count) of \(checks.count) checks passed")
        default: break
        }
        if !fullText.isEmpty { parts.append(fullText) }
        return parts.joined(separator: ". ")
    }

    /// - Parameter files: how many files the task changed since it began (git, as the Changes
    ///   panel counts them), shown once it's done.
    static func make(_ agent: SpatialAgent, review: KitchenReviews.State?, note: String? = nil, checks: [Check]? = nil, files: Int? = nil,
                     model: String = "", now: Date = Date(), labels: TaskLabels = .shared) -> ChefTagContent {
        let value = agent.value
        let work = KitchenLayout.work(for: value, review: review)
        let task = TaskTitle.full(value.task)
        let short = labels.title(agent)
        let steps = value.feed.filter { ![.started, .finished, .interrupted].contains($0.kind) }
        let phase = Self.phase(value, review: review, area: work.area, now: now)
        var line: String
        switch phase {
        case .starting: line = "starting…"
        case .working: line = steps.last?.title ?? (value.latestActivity.isEmpty ? value.action : value.latestActivity)
        case .thinking:
            let quiet = [value.lastToolAt, value.lastCommentaryAt].compactMap { $0 }.max().map { Int(now.timeIntervalSince($0)) } ?? 0
            line = "thinking · \(quiet)s"
        case .waiting: line = "waiting for you"
        case .approval: line = value.latestTool.isEmpty ? "needs approval" : "allow \(value.latestTool)?"
        case .failed: line = steps.last(where: { $0.outcome == .failed })?.title ?? "turn failed"
        case .stopped: line = "stopped"
        case .done: line = files.map { $0 == 0 ? "done" : "done · \($0) file\($0 == 1 ? "" : "s")" } ?? "done"
        case .checking: line = note ?? "PR checks running"
        case .needsFix: line = note.map { $0.replacingOccurrences(of: "Needs a fix · ", with: "") } ?? "needs a fix"
        case .shipped: line = note ?? "ready to merge"
        case .idle: line = ""
        }
        line = line.replacingOccurrences(of: "\n", with: " ")
        var progress: Progress?
        if [.checking, .needsFix, .shipped].contains(phase), let checks, !checks.isEmpty { progress = .checks(checks) }
        else if case .steps(let done, let total) = value.planProgress, phase != .idle { progress = .steps(done: done, total: total) }
        else if [.starting, .working, .thinking].contains(phase) { progress = .sweep }
        // The bar shows how far along it is; the log's footer just says for how long.
        var footer: [String] = []
        if let start = value.feed.last(where: { $0.kind == .started })?.time, phase.running || phase == .thinking {
            let seconds = max(0, Int(now.timeIntervalSince(start)))
            footer.append(seconds >= 60 ? "\(seconds / 60)m \(seconds % 60)s" : "\(seconds)s")
        }
        return ChefTagContent(name: value.name, model: model, phase: phase, line: line, progress: progress,
                              text: short.isEmpty ? value.name : short, fullText: task.isEmpty ? value.name : task,
                              stale: !agent.fresh, resting: work.area == "break",
                              log: (phase == .working ? steps.dropLast() : steps[...]).suffix(3).map { ($0.outcome == .failed ? "✗ " : "✓ ") + $0.title },
                              footer: footer.joined(separator: " · "))
    }

    static func phase(_ value: WorkspaceAgent, review: KitchenReviews.State?, area: String?, now: Date) -> Phase {
        // A pull request's state speaks for a chef that isn't working on it.
        if value.status != .working {
            switch review {
            case .checking: return .checking
            case .needsFix: return .needsFix
            case .shipped: return .shipped
            default: break
            }
        }
        switch value.status {
        case .working:
            if value.feed.last?.kind == .started { return .starting }
            return ChefMoment.silent(value, now: now) ? .thinking : .working
        case .waiting: return value.attentionReason == .approval ? .approval : .waiting
        case .failed: return .failed
        case .stopped: return .stopped
        case .done: return area == "serving" ? .done : .idle
        case .ready, .unknown: return .idle
        }
    }
}

enum ChefTagPalette {
    static let run = NSColor(red: 0.47, green: 0.75, blue: 1.0, alpha: 1)
    static let ok = NSColor(red: 0.38, green: 0.83, blue: 0.58, alpha: 1)
    static let wait = NSColor(red: 0.96, green: 0.69, blue: 0.25, alpha: 1)
    static let ask = NSColor(red: 0.71, green: 0.55, blue: 1.0, alpha: 1)
    static let fail = NSColor(red: 1.0, green: 0.48, blue: 0.42, alpha: 1)
    static let idle = NSColor(red: 0.6, green: 0.63, blue: 0.65, alpha: 1)
    static let star = NSColor(red: 0.95, green: 0.79, blue: 0.3, alpha: 1)
    static let ink = NSColor(red: 0.07, green: 0.08, blue: 0.09, alpha: 0.9)
    /// The terminal strip: opaque, so the tab tucked behind it doesn't show through.
    static let strip = NSColor(red: 0.08, green: 0.09, blue: 0.1, alpha: 1)
    static let paper = NSColor.white.withAlphaComponent(0.93)
    static let text = NSColor(red: 0.93, green: 0.91, blue: 0.88, alpha: 1)
    static let dim = NSColor(red: 0.7, green: 0.72, blue: 0.75, alpha: 1)
}

/// A chef's tag, shaped like a folder: the name on a tab, the live line on the strip below it, with a segmented progress bar under it and,
/// selected, a short log above. One view, so the parts move together.
final class ChefTagView: NSView {
    enum Mode: Equatable {
        /// Name and model, the task, and the live line.
        case full
        /// Name and model, and the task: receded while another chef is selected, crowded out, or idle.
        case compact
        /// Name and model only: no task to name.
        case nameOnly
    }
    static let maxTextWidth: CGFloat = 140
    /// Selected, the line has the log's width to use.
    static let selectedTextWidth: CGFloat = 250
    static let scrollSpeed: CGFloat = 35 // points per second
    static let edgePause: CFTimeInterval = 1.5
    /// The terminal strip, and the name tab on top of it.
    static let pillHeight: CGFloat = 18
    static let tabHeight: CGFloat = 15
    /// One terminal line, and the strip's padding above and below its lines.
    static let lineHeight: CGFloat = 13
    static let stripPadding: CGFloat = 3
    /// Room around the parts for the attention ring's pulse.
    static let margin: CGFloat = 3
    static let barGap: CGFloat = 3

    private(set) var content: ChefTagContent?
    private(set) var mode: Mode = .full
    private(set) var selected = false
    private(set) var hovered = false
    private var reducedMotion = false
    /// The parts, inside one view that bobs and shakes as a whole.
    private let body = TagPart()
    private let card = TagPart()
    /// The selected log's lines, one row each so a long one can scroll on its own.
    private var cardLines: [String] = []
    private var cardRows: [(clip: TagPart, label: NSTextField)] = []
    static let cardLineHeight: CGFloat = 12
    static let cardWidth: CGFloat = 260
    private let pill = TagPart()
    private let ring = TagPart(), glow = TagPart()
    private let nameBox = TagPart(), termBox = TagPart()
    /// Squares the strip's corner under the tab, so tab and strip read as one folder.
    private let joint = TagPart()
    private let dot = TagPart()
    private let nameLabel = NSTextField(labelWithString: "")
    private let modelLabel = NSTextField(labelWithString: "")
    /// The terminal's first line: the task.
    private let taskLabel = NSTextField(labelWithString: "")
    private let glyphBox = TagPart()
    private let glyphLabel = NSTextField(labelWithString: "")
    private let clip = TagPart()
    private let lineLabel = NSTextField(labelWithString: "")
    private let caret = TagPart()
    let bar = ChefProgressView(frame: .zero)
    private var lastReaction: Date = .distantPast
    var text: String { content?.text ?? "" }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addSubview(body)
        for part in [glow, ring, card, pill, bar] as [NSView] { body.addSubview(part) }
        card.fill = ChefTagPalette.ink; card.radius = 6
        pill.addSubview(nameBox); pill.addSubview(termBox); pill.addSubview(joint)
        nameBox.fill = ChefTagPalette.paper
        nameBox.addSubview(dot); nameBox.addSubview(nameLabel); nameBox.addSubview(modelLabel)
        nameLabel.font = .systemFont(ofSize: 10, weight: .semibold); nameLabel.textColor = NSColor(white: 0.1, alpha: 1)
        modelLabel.font = .systemFont(ofSize: 9.5, weight: .medium); modelLabel.textColor = NSColor(white: 0.1, alpha: 0.55)
        termBox.fill = ChefTagPalette.strip; joint.fill = ChefTagPalette.strip
        for view in [taskLabel, glyphBox, clip, caret] as [NSView] { termBox.addSubview(view) }
        taskLabel.font = .monospacedSystemFont(ofSize: 9.5, weight: .semibold); taskLabel.textColor = .white
        taskLabel.lineBreakMode = .byTruncatingTail
        glyphBox.addSubview(glyphLabel)
        glyphLabel.font = .monospacedSystemFont(ofSize: 9.5, weight: .bold); glyphLabel.alignment = .center
        clip.clips = true; clip.addSubview(lineLabel)
        lineLabel.font = .monospacedSystemFont(ofSize: 9.5, weight: .regular); lineLabel.textColor = ChefTagPalette.text
        lineLabel.wantsLayer = true; lineLabel.lineBreakMode = .byClipping
        caret.fill = ChefTagPalette.text
        ring.radius = 7.5; glow.radius = 7.5
        setAccessibilityElement(true); setAccessibilityRole(.staticText)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// How the parts show for a mode (the current one unless asked about another).
    private struct Shape {
        var mode: Mode, selected: Bool
        var task: Bool, line: Bool, term: Bool, card: Bool, bar: Bool
        /// The strip's height for its lines.
        var strip: CGFloat { ChefTagView.stripPadding * 2 + ChefTagView.lineHeight * CGFloat((task ? 1 : 0) + (line ? 1 : 0)) + 1 }
    }
    private func shape(_ mode: Mode? = nil, selected: Bool? = nil, hovered: Bool? = nil) -> Shape {
        let selected = selected ?? self.selected
        let mode = effective(mode ?? self.mode, selected: selected, hovered: hovered ?? self.hovered)
        let task = mode != .nameOnly && !(content?.text.isEmpty ?? true)
        let line = mode == .full && !(content?.line.isEmpty ?? true)
        return Shape(mode: mode, selected: selected, task: task, line: line, term: task || line,
                     card: selected && mode == .full && !(content?.log.isEmpty ?? true), bar: mode != .nameOnly && content?.progress != nil)
    }
    /// An idle chef shows its name and its latest task unless selected or under the pointer;
    /// with no task to name, just its name.
    private func effective(_ mode: Mode, selected: Bool, hovered: Bool) -> Mode {
        if content?.text.isEmpty ?? true, content?.line.isEmpty ?? true { return .nameOnly }
        return content?.phase == .idle && !selected && !hovered ? .compact : mode
    }
    /// The line's drawn width, with the label's own inset on each side.
    private var lineWidth: CGFloat { ceil(lineLabel.attributedStringValue.size().width) + 4 }
    private func textWidth(_ shape: Shape) -> CGFloat { shape.selected ? Self.selectedTextWidth : Self.maxTextWidth }
    private var modelWidth: CGFloat { modelLabel.stringValue.isEmpty ? 0 : 5 + ceil(modelLabel.attributedStringValue.size().width) }
    private var nameWidth: CGFloat { 6 + 6 + 4 + ceil(nameLabel.attributedStringValue.size().width) + modelWidth + 7 }
    private var taskWidth: CGFloat { ceil(taskLabel.attributedStringValue.size().width) + 4 }
    private func termWidth(_ shape: Shape) -> CGFloat {
        guard shape.term else { return 0 }
        var line: CGFloat = 0
        if shape.line {
            line = 8 + 4 + min(textWidth(shape), lineWidth)
            if content?.phase.running == true { line += 2 + 5 }
        }
        let task = shape.task ? min(textWidth(shape) + 50, taskWidth) : 0
        return 5 + max(line, task) + 6
    }
    private func cardSize(_ shape: Shape) -> NSSize {
        guard shape.card else { return .zero }
        let widest = cardRows.prefix(cardLines.count).map { width(of: $0.label) }.max() ?? 0
        return NSSize(width: min(Self.cardWidth, widest) + 14, height: CGFloat(cardLines.count) * Self.cardLineHeight + 10)
    }
    /// The tag's width: the strip is at least as wide as its tab (the bar matches it).
    private func pillWidth(_ shape: Shape) -> CGFloat { max(nameWidth, termWidth(shape), cardSize(shape).width) }
    /// The whole tag's size, margins included, as it is or as it would be in another mode.
    func size(_ mode: Mode? = nil, selected: Bool? = nil, hovered: Bool? = nil) -> NSSize {
        let shape = shape(mode, selected: selected, hovered: hovered)
        let card = cardSize(shape)
        var height = Self.tabHeight + (shape.term ? shape.strip : 0) + (shape.bar ? Self.barGap + ChefProgressView.height : 0)
        if card.height > 0 { height += card.height + 3 }
        return NSSize(width: pillWidth(shape) + Self.margin * 2, height: height + Self.margin * 2)
    }
    var tagSize: NSSize { size() }
    /// Where the pill sits inside the tag (for tests and placement).
    var pillFrame: CGRect { convert(pill.frame, from: body) }

    func update(_ content: ChefTagContent, reducedMotion: Bool) {
        guard content != self.content || reducedMotion != self.reducedMotion else { return }
        let lineChanged = content.line != self.content?.line || reducedMotion != self.reducedMotion
        let restyle = content.phase != self.content?.phase || reducedMotion != self.reducedMotion || content.progress != self.content?.progress
        self.content = content; self.reducedMotion = reducedMotion
        nameLabel.stringValue = content.name
        modelLabel.stringValue = content.model
        taskLabel.stringValue = content.text
        lineLabel.stringValue = content.line
        glyphLabel.stringValue = content.phase.symbol
        // History under the live line, newest first, then how long this turn has run. The task
        // is the terminal's first line, so it isn't repeated here.
        let card = content.log.reversed() + (content.footer.isEmpty ? [] : [content.footer])
        let cardChanged = setCardLines(Array(card))
        alphaValue = tagAlpha
        let described = content.spoken
        setAccessibilityLabel(described); toolTip = described
        bar.update(content.progress, color: content.phase == .idle || content.phase == .thinking || content.phase == .stopped ? ChefTagPalette.ok : barColor(content.phase),
                   live: content.phase.running && !reducedMotion)
        layoutTag()
        if lineChanged || cardChanged { restartMarquee() }
        if restyle { restartMotion() }
    }
    private func barColor(_ phase: ChefTagContent.Phase) -> NSColor { phase.running ? ChefTagPalette.ok : phase.color }

    /// How much of the tag shows, and whether it's selected or under the pointer.
    func present(_ mode: Mode, selected: Bool, hovered: Bool) {
        let mode = effective(mode, selected: selected, hovered: hovered)
        guard mode != self.mode || selected != self.selected || hovered != self.hovered else { return }
        self.mode = mode; self.selected = selected; self.hovered = hovered
        alphaValue = tagAlpha
        layoutTag(); restartMotion(); restartMarquee()
    }
    /// Receded and crowded tags step back; an idle one (compact on its own) and one that needs you don't.
    private var modeAlpha: CGFloat { mode == .compact && content?.phase.needsYou != true && content?.phase != .idle ? 0.5 : 1 }
    /// Last known tags fade, except the one you selected: you're reading it.
    private var tagAlpha: CGFloat { content?.stale == true && !selected ? min(0.6, modeAlpha) : modeAlpha }

    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); layoutTag() }
    override func layout() { super.layout(); layoutTag() }

    private func layoutTag() {
        guard let content else { return }
        let shape = shape()
        let m = Self.margin, width = pillWidth(shape)
        body.frame = bounds
        // Top to bottom: the name tab and live line, the progress bar, then (selected) the history.
        let y = m
        pill.frame = NSRect(x: m, y: y, width: width, height: Self.tabHeight + (shape.term ? shape.strip : 0))
        let accent = content.phase.needsYou ? content.phase.color : ChefTagPalette.run
        // The name tab on the strip, like a folder: the tab runs on behind the strip (hiding its
        // lower corners) and a square patch fills the strip's corner under it.
        let radius: CGFloat = 6
        nameBox.fill = selected ? accent : ChefTagPalette.paper
        nameBox.frame = NSRect(x: 0, y: 0, width: nameWidth, height: Self.tabHeight + (shape.term ? radius : 0))
        nameBox.radius = radius
        joint.isHidden = !shape.term
        joint.frame = NSRect(x: 0, y: Self.tabHeight, width: radius, height: radius)
        dot.frame = NSRect(x: 6, y: (Self.tabHeight - 6) / 2, width: 6, height: 6)
        dot.radius = 3
        dot.fill = content.stale ? .clear : content.phase.color
        dot.stroke = content.stale ? content.phase.color : nil
        let nameText = ceil(nameLabel.attributedStringValue.size().width) + 4
        nameLabel.frame = NSRect(x: 16, y: 1, width: nameText, height: Self.tabHeight - 2)
        modelLabel.isHidden = content.model.isEmpty
        modelLabel.frame = NSRect(x: nameLabel.frame.maxX + 1, y: 1.5, width: max(0, modelWidth), height: Self.tabHeight - 2)
        termBox.isHidden = !shape.term
        termBox.frame = NSRect(x: 0, y: Self.tabHeight, width: width, height: shape.strip)
        // Line one: the task. Line two: what it's doing now.
        taskLabel.isHidden = !shape.task
        taskLabel.frame = NSRect(x: 4, y: Self.stripPadding, width: max(0, width - 10), height: Self.lineHeight + 2)
        let lineY = Self.stripPadding + (shape.task ? Self.lineHeight : 0)
        termBox.radius = radius
        let outline = body.convert(shape.term ? termBox.frame : nameBox.frame, from: pill)
        ring.frame = outline.insetBy(dx: -1.5, dy: -1.5); glow.frame = ring.frame
        glyphBox.isHidden = !shape.line
        glyphBox.frame = NSRect(x: 5, y: lineY - 2, width: 8, height: Self.lineHeight + 4)
        glyphLabel.frame = NSRect(x: -2, y: 2, width: 12, height: Self.lineHeight + 2)
        glyphLabel.textColor = content.phase.color
        let x = glyphBox.frame.maxX
        clip.isHidden = !shape.line
        if shape.line {
            // A wider pill (the selected log is wider) gives the line its room.
            let room = termBox.frame.width - x - 4 - (content.phase.running ? 7 : 0) - 6
            let visible = min(max(textWidth(shape), room), lineWidth)
            clip.frame = NSRect(x: x + 4, y: lineY, width: visible + 1, height: Self.lineHeight + 2)
            lineLabel.frame = NSRect(x: -2, y: 0, width: lineWidth + 2, height: Self.lineHeight + 2)
        }
        caret.isHidden = !(shape.line && content.phase.running)
        if !caret.isHidden { caret.frame = NSRect(x: clip.frame.maxX + 1, y: lineY + 2, width: 5, height: 10) }
        // Needing you, selected or under the pointer: a ring around the pill.
        let ringColor: NSColor? = content.phase.needsYou ? content.phase.color : selected ? accent : hovered ? NSColor.white.withAlphaComponent(0.75) : nil
        ring.isHidden = ringColor == nil; ring.stroke = ringColor; ring.lineWidth = hovered && !selected && !content.phase.needsYou ? 1 : 1.5
        nameBox.stroke = ringColor; nameBox.lineWidth = ring.lineWidth
        glow.isHidden = !content.phase.needsYou || reducedMotion; glow.stroke = content.phase.color; glow.lineWidth = 1.5
        bar.isHidden = !shape.bar
        if shape.bar { bar.frame = NSRect(x: m, y: pill.frame.maxY + Self.barGap, width: width, height: ChefProgressView.height) }
        let cardBox = cardSize(shape)
        card.isHidden = cardBox.height == 0
        if !card.isHidden {
            card.frame = NSRect(x: m, y: (shape.bar ? bar.frame.maxY : pill.frame.maxY) + 3, width: width, height: cardBox.height)
            for (index, row) in cardRows.enumerated() {
                row.clip.isHidden = index >= cardLines.count
                row.clip.frame = NSRect(x: 7, y: 5 + CGFloat(index) * Self.cardLineHeight, width: width - 14, height: Self.cardLineHeight)
                row.label.frame = NSRect(x: -2, y: -1, width: self.width(of: row.label) + 2, height: Self.cardLineHeight + 2)
            }
        }
    }

    /// Long lines scroll to the end and back, pausing at each end (still under Reduce Motion).
    private func restartMarquee() {
        scroll(lineLabel, overflow: lineWidth - (clip.isHidden ? textWidth(shape()) : clip.frame.width - 1))
        // The selected log's recent activity: a line that doesn't fit scrolls on a loop, like a ticker.
        for (index, row) in cardRows.enumerated() {
            let text = index < cardLines.count ? cardLines[index] : ""
            ticker(row.label, text, room: card.isHidden || row.clip.isHidden ? .infinity : row.clip.frame.width)
        }
    }
    /// Space between a ticker line's end and its next pass.
    static let tickerGap = "   ·   "
    /// Shows `text`; when it's wider than `room`, it runs on repeat (text, gap, text) and scrolls
    /// one pass at a time without pausing, so the line never ends. Still under Reduce Motion.
    private func ticker(_ label: NSTextField, _ text: String, room: CGFloat) {
        label.layer?.removeAnimation(forKey: "marquee")
        let font = label.font ?? .monospacedSystemFont(ofSize: 9, weight: .regular)
        func measure(_ string: String) -> CGFloat { NSAttributedString(string: string, attributes: [.font: font]).size().width }
        let fits = measure(text) + 4 <= room
        label.stringValue = fits || reducedMotion ? text : text + Self.tickerGap + text
        label.frame.size.width = width(of: label) + 2
        guard !fits, !reducedMotion else { return }
        let pass = measure(text + Self.tickerGap)
        let run = CABasicAnimation(keyPath: "transform.translation.x")
        run.fromValue = 0; run.toValue = -pass
        run.duration = CFTimeInterval(pass / Self.scrollSpeed); run.repeatCount = .infinity
        run.timingFunction = CAMediaTimingFunction(name: .linear)
        label.layer?.add(run, forKey: "marquee")
    }
    /// A label's drawn width, with its own inset on each side.
    private func width(of label: NSTextField) -> CGFloat { ceil(label.attributedStringValue.size().width) + 4 }
    /// Rows for the selected log's lines; true when the text changed.
    @discardableResult private func setCardLines(_ lines: [String]) -> Bool {
        guard lines != cardLines else { return false }
        cardLines = lines
        while cardRows.count < lines.count {
            let clip = TagPart(); clip.clips = true
            let label = NSTextField(labelWithString: "")
            label.font = .monospacedSystemFont(ofSize: 9, weight: .regular); label.textColor = ChefTagPalette.dim
            label.lineBreakMode = .byClipping; label.wantsLayer = true
            clip.addSubview(label); card.addSubview(clip)
            cardRows.append((clip, label))
        }
        for (index, row) in cardRows.enumerated() { row.label.stringValue = index < lines.count ? lines[index] : "" }
        return true
    }
    private func scroll(_ label: NSTextField, overflow: CGFloat) {
        label.layer?.removeAnimation(forKey: "marquee")
        guard overflow > 1, !reducedMotion else { return }
        let travel = CFTimeInterval(overflow / Self.scrollSpeed), pause = Self.edgePause
        let total = pause + travel + pause + travel
        let scroll = CAKeyframeAnimation(keyPath: "transform.translation.x")
        scroll.values = [0, 0, -overflow, -overflow, 0]
        scroll.keyTimes = [0, pause / total, (pause + travel) / total, (pause + travel + pause) / total, 1].map { NSNumber(value: $0) }
        scroll.duration = total; scroll.repeatCount = .infinity
        label.layer?.add(scroll, forKey: "marquee")
    }

    /// The tag's motion: working bobs with a breathing dot and blinking cursor, needing you
    /// pulses, a failure shakes now and then, checks spin. Nothing under Reduce Motion.
    private func restartMotion() {
        for part in [body, dot, caret, glow, glyphBox] { part.layer?.removeAllAnimations() }
        guard let phase = content?.phase, !reducedMotion else { return }
        let quiet = mode == .compact && !phase.needsYou
        if phase.running && !quiet {
            body.layer?.add(Self.loop("transform.translation.y", [0, -2, 0], duration: 2.6), forKey: "bob")
            let blink = Self.loop("opacity", [1, 1, 0, 0], duration: 1); blink.calculationMode = .discrete
            caret.layer?.add(blink, forKey: "blink")
        }
        if phase == .thinking && !quiet { body.layer?.add(Self.loop("transform.translation.y", [0, -2, 0], duration: 4.2), forKey: "bob") }
        if (phase.running || phase == .thinking || phase.needsYou) && !quiet { dot.layer?.add(Self.loop("opacity", [1, 0.35, 1], duration: 1.4), forKey: "breathe") }
        if phase.needsYou {
            let fade = Self.loop("opacity", [0.7, 0, 0], duration: 1.6)
            let grow = Self.loop("borderWidth", [1.5, 6, 6], duration: 1.6)
            glow.layer?.add(fade, forKey: "pulse"); glow.layer?.add(grow, forKey: "grow")
        }
        if phase == .failed || phase == .needsFix {
            let shake = Self.loop("transform.translation.x", [0, 0, -3, 3, -2, 2, 0], duration: 4)
            shake.keyTimes = [0, 0.84, 0.86, 0.89, 0.92, 0.95, 1]
            body.layer?.add(shake, forKey: "shake")
        }
        if phase == .checking { glyphBox.layer?.add(spin(), forKey: "spin") }
    }
    /// A brief pop or shake for a moment (a step done, a test failed), with a quiet announcement.
    func react(_ moments: [ChefEmote], now: Date = Date()) {
        guard let first = moments.sorted().first, now.timeIntervalSince(lastReaction) >= 1 else { return }
        lastReaction = now
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: "\(content?.name ?? "") \(first.spoken)", .priority: NSAccessibilityPriorityLevel.low.rawValue])
        guard !reducedMotion else { return }
        if [.angry, .wrench, .alert].contains(first) {
            let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
            shake.values = [0, -3, 3, -2, 2, 0]; shake.duration = 0.4
            body.layer?.add(shake, forKey: "jolt")
        } else {
            glyphBox.layer?.add(pop(), forKey: "pop")
        }
    }

    private static func loop(_ key: String, _ values: [CGFloat], duration: CFTimeInterval) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: key)
        animation.values = values; animation.duration = duration; animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return animation
    }
    /// Scale or turn the symbol about its centre (a view's layer is anchored at its corner).
    private func about(_ transform: CATransform3D) -> NSValue {
        let c = CGPoint(x: glyphBox.bounds.midX, y: glyphBox.bounds.midY)
        return NSValue(caTransform3D: CATransform3DConcat(CATransform3DConcat(CATransform3DMakeTranslation(-c.x, -c.y, 0), transform), CATransform3DMakeTranslation(c.x, c.y, 0)))
    }
    private func pop() -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = [CATransform3DIdentity, CATransform3DMakeScale(1.5, 1.5, 1), CATransform3DMakeScale(0.9, 0.9, 1), CATransform3DIdentity].map(about)
        animation.duration = 0.45
        return animation
    }
    private func spin() -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = stride(from: 0.0, through: 1.0, by: 0.25).map { about(CATransform3DMakeRotation(-.pi * 2 * $0, 0, 0, 1)) }
        animation.duration = 2; animation.repeatCount = .infinity
        return animation
    }
}

/// The progress bar under a chef's pill: one outlined block per checklist step (or check), a
/// sweep for work without a list.
final class ChefProgressView: NSView {
    static let height: CGFloat = 6
    static let empty = NSColor(red: 0.08, green: 0.07, blue: 0.06, alpha: 0.6)
    private(set) var progress: ChefTagContent.Progress?
    private var color: NSColor = ChefTagPalette.ok
    private var live = false
    private var segments: [TagPart] = []
    private let sweep = TagPart()
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        sweep.fill = ChefTagPalette.ok; sweep.radius = 2
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Filled blocks (for tests): how many show done, or passed.
    var filled: Int { segments.filter { $0.fill != Self.empty }.count }
    var blocks: Int { segments.count }

    func update(_ progress: ChefTagContent.Progress?, color: NSColor, live: Bool) {
        guard progress != self.progress || color != self.color || live != self.live else { return }
        self.progress = progress; self.color = color; self.live = live
        let fills: [NSColor]
        switch progress {
        case .steps(let done, let total): fills = (0..<total).map { $0 < done ? color : Self.empty }
        case .checks(let checks): fills = checks.map { $0 == .passed ? ChefTagPalette.ok : $0 == .failed ? ChefTagPalette.fail : Self.empty }
        case .sweep: fills = [Self.empty]
        case nil: fills = []
        }
        while segments.count > fills.count { segments.removeLast().removeFromSuperview() }
        while segments.count < fills.count { let part = TagPart(); part.radius = 2; part.stroke = NSColor(white: 0.03, alpha: 0.85); part.lineWidth = 1; addSubview(part, positioned: .below, relativeTo: nil); segments.append(part) }
        for (part, fill) in zip(segments, fills) { part.fill = fill; part.layer?.removeAllAnimations() }
        if case .sweep = progress { if sweep.superview == nil { addSubview(sweep) } } else { sweep.removeFromSuperview() }
        sweep.fill = color
        switch progress {
        case .steps(let done, let total): setAccessibilityLabel("\(done) of \(total) steps done")
        case .checks(let checks): setAccessibilityLabel("\(checks.filter { $0 == .passed }.count) of \(checks.count) checks passed")
        case .sweep: setAccessibilityLabel("Working")
        case nil: setAccessibilityLabel(nil)
        }
        needsLayout = true
        animate()
    }
    override func layout() {
        super.layout()
        let gap: CGFloat = 2, count = CGFloat(max(1, segments.count))
        let width = (bounds.width - gap * (count - 1)) / count
        for (index, part) in segments.enumerated() { part.frame = CGRect(x: CGFloat(index) * (width + gap), y: 0, width: width, height: bounds.height) }
        sweep.frame = CGRect(x: 0, y: 1, width: bounds.width * 0.35, height: bounds.height - 2)
        animate()
    }
    /// The newest filled block glows while work goes on; the sweep moves across.
    private func animate() {
        sweep.layer?.removeAllAnimations()
        guard live else { return }
        if sweep.superview != nil {
            let move = CABasicAnimation(keyPath: "transform.translation.x")
            move.fromValue = -bounds.width * 0.35; move.toValue = bounds.width
            move.duration = 1.6; move.repeatCount = .infinity; move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            sweep.layer?.add(move, forKey: "sweep")
        } else if case .steps(let done, _) = progress, done > 0, done <= segments.count, segments[done - 1].layer?.animation(forKey: "glow") == nil {
            let glow = CAKeyframeAnimation(keyPath: "opacity")
            glow.values = [1, 0.55, 1]; glow.duration = 1.4; glow.repeatCount = .infinity
            segments[done - 1].layer?.add(glow, forKey: "glow")
        }
    }
}

/// A plain layer-backed part of a tag. Views, not loose sublayers: inside the kitchen's layer
/// tree, hand-added layers were scaled.
final class TagPart: NSView {
    var fill: NSColor? { didSet { needsDisplay = true } }
    var stroke: NSColor? { didSet { needsDisplay = true } }
    var lineWidth: CGFloat = 1.5 { didSet { needsDisplay = true } }
    var radius: CGFloat = 0 { didSet { needsDisplay = true } }
    var clips = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        guard let layer else { return }
        layer.backgroundColor = fill?.cgColor
        layer.borderColor = stroke?.cgColor; layer.borderWidth = stroke == nil ? 0 : lineWidth
        layer.cornerRadius = radius; layer.masksToBounds = clips
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
