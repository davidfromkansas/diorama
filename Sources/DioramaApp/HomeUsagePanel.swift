import SwiftUI
import DioramaCore

/// Home's right column: agent status, weekly limits and where the last week's tokens went.
struct HomeUsagePanel: View {
    let home: HomeUsage
    var status = AgentStatusCounts()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HomeUsageSection(title: "Agents") {
                    AgentStatusRow(counts: status)
                }
                HomeUsageSection(title: "Usage", subtitle: "Weekly limits") {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach([Provider.claude, .codex], id: \.self) { provider in
                            StaminaRow(name: provider == .claude ? "Claude Code" : "Codex", plan: home.planName(provider), window: home.weekly[provider])
                        }
                    }
                }
                HomeUsageSection(title: "Token Flow", subtitle: "Past 7 days") {
                    TokenFlowModule(home: home)
                }
            }.padding(16)
        }.frame(width: 340).frame(maxHeight: .infinity).background(DioramaStyle.sidebar)
    }
}

/// Totals across every connected project, counting each conversation's main agent once — the
/// same unit the kitchen counts — with the sidebar's rules for blocked and unread.
struct AgentStatusCounts: Equatable {
    var running = 0, waiting = 0, unread = 0
    var approvals = 0, questions = 0, failures = 0
    static func make(_ projects: [SpatialProject], viewed: (WorkspaceAgent) -> Bool) -> Self {
        var counts = Self(), seen = Set<String>()
        for agent in projects.flatMap({ $0.teams.flatMap(\.agents) }) where agent.value.isMain && seen.insert(agent.id).inserted {
            if agent.value.isWorking { counts.running += 1; continue }
            switch AgentSidebarStatus.resolve(agent.value, viewed: viewed(agent.value)) {
            case .blocked:
                counts.waiting += 1
                if agent.value.status != .waiting { counts.failures += 1 }
                else if agent.value.attentionReason == .approval { counts.approvals += 1 }
                else { counts.questions += 1 }
            case .done: counts.unread += 1
            default: break
            }
        }
        return counts
    }
    var breakdown: String {
        [(approvals, "approval", "approvals"), (questions, "question", "questions"), (failures, "failed", "failed")]
            .filter { $0.0 > 0 }.map { "\($0.0) \($0.0 == 1 ? $0.1 : $0.2)" }.joined(separator: " · ")
    }
}

struct AgentStatusRow: View {
    let counts: AgentStatusCounts
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusTile(value: counts.running, title: "Running", tint: counts.running > 0 ? DioramaStyle.accent : nil,
                           accessibility: "\(counts.running) agents running")
                StatusTile(value: counts.waiting, title: "Waiting on you", tint: counts.waiting > 0 ? .orange : nil, emphasized: counts.waiting > 0,
                           accessibility: "\(counts.waiting) agents waiting on you" + (counts.breakdown.isEmpty ? "" : ": " + counts.breakdown.replacingOccurrences(of: " · ", with: ", ")))
                StatusTile(value: counts.unread, title: "Unread", tint: counts.unread > 0 ? DioramaStyle.accent : nil,
                           accessibility: "\(counts.unread) finished agents unread")
            }
            if !counts.breakdown.isEmpty {
                Text(counts.breakdown).font(.system(size: 11, design: .monospaced)).foregroundStyle(.orange)
            }
        }
    }
}

struct StatusTile: View {
    let value: Int
    let title: String
    var tint: Color?
    var emphasized = false
    let accessibility: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(value)").font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .foregroundStyle(emphasized ? AnyShapeStyle(tint ?? .primary) : AnyShapeStyle(.primary))
                Spacer(minLength: 0)
                Circle().fill(tint ?? Color.primary.opacity(0.2)).frame(width: 6, height: 6)
            }
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true).fixedSize(horizontal: false, vertical: true)
        }.padding(10).frame(maxWidth: .infinity, alignment: .topLeading)
            .background(emphasized ? (tint ?? .clear).opacity(0.12) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(emphasized ? (tint ?? .clear).opacity(0.5) : .clear, lineWidth: 1))
            .accessibilityElement(children: .ignore).accessibilityLabel(accessibility)
    }
}

/// One titled card in Home's right column.
struct HomeUsageSection<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                if let subtitle { Text(subtitle).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary) }
            }.accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            content()
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(DioramaStyle.border, lineWidth: 1))
    }
}

struct StaminaRow: View {
    let name: String
    let plan: String
    let window: LimitWindow?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let current = window.flatMap { $0.expired(now: context.date) ? nil : $0 }
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name).font(.system(size: 13, weight: .semibold))
                    Text(plan).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(Self.headline(current)).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Self.tint(current))
                }
                SegmentBar(left: current?.leftPercent, tint: Self.tint(current))
                HStack {
                    Text(current?.usedPercent.map { "\(Int($0.rounded()))% used" } ?? Self.statusText(current))
                    Spacer()
                    Text(Self.resetText(window, now: context.date))
                }.font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
            }.accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.accessibility(name: name, window: current, now: context.date))
        }
    }
    static func headline(_ window: LimitWindow?) -> String {
        guard let window else { return "—" }
        if let left = window.leftPercent { return "\(Int(left.rounded()))% LEFT" }
        return window.status == .exhausted ? "EMPTY" : window.status == .warning ? "LOW" : "OK"
    }
    static func tint(_ window: LimitWindow?) -> Color {
        guard let window else { return .secondary }
        if window.status == .exhausted || (window.leftPercent ?? 100) <= 0 { return .red }
        if window.status == .warning || (window.leftPercent ?? 100) <= 20 { return .orange }
        return DioramaStyle.accent
    }
    static func statusText(_ window: LimitWindow?) -> String {
        guard let window else { return "Not reported yet" }
        return switch window.status {
        case .exhausted: "Limit reached"
        case .warning: "Near limit"
        default: "Within limit"
        }
    }
    static func resetText(_ window: LimitWindow?, now: Date) -> String {
        guard let reset = window?.resetsAt else { return "" }
        if reset <= now { return "refilled" }
        return "refills " + reset.formatted(.dateTime.weekday(.abbreviated).hour().minute()) + " · " + countdown(reset.timeIntervalSince(now))
    }
    static func countdown(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60)), days = minutes / 1440, hours = minutes % 1440 / 60
        if days > 0 { return "\(days)d \(hours)h" }
        return hours > 0 ? "\(hours)h \(minutes % 60)m" : "\(minutes % 60)m"
    }
    static func accessibility(name: String, window: LimitWindow?, now: Date) -> String {
        guard let window else { return "\(name) weekly limit not reported yet" }
        var parts = ["\(name) weekly limit"]
        if let left = window.leftPercent, let used = window.usedPercent {
            parts.append("\(Int(left.rounded())) percent left, \(Int(used.rounded())) percent used")
        } else { parts.append(statusText(window)) }
        let reset = resetText(window, now: now)
        if !reset.isEmpty { parts.append(reset.replacingOccurrences(of: " · ", with: ", ")) }
        return parts.joined(separator: ", ")
    }
}

/// Twenty cells, filled for what is left, like a game's stamina meter.
struct SegmentBar: View {
    let left: Double?
    let tint: Color
    var body: some View {
        let filled = left.map { Int(($0 / 5).rounded()) } ?? 0
        HStack(spacing: 2) {
            ForEach(0..<20, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5).fill(index < filled ? tint : Color.primary.opacity(0.08))
            }
        }.frame(height: 12)
    }
}

struct TokenFlowModule: View {
    let home: HomeUsage
    @AppStorage("home.tokenFlow.byPlan") private var byPlan = false
    private var nodes: [HomeUsage.Node] { byPlan ? home.byPlan : home.byProject }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 24) {
                stat(home.tokens.input, "in")
                stat(home.tokens.output, "out")
            }
            Picker("Group by", selection: $byPlan) {
                Text("Projects").tag(false)
                Text("Plans").tag(true)
            }.pickerStyle(.segmented).labelsHidden().pointingHand()
            if nodes.isEmpty {
                Text(home.loading ? "Indexing history…" : "No token usage in the last 7 days.").font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                SankeyView(input: home.tokens.input, output: home.tokens.output, nodes: nodes, colors: byPlan ? Self.planColors(nodes) : Self.projectColors)
                Text("Input includes cached context.").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
    private func stat(_ value: Int64, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(PortfolioProjectTile.compact(value)).font(.system(size: 22, weight: .semibold, design: .monospaced))
            Text(label).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
    static let projectColors: [Color] = [DioramaStyle.accent, Color(red: 0.36, green: 0.66, blue: 0.48), Color(red: 0.40, green: 0.55, blue: 0.82),
        Color(red: 0.87, green: 0.58, blue: 0.38), Color(red: 0.80, green: 0.45, blue: 0.62), Color(red: 0.62, green: 0.62, blue: 0.66)]
    static func planColors(_ nodes: [HomeUsage.Node]) -> [Color] {
        nodes.map { $0.id == Provider.claude.rawValue ? Color(red: 0.85, green: 0.47, blue: 0.34) : Color.primary.opacity(0.6) }
    }
}

/// Node and ribbon geometry, kept separate from drawing so it can be checked without rendering.
struct SankeyLayout {
    struct Ribbon { var from: CGRect; var to: CGRect; var node: Int; var output: Bool }
    var left: [CGRect] = []
    var right: [CGRect] = []
    var ribbons: [Ribbon] = []
    /// Label centers for the right nodes, spread apart where small nodes sit too close to read.
    var labels: [CGFloat] = []
    init(input: Int64, output: Int64, nodes: [TokenSplit], size: CGSize, labelWidth: CGFloat = 52, rightLabelWidth: CGFloat = 132, nodeWidth: CGFloat = 6, gap: CGFloat = 6) {
        let total = Double(max(1, input + output))
        let leftX = labelWidth, rightX = size.width - rightLabelWidth - nodeWidth
        let leftScale = (size.height - gap) / total
        let rightScale = (size.height - gap * CGFloat(max(0, nodes.count - 1))) / total
        let inHeight = max(2, Double(input) * leftScale), outHeight = max(2, Double(output) * leftScale)
        left = [CGRect(x: leftX, y: 0, width: nodeWidth, height: inHeight), CGRect(x: leftX, y: inHeight + gap, width: nodeWidth, height: outHeight)]
        var y: CGFloat = 0, inY = left[0].minY, outY = left[1].minY
        for (index, node) in nodes.enumerated() {
            let rect = CGRect(x: rightX, y: y, width: nodeWidth, height: max(2, Double(node.total) * rightScale))
            right.append(rect)
            let inRight = Double(node.input) * rightScale, outRight = Double(node.output) * rightScale
            ribbons.append(.init(from: CGRect(x: leftX + nodeWidth, y: inY, width: 0, height: Double(node.input) * leftScale),
                                 to: CGRect(x: rightX, y: y, width: 0, height: inRight), node: index, output: false))
            ribbons.append(.init(from: CGRect(x: leftX + nodeWidth, y: outY, width: 0, height: Double(node.output) * leftScale),
                                 to: CGRect(x: rightX, y: y + inRight, width: 0, height: outRight), node: index, output: true))
            inY += Double(node.input) * leftScale; outY += Double(node.output) * leftScale
            y = rect.maxY + gap
        }
        let spacing: CGFloat = 15
        labels = right.map(\.midY)
        for index in labels.indices.dropFirst() { labels[index] = max(labels[index], labels[index - 1] + spacing) }
        if let last = labels.indices.last {
            labels[last] = min(labels[last], size.height - spacing / 2)
            for index in labels.indices.dropLast().reversed() { labels[index] = min(labels[index], labels[index + 1] - spacing) }
        }
    }
}

struct SankeyView: View {
    let input: Int64
    let output: Int64
    let nodes: [HomeUsage.Node]
    let colors: [Color]
    private let width: CGFloat = 278
    private var height: CGFloat { max(150, CGFloat(nodes.count) * 28) }
    var body: some View {
        let layout = SankeyLayout(input: input, output: output, nodes: nodes.map(\.tokens), size: CGSize(width: width, height: height))
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for ribbon in layout.ribbons where ribbon.from.height > 0 {
                    let a = ribbon.from, b = ribbon.to, mid = (a.minX + b.minX) / 2
                    var path = Path()
                    path.move(to: CGPoint(x: a.minX, y: a.minY))
                    path.addCurve(to: CGPoint(x: b.minX, y: b.minY), control1: CGPoint(x: mid, y: a.minY), control2: CGPoint(x: mid, y: b.minY))
                    path.addLine(to: CGPoint(x: b.minX, y: b.maxY))
                    path.addCurve(to: CGPoint(x: a.minX, y: a.maxY), control1: CGPoint(x: mid, y: b.maxY), control2: CGPoint(x: mid, y: a.maxY))
                    path.closeSubpath()
                    context.fill(path, with: .color(color(ribbon.node).opacity(ribbon.output ? 0.18 : 0.32)))
                }
                for rect in layout.left { context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(.primary.opacity(0.75))) }
                for (index, rect) in layout.right.enumerated() { context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color(index))) }
            }
            ForEach(Array(zip(["Input", "Output"], layout.left)), id: \.0) { name, rect in
                Text(name).font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .frame(width: rect.minX - 8, alignment: .trailing).position(x: (rect.minX - 8) / 2, y: rect.midY)
            }
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                let rect = layout.right[index]
                HStack(spacing: 5) {
                    Text(node.name).lineLimit(1).truncationMode(.tail)
                    Text(PortfolioProjectTile.compact(node.tokens.total)).foregroundStyle(.secondary).fixedSize()
                }.font(.system(size: 11)).frame(width: width - rect.maxX - 8, alignment: .leading)
                    .position(x: rect.maxX + 8 + (width - rect.maxX - 8) / 2, y: layout.labels[index])
            }
        }.frame(width: width, height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary)
    }
    var summary: String {
        let parts: [String] = nodes.map { node in node.name + " " + PortfolioProjectTile.compact(node.tokens.total) }
        let totals = PortfolioProjectTile.compact(input) + " in, " + PortfolioProjectTile.compact(output) + " out. "
        return "Token flow, last 7 days: " + totals + parts.joined(separator: ", ")
    }
    private func color(_ index: Int) -> Color { colors.isEmpty ? DioramaStyle.accent : colors[index % colors.count] }
}
