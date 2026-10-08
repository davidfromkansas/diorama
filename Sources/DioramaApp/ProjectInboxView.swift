import SwiftUI
import DioramaCore

struct ProjectInboxView: View {
    let model: ProjectInboxModel
    let project: String
    let height: CGFloat
    @Binding var expanded: Bool
    @Binding var selected: InboxThread?
    var reply: (InboxThread) -> Void
    var canReply: (InboxThread) -> Bool
    var leadingControl: AnyView? = nil
    var presentation: ProjectTabStore? = nil
    /// In the kitchen the pill docks at the top with the card below it; in the office the card
    /// opens above the pill at the bottom.
    var dockedTop = false
    @State private var rows: [InboxThread] = []
    @State private var next: String?
    @State private var unread = 0
    @State private var loading = false
    @State private var error: String?
    @State private var filter = InboxFilter.inbox
    @State private var atTop = true
    @State private var newUpdates = false
    @State private var viewport = ConversationHistoryViewport()
    @State private var generation = 0
    @State private var refreshAgain = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if dockedTop { pill }
            card
            if !dockedTop { pill }
        }
        .environment(\.colorScheme, .light).environment(\.avatarMessages, true).tint(.blue)
         .task(id: project) {
            let saved = presentation?.inboxBookmarks[project]
            filter = InboxFilter(rawValue: saved?.filter ?? "") ?? .inbox
            viewport.checkpoint = saved?.listAnchor
            rows = []; await load(reset: true)
        }
        .onDisappear { saveBookmark() }
        .onChange(of: model.revision) { Task { await load(reset: true) } }
        .onChange(of: filter) { Task { await load(reset: true, force: true) } }
    }
    private var card: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(SidebarStyle.divider).frame(height: 1)
            if let selected {
                InboxThreadDetail(model: model, thread: selected, reply: { reply(selected) }, canReply: canReply(selected), presentation: presentation)
                    .id(selected.id)
            } else {
                if newUpdates {
                    Button("New updates · Show newest") { Task { await load(reset: true, force: true) } }
                        .buttonStyle(ModalSecondaryButtonStyle(height: 24)).padding(8)
                }
                list
            }
            if let error {
                HStack(spacing: 8) {
                    Text(error).font(.system(size: 11.5)).foregroundStyle(.red).lineLimit(2)
                    Spacer(minLength: 0)
                    Button("Retry") { Task { await load(reset: true) } }.buttonStyle(ModalSecondaryButtonStyle(height: 24))
                }.padding(.horizontal, SidebarStyle.horizontal).padding(.vertical, 8)
            }
            if let notice = model.notice ?? model.historyNotices[project] {
                Text(notice).font(.system(size: 11)).foregroundStyle(SidebarStyle.secondary).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SidebarStyle.horizontal).padding(.vertical, 9)
                    .background(Color(red: 0.969, green: 0.957, blue: 0.937))
                    .overlay(alignment: .top) { Rectangle().fill(SidebarStyle.divider).frame(height: 1) }
            }
        }
        .frame(height: expanded ? height : 0).clipped().opacity(expanded ? 1 : 0)
        .utilityCard(open: expanded)
        // Half off the card's top-left corner, like the agent card's (which sits top right).
        .overlay(alignment: .topLeading) {
            if expanded { SidebarCornerButton(grow: false) { viewport.capture(); expanded = false }.offset(x: -14, y: -14) }
        }
        .allowsHitTesting(expanded).accessibilityElement(children: expanded ? .contain : .ignore).accessibilityHidden(!expanded)
    }
    private var pill: some View {
        UtilityPill {
            if let leadingControl { leadingControl; UtilityPillDivider() }
            UtilitySegment(symbol: "tray", label: "Inbox", selected: expanded, action: { if expanded { viewport.capture() }; expanded.toggle() }) {
                if unread > 0 { UtilityBadge(count: unread) }
            }
            .help(expanded ? "Close inbox" : "Agent updates in this project")
            .accessibilityLabel("Inbox, \(unread) unread threads, \(expanded ? "expanded" : "collapsed")")
        }
    }
    private func saveBookmark() {
        viewport.capture()
        var value = presentation?.inboxBookmarks[project] ?? InboxViewBookmark()
        value.filter = filter.rawValue; value.listAnchor = viewport.checkpoint
        presentation?.inboxBookmarks[project] = value
    }
    private var header: some View {
        HStack(spacing: 6) {
            if selected != nil {
                UtilityIconButton(symbol: "chevron.left", help: "Back to inbox") { selected = nil }
            } else {
                Image(systemName: "tray").font(.system(size: 13, weight: .medium)).foregroundStyle(SidebarStyle.title)
            }
            Text("Inbox").font(.system(size: 13, weight: .semibold)).foregroundStyle(SidebarStyle.title)
            Spacer(minLength: 6)
            if selected == nil {
                UtilitySegmentedPicker(options: InboxFilter.allCases, selection: $filter) { $0.rawValue }
                    .help("Filter inbox").accessibilityLabel("Show")
            }
        }
        .padding(.leading, selected == nil ? SidebarStyle.horizontal : 6).padding(.trailing, 8).padding(.vertical, 8).frame(minHeight: 44)
    }
    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    Color.clear.frame(height: 1).id("inbox-top")
                    if rows.isEmpty && !loading {
                        if model.indexing { ProgressView("Loading agent updates…").controlSize(.small).padding(24) }
                        else { Text("No agent updates yet").font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary).padding(24) }
                    }
                    // The inbox leads with what's unread, like the agent card's groups.
                    let unreadRows = filter == .inbox ? rows.filter(\.unread) : []
                    let otherRows = filter == .inbox ? rows.filter { !$0.unread } : rows
                    if !unreadRows.isEmpty {
                        UtilityCardBand(title: "Unread", count: unread, tint: SidebarStyle.tint(.inProgress))
                        ForEach(unreadRows) { row in rowView(row) }
                        if !otherRows.isEmpty { UtilityCardBand(title: "Earlier", tint: SidebarStyle.tint(.idle)) }
                    }
                    ForEach(otherRows) { row in rowView(row) }
                    if loading { ProgressView().controlSize(.small).padding(12) }
                    if next != nil { Button("Load older updates") { Task { await load(reset: false) } }.buttonStyle(ModalSecondaryButtonStyle(height: 24)).padding(10) }
                }.background(InboxScrollProbe { top, bottom in
                    atTop = top
                    if bottom && next != nil { Task { await load(reset: false) } }
                    if top && newUpdates { Task { await load(reset: true) } }
                })
            }
            .onChange(of: generation) { if let id = viewport.anchorID { proxy.scrollTo(id, anchor: .top); viewport.restore() } else { proxy.scrollTo("inbox-top", anchor: .top) } }
            .onAppear { if let id = viewport.anchorID { proxy.scrollTo(id, anchor: .top); viewport.restore() } }
            .onChange(of: expanded) { _, value in
                if value, let id = viewport.anchorID { proxy.scrollTo(id, anchor: .top); viewport.restore() }
            }
        }
    }
    private func rowView(_ row: InboxThread) -> some View {
        Button {
            viewport.capture()
            selected = row
            Task { await model.act(row.id, .read, through: row.updates.last?.id) }
        } label: { InboxThreadRow(thread: row) }.pointingHand()
        .buttonStyle(.plain)
        .background(ConversationHistoryRowAnchor(id: row.id, viewport: viewport))
        .contextMenu {
            Button("Mark unread") { act(row, .unread) }.pointingHand()
            Button("Archive") { act(row, .archive) }.pointingHand()
            Button("Not a delivery") { act(row, .reject) }.pointingHand()
            if filter != .inbox { Button("Restore") { act(row, .restore) }.pointingHand() }
        }
    }
    private func act(_ row: InboxThread, _ action: InboxAction) { Task { await model.act(row.id, action); await load(reset: true, force: true) } }
    private func load(reset: Bool, force: Bool = false) async {
        guard !loading else { if reset { refreshAgain = true }; return }
        loading = true
        defer {
            loading = false
            if refreshAgain { refreshAgain = false; Task { await load(reset: true) } }
        }
        let identity = project, selectedFilter = filter
        do {
            let page = try await model.store.page(project: identity, filter: selectedFilter, after: reset ? nil : next, around: rows.isEmpty && !force ? viewport.anchorID : nil)
            guard identity == project, selectedFilter == filter, !Task.isCancelled else { return }
            unread = page.unread; error = nil
            // Metadata refresh must update visible labels even while older rows are
            // anchored. Copy only the title; arrivals still follow the existing policy.
            let metadata = try await model.store.summaries(rows.map(\.id) + (selected.map { [$0.id] } ?? []))
            for index in rows.indices {
                if let title = metadata[rows[index].id]?.title, rows[index].title != title { rows[index].title = title }
            }
            if let id = selected?.id, let title = metadata[id]?.title, selected?.title != title { selected?.title = title }
            if reset && !force && !atTop && !rows.isEmpty { newUpdates = true; return }
            let restoring = rows.isEmpty && viewport.anchorID != nil
            if reset {
                if rows != page.rows { rows = page.rows }
                newUpdates = false
                if force { generation += 1 }
            } else {
                let existing = Set(rows.map(\.id))
                viewport.capture()
                rows += page.rows.filter { !existing.contains($0.id) }
                // Keep the currently viewed tail, not every page ever visited.
                if rows.count > 250 { rows.removeFirst(rows.count - 250); newUpdates = true; viewport.restore() }
            }
            next = page.next
            if restoring { generation += 1; atTop = false }
        } catch { self.error = "Could not load inbox: " + error.localizedDescription }
    }
}

struct InboxThreadRow: View {
    let thread: InboxThread
    static func timestamp(_ date: Date, received: Bool, now: Date = Date()) -> String {
        let value = Calendar.current.isDate(date, inSameDayAs: now)
            ? date.formatted(date: .omitted, time: .shortened) : date.formatted(date: .abbreviated, time: .shortened)
        return received ? "Received " + value : value
    }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(String(thread.agent.prefix(1)).uppercased()).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(thread.unread ? SidebarStyle.accent : Color(red: 0.56, green: 0.56, blue: 0.58)))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(thread.agent).font(.system(size: 12, weight: thread.unread ? .semibold : .medium)).foregroundStyle(Color(red: 0.33, green: 0.33, blue: 0.35))
                    Spacer(minLength: 4)
                    Text(Self.timestamp(thread.date, received: thread.received)).font(.system(size: 11)).foregroundStyle(Color(red: 0.56, green: 0.56, blue: 0.58))
                        .help(thread.date.formatted(date: .complete, time: .complete))
                }
                Text(TaskTitle.compact(thread.title)).help(TaskTitle.full(thread.title)).accessibilityLabel(TaskTitle.full(thread.title))
                    .font(.system(size: 13, weight: thread.unread ? .semibold : .regular)).foregroundStyle(SidebarStyle.title).lineLimit(1)
                Text(thread.excerpt).font(.system(size: 11.5)).foregroundStyle(SidebarStyle.secondary).lineLimit(1)
                if thread.attachments > 0 || thread.outcome != "completed" {
                    HStack(spacing: 8) {
                        if thread.attachments > 0 { Label("\(thread.attachments)", systemImage: "paperclip").foregroundStyle(SidebarStyle.secondary) }
                        if thread.outcome != "completed" { Text(thread.outcome.capitalized).foregroundStyle(SidebarStyle.tint(.needsYou).text) }
                    }.font(.system(size: 11)).padding(.top, 1)
                }
            }
        }
        .padding(.horizontal, SidebarStyle.horizontal).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(thread.unread ? Color(red: 0.953, green: 0.969, blue: 1.0) : .clear)
        .overlay(alignment: .leading) { if thread.unread { Rectangle().fill(SidebarStyle.accent).frame(width: 3) } }
        .overlay(alignment: .bottom) { Rectangle().fill(SidebarStyle.divider).frame(height: 1) }
        .contentShape(Rectangle()).accessibilityElement(children: .combine)
            .accessibilityLabel("\(thread.unread ? "Unread, " : "")\(thread.agent), \(thread.title), \(thread.excerpt), \(thread.received ? "Received " : "")\(thread.date.formatted(date: .complete, time: .complete))")
    }
}

private struct InboxThreadDetail: View {
    let model: ProjectInboxModel
    let thread: InboxThread
    let reply: () -> Void
    let canReply: Bool
    var presentation: ProjectTabStore? = nil
    @State private var updates: [InboxUpdate] = []
    @State private var loading = false
    @State private var hasOlder = true
    @State private var follows = true
    @State private var retry = 0
    @State private var suppressRead = false
    @State private var error: String?
    @State private var newUpdates = false
    @State private var preview: ClaudeOutput?
    @State private var viewport = ConversationHistoryViewport()
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(TaskTitle.compact(thread.title)).help(TaskTitle.full(thread.title)).accessibilityLabel(TaskTitle.full(thread.title)).font(.system(size: 15, weight: .semibold)).foregroundStyle(SidebarStyle.title).lineLimit(2)
                Spacer()
                Menu {
                    Button("Mark unread") { suppressRead = true; Task { await model.act(thread.id, .unread) } }.pointingHand()
                    Button("Archive") { Task { await model.act(thread.id, .archive) } }.pointingHand()
                    Button("Not a delivery") { Task { await model.act(thread.id, .reject) } }.pointingHand()
                    Button("Restore") { Task { await model.act(thread.id, .restore) } }.pointingHand()
                } label: { Image(systemName: "ellipsis.circle") }.pointingHand().menuStyle(.borderlessButton).frame(width: 24)
            }.padding(12)
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                if newUpdates { Button("New updates · Show latest") { follows = true; Task { await load(older: false, proxy: proxy) } }.pointingHand().padding(8) }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        Color.clear.frame(height: 1).id("detail-top")
                        if loading { ProgressView().controlSize(.small) }
                        ForEach(updates.reversed()) { update in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(InboxThreadRow.timestamp(update.date, received: update.received)).font(.caption).foregroundStyle(.secondary)
                                if update.outcome != "completed" { Text(update.outcome.capitalized).foregroundStyle(.orange) }
                                if !update.text.isEmpty { TranscriptContent(text: update.text).textSelection(.enabled) }
                                ForEach(update.outputs) { output in
                                    if ConversationImageSource.isImage(output) { ConversationImageView(output: output) }
                                    else { Button { preview = output } label: { Label(output.name, systemImage: "doc") }.pointingHand() }
                                }
                            }.id(update.id).background(ConversationHistoryRowAnchor(id: update.id, viewport: viewport))
                                .background(AgentCompletionVisibility(key: update.id, active: true))
                            Divider()
                        }
                        if hasOlder { Button("Load older updates") { Task { await load(older: true, proxy: proxy) } }.pointingHand() }
                    }.padding(12).background(InboxScrollProbe { top, bottom in
                        follows = top
                        if !top { viewport.cancel() }
                        if bottom && !top && hasOlder && !updates.isEmpty {
                            Task { await load(older: true, proxy: proxy) }
                        }
                    })
                }
                .task(id: retry) { viewport.checkpoint = presentation?.inboxBookmarks[thread.id]?.detailAnchor; await load(older: false, proxy: proxy) }
                .onChange(of: model.revision) { Task { await load(older: false, proxy: proxy) } }
                }
            }
            if let error { HStack { Text(error).font(.caption).foregroundStyle(.red); Button("Retry") { retry += 1 }.pointingHand() }.padding(8) }
            HStack {
                Spacer()
                Button(canReply ? "Reply" : "Open conversation", action: reply).buttonStyle(ModalPrimaryButtonStyle())
            }
            .padding(.horizontal, SidebarStyle.horizontal).padding(.vertical, 10)
            .background(Color(red: 0.969, green: 0.957, blue: 0.937))
            .overlay(alignment: .top) { Rectangle().fill(SidebarStyle.divider).frame(height: 1) }
        }.onDisappear {
            viewport.capture()
            var saved = presentation?.inboxBookmarks[thread.id] ?? InboxViewBookmark()
            saved.detailAnchor = viewport.checkpoint; presentation?.inboxBookmarks[thread.id] = saved
        }.sheet(item: $preview) { ClaudeOutputPreviewView(output: $0).environment(\.colorScheme, .light) }
    }
    private func load(older: Bool, proxy: ScrollViewProxy) async {
        guard !loading else { return }; loading = true; defer { loading = false }
        do {
            for reference in thread.updates { AgentCompletionViews.shared.seed(reference.id, unread: !reference.read, historicalUnread: true) }
            let page = try await model.store.detail(thread.id, before: older ? updates.first?.id : nil, around: updates.isEmpty ? viewport.anchorID : nil)
            guard !Task.isCancelled else { return }
            let initial = updates.isEmpty, following = follows
            if older {
                let anchor = viewport.capture(), existing = Set(updates.map(\.id))
                updates = page.filter { !existing.contains($0.id) } + updates
                if updates.count > 100 { updates.removeLast(updates.count - 100); newUpdates = true }
                hasOlder = page.count == 20
                if let anchor { proxy.scrollTo(anchor, anchor: .top); viewport.restore() }
            } else if initial || following {
                newUpdates = false
                if updates != page { updates = page }
                hasOlder = page.count == 20
                if initial, let anchor = viewport.anchorID { proxy.scrollTo(anchor, anchor: .top); viewport.restore(); follows = false }
                else { proxy.scrollTo("detail-top", anchor: .top) }
                let unread = page.filter { update in thread.updates.first(where: { $0.id == update.id })?.read != true }
                if !suppressRead && !unread.isEmpty { await model.act(thread.id, .read, viewed: Set(unread.map(\.id))) }
            } else if page.last?.id != updates.last?.id { newUpdates = true }
            error = nil
        } catch { self.error = "Could not load updates: " + error.localizedDescription }
    }
}

/// Observes native scroll bounds; publishes only edge changes, never every wheel delta.
private struct InboxScrollProbe: NSViewRepresentable {
    var changed: (Bool, Bool) -> Void
    func makeNSView(context: Context) -> Probe { Probe(changed: changed) }
    func updateNSView(_ view: Probe, context: Context) { view.changed = changed }
    static func dismantleNSView(_ view: Probe, coordinator: ()) { NotificationCenter.default.removeObserver(view) }
    final class Probe: NSView {
        var changed: (Bool, Bool) -> Void
        private var edges: (Bool, Bool)?
        init(changed: @escaping (Bool, Bool) -> Void) { self.changed = changed; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); NotificationCenter.default.removeObserver(self)
            DispatchQueue.main.async { [weak self] in
                guard let self, let scroll = self.enclosingScrollView else { return }
                scroll.contentView.postsBoundsChangedNotifications = true
                NotificationCenter.default.addObserver(self, selector: #selector(self.moved), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
            }
        }
        @objc private func moved() {
            guard let scroll = enclosingScrollView, let document = scroll.documentView else { return }
            let top = scroll.contentView.bounds.minY <= 20
            let bottom = document.bounds.height - scroll.contentView.bounds.maxY < 120
            guard edges?.0 != top || edges?.1 != bottom else { return }
            edges = (top, bottom)
            DispatchQueue.main.async { [weak self] in self?.changed(top, bottom) }
        }
    }
}
