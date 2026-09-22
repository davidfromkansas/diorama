import SwiftUI
import Observation
import DioramaCore

@Observable
final class ProjectModel {
    var projects: [DioramaProject] = []
    var selectedID: String? = UserDefaults.standard.string(forKey: "selectedProject") {
        didSet { if storageURL == ProjectStorage.file { UserDefaults.standard.set(selectedID, forKey: "selectedProject") } }
    }
    var error: String?
    var busy = Set<String>()
    var associations: [String: String] = [:]
    var storageReadable = true
    let storageURL: URL
    init(storageURL: URL = ProjectStorage.file) {
        self.storageURL = storageURL
        do { projects = try ProjectStorage.load(from: storageURL) }
        catch { self.error = "Projects could not be loaded. The saved file has not been overwritten: \(error.localizedDescription)"; storageReadable = false }
    }
    var selected: DioramaProject? { projects.first { $0.id == selectedID } }
    func checkpoint() throws {
        guard storageReadable else { throw AppServerFailure("Project storage is unavailable; restore the saved file before creating work.") }
        try ProjectStorage.save(projects, to: storageURL)
    }
    func save() {
        guard storageReadable else { return }
        do { try ProjectStorage.save(projects, to: storageURL) } catch { self.error = "Could not save Projects: \(error.localizedDescription)" }
    }
    func update(_ id: String, _ body: (inout DioramaProject) -> Void) {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return }
        body(&projects[i]); save()
    }
    func add(_ project: DioramaProject) {
        if let existing = projects.first(where: { $0.commonDirectory == project.commonDirectory }) { selectedID = existing.id; return }
        projects.append(project); selectedID = project.id; save()
    }
    func sessions(_ project: DioramaProject, library: LibraryModel) -> [Session] {
        let paths = Set([project.folder] + project.workspaces.map(\.folder))
        let ids = Set(project.workspaces.compactMap(\.threadID))
        return library.sessions.filter { ids.contains($0.sessionID) || paths.contains($0.project) || associations[$0.project] == project.commonDirectory }
    }
    func associate(_ sessions: [Session]) async {
        for path in Set(sessions.map(\.project)).filter({ $0.hasPrefix("/") && associations[$0] == nil }) {
            guard !Task.isCancelled else { return }
            if let project = try? await ProjectGit.discover(path) { associations[path] = project.commonDirectory }
            else { associations[path] = "unavailable" }
        }
    }
    func prepare(projectID: String, base: String, cached: Bool) async throws -> ProjectWorkspace {
        guard let initial = projects.first(where: { $0.id == projectID }) else { throw AppServerFailure("Project unavailable") }
        let id = initial.pendingWorkspace ?? UUID().uuidString
        update(projectID) { $0.pendingWorkspace = id }
        try checkpoint()
        if let existing = initial.workspaces.first(where: { $0.id == id }) { return existing }
        let workspace = try await ProjectGit.createWorkspace(project: initial, id: id, base: base.isEmpty ? nil : base, useCached: cached)
        update(projectID) {
            $0.workspaces.append(workspace)
            if !cached { $0.fetchedAt = Date() }
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
    @State private var projectQuery = ""
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Projects").font(.title2.bold())
                    Spacer()
                    Menu { addActions } label: { Image(systemName: "plus") }.menuStyle(.borderlessButton).fixedSize().help("Add Project")
                }.padding(.horizontal, 16).padding(.top, 14)
                List(selection: $projects.selectedID) {
                    ForEach(projects.projects.filter { projectQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(projectQuery) }) { project in
                        HStack {
                            Label(project.name, systemImage: "folder")
                            Spacer()
                            if projects.sessions(project, library: library).contains(where: { library.needsAttention($0) }) {
                                Image(systemName: "exclamationmark.circle").foregroundStyle(.orange).accessibilityLabel("Needs attention")
                            } else if projects.sessions(project, library: library).contains(where: { library.isWorking($0) }) {
                                Image(systemName: "circle.dotted").foregroundStyle(.secondary).accessibilityLabel("Working")
                            }
                        }.tag(project.id).help(project.folder)
                    }
                    Section {
                        Label("Imported activity", systemImage: "tray.full").tag("imported")
                    }
                }.searchable(text: $projectQuery, prompt: "Find a Project")
            }.navigationSplitViewColumnWidth(min: 180, ideal: 230, max: 320)
        } detail: {
            if projects.selectedID == "imported" { LibraryView(model: library) }
            else if let project = projects.selected {
                ProjectDetailView(projectID: project.id, projects: projects, library: library).id(project.id)
            } else {
                ContentUnavailableView {
                    Label("Your work starts with a Project", systemImage: "folder")
                } description: { Text("Bring sessions, files, and shared context together around a repository.") }
                actions: { HStack { addActions } }
            }
        }
        .sheet(isPresented: Binding(get: { addMode != nil }, set: { if !$0 { addMode = nil } })) {
            AddProjectView(mode: addMode ?? "New Project", projects: projects)
        }
        .alert("Projects", isPresented: Binding(get: { projects.error != nil }, set: { if !$0 { projects.error = nil } })) {
            Button("OK") { projects.error = nil }
        } message: { Text(projects.error ?? "") }
        .alert("Rename conversation", isPresented: Binding(get: { library.projectNavigation && library.renameSession != nil }, set: { if !$0 { library.renameSession = nil } })) {
            TextField("Name", text: $library.renameText)
            Button("Save") { if let session = library.renameSession { library.renameConversation(session) } }
            Button("Cancel", role: .cancel) { library.renameSession = nil }
        }
        .alert("Archive or restore conversation?", isPresented: Binding(get: { library.projectNavigation && library.archiveSession != nil }, set: { if !$0 { library.archiveSession = nil } })) {
            Button("Continue") { if let session = library.archiveSession { library.archiveConversation(session) } }
            Button("Cancel", role: .cancel) { library.archiveSession = nil }
        } message: { Text("Working files and branches are retained. Cleanup is a separate action.") }
        .alert("Conversation action", isPresented: Binding(get: { library.projectNavigation && library.workflowError != nil }, set: { if !$0 { library.workflowError = nil } })) {
            Button("OK") { library.workflowError = nil }
        } message: { Text(library.workflowError ?? "") }
        .onChange(of: library.execution.tasks.keys.sorted()) { library.syncOwnedSessions() }
        .onChange(of: projects.selectedID, initial: true) { library.projectNavigation = projects.selectedID != "imported" }
        .onChange(of: library.showNewTask) {
            if library.showNewTask {
                library.showNewTask = false
                if let id = projects.selected?.id { projects.update(id) { $0.section = "Sessions"; $0.selectedSession = nil } }
                else { projects.selectedID = nil }
                library.selectedID = nil
            }
        }
        .task {
            library.beginWatching()
            while !Task.isCancelled {
                if projects.selectedID != "imported", !library.paused { await library.refresh() }
                await projects.associate(library.sessions)
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
    }
    @ViewBuilder private var addActions: some View {
        Button("Open project…") {
            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    Task { do { projects.add(try await ProjectGit.discover(url.path)) } catch { projects.error = error.localizedDescription } }
                }
            }
        }
        Button("Open GitHub project…") { addMode = "Open GitHub project" }
        Button("New Project…") { addMode = "New Project" }
    }
}

struct AddProjectView: View {
    let mode: String
    @Bindable var projects: ProjectModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var repository = ""
    @State private var parent = UserDefaults.standard.string(forKey: "projectParent") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/ChatGPT").path
    @State private var publish = false
    @State private var visibility = "private"
    @State private var error: String?
    @State private var operation: Task<Void, Never>?
    @State private var local: DioramaProject?
    @State private var repositories: [String] = []
    @State private var searching = false
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
                            let result = try await ProjectCommand.gh(["repo", "list", "--limit", "100", "--json", "nameWithOwner", "--jq", ".[].nameWithOwner"])
                            repositories = result.split(separator: "\n").map(String.init)
                        } catch { self.error = error.localizedDescription }
                    }
                }.disabled(searching)
                if !repositories.isEmpty {
                    ScrollView { VStack(alignment: .leading) {
                        ForEach(repositories.filter { repository.isEmpty || $0.localizedCaseInsensitiveContains(repository) }, id: \.self) { repo in
                            Button(repo) { repository = repo; name = repo.split(separator: "/").last.map(String.init) ?? "" }.buttonStyle(.plain)
                        }
                    }}.frame(maxHeight: 140)
                }
            }
            TextField("Project name", text: $name).disabled(local != nil)
            HStack { TextField("Location", text: $parent).textFieldStyle(.roundedBorder).disabled(local != nil); Button("Choose location…") {
                let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                panel.begin { if $0 == .OK, let url = panel.url { parent = url.path } }
            }.disabled(local != nil) }
            Text(URL(fileURLWithPath: parent).appendingPathComponent(name).path).font(.caption).foregroundStyle(.secondary)
            if mode == "New Project" {
                Toggle("Publish to GitHub", isOn: $publish)
                if publish {
                    TextField("GitHub owner/repository", text: $repository)
                    Picker("Visibility", selection: $visibility) { Text("Private").tag("private"); Text("Public").tag("public") }
                }
                Text("Creates an empty initial commit on main. Publishing pushes this initial branch.").font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            HStack {
                Button("Cancel") { operation?.cancel(); dismiss() }
                Spacer()
                if operation != nil { ProgressView().controlSize(.small) }
                Button(local != nil ? "Retry publishing" : mode == "New Project" ? (publish ? "Create and publish" : "Create") : "Clone and open") { start() }
                    .buttonStyle(.borderedProminent).disabled(operation != nil || name.isEmpty || name.contains("/") || name == "." || name == "..")
            }
        }.padding(24).frame(width: 560).onDisappear { operation?.cancel() }
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
                    project = try await ProjectGit.initialize(path); local = project; projects.add(project)
                } else {
                    guard !repository.hasPrefix("-"), !repository.isEmpty else { throw AppServerFailure("Choose a GitHub repository.") }
                    guard !FileManager.default.fileExists(atPath: path) else { throw AppServerFailure("Destination already exists. Choose another name or use Open project.") }
                    _ = try await ProjectCommand.gh(["repo", "clone", repository, path])
                    project = try await ProjectGit.discover(path)
                }
                if publish {
                    guard !repository.isEmpty, !repository.hasPrefix("-") else { throw AppServerFailure("Enter the GitHub owner/repository. Your local Project is ready.") }
                    let origin = try? await ProjectCommand.git(project.folder, ["remote", "get-url", "origin"])
                    if origin == nil { _ = try await ProjectCommand.gh(["repo", "create", repository, "--" + visibility, "--source", project.folder, "--remote", "origin"]) }
                    _ = try await ProjectCommand.git(project.folder, ["push", "-u", "origin", "main"])
                    let discovered = try await ProjectGit.discover(project.folder)
                    project.remote = discovered.remote; project.base = "origin/main"
                    projects.update(project.id) { $0.remote = project.remote; $0.base = project.base }
                }
                UserDefaults.standard.set(parent, forKey: "projectParent")
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
    @State private var query = ""
    @State private var showArchived = false
    @State private var showSessionList = false
    @State private var contextSnapshot: ProjectContext?
    @State private var remoteSheet = false
    @State private var remoteURL = ""
    private var project: DioramaProject { projects.projects.first { $0.id == projectID } ?? .unavailable }
    private var section: Binding<String> { Binding(get: { project.section }, set: { value in projects.update(projectID) { $0.section = value } }) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(project.name).font(.title2.bold())
                Spacer()
                Menu {
                    Button("Rename") { name = project.name; rename = true }
                    Button("Reveal in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: project.folder)) }
                    Button("Open on GitHub") { Task { do {
                        let url = try await ProjectCommand.gh(["repo", "view", "--json", "url", "--jq", ".url"], folder: project.folder)
                        if let link = URL(string: url) { NSWorkspace.shared.open(link) }
                    } catch { projects.error = error.localizedDescription } } }
                    Button("Locate folder…") { locate() }
                    Button("Connect GitHub repository…") { remoteSheet = true }
                    Divider()
                    Button("Remove from Diorama") { projects.projects.removeAll { $0.id == projectID }; projects.selectedID = nil; projects.save() }.disabled(projects.busy.contains(projectID))
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                Button("New Session") { projects.update(projectID) { $0.section = "Sessions"; $0.selectedSession = nil }; library.selectedID = nil }
                    .disabled(projects.busy.contains(projectID))
            }.padding(20)
            Picker("Project section", selection: section) {
                ForEach(["Sessions", "Pull Requests", "Files", "Context"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 20).padding(.bottom, 14)
            Divider()
            switch project.section {
            case "Context": ProjectContextView(projectID: projectID, projects: projects)
            case "Files": ProjectFilesView(projectID: projectID, projects: projects, library: library)
            case "Pull Requests": LinkedProjectPRView(projectID: projectID, library: library)
            default: sessions
            }
        }
        .sheet(isPresented: Binding(get: { contextSnapshot != nil }, set: { if !$0 { contextSnapshot = nil } })) {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text("This session’s Project context").font(.headline); Spacer(); Button("Done") { contextSnapshot = nil } }
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
                    Button("Cancel") { remoteSheet = false }
                    Spacer()
                    Button("Connect") { Task { do {
                        guard let url = URL(string: remoteURL), url.scheme == "https", url.host == "github.com", url.path.split(separator: "/").count == 2 else { throw AppServerFailure("Enter a GitHub repository HTTPS URL.") }
                        _ = try await ProjectCommand.git(project.folder, ["remote", "add", "origin", remoteURL])
                        projects.update(projectID) { $0.remote = remoteURL; $0.base = "origin/main" }
                        _ = try await ProjectGit.refresh(project)
                        projects.update(projectID) { $0.fetchedAt = Date() }
                        remoteSheet = false
                    } catch { projects.error = error.localizedDescription } } }
                }
            }.padding(24).frame(width: 520)
        }
        .alert("Rename Project", isPresented: $rename) {
            TextField("Name", text: $name)
            Button("Save") { if !name.isEmpty { projects.update(projectID) { $0.name = name } } }
            Button("Cancel", role: .cancel) {}
        }
        .task(id: project.selectedSession) {
            library.selectedID = project.selectedSession
            while !Task.isCancelled {
                await library.readSelected()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
    private var sessions: some View {
        GeometryReader { geometry in
            if geometry.size.width < 720 {
                VStack(alignment: .leading, spacing: 0) {
                    Button(showSessionList ? "Back to conversation" : "Sessions") { showSessionList.toggle() }.padding(12)
                    if showSessionList { sessionList.frame(maxWidth: .infinity) } else { sessionContent }
                }
            } else {
                HSplitView { sessionList; sessionContent }
            }
        }
    }
    private var sessionList: some View {
            VStack(spacing: 10) {
                TextField("Find a session", text: $query).textFieldStyle(.roundedBorder).padding(.horizontal, 12).padding(.top, 12)
                Toggle("Show archived", isOn: $showArchived).font(.caption).padding(.horizontal, 12)
                List(selection: Binding(get: { project.selectedSession }, set: { value in
                    projects.update(projectID) { $0.selectedSession = value; $0.fileLocation = nil; $0.fileSelection = nil }; library.selectedID = value; showSessionList = false
                })) {
                    ForEach(SessionPresentation.rows(projects.sessions(project, library: library).filter {
                        (showArchived || !$0.archived) && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query))
                    }, showInternal: false)) { row in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(markdownTitle(row.session.title)).lineLimit(2)
                            Text(row.session.provider.rawValue + (row.session.archived ? " · Archived" : "")).font(.caption).foregroundStyle(.secondary)
                            if library.isWorking(row.session) { Text("Working").font(.caption).foregroundStyle(.secondary) }
                            if library.needsAttention(row.session) { Text("Needs attention").font(.caption).foregroundStyle(.orange) }
                        }.padding(.leading, CGFloat(row.depth) * 10).tag(row.session.id)
                    }
                }
            }.frame(minWidth: 170, idealWidth: 230, maxWidth: 300)
    }
    private var sessionContent: some View {
            VStack(spacing: 0) {
                if let session = library.sessions.first(where: { $0.id == project.selectedSession }) {
                    HStack {
                        if let work = project.workspaces.first(where: { $0.threadID == session.sessionID }) {
                            Menu {
                                if let source = work.linkedFrom { Button("Open original session") { projects.update(projectID) { $0.selectedSession = source }; library.selectedID = source } }
                                Text(work.branch)
                                Text(work.folder)
                                Text("Base: " + String(work.baseCommit.prefix(10)))
                                Text("Context revision: " + work.context.revision)
                                Button("Reveal worktree") { NSWorkspace.shared.open(URL(fileURLWithPath: work.folder)) }
                                if session.archived, !work.cleaned {
                                    Button("Clean up worktree…") { cleanup(work) }
                                }
                            } label: { Label("codex/…" + String(work.branch.suffix(8)), systemImage: "arrow.triangle.branch") }.fixedSize()
                        }
                        Spacer()
                        Menu("Project context") {
                            if let snapshot = project.workspaces.first(where: { $0.threadID == session.sessionID })?.context {
                                Button("View this session’s context") { contextSnapshot = snapshot }
                            }
                            Button("Edit shared context") { section.wrappedValue = "Context" }
                        }.fixedSize()
                    }.font(.caption).padding(.horizontal, 20).padding(.top, 10)
                    if let work = project.workspaces.first(where: { $0.threadID == session.sessionID }) {
                        SessionReviewContainer(session: session, workspaceID: work.id, projectID: projectID, library: library, review: library.reviews.state(work.id)).id(session.id)
                    } else { SessionView(session: session, model: library).id(session.id) }
                } else {
                    ProjectDraftView(projectID: projectID, projects: projects, library: library)
                }
            }.frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
    }
    private func locate() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.begin { response in
            if response == .OK, let url = panel.url { Task { do {
                let found = try await ProjectGit.discover(url.path)
                projects.update(projectID) { $0.folder = found.folder; $0.commonDirectory = found.commonDirectory }
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
    @State private var model = UserDefaults.standard.string(forKey: "defaultAgentModel") ?? ""
    @State private var effort = ""
    @State private var approval: ApprovalReviewChoice = .inherit
    @State private var queue = false
    @State private var attachments: [ConversationAttachment] = []
    @State private var capabilities: [CapabilityInput] = []
    @State private var base = ""
    @State private var branches: [String] = []
    @State private var cached = false
    @State private var error: String?
    private var project: DioramaProject { projects.projects.first { $0.id == projectID } ?? .unavailable }
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
            Spacer()
            Text("What would you like to work on?").font(.title2.bold())
            Text("A new session gets its own branch and working files.").foregroundStyle(.secondary)
            if let source = project.linkedFrom {
                Text("Linked from \(source). The handoff below is editable. Starts from the source’s committed revision; uncommitted changes stay in the original session.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button { projects.update(projectID) { $0.section = "Context" } } label: { Label("Project context", systemImage: "doc.text") }
                Spacer()
                Picker("Start from", selection: $base) {
                    Text(project.base).tag("")
                    ForEach(branches.filter { $0 != project.base }, id: \.self) { Text($0).tag($0) }
                }.frame(maxWidth: 260).disabled(project.pendingWorkspace != nil)
            }.font(.caption)
            if projects.busy.contains(projectID) { ProgressView("Preparing session…").controlSize(.small) }
            if let error {
                Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                if project.remote != nil { Toggle("Use last fetched revision on retry", isOn: $cached).font(.caption) }
                if let pending = project.workspaces.first(where: { $0.id == project.pendingWorkspace }) {
                    if let thread = pending.threadID {
                        Button("Open prepared conversation") {
                            library.syncOwnedSessions()
                            projects.update(projectID) { $0.selectedSession = (library.execution.tasks[thread]?.provider ?? .codex).rawValue + ":" + thread }
                        }
                    }
                    Button("Start a separate session instead") { projects.update(projectID) { $0.pendingWorkspace = nil }; self.error = nil }
                }
            }
            ConversationComposer(controller: library.execution, model: $model, effort: $effort,
                prompt: Binding(get: { project.draft }, set: { value in projects.update(projectID) { $0.draft = value } }),
                attachments: $attachments, approvalReview: $approval, effectiveModel: "", sending: projects.busy.contains(projectID), active: false,
                capabilities: $capabilities, folder: project.folder, mode: modeBinding, goalMode: goalBinding, queueMode: $queue, queueAvailable: false, send: send)
            Spacer()
        }.padding(28).frame(maxWidth: 850)
        .task {
            model = project.draftModel ?? UserDefaults.standard.string(forKey: "defaultAgentModel") ?? ""
            attachments = project.draftAttachments.compactMap { try? ConversationAttachment(url: URL(fileURLWithPath: $0)) }
            await library.execution.connect()
            if let result = try? await ProjectCommand.git(project.folder, ["for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes"]) {
                branches = result.split(separator: "\n").map(String.init).filter { !$0.hasSuffix("/HEAD") }
            }
        }
        .onChange(of: model) { projects.update(projectID) { $0.draftModel = model } }
        .onChange(of: attachments) { projects.update(projectID) { $0.draftAttachments = attachments.map { $0.url.path } } }
    }
    private func send() {
        guard !projects.busy.contains(projectID) else { return }
        projects.busy.insert(projectID); error = nil
        let prompt = project.draft, files = attachments, selectedBase = project.linkedBase ?? base, useCached = project.linkedBase != nil || cached
        let linkedFrom = project.linkedFrom, selectedMode = mode, selectedGoal = goal
        Task {
            defer { projects.busy.remove(projectID) }
            do {
                _ = try ConversationAttachment.input(prompt: prompt, attachments: files)
                let work = try await projects.prepare(projectID: projectID, base: selectedBase, cached: useCached)
                guard !work.deliveryAttempted else { throw AppServerFailure("Previous message delivery needs review. Open the prepared conversation and check its history; Retry will not resend it.") }
                guard !work.creationUncertain else { throw AppServerFailure("A previous task creation has an unknown outcome. Inspect Imported activity before starting again. Your draft and worktree are preserved.") }
                await library.execution.connect()
                await library.execution.loadModes()
                guard library.execution.connected else { throw AppServerFailure(library.execution.error ?? "Could not connect to Codex") }
                var thread = work.threadID
                if thread == nil {
                    projects.updateWorkspace(projectID, id: work.id) { $0.creationUncertain = true }
                    try projects.checkpoint()
                    do { thread = try await library.execution.prepare(folder: work.folder, title: prompt, model: model, projectContext: work.context.prompt(folder: work.folder, commit: work.baseCommit)) }
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
                projects.update(projectID) { $0.draft = ""; $0.draftAttachments = []; $0.draftModel = nil; $0.draftMode = nil; $0.draftGoal = nil; $0.linkedFrom = nil; $0.linkedBase = nil; $0.pendingWorkspace = nil; $0.selectedSession = selected }
                library.saveDraft(selected, text: "", attachments: [], mode: selectedMode)
                library.selectedID = selected; attachments = []
            } catch { self.error = error.localizedDescription }
        }
    }
}
