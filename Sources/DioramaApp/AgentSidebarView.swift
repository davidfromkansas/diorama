import AppKit
import DioramaCore
import SwiftUI

/// Light, warm colours for the agent sidebar card.
enum SidebarStyle {
    static let background = Color(red: 0.988, green: 0.982, blue: 0.970)
    static let divider = Color.black.opacity(0.07)
    static let title = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let secondary = Color(red: 0.42, green: 0.42, blue: 0.44)
    static let selected = Color(red: 0.90, green: 0.94, blue: 1.0)
    static let accent = Color(red: 0.16, green: 0.42, blue: 0.93)
    static let horizontal: CGFloat = 12
    static let rowHeight: CGFloat = 72, actionRowHeight: CGFloat = 80, bandHeight: CGFloat = 30
    /// Extra height for a row's status bar.
    static let statusBarHeight: CGFloat = 12
    struct Tint { let band: Color; let text: Color; let dot: Color }
    static func tint(_ group: AgentSidebarGroup) -> Tint {
        switch group {
        case .needsYou: Tint(band: Color(red: 1.0, green: 0.95, blue: 0.88), text: Color(red: 0.66, green: 0.33, blue: 0.02), dot: Color(red: 0.96, green: 0.6, blue: 0.1))
        case .inProgress: Tint(band: Color(red: 0.91, green: 0.94, blue: 1.0), text: Color(red: 0.11, green: 0.36, blue: 0.82), dot: Color(red: 0.19, green: 0.44, blue: 0.93))
        case .done: Tint(band: Color(red: 0.91, green: 0.97, blue: 0.92), text: Color(red: 0.11, green: 0.47, blue: 0.23), dot: Color(red: 0.18, green: 0.67, blue: 0.31))
        case .idle: Tint(band: Color(red: 0.94, green: 0.94, blue: 0.93), text: Color(red: 0.33, green: 0.33, blue: 0.35), dot: Color(red: 0.56, green: 0.56, blue: 0.58))
        }
    }
}

/// The kitchen's agent card: project counts and Create, search, then the conversations grouped
/// Needs you → In progress → Done → Idle. Header and search stay put while the groups scroll.
struct AgentSidebarCard: View {
    let items: [AgentSidebarItem]
    let projectID: String
    let selectedConversation: String?
    let select: (AgentSidebarItem) -> Void
    let reviewRequest: (AgentSidebarItem) -> Void
    let reviewChanges: (AgentSidebarItem) -> Void
    let create: (() -> Void)?
    @State private var query = ""
    @State private var collapsed: Set<AgentSidebarGroup> = []
    @FocusState private var searchFocused: Bool

    var body: some View {
        let summary = AgentSidebar.summary(items)
        let shown = items.filter { $0.matches(query) }
        VStack(spacing: 0) {
            SidebarHeader(summary: summary, create: create)
                .padding(.horizontal, SidebarStyle.horizontal).padding(.top, 12).padding(.bottom, 8)
            SidebarSearchField(query: $query, focused: $searchFocused)
                .padding(.horizontal, SidebarStyle.horizontal).padding(.bottom, 10)
            Rectangle().fill(SidebarStyle.divider).frame(height: 1)
            if items.isEmpty {
                emptyState("Create an agent to get started.")
            } else if shown.isEmpty {
                emptyState("No matching agents")
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(AgentSidebarGroup.allCases) { group in
                            let rows = shown.filter { $0.group == group }
                            if !rows.isEmpty {
                                SidebarGroupHeader(group: group, count: rows.count, expanded: !collapsed.contains(group)) { toggle(group) }
                                if !collapsed.contains(group) {
                                    ForEach(rows) { item in
                                        AgentSidebarRow(item: item, selected: item.conversationID == selectedConversation,
                                                        select: { select(item) },
                                                        action: { item.group == .done ? reviewChanges(item) : reviewRequest(item) })
                                        // A row that moves to another group is a new row there: the lazy
                                        // list would otherwise keep showing its old icon, status and button.
                                        .id(item.id + "\u{1F}" + String(item.group.rawValue))
                                    }
                                }
                            }
                        }
                    }
                    .accessibilityElement(children: .contain).accessibilityLabel("Agents")
                }
                .scrollIndicators(.automatic)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SidebarStyle.background)
        .environment(\.colorScheme, .light)
        .onChange(of: projectID, initial: true) { _, project in collapsed = AgentSidebarCollapse.load(project) }
    }
    private func toggle(_ group: AgentSidebarGroup) {
        if collapsed.contains(group) { collapsed.remove(group) } else { collapsed.insert(group) }
        AgentSidebarCollapse.save(collapsed, project: projectID)
    }
    private func emptyState(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary)
            .frame(maxWidth: .infinity, alignment: .center).padding(.top, 28)
            .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct SidebarHeader: View {
    let summary: AgentSidebar.Summary
    let create: (() -> Void)?
    var body: some View {
        HStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                Text(AgentSidebar.summaryText(summary))
                // Narrow cards: the same counts with coloured dots instead of words.
                HStack(spacing: 8) {
                    count(summary.active, .inProgress); count(summary.needsYou, .needsYou); count(summary.done, .done)
                }
            }
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(SidebarStyle.title)
            .lineLimit(1)
            .accessibilityElement(children: .ignore).accessibilityLabel(AgentSidebar.summaryText(summary))
            Spacer(minLength: 6)
            if let create {
                Button("Create", action: create).buttonStyle(ModalPrimaryButtonStyle()).accessibilityLabel("Create agent")
                    .help("Create an agent in this project")
            }
        }
    }
    private func count(_ value: Int, _ group: AgentSidebarGroup) -> some View {
        HStack(spacing: 4) { Circle().fill(SidebarStyle.tint(group).dot).frame(width: 7, height: 7); Text("\(value)") }
    }
}

private struct SidebarSearchField: View {
    @Binding var query: String
    var focused: FocusState<Bool>.Binding
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary)
            TextField("Search agents…", text: $query).textFieldStyle(.plain).font(.system(size: 13))
                .focused(focused).accessibilityLabel("Search agents")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search").pointingHand()
            }
        }
        .padding(.horizontal, 9).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(focused.wrappedValue ? SidebarStyle.accent.opacity(0.7) : Color.black.opacity(0.12), lineWidth: focused.wrappedValue ? 2 : 1))
    }
}

private struct SidebarGroupHeader: View {
    let group: AgentSidebarGroup
    let count: Int
    let expanded: Bool
    let toggle: () -> Void
    var body: some View {
        let tint = SidebarStyle.tint(group)
        Button(action: toggle) {
            HStack(spacing: 8) {
                Circle().fill(tint.dot).frame(width: 8, height: 8)
                Text(group.title).font(.system(size: 13, weight: .semibold))
                Text("\(count)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 6).frame(minWidth: 18, minHeight: 17)
                    .background(Capsule().fill(tint.dot.opacity(0.18)))
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 0 : -90))
            }
            .foregroundStyle(tint.text)
            .padding(.horizontal, SidebarStyle.horizontal).frame(height: SidebarStyle.bandHeight)
            .background(tint.band).contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointingHand()
        .overlay(alignment: .bottom) { Rectangle().fill(SidebarStyle.divider).frame(height: 1) }
        .accessibilityLabel("\(group.title), \(count)")
        .accessibilityValue(expanded ? "expanded" : "collapsed")
        .accessibilityHint(expanded ? "Collapses the group" : "Expands the group")
        .accessibilityAddTraits(.isHeader)
    }
}

/// One conversation: status icon, then title, status · model, and live activity or a review button.
struct AgentSidebarRow: View {
    let item: AgentSidebarItem
    let selected: Bool
    let select: () -> Void
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var hovered = false
    var body: some View {
        let tint = SidebarStyle.tint(item.group)
        HStack(alignment: .top, spacing: 10) {
            AgentSidebarIcon(group: item.group).frame(width: 24, height: 24).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                AgentHoverTitle(text: item.title, active: !reduceMotion, size: 13, bold: true).frame(height: 17)
                (Text(item.status).foregroundColor(tint.text) + Text(" · " + item.model).foregroundColor(SidebarStyle.secondary))
                    .font(.system(size: 11.5)).lineLimit(1).truncationMode(.tail).frame(height: 15)
                if item.hasAction {
                    ReviewActionButton(title: item.actionTitle, action: action).padding(.top, 2)
                } else {
                    Text(item.activity).font(.system(size: 11.5)).foregroundStyle(SidebarStyle.secondary)
                        .lineLimit(1).truncationMode(.tail).frame(height: 15)
                }
                if let progress = item.progress {
                    AgentSidebarStatusBar(progress: progress, paused: item.group == .needsYou).padding(.top, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, SidebarStyle.horizontal).padding(.top, 11)
        .frame(height: (item.hasAction ? SidebarStyle.actionRowHeight : SidebarStyle.rowHeight) + (item.progress == nil ? 0 : SidebarStyle.statusBarHeight), alignment: .top)
        .background(selected ? SidebarStyle.selected : hovered ? Color.black.opacity(0.03) : Color.clear)
        .overlay(alignment: .leading) { if selected { Rectangle().fill(SidebarStyle.accent).frame(width: 3) } }
        .overlay(alignment: .bottom) { Rectangle().fill(SidebarStyle.divider).frame(height: 1).padding(.leading, SidebarStyle.horizontal + 34) }
        .overlay { if focused { RoundedRectangle(cornerRadius: 4).strokeBorder(SidebarStyle.accent.opacity(0.8), lineWidth: 2).padding(1) } }
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hovered = $0 }
        .focusable().focused($focused)
        .onKeyPress(.return) { select(); return .handled }
        .onKeyPress(.space) { select(); return .handled }
        .help(item.title)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.title). \(item.status), \(item.model)" + (item.hasAction ? "" : ". \(item.activity)"))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select() }
        .accessibilityAction(named: item.actionTitle) { if item.hasAction { action() } }
    }
}

/// A row's status bar: checklist steps filled in the group's colour with the count beside it;
/// amber and "paused" while the agent waits for you; a soft sweep when it works without a list.
struct AgentSidebarStatusBar: View {
    let progress: AgentSidebarProgress
    let paused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let tint = SidebarStyle.tint(paused ? .needsYou : .inProgress)
        HStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.08))
                    switch progress {
                    case .steps(let done, let total):
                        Capsule().fill(paused ? tint.dot.opacity(0.75) : tint.dot)
                            .frame(width: max(4, geometry.size.width * CGFloat(done) / CGFloat(max(1, total))))
                            .animation(.easeOut(duration: 0.3), value: done)
                    case .working:
                        if reduceMotion {
                            Capsule().fill(tint.dot.opacity(0.35)).frame(width: geometry.size.width * 0.3)
                        } else {
                            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
                                Capsule().fill(LinearGradient(colors: [tint.dot.opacity(0), tint.dot, tint.dot.opacity(0)], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: geometry.size.width * 0.3)
                                    .offset(x: geometry.size.width * 1.3 * phase - geometry.size.width * 0.3)
                            }
                        }
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 4)
            Text(label).font(.system(size: 10.5, weight: .semibold)).monospacedDigit()
                .foregroundStyle(progress == .working ? SidebarStyle.secondary : tint.text).lineLimit(1).fixedSize()
        }
        .frame(height: 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
    private var label: String {
        switch progress {
        case .steps(let done, let total): "\(done)/\(total)" + (paused ? " · paused" : "")
        case .working: "no checklist"
        }
    }
    private var accessibilityText: String {
        switch progress {
        case .steps(let done, let total): "\(done) of \(total) steps done" + (paused ? ", paused" : "")
        case .working: "Working, no checklist"
        }
    }
}

private struct ReviewActionButton: View {
    let title: String
    let action: () -> Void
    @State private var hovered = false
    @FocusState private var focused: Bool
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) { Text(title); Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold)) }
                .font(.system(size: 12, weight: .medium)).foregroundStyle(SidebarStyle.title)
                .padding(.horizontal, 9).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovered ? Color.black.opacity(0.05) : Color.white))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(focused ? SidebarStyle.accent.opacity(0.8) : Color.black.opacity(0.16), lineWidth: focused ? 2 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(PressedOpacity()).focused($focused)
        .onHover { hovered = $0 }.pointingHand()
        .accessibilityLabel(title)
    }
    private struct PressedOpacity: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View { configuration.label.opacity(configuration.isPressed ? 0.6 : 1) }
    }
}

/// The 24 pt status mark: Generative Loaders' matrix loader while in progress, otherwise an
/// exclamation, check or pause circle in the group's colour.
struct AgentSidebarIcon: View {
    let group: AgentSidebarGroup
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let tint = SidebarStyle.tint(group)
        Group {
            switch group {
            case .inProgress: MatrixLoader(color: NSColor(tint.dot), animate: !reduceMotion).accessibilityLabel("In progress")
            case .needsYou: Image(systemName: "exclamationmark.circle.fill").resizable().foregroundStyle(.white, tint.dot).accessibilityLabel("Needs you")
            case .done: Image(systemName: "checkmark.circle.fill").resizable().foregroundStyle(.white, tint.dot).accessibilityLabel("Done")
            case .idle: Image(systemName: "pause.circle").resizable().foregroundStyle(tint.dot).accessibilityLabel("Idle")
            }
        }
        .frame(width: 24, height: 24)
    }
}

/// Native port of Generative Loaders' MIT-licensed "matrix" InlineLoader (generativeloaders.com):
/// a 5×5 grid of dots, smaller away from the centre, each pulsing (opacity .22→1, scale .48→1,
/// ease-in-out, 1.2 s) with a delay that ripples out from the centre. Still under Reduce Motion.
struct MatrixLoader: NSViewRepresentable {
    let color: NSColor
    let animate: Bool
    func makeNSView(context: Context) -> Grid { Grid(frame: NSRect(x: 0, y: 0, width: 24, height: 24)) }
    func updateNSView(_ view: Grid, context: Context) { view.configure(color: color, animate: animate) }
    final class Grid: NSView {
        private var signature = ""
        private var color = NSColor.systemBlue, animate = true
        override var isFlipped: Bool { true }
        override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override var intrinsicContentSize: NSSize { NSSize(width: 24, height: 24) }
        func configure(color: NSColor, animate: Bool) {
            self.color = color; self.animate = animate
            let next = "\(color)|\(animate)|\(bounds.size)"
            guard next != signature, let layer else { return }
            signature = next
            layer.sublayers?.forEach { $0.removeFromSuperlayer() }
            let size = min(bounds.width, bounds.height) > 0 ? min(bounds.width, bounds.height) : 24
            let inset = size * 0.03, cell = (size - inset * 2) / 5
            let start = CACurrentMediaTime()
            for index in 0..<25 {
                let x = index % 5, y = index / 5
                let distance = Double(abs(x - 2) + abs(y - 2))
                let diameter = cell * CGFloat(0.72 - distance * 0.07)
                let dot = CALayer()
                dot.frame = CGRect(x: inset + CGFloat(x) * cell + (cell - diameter) / 2, y: inset + CGFloat(y) * cell + (cell - diameter) / 2, width: diameter, height: diameter)
                dot.cornerRadius = diameter / 2
                dot.backgroundColor = color.cgColor
                layer.addSublayer(dot)
                guard animate else { dot.opacity = Float(1 - distance * 0.15); continue }
                let delay = distance * -0.13 - Double(index) * 0.008
                func pulse(_ key: String, _ low: Double) -> CAKeyframeAnimation {
                    let animation = CAKeyframeAnimation(keyPath: key)
                    animation.values = [low, 1, low]; animation.keyTimes = [0, 0.48, 1]
                    animation.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeInEaseOut)]
                    animation.duration = 1.2; animation.repeatCount = .infinity; animation.beginTime = start + delay
                    return animation
                }
                dot.add(pulse("opacity", 0.22), forKey: "opacity")
                dot.add(pulse("transform.scale", 0.48), forKey: "scale")
            }
        }
        override func layout() { super.layout(); configure(color: color, animate: animate) }
    }
}
