import AppKit
import SwiftUI
import DioramaCore

struct LiveAgentRosterPanel: View {
    let model: LiveAgentRosterModel
    let agents: [SpatialAgent]
    let active: Bool
    let paused: Bool
    let open: (SpatialFocus) -> Void
    var archive: ((AgentRosterRow) -> Void)? = nil
    var create: (() -> Void)? = nil
    /// Drawn as a dark, see-through card floating over the kitchen, with a collapse control.
    var floating = false
    var collapse: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Agents").font(.headline)
                    Text("\(model.rows.filter { $0.sidebarStatus == .working }.count) working · \(model.rows.filter { $0.sidebarStatus == .blocked }.count) need attention")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let create {
                    Button(action: create) { HStack(spacing: 4) { Text("Create"); Image(systemName: "plus") } }.pointingHand()
                        .buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(floating ? Color.accentColor : .blue)
                        .accessibilityLabel("Create agent")
                }
                if let collapse {
                    Button(action: collapse) { Image(systemName: "minus").font(.system(size: 11, weight: .bold)).frame(width: 18, height: 18) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).pointingHand().help("Collapse (⌘B)").accessibilityLabel("Collapse agents")
                }
            }.padding(.horizontal, floating ? 12 : 6).padding(.vertical, floating ? 10 : 14)
            Divider()
            if model.newActivity {
                Button("New activity ↑") { model.anchor = nil; model.newActivity = false; model.jumpRevision += 1 }.pointingHand()
                    .buttonStyle(.plain).font(.caption.weight(.medium)).foregroundStyle(.blue).padding(8)
            }
            if model.rows.isEmpty {
                ContentUnavailableView("No agents reported", systemImage: "person.2", description: Text("Agents appear as project activity is discovered."))
                    .frame(maxHeight: .infinity)
            } else {
                LiveAgentRosterTable(model: model, animate: active && !paused && !reduced, paused: paused, recentExpanded: false, jumpRevision: model.jumpRevision, open: open, archive: archive, floating: floating)
            }
            if !floating {
                Divider()
                Text(paused ? "Observation paused · last reported state" : "Reported activity · providers may buffer updates")
                    .font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 6).padding(.vertical, 10)
            }
        }
        // Fill the sidebar's full height whatever the row count; the footer stays at the bottom.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(floating ? Color.clear : Color.white).environment(\.colorScheme, floating ? .dark : .light).tint(floating ? nil : .blue)
        .onChange(of: agents, initial: true) { _, value in model.ingest(value) }
        .onChange(of: AgentCompletionViews.shared.revision) { model.ingest(agents) }
        .onChange(of: active, initial: true) { _, value in model.setActive(value) }
        .onDisappear { model.setActive(false) }
    }
}

@Observable final class RosterInteraction { var hovered = false; var focused = false }
private struct LiveAgentRosterCellContent: View {
    let row: AgentRosterRow
    let animate: Bool
    let paused: Bool
    let interaction: RosterInteraction
    private var agent: WorkspaceAgent { row.agent.value }
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            AgentStatusIcon(status: row.sidebarStatus, animate: animate).frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 4) {
                AgentHoverTitle(text: TaskTitle.full(agent.task), active: animate && (interaction.hovered || interaction.focused), size: 13, bold: true)
                    .frame(height: 18)
                metadataText
                    .font(.system(size: 10)).lineLimit(1).frame(height: 16)
                    .help(row.sidebarStatus.label + reason + " - " + providerModel)
                    .accessibilityLabel(row.sidebarStatus.label + reason + " - " + providerModel)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 10))
                    AgentHoverTitle(text: agent.branch ?? "Branch unavailable", active: animate && (interaction.hovered || interaction.focused), size: 10, bold: false, secondary: true)
                        .frame(height: 15)
                        .alignmentGuide(.firstTextBaseline) { _ in 11.5 }
                }.foregroundStyle(.secondary).frame(height: 15)
            }
        }.padding(.horizontal, 6).padding(.vertical, 10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .bottom) { Divider().padding(.leading, 42).padding(.trailing, 6) }
    }
    private var metadataText: some View {
        HStack(spacing: 4) {
            Text(row.sidebarStatus.label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(statusTint)
                .padding(.horizontal, 5)
                .frame(height: 16)
                .background(statusTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(statusTint.opacity(0.18), lineWidth: 0.5) }
                .fixedSize(horizontal: true, vertical: false)
            Text("- " + providerModel).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
    }
    private var statusTint: Color {
        switch row.sidebarStatus {
        case .blocked: Color(nsColor: .systemBrown)
        case .working: Color(nsColor: .systemBlue)
        case .done: Color(nsColor: .systemGreen)
        case .unknown: Color(nsColor: .systemPurple)
        case .idle: Color.secondary
        }
    }
    private var providerModel: String {
        let provider: String
        switch agent.provider {
        case Provider.claude.rawValue: provider = "Anthropic"
        case Provider.codex.rawValue: provider = "OpenAI"
        default: provider = agent.provider.isEmpty ? "Provider unavailable" : agent.provider
        }
        return provider + "/" + (agent.reportedModel ?? "Model unavailable")
    }
    private var reason: String {
        guard row.sidebarStatus == .blocked else { return "" }
        if agent.status == .failed { return " · Turn failed" }
        if agent.status == .stopped { return " · Interrupted" }
        switch agent.attentionReason { case .approval: return " · Needs approval"; case .input: return " · Needs an answer"; case .other: return " · Needs attention" }
    }
}

/// Native virtualization gives fixed row geometry, exact scroll anchors, and stable keyboard
/// selection without laying out all agents or installing a polling/rendering loop.
struct LiveAgentRosterTable: NSViewRepresentable {
    let model: LiveAgentRosterModel
    let animate: Bool
    let paused: Bool
    let recentExpanded: Bool
    let jumpRevision: Int
    let open: (SpatialFocus) -> Void
    var archive: ((AgentRosterRow) -> Void)? = nil
    /// Clear background and dark appearance, for the floating card over the kitchen.
    var floating = false
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = !floating; scroll.backgroundColor = .white
        if floating { scroll.appearance = NSAppearance(named: .darkAqua) }
        let table = RosterTable()
        table.style = .plain
        table.headerView = nil; table.backgroundColor = floating ? .clear : .white
        table.intercellSpacing = .zero; table.rowHeight = Coordinator.rowHeight
        table.selectionHighlightStyle = .regular; table.allowsMultipleSelection = false
        table.addTableColumn(NSTableColumn(identifier: .init("agent")))
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.target = context.coordinator; table.action = #selector(Coordinator.activate)
        table.pressed = { model.setPressed($0) }
        table.setAccessibilityLabel("Project agents, ordered by status then recent activity")
        table.focusChanged = { [weak coordinator = context.coordinator] in coordinator?.updateFocus() }
        table.contextMenuAt = { [weak coordinator = context.coordinator] index in coordinator?.menu(at: index) }
        scroll.documentView = table
        context.coordinator.table = table; context.coordinator.scroll = scroll
        context.coordinator.update(self)
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) { context.coordinator.update(self) }
    static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) { coordinator.saveAnchor(); coordinator.table?.pressed?(false) }

    final class RosterTable: NSTableView {
        var pressed: ((Bool) -> Void)?
        var contextMenuAt: ((Int) -> NSMenu?)?
        var focusChanged: (() -> Void)?
        override func becomeFirstResponder() -> Bool { let result = super.becomeFirstResponder(); focusChanged?(); return result }
        override func resignFirstResponder() -> Bool {
            let result = super.resignFirstResponder()
            for row in 0..<numberOfRows { (view(atColumn: 0, row: row, makeIfNecessary: false) as? Cell)?.interaction.focused = false }
            return result
        }
        override func resetCursorRects() {
            super.resetCursorRects()
            let visible = rows(in: visibleRect)
            guard visible.location != NSNotFound, visible.length > 0 else { return }
            for row in visible.location..<min(numberOfRows, NSMaxRange(visible)) {
                let rect = rect(ofRow: row).intersection(visibleRect)
                if !rect.isEmpty { addCursorRect(rect, cursor: .pointingHand) }
            }
        }
        override func menu(for event: NSEvent) -> NSMenu? { contextMenuAt?(row(at: convert(event.locationInWindow, from: nil))) }
        override func mouseDown(with event: NSEvent) {
            pressed?(true)
            defer { pressed?(false) }
            super.mouseDown(with: event)
        }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36 || event.keyCode == 49 { sendAction(action, to: target); return }
            super.keyDown(with: event)
        }
    }
    final class Cell: NSTableCellView {
        let interaction = RosterInteraction()
        override func updateTrackingAreas() {
            super.updateTrackingAreas(); trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        }
        override func mouseEntered(with event: NSEvent) { interaction.hovered = true }
        override func mouseExited(with event: NSEvent) { interaction.hovered = false }
        var host: NSHostingView<AnyView>?
        var invoke: (() -> Void)?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func accessibilityPerformPress() -> Bool { invoke?(); return true }
        func show(_ content: AnyView, label: String, action: @escaping () -> Void) {
            if let host { host.rootView = content }
            else {
                let host = NSHostingView(rootView: content)
                self.host = host; host.translatesAutoresizingMaskIntoConstraints = false; addSubview(host)
                NSLayoutConstraint.activate([host.leadingAnchor.constraint(equalTo: leadingAnchor), host.trailingAnchor.constraint(equalTo: trailingAnchor), host.topAnchor.constraint(equalTo: topAnchor), host.bottomAnchor.constraint(equalTo: bottomAnchor)])
            }
            invoke = action
            setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel(label)
            host?.setAccessibilityElement(false)
        }
    }
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        static let rowHeight: CGFloat = 78
        static let recentID = "__recent_header__"
        var parent: LiveAgentRosterTable
        weak var table: RosterTable?
        weak var scroll: NSScrollView?
        var ids: [String] = []
        var rows: [String: AgentRosterRow] = [:]
        private var lastJump = 0
        init(_ parent: LiveAgentRosterTable) { self.parent = parent }
        func numberOfRows(in tableView: NSTableView) -> Int { ids.count }
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { Self.rowHeight }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row index: Int) -> NSView? {
            guard ids.indices.contains(index) else { return nil }
            let cell = tableView.makeView(withIdentifier: .init("agent-cell"), owner: self) as? Cell ?? Cell()
            cell.identifier = .init("agent-cell")
            configure(cell, id: ids[index])
            return cell
        }
        func configure(_ cell: Cell, id: String) {
            if let row = rows[id] {
                let value = row.agent.value
                let label = [value.name, TaskTitle.full(value.task), value.branch ?? "Branch unavailable", value.worktree ?? "Worktree unavailable", row.sidebarStatus.label, value.statusLabel, value.reportedModel ?? "Model unavailable", value.parentName.map { "Parent: " + $0 } ?? "", value.latestActivity].filter { !$0.isEmpty }.joined(separator: ". ")
                cell.toolTip = label
                cell.show(AnyView(LiveAgentRosterCellContent(row: row, animate: parent.animate, paused: parent.paused, interaction: cell.interaction).id(row.id)), label: label) { [weak self] in self?.parent.open(row.destination) }
            }
        }
        @objc func activate() {
            guard let table, ids.indices.contains(table.selectedRow) else { return }
            let id = ids[table.selectedRow]
            if let row = rows[id] { parent.open(row.destination) }
        }
        func menu(at index: Int) -> NSMenu? {
            guard ids.indices.contains(index), let row = rows[ids[index]] else { return nil }
            let menu = NSMenu(); menu.autoenablesItems = false
            let supported = row.agent.value.isMain && row.agent.value.provider == Provider.codex.rawValue && parent.archive != nil
            let item = NSMenuItem(title: supported ? "Archive agent…" : (row.agent.value.isMain ? "Archiving is unavailable for this provider" : "Subagents cannot be archived independently"), action: #selector(archiveClicked(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = row.id; item.isEnabled = supported; menu.addItem(item); return menu
        }
        @objc private func archiveClicked(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String, let row = rows[id] else { return }; parent.archive?(row)
        }
        func tableViewSelectionDidChange(_ notification: Notification) { updateFocus() }
        func updateFocus() {
            guard let table else { return }
            for i in ids.indices {
                (table.view(atColumn: 0, row: i, makeIfNecessary: false) as? Cell)?.interaction.focused = table.selectedRow == i && table.window?.firstResponder === table
            }
        }
        func tableView(_ tableView: NSTableView, didRemove rowView: NSTableRowView, forRow row: Int) {
            for cell in rowView.subviews.compactMap({ $0 as? Cell }) { cell.interaction.hovered = false; cell.interaction.focused = false; cell.host?.rootView = AnyView(EmptyView()) }
        }
        func currentAnchor() -> AgentRosterAnchor? {
            guard let table, let scroll, scroll.contentView.bounds.minY > 2 else { return nil }
            let y = scroll.contentView.bounds.minY
            let index = table.row(at: NSPoint(x: 1, y: y + 1))
            guard ids.indices.contains(index) else { return nil }
            return AgentRosterAnchor(id: ids[index], offset: y - table.rect(ofRow: index).minY)
        }
        func saveAnchor() { parent.model.anchor = currentAnchor() }
        func restore(_ anchor: AgentRosterAnchor?) {
            guard let table, let scroll else { return }
            let y = anchor.flatMap { anchor in ids.firstIndex(of: anchor.id).map { table.rect(ofRow: $0).minY + anchor.offset } } ?? 0
            let maximum = max(0, table.bounds.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: min(maximum, max(0, y))))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        func update(_ next: LiveAgentRosterTable) {
            guard let table else { return }
            let oldParent = parent
            let anchor = ids.isEmpty ? next.model.anchor : currentAnchor()
            let selected = ids.indices.contains(table.selectedRow) ? ids[table.selectedRow] : nil
            parent = next
            let previous = rows
            rows = Dictionary(next.model.rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let nextIDs = next.model.rows.map(\.id)
            if ids != nextIDs {
                let previousIDs = ids
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = next.animate && anchor == nil ? 0.25 : 0
                    table.beginUpdates()
                    for index in ids.indices.reversed() where !nextIDs.contains(ids[index]) {
                        ids.remove(at: index); table.removeRows(at: IndexSet(integer: index), withAnimation: context.duration > 0 ? .effectFade : [])
                    }
                    for (index, id) in nextIDs.enumerated() {
                        if let old = ids.firstIndex(of: id) {
                            if old != index { ids.remove(at: old); ids.insert(id, at: index); table.moveRow(at: old, to: index) }
                        } else {
                            ids.insert(id, at: index); table.insertRows(at: IndexSet(integer: index), withAnimation: context.duration > 0 ? .effectFade : [])
                        }
                    }
                    table.endUpdates()
                }
                if let selected, let index = ids.firstIndex(of: selected) { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
                table.layoutSubtreeIfNeeded()
                restore(anchor)
                if let anchor, let index = ids.firstIndex(of: anchor.id), Array(previousIDs.prefix(index + 1)) != Array(ids.prefix(index + 1)) {
                    DispatchQueue.main.async { if next.model.jumpRevision == next.jumpRevision { next.model.newActivity = true } }
                }
            }
            if let anchor, let index = ids.firstIndex(of: anchor.id), ids.prefix(index).contains(where: { previous[$0]?.revision != rows[$0]?.revision }) {
                DispatchQueue.main.async { if next.model.jumpRevision == next.jumpRevision { next.model.newActivity = true } }
            }
            // No reloadData on activity bursts: update only realized, changed cells.
            for (index, id) in ids.enumerated() where previous[id] != rows[id] || oldParent.animate != next.animate || oldParent.paused != next.paused || id == Self.recentID {
                if let cell = table.view(atColumn: 0, row: index, makeIfNecessary: false) as? Cell { configure(cell, id: id) }
            }
            if lastJump != next.jumpRevision { lastJump = next.jumpRevision; restore(nil) }
        }
    }
}
