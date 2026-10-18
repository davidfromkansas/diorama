import SwiftUI
import DioramaCore

/// What a project card can do; routed by HomeView.
struct HomeCardActions {
    var openAgent: (SpatialFocus) -> Void
    var newTask: (String) -> Void
    var openKitchen: (String) -> Void
    /// Asks before removing the project from Diorama.
    var removeProject: (_ id: String, _ name: String) -> Void = { _, _ in }
}

/// The section's cards in a row like the 2008 Xbox dashboard: one large card in front, the rest
/// angled and shrinking to the right. Every card is laid out once at full size and only scaled,
/// moved and turned, so moving swings the same card round into the front slot.
struct HomeCardRow<Card: Identifiable, Content: View>: View where Card.ID == String {
    let cards: [Card]
    @Binding var front: Int
    /// Angles the cards behind the front one (off for flat snapshots).
    var tilt = true
    /// Shorter in small windows, so the row never runs under the cards at the bottom.
    var height: CGFloat = Self.defaultHeight
    @ViewBuilder let content: (Card, _ isFront: Bool) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let frontWidth = Self.frontWidth(width)
            ZStack(alignment: .topLeading) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    let slot = (index - front + cards.count) % max(cards.count, 1)
                    let place = Self.place(slot: slot, frontWidth: frontWidth, width: width)
                    // Only the cards you can see (and the one just leaving) are drawn; the rest wait as empty frames.
                    Group { if place.visible || slot == cards.count - 1 { content(card, slot == 0) } else { Color.clear } }
                        .frame(width: frontWidth, height: height)
                        .overlay {
                            // Behind cards are previews: a click anywhere brings them forward.
                            if slot != 0 {
                                Color.clear.contentShape(Rectangle()).onTapGesture { move(to: index) }.pointingHand()
                                    .accessibilityElement().accessibilityLabel("Bring forward").accessibilityAddTraits(.isButton)
                                    .accessibilityAction { move(to: index) }
                            }
                        }
                        .scaleEffect(place.scale, anchor: .leading)
                        .rotation3DEffect(.degrees(reduceMotion || !tilt ? 0 : place.angle), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.55)
                        .offset(x: place.x)
                        .opacity(place.visible ? 1 : 0)
                        .zIndex(Double(100 - slot))
                        .allowsHitTesting(place.visible)
                        .accessibilityHidden(!place.visible)
                }
            }
            .frame(width: width, height: height, alignment: .topLeading)
            .overlay(alignment: .leading) { if hovering && cards.count > 1 { arrows(frontWidth: frontWidth) } }
        }
        .frame(height: height)
        .onHover { hovering = $0 }
        .background(ScrollSwipe { step($0) })
    }

    static var defaultHeight: CGFloat { 400 }
    /// The tallest the row grows in a tall window; beyond this the cards would just be empty space.
    static var maxHeight: CGFloat { 600 }
    // The front card's content (hero, pills, footer buttons) needs about 600 pt.
    static func frontWidth(_ width: CGFloat) -> CGFloat { min(780, max(600, width * 0.62)) }
    struct Place { var x: CGFloat; var scale: CGFloat; var angle: Double; var visible: Bool }
    /// Slot 0 is the front card; later slots step right, smaller and angled away.
    static func place(slot: Int, frontWidth: CGFloat, width: CGFloat) -> Place {
        guard slot > 0 else { return Place(x: 0, scale: 1, angle: 0, visible: true) }
        // Spread the cards behind across what's left of the row, the last one ending at its edge;
        // a turned card shows about 0.9 of its width.
        let offsets: [CGFloat] = [0, 0.45, 0.75, 1], scales: [CGFloat] = [0.66, 0.56, 0.48, 0.42]
        let k = min(slot - 1, offsets.count - 1)
        let start = frontWidth + 6, shown = frontWidth * scales[k] * 0.9
        return Place(x: start + max(0, width - start - shown) * offsets[k], scale: scales[k], angle: -26, visible: slot <= 4)
    }

    func step(_ direction: Int) {
        guard cards.count > 1 else { return }
        move(to: (front + direction + cards.count) % cards.count)
    }
    private func move(to index: Int) {
        guard index != front else { return }
        // Forward when the card was to the right of the front one.
        HomeSound.shared.move((index - front + cards.count) % cards.count <= cards.count / 2 ? 1 : -1)
        // Reduce Motion: no sliding or turning; the cards swap at once.
        if reduceMotion { front = index } else { withAnimation(.spring(duration: 0.45, bounce: 0.18)) { front = index } }
    }
    private func arrows(frontWidth: CGFloat) -> some View {
        HStack {
            arrow("chevron.left", label: "Previous") { step(-1) }
            Spacer()
            arrow("chevron.right", label: "Next") { step(1) }
        }.frame(width: frontWidth + 32).offset(x: -16)
    }
    private func arrow(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(HomeStyle.ink)
                .frame(width: 32, height: 32).background(.white, in: Circle()).overlay(Circle().strokeBorder(HomeStyle.border)).modifier(CardShadow())
        }.buttonStyle(.plain).pointingHand().accessibilityLabel(label)
    }
}

/// A project's card. In front: the coloured hero with tokens, the counts, every agent that isn't
/// idle and the actions. Behind: a colour stripe, the name and the counts.
struct HomeProjectCardView: View {
    let card: HomeProjectCard
    let front: Bool
    let days: [TokenSplit]?
    let actions: HomeCardActions
    var body: some View {
        HomeCardFrame(colour: HomeRank.colour(card.id)) {
            Text(card.name).font(.system(size: 30, weight: .bold)).tracking(-0.5).foregroundStyle(.white).lineLimit(3).minimumScaleFactor(0.6)
            if card.count(.working) > 0 { HomeLiveDot() }
            Spacer(minLength: 0)
            if let days, days.contains(where: { $0.total > 0 }) { HomeTokenSummary(days: days) }
        } content: {
            HomeCountPills(card: card).padding(.horizontal, 18).padding(.vertical, 14)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(card.rows) { row in HomeAgentRowView(row: row) { actions.openAgent(row.focus) } }
                }
            }
            .overlay(alignment: .top) { Rectangle().fill(HomeStyle.rule).frame(height: 1) }
            HomeCardFooter(project: card.id, name: card.name, actions: actions, urgent: urgent.map { urgent in
                (urgent.title, urgent.tint, { actions.openAgent(urgent.row.focus) })
            }, canRemove: card.count(.working) == 0)
        }
        .allowsHitTesting(front)
        .accessibilityElement(children: front ? .contain : .ignore)
        .accessibilityLabel(front ? card.name : "\(card.name). \(HomeCountPills.summary(card))")
    }
    /// Answer whoever has waited, else review the finished work.
    private var urgent: (row: HomeAgentRow, title: String, tint: Color)? {
        if let row = card.rows.first(where: { $0.state == .needsInput }) {
            let title = row.item.requests > 0 ? (row.item.requests > 1 ? "Review \(row.item.requests) requests" : "Review request") : "Answer"
            return (row, title, HomeStyle.orange)
        }
        let done = card.rows.filter { $0.state == .toReview }
        if let row = done.first { return (row, "Review \(done.count)", HomeStyle.green) }
        return nil
    }
}

/// Every Home card: a coloured hero on the left, the card's content on the right.
struct HomeCardFrame<Hero: View, Content: View>: View {
    let colour: Color
    @ViewBuilder let hero: () -> Hero
    @ViewBuilder let content: () -> Content
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Narrower on small cards, so the content beside it keeps its room.
                VStack(alignment: .leading, spacing: 10) { hero() }
                    .padding(18).frame(width: min(230, max(180, geometry.size.width * 0.3)), alignment: .leading)
                    .frame(maxHeight: .infinity, alignment: .top).background(colour)
                VStack(alignment: .leading, spacing: 0) { content() }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background(HomeStyle.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(HomeStyle.border))
        // The shadow comes from a plain shape behind the card, not the card's contents, so moving
        // cards don't re-blur everything on them every frame.
        .background(RoundedRectangle(cornerRadius: 14).fill(HomeStyle.card)
            .shadow(color: Color(red: 0.16, green: 0.08, blue: 0.27).opacity(0.22), radius: 20, y: 18))
    }
}

struct HomeLiveDot: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(red: 1, green: 0.42, blue: 0.42)).frame(width: 7, height: 7)
                .overlay(Circle().stroke(Color(red: 1, green: 0.42, blue: 0.42).opacity(0.3), lineWidth: 3))
            Text("Live").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
        }
    }
}

/// New task, Open kitchen (or office) and the card's main action.
struct HomeCardFooter: View {
    let project: String
    @Environment(ProjectScenes.self) private var scenes: ProjectScenes?
    private var place: String { SceneThemes.vocabulary(scenes?.kind(for: project) ?? .kitchen).place }
    /// For VoiceOver: "New task in kitchen-check", not three identical "New task" buttons.
    var name = ""
    let actions: HomeCardActions
    var urgent: (title: String, tint: Color, run: () -> Void)?
    /// Nothing is working in it, so it can be removed.
    var canRemove = true
    var body: some View {
        HStack(spacing: 8) {
            Button { actions.newTask(project) } label: {
                Label("New task", systemImage: "plus").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 34).background(HomeStyle.blue, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).pointingHand().accessibilityLabel(name.isEmpty ? "New task" : "New task in \(name)")
            Button { actions.openKitchen(project) } label: {
                Text("Open \(place)").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(HomeStyle.ink)
                    .padding(.horizontal, 14).frame(height: 34).background(.white, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(red: 0.85, green: 0.83, blue: 0.80)))
            }.buttonStyle(.plain).pointingHand().accessibilityLabel(name.isEmpty ? "Open \(place)" : "Open \(name)'s \(place)")
            settings
            Spacer()
            if let urgent {
                Button(action: urgent.run) {
                    Text(urgent.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        .padding(.horizontal, 12).frame(height: 34).background(urgent.tint, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).pointingHand()
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(HomeStyle.rule).frame(height: 1) }
    }
    /// The project's settings: for now, removing it from Diorama.
    private var settings: some View {
        Menu {
            Button("Remove from Diorama…", role: .destructive) { actions.removeProject(project, name) }
                .disabled(!canRemove)
            if !canRemove { Text("Stop this project's agents first") }
        } label: {
            Image(systemName: "gearshape").font(.system(size: 14, weight: .medium)).foregroundStyle(HomeStyle.secondary)
                .frame(width: 34, height: 34).background(.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(red: 0.85, green: 0.83, blue: 0.80)))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().pointingHand()
        .help("Project settings").accessibilityLabel(name.isEmpty ? "Project settings" : "Settings for \(name)")
    }
}

/// Working · Needs you · To review, in the project sidebar's colours.
struct HomeCountPills: View {
    let card: HomeProjectCard
    var body: some View {
        // Labels when they fit; just the numbers in their colours on a narrow card.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                pill(card.count(.working), "Working", .inProgress)
                pill(card.count(.needsInput), "Needs you", .needsYou)
                pill(card.count(.toReview), "To review", .done)
            }
            HStack(spacing: 6) {
                pill(card.count(.working), nil, .inProgress)
                pill(card.count(.needsInput), nil, .needsYou)
                pill(card.count(.toReview), nil, .done)
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(Self.summary(card))
    }
    static func summary(_ card: HomeProjectCard) -> String {
        "\(card.count(.working)) working, \(card.count(.needsInput)) need you, \(card.count(.toReview)) to review"
    }
    private func pill(_ count: Int, _ label: String?, _ group: AgentSidebarGroup) -> some View {
        let tint = SidebarStyle.tint(group)
        return HStack(spacing: 6) {
            Text("\(count)").font(.system(size: 14, weight: .heavy)).monospacedDigit()
            if let label { Text(label).font(.system(size: 12.5, weight: .semibold)) }
        }
        .foregroundStyle(tint.text).padding(.horizontal, 10).frame(height: 26)
        .background(tint.band, in: Capsule()).opacity(count > 0 ? 1 : 0.45).lineLimit(1).fixedSize()
    }
}

/// One agent on a card: the project sidebar's icon, title, status and progress.
struct HomeAgentRowView: View {
    let row: HomeAgentRow
    let open: () -> Void
    @State private var hovered = false
    var body: some View {
        let group: AgentSidebarGroup = switch row.state { case .needsInput: .needsYou; case .working: .inProgress; case .toReview: .done; case .idle: .idle }
        let tint = SidebarStyle.tint(group)
        Button(action: open) {
            HStack(alignment: .top, spacing: 12) {
                AgentSidebarIcon(group: group).padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.item.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(HomeStyle.ink).lineLimit(1)
                    HStack(spacing: 4) {
                        Text(row.state == .toReview ? (row.opened ? "Ready to decide" : "Not opened yet") : row.item.status).foregroundStyle(tint.text)
                        Text("·").foregroundStyle(HomeStyle.muted)
                        if !row.item.provider.isEmpty { HomeMark.provider(row.item.provider.lowercased().contains("claude") ? .claude : .codex).image(size: 11) }
                        Text(detail).foregroundStyle(HomeStyle.muted)
                    }.font(.system(size: 12.5)).lineLimit(1)
                    if let progress = row.item.progress {
                        AgentSidebarStatusBar(progress: progress, paused: row.state == .needsInput).padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18).padding(.vertical, 9)
            .background(hovered ? Color.black.opacity(0.03) : .clear)
            .overlay(alignment: .bottom) { Rectangle().fill(HomeStyle.rule).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointingHand().onHover { hovered = $0 }
        .help("Open \(row.item.title)")
        .accessibilityLabel("\(row.item.title). \(row.state == .toReview ? (row.opened ? "Ready to decide" : "Not opened yet") : row.item.status). \(detail)")
    }
    private var detail: String {
        // Finished work: when it finished, not the sidebar's idle line ("Waiting for a task").
        let finished = row.state == .toReview ? row.item.finishedAt.map { "Finished " + $0.formatted(.relative(presentation: .named)) } ?? "Finished" : nil
        let what = finished ?? row.item.question ?? (row.item.activity.isEmpty ? nil : row.item.activity)
        return [row.item.model, what].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// The week's chart when the card has room for it, else just today's total.
struct HomeTokenSummary: View {
    let days: [TokenSplit]
    var body: some View {
        ViewThatFits(in: .vertical) {
            HomeTokenWeek(days: days)
            HStack(alignment: .firstTextBaseline) {
                Text("TOKENS · TODAY").font(.system(size: 11, weight: .bold)).tracking(1).foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text(TokenCount.compact(days.last?.total ?? 0)).font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(.white)
            }
            Color.clear.frame(height: 0)
        }
    }
}

/// Tokens today, the last seven days as bars, and today's split of input and output.
struct HomeTokenWeek: View {
    let days: [TokenSplit]
    var body: some View {
        let today = days.last ?? TokenSplit()
        let peak = max(1, days.map(\.total).max() ?? 1)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("TOKENS · TODAY").font(.system(size: 11, weight: .bold)).tracking(1).foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text(TokenCount.compact(today.total)).font(.system(size: 20, weight: .bold, design: .monospaced)).foregroundStyle(.white)
            }
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    let isToday = index == days.count - 1
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3).fill(.white.opacity(isToday ? 1 : 0.5))
                            .frame(height: day.total > 0 ? max(3, 52 * CGFloat(day.total) / CGFloat(peak)) : 2)
                            .frame(height: 52, alignment: .bottom)
                        Text(label(index)).font(.system(size: 10.5, weight: isToday ? .bold : .medium)).foregroundStyle(.white.opacity(isToday ? 1 : 0.7))
                            .lineLimit(1).fixedSize()
                    }.frame(maxWidth: .infinity)
                        .help("\(label(index, full: true)): \(TokenCount.compact(day.total)) tokens")
                }
            }
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Rectangle().fill(.white.opacity(0.95)).frame(width: geometry.size.width * CGFloat(today.total > 0 ? Double(today.input) / Double(today.total) : 0))
                    Rectangle().fill(.white.opacity(0.45))
                }
            }.frame(height: 8).clipShape(Capsule())
            HStack {
                legend("in " + TokenCount.compact(today.input), opacity: 0.95)
                Spacer()
                legend("out " + TokenCount.compact(today.output), opacity: 0.45)
            }.font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tokens today \(today.total), \(today.input) in, \(today.output) out")
    }
    private func label(_ index: Int, full: Bool = false) -> String {
        if index == days.count - 1 { return "Today" }
        let date = Calendar.current.date(byAdding: .day, value: index - (days.count - 1), to: Date()) ?? Date()
        return full ? date.formatted(.dateTime.weekday(.wide)) : String(date.formatted(.dateTime.weekday(.narrow)))
    }
    private func legend(_ text: String, opacity: Double) -> some View {
        HStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(.white.opacity(opacity)).frame(width: 8, height: 8); Text(text) }
    }
}

/// Two-finger horizontal swipes over the card row, one card per gesture.
struct ScrollSwipe: NSViewRepresentable {
    let step: (Int) -> Void
    func makeNSView(context: Context) -> Catcher { Catcher() }
    func updateNSView(_ view: Catcher, context: Context) { view.step = step }
    static func dismantleNSView(_ view: Catcher, coordinator: ()) { view.stop() }
    final class Catcher: NSView {
        var step: ((Int) -> Void)?
        private var monitor: Any?
        private var travel: CGFloat = 0
        private var fired = false
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window, !self.isHiddenOrHasHiddenAncestor else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point), abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return event }
                if event.phase == .began || event.phase == .mayBegin { self.travel = 0; self.fired = false }
                self.travel += event.scrollingDeltaX
                if !self.fired, abs(self.travel) > 40 {
                    self.fired = true
                    let direction = self.travel < 0 ? 1 : -1
                    MainActor.assumeIsolated { self.step?(direction) }
                }
                if event.phase == .ended || event.phase == .cancelled { self.travel = 0; self.fired = false }
                return nil
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    }
}

/// The front slot when a section is empty: a blank card the size of a project card, so the page
/// doesn't jump, saying what will show up there.
struct HomeEmptyCard: View {
    let section: HomeSectionKind
    var searching = false
    var body: some View {
        let dash = StrokeStyle(lineWidth: 1.5, dash: [6, 5])
        HStack(spacing: 0) {
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(HomeStyle.purple.opacity(0.06)))
                var stripes = Path()
                var x = -size.height
                while x < size.width { stripes.move(to: CGPoint(x: x, y: size.height)); stripes.addLine(to: CGPoint(x: x + size.height, y: 0)); x += 14 }
                context.stroke(stripes, with: .color(HomeStyle.purple.opacity(0.08)), lineWidth: 2)
            }
            .frame(width: 230)
            .overlay(alignment: .trailing) { Rectangle().stroke(HomeStyle.purple.opacity(0.25), style: dash).frame(width: 0.75) }
            VStack(spacing: 14) {
                icon.frame(width: 52, height: 52).background(tint.band, in: Circle())
                Text(title).font(.system(size: 22, weight: .bold)).tracking(-0.3).foregroundStyle(HomeStyle.ink)
                Text(line).font(.system(size: 14.5)).foregroundStyle(HomeStyle.muted).multilineTextAlignment(.center).frame(maxWidth: 380)
            }
            .padding(.horizontal, 48).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(HomeStyle.card.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(HomeStyle.purple.opacity(0.35), style: dash))
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.01))
            .shadow(color: Color(red: 0.16, green: 0.08, blue: 0.27).opacity(0.08), radius: 20, y: 18))
        .accessibilityElement(children: .combine)
    }
    private var tint: SidebarStyle.Tint {
        switch section {
        case .needsYou: SidebarStyle.tint(.done)
        case .active: SidebarStyle.tint(.inProgress)
        case .needsReview: SidebarStyle.tint(.done)
        case .recent: SidebarStyle.Tint(band: Color(red: 0.937, green: 0.906, blue: 0.98), text: HomeStyle.purple, dot: HomeStyle.purple)
        }
    }
    @ViewBuilder private var icon: some View {
        let symbol = switch section {
        case .needsYou: "checkmark"
        case .active: "pause.circle"
        case .needsReview: "checkmark.seal"
        case .recent: searching ? "magnifyingglass" : "folder"
        }
        Image(systemName: symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(tint.text)
    }
    private var title: String {
        switch section {
        case .needsYou: "You're all caught up"
        case .active: "No agents at work"
        case .needsReview: "Nothing to review"
        case .recent: searching ? "No matching projects" : "No other projects yet"
        }
    }
    private var line: String {
        switch section {
        case .needsYou: "Agents that ask a question or need your approval show up here."
        case .active: "Start a task in any project and it shows up here while it runs."
        case .needsReview: "Finished work you haven't opened or decided on shows up here."
        case .recent: searching ? "Try a different name." : "Add a project and it shows up here when nothing is running in it."
        }
    }
}
