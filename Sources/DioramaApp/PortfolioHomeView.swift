import SwiftUI
import DioramaCore

struct PortfolioHomeView: View {
    @Bindable var library: LibraryModel
    let projects: [SpatialProject]
    let active: Bool
    let select: (SpatialFocus) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduced
    private let ink = Color(red: 0.16, green: 0.23, blue: 0.23)
    static func columnCount(width: CGFloat) -> Int { width >= 1040 ? 2 : 1 }
    var body: some View {
        @Bindable var store = library.portfolio
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("PORTFOLIO").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2).foregroundStyle(.secondary)
                        Text("Projects").font(.system(size: 27, weight: .medium))
                    }
                    Spacer()
                    Text("\(projects.count) projects · All-time usage").font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 18)
                if projects.isEmpty {
                    ContentUnavailableView("Your projects belong here", systemImage: "square.grid.2x2", description: Text("Connect a project from the sidebar to start exploring its work."))
                } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: Self.columnCount(width: geometry.size.width)), spacing: 16) {
                            ForEach(store.ordered(projects)) { project in
                                PortfolioProjectTile(project: project, usage: store.usage(project.id), paused: library.paused,
                                    animate: active && !reduced && !library.paused, loading: library.isScanning, viewportHeight: max(0, geometry.size.height - 115), select: select)
                                    .id(project.id)
                            }
                        }.scrollTargetLayout().padding(.horizontal, 24).padding(.bottom, 24)
                    }.coordinateSpace(name: "portfolio-scroll").scrollPosition(id: $store.scrollID, anchor: .top)
                }
                HStack {
                    Text(library.paused ? "Observation paused" : "Updates from connected agents")
                    Spacer()
                    Text("Reported usage · may arrive in batches")
                }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 12)
            }.foregroundStyle(ink).background(Color(red: 0.975, green: 0.978, blue: 0.965))
        }.accessibilityElement(children: .contain).environment(\.colorScheme, .light).tint(Color(red: 0.12, green: 0.49, blue: 0.34))
    }
}

private struct PortfolioProjectTile: View {
    let project: SpatialProject
    let usage: PortfolioUsageSummary
    let paused: Bool
    let animate: Bool
    let loading: Bool
    let viewportHeight: CGFloat
    let select: (SpatialFocus) -> Void
    @State private var details = false
    @State private var attention = false
    @State private var onScreen = false
    private var exceptions: [PortfolioException] { PortfolioException.ordered(project) }
    private var summary: SpatialSummary { project.summary }
    private var tokenText: String {
        let count = usage.tokens.map(Self.compact)
        switch usage.coverage {
        case .loading: return count.map { "Loading · " + $0 } ?? "Loading…"
        case .unavailable: return "Unavailable"
        case .partial: return "Partial · " + (count ?? "Unavailable")
        case .reported: return count ?? "Unavailable"
        }
    }
    private static func compact(_ count: Int64) -> String {
        if count >= 1_000_000_000 { return String(format: "%.1fB", Double(count) / 1_000_000_000) }
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 10_000 { return String(format: "%.1fK", Double(count) / 1000) }
        return count.formatted()
    }
    var body: some View {
        GeometryReader { geometry in
            let slabWidth = max(64, min(180, geometry.size.width * 0.34))
            HStack(spacing: 16) {
                Button { select(.project(project.id)) } label: {
                    PortfolioPlatform(surface: PortfolioSurface(projectID: project.id))
                        .frame(width: slabWidth, height: slabWidth * 0.695)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Open \(project.name) office")
                metadataCard
            }.frame(maxHeight: .infinity)
                .onChange(of: geometry.frame(in: .named("portfolio-scroll")), initial: true) { _, frame in
                    onScreen = frame.maxY > 0 && frame.minY < viewportHeight
                }
        }.frame(height: 198).onDisappear { onScreen = false }
    }
    private func exceptionText(_ first: PortfolioException) -> String {
        let extra = exceptions.count > 1 ? " · +\(exceptions.count - 1) more" : ""
        return first.label + " · " + first.conversation + extra
    }
    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button { select(.project(project.id)) } label: {
                Text(project.name).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).help("Open project office")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { working; attentionButton }
                VStack(alignment: .leading, spacing: 5) { working; attentionButton }
            }
            Button { details.toggle() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "cylinder.split.1x2").foregroundStyle(.secondary)
                    Text(tokenText).fontWeight(.medium).monospacedDigit().lineLimit(1)
                    Text("tokens").foregroundStyle(.secondary)
                }.font(.system(size: 12))
            }.buttonStyle(.plain).help("Tokens consumed · All time")
                .accessibilityLabel("Tokens consumed, all time: \(tokenText). Show reported usage details")
                .popover(isPresented: $details) { usageDetails }
            if let first = exceptions.first {
                Button { select(first.destination) } label: {
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: first.priority == 2 ? "exclamationmark.triangle" : "arrow.up.right")
                        Text(exceptionText(first)).lineLimit(2)
                    }.font(.system(size: 11)).foregroundStyle(Color(red: 0.60, green: 0.34, blue: 0.04))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
            }
            if loading && project.teams.isEmpty {
                freshness("Discovering activity…", icon: "arrow.triangle.2.circlepath")
            } else if paused {
                freshness("Observation paused", icon: "pause.circle")
            } else if summary.stale > 0 {
                freshness("\(summary.stale) last known / unavailable", icon: "clock.badge.exclamationmark")
            } else if summary.working == 0 && summary.attention == 0 && summary.failed == 0 {
                freshness("No active work", icon: "minus.circle")
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.10), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.035), radius: 7, y: 3)
    }
    private var working: some View {
        HStack(spacing: 5) {
            PortfolioLiveIndicator(working: summary.working > 0 && !paused, animate: animate && onScreen)
            Text("\(summary.working) working").monospacedDigit()
        }.font(.system(size: 12)).accessibilityElement(children: .combine)
    }
    private var attentionButton: some View {
        Button { attention.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.bubble").foregroundStyle(summary.attention > 0 ? Color.orange : .gray)
                Text("\(summary.attention) need input").monospacedDigit()
            }.font(.system(size: 12))
        }.buttonStyle(.plain).accessibilityLabel("\(summary.attention) agents need input in \(project.name). Show attention list")
            .popover(isPresented: $attention) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(project.name + " · Attention").font(.headline)
                    if exceptions.isEmpty { Text("No reported requests or failures.").foregroundStyle(.secondary) }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(exceptions) { item in
                                Button { attention = false; select(item.destination) } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.label + " · " + item.agent.value.name)
                                        Text(item.conversation).font(.caption).foregroundStyle(.secondary)
                                        Text(item.agent.value.statusLabel).font(.caption2).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }.padding(16).frame(width: 330, height: 280)
            }
    }
    private func freshness(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
    }
    private var usageDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tokens consumed · All time").font(.headline)
            Text(usage.tokens.map { $0.formatted() + " reported tokens" } ?? "No reported token total available.").font(.title3.monospacedDigit())
            Text("\(usage.sources.count) contributing provider sources · \(usage.coverage.rawValue.capitalized)").font(.caption)
            Text("Includes available archived conversation usage. Cached input follows each provider’s accounting. Overlapping totals are not added together.").font(.caption).foregroundStyle(.secondary)
            if usage.coverage == .partial { Text("Some history is unavailable or delegated usage cannot be separated reliably. This is a known lower bound.").font(.caption) }
            if let date = usage.observedAt { Text("Last usage report: " + date.formatted(date: .abbreviated, time: .shortened)).font(.caption) }
        }.padding(18).frame(width: 320)
    }
}

/// Static platform geometry. Agent overlays can share PortfolioSurface.project without
/// changing tile layout, metrics, or navigation. Intentionally blank in this version.
struct PortfolioPlatform: View {
    let surface: PortfolioSurface
    var body: some View {
        Canvas { context, size in
            func point(_ u: Double, _ v: Double) -> CGPoint { surface.project(u: u, v: v, width: size.width, height: size.height) }
            let a = point(0, 0), b = point(1, 0), c = point(1, 1), d = point(0, 1)
            let depth = 9.0
            func lower(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: p.y + depth) }
            func polygon(_ points: [CGPoint]) -> Path {
                Path { p in p.addLines(points); p.closeSubpath() }
            }
            let left = polygon([d, c, lower(c), lower(d)])
            let right = polygon([c, b, lower(b), lower(c)])
            let top = polygon([a, b, c, d])
            let line = Color(red: 0.28, green: 0.40, blue: 0.36)
            context.fill(left, with: .color(Color(red: 0.88, green: 0.93, blue: 0.89)))
            context.fill(right, with: .color(Color(red: 0.82, green: 0.89, blue: 0.85)))
            context.fill(top, with: .color(Color(red: 0.94, green: 0.97, blue: 0.94)))
            for path in [left, right, top] { context.stroke(path, with: .color(line), lineWidth: 0.7) }
        }.accessibilityHidden(true)
    }
}

private struct PortfolioLiveIndicator: View {
    let working: Bool
    let animate: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: !working || !animate)) { context in
            let phase = working && animate ? (sin(context.date.timeIntervalSinceReferenceDate * .pi) + 1) / 2 : 0
            ZStack {
                Circle().stroke(working ? Color(red: 0.1, green: 0.57, blue: 0.36) : .gray.opacity(0.6), lineWidth: 1.5)
                if working { Circle().fill(Color(red: 0.1, green: 0.57, blue: 0.36)).padding(4).opacity(0.5 + phase * 0.5) }
            }.frame(width: 14, height: 14)
        }.accessibilityHidden(true)
    }
}
