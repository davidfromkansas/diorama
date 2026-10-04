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
            VStack(spacing: 0) {
                header
                Divider()
                if let selected {
                    InboxThreadDetail(model: model, thread: selected, reply: { reply(selected) }, canReply: canReply(selected), presentation: presentation)
                        .id(selected.id)
                } else {
                    if newUpdates { Button("New updates · Show newest") { Task { await load(reset: true, force: true) } }.pointingHand().padding(8) }
                    list
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red).padding(8); Button("Retry") { Task { await load(reset: true) } }.pointingHand() }
                if let notice = model.notice ?? model.historyNotices[project] { Text(notice).font(.caption2).foregroundStyle(.secondary).lineLimit(2).padding(8) }
            }
            .frame(height: expanded ? height : 0).clipped().opacity(expanded ? 1 : 0)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.black.opacity(expanded ? 0.12 : 0)))
            .shadow(color: .black.opacity(expanded ? 0.12 : 0), radius: 12, y: 4)
            .allowsHitTesting(expanded).accessibilityElement(children: expanded ? .contain : .ignore).accessibilityHidden(!expanded)
            HStack(spacing: 8) {
            Spacer(minLength: 0)
            if let leadingControl { leadingControl }
            Button { if expanded { viewport.capture() }; expanded.toggle() } label: {
                Label("Inbox · \(unread) unread", systemImage: "tray").font(.callout.weight(.medium)).lineLimit(1).minimumScaleFactor(0.65).padding(.horizontal, 14).padding(.vertical, 10)
            }.pointingHand().buttonStyle(.plain).background(.white, in: Capsule()).overlay(Capsule().stroke(.black.opacity(0.12)))
                .accessibilityLabel("Inbox, \(unread) unread threads, \(expanded ? "expanded" : "collapsed")")
        }
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
    private func saveBookmark() {
        viewport.capture()
        var value = presentation?.inboxBookmarks[project] ?? InboxViewBookmark()
        value.filter = filter.rawValue; value.listAnchor = viewport.checkpoint
        presentation?.inboxBookmarks[project] = value
    }
    private var header: some View {
        HStack {
            if selected != nil { Button { selected = nil } label: { Image(systemName: "chevron.left") }.pointingHand().help("Back to inbox") }
            Text("Inbox").font(.headline)
            Spacer()
            if selected == nil {
                Menu { Picker("Show", selection: $filter) { ForEach(InboxFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pointingHand() } label: { Image(systemName: "line.3.horizontal.decrease.circle") }.pointingHand()
                    .menuStyle(.borderlessButton).frame(width: 24).help("Filter inbox")
            }
            Button { viewport.capture(); expanded = false } label: { Image(systemName: "chevron.down") }.pointingHand().help("Collapse inbox")
        }.buttonStyle(.plain).padding(12)
    }
    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    Color.clear.frame(height: 1).id("inbox-top")
                    if rows.isEmpty && !loading {
                        if model.indexing { ProgressView("Loading agent updates…").controlSize(.small).padding(24) }
                        else { Text("No agent updates yet").foregroundStyle(.secondary).padding(24) }
                    }
                    ForEach(rows) { row in
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
                        Divider().padding(.leading, 28)
                    }
                    if loading { ProgressView().controlSize(.small).padding(12) }
                    if next != nil { Button("Load older updates") { Task { await load(reset: false) } }.pointingHand().padding(10) }
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
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(thread.unread ? Color.blue : .clear).frame(width: 6, height: 6).padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(thread.agent).font(.callout.weight(thread.unread ? .semibold : .regular))
                    Spacer(minLength: 4)
                    Text(Self.timestamp(thread.date, received: thread.received)).font(.caption2).foregroundStyle(.secondary)
                        .help(thread.date.formatted(date: .complete, time: .complete))
                }
                Text(TaskTitle.compact(thread.title)).help(TaskTitle.full(thread.title)).accessibilityLabel(TaskTitle.full(thread.title)).font(.callout.weight(thread.unread ? .semibold : .regular)).lineLimit(1)
                Text(thread.excerpt).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if thread.attachments > 0 || thread.outcome != "completed" {
                    HStack {
                        if thread.attachments > 0 { Label("\(thread.attachments)", systemImage: "paperclip") }
                        if thread.outcome != "completed" { Text(thread.outcome.capitalized).foregroundStyle(.orange) }
                    }.font(.caption2)
                }
            }
        }.padding(12).contentShape(Rectangle()).accessibilityElement(children: .combine)
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
                Text(TaskTitle.compact(thread.title)).help(TaskTitle.full(thread.title)).accessibilityLabel(TaskTitle.full(thread.title)).font(.headline).lineLimit(2)
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
            Divider()
            Button(canReply ? "Reply" : "Open conversation", action: reply).pointingHand().buttonStyle(.borderedProminent).padding(10)
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
