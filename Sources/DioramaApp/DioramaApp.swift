import SwiftUI
import Observation
import DioramaCore

enum ConversationViewMode: String, CaseIterable {
    case workspace = "Workspace", conversation = "Conversation", activity = "Activity", html = "HTML view"
}

@Observable
final class LibraryModel {
    /// Only the service owner installs provider callbacks and runs discovery. Window facades
    /// share its data but own navigation, transcript selection and presentation lifetimes.
    @ObservationIgnored let sharedOwner: LibraryModel?
    @ObservationIgnored private var servicesTask: Task<Void, Never>?
    @ObservationIgnored private var portfolioTask: Task<Void, Never>?
    @ObservationIgnored private var windowCount = 0
    @ObservationIgnored var windowModels: [WeakLibraryWindow] = []
    func makeWindowModel() -> LibraryModel {
        windowCount += 1
        let window = LibraryModel(navigation: WorkspaceNavigation(namespace: "window.\(windowCount)"), sharedOwner: self)
        windowModels.append(WeakLibraryWindow(window))
        startServices()
        return window
    }
    func startServices() {
        guard sharedOwner == nil, servicesTask == nil else { return }
        beginWatching()
        servicesTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !paused { await refresh(); await projects.associate(sessions) }
                try? await Task.sleep(for: .seconds(15))
            }
        }
        portfolioTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if NSApp.isActive && !paused { await portfolio.refresh(self) }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    func flushWindowPresentation() {
        flushDrafts()
        for item in windowModels { item.value?.captureProjectPresentation(); item.value?.navigation.flushPersistence() }
        navigation.flushPersistence()
    }

    let library: ImportedSessionLibrary
    let localDiscovery: SessionLibrary
    let projects: ProjectModel
    let reviews: SessionReviewStore
    let navigation: WorkspaceNavigation
    let spatial = SpatialWorkspaceState()
    let projectInbox: ProjectInboxModel
    @ObservationIgnored let workspaceProjectionCache = WorkspaceProjectionCache()
    @ObservationIgnored let agentNames: AgentDisplayNameModel
    @ObservationIgnored let planDiscovery: AgentPlanDiscovery
    var portfolio: PortfolioStore
    var activityPanels: [String: ActivityPanelState] = [:]
    let conversations: DioramaConversationModel
    /// Skills armed from the kitchen's command bar, by conversation, until its composer picks
    /// them up for the next message.
    var armedCapabilities: [String: [CapabilityInput]] = [:]
    func arm(_ capability: CapabilityInput, for conversation: String) {
        var list = armedCapabilities[conversation] ?? []
        guard !list.contains(where: { $0.id == capability.id }) else { return }
        list.append(capability); armedCapabilities[conversation] = list
    }
    var drafts: [String: ConversationDraft] {
        get { sharedOwner?.drafts ?? ownedDrafts }
        set { if let sharedOwner { sharedOwner.drafts = newValue } else { ownedDrafts = newValue } }
    }
    var outgoing: [String: OutgoingMessage] {
        get { sharedOwner?.outgoing ?? ownedOutgoing }
        set { if let sharedOwner { sharedOwner.outgoing = newValue } else { ownedOutgoing = newValue } }
    }
    var retryOutgoing: [String: () -> Void] {
        get { sharedOwner?.retryOutgoing ?? ownedRetryOutgoing }
        set { if let sharedOwner { sharedOwner.retryOutgoing = newValue } else { ownedRetryOutgoing = newValue } }
    }
    var sessions: [Session] {
        get { sharedOwner?.sessions ?? ownedSessions }
        set { if let sharedOwner { sharedOwner.sessions = newValue } else { ownedSessions = newValue } }
    }
    var notices: [String] {
        get { sharedOwner?.notices ?? ownedNotices }
        set { if let sharedOwner { sharedOwner.notices = newValue } else { ownedNotices = newValue } }
    }
    var pinned: Set<String> {
        get { sharedOwner?.pinned ?? ownedPinned }
        set { if let sharedOwner { sharedOwner.pinned = newValue } else { ownedPinned = newValue } }
    }
    var isScanning: Bool {
        get { sharedOwner?.isScanning ?? ownedIsScanning }
        set { if let sharedOwner { sharedOwner.isScanning = newValue } else { ownedIsScanning = newValue } }
    }
    var scannedAt: Date? {
        get { sharedOwner?.scannedAt ?? ownedScannedAt }
        set { if let sharedOwner { sharedOwner.scannedAt = newValue } else { ownedScannedAt = newValue } }
    }
    var observations: [String: ExternalObservationSnapshot] {
        get { sharedOwner?.observations ?? ownedObservations }
        set { if let sharedOwner { sharedOwner.observations = newValue } else { ownedObservations = newValue } }
    }
    var observationClock: Date {
        get { sharedOwner?.observationClock ?? ownedObservationClock }
        set { if let sharedOwner { sharedOwner.observationClock = newValue } else { ownedObservationClock = newValue } }
    }
    var activity: [String: ActivitySummary] {
        get { sharedOwner?.activity ?? ownedActivity }
        set { if let sharedOwner { sharedOwner.activity = newValue } else { ownedActivity = newValue } }
    }
    var folderOrder: [String] {
        get { sharedOwner?.folderOrder ?? ownedFolderOrder }
        set { if let sharedOwner { sharedOwner.folderOrder = newValue } else { ownedFolderOrder = newValue } }
    }
    func appendReviewDraft(_ session: String, text: String) {
        var draft = drafts[session] ?? ConversationDraft()
        draft.text += (draft.text.isEmpty ? "" : "\n\n") + text
        drafts[session] = draft
        if let data = try? JSONEncoder().encode(drafts) { UserDefaults.standard.set(data, forKey: "conversationDrafts") }
    }
    var historyRevealTargets: [String: String] = [:]
    var scrollPositions: [String: String] = UserDefaults.standard.dictionary(forKey: "conversationScrollPositions") as? [String: String] ?? [:]
    private var ownedDrafts: [String: ConversationDraft] = [:]
    @ObservationIgnored private let draftPersistence: ConversationDraftPersistence
    func flushDrafts() { draftPersistence.flush() }
    func saveDraft(_ session: String, text: String, attachments: [ConversationAttachment], mode: String? = nil) {
        var draft = drafts[session] ?? ConversationDraft();
        if let mode { draft.mode = mode }
         draft.text = text; draft.attachments = attachments.map { $0.url.path }
        drafts[session] = draft
        draftPersistence.schedule(drafts)
    }
    private var ownedOutgoing: [String: OutgoingMessage] = {
        guard let data = UserDefaults.standard.data(forKey: "outgoingMessages"),
              var values = try? JSONDecoder().decode([String: OutgoingMessage].self, from: data) else { return [:] }
        for key in values.keys where values[key]?.state == .pending { values[key]?.state = .uncertain }
        return values
    }()
    private var ownedRetryOutgoing: [String: () -> Void] = [:]
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
    var developmentReload: DevelopmentReload?
    let execution: ExecutionController
    let observationHookDirectory: URL?
    init(execution: ExecutionController? = nil, projects: ProjectModel? = nil, conversations: DioramaConversationModel? = nil, navigation: WorkspaceNavigation? = nil, observationHookDirectory: URL? = HookStore.directory, sharedOwner: LibraryModel? = nil, draftDefaults: UserDefaults = .standard) {
        _ = AgentCompletionViews.shared
        self.sharedOwner = sharedOwner
        self.draftPersistence = sharedOwner?.draftPersistence ?? ConversationDraftPersistence(defaults: draftDefaults)
        self.ownedDrafts = sharedOwner == nil ? draftPersistence.load() : [:]
        self.library = sharedOwner?.library ?? ImportedSessionLibrary(titleCacheURL: ProjectStorage.directory.appendingPathComponent("provider-task-titles.json"))
        self.localDiscovery = sharedOwner?.localDiscovery ?? SessionLibrary()
        self.reviews = sharedOwner?.reviews ?? SessionReviewStore()
        self.projectInbox = sharedOwner?.projectInbox ?? ProjectInboxModel()
        self.agentNames = sharedOwner?.agentNames ?? AgentDisplayNameModel()
        self.planDiscovery = sharedOwner?.planDiscovery ?? AgentPlanDiscovery()
        self.portfolio = sharedOwner?.portfolio ?? PortfolioStore()
        self.externalObserver = sharedOwner?.externalObserver ?? ExternalSessionObserver()
        self.activityLibrary = sharedOwner?.activityLibrary ?? ActivityLibrary()
        self.observationHookDirectory = observationHookDirectory
        self.navigation = navigation ?? WorkspaceNavigation()
        self.execution = sharedOwner?.execution ?? execution ?? ExecutionController(transport: AgentExecutionTransport(), journal: ExecutionController.defaultJournal)
        self.projects = sharedOwner.map { ProjectModel(sharing: $0.projects) } ?? projects ?? ProjectModel()
        self.conversations = sharedOwner?.conversations ?? conversations ?? DioramaConversationModel()
        guard sharedOwner == nil else { return }
        restoreConversationMembership()
        // Chef name tags get four-word task labels from the agent's own provider.
        TaskLabels.shared.generator = { [weak execution = self.execution] task, latest, provider in await execution?.taskLabel(task, latest: latest, provider: provider) }
        self.execution.titleEvent = { [weak self] id, provider, name in
            guard let self else { return }
            for index in self.sessions.indices where self.sessions[index].sessionID == id && self.sessions[index].provider == provider {
                self.sessions[index] = self.sessions[index].updated(title: name)
                self.sessions[index].titleSource = .provider
            }
            self.refreshProjectInbox()
        }
        self.execution.inboxEvent = { [weak self] session, event, entries in
            guard let self else { return }
            for source in self.inboxSources() where source.session.provider == session.provider && source.session.sessionID == session.sessionID {
                self.projectInbox.live(source, event: event, entries: entries)
            }
        }
    }
    var windowIsActive = true
    var showNewTask = false
    var projectNavigation = false
    var showingLiveTurn: Bool {
        guard selected?.observationOnly != true, let id = selected?.sessionID, let task = execution.tasks[id] else { return false }
        return task.attached && !task.transcript.entries.isEmpty
    }
    var displayedTranscript: Transcript {
        var value = nativeTranscript
        if let selected, let record = conversations.record(selected.id) { value.entries = record.precedingEntries() + value.entries }
        return value
    }
    var nativeTranscript: Transcript {
        let session = selected
        let savedHistory = transcriptSessionID == session?.id ? transcript : Transcript()
        let task = session.flatMap { execution.tasks[$0.sessionID] }
        let useLive = session?.observationOnly != true && task?.attached == true && task?.transcript.entries.isEmpty == false
        var saved = conversationPresentation.merger(for: session?.id ?? "").merged(
            saved: savedHistory,
            live: useLive ? task?.transcript : nil,
            claudeCutoff: useLive && task?.provider == .claude ? task?.liveStartedAt : nil)
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
        let conversation = conversations.record(id)?.id ?? execution.tasks[id]?.session.id
        if let project = projects.projects.first(where: { $0.workspaces.contains(where: { $0.threadID == id }) }) {
            navigate(.project(project.id, conversation))
        } else if let session = sessions.first(where: { $0.id == conversation }) { openInWorkspace(session) }
        else { navigate(.imported(conversation)) }
    }
    private var ownedSessions: [Session] = [] { didSet { if ownedSessions != oldValue { ownedSessionsRevision &+= 1 } } }
    private var ownedSessionsRevision: UInt64 = 0
    var sessionsRevision: UInt64 { sharedOwner?.sessionsRevision ?? ownedSessionsRevision }
    private var ownedNotices: [String] = []
    @ObservationIgnored let conversationPresentation = ConversationPresentationCache()
    var selectedID: String? {
        didSet {
            guard selectedID != oldValue else { return }
            if let id = transcriptSessionID { conversationPresentation.save(transcript, for: id) }
            if let id = selectedID, let saved = conversationPresentation.transcript(for: id) {
                transcript = saved; transcriptSessionID = id
            } else {
                transcript = Transcript(); transcriptSessionID = nil
            }
        }
    }
    var selectedFolderID: String?
    var query = ""
    private var ownedPinned = Set(UserDefaults.standard.stringArray(forKey: "pinnedConversations") ?? [])
    var archiveFilter = "All"
    var showMessageSearch = false
    var renameSession: Session?
    var renameText = ""
    var archiveSession: Session?
    var workflowError: String?
    var provider = "All"
    private var ownedIsScanning = false
    private var ownedScannedAt: Date?
    var transcript = Transcript()
    var transcriptSessionID: String?
    var readingTranscriptID: String?
    func historyIsLoading(_ session: Session) -> Bool {
        guard !paused else { return false }
        return transcriptSessionID != session.id ||
            ((transcript.entries.isEmpty || transcript.error != nil) && readingTranscriptID == session.id)
    }
    var entryLimit = 300
    var showConnections = false
    var paused: Bool {
        get { sharedOwner?.paused ?? ownedPaused }
        set { if let sharedOwner { sharedOwner.paused = newValue } else { ownedPaused = newValue } }
    }
    private var ownedPaused = false {
        didSet {
            if paused { watcher = nil; updateTask?.cancel(); updateTask = nil }
            else { beginWatching() }
        }
    }
    let externalObserver: ExternalSessionObserver
    private var ownedObservations: [String: ExternalObservationSnapshot] = [:]
    private var ownedObservationClock = Date()
    private var readingSelection = false
    private var selectionReadRequested = false
    let activityLibrary: ActivityLibrary
    private var ownedActivity: [String: ActivitySummary] = [:]
    var activityFilter = "All"
    var showInbox = false
    var watcher: DirectoryWatcher?
    var updateTask: Task<Void, Never>?
    var rescanRequested = false
    private var changedObservationPaths: Set<String> = []
    var viewMode: ConversationViewMode = .workspace
    private var ownedFolderOrder: [String] = []
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
    static func affectsSelectedHistory(paths: [String], incoming: [Session], selected: Session?) -> Bool {
        guard let selected else { return false }
        if incoming.contains(where: { $0.provider == selected.provider && ($0.sessionID == selected.sessionID || $0.parentID == selected.sessionID) }) { return true }
        return paths.contains { path in
            // Directory-level events and hooks may not carry a transcript identity.
            path == selected.url?.path || path.hasPrefix(HookStore.base.path + "/") ||
                !["json", "jsonl"].contains(URL(fileURLWithPath: path).pathExtension)
        }
    }

    func beginWatching() {
        guard sharedOwner == nil else { return }
        guard watcher == nil else { return }
        // Watch transcripts, not Codex's runtime database/logs: our reader must not
        // trigger another discovery pass through its own App Server housekeeping.
        // A missing root still watches its parent so first-time sessions appear.
        let roots = (StorageRoot.defaults().map(\.url) + [ClaudeDesktopPaths.defaults.metadata]).map {
            FileManager.default.fileExists(atPath: $0.path) ? $0.path : $0.deletingLastPathComponent().path
        }
        try? FileManager.default.createDirectory(at: HookStore.base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        watcher = DirectoryWatcher(paths: roots + [HookStore.base.path], changed: { [weak self] paths in
            guard let self, !self.paused else { return }
            self.changedObservationPaths.formUnion(paths.prefix(max(0, 256 - self.changedObservationPaths.count)))
            guard self.updateTask == nil else { return }
            self.updateTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                guard let self else { return }
                defer { if !Task.isCancelled { self.updateTask = nil } }
                repeat {
                let paths = Array(self.changedObservationPaths)
                self.changedObservationPaths.removeAll()
                async let changed = SessionLibrary.changedSessions(paths: paths)
                let incomingSessions = await changed
                self.portfolio.register(incomingSessions)
                guard !self.paused, !Task.isCancelled else { return }
                for incoming in incomingSessions {
                    if let index = self.sessions.firstIndex(where: { $0.id == incoming.id }) {
                        // Full reconciliation owns Desktop classification and richer API metadata.
                        self.sessions[index] = incoming.retainingDiscoveryMetadata(from: self.sessions[index])
                    } else { self.sessions.append(incoming) }
                }
                self.refreshProjectInbox()
                // The periodic pass reconciles metadata-only changes and archives.
                if paths.contains(where: { $0.hasSuffix(".json") }) { Task { await self.refresh() } }
                // Visible windows refresh their selected history; discovery never hydrates hidden views.
                } while !self.changedObservationPaths.isEmpty && !self.paused && !Task.isCancelled
            }
        })
    }
    func openAttention(_ session: Session) {
        query = ""; provider = "All"; activityFilter = "All"
        selectedFolderID = WorkingFolder.group([session]).first?.id; selectedID = session.id
        let attentionMode: ConversationViewMode = execution.tasks[session.sessionID]?.attached != true ? .activity : .conversation
        showInbox = false
        openInWorkspace(session)
        viewMode = attentionMode
        if let project = projects.selected {
            navigation.tabs[project.id + ":" + session.id] = viewMode == .activity ? .activity : .conversation
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
        if let sharedOwner { await sharedOwner.refresh(); return }
        guard !isScanning else { rescanRequested = true; return }
        isScanning = true
        let scanStarted = Date()
        async let richDiscovery = library.scan()
        let local = await localDiscovery.scan()
        portfolio.register(local.sessions)
        if !Task.isCancelled && !paused {
            execution.observeDesktopSessions(local.sessions)
            var indices = Dictionary(uniqueKeysWithValues: sessions.enumerated().map { ($0.element.id, $0.offset) })
            for incoming in local.sessions {
                if let index = indices[incoming.id] {
                    if incoming.modified > sessions[index].modified { sessions[index] = incoming.retainingDiscoveryMetadata(from: sessions[index]) }
                } else {
                    indices[incoming.id] = sessions.count; sessions.append(incoming)
                }
            }
            scannedAt = Date()
            reconcileSelection()
        }
        let snapshot = await richDiscovery
        portfolio.register(snapshot.sessions)
        let activitySnapshot = await activityLibrary.scan(snapshot.sessions)
        if !Task.isCancelled && !paused {
            // Keep existing row order stable as files change; append newly discovered sessions.
            var incoming = Dictionary(uniqueKeysWithValues: snapshot.sessions.map { ($0.id, $0) })
            for session in sessions where session.modified > scanStarted { incoming[session.id] = session }
            for task in execution.tasks.values where incoming[task.session.id] == nil { incoming[task.session.id] = task.session }
            let existing = Set(sessions.map(\.id))
            sessions = sessions.compactMap { old in incoming[old.id].map { $0.retainingTitle(from: old) } } + snapshot.sessions.filter { !existing.contains($0.id) }
            syncOwnedSessions()
            for folder in WorkingFolder.group(sessions) where !folderOrder.contains(folder.id) { folderOrder.append(folder.id) }
            execution.observeDesktopSessions(snapshot.sessions)
            activity = activitySnapshot
            for (id, observation) in observations where observation.synchronizedAt > scanStarted { activity[id] = observation.activity }
            notices = snapshot.notices; scannedAt = Date()
            reconcileSelection()
        }
        refreshProjectInbox()
        isScanning = false
        if rescanRequested && !paused { rescanRequested = false; await refresh() }
    }
    func readSelected() async {
        guard !paused else { return }
        guard !readingSelection else { selectionReadRequested = true; return }
        readingSelection = true
        repeat {
            selectionReadRequested = false
            await readCurrentSelection()
        } while selectionReadRequested && !paused && !Task.isCancelled
        readingSelection = false
    }

    private func readCurrentSelection() async {
        guard let session = selected else { transcript = Transcript(); transcriptSessionID = nil; return }
        let selectionGeneration = navigation.projectTabs.generation
        readingTranscriptID = session.id
        defer { if readingTranscriptID == session.id { readingTranscriptID = nil } }
        observationClock = Date()
        if session.url != nil && execution.tasks[session.sessionID]?.attached != true {
            var observation = await externalObserver.read(session, limit: entryLimit, hookDirectory: observationHookDirectory)
            var parents = Set([session.sessionID])
            var descendants: [Session] = []
            var seen = Set([session.id])
            for _ in 0..<8 {
                let next = sessions.filter { $0.provider == session.provider && $0.parentID.map(parents.contains) == true && !seen.contains($0.id) }
                guard !next.isEmpty else { break }
                descendants += next; parents.formUnion(next.map(\.sessionID)); seen.formUnion(next.map(\.id))
            }
            // Publish the selected conversation before child I/O, then return all
            // child observations in one actor hop rather than twenty UI round trips.
            guard !paused, selectedID == session.id, navigation.projectTabs.generation == selectionGeneration, !Task.isCancelled else { return }
            if observation.error == nil,
               transcript != observation.transcript || transcriptSessionID != session.id {
                transcript = observation.transcript; transcriptSessionID = session.id
            }
            let observedChildren = await externalObserver.readChildren(Array(descendants.prefix(20)), hookDirectory: observationHookDirectory)
            for child in descendants.prefix(20) {
                if let childObservation = observedChildren[child.id] {
                    observation.structured.apply(childObservation.agentRecord(child, parent: session))
                }
            }
            guard !paused, !Task.isCancelled, selectedID == session.id, navigation.projectTabs.generation == selectionGeneration else { return }
            var updatedObservations = observations.merging(observedChildren) { _, latest in latest }
            updatedObservations[session.id] = observation
            if updatedObservations.count > 24 {
                let retained = Set(descendants.prefix(20).map(\.id) + [session.id])
                updatedObservations = updatedObservations.filter { retained.contains($0.key) }
            }
            observations = updatedObservations
            activity[session.id] = observation.activity
            if observation.error == nil {
                if transcript != observation.transcript || transcriptSessionID != session.id {
                    transcript = observation.transcript; transcriptSessionID = session.id
                }
            } else if transcriptSessionID != session.id {
                transcript = observation.transcript; transcript.error = observation.error; transcriptSessionID = session.id
            }
            execution.observeActivity(session, snapshot: observation.structured)
        } else {
            let result = await library.transcript(for: session, limit: entryLimit)
            guard !paused, !Task.isCancelled, selectedID == session.id, navigation.projectTabs.generation == selectionGeneration else { return }
            if transcript != result || transcriptSessionID != session.id { transcript = result; transcriptSessionID = session.id }
            await execution.importActivity(session, transcript: result)
        }
    }

}

final class WeakLibraryWindow {
    weak var value: LibraryModel?
    init(_ value: LibraryModel) { self.value = value }
}

@main
struct DioramaApp: App {
    @State private var model = LibraryModel()
    @State private var updates = AppUpdateCoordinator()
    @AppStorage("agentOnboardingComplete") private var onboarded = false
    @NSApplicationDelegateAdaptor(DioramaApplicationDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("Diorama") {
            if CommandLine.arguments.contains("--inbox-benchmark") {
                SceneBenchmarkView(withInbox: true)
            } else if CommandLine.arguments.contains("--scene-benchmark") || Bundle.main.object(forInfoDictionaryKey: "DioramaSceneBenchmark") as? Bool == true {
                SceneBenchmarkView()
            } else if CommandLine.arguments.contains("--capybara-lab") || Bundle.main.object(forInfoDictionaryKey: "DioramaMovementLab") as? Bool == true {
                WorkspaceSceneView(startInMovementLab: true)
                    .frame(minWidth: 760, minHeight: 600).preferredColorScheme(.dark)
            } else {
            DesktopWindow(services: model, updates: updates)
                .onAppear {
                    delegate.execution = model.execution
                    delegate.updates = updates
                    updates.configure(library: model)
                    if model.developmentReload == nil { model.developmentReload = DevelopmentReload.configured(library: model) }
                    delegate.developmentReload = model.developmentReload
                    model.syncOwnedSessions()
                }
                // Pull requests: CI, conflicts and merges move the chefs; finished fixes get pushed.
                .task { await PRWatcher.shared.run(library: model) }
                .sheet(isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })) {
                    AgentSettingsView(controller: model.execution, onboarding: true, finish: { onboarded = true })
                }
                .frame(minWidth: 760, minHeight: 600)
            }
        }
        .defaultSize(width: 1320, height: 850)
        .windowStyle(.hiddenTitleBar)
        .commands {
            DesktopCommands()
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updates.check() }
                if updates.isDevelopment {
                    Menu("Preview update notification") {
                        Button("Available") { updates.showPreview(.available) }
                        Button("Downloading") { updates.showPreview(.downloading) }
                        Button("Ready to restart") { updates.showPreview(.ready) }
                        Button("Download failed") { updates.showPreview(.failed) }
                    }
                }
            }
            CommandGroup(after: .newItem) {
                Button("Refresh sessions") { Task { await model.refresh() } }.pointingHand().keyboardShortcut("r")
                if let reload = model.developmentReload {
                    Toggle("Automatically reload source changes", isOn: Binding(get: { reload.enabled }, set: { reload.setEnabled($0) })).pointingHand()
                    Text(reload.status)
                    Button("Benchmark live agent roster") { AgentRosterBenchmarkWindow.open() }.pointingHand()
                    Button("Benchmark standing office") { StandingOfficeBenchmarkWindow.open() }.pointingHand()
                    Button("Benchmark fixed office") { FixedOfficeBenchmarkWindow.open() }.pointingHand()
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
                    }.pointingHand().pickerStyle(.segmented).padding(.top, 12)
                }.padding(20)
                Button { model.showInbox = true } label: {
                    Label("Attention inbox · \(model.attentionSessions.count)", systemImage: "tray")
                }.pointingHand().padding(.horizontal, 20).padding(.bottom, 12)
                List(selection: $model.selectedFolderID) {
                    ForEach(model.folders) { folder in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(folder.name, systemImage: "folder").font(.system(size: 13, weight: .medium))
                            Text(folder.path ?? "No absolute folder recorded").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                            Text(SessionPresentation.counts(folder.sessions, showInternal: model.showInternal))
                                .font(.system(size: 10)).foregroundStyle(.tertiary)
                            Text(model.counts(folder)).font(.system(size: 10)).foregroundStyle(.secondary)
                        }.padding(.vertical, 6).pointingHand().tag(folder.id)
                    }
                }.listStyle(.sidebar)
                HStack {
                    if model.isScanning { ProgressView().controlSize(.small) }
                    Text("\(model.folders.count) folders · \(model.filtered.count) sessions").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { model.showConnections = true } label: { Image(systemName: "externaldrive.connected.to.line.below") }.pointingHand().help("Local connections")
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
                            Button("Open folder in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }.pointingHand()
                                .font(.caption)
                        }
                    }.padding(18)
                    Picker("Archive", selection: $model.archiveFilter) { Text("All conversations").tag("All"); Text("Active").tag("Active"); Text("Archived").tag("Archived") }.pointingHand().padding(.horizontal, 18)
                    Picker("Activity", selection: $model.activityFilter) {
                        Text("All").tag("All")
                        Text("Working").tag("Working")
                        Text("Needs attention").tag("Needs attention")
                    }.pointingHand().padding(.horizontal, 18)
                    if model.rows(folder).isEmpty {
                        Text("No conversations match these filters.")
                            .font(.callout).foregroundStyle(.secondary).padding(18)
                    }
                    List(selection: $model.selectedID) {
                        ForEach(model.rows(folder)) { row in
                            let session = row.session
                            VStack(alignment: .leading, spacing: 6) {
                                Text((model.pinned.contains(session.id) ? "📌 " : "") + session.displayTitle).help(TaskTitle.full(session.title)).accessibilityLabel(TaskTitle.full(session.title)).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                HStack {
                                    Text(session.sourceLabel)
                                    Text(row.label)
                                    if session.archived { Text("Archived") }
                                }.font(.caption2).foregroundStyle(.secondary)
                                ActivityBadge(summary: model.summary(session), livePhase: model.execution.tasks[session.sessionID]?.attached == true ? model.execution.tasks[session.sessionID]?.phase : nil)
                                Text(session.modified, style: .date).font(.caption2).foregroundStyle(.tertiary)
                            }.padding(.vertical, 6).padding(.leading, CGFloat(min(row.depth, 8)) * 16).pointingHand().tag(session.id)
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
                    Button("Check connections") { model.showConnections = true }.pointingHand()
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Search chats") { model.showMessageSearch = true }.pointingHand()
                Button { model.projects.selectedID = nil } label: { Label("New Session", systemImage: "plus") }.pointingHand()
                Toggle("Show internal sessions", isOn: $model.showInternal).pointingHand()
                    .help("Include internal approval reviews without changing source records")
                Button { model.paused.toggle() } label: { Label(model.paused ? "Resume updates" : "Pause updates", systemImage: model.paused ? "play" : "pause") }.pointingHand()
                    .help("Pause observation only; agents continue working")
                Button { Task { await model.refresh(); await model.readSelected() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }.pointingHand().disabled(model.isScanning)
            }
        }
        .sheet(isPresented: $model.showMessageSearch) { ConversationSearchView(model: model, threadID: nil) }
        .alert("Rename conversation", isPresented: Binding(get: { model.renameSession != nil }, set: { if !$0 { model.renameSession = nil } })) {
            TextField("Name", text: $model.renameText)
            Button("Save") { if let session = model.renameSession { model.renameConversation(session) } }.pointingHand()
            Button("Cancel", role: .cancel) { model.renameSession = nil }.pointingHand()
        }
        .alert(model.archiveSession?.archived == true ? "Restore conversation?" : "Archive conversation?", isPresented: Binding(get: { model.archiveSession != nil }, set: { if !$0 { model.archiveSession = nil } })) {
            Button("Continue") { if let session = model.archiveSession { model.archiveConversation(session) } }.pointingHand()
            Button("Cancel", role: .cancel) { model.archiveSession = nil }.pointingHand()
        } message: { Text("This uses Codex's conversation API. Archiving may include spawned descendants; it does not delete working files.") }
        .alert("Conversation action", isPresented: Binding(get: { model.workflowError != nil }, set: { if !$0 { model.workflowError = nil } })) { Button("OK") { model.workflowError = nil }.pointingHand() } message: { Text(model.workflowError ?? "") }
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
    @Environment(\.avatarMessages) private var avatarMessages
    let session: Session
    @Bindable var model: LibraryModel
    var hasLocalReview = false
    var activityAction: ((String) -> Void)?
    var shellContent = false
    var embeddedWorkScreen = false
    private var effectiveMode: ConversationViewMode { embeddedWorkScreen ? .conversation : model.viewMode }
    private var activityState: ActivityPanelState { model.activityState(session) }
    private func openActivity(_ section: String) {
        activityState.section = section
        if let activityAction { activityAction(section) } else { showChanges = false; activityState.visible = true }
    }
    @State private var showDetails = false
    @State private var showChanges = false
    @State private var showFind = false
    @State private var followsLatest = true
    @State private var bottomRevealRevision = 0
    @AppStorage("conversationHistoryDisplayMode") private var historyMode = HistoryDisplayMode.conversation.rawValue
    @State private var showUsage = false
    private var displayMode: HistoryDisplayMode { HistoryDisplayMode(rawValue: historyMode) ?? .conversation }
    private var workingIndicator: ConversationWorkingState? {
        let task = model.execution.tasks[session.sessionID]
        return ConversationWorkingState.resolve(
            phase: task?.phase, attached: task?.attached == true,
            pending: model.outgoing.values.contains { $0.sessionID == session.sessionID && $0.state == .pending },
            blocked: model.execution.requests.values.contains { $0.threadID == session.sessionID && $0.isBlocking }
        )
    }
    private var rowCache: ConversationRowCache { model.conversationPresentation.rows(for: session.id) }
    @State private var historyViewport = ConversationHistoryViewport()
    @State private var historyWindow = ConversationHistoryPage.size
    @State private var historyReadLimit = 300
    @State private var oldestVisibleID: String?
    @State private var loadingOlder = false
    @State private var olderError: String?
    @State private var olderRequest = 0
    private var preparedRows: [ConversationRowCache.Prepared] { rowCache.prepare(model.displayedTranscript.entries, mode: displayMode) }
    private var historyRows: [HistoryRow] { preparedRows.map(\.row) }
    private func loadOlder(scroll: ScrollViewProxy) async {
        guard !loadingOlder else { return }
        let before = preparedRows
        let start = oldestVisibleID.flatMap { id in before.firstIndex { $0.id == id } } ?? max(0, before.count - historyWindow)
        guard start > 0 || model.displayedTranscript.earlierContentOmitted else { return }
        loadingOlder = true; olderError = nil
        defer { loadingOlder = false }
        // Publish the loading state before reading or preparing the next page.
        await Task.yield()
        guard !Task.isCancelled, model.selectedID == session.id else { return }
        if start == 0 {
            guard !model.paused else { olderError = "Resume observation to load older history."; return }
            let oldLimit = model.entryLimit
            model.entryLimit += 300
            historyReadLimit = model.entryLimit
            await model.readSelected()
            guard !Task.isCancelled, model.selectedID == session.id else { return }
            if let error = model.observations[session.id]?.error ?? model.displayedTranscript.error {
                olderError = error; model.entryLimit = oldLimit; return
            }
        }
        let updated = preparedRows
        let previousStart = before.indices.contains(start) ? updated.firstIndex { $0.id == before[start].id } : nil
        let newStart = max(0, (previousStart ?? updated.count - historyWindow) - ConversationHistoryPage.size)
        guard let first = updated.dropFirst(newStart).first,
              first.id != before.dropFirst(start).first?.id else {
            olderError = "No additional history is available from this source."; return
        }
        let anchor = historyViewport.capture()
        oldestVisibleID = first.id
        historyWindow = updated.count - newStart
        await Task.yield()
        guard !Task.isCancelled else { return }
        if let anchor { scroll.scrollTo(anchor, anchor: .top) }
        historyViewport.restore()
    }
    private func saveHistoryBookmark() {
        historyViewport.capture()
        let bookmark = ConversationViewBookmark(
            followsLatest: followsLatest, anchor: historyViewport.checkpoint,
            oldestID: oldestVisibleID, window: historyWindow, entryLimit: historyReadLimit)
        if model.navigation.projectTabs.conversationBookmarks[session.id] != bookmark {
            model.navigation.projectTabs.conversationBookmarks[session.id] = bookmark
        }
    }
    private var failureReview: (key: String, label: String)? {
        guard let agent = model.workspaceAgents(session).first(where: \.isMain),
              [.failed, .stopped].contains(agent.status), let key = agent.completionKey else { return nil }
        return (key, agent.status == .failed ? "This turn failed." : "This turn was interrupted.")
    }
    private func completionVisibilityKeys(entries: [Entry]) -> [String: String] {
        let tracker = AgentCompletionViews.shared
        let sources = model.conversations.record(session.id)?.segments
            ?? [ConversationSegment(nativeID: session.sessionID, provider: session.provider, model: "")]
        var last: [String: String] = [:]
        for entry in entries where entry.claude?.agentID == nil {
            guard entry.kind == "Assistant" || entry.kind == "Proposed plan" || entry.image != nil || !(entry.tool?.outputs.isEmpty ?? true) || ConversationHistory.needsAttention(entry),
                  let turn = entry.completionMessageID ?? entry.turnID else { continue }
            let matches = sources.compactMap { source -> String? in
                let key = source.provider + ":" + source.nativeID + ":" + turn
                return tracker.confirmed.contains(key) || model.execution.tasks[source.nativeID]?.terminalTurns.contains(turn) == true ? key : nil
            }
            // Ambiguous imported identities must never acknowledge another segment.
            guard Set(matches).count == 1, let key = matches.first else { continue }
            last[key] = entry.id
        }
        return Dictionary(last.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
    }
    var body: some View {
        // Project sessions already have a review host. Even a hidden inspector
        // installs a native split view whose intrinsic height can push the
        // approval controls and composer outside the project viewport.
        if hasLocalReview {
            conversationContent
        } else {
            conversationContent
                .inspector(isPresented: Binding(get: { showChanges || activityState.visible }, set: { if !$0 { showChanges = false; activityState.visible = false } })) {
                    if activityState.visible {
                        SessionActivityPanel(session: session, library: model, state: activityState, close: { activityState.visible = false })
                            .inspectorColumnWidth(min: 380, ideal: 520, max: 900)
                    } else {
                        VStack(spacing: 0) {
                            ReviewChangesControls(model: model, session: session)
                            Divider()
                            ExecutionChangesView(work: model.execution.tasks[session.sessionID]?.work ?? ExecutionWork())
                        }.inspectorColumnWidth(min: 400, ideal: 580, max: 900)
                    }
                }
        }
    }
    private func historyEntry(_ entry: Entry) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
        if entry.kind == "Provider switch" {
            DisclosureGroup {
                Text(entry.text.components(separatedBy: "\n").dropFirst(2).joined(separator: "\n")).font(.caption).textSelection(.enabled)
            } label: { Text(entry.text.components(separatedBy: "\n").first ?? "Model switched").disclosurePointingHand() }.font(.caption).foregroundStyle(.secondary).padding(.vertical, 12)
        } else {
        EntryView(entry: entry, viewPlan: { activityState.selectedPlan = model.activitySnapshot(session).plans.first(where: { $0.nativeID == entry.providerItemID || $0.detail == entry.text })?.id; openActivity("Plan") }, selectWorker: { model.openWorker($0) }, progress: model.execution.tasks[session.sessionID]?.toolProgress[entry.tool?.item["id"].string ?? ""])
            .contextMenu {
                if let turn = entry.turnID, session.provider == .codex {
                    Button("Fork through this turn") { model.forkConversation(session, through: turn) }.pointingHand().disabled(model.execution.tasks[session.sessionID]?.phase.active == true)
                }
            }
        }
        if let message = model.outgoing[entry.id] {
            if message.state == .failed || message.state == .uncertain {
                HStack {
                    Text(message.state == .failed ? "Not sent" : "Delivery unconfirmed · check history before resending").font(.caption).foregroundStyle(.secondary)
                    if message.state == .failed, let retry = model.retryOutgoing[entry.id] { Button("Retry", action: retry).pointingHand().buttonStyle(.borderless) }
                }
                if let error = message.error { DisclosureGroup { Text(error).font(.caption).textSelection(.enabled) } label: { Text("Details").disclosurePointingHand() } }
            }
        }
        }
        .environment(\.historyDetails, displayMode == .detailed)
    }

    @ViewBuilder private var historyControls: some View {
                    Menu {
                        Picker("History detail", selection: $historyMode) {
                            ForEach(HistoryDisplayMode.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                        }.pointingHand()
                    } label: { Label(displayMode.rawValue, systemImage: "text.alignleft") }.pointingHand()
                        .help("Conversation groups routine activity. Detailed shows all available records.")
                        .accessibilityLabel("History view: " + displayMode.rawValue)
                    Button("Usage") { showUsage = true }.pointingHand()

                        .popover(isPresented: $showUsage) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 16) {
                                    Text("Reported usage").font(.headline)
                                    Text("From loaded conversation history; reports may overlap. These are not added together.").font(.caption).foregroundStyle(.secondary)
                                    let records = model.displayedTranscript.entries.filter(ConversationHistory.isUsage)
                                    if records.isEmpty { Text("No usage reported in loaded history.").foregroundStyle(.secondary) }
                                    ForEach(records) { EntryView(entry: $0) }
                                }.padding(20)
                            }.frame(width: 380, height: 420)
                        }
    }

    private var avatarTools: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conversation").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            historyControls
            if session.provider == .codex { Button("Find") { showFind = true }.pointingHand().keyboardShortcut("f", modifiers: .command) }
            Button("Activity") { openActivity(activityState.section) }.pointingHand()
            let snapshot = model.activitySnapshot(session)
            if !snapshot.plans.isEmpty { Button("Plan") { openActivity("Plan") }.pointingHand() }
            if !snapshot.steps.isEmpty { Button("Tasks") { openActivity("Steps") }.pointingHand() }
            Menu("Conversation actions") { ConversationActions(model: model, session: session) }.pointingHand()
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.sourceLabel + " · " + model.health)
                    Text(model.summary(session).state.rawValue)
                    Text(session.project)
                    Text("Session: " + session.sessionID)
                    if let observation = model.observations[session.id] {
                        Text("Last read: " + observation.synchronizedAt.formatted())
                    }
                    Text("Saved transcript updates may be buffered by the provider.")
                    if let url = session.url { Button("Reveal transcript") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.pointingHand() }
                }.font(.caption).textSelection(.enabled)
            } label: { Text("Details").disclosurePointingHand() }
        }
    }

    private var conversationContent: some View {
        // Capture derived history outside ScrollViewReader's deferred layout closure.
        // Lazy row discovery re-evaluates that closure during native scrolling.
        let transcript = model.displayedTranscript
        let prepared = rowCache.prepare(transcript.entries, mode: displayMode)
        let completionKeys = completionVisibilityKeys(entries: transcript.entries)
        let indicator = workingIndicator
        let failure = failureReview
        return VStack(alignment: .leading, spacing: 0) {
            if !avatarMessages {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        if !shellContent { Text(session.displayTitle).help(TaskTitle.full(session.title)).accessibilityLabel(TaskTitle.full(session.title)).font(.system(size: 16, weight: .medium)).lineLimit(2).textSelection(.enabled) }
                        Text("\(session.sourceLabel) · Last reported: \(model.summary(session).state.rawValue) · \(model.health)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if session.provider == .codex {
                        Button("Find") { showFind = true }.pointingHand().keyboardShortcut("f", modifiers: .command)
                        if !hasLocalReview { Button("Review") { showChanges = true }.pointingHand() }
                        Menu { ConversationActions(model: model, session: session) } label: { Image(systemName: "ellipsis.circle") }.pointingHand()
                    }
                    Button("Activity") { openActivity(activityState.section) }.pointingHand()
                    Button { showDetails.toggle() } label: { Image(systemName: "info.circle") }.pointingHand()
                        .buttonStyle(.plain).help("Conversation details").accessibilityLabel("Conversation details")
                        .popover(isPresented: $showDetails) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Conversation details").font(.headline)
                                Text(session.project.isEmpty ? "Working folder unavailable" : session.project)
                                Text(session.classification.rawValue + " · " + session.classificationEvidence)
                                Text("Session ID: " + session.sessionID)
                                if let parent = session.parentID { Text("Recorded parent: " + parent) }
                                Text("Discovery: " + session.historySource)
                                if let observation = model.observations[session.id] {
                                    if let source = observation.sourceModifiedAt { Text("Last source change: " + source.formatted()) }
                                    Text("Last observer read: " + observation.synchronizedAt.formatted())
                                    Text("Last successful synchronization: " + (observation.lastSuccessfulSynchronization?.formatted() ?? "Not yet synchronized"))
                                }
                                Text("\(transcript.source) · \(transcript.malformed) unrecognized records")
                                Text("Recorded status may be stale. Claude Code Desktop conversations are view-only.").foregroundStyle(.secondary)
                                if let url = session.url { Button("Reveal transcript") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.pointingHand() }
                            }.font(.caption).textSelection(.enabled).padding(20).frame(width: 380)
                        }
                }
                HStack(spacing: 12) {
                    historyControls
                    Spacer(minLength: 0)
                }
            }.buttonStyle(.borderless).padding(.horizontal, 20).padding(.vertical, shellContent ? 8 : 12)
            if session.provider == .codex && model.execution.tasks[session.sessionID]?.attached != true {
                Label("Observing saved transcript · Codex may buffer updates until later in the turn. Hooks can improve activity coverage.", systemImage: "clock.badge.exclamationmark")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.bottom, 8)
            }
            }
            if !model.historyIsLoading(session), let error = model.observations[session.id]?.error {
                HStack {
                    Label("Observation unavailable: " + error, systemImage: "exclamationmark.triangle")
                    Spacer()
                    Button("Retry") { Task { await model.readSelected() } }.pointingHand().disabled(model.paused)
                }.font(.caption).foregroundStyle(.orange).padding(12)
            }
            if !shellContent {
                HStack(spacing: 0) {
                    ForEach(ConversationViewMode.allCases, id: \.self) { mode in
                        WorkspaceTabButton(title: mode.rawValue, selected: effectiveMode == mode) { model.viewMode = mode }
                    }
                }.padding(.horizontal, 12)
            }
            WorkspacePaneStack {
                VStack(spacing: 0) {
                    let snapshot = model.activitySnapshot(session)
                    if !avatarMessages && (!snapshot.plans.isEmpty || !snapshot.steps.isEmpty || !snapshot.agents.isEmpty) {
                        HStack {
                            if !snapshot.plans.isEmpty { Button("Plan") { openActivity("Plan") }.pointingHand() }
                            if !snapshot.steps.isEmpty { Button("Tasks · \(snapshot.steps.filter { $0.status == "completed" }.count)/\(snapshot.steps.count)") { openActivity("Steps") }.pointingHand() }
                            if !snapshot.agents.isEmpty { Button("Agents · " + snapshot.agentSummary) { openActivity("Agents") }.pointingHand() }
                        }.font(.callout).padding(.horizontal, 24).padding(.bottom, 10)
                    }
                    if let task = model.execution.tasks[session.sessionID], task.attached {
                        if !avatarMessages && !hasLocalReview && !task.work.diff.isEmpty {
                            Button("Changes · \(task.work.files.count) files · +\(task.work.files.reduce(0) { $0 + $1.additions }) −\(task.work.files.reduce(0) { $0 + $1.deletions })") { showChanges.toggle() }.pointingHand()
                                .padding(.horizontal, 24).padding(.bottom, 10)
                        }
                    }
                    Divider()
                    if effectiveMode == .html {
                        HTMLCanvasView(session: session, livePhase: model.execution.tasks[session.sessionID]?.attached == true ? model.execution.tasks[session.sessionID]?.phase : nil, activities: CanvasActivity.current(model.execution.tasks[session.sessionID]), observedSummary: model.summary(session))
                            .id(session.id)
                    } else if effectiveMode == .activity {
                        SessionActivityPanel(session: session, library: model, state: activityState, close: { model.viewMode = .conversation })
                    } else if model.historyIsLoading(session) && transcript.entries.isEmpty {
                        ConversationHistoryLoader().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if model.paused && model.transcriptSessionID != session.id {
                        ContentUnavailableView("Observation paused", systemImage: "pause.circle", description: Text("Resume observation to load conversation history."))
                    } else if !model.historyIsLoading(session), let error = transcript.error {
                        ContentUnavailableView("Transcript unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
                    } else {
                        ScrollViewReader { scroll in
                        List {
                            Group {
                                if model.historyIsLoading(session) {
                                    ConversationHistoryLoader(compact: true)
                                } else if let notice = transcript.notice {
                                    Text(notice).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                                }
                                if !transcript.unrecognizedTypes.isEmpty {
                                    DisclosureGroup {
                                        ForEach(transcript.unrecognizedTypes.keys.sorted(), id: \.self) { type in
                                            Text("\(type): \(transcript.unrecognizedTypes[type] ?? 0)").font(.caption.monospaced())
                                        }
                                    } label: { Text("Some source record types are not displayed").disclosurePointingHand() }.font(.caption).foregroundStyle(.secondary)
                                }
                                if transcript.entries.isEmpty { Text(model.execution.tasks[session.sessionID]?.phase.active == true ? "Your conversation will appear here." : "No messages yet.").foregroundStyle(.secondary) }
                                let start = oldestVisibleID.flatMap { id in prepared.firstIndex { $0.id == id } } ?? max(0, prepared.count - historyWindow)
                                if start > 0 || transcript.earlierContentOmitted {
                                    HStack {
                                        if loadingOlder { OlderHistoryLoader() }
                                        else if olderError != nil { Button("Retry") { olderError = nil; olderRequest += 1 }.pointingHand() }
                                        if let olderError { Text(olderError).foregroundStyle(.secondary) }
                                    }.font(.caption).frame(minHeight: 24).frame(maxWidth: .infinity).id("older-history")
                                }
                                ForEach(Array(prepared.dropFirst(start))) { item in
                                    let row = item.row
                                    VStack(alignment: .leading, spacing: 0) {
                                    if avatarMessages, let date = item.separator {
                                        Text(date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 8)
                                    }
                                    if row.grouped {
                                        HistoryActivityGroup(row: row) { historyEntry($0) }
                                    } else if let entry = row.entries.first {
                                        historyEntry(entry).environment(\.avatarBubbleTail, item.tail)
                                    }
                                    }.id(item.id)
                                    .background(ConversationHistoryRowAnchor(id: item.id, viewport: historyViewport))
                                    .background(AgentCompletionVisibility(key: row.entries.last.flatMap { completionKeys[$0.id] }, active: model.windowIsActive && model.selectedID == session.id && effectiveMode == .conversation))
                                }
                                if let failure {
                                    Text(failure.label).font(.callout).foregroundStyle(.secondary)
                                        .background(AgentCompletionVisibility(key: failure.key, active: model.windowIsActive && model.selectedID == session.id))
                                }
                                if let indicator {
                                    ConversationWorkingIndicator(state: indicator, active: effectiveMode == .conversation)
                                }
                                Color.clear.frame(height: 1).id("conversation-bottom")
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 9, leading: 24, bottom: 9, trailing: 24))
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .environment(\.defaultMinListRowHeight, 1)
                        .background(ConversationScrollTracking(followsLatest: followsLatest, revealRevision: bottomRevealRevision, onOlderHistory: { if !loadingOlder && olderError == nil { olderRequest += 1 } }, onScrollBegan: { historyViewport.cancel(); if oldestVisibleID == nil { oldestVisibleID = preparedRows.suffix(historyWindow).first?.id } }) { followsLatest = $0; saveHistoryBookmark() })
                        .frame(minHeight: 0, maxHeight: .infinity).layoutPriority(-1)
                        .task(id: olderRequest) { if olderRequest > 0 { await loadOlder(scroll: scroll) } }
                        .onChange(of: session.id) { historyWindow = ConversationHistoryPage.size; oldestVisibleID = nil; olderError = nil; historyViewport.cancel() }
                        .onChange(of: historyMode) { historyWindow = ConversationHistoryPage.size; oldestVisibleID = nil; historyViewport.cancel() }
                        .onChange(of: model.execution.tasks[session.sessionID]?.transcript) { model.reconcileOutgoing(session.sessionID) }
                        .onAppear {
                            // Reopening a conversation always starts with a small recent page.
                            // Older pages are requested only while the reader scrolls back.
                            followsLatest = true
                            historyReadLimit = model.entryLimit
                            historyWindow = ConversationHistoryPage.size
                            oldestVisibleID = nil
                            historyViewport.cancel()
                            bottomRevealRevision += 1
                        }
                        .onDisappear { saveHistoryBookmark() }
                        .task(id: bottomRevealRevision) {
                            // A deliberate reveal (open, send, Jump to latest) waits for the new row's layout.
                            await Task.yield()
                            guard !Task.isCancelled, followsLatest else { return }
                            scroll.scrollTo("conversation-bottom", anchor: .bottom)
                        }
                        .onChange(of: model.outgoing.keys.sorted()) { old, new in
                            if new.contains(where: { !old.contains($0) && model.outgoing[$0]?.sessionID == session.sessionID }) {
                                followsLatest = true
                                bottomRevealRevision += 1
                            }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if !followsLatest {
                                Button {
                                    followsLatest = true
                                    bottomRevealRevision += 1
                                } label: { Label("Jump to latest", systemImage: "arrow.down") }.pointingHand()
                                    .buttonStyle(.borderedProminent).padding(16)
                            }
                        }
                        .onChange(of: model.historyRevealTargets[session.id]) { _, value in
                            guard let value else { return }
                            followsLatest = false
                            historyWindow = preparedRows.count; oldestVisibleID = preparedRows.first?.id
                            let target = ConversationHistory.anchor(value, in: historyRows, original: transcript.entries) ?? value
                            scroll.scrollTo(target, anchor: .top)
                        }
                        }
                    }
                    Divider()
                    ExecutionControls(library: model, session: session).id(session.id)
                        .anchorPreference(key: UpdateComposerAnchor.self, value: .bounds) { $0 }
                        .environment(\.avatarConversationTools, AnyView(avatarTools))
                        .frame(maxWidth: 800).frame(maxWidth: .infinity)
                }
                .opacity(effectiveMode == .workspace ? 0 : 1)
                .allowsHitTesting(effectiveMode != .workspace)
                .accessibilityHidden(effectiveMode == .workspace)
                if effectiveMode == .workspace {
                    WorkspaceSessionScene(library: model, session: session,
                        openConversation: { model.viewMode = .conversation },
                        openActivity: { model.viewMode = .activity }).id(session.id)
                }
            }
        }
        .environment(\.conversationImageBaseURL, URL(fileURLWithPath: session.project, isDirectory: true))
        .sheet(isPresented: $showFind) { ConversationSearchView(model: model, threadID: session.sessionID) }
        .onChange(of: session.id) { showChanges = false }
        .onChange(of: model.showingLiveTurn) { if !model.showingLiveTurn { showChanges = false } }
    }
}

struct EntryView: View {
    @Environment(\.avatarMessages) private var avatarMessages
    let entry: Entry
    var viewPlan: (() -> Void)?
    var selectWorker: ((String) -> Void)?
    var progress: String?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.historyDetails) private var historyDetails
    private var isUser: Bool { entry.category == .user }
    var body: some View {
        if avatarMessages && (entry.category == .user || entry.category == .assistant) {
            VStack(alignment: .leading, spacing: 6) {
                AvatarMessageBubble(entry: entry)
                if historyDetails, let records = entry.sourceRecords, !records.isEmpty {
                    SourceRecordDetails(records: records)
                }
            }
        } else {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 52) }
            VStack(alignment: .leading, spacing: 8) {
                if let image = entry.image {
                    ToolImagePreview(reference: image)
                }
                if let presentation = entry.claude {
                    ClaudeEntryView(entry: entry, presentation: presentation)
                } else if let presentation = entry.codex {
                    CodexEntryView(entry: entry, presentation: presentation, selectWorker: selectWorker, progress: progress)
                } else if entry.kind == "Proposed plan" {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Proposed plan", systemImage: "doc.text").font(.headline)
                        Text(entry.text).lineLimit(3).foregroundStyle(.secondary)
                        if let viewPlan { Button("View plan", action: viewPlan).pointingHand() }
                        else { DisclosureGroup { TranscriptContent(text: entry.text) } label: { Text("View plan").disclosurePointingHand() } }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                } else if let tool = entry.tool {
                    RichToolResultView(result: tool, selectWorker: selectWorker, progress: progress)
                } else if entry.category == .activity || entry.category == .context {
                    DisclosureGroup {
                        TranscriptContent(text: entry.text, literal: entry.kind == "Tool call").padding(.top, 8)
                    } label: { Group {
                        Label(entry.image != nil ? "Image details" : entry.category == .context ? "System context" : markdownTitle(String(entry.text.prefix(100))).replacingOccurrences(of: "\n", with: " "),
                              systemImage: entry.image != nil ? "photo" : entry.category == .context ? "doc.text" : "terminal")
                            .lineLimit(2)
                     }.disclosurePointingHand() }.font(.callout).foregroundStyle(.secondary)
                } else {
                    if !isUser { Text("Assistant").font(.caption.weight(.medium)).foregroundStyle(.secondary) }
                    TranscriptContent(text: entry.text)
                }
                if historyDetails, let records = entry.sourceRecords, !records.isEmpty, entry.category != .context {
                    SourceRecordDetails(records: records)
                }
            }
            .padding(isUser ? 16 : 4)
            .background(isUser ? DioramaStyle.raised : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .environment(\.colorScheme, isUser ? .dark : colorScheme)
            .help(entry.timestamp ?? entry.kind)
            if isUser == false { Spacer(minLength: 0) }
        }.padding(.vertical, isUser ? 6 : 2)
        }
    }
}

enum ConnectionTab: String, CaseIterable {
    case codex = "Codex", claude = "Claude Code", desktop = "Claude Desktop"
    var provider: Provider { self == .codex ? .codex : .claude }
    var icon: String { self == .desktop ? "desktopcomputer" : "terminal" }
}

struct ConnectionsView: View {
    @Bindable var model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection: ConnectionTab = .codex
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Connections").font(.title2.weight(.semibold))
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 24, height: 24) }
                        .pointingHand().buttonStyle(HoverButtonStyle()).accessibilityLabel("Close connections")
                        .keyboardShortcut(.cancelAction)
                }
                HStack(spacing: 20) {
                    ForEach(ConnectionTab.allCases, id: \.self) { tab in
                        Button { selection = tab } label: {
                            Label(tab.rawValue, systemImage: tab.icon)
                                .font(.system(size: 13, weight: selection == tab ? .semibold : .regular))
                                .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
                                .padding(.vertical, 10)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(selection == tab ? Color.accentColor : .clear).frame(height: 2)
                                }
                        }.pointingHand().buttonStyle(HoverButtonStyle(inset: 0))
                            .accessibilityAddTraits(selection == tab ? .isSelected : [])
                    }
                    Spacer(minLength: 0)
                }
            }.padding(.horizontal, 24).padding(.top, 24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if selection == .codex {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Agent execution").font(.headline)
                                Spacer()
                                Label(model.execution.connected ? "Connected" : "Disconnected", systemImage: model.execution.connected ? "checkmark.circle.fill" : "minus.circle")
                                    .font(.callout).foregroundStyle(model.execution.connected ? Color.green : Color.secondary)
                            }
                            Text("Connection used to run agent tasks in Diorama.").font(.callout).foregroundStyle(.secondary)
                            if let error = model.execution.error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                        }
                        Divider()
                    } else if selection == .desktop {
                        Label("View-only integration", systemImage: "eye").font(.headline)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Local activity & history").font(.headline)
                            Text("Observe Claude Code sessions from local records. Activity reporting is configured below.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    HookConnections(model: model, selection: selection)
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Text("Local to this Mac").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.pointingHand().keyboardShortcut(.defaultAction)
            }.padding(.horizontal, 24).padding(.vertical, 16)
        }.frame(width: 680, height: 640)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ConnectionDiagnostics: View {
    @Bindable var model: LibraryModel
    let selection: ConnectionTab
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.health + " · current activity unverified")
            if let checked = model.scannedAt { Text("Last check: " + checked.formatted()) }
            if selection == .codex {
                if let history = model.notices.first(where: { $0.hasPrefix("Codex history:") }) { Text(history) }
                Text("New tasks run directly in your chosen folder. Closing a window keeps work running; quitting requires confirmed interruption of active Diorama tasks. Eligible imported conversations can continue here after the other client releases them.")
            }
            Text("History observation never starts tasks. Execution occurs only through explicit new-task or owned-task controls.")
            Text("Diorama reads Codex history through a local App Server with explicit local-file fallbacks. Claude Code and activity use local records. App Server may maintain its own runtime metadata.")
            ForEach(StorageRoot.defaults().filter { $0.provider == selection.provider }, id: \.url) { root in
                VStack(alignment: .leading, spacing: 4) {
                    Text(root.provider.rawValue + (root.archived ? " · Archived" : "")).fontWeight(.medium)
                    Text(root.url.path).font(.system(.caption, design: .monospaced))
                }
            }
            if selection == .desktop {
                Text("Claude Chat / Cowork: not connected")
                Text("Local Claude Code Desktop history is observed through session metadata and transcripts. Chat, Cowork, cloud and SSH sessions are outside this integration.")
            }
            if !model.notices.isEmpty { Text(model.notices.joined(separator: "\n")) }
        }.font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
    }
}
