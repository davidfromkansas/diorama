import SwiftUI
import DioramaCore

@Observable final class ProjectServersModel {
    var rows: [ProjectLocalServer] = []
    var checked: Date?
    var duration: TimeInterval = 0
    var error: String?
    var scanning = false
    var detectionDetail = ""
    @ObservationIgnored private var pending = false
    @ObservationIgnored private var owners: [String: String] = [:]
    @ObservationIgnored private var portOwners: [Int: String] = [:]
    @ObservationIgnored private var retiredPorts = Set<Int>()
    @ObservationIgnored private var generation = 0
    func invalidate() { generation += 1 }
    func refresh(project: String, roots: [LocalServerRoot], links: [LocalServerLink]) async {
        guard !scanning else { pending = true; return }
        scanning = true
        defer { scanning = false }
        repeat {
            pending = false
            let version = generation
            do {
                let inventory = try await ProjectServerDiscovery.scan()
                guard !Task.isCancelled, version == generation else { return }
                let listening = inventory.processes.filter { !$0.endpoints.isEmpty }
                detectionDetail = "\(listening.count) local listeners · \(listening.filter { !$0.folder.isEmpty }.count) with folder metadata · \(roots.count) project roots"
                let alive = Set(listening.map(\.id))
                // Once a port changes process, old URL evidence cannot authorize opening it.
                for process in listening {
                    for port in process.endpoints.compactMap(ProjectServerDiscovery.port) {
                        if let old = portOwners[port], old != process.id { retiredPorts.insert(port) }
                        portOwners[port] = process.id
                    }
                }
                let validLinks = links.filter { !retiredPorts.contains($0.port) }
                var matches = await Self.match(inventory.processes, roots: roots, links: validLinks)
                for index in matches.indices where matches[index].confirmed { owners[matches[index].id] = matches[index].project }
                for process in listening where !matches.contains(where: { $0.id == process.id && $0.confirmed }) {
                    if let owner = owners[process.id] {
                        matches.removeAll { $0.id == process.id }
                        matches.append(.init(id: process.id, process: process, project: owner, confirmed: true, links: []))
                    }
                }
                owners = owners.filter { alive.contains($0.key) }
                let relevant = matches.filter { $0.project == project }
                let positions = Dictionary(rows.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
                let ordered = relevant.sorted {
                    if $0.confirmed != $1.confirmed { return $0.confirmed }
                    return (positions[$0.id] ?? Int.max, $0.id) < (positions[$1.id] ?? Int.max, $1.id)
                }
                if rows != ordered { rows = ordered }
                checked = inventory.observed; duration = inventory.duration; error = nil
            } catch { if !Task.isCancelled { self.error = "Discovery unavailable · previous results may be stale" } }
        } while pending && !Task.isCancelled
    }
    @concurrent private static func match(_ processes: [LocalServerProcess], roots: [LocalServerRoot], links: [LocalServerLink]) async -> [ProjectLocalServer] {
        ProjectServerDiscovery.match(processes, roots: roots, links: links)
    }
}

/// Observation is contained here so refreshing servers does not rebuild the office scene.
struct ProjectOfficeInbox: View {
    let library: LibraryModel
    let project: String
    let height: CGFloat
    let active: Bool
    @Binding var inboxExpanded: Bool
    @Binding var serversExpanded: Bool
    @Binding var selected: InboxThread?
    var reply: (InboxThread) -> Void
    var canReply: (InboxThread) -> Bool
    /// The kitchen docks the pill top right with the cards below; the office keeps them above.
    var dockedTop = false
    @State private var servers = ProjectServersModel()
    @State private var links: [LocalServerLink] = []
    @State private var roots: [LocalServerRoot] = []
    @State private var trigger = 0
    @State private var history = ProjectServerHistory()
    var body: some View {
        ProjectInboxView(model: library.projectInbox, project: project, height: height,
            expanded: $inboxExpanded, selected: $selected, reply: reply, canReply: canReply,
            leadingControl: AnyView(serversSegment), presentation: library.navigation.projectTabs, dockedTop: dockedTop)
        .overlay(alignment: dockedTop ? .top : .bottom) {
            if serversExpanded { panel.frame(height: height).padding(dockedTop ? .top : .bottom, 50) }
        }
        .environment(\.colorScheme, .light).tint(.blue)
        .onChange(of: inboxExpanded) { _, value in if value { serversExpanded = false } }
        .task(id: "\(project):\(active):\(trigger)") {
            servers.invalidate()
            guard active else { return }
            while !Task.isCancelled {
                await collectEvidence()
                guard !Task.isCancelled else { return }
                await servers.refresh(project: project, roots: roots, links: links)
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
        .onChange(of: library.sessionsRevision) { _, _ in
            guard active else { return }
            Task { let previous = links; await collectEvidence(); if previous != links { trigger += 1 } }
        }
        .onChange(of: liveEvidence) { _, _ in if active { trigger += 1 } }
        .onDisappear { servers.invalidate() }
    }
    private var liveEvidence: [String] {
        library.execution.tasks.values.map { task in
            let text = task.transcript.entries.last?.text ?? ""
            return text.contains("localhost") || text.contains("127.0.0.1") || text.contains("[::1]") ? task.session.id + String(text.suffix(2048)) : ""
        }.filter { !$0.isEmpty }.sorted()
    }
    private var listening: Bool { active && servers.error == nil }
    private var serversSegment: some View {
        let count = servers.rows.filter(\.confirmed).count
        return UtilitySegment(symbol: "server.rack", count: count, label: count == 1 ? "server" : "servers", selected: serversExpanded, action: {
            serversExpanded.toggle()
            if serversExpanded { inboxExpanded = false; trigger += 1 }
        }) {
            UtilityStatusDot(live: listening && count > 0)
        }
        .help(listening ? "Project TCP listeners; availability is not application health" : "Last seen listeners (paused or the scan failed)")
        .accessibilityLabel("Servers, \(count) \(listening ? "listening" : "last seen"), \(active ? "" : "paused, ")\(serversExpanded ? "expanded" : "collapsed")")
    }
    private var panel: some View {
        let confirmed = servers.rows.filter(\.confirmed), possible = servers.rows.filter { !$0.confirmed }
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "server.rack").font(.system(size: 13, weight: .medium)).foregroundStyle(SidebarStyle.title)
                Text("Local servers").font(.system(size: 13, weight: .semibold)).foregroundStyle(SidebarStyle.title)
                Spacer(minLength: 6)
                if servers.scanning { ProgressView().controlSize(.small) }
                UtilityIconButton(symbol: "arrow.clockwise", help: "Refresh servers") { trigger += 1 }.disabled(!active)
            }
            .padding(.leading, SidebarStyle.horizontal).padding(.trailing, 8).frame(height: 44)
            ScrollView {
                LazyVStack(spacing: 0) {
                    if servers.rows.isEmpty {
                        Text(servers.checked == nil ? "Discovering local listeners…" : "No project servers detected")
                            .font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary)
                            .frame(maxWidth: .infinity).padding(.top, 28)
                            .overlay(alignment: .top) { Rectangle().fill(SidebarStyle.divider).frame(height: 1) }
                    }
                    if !confirmed.isEmpty {
                        UtilityCardBand(title: listening ? "Listening" : "Last seen", count: confirmed.count, tint: SidebarStyle.tint(listening ? .done : .idle))
                        ForEach(confirmed) { row in serverRow(row) }
                    }
                    if !possible.isEmpty {
                        UtilityCardBand(title: "Possible matches", count: possible.count, tint: SidebarStyle.tint(.needsYou))
                        ForEach(possible) { row in serverRow(row) }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                if !active { Text("Paused · retained results may be stale") }
                if let error = servers.error { Text(error).foregroundStyle(SidebarStyle.tint(.needsYou).text) }
                Text("Partial detection · local processes this app can see. A listening port doesn’t mean the app is healthy.").help(servers.detectionDetail)
                if let checked = servers.checked { Text("Checked \(checked.formatted(date: .omitted, time: .standard))") }
            }
            .font(.system(size: 11)).foregroundStyle(SidebarStyle.secondary).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SidebarStyle.horizontal).padding(.vertical, 9)
            .background(Color(red: 0.969, green: 0.957, blue: 0.937))
            .overlay(alignment: .top) { Rectangle().fill(SidebarStyle.divider).frame(height: 1) }
        }
        .utilityCard(open: true)
        .overlay(alignment: .topLeading) { SidebarCornerButton(grow: false) { serversExpanded = false }.offset(x: -14, y: -14) }
        .environment(\.colorScheme, .light)
    }
    private func serverRow(_ row: ProjectLocalServer) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if row.confirmed {
                    Image(systemName: "waveform.path").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 24, height: 24).background(Circle().fill(listening ? SidebarStyle.tint(.done).dot : SidebarStyle.tint(.idle).dot))
                } else {
                    Image(systemName: "questionmark").font(.system(size: 11, weight: .bold)).foregroundStyle(SidebarStyle.tint(.needsYou).dot)
                        .frame(width: 24, height: 24).overlay(Circle().strokeBorder(SidebarStyle.tint(.needsYou).dot, lineWidth: 1.8))
                }
            }.padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.process.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(SidebarStyle.title).lineLimit(1)
                if !row.process.folder.isEmpty {
                    Text(row.process.folder).font(.system(size: 11.5)).foregroundStyle(SidebarStyle.secondary).lineLimit(1).truncationMode(.middle)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(row.process.endpoints, id: \.self) { endpoint in
                        HStack(spacing: 6) {
                            Text(endpoint).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(SidebarStyle.title).textSelection(.enabled).lineLimit(1)
                            Spacer(minLength: 4)
                            UtilityIconButton(symbol: "doc.on.doc", help: "Copy address") {
                                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(endpoint, forType: .string)
                            }.frame(width: 24, height: 24)
                        }.frame(height: 24)
                    }
                }.padding(.top, 2)
                ForEach(Array(row.links.enumerated()), id: \.offset) { _, link in
                    VStack(alignment: .leading, spacing: 3) {
                        if !link.title.isEmpty { Text(link.title).font(.system(size: 11.5)).foregroundStyle(SidebarStyle.secondary).lineLimit(1) }
                        ReviewActionButton(title: "Open in browser", symbol: "arrow.up.right") { NSWorkspace.shared.open(link.url) }.help(link.label)
                    }.padding(.top, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, SidebarStyle.horizontal).padding(.top, 11).padding(.bottom, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(SidebarStyle.divider).frame(height: 1) }
    }
    private func collectEvidence() async {
        let projects = library.projects.projects
        let sourceSessions = projects.flatMap { p in library.projects.sessions(p, library: library).flatMap { library.planSources($0) }.map { (p.id, $0) } }
        // Reuse available observations; never attach or resume a session to inspect a URL.
        let sources = sourceSessions.map { owner, session -> (String, String, String, [String]) in
            let snapshot = library.planDiscovery.snapshots[AgentPlanDiscovery.key(session)]
            var text = (snapshot?.records.suffix(200) ?? []).map { $0.detail + "\n" + $0.title }
            text += (library.execution.tasks[session.sessionID]?.transcript.entries.suffix(100) ?? []).filter { $0.kind != "You" }.map(\.text)
            return (owner, session.id, session.title, text)
        }
        let result = await Self.prepare(projects: projects, sources: sources, sessionRoots: sourceSessions.map { ($0.0, $0.1.project) })
        guard !Task.isCancelled else { return }
        var historical: [LocalServerLink] = []
        let local = sourceSessions.filter { $0.0 == project }
        for start in stride(from: 0, to: local.count, by: 2) {
            guard !Task.isCancelled else { return }
            let batch = Array(local[start..<min(start + 2, local.count)])
            let reader = history
            let found = await withTaskGroup(of: [LocalServerLink].self) { group in
                for (owner, session) in batch { group.addTask { await reader.read(session, project: owner) } }
                var values: [LocalServerLink] = []
                for await value in group { values += value }
                return values
            }
            historical += found
        }
        guard !Task.isCancelled else { return }
        var seen = Set<String>()
        roots = result.0
        links = Array((result.1 + historical).filter { seen.insert($0.project + ":" + $0.url.absoluteString).inserted }.prefix(500))
    }
    @concurrent private static func prepare(projects: [DioramaProject], sources: [(String, String, String, [String])], sessionRoots: [(String, String)]) async -> ([LocalServerRoot], [LocalServerLink]) {
        let paths = projects.flatMap { p in ([p.folder] + p.workspaces.filter { !$0.cleaned }.map(\.folder)).map { (p.id, $0) } } + sessionRoots
        let roots = paths.filter { !$0.1.isEmpty }.map { LocalServerRoot(project: $0.0, folder: URL(fileURLWithPath: $0.1).resolvingSymlinksInPath().standardizedFileURL.path) }
        var seen = Set<String>()
        let links = sources.flatMap { project, id, title, texts in texts.flatMap { ProjectServerDiscovery.links(in: $0, project: project, conversation: id, title: title) } }
            .filter { seen.insert($0.project + ":" + $0.url.absoluteString).inserted }.prefix(500)
        return (roots, Array(links))
    }
}
