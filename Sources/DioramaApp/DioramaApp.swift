import SwiftUI
import Observation
import DioramaCore

enum ConversationViewMode: String, CaseIterable {
    case conversation = "Conversation", activity = "Activity", html = "HTML view"
}

@Observable
final class LibraryModel {
    let library = ImportedSessionLibrary()
    let projects: ProjectModel
    let reviews = SessionReviewStore()
    let conversations: DioramaConversationModel
    func appendReviewDraft(_ session: String, text: String) {
        var draft = drafts[session] ?? ConversationDraft()
        draft.text += (draft.text.isEmpty ? "" : "\n\n") + text
        drafts[session] = draft
        if let data = try? JSONEncoder().encode(drafts) { UserDefaults.standard.set(data, forKey: "conversationDrafts") }
    }
    var scrollPositions: [String: String] = UserDefaults.standard.dictionary(forKey: "conversationScrollPositions") as? [String: String] ?? [:]
    var drafts: [String: ConversationDraft] = {
        guard let data = UserDefaults.standard.data(forKey: "conversationDrafts") else { return [:] }
        return (try? JSONDecoder().decode([String: ConversationDraft].self, from: data)) ?? [:]
    }()
    func saveDraft(_ session: String, text: String, attachments: [ConversationAttachment]) {
        var draft = ConversationDraft(); draft.text = text; draft.attachments = attachments.map { $0.url.path }
        drafts[session] = draft
        if let data = try? JSONEncoder().encode(drafts) { UserDefaults.standard.set(data, forKey: "conversationDrafts") }
    }
    var outgoing: [String: OutgoingMessage] = {
        guard let data = UserDefaults.standard.data(forKey: "outgoingMessages"),
              var values = try? JSONDecoder().decode([String: OutgoingMessage].self, from: data) else { return [:] }
        for key in values.keys where values[key]?.state == .pending { values[key]?.state = .uncertain }
        return values
    }()
    var retryOutgoing: [String: () -> Void] = [:]
    func persistOutgoing() {
        if let data = try? JSONEncoder().encode(outgoing) { UserDefaults.standard.set(data, forKey: "outgoingMessages") }
    }
    func reconcileOutgoing(_ sessionID: String) {
        let entries = execution.tasks[sessionID]?.transcript.entries ?? []
        for message in outgoing.values where message.sessionID == sessionID && message.matchingEcho(in: entries) {
            outgoing.removeValue(forKey: message.id); retryOutgoing.removeValue(forKey: message.id)
        }
        persistOutgoing()
    }
    let execution: ExecutionController
    init(execution: ExecutionController? = nil, projects: ProjectModel? = nil, conversations: DioramaConversationModel? = nil) {
        self.execution = execution ?? ExecutionController(transport: AgentExecutionTransport(), journal: ExecutionController.defaultJournal, canvas: ConversationCanvas())
        self.projects = projects ?? ProjectModel()
        self.conversations = conversations ?? DioramaConversationModel()
        restoreConversationMembership()
    }
    var showNewTask = false
    var projectNavigation = false
    var showingLiveTurn: Bool {
        guard let id = selected?.sessionID, let task = execution.tasks[id] else { return false }
        return task.attached && !task.transcript.entries.isEmpty
    }
    var displayedTranscript: Transcript {
        var value = nativeTranscript
        if let selected, let record = conversations.record(selected.id) { value.entries = record.precedingEntries() + value.entries }
        return value
    }
    var nativeTranscript: Transcript {
        var saved = transcriptSessionID == selected?.id ? transcript : Transcript()
        if showingLiveTurn, let id = selected?.sessionID, let task = execution.tasks[id] {
            if task.provider == .claude, let started = task.liveStartedAt {
                let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                saved.entries.removeAll { entry in
                    guard let value = entry.timestamp, let date = parser.date(from: value) ?? ISO8601DateFormatter().date(from: value) else { return false }
                    return date >= started
                }
            }
            saved = saved.mergingLive(task.transcript)
        }
        if let id = selected?.sessionID {
            if outgoing.values.contains(where: { $0.sessionID == id }), let error = saved.error {
                saved.notice = "Saved history unavailable: " + error; saved.error = nil
            }
            for message in outgoing.values.filter({ $0.sessionID == id }).sorted(by: { $0.createdAt < $1.createdAt }) {
                let live = execution.tasks[id]?.transcript.entries ?? []
                let liveIDs = Set(live.map(\.id))
                let acknowledgedInHistory = message.turnID != nil && message.matchingEcho(in: saved.entries)
                if !message.matchingEcho(in: live) && !acknowledgedInHistory {
                    let firstNew = saved.entries.firstIndex { liveIDs.contains($0.id) && !message.baselineIDs.contains($0.id) && $0.kind != "System context" && !$0.id.hasPrefix("outgoing-") }
                    saved.entries.insert(message.entry, at: firstNew ?? saved.entries.endIndex)
                }
            }
        }
        return saved
    }
    func syncOwnedSessions() {
        let existing = Set(sessions.map(\.id))
        sessions += execution.tasks.values.filter { !existing.contains($0.session.id) }.map(\.session)
        restoreConversationMembership()
        sessions = conversations.project(sessions)
        for folder in WorkingFolder.group(sessions) where !folderOrder.contains(folder.id) { folderOrder.append(folder.id) }
    }
    func selectOwned(_ id: String) {
        syncOwnedSessions()
        query = ""; provider = "All"; activityFilter = "All"
        selectedFolderID = execution.tasks[id].flatMap { WorkingFolder.group([$0.session]).first?.id }
        selectedID = conversations.record(id)?.id ?? execution.tasks[id]?.session.id
        viewMode = .conversation
        if projectNavigation, let project = projects.projects.first(where: { $0.workspaces.contains(where: { $0.threadID == id }) }) {
            projects.selectedID = project.id
            projects.update(project.id) { $0.selectedSession = selectedID; $0.section = "Sessions" }
        }
    }
    var sessions: [Session] = []
    var notices: [String] = []
    var selectedID: String?
    var selectedFolderID: String?
    var query = ""
    var pinned = Set(UserDefaults.standard.stringArray(forKey: "pinnedConversations") ?? [])
    var archiveFilter = "All"
    var showMessageSearch = false
    var renameSession: Session?
    var renameText = ""
    var archiveSession: Session?
    var workflowError: String?
    var provider = "All"
    var isScanning = false
    var scannedAt: Date?
    var transcript = Transcript()
    var transcriptSessionID: String?
    var entryLimit = 300
    var showConnections = false
    var paused = false
    let activityLibrary = ActivityLibrary()
    var activity: [String: ActivitySummary] = [:]
    var activityFilter = "All"
    var showInbox = false
    var watcher: DirectoryWatcher?
    var updateTask: Task<Void, Never>?
    var rescanRequested = false
    var viewMode: ConversationViewMode = .conversation
    var folderOrder: [String] = []
    func summary(_ session: Session) -> ActivitySummary {
        if let task = execution.tasks[session.sessionID], task.attached, !task.activity.isEmpty {
            return .merged(task.activity)
        }
        return activity[session.id] ?? ActivitySummary()
    }
    func rows(_ folder: WorkingFolder) -> [SessionRow] {
        SessionPresentation.rows(folder.sessions, showInternal: showInternal).filter { row in
            activityFilter == "All" || (row.session.classification != .internalReview &&
            (activityFilter == "Working" ? isWorking(row.session) : needsAttention(row.session)))
        }
    }
    func isWorking(_ session: Session) -> Bool {
        if let task = execution.tasks[session.sessionID], task.attached { return task.phase == .working || task.phase == .submitting }
        return summary(session).state == .working
    }
    func needsAttention(_ session: Session) -> Bool {
        if execution.tasks[session.sessionID]?.attached == true { return execution.requests.values.contains { $0.threadID == session.sessionID } }
        return !summary(session).attention.isEmpty
    }
    var attentionSessions: [Session] { sessions.filter { $0.classification != .internalReview && needsAttention($0) } }
    var health: String { paused ? "Paused" : (scannedAt == nil || (sessions.isEmpty && !notices.isEmpty) || (!sessions.isEmpty && activity.values.allSatisfy { $0.error != nil })) ? "Unavailable" : "Observing" }
    func counts(_ folder: WorkingFolder) -> String {
        func count(_ subagent: Bool) -> String {
            let records = folder.sessions.filter { $0.classification != .internalReview && ($0.classification == .subagent) == subagent }
            return "\(records.filter { isWorking($0) }.count) working · \(records.filter { needsAttention($0) }.count) attention"
        }
        return "Last reported conversations: " + count(false) + "\nSubagents: " + count(true) + " · current activity unverified"
    }
    func beginWatching() {
        guard watcher == nil else { return }
        // Watch transcripts, not Codex's runtime database/logs: our reader must not
        // trigger another discovery pass through its own App Server housekeeping.
        // A missing root still watches its parent so first-time sessions appear.
        let roots = StorageRoot.defaults().map {
            FileManager.default.fileExists(atPath: $0.url.path) ? $0.url.path : $0.url.deletingLastPathComponent().path
        }
        try? FileManager.default.createDirectory(at: HookStore.base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        watcher = DirectoryWatcher(paths: roots + [HookStore.base.path]) { [weak self] in
            guard let self, !self.paused else { return }
            self.updateTask?.cancel()
            self.updateTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard let self else { return }
                self.updateTask = nil
                await self.refresh(); await self.readSelected()
            }
        }
    }
    func openAttention(_ session: Session) {
        query = ""; provider = "All"; activityFilter = "All"
        selectedFolderID = WorkingFolder.group([session]).first?.id; selectedID = session.id
        viewMode = execution.tasks[session.sessionID]?.attached != true ? .activity : .conversation; showInbox = false
        if projectNavigation, let project = projects.projects.first(where: { projects.sessions($0, library: self).contains(where: { $0.id == session.id }) }) {
            projects.selectedID = project.id; projects.update(project.id) { $0.selectedSession = session.id; $0.section = "Sessions" }
        }
    }
    var showInternal = UserDefaults.standard.bool(forKey: "showInternalSessions") {
        didSet { UserDefaults.standard.set(showInternal, forKey: "showInternalSessions"); reconcileSelection() }
    }

    var filtered: [Session] {
        sessions.filter { (archiveFilter == "All" || (archiveFilter == "Archived" ? $0.archived : !$0.archived)) && (provider == "All" || $0.provider.rawValue == provider) &&
            (query.isEmpty || ($0.title + " " + $0.project + " " + $0.sessionID).localizedCaseInsensitiveContains(query)) }
    }
    var selected: Session? { sessions.first { $0.id == selectedID && (showInternal || $0.classification != .internalReview) } }
    var folders: [WorkingFolder] {
        let ordered = sessions.filter { pinned.contains($0.id) } + sessions.filter { !pinned.contains($0.id) }
        let rank = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element.id, $0.offset) })
        return WorkingFolder.group(filtered).map { folder in
            WorkingFolder(id: folder.id, path: folder.path, sessions: folder.sessions.sorted { rank[$0.id, default: 0] < rank[$1.id, default: 0] })
        }.sorted { folderOrder.firstIndex(of: $0.id) ?? Int.max < folderOrder.firstIndex(of: $1.id) ?? Int.max }
    }
    var selectedFolder: WorkingFolder? { folders.first { $0.id == selectedFolderID } }
    func reconcileSelection() {
        guard !projectNavigation else { return }
        if !folders.contains(where: { $0.id == selectedFolderID }) { selectedFolderID = folders.first?.id }
        selectFolderSession()
    }
    func selectFolderSession() {
        let rows = selectedFolder.map { self.rows($0) } ?? []
        selectedID = SessionPresentation.selection(selectedID, rows: rows)
    }
    func refresh() async {
        guard !isScanning else { rescanRequested = true; return }
        isScanning = true
        let snapshot = await library.scan()
        let activitySnapshot = await activityLibrary.scan(snapshot.sessions)
        if !Task.isCancelled && !paused {
            // Keep existing row order stable as files change; append newly discovered sessions.
            var incoming = Dictionary(uniqueKeysWithValues: snapshot.sessions.map { ($0.id, $0) })
            for task in execution.tasks.values where incoming[task.session.id] == nil { incoming[task.session.id] = task.session }
            let existing = Set(sessions.map(\.id))
            sessions = sessions.compactMap { incoming[$0.id] } + snapshot.sessions.filter { !existing.contains($0.id) }
            syncOwnedSessions()
            for folder in WorkingFolder.group(sessions) where !folderOrder.contains(folder.id) { folderOrder.append(folder.id) }
            activity = activitySnapshot; notices = snapshot.notices; scannedAt = Date()
            reconcileSelection()
        }
        isScanning = false
        if rescanRequested && !paused { rescanRequested = false; await refresh() }
    }
    func readSelected() async {
        guard let session = selected else { transcript = Transcript(); transcriptSessionID = nil; return }
        let result = await library.transcript(for: session, limit: entryLimit)
        guard !Task.isCancelled, selectedID == session.id else { return }
        if transcript != result || transcriptSessionID != session.id { transcript = result; transcriptSessionID = session.id }
    }
}

@main
struct DioramaApp: App {
    @State private var model = LibraryModel()
    @AppStorage("agentOnboardingComplete") private var onboarded = false
    @NSApplicationDelegateAdaptor(DioramaApplicationDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("Diorama") {
            ProjectsRootView(library: model)
                .onAppear { delegate.execution = model.execution; model.syncOwnedSessions() }
                .sheet(isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })) {
                    AgentSettingsView(controller: model.execution, onboarding: true, finish: { onboarded = true })
                }
                .frame(minWidth: 760, minHeight: 600)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1250, height: 820)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New session") { model.showNewTask = true }.keyboardShortcut("n")
                Button("Refresh sessions") { Task { await model.refresh() } }.keyboardShortcut("r")
                ForEach(Array(["Sessions", "Pull Requests", "Files", "Context"].enumerated()), id: \.offset) { index, section in
                    Button(section) { if let id = model.projects.selectedID { model.projects.update(id) { $0.section = section } } }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                }
            }
        }
        Settings { AgentSettingsView(controller: model.execution) }
    }
}

struct LibraryView: View {
    @Bindable var model: LibraryModel
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("DIORAMA", systemImage: "moon.stars").font(.system(.title2, design: .rounded, weight: .semibold))
                    Text("WORKING FOLDERS").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2).foregroundStyle(.secondary)
                    Picker("Provider", selection: $model.provider) {
                        Text("All").tag("All")
                        ForEach(Provider.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                    }.pickerStyle(.segmented).padding(.top, 12)
                }.padding(20)
                Button { model.showInbox = true } label: {
                    Label("Attention inbox · \(model.attentionSessions.count)", systemImage: "tray")
                }.padding(.horizontal, 20).padding(.bottom, 12)
                List(selection: $model.selectedFolderID) {
                    ForEach(model.folders) { folder in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(folder.name, systemImage: "folder").font(.system(size: 13, weight: .medium))
                            Text(folder.path ?? "No absolute folder recorded").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                            Text(SessionPresentation.counts(folder.sessions, showInternal: model.showInternal))
                                .font(.system(size: 10)).foregroundStyle(.tertiary)
                            Text(model.counts(folder)).font(.system(size: 10)).foregroundStyle(.secondary)
                        }.padding(.vertical, 6).tag(folder.id)
                    }
                }.listStyle(.sidebar)
                HStack {
                    if model.isScanning { ProgressView().controlSize(.small) }
                    Text("\(model.folders.count) folders · \(model.filtered.count) sessions").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { model.showConnections = true } label: { Image(systemName: "externaldrive.connected.to.line.below") }.help("Local connections")
                }.padding(16)
            }.navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 400)
            .searchable(text: $model.query, prompt: "Search folders or sessions")
        } content: {
            if let folder = model.selectedFolder {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(folder.name).font(.headline)
                        Text(SessionPresentation.counts(folder.sessions, showInternal: model.showInternal)).font(.caption).foregroundStyle(.secondary)
                        if let path = folder.path {
                            Button("Open folder in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                                .font(.caption)
                        }
                    }.padding(18)
                    Picker("Archive", selection: $model.archiveFilter) { Text("All conversations").tag("All"); Text("Active").tag("Active"); Text("Archived").tag("Archived") }.padding(.horizontal, 18)
                    Picker("Activity", selection: $model.activityFilter) {
                        Text("All").tag("All")
                        Text("Working").tag("Working")
                        Text("Needs attention").tag("Needs attention")
                    }.padding(.horizontal, 18)
                    if model.rows(folder).isEmpty {
                        Text("No conversations match these filters.")
                            .font(.callout).foregroundStyle(.secondary).padding(18)
                    }
                    List(selection: $model.selectedID) {
                        ForEach(model.rows(folder)) { row in
                            let session = row.session
                            VStack(alignment: .leading, spacing: 6) {
                                Text((model.pinned.contains(session.id) ? "📌 " : "") + markdownTitle(session.title)).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                HStack {
                                    Text(session.provider.rawValue)
                                    Text(row.label)
                                    if session.archived { Text("Archived") }
                                }.font(.caption2).foregroundStyle(.secondary)
                                ActivityBadge(summary: model.summary(session), livePhase: model.execution.tasks[session.sessionID]?.attached == true ? model.execution.tasks[session.sessionID]?.phase : nil)
                                Text(session.modified, style: .date).font(.caption2).foregroundStyle(.tertiary)
                            }.padding(.vertical, 6).padding(.leading, CGFloat(min(row.depth, 8)) * 16).tag(session.id)
                                .contextMenu { ConversationActions(model: model, session: session) }
                        }
                    }
                }.navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 400)
            } else {
                ContentUnavailableView("No matching folders", systemImage: "folder", description: Text("Try another search or provider filter."))
            }
        } detail: {
            if let session = model.selected { SessionView(session: session, model: model) }
            else {
                ContentUnavailableView {
                    Label(model.isScanning ? "Discovering sessions" : "Your mission archive", systemImage: "moon.stars")
                } description: {
                    Text("Existing local Codex and Claude Code sessions appear automatically. No sign-in or API calls are needed.")
                } actions: {
                    Button("Check connections") { model.showConnections = true }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Search chats") { model.showMessageSearch = true }
                Button { model.projects.selectedID = nil } label: { Label("New Session", systemImage: "plus") }
                Toggle("Show internal sessions", isOn: $model.showInternal)
                    .help("Include internal approval reviews without changing source records")
                Button { model.paused.toggle() } label: { Label(model.paused ? "Resume updates" : "Pause updates", systemImage: model.paused ? "play" : "pause") }
                    .help("Pause observation only; agents continue working")
                Button { Task { await model.refresh(); await model.readSelected() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }.disabled(model.isScanning)
            }
        }
        .sheet(isPresented: $model.showMessageSearch) { ConversationSearchView(model: model, threadID: nil) }
        .alert("Rename conversation", isPresented: Binding(get: { model.renameSession != nil }, set: { if !$0 { model.renameSession = nil } })) {
            TextField("Name", text: $model.renameText)
            Button("Save") { if let session = model.renameSession { model.renameConversation(session) } }
            Button("Cancel", role: .cancel) { model.renameSession = nil }
        }
        .alert(model.archiveSession?.archived == true ? "Restore conversation?" : "Archive conversation?", isPresented: Binding(get: { model.archiveSession != nil }, set: { if !$0 { model.archiveSession = nil } })) {
            Button("Continue") { if let session = model.archiveSession { model.archiveConversation(session) } }
            Button("Cancel", role: .cancel) { model.archiveSession = nil }
        } message: { Text("This uses Codex's conversation API. Archiving may include spawned descendants; it does not delete working files.") }
        .alert("Conversation action", isPresented: Binding(get: { model.workflowError != nil }, set: { if !$0 { model.workflowError = nil } })) { Button("OK") { model.workflowError = nil } } message: { Text(model.workflowError ?? "") }
        .onChange(of: model.execution.tasks.keys.sorted()) { model.syncOwnedSessions() }
        .sheet(isPresented: $model.showInbox) { AttentionInbox(model: model) }
        .onChange(of: model.activityFilter) { model.selectFolderSession() }
        .onChange(of: model.paused) {
            if !model.paused { Task { await model.refresh(); await model.readSelected() } }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            if !model.paused { Task { await model.refresh(); await model.readSelected() } }
        }
        .sheet(isPresented: $model.showConnections) { ConnectionsView(model: model) }
        .onChange(of: model.selectedFolderID) { model.selectFolderSession() }
        .onChange(of: model.query) { model.reconcileSelection() }
        .onChange(of: model.provider) { model.reconcileSelection() }
        .task {
            model.beginWatching()
            while !Task.isCancelled {
                if !model.paused { await model.refresh() }
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
        .task(id: model.selectedID) {
            model.entryLimit = 300
            while !Task.isCancelled {
                if !model.paused { await model.readSelected() }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
}

struct SessionView: View {
    let session: Session
    @Bindable var model: LibraryModel
    var hasLocalReview = false
    @State private var showDetails = false
    @State private var showChanges = false
    @State private var showFind = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(markdownTitle(session.title)).font(.system(size: 16, weight: .semibold)).lineLimit(2).textSelection(.enabled)
                        Text("\(session.provider.rawValue) · Last reported: \(model.summary(session).state.rawValue) · \(model.health)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if session.provider == .codex {
                        Button("Find") { showFind = true }.keyboardShortcut("f", modifiers: .command)
                        if !hasLocalReview { Button("Review") { showChanges = true } }
                        Menu { ConversationActions(model: model, session: session) } label: { Image(systemName: "ellipsis.circle") }
                    }
                    Button { showDetails.toggle() } label: { Image(systemName: "info.circle") }
                        .buttonStyle(.plain).help("Conversation details").accessibilityLabel("Conversation details")
                        .popover(isPresented: $showDetails) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Conversation details").font(.headline)
                                Text(session.project.isEmpty ? "Working folder unavailable" : session.project)
                                Text(session.classification.rawValue + " · " + session.classificationEvidence)
                                Text("Session ID: " + session.sessionID)
                                if let parent = session.parentID { Text("Recorded parent: " + parent) }
                                Text("Discovery: " + session.historySource)
                                Text("\(model.displayedTranscript.source) · \(model.displayedTranscript.malformed) unrecognized records")
                                Text("Recorded status may be stale. Unified Claude Desktop is not connected.").foregroundStyle(.secondary)
                                if let url = session.url { Button("Reveal transcript") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                            }.font(.caption).textSelection(.enabled).padding(20).frame(width: 380)
                        }
                }
            }.padding(.horizontal, 24).padding(.vertical, 16)
            if model.projectNavigation {
                HStack {
                    Spacer()
                    Picker("Conversation view", selection: $model.viewMode) {
                        ForEach(ConversationViewMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
                    }.pickerStyle(.menu).labelsHidden().fixedSize()
                }.padding(.horizontal, 24).padding(.bottom, 8)
            } else {
            Picker("View", selection: $model.viewMode) {
                ForEach(ConversationViewMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
            }.pickerStyle(.segmented).padding(.horizontal, 26).padding(.bottom, 12)
            }
            if let task = model.execution.tasks[session.sessionID], task.attached {
                if !task.work.plan.isEmpty { ExecutionPlanView(work: task.work).padding(.horizontal, 24).padding(.bottom, 10) }
                if !hasLocalReview && !task.work.diff.isEmpty {
                    Button("Changes · \(task.work.files.count) files · +\(task.work.files.reduce(0) { $0 + $1.additions }) −\(task.work.files.reduce(0) { $0 + $1.deletions })") { showChanges.toggle() }
                        .padding(.horizontal, 24).padding(.bottom, 10)
                }
            }
            Divider()
            if model.viewMode == .html {
                HTMLCanvasView(session: session, livePhase: model.execution.tasks[session.sessionID]?.attached == true ? model.execution.tasks[session.sessionID]?.phase : nil, activities: CanvasActivity.current(model.execution.tasks[session.sessionID]), observedSummary: model.summary(session))
                    .id(session.id)
            } else if model.viewMode == .activity {
                ActivityTimeline(summary: model.summary(session), livePhase: model.execution.tasks[session.sessionID]?.attached == true ? model.execution.tasks[session.sessionID]?.phase : nil)
            } else if model.transcriptSessionID != session.id && !model.showingLiveTurn && !model.outgoing.values.contains(where: { $0.sessionID == session.sessionID }) {
                ProgressView("Reading transcript…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.displayedTranscript.error {
                ContentUnavailableView("Transcript unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if let notice = model.displayedTranscript.notice { Text(notice).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                        if model.displayedTranscript.earlierContentOmitted {
                            HStack {
                                Text("Showing the latest \(model.displayedTranscript.entries.count) entries.").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                if model.entryLimit < 5000 {
                                    Button("Load more") { model.entryLimit = min(5000, model.entryLimit + 500); Task { await model.readSelected() } }
                                }
                            }
                        }
                        if model.displayedTranscript.entries.isEmpty { Text("No supported conversation entries yet.").foregroundStyle(.secondary) }
                        ForEach(model.displayedTranscript.entries) { entry in
                            VStack(alignment: .trailing, spacing: 6) {
                            if entry.kind == "Provider switch" {
                                DisclosureGroup(entry.text.components(separatedBy: "\n").first ?? "Model switched") {
                                    Text(entry.text.components(separatedBy: "\n").dropFirst(2).joined(separator: "\n")).font(.caption).textSelection(.enabled)
                                }.font(.caption).foregroundStyle(.secondary).padding(.vertical, 12)
                            } else {
                            EntryView(entry: entry, selectWorker: { model.openWorker($0) }, progress: model.execution.tasks[session.sessionID]?.toolProgress[entry.tool?.item["id"].string ?? ""])
                                .contextMenu {
                                    if let turn = entry.turnID, session.provider == .codex {
                                        Button("Fork through this turn") { model.forkConversation(session, through: turn) }.disabled(model.execution.tasks[session.sessionID]?.phase.active == true)
                                    }
                                }
                            }
                            if let message = model.outgoing[entry.id] {
                                if message.state == .failed || message.state == .uncertain {
                                    HStack {
                                        Text(message.state == .failed ? "Not sent" : "Delivery unconfirmed · check history before resending").font(.caption).foregroundStyle(.secondary)
                                        if message.state == .failed, let retry = model.retryOutgoing[entry.id] { Button("Retry", action: retry).buttonStyle(.borderless) }
                                    }
                                    if let error = message.error { DisclosureGroup("Details") { Text(error).font(.caption).textSelection(.enabled) } }
                                }
                            }
                            }
                        }
                    }.scrollTargetLayout().padding(24).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
                }.defaultScrollAnchor(.bottom)
                .onChange(of: model.execution.tasks[session.sessionID]?.transcript) { model.reconcileOutgoing(session.sessionID) }
                .scrollPosition(id: Binding(get: { model.scrollPositions[session.id] }, set: { value in
                    if let value, model.scrollPositions[session.id] != value {
                        model.scrollPositions[session.id] = value
                        UserDefaults.standard.set(model.scrollPositions, forKey: "conversationScrollPositions")
                    }
                }))
            }
            Divider()
            ExecutionControls(library: model, session: session).id(session.id)
                .frame(maxWidth: 800).frame(maxWidth: .infinity)

        }
        .sheet(isPresented: $showFind) { ConversationSearchView(model: model, threadID: session.sessionID) }
        .inspector(isPresented: $showChanges) {
            VStack(spacing: 0) {
            ReviewChangesControls(model: model, session: session)
            Divider()
            ExecutionChangesView(work: model.execution.tasks[session.sessionID]?.work ?? ExecutionWork())
            }.inspectorColumnWidth(min: 400, ideal: 580, max: 900)
        }
        .onChange(of: session.id) { showChanges = false }
        .onChange(of: model.showingLiveTurn) { if !model.showingLiveTurn { showChanges = false } }
    }
}

struct EntryView: View {
    let entry: Entry
    var selectWorker: ((String) -> Void)?
    var progress: String?
    @Environment(\.colorScheme) private var colorScheme
    private var isUser: Bool { entry.category == .user }
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 52) }
            VStack(alignment: .leading, spacing: 8) {
                if let image = entry.image {
                    ToolImagePreview(reference: image)
                }
                if let tool = entry.tool {
                    RichToolResultView(result: tool, selectWorker: selectWorker, progress: progress)
                } else if entry.category == .activity || entry.category == .context {
                    DisclosureGroup {
                        TranscriptContent(text: entry.text, literal: entry.kind == "Tool call").padding(.top, 8)
                    } label: {
                        Label(entry.image != nil ? "Image details" : entry.category == .context ? "System context" : markdownTitle(String(entry.text.prefix(100))).replacingOccurrences(of: "\n", with: " "),
                              systemImage: entry.image != nil ? "photo" : entry.category == .context ? "doc.text" : "terminal")
                            .lineLimit(2)
                    }.font(.callout).foregroundStyle(.secondary)
                } else {
                    if !isUser { Text("Assistant").font(.caption.weight(.medium)).foregroundStyle(.secondary) }
                    TranscriptContent(text: entry.text)
                }
            }
            .padding(isUser ? 16 : 4)
            .background(isUser ? Color(red: 0.0, green: 0.36, blue: 0.82) : Color.clear, in: UserMessageBubble())
            .environment(\.colorScheme, isUser ? .dark : colorScheme)
            .help(entry.timestamp ?? entry.kind)
            if isUser == false { Spacer(minLength: 0) }
        }.padding(.vertical, isUser ? 6 : 2)
    }
}

struct ConnectionsView: View {
    @Bindable var model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Text("Local connections").font(.title2.weight(.semibold))
            Text(model.health + " · current activity unverified").font(.caption)
            if let checked = model.scannedAt { Text("Last check: " + checked.formatted()).font(.caption) }
            if let history = model.notices.first(where: { $0.hasPrefix("Codex history:") }) {
                Text(history).font(.callout).textSelection(.enabled)
            }
            Text("Codex execution: " + (model.execution.connected ? "Connected" : "Disconnected")).font(.headline)
            Text("New tasks run directly in your chosen folder. Closing a window keeps work running; quitting requires confirmed interruption of active Diorama tasks. Eligible imported conversations can continue here after the other client releases them.").font(.caption)
            if let error = model.execution.error { Text(error).font(.caption).foregroundStyle(.orange) }
            HookConnections(model: model)
            Text("Diorama reads Codex history through a local App Server with explicit local-file fallbacks. Claude Code and activity use local records. History observation never starts tasks. Execution occurs only through explicit new-task or owned-task controls. App Server may maintain its own runtime metadata.").foregroundStyle(.secondary)
            ForEach(StorageRoot.defaults(), id: \.url) { root in
                VStack(alignment: .leading, spacing: 4) {
                    Text(root.provider.rawValue + (root.archived ? " · Archived" : "")).font(.headline)
                    Text(root.url.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                }
            }
            Divider()
            Text("Unified Claude Desktop: not connected").font(.headline)
            Text("Claude Code history can be read locally. We have not verified a supported feed for the unified Claude desktop experience.").font(.callout).foregroundStyle(.secondary)
            if !model.notices.isEmpty {
                ScrollView { Text(model.notices.joined(separator: "\n")).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 130)
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(28)
        }.frame(width: 680, height: 740)
    }
}
