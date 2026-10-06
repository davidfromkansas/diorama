import SwiftUI
import Observation
import DioramaCore

/// Persistent project and execution membership, shared by every window.
@Observable final class ProjectRepository {
    var records: [DioramaProject] = [] { didSet { recordsRevision &+= 1 } }
    /// Bumped on any project change, so cached per-project lookups can be trusted cheaply.
    @ObservationIgnored var recordsRevision: UInt64 = 0
    var error: String?
    var busy = Set<String>()
    var associations: [String: String] = [:] { didSet { associationsRevision &+= 1 } }
    var associationsRevision: UInt64 = 0
    var storageReadable = true
    let storageURL: URL
    init(storageURL: URL) {
        self.storageURL = storageURL
        do { records = try ProjectStorage.load(from: storageURL) }
        catch { self.error = "Projects could not be loaded. The saved file has not been overwritten: \(error.localizedDescription)"; storageReadable = false }
    }
}

struct ProjectViewSelection: Codable, Equatable {
    var session: String?
    var section: String
    var fileLocation: String?
    var fileSelection: String?
    var expandedFolders: Set<String>
    init(_ project: DioramaProject) {
        session = project.selectedSession; section = project.section
        fileLocation = project.fileLocation; fileSelection = project.fileSelection; expandedFolders = project.expandedFolders
    }
    func apply(to project: inout DioramaProject) {
        project.selectedSession = session; project.section = section
        project.fileLocation = fileLocation; project.fileSelection = fileSelection; project.expandedFolders = expandedFolders
    }
}

@Observable final class ProjectModel {
    let repository: ProjectRepository
    var presentation: [String: ProjectViewSelection] = [:]
    var projects: [DioramaProject] {
        get { repository.records.map { record in var value = record; presentation[record.id]?.apply(to: &value); return value } }
        set { repository.records = newValue }
    }
    var selectedID: String?
    var error: String? { get { repository.error } set { repository.error = newValue } }
    var busy: Set<String> { get { repository.busy } set { repository.busy = newValue } }
    var associations: [String: String] { get { repository.associations } set { repository.associations = newValue } }
    private var associationsRevision: UInt64 { repository.associationsRevision }
    var storageReadable: Bool { get { repository.storageReadable } set { repository.storageReadable = newValue } }
    var storageURL: URL { repository.storageURL }
    @ObservationIgnored private var sessionCache: [String: ProjectSessionCache] = [:]
    @ObservationIgnored private var sessionIndex: ProjectSessionIndex?
    private struct ProjectSessionIndex {
        let libraryID: ObjectIdentifier
        let revision: UInt64
        let rows: [Session]
        let folders: [String: [Int]]
        let threads: [String: [Int]]
        var resolvedFolders: [String: String] = [:]
        init(library: LibraryModel) {
            libraryID = ObjectIdentifier(library); revision = library.sessionsRevision
            rows = library.sessions
            var folders: [String: [Int]] = [:], threads: [String: [Int]] = [:]
            for (index, row) in rows.enumerated() {
                folders[row.project, default: []].append(index)
                threads[row.sessionID, default: []].append(index)
            }
            self.folders = folders; self.threads = threads
        }
    }
    private struct ProjectSessionCache {
        let libraryID: ObjectIdentifier
        let sessionsRevision: UInt64
        let associationsRevision: UInt64
        let recordsRevision: UInt64
        let project: DioramaProject
        let commonDirectory: String
        let paths: Set<String>
        let threadIDs: Set<String>
        let sessions: [Session]
    }
    init(storageURL: URL = ProjectStorage.file) {
        repository = ProjectRepository(storageURL: storageURL)
        selectedID = UserDefaults.standard.string(forKey: "selectedProject")
    }
    init(sharing model: ProjectModel) { repository = model.repository }
    var selected: DioramaProject? { projects.first { $0.id == selectedID } }
    func checkpoint() throws {
        guard storageReadable else { throw AppServerFailure("Project storage is unavailable; restore the saved file before creating work.") }
        try ProjectStorage.save(repository.records, to: storageURL)
    }
    func save() {
        guard storageReadable else { return }
        do { try ProjectStorage.save(repository.records, to: storageURL) } catch { self.error = "Could not save Projects: \(error.localizedDescription)" }
    }
    func update(_ id: String, _ body: (inout DioramaProject) -> Void) {
        guard let i = repository.records.firstIndex(where: { $0.id == id }) else { return }
        var value = repository.records[i]
        presentation[id]?.apply(to: &value)
        body(&value)
        presentation[id] = ProjectViewSelection(value)
        // Keep navigation out of the shared repository. Drafts and workspaces remain shared.
        ProjectViewSelection(repository.records[i]).apply(to: &value)
        if value != repository.records[i] { repository.records[i] = value; save() }
    }
    func add(_ project: DioramaProject) {
        if let existing = projects.first(where: {
            $0.folderIdentity == project.folderIdentity || ($0.isGitBacked && project.isGitBacked && $0.commonDirectory == project.commonDirectory)
        }) { selectedID = existing.id; return }
        projects.append(project); selectedID = project.id; save()
    }
    func sessions(_ project: DioramaProject, library: LibraryModel) -> [Session] {
        // Fast path: nothing about projects, sessions or associations changed since the last
        // lookup (tab badges ask on every view update; comparing path sets there was slow).
        if let cached = sessionCache[project.id], cached.libraryID == ObjectIdentifier(library),
           cached.sessionsRevision == library.sessionsRevision, cached.associationsRevision == associationsRevision,
           cached.recordsRevision == repository.recordsRevision, cached.project == project {
            return cached.sessions
        }
        // Check raw membership inputs before doing any filesystem work. Scroll-driven
        // view updates usually need exactly the same rows as the previous frame.
        let paths = Set([project.folder] + project.workspaces.map(\.folder))
        let ids = Set(project.workspaces.compactMap(\.threadID))
        let revision = library.sessionsRevision
        if let cached = sessionCache[project.id], cached.libraryID == ObjectIdentifier(library),
           cached.sessionsRevision == revision, cached.associationsRevision == associationsRevision,
           cached.commonDirectory == project.commonDirectory, cached.paths == paths, cached.threadIDs == ids {
            return cached.sessions
        }
        if sessionIndex?.libraryID != ObjectIdentifier(library) || sessionIndex?.revision != revision {
            sessionIndex = ProjectSessionIndex(library: library)
        }
        let canonicalPaths = Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path })
        let knownAssociations = associations
        var matches = Set<Int>()
        // Resolve membership once per distinct folder, not once per conversation.
        // The same index serves every tab and agent-name lookup for this roster.
        for (folder, indices) in sessionIndex!.folders {
            let direct = paths.contains(folder) || (project.isGitBacked && knownAssociations[folder] == project.commonDirectory)
            if direct { matches.formUnion(indices); continue }
            let resolved: String
            if let cached = sessionIndex!.resolvedFolders[folder] { resolved = cached }
            else {
                resolved = URL(fileURLWithPath: folder).standardizedFileURL.resolvingSymlinksInPath().path
                sessionIndex!.resolvedFolders[folder] = resolved
            }
            if canonicalPaths.contains(resolved) { matches.formUnion(indices) }
        }
        for id in ids { matches.formUnion(sessionIndex!.threads[id] ?? []) }
        let rows = matches.sorted().map { sessionIndex!.rows[$0] }
        sessionCache[project.id] = ProjectSessionCache(libraryID: ObjectIdentifier(library), sessionsRevision: revision,
            associationsRevision: associationsRevision, recordsRevision: repository.recordsRevision, project: project, commonDirectory: project.commonDirectory, paths: paths, threadIDs: ids, sessions: rows)
        return rows
    }

    func associate(_ sessions: [Session]) async {
        for path in Set(sessions.map(\.project)).filter({ $0.hasPrefix("/") && associations[$0] == nil }) {
            guard !Task.isCancelled else { return }
            if let project = try? await ProjectGit.discover(path) { associations[path] = project.commonDirectory }
            else { associations[path] = "unavailable" }
        }
    }
    func prepare(projectID: String, base: String, cached: Bool, options: SessionStartOptions? = nil, switchConfirmed: Bool = false, activeFolders: Set<String> = []) async throws -> ProjectWorkspace {
        guard let initial = projects.first(where: { $0.id == projectID }) else { throw AppServerFailure("Project unavailable") }
        guard initial.isGitBacked else { throw AppServerFailure("Starting sessions in Diorama requires Git. You can still view externally started sessions.") }
        let id = initial.pendingWorkspace ?? UUID().uuidString
        update(projectID) { $0.pendingWorkspace = id }
        try checkpoint()
        if let existing = initial.workspaces.first(where: { $0.id == id }) { return existing }
        let workspace: ProjectWorkspace
        if let options {
            let found = try await ProjectGit.discover(options.folder)
            var destination = projects.first(where: { $0.commonDirectory == found.commonDirectory }) ?? found
            destination.id = initial.id
            workspace = try await ProjectGit.prepareLocal(project: destination, id: id, options: options, switchConfirmed: switchConfirmed, activeFolders: activeFolders)
        } else {
            guard let name = DescriptiveBranch.suggestion(initial.draft) else { throw AppServerFailure("Enter a descriptive new branch name before creating a worktree.") }
            workspace = try await ProjectGit.createWorkspace(project: initial, id: id, base: base.isEmpty ? nil : base, useCached: cached, branchName: name)
        }
        update(projectID) {
            $0.workspaces.append(workspace)

        }
        try checkpoint()
        return workspace
    }
    func updateWorkspace(_ projectID: String, id: String, _ body: (inout ProjectWorkspace) -> Void) {
        update(projectID) { project in
            if let index = project.workspaces.firstIndex(where: { $0.id == id }) { body(&project.workspaces[index]) }
        }
    }
}

struct ProjectsRootView: View {
    @Bindable var library: LibraryModel
    @Bindable var projects: ProjectModel
    init(library: LibraryModel) { self.library = library; self.projects = library.projects }
    @State private var addMode: String?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        WorkspaceShell(library: library) { addActions }
        .sheet(isPresented: Binding(get: { addMode != nil }, set: { if !$0 { addMode = nil } })) {
            if addMode == "Choose Project" {
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Text("New Session").font(.title2.bold()); Spacer(); Button("Cancel") { addMode = nil }.pointingHand() }
                    Text("Choose a project for this session.").foregroundStyle(.secondary)
                    ForEach(projects.projects) { project in
                        Button(project.name) { library.navigate(.project(project.id, nil)); library.focusWorkspaceComposer(); addMode = nil }.pointingHand()
                    }
                    Divider()
                    addActions
                }.padding(24).frame(width: 440)
            } else { AddProjectView(mode: addMode ?? "New Project", projects: projects) }
        }
        .alert("Projects", isPresented: Binding(get: { projects.error != nil }, set: { if !$0 { projects.error = nil } })) {
            Button("OK") { projects.error = nil }.pointingHand()
        } message: { Text(projects.error ?? "") }
        .alert("Rename conversation", isPresented: Binding(get: { library.renameSession != nil }, set: { if !$0 { library.renameSession = nil } })) {
            TextField("Name", text: $library.renameText)
            Button("Save") { if let session = library.renameSession { library.renameConversation(session) } }.pointingHand()
            Button("Cancel", role: .cancel) { library.renameSession = nil }.pointingHand()
        }
        .alert("Archive or restore conversation?", isPresented: Binding(get: { library.archiveSession != nil }, set: { if !$0 { library.archiveSession = nil } })) {
            Button("Continue") { if let session = library.archiveSession { library.archiveConversation(session) } }.pointingHand()
            Button("Cancel", role: .cancel) { library.archiveSession = nil }.pointingHand()
        } message: { Text("Working files and branches are retained. Cleanup is a separate action.") }
        .alert("Conversation action", isPresented: Binding(get: { library.workflowError != nil }, set: { if !$0 { library.workflowError = nil } })) {
            Button("OK") { library.workflowError = nil }.pointingHand()
        } message: { Text(library.workflowError ?? "") }
        .sheet(isPresented: $library.showInbox) { AttentionInbox(model: library) }
        .sheet(isPresented: $library.showConnections) { ConnectionsView(model: library) }
        .sheet(isPresented: $library.showMessageSearch) { ConversationSearchView(model: library, threadID: nil) }
        .onChange(of: library.execution.tasks.keys.sorted()) { library.syncOwnedSessions() }
        .onChange(of: projects.selectedID, initial: true) { library.projectNavigation = projects.selectedID != "imported" }
        .onChange(of: addMode) { if addMode != nil { library.captureProjectPresentation(); library.navigation.projectTabs.pickerPresented = false } }
        .onChange(of: library.showNewTask) {
            if library.showNewTask {
                library.showNewTask = false
                if let id = projects.selected?.id { library.navigate(.project(id, nil)); library.focusWorkspaceComposer() }
                else { library.navigation.searchPresented = false; addMode = "Choose Project" }
                library.selectedID = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if !library.paused, scenePhase == .active { Task { await library.readSelected() } }
        }
        .task(id: HistoryPresentationIdentity(session: library.selectedID, active: scenePhase == .active && library.windowIsActive)) {
            guard library.selectedID != nil, scenePhase == .active, library.windowIsActive else { return }
            while !Task.isCancelled {
                if !library.paused { await library.readSelected() }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
    @ViewBuilder private var addActions: some View {
        Button {
            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    Task { do { let opened = try await ProjectFolder.open(url.path); library.captureProjectPresentation(); projects.add(opened); if let id = projects.selectedID { library.selectProjectTab(id) }; addMode = nil } catch { projects.error = error.localizedDescription } }
                }
            }
        } label: { Label("Connect Project", systemImage: "folder") }.pointingHand()
        Button { addMode = "Open GitHub project" } label: {
            Label { Text("Open GitHub Project") } icon: { ConnectorMark(server: "github").accessibilityHidden(true) }
        }.pointingHand()
        Button { addMode = "New Project" } label: { Label("New Project", systemImage: "plus") }.pointingHand()
    }
}

struct AddProjectView: View {
    let mode: String
    @Bindable var projects: ProjectModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var repository = ""
    @State private var parent = ProjectStorage.newProjectsDirectory.path
    @State private var publish = false
    @State private var visibility = "private"
    @State private var error: String?
    @State private var operation: Task<Void, Never>?
    @State private var local: DioramaProject?
    @State private var repositories: [String] = []
    @State private var searching = false
    @State private var repositoryPage = 0
    @State private var hasMoreRepositories = true
    @State private var showGitHub = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(mode).font(.title2.bold())
            if mode == "Open GitHub project" {
                TextField("owner/repository or GitHub URL", text: $repository)
                Button(searching ? "Loading repositories…" : "Browse my repositories") {
                    searching = true
                    Task {
                        defer { searching = false }
                        do {
                            let result = try await GitHubAccount.shared.repositories()
                            repositories = result.map(\.full_name)
                            repositoryPage = 1; hasMoreRepositories = result.count == 100
                        } catch { self.error = error.localizedDescription }
                    }
                }.pointingHand().disabled(searching)
                if !repositories.isEmpty {
                    ScrollView { VStack(alignment: .leading) {
                        ForEach(repositories.filter { repository.isEmpty || $0.localizedCaseInsensitiveContains(repository) }, id: \.self) { repo in
                            Button(repo) { repository = repo; name = repo.split(separator: "/").last.map(String.init) ?? "" }.pointingHand().buttonStyle(.plain)
                        }
                    }}.frame(maxHeight: 140)
                    if hasMoreRepositories {
                        Button("Load more repositories") {
                            searching = true
                            Task {
                                defer { searching = false }
                                do {
                                    let rows = try await GitHubAccount.shared.repositories(page: repositoryPage + 1)
                                    repositories += rows.map(\.full_name).filter { !repositories.contains($0) }
                                    repositoryPage += 1; hasMoreRepositories = rows.count == 100
                                } catch { self.error = error.localizedDescription }
                            }
                        }.pointingHand().disabled(searching)
                    }
                }
            }
            TextField("Project name", text: $name).disabled(local != nil)
            HStack { TextField("Location", text: $parent).textFieldStyle(.roundedBorder).disabled(local != nil); Button("Choose location…") {
                let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                panel.begin { if $0 == .OK, let url = panel.url { parent = url.path } }
            }.pointingHand().disabled(local != nil) }
            Text(URL(fileURLWithPath: parent).appendingPathComponent(name).path).font(.caption).foregroundStyle(.secondary)
            if mode == "New Project" {
                Toggle("Publish to GitHub", isOn: $publish).pointingHand()
                if publish {
                    TextField("GitHub owner/repository", text: $repository)
                    Picker("Visibility", selection: $visibility) { Text("Private").tag("private"); Text("Public").tag("public") }.pointingHand()
                }
                Text("Creates an empty initial commit on main. Publishing pushes this initial branch.").font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            if mode == "Open GitHub project" || publish { Button("GitHub account…") { showGitHub = true }.pointingHand() }
            HStack {
                Button("Cancel") { operation?.cancel(); dismiss() }.pointingHand()
                Spacer()
                if operation != nil { ProgressView().controlSize(.small) }
                Button(local != nil ? "Retry publishing" : mode == "New Project" ? (publish ? "Create and publish" : "Create") : "Clone and open") { start() }.pointingHand()
                    .buttonStyle(.borderedProminent).disabled(operation != nil || name.isEmpty || name.contains("/") || name == "." || name == "..")
            }
        }.padding(24).frame(width: 560).onDisappear { operation?.cancel() }
        .sheet(isPresented: $showGitHub) {
            VStack(alignment: .leading, spacing: 20) {
                GitHubSettingsView()
                HStack { Spacer(); Button("Done") { showGitHub = false }.pointingHand().keyboardShortcut(.defaultAction) }
            }.padding(24).frame(width: 620)
        }
    }
    private func start() {
        error = nil
        operation = Task {
            defer { operation = nil }
            do {
                let path = URL(fileURLWithPath: parent).appendingPathComponent(name).path
                var project: DioramaProject
                if let local { project = local }
                else if mode == "New Project" {
                    let identity = publish ? try await GitHubAccount.shared.identity() : nil
                    project = try await ProjectGit.initialize(path, githubIdentity: identity); local = project; projects.add(project)
                } else {
                    guard !repository.hasPrefix("-"), !repository.isEmpty else { throw AppServerFailure("Choose a GitHub repository.") }
                    guard !FileManager.default.fileExists(atPath: path) else { throw AppServerFailure("Destination already exists. Choose another name or use Open project.") }
                    try await GitHubRepositoryService.shared.clone(repository, to: path)
                    project = try await ProjectGit.discover(path)
                }
                if publish {
                    guard !repository.isEmpty, !repository.hasPrefix("-") else { throw AppServerFailure("Enter the GitHub owner/repository. Your local Project is ready.") }
                    _ = try await GitHubRepositoryService.shared.publish(folder: project.folder, name: repository, privateRepository: visibility == "private")
                    let discovered = try await ProjectGit.discover(project.folder)
                    project.remote = discovered.remote
                    projects.update(project.id) { $0.remote = project.remote; $0.base = project.base }
                }
                projects.add(project); dismiss()
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct ProjectDetailView: View {
    let projectID: String
    @Bindable var projects: ProjectModel
    @Bindable var library: LibraryModel
    @State private var rename = false
    @State private var name = ""
    @State private var contextSnapshot: ProjectContext?
    @State private var remoteSheet = false
    @State private var remoteURL = ""
    @State private var publishSheet = false
    private var project: DioramaProject { projects.projects.first { $0.id == projectID } ?? .unavailable }
    private var section: Binding<String> { Binding(get: { project.section }, set: { value in projects.update(projectID) { $0.section = value } }) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "folder").foregroundStyle(DioramaStyle.accent)
                Text(project.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if !project.isGitBacked {
                    Text("No Git detected").font(.caption).foregroundStyle(.secondary)
                        .help("You can still view conversations, agents, and files. Git features are unavailable.")
                }
                if let session = library.sessions.first(where: { $0.id == project.selectedSession }) {
                    Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                    Text(session.displayTitle).help(TaskTitle.full(session.title)).accessibilityLabel(TaskTitle.full(session.title)).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if let session = library.sessions.first(where: { $0.id == project.selectedSession }),
                   let work = project.workspaces.first(where: { $0.threadID == session.sessionID }) {
                    Label(work.branch, systemImage: "arrow.triangle.branch").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 150).help(work.folder)
                    Button { NSWorkspace.shared.open(URL(fileURLWithPath: work.folder)) } label: { Image(systemName: "folder") }.pointingHand().help("Open session folder")
                }
                Menu {
                    Button("Shared context") { section.wrappedValue = "Context" }.pointingHand()
                    Button("Pull Requests") { section.wrappedValue = "Pull Requests" }.pointingHand().disabled(!project.isGitBacked)
                    Button("Files") { section.wrappedValue = "Files" }.pointingHand()
                    if let session = library.sessions.first(where: { $0.id == project.selectedSession }),
                       let work = project.workspaces.first(where: { $0.threadID == session.sessionID }) {
                        Divider()
                        Text(work.branch)
                        Text("Base: " + String(work.baseCommit.prefix(10)))
                        Button("View session context") { contextSnapshot = work.context }.pointingHand()
                        Button("Reveal worktree") { NSWorkspace.shared.open(URL(fileURLWithPath: work.folder)) }.pointingHand()
                        if let source = work.linkedFrom { Button("Open original session") { library.navigate(.project(projectID, source)) }.pointingHand() }
                        if session.archived, !work.cleaned, work.isManagedWorktree { Button("Clean up worktree…") { cleanup(work) }.pointingHand() }
                    }
                    Divider()
                    Button("Rename") { name = project.name; rename = true }.pointingHand()
                    Button("Reveal in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: project.folder)) }.pointingHand()
                    if let remote = project.remote, let repository = try? GitHubGit.https(remote), let url = URL(string: "https://github.com/" + repository.name) {
                        Text("GitHub · " + repository.name)
                        Button("Open on GitHub") { NSWorkspace.shared.open(url) }.pointingHand()
                    } else {
                        Text("Local only")
                        Button("Publish to GitHub…") { publishSheet = true }.pointingHand().disabled(!project.isGitBacked)
                    }
                    Button("Locate folder…") { locate() }.pointingHand()
                    Button("Connect GitHub repository…") { remoteSheet = true }.pointingHand().disabled(!project.isGitBacked)
                    if !project.isGitBacked { Text("Git features require a Git repository.") }
                    Divider()
                    Button("Remove from Diorama") { projects.projects.removeAll { $0.id == projectID }; projects.selectedID = nil; projects.save() }.pointingHand().disabled(projects.busy.contains(projectID))
                } label: { Image(systemName: "ellipsis") }.pointingHand().menuStyle(.borderlessButton).fixedSize()
                Button("New Session") { library.navigate(.project(projectID, nil)); library.focusWorkspaceComposer() }.pointingHand()
                    .disabled(projects.busy.contains(projectID) || !project.isGitBacked)
                    .help(project.isGitBacked ? "Start a new session" : "Starting sessions in Diorama requires Git. External sessions remain viewable.")
            }.buttonStyle(.borderless).padding(.horizontal, 16).frame(height: 38).background(DioramaStyle.sidebar)
            Divider()
            ProjectWorkbench(projectID: projectID, library: library)
        }
        .sheet(isPresented: $publishSheet) { GitHubPublishView(project: project, library: library) }
        .sheet(isPresented: Binding(get: { contextSnapshot != nil }, set: { if !$0 { contextSnapshot = nil } })) {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text("This session’s Project context").font(.headline); Spacer(); Button("Done") { contextSnapshot = nil }.pointingHand() }
                Text("Captured when this session was created. Later Project edits do not change it.").foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(contextSnapshot?.instructions.isEmpty == false ? contextSnapshot!.instructions : "No additional instructions.")
                        ForEach(contextSnapshot?.references ?? [], id: \.self) { Text($0) }
                    }.textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(24).frame(width: 560, height: 420)
        }
        .sheet(isPresented: $remoteSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Connect GitHub repository").font(.title2.bold())
                Text("Add origin to this local repository. Existing remotes are never replaced.").foregroundStyle(.secondary)
                TextField("https://github.com/owner/repository.git", text: $remoteURL)
                HStack {
                    Button("Cancel") { remoteSheet = false }.pointingHand()
                    Spacer()
                    Button("Connect") { Task { do {
                        guard let url = URL(string: remoteURL), url.scheme == "https", url.host == "github.com", url.path.split(separator: "/").count == 2 else { throw AppServerFailure("Enter a GitHub repository HTTPS URL.") }
                        _ = try await ProjectCommand.git(project.folder, ["remote", "add", "origin", remoteURL])
                        projects.update(projectID) { $0.remote = remoteURL; $0.base = "origin/main" }
                        _ = try await ProjectGit.refresh(project)
                        projects.update(projectID) { $0.fetchedAt = Date() }
                        remoteSheet = false
                    } catch { projects.error = error.localizedDescription } } }.pointingHand()
                }
            }.padding(24).frame(width: 520)
        }
        .alert("Rename Project", isPresented: $rename) {
            TextField("Name", text: $name)
            Button("Save") { if !name.isEmpty { projects.update(projectID) { $0.name = name } } }.pointingHand()
            Button("Cancel", role: .cancel) {}.pointingHand()
        }
        .task(id: project.selectedSession) {
            library.selectedID = project.selectedSession
            while !Task.isCancelled {
                if !library.paused { await library.readSelected() }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
    private func locate() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.begin { response in
            if response == .OK, let url = panel.url { Task { do {
                let found = try await ProjectFolder.open(url.path)
                projects.update(projectID) { $0.folder = found.folder; $0.commonDirectory = found.commonDirectory; $0.base = found.base; $0.remote = found.remote }
            } catch { projects.error = error.localizedDescription } } }
        }
    }
    private func cleanup(_ work: ProjectWorkspace) {
        guard let id = work.threadID, library.execution.tasks[id]?.phase.active != true else { return }
        Task { do {
            _ = try await ProjectGit.refresh(project)
            try await ProjectGit.cleanup(project: project, workspace: work)
            projects.updateWorkspace(projectID, id: work.id) { $0.cleaned = true }
        } catch { projects.error = "Cleanup stopped: " + error.localizedDescription } }
    }
}

struct ProjectDraftView: View {
    let projectID: String
    @Bindable var projects: ProjectModel
    @Bindable var library: LibraryModel
    var compact = false
    var creationProjectPicker = AnyView(EmptyView())
    var creationClose = AnyView(EmptyView())
    var created: ((String, String) -> Void)? = nil
    @State private var model = UserDefaults.standard.string(forKey: "defaultAgentModel") ?? ""
    @State private var effort = ""
    @State private var approval: ApprovalReviewChoice = .inherit
    @State private var queue = false
    @State private var attachments: [ConversationAttachment] = []
    @State private var capabilities: [CapabilityInput] = []
    @State private var branches: [String] = []
    @State private var currentReference = "HEAD"
    @State private var branchSearch = ""
    @State private var showBranches = false
    @State private var showWorkspaceOptions = false
    @State private var confirmSwitch = false
    @State private var loadingStart = false
    @State private var error: String?
    private var project: DioramaProject { projects.projects.first { $0.id == projectID } ?? .unavailable }
    private var start: SessionStartOptions { project.draftStart ?? SessionStartOptions(folder: project.folder, reference: "") }
    private var prepared: ProjectWorkspace? { project.workspaces.first { $0.id == project.pendingWorkspace } }
    private var mode: String { project.draftMode ?? "default" }
    private var goal: Bool { mode != "plan" && project.draftGoal == true }
    private var modeBinding: Binding<String> {
        Binding(get: { mode }, set: { value in
            projects.update(projectID) { $0.draftMode = value; if value == "plan" { $0.draftGoal = false } }
        })
    }
    private var goalBinding: Binding<Bool> {
        Binding(get: { goal }, set: { value in
            projects.update(projectID) { $0.draftGoal = value; if value { $0.draftMode = "default" } }
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !compact { Spacer() }
            if !compact { Text("What would you like to work on?").font(.title2.bold())
            Text(start.createWorktree ? "Work in an isolated copy of the repository." : "Work directly in this folder; changes are shared with other sessions.").foregroundStyle(.secondary)
            }
            if let source = project.linkedFrom {
                Text("Linked from \(source). The handoff below is editable. Starts from the source’s committed revision; uncommitted changes stay in the original session.").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                HStack(spacing: 12) {
                if compact { creationProjectPicker }
                if !compact {
                    Button { projects.update(projectID) { $0.section = "Context" } } label: { Label("Project context", systemImage: "doc.text") }.pointingHand()
                    Spacer()
                }
                if compact {
                    Button { showWorkspaceOptions.toggle() } label: {
                        Image(systemName: "ellipsis").font(.system(size: 16, weight: .medium)).frame(width: 24, height: 24)
                    }.pointingHand().buttonStyle(HoverButtonStyle()).accessibilityLabel("Workspace options")
                        .popover(isPresented: $showWorkspaceOptions) {
                            VStack(alignment: .leading, spacing: 10) {
                                if let prepared {
                                    Label(URL(fileURLWithPath: prepared.folder).lastPathComponent, systemImage: "folder").help(prepared.folder)
                                    Text("Workspace already prepared").font(.caption).foregroundStyle(.secondary)
                                } else {
                                    HStack(spacing: 12) {
                                        Text("Target branch").foregroundStyle(.secondary)
                                        Spacer(minLength: 0)
                                        branchPicker
                                    }
                                    worktreeToggle
                                }
                            }.font(.system(size: 13)).padding(12).frame(width: 310)
                                .disabled(projects.busy.contains(projectID) || loadingStart)
                                .avatarPopoverDismissal(isPresented: $showWorkspaceOptions)
                        }
                } else if let prepared {
                    if prepared.threadID == nil {
                        Label(URL(fileURLWithPath: prepared.folder).lastPathComponent, systemImage: "folder")
                            .help(prepared.folder)
                    }
                } else {
                    if !compact { Button(action: chooseStartFolder) {
                        Label(URL(fileURLWithPath: start.folder).lastPathComponent, systemImage: "folder")
                            .lineLimit(1).truncationMode(.middle)
                    }.pointingHand().help(start.folder).accessibilityLabel("Working directory").disabled(project.linkedBase != nil) }
                    branchPicker
                    worktreeToggle
                }
                }.disabled(projects.busy.contains(projectID) || loadingStart)
                if compact { Spacer(minLength: 0); creationClose }
            }.font(.caption)
            if !compact && start.createWorktree && prepared == nil { branchNameField }
            if projects.busy.contains(projectID) { ProgressView("Preparing session…").controlSize(.small) }
            if let error {
                Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                if let pending = project.workspaces.first(where: { $0.id == project.pendingWorkspace }) {
                    if let thread = pending.threadID {
                        Button("Open prepared conversation") {
                            library.syncOwnedSessions()
                            projects.update(projectID) { $0.selectedSession = (library.execution.tasks[thread]?.provider ?? .codex).rawValue + ":" + thread }
                        }.pointingHand()
                    }
                    Button("Start a separate session instead") { projects.update(projectID) { $0.pendingWorkspace = nil }; self.error = nil }.pointingHand()
                }
            }
            ConversationComposer(controller: library.execution, model: $model, effort: $effort,
                prompt: Binding(get: { project.draft }, set: { value in projects.update(projectID) { $0.draft = value } }),
                attachments: $attachments, approvalReview: $approval, effectiveModel: "", sending: projects.busy.contains(projectID) || loadingStart, active: false,
                capabilities: $capabilities, folder: start.folder, mode: modeBinding, goalMode: goalBinding, queueMode: $queue, queueAvailable: false, creationPresentation: compact, send: requestSend)
            if !compact { Spacer() }
        }.padding(compact ? 20 : 28).frame(maxWidth: 850)
        .task {
            model = project.draftModel ?? UserDefaults.standard.string(forKey: "defaultAgentModel") ?? ""
            attachments = project.draftAttachments.compactMap { try? ConversationAttachment(url: URL(fileURLWithPath: $0)) }
            await library.execution.connect()
            await loadStart(resetReference: project.draftStart == nil)
            if compact { ComposerNSTextView.focusVisible() }

        }
        .confirmationDialog("Switch the project folder to \(start.reference)? Other tools using this folder will see the change.", isPresented: $confirmSwitch) {
            Button("Switch branch and start") { send(switchConfirmed: true) }.pointingHand()
            Button("Cancel", role: .cancel) { }.pointingHand()
        }
        .onChange(of: project.draftAttachments) {
            let saved = project.draftAttachments.compactMap { try? ConversationAttachment(url: URL(fileURLWithPath: $0)) }
            if saved != attachments { attachments = saved }
        }
        .onChange(of: model) { projects.update(projectID) { $0.draftModel = model } }
        .onChange(of: attachments) { projects.update(projectID) { $0.draftAttachments = attachments.map { $0.url.path } } }
    }
    private var branchPicker: some View {
                    Button { showBranches = true } label: {
                        Label(start.reference == "HEAD" ? "Current revision" : start.reference, systemImage: "arrow.triangle.branch")
                            .lineLimit(1).truncationMode(.middle)
                    }.pointingHand().buttonStyle(HoverButtonStyle()).help("Branch to start from").disabled(project.linkedBase != nil)
                    .popover(isPresented: $showBranches) {
                        BranchSelectionPopover(branches: (currentReference == "HEAD" ? ["HEAD"] : []) + branches,
                            selected: start.reference, search: $branchSearch) { branch in
                                projects.update(projectID) { $0.draftStart?.reference = branch }
                                showBranches = false
                            }
                            .avatarPopoverDismissal(isPresented: $showBranches)
                    }

    }
    private var worktreeToggle: some View {
                    Toggle("Create new worktree", isOn: Binding(get: { start.createWorktree }, set: { value in
                        projects.update(projectID) { $0.draftStart?.createWorktree = value }
                        Task { await loadStart(resetReference: true) }
                    })).pointingHand().modifier(HoverControlSurface()).disabled(project.linkedBase != nil)
    }
    private var branchNameField: some View {
        VStack(alignment: .leading, spacing: 6) {
                TextField("New branch name", text: Binding(get: { start.branchName ?? DescriptiveBranch.suggestion(project.draft) ?? "" }, set: { value in
                    projects.update(projectID) { $0.draftStart = $0.draftStart ?? start; $0.draftStart?.branchName = value }
                })).textFieldStyle(.roundedBorder).accessibilityLabel("New branch name").disabled(loadingStart || projects.busy.contains(projectID))
                Text("1–6 lowercase words, separated by hyphens. Existing names get a numeric suffix.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func loadStart(resetReference: Bool) async {
        loadingStart = true
        defer { loadingStart = false }
        do {
            let folder = start.folder
            branches = compact && start.createWorktree ? try await ProjectGit.startBranches(folder) : try await ProjectGit.localBranches(folder)
            currentReference = await ProjectGit.currentBranch(folder)
            var options = start
            if resetReference || options.reference.isEmpty {
                if let linked = project.linkedBase { options.reference = linked; options.createWorktree = true }
                else if options.createWorktree { options.reference = compact ? try await ProjectGit.defaultStartReference(folder) : try await ProjectGit.defaultLocalReference(folder) }
                else { options.reference = await ProjectGit.currentBranch(folder) }
            }
            projects.update(projectID) { $0.draftStart = options }
            error = nil
        } catch { self.error = "Choose a Git project with at least one commit. " + error.localizedDescription }
    }
    private func chooseStartFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: start.folder)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                do {
                    let found = try await ProjectGit.discover(url.path)
                    _ = try await ProjectGit.localBranches(found.folder)
                    if !projects.projects.contains(where: { $0.commonDirectory == found.commonDirectory }) {
                        projects.projects.append(found); projects.save()
                    }
                    projects.update(projectID) { $0.draftStart = SessionStartOptions(folder: url.resolvingSymlinksInPath().path, reference: "", createWorktree: start.createWorktree) }
                    await loadStart(resetReference: true)
                } catch { self.error = "Choose a Git project with at least one commit. " + error.localizedDescription }
            }
        }
    }
    private func requestSend() {
        guard !loadingStart else { return }
        Task {
            if prepared == nil, !start.createWorktree, await ProjectGit.currentBranch(start.folder) != start.reference {
                confirmSwitch = true
            } else { send() }
        }
    }
    private func send(switchConfirmed: Bool = false) {

        guard !projects.busy.contains(projectID) else { return }
        projects.busy.insert(projectID); error = nil
        let prompt = project.draft, files = attachments, selectedBase = project.linkedBase ?? start.reference
        var options = start
        options.reference = selectedBase
        if project.linkedBase != nil { options.createWorktree = true }
        if options.createWorktree && prepared == nil {
            options.branchName = compact ? (DescriptiveBranch.suggestion(prompt) ?? "work-session") : (options.branchName ?? DescriptiveBranch.suggestion(prompt))
            guard let branch = options.branchName, DescriptiveBranch.valid(branch) else {
                error = "Enter a descriptive branch name using 1–6 lowercase words separated by hyphens."
                projects.busy.remove(projectID)
                return
            }
        }
        let linkedFrom = project.linkedFrom, selectedMode = mode, selectedGoal = goal
        Task {
            defer { projects.busy.remove(projectID) }
            do {
                _ = try ConversationAttachment.input(prompt: prompt, attachments: files)
                let work = try await projects.prepare(projectID: projectID, base: selectedBase, cached: true, options: options, switchConfirmed: switchConfirmed, activeFolders: Set(library.execution.tasks.values.filter { $0.phase.active }.map(\.folder)))
                guard !work.deliveryAttempted else { throw AppServerFailure("Previous message delivery needs review. Open the prepared conversation and check its history; Retry will not resend it.") }
                guard !work.creationUncertain else { throw AppServerFailure("A previous task creation has an unknown outcome. Inspect Imported activity before starting again. Your draft and worktree are preserved.") }
                await library.execution.connect()
                await library.execution.loadModes()
                guard library.execution.connected else { throw AppServerFailure(library.execution.error ?? "Could not connect to Codex") }
                var thread = work.threadID
                if thread == nil {
                    projects.updateWorkspace(projectID, id: work.id) { $0.creationUncertain = true }
                    try projects.checkpoint()
                    do { thread = try await library.execution.prepare(folder: work.folder, title: prompt, model: model, projectContext: work.context.prompt(folder: work.folder, commit: work.baseCommit), permission: approval) }
                    catch let failure as ExecutionRPCRejection {
                        projects.updateWorkspace(projectID, id: work.id) { $0.creationUncertain = false }
                        throw failure
                    }
                    projects.updateWorkspace(projectID, id: work.id) { $0.threadID = thread; $0.creationUncertain = false; $0.linkedFrom = linkedFrom }
                }
                guard let thread else { return }
                if library.execution.tasks[thread]?.attached != true {
                    guard let session = library.sessions.first(where: { $0.sessionID == thread }) else { throw AppServerFailure("Refresh Imported activity to reconnect this prepared session.") }
                    try await library.execution.resumeImported(session)
                }
                guard let actualFolder = library.execution.tasks[thread]?.folder,
                      URL(fileURLWithPath: actualFolder).resolvingSymlinksInPath() == URL(fileURLWithPath: work.folder).resolvingSymlinksInPath() else {
                    throw AppServerFailure("The prepared conversation’s working folder changed. Open it to inspect before sending.")
                }
                try projects.checkpoint()
                let combined = prompt
                _ = try ConversationAttachment.input(prompt: combined, attachments: files)
                projects.updateWorkspace(projectID, id: work.id) { $0.deliveryAttempted = true }
                try projects.checkpoint()
                do {
                    try await library.execution.sendWithGoal(id: thread, prompt: combined, model: model, effort: effort, attachments: files, approvalReview: approval, mode: selectedMode, capabilities: capabilities, goal: selectedGoal)
                } catch let failure as ExecutionRPCRejection {
                    projects.updateWorkspace(projectID, id: work.id) { $0.deliveryAttempted = false }
                    throw failure
                }
                library.syncOwnedSessions()
                let selected = (library.execution.tasks[thread]?.provider ?? .codex).rawValue + ":" + thread
                projects.update(projectID) { $0.draft = ""; $0.draftAttachments = []; $0.draftModel = nil; $0.draftStart = nil; $0.draftMode = nil; $0.draftGoal = nil; $0.linkedFrom = nil; $0.linkedBase = nil; $0.pendingWorkspace = nil; $0.selectedSession = selected }
                library.saveDraft(selected, text: "", attachments: [], mode: selectedMode)
                if let destination = try? await ProjectGit.discover(options.folder),
                   let target = projects.projects.first(where: { $0.commonDirectory == destination.commonDirectory }), target.id != projectID {
                    let completed = projects.projects.first(where: { $0.id == projectID })?.workspaces.first(where: { $0.id == work.id })
                    projects.update(projectID) { $0.workspaces.removeAll { $0.id == work.id }; $0.selectedSession = nil }
                    projects.update(target.id) { if let completed { $0.workspaces.append(completed) }; $0.selectedSession = selected }
                    library.navigate(.project(target.id, selected))
                }
                library.selectedID = selected; attachments = []
                created?(projects.projects.first(where: { $0.workspaces.contains(where: { $0.id == work.id }) })?.id ?? projectID, selected)
            } catch { self.error = error.localizedDescription }
        }
    }
}

private struct HistoryPresentationIdentity: Equatable { let session: String?; let active: Bool }
