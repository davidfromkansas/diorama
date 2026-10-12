import SwiftUI
import simd
import DioramaCore

/// The Home tab's city: every project a building on its permanent lot, districts by GitHub owner.
/// Click a building and the bus drives there, then the project opens, like Overcooked 2's map.
struct OverworldView: View {
    let projects: [SpatialProject]
    let ledger: OverworldLotLedger
    /// Projects that joined the city this session, and when, so they rise into place.
    let arrivals: [String: Date]
    let usage: (String) -> PortfolioUsageSummary
    /// Saved camera; nil frames the whole city.
    @Binding var camera: OverworldCamera?
    let animate: Bool
    let paused: Bool
    let loading: Bool
    /// Where the bus waits: the project opened most recently.
    let parkedAt: String?
    /// Projects whose name plates always show.
    let named: Set<String>
    /// Search matches; nil when not searching. Everything else fades.
    let matches: Set<String>?
    let open: (SpatialFocus) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var live: OverworldCamera?
    @State private var dragStart: OverworldCamera?
    @State private var hovered: String?
    @State private var highlighted: String?
    @State private var bus: OverworldBus?
    @State private var parked: SIMD2<Double>?
    @State private var trip: Task<Void, Never>?
    @State private var commit: Task<Void, Never>?
    @State private var details: String?

    static let tick = 0.6

    struct Scene {
        let layout: OverworldLayout
        /// Painter's order.
        let models: [OverworldBuildingModel]
        let byID: [String: OverworldBuildingModel]
        let massings: [String: PortfolioMassing]
        let fit: OverworldCamera
    }

    var body: some View {
        GeometryReader { geometry in
            content(size: geometry.size)
        }
    }

    private func scene(size: CGSize) -> Scene {
        let layout = OverworldLayout(ledger: ledger)
        let lookup = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var models: [OverworldBuildingModel] = []
        for lot in layout.lots {
            guard let id = lot.projectID, let project = lookup[id] else { continue }
            let metrics = PortfolioBuildingMetrics(conversations: project.teams.count, tokens: usage(id).tokens)
            let massing = PortfolioMassing(.of(projectID: id, metrics: metrics), metrics: metrics)
            models.append(OverworldBuildingModel(project: project, lot: lot, massing: massing))
        }
        let byID = Dictionary(models.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let tallest = models.map(\.massing.peak.z).max() ?? 6
        return Scene(layout: layout, models: models, byID: byID, massings: byID.mapValues(\.massing),
                     fit: OverworldCamera.fit(layout, height: tallest + 2, size: size))
    }

    private func view(_ scene: Scene) -> OverworldCamera {
        (live ?? camera ?? scene.fit).clamped(to: scene.layout)
    }

    @ViewBuilder private func content(size: CGSize) -> some View {
        let scene = scene(size: size)
        let projection = view(scene).projection(size: size)
        ZStack(alignment: .topLeading) {
            world(scene, projection)
            busLayer(scene, projection)
            markers(scene, projection)
            if let id = hovered, let model = scene.byID[id] { tag(model, projection) }
            detailsAnchor(scene, projection)
            controls(scene, size: size, projection)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .contentShape(Rectangle())
        .background(OverworldInput(
            pan: { delta in move(view(scene).panned(by: delta, size: size), scene) },
            zoom: { factor, anchor in move(view(scene).zoomed(by: factor, anchor: anchor, size: size, minUnit: scene.fit.unit * 0.8), scene) }))
        .gesture(DragGesture(minimumDistance: 4)
            .onChanged { drag in
                let start = dragStart ?? view(scene)
                dragStart = start
                live = start.panned(by: drag.translation, size: size).clamped(to: scene.layout)
            }
            .onEnded { _ in
                if let live { camera = live }
                live = nil; dragStart = nil
            })
        .onTapGesture(coordinateSpace: .local) { location in
            if let id = OverworldHit.project(at: location, layout: scene.layout, massings: scene.massings, projection) {
                send(id, to: .project(id), scene, projection, size: size)
            }
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location):
                let id = OverworldHit.project(at: location, layout: scene.layout, massings: scene.massings, projection)
                if id != hovered { hovered = id }
            case .ended:
                if hovered != nil { hovered = nil }
            }
        }
        .contextMenu { menu(scene, projection, size: size) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Project city")
        .accessibilityChildren {
            ForEach(scene.models, id: \.id) { model in
                Button("Open \(model.project.name). \(model.summary.text)") { send(model.id, to: .project(model.id), scene, projection, size: size) }
            }
        }
        .onDisappear { trip?.cancel(); commit?.cancel() }
    }

    // MARK: Layers

    private func world(_ scene: Scene, _ projection: OverworldProjection) -> some View {
        TimelineView(schedule(scene)) { timeline in
            Canvas { graphics, size in
                drawWorld(graphics, size: size, scene, projection, date: timeline.date)
            }
        }.allowsHitTesting(false)
    }

    /// Ticks only while something on the map moves: working floors and pins, or a rising building.
    private func schedule(_ scene: Scene) -> AnimationTimelineSchedule {
        let signalling = scene.models.contains { $0.summary.working > 0 || $0.summary.attention > 0 || $0.summary.failed > 0 }
        let rising = !reduceMotion && arrivals.values.contains { Date.now.timeIntervalSince($0) < 1 }
        return .animation(minimumInterval: rising ? nil : Self.tick, paused: !(animate && signalling) && !rising)
    }

    /// Signs, name plates and pins, above the bus.
    private func markers(_ scene: Scene, _ projection: OverworldProjection) -> some View {
        TimelineView(schedule(scene)) { timeline in
            Canvas { graphics, size in
                let renderer = OverworldRenderer(graphics: graphics, projection: projection, layout: scene.layout, dark: scheme == .dark,
                                                 viewport: CGRect(origin: .zero, size: size))
                let tick = animate ? Int(timeline.date.timeIntervalSinceReferenceDate / Self.tick) : 0
                let visible = scene.models.filter(renderer.isVisible)
                renderer.drawBanners()
                for model in visible where showsPlate(model.id, projection) { renderer.drawPlate(model) }
                for model in visible { renderer.drawPin(model, blinkOff: animate && tick % 2 == 1) }
            }
        }.allowsHitTesting(false)
    }

    private func drawWorld(_ graphics: GraphicsContext, size: CGSize, _ scene: Scene, _ projection: OverworldProjection, date: Date) {
        let renderer = OverworldRenderer(graphics: graphics, projection: projection, layout: scene.layout, dark: scheme == .dark,
                                         viewport: CGRect(origin: .zero, size: size))
        renderer.drawGround()
        let tick = animate ? Int(date.timeIntervalSinceReferenceDate / Self.tick) : 0
        let visible = scene.models.filter(renderer.isVisible)
        for model in visible {
            let faded = matches.map { !$0.contains(model.id) } ?? false
            renderer.drawBuilding(model, animate: animate, tick: tick, rise: rise(model.id, at: date), faded: faded)
            if model.id == hovered || model.id == highlighted { renderer.drawOutline(model) }
        }
    }

    private func busLayer(_ scene: Scene, _ projection: OverworldProjection) -> some View {
        TimelineView(.animation(paused: bus == nil)) { timeline in
            Canvas { graphics, size in
                let renderer = OverworldRenderer(graphics: graphics, projection: projection, layout: scene.layout, dark: scheme == .dark,
                                                 viewport: CGRect(origin: .zero, size: size))
                guard let place = busPlace(scene, at: timeline.date) else { return }
                renderer.drawBus(at: place.point, heading: place.heading)
                // Buildings standing in front of the bus are drawn again over it.
                let center = projection.screen(place.point)
                let reach = projection.unit * 2
                let area = CGRect(x: center.x - reach, y: center.y - reach * 1.5, width: reach * 2, height: reach * 2)
                for model in scene.models where renderer.occludes(model, bus: place.point) {
                    let outline = OverworldHit.silhouette(model.massing, at: model.lot, projection)
                    guard Path({ $0.addLines(outline); $0.closeSubpath() }).boundingRect.intersects(area) else { continue }
                    renderer.drawBuilding(model, animate: false, tick: 0, faded: matches.map { !$0.contains(model.id) } ?? false, ground: false)
                }
            }
        }.allowsHitTesting(false)
    }

    /// Name and status floating over the hovered building.
    private func tag(_ model: OverworldBuildingModel, _ projection: OverworldProjection) -> some View {
        let peak = model.massing.peak
        let top = projection.screen(model.lot.origin.x + peak.x, model.lot.origin.y + peak.y, peak.z)
        return VStack(spacing: 2) {
            Text(model.project.name).font(.system(size: 12, weight: .semibold))
            Text(model.summary.text).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .fixedSize()
        .position(x: top.x, y: top.y - 44)
        .allowsHitTesting(false)
    }

    /// The details card for a building, opened from its context menu.
    private func detailsAnchor(_ scene: Scene, _ projection: OverworldProjection) -> some View {
        let model = details.flatMap { scene.byID[$0] }
        let point = model.map { m -> CGPoint in
            let peak = m.massing.peak
            return projection.screen(m.lot.origin.x + peak.x, m.lot.origin.y + peak.y, peak.z)
        } ?? .zero
        return Color.clear.frame(width: 1, height: 1).position(point)
            .popover(isPresented: Binding(get: { model != nil }, set: { if !$0 { details = nil } }), arrowEdge: .top) {
                if let model {
                    PortfolioProjectFacts(project: model.project, usage: usage(model.id), paused: paused, animate: animate, loading: loading) { focus in
                        details = nil
                        open(focus)
                    }.frame(width: 300).padding(6)
                }
            }
    }

    // MARK: Controls

    private struct Request: Identifiable {
        let projectID: String
        let projectName: String
        let item: PortfolioException
        var id: String { item.id }
    }

    private func requests(_ scene: Scene) -> [Request] {
        scene.models.flatMap { model in
            PortfolioException.ordered(model.project).map { Request(projectID: model.id, projectName: model.project.name, item: $0) }
        }.sorted {
            if $0.item.priority != $1.item.priority { return $0.item.priority < $1.item.priority }
            return ($0.item.agent.value.observedAt ?? .distantFuture) < ($1.item.agent.value.observedAt ?? .distantFuture)
        }
    }

    private func controls(_ scene: Scene, size: CGSize, _ projection: OverworldProjection) -> some View {
        let waiting = requests(scene)
        return HStack(alignment: .top, spacing: 6) {
            if !waiting.isEmpty {
                Text("Needs you").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.vertical, 7)
                ForEach(waiting.prefix(5)) { request in
                    Button { send(request.projectID, to: request.item.destination, scene, projection, size: size) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: request.item.priority == 2 ? "exclamationmark.triangle.fill" : "exclamationmark.bubble.fill")
                                .foregroundStyle(request.item.priority == 2 ? Color.red : Color.orange)
                            Text(request.item.label).fontWeight(.medium)
                            Text(request.projectName).foregroundStyle(.secondary)
                        }.font(.system(size: 11)).lineLimit(1)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                    }.buttonStyle(.plain).pointingHand()
                        .help(request.item.conversation)
                        .onHover { inside in highlighted = inside ? request.projectID : (highlighted == request.projectID ? nil : highlighted) }
                }
                if waiting.count > 5 {
                    Menu("+\(waiting.count - 5)") {
                        ForEach(waiting.dropFirst(5)) { request in
                            Button(request.item.label + " · " + request.projectName) { send(request.projectID, to: request.item.destination, scene, projection, size: size) }
                        }
                    }.menuStyle(.borderlessButton).fixedSize().padding(.vertical, 5).pointingHand()
                }
            }
            Spacer(minLength: 0)
            Button { camera = nil; live = nil } label: {
                Label("Fit all", systemImage: "arrow.down.right.and.arrow.up.left").font(.system(size: 11))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
            }.buttonStyle(.plain).pointingHand().keyboardShortcut("0", modifiers: .command).help("Show the whole city (⌘0)")
        }.padding(12)
    }

    @ViewBuilder private func menu(_ scene: Scene, _ projection: OverworldProjection, size: CGSize) -> some View {
        if let id = hovered, let model = scene.byID[id] {
            Button("Open \(model.project.name)") { send(id, to: .project(id), scene, projection, size: size) }
            ForEach(PortfolioException.ordered(model.project)) { item in
                Button(item.label + " · " + item.conversation) { send(id, to: item.destination, scene, projection, size: size) }
            }
            Divider()
            Button("Show Details") { details = id }
        } else {
            Button("Fit All") { camera = nil; live = nil }
        }
    }

    // MARK: Behaviour

    private func move(_ next: OverworldCamera, _ scene: Scene) {
        live = next.clamped(to: scene.layout)
        // Save once the scrolling settles, not on every event.
        commit?.cancel()
        commit = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let settled = live else { return }
            camera = settled
            live = nil
        }
    }

    private func showsPlate(_ id: String, _ projection: OverworldProjection) -> Bool {
        named.contains(id) || matches?.contains(id) == true || projection.unit >= 14
    }

    /// Height fraction for a newly arrived building: a quick rise with a little overshoot.
    private func rise(_ id: String, at date: Date) -> Double {
        guard !reduceMotion, let arrived = arrivals[id] else { return 1 }
        let t = min(1, max(0, date.timeIntervalSince(arrived) / 0.7))
        let overshoot = 1.70158, back = t - 1
        return 1 + (overshoot + 1) * back * back * back + overshoot * back * back
    }

    private func busPlace(_ scene: Scene, at date: Date) -> (point: SIMD2<Double>, heading: SIMD2<Double>)? {
        if let bus { return bus.position(after: date.timeIntervalSince(bus.start)) }
        if let parked { return (parked, SIMD2(1, 0)) }
        if let id = parkedAt, let lot = scene.layout.lot(for: id) { return (lot.door, SIMD2(1, 0)) }
        guard !scene.layout.districts.isEmpty else { return nil }
        return (scene.layout.position(.init(district: 0, column: 0, row: 0)), SIMD2(1, 0))
    }

    /// Drives the bus to a project's door, then opens `focus`. With Reduce Motion, opens at once.
    private func send(_ id: String, to focus: SpatialFocus, _ scene: Scene, _ projection: OverworldProjection, size: CGSize) {
        guard !reduceMotion, let lot = scene.layout.lot(for: id), var start = busPlace(scene, at: .now)?.point else {
            open(focus); return
        }
        // A bus parked off screen joins at the nearest intersection the viewer can see.
        let viewport = CGRect(origin: .zero, size: size).insetBy(dx: 24, dy: 24)
        if !viewport.contains(projection.screen(start)) {
            let visible = scene.layout.nodes.filter { viewport.contains(projection.screen(scene.layout.position($0))) }
            guard let node = scene.layout.nearestNode(to: lot.door, among: visible) else { open(focus); return }
            start = scene.layout.position(node)
        }
        let next = OverworldBus(path: scene.layout.route(from: start, to: lot), start: .now, target: id)
        bus = next
        trip?.cancel()
        trip = Task { @MainActor in
            try? await Task.sleep(for: .seconds(next.duration))
            guard !Task.isCancelled else { return }
            parked = lot.door
            bus = nil
            open(focus)
        }
    }
}
