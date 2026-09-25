import SwiftUI
import DioramaCore

struct ProjectContextView: View {
    let projectID: String
    @Bindable var projects: ProjectModel
    @State private var reference = ""
    @State private var notice: String?
    @State private var refreshing = false
    @State private var missing = Set<String>()
    private var project: DioramaProject { projects.projects.first { $0.id == projectID } ?? .unavailable }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Shared context for every new session").font(.title2.bold())
                Text("New sessions use the local starting branch you choose, these instructions, and references. Existing sessions keep the context they started with.")
                    .foregroundStyle(.secondary)
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Repository", systemImage: "folder").font(.headline)
                            Spacer()
                            Button(refreshing ? "Refreshing…" : "Fetch from remote") { refresh() }.disabled(refreshing)
                        }
                        Text(project.folder).textSelection(.enabled)
                        TextField("Remote comparison base", text: Binding(get: { project.base }, set: { value in projects.update(projectID) { $0.base = value } }))
                        if let date = project.fetchedAt { Text("Last fetched \(date.formatted())").font(.caption).foregroundStyle(.secondary) }
                        else { Text("New sessions start from local commits. Fetch explicitly to update remote information.").font(.caption).foregroundStyle(.secondary) }
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Instructions").font(.headline)
                    Text("What should agents know when working on this Project?").foregroundStyle(.secondary)
                    TextEditor(text: Binding(get: { project.context.instructions }, set: { value in
                        projects.update(projectID) { $0.context.instructions = value; $0.context.revision = UUID().uuidString }
                    })).font(.body).frame(minHeight: 170).padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    Text(projects.error == nil ? "Saved locally in Diorama" : "Changes could not be saved").font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("References").font(.headline)
                    Text("Add a repository-relative file path or a web link. Agents read these as needed.").foregroundStyle(.secondary)
                    ForEach(project.context.references, id: \.self) { ref in
                        HStack {
                            VStack(alignment: .leading) {
                                Label(ref, systemImage: ref.hasPrefix("http") ? "link" : "doc").textSelection(.enabled)
                                if missing.contains(ref) { Text("Not found in the current base revision").font(.caption).foregroundStyle(.orange) }
                            }
                            Spacer()
                            Button { projects.update(projectID) { $0.context.references.removeAll { $0 == ref }; $0.context.revision = UUID().uuidString } } label: { Image(systemName: "minus.circle") }.help("Remove reference")
                        }
                    }
                    HStack {
                        TextField("docs/spec.md or https://…", text: $reference)
                        Button("Add reference") { add() }.disabled(reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if let notice { Text(notice).foregroundStyle(.orange).textSelection(.enabled) }
            }.padding(28).frame(maxWidth: 840, alignment: .leading).frame(maxWidth: .infinity)
        }
        .task(id: project.base + project.context.references.joined()) {
            let refs = project.context.references.filter { !$0.hasPrefix("http://") && !$0.hasPrefix("https://") }
            if let paths = try? await ProjectGit.files(folder: project.folder, revision: project.base) {
                if !Task.isCancelled { missing = Set(refs).subtracting(paths) }
            }
        }
    }
    private func add() {
        let ref = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if ref.hasPrefix("https://") || ref.hasPrefix("http://") {
            guard URL(string: ref)?.host != nil else { notice = "Enter a valid web link."; return }
        } else {
            guard !ref.hasPrefix("/"), !ref.split(separator: "/").contains(".."), !ref.hasPrefix("~"), !ref.contains(":") else {
                notice = "Choose a path inside the repository, relative to its root."; return
            }
        }
        projects.update(projectID) {
            if !$0.context.references.contains(ref) { $0.context.references.append(ref); $0.context.revision = UUID().uuidString }
        }
        reference = ""; notice = nil
    }
    private func refresh() {
        refreshing = true; notice = nil
        Task {
            defer { refreshing = false }
            do { _ = try await ProjectGit.refresh(project); projects.update(projectID) { $0.fetchedAt = Date() } }
            catch { notice = error.localizedDescription }
        }
    }
}

struct ProjectFilesView: View {
    let projectID: String
    @Bindable var projects: ProjectModel
    @Bindable var library: LibraryModel
    var inspectorOnly = false
    var openDocument: ((WorkspaceDocument) -> Void)? = nil
    @State private var location = "base"
    @State private var query = ""
    @State private var files: [String] = []
    @State private var tree: [ProjectFileNode] = []
    @State private var selection: String?
    @State private var preview = ""
    @State private var image: NSImage?
    @State private var error: String?
    @State private var revision: String?
    @State private var loading = false
    @State private var showIgnored = false
    private var project: DioramaProject { projects.projects.first { $0.id == projectID } ?? .unavailable }
    private var work: ProjectWorkspace? { project.workspaces.first { $0.id == location && !$0.cleaned } }
    private var folder: String { work?.folder ?? project.folder }
    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                fileControls
                VStack(alignment: .leading, spacing: 8) { locationPicker; fileOptions }
            }.padding(12)
            if let error { Text(error).foregroundStyle(.orange).padding(.horizontal, 16).textSelection(.enabled) }
            if inspectorOnly { fileList } else {
            HSplitView {
                fileList.frame(minWidth: 200, idealWidth: 280, maxWidth: 420)
                filePreview
            }
            }
        }
        .onAppear {
            if let saved = project.fileLocation { location = saved }
            else if let selected = project.selectedSession, let work = project.workspaces.first(where: { library.sessions.first(where: { $0.id == selected })?.sessionID == $0.threadID && !$0.cleaned }) { location = work.id }
        }
        .onChange(of: location) { projects.update(projectID) { $0.fileLocation = location; $0.fileSelection = nil } }
        .onChange(of: selection) {
            if let selection {
                projects.update(projectID) { $0.fileSelection = selection }
                if inspectorOnly { openDocument?(WorkspaceDocument(folder: folder, path: selection, revision: revision)) }
            }
        }
        .task(id: location + String(showIgnored)) { await load() }
        .task(id: selection) { await loadPreview() }
    }
    private var locationPicker: some View {
                Picker("Files from", selection: $location) {
                    Text("Project base · " + project.base).tag("base")
                    ForEach(project.workspaces.filter { !$0.cleaned }) { work in Text(work.branch).tag(work.id) }
                }.labelsHidden().frame(maxWidth: .infinity)
    }
    private var fileOptions: some View {
        HStack {
            Toggle("Show ignored", isOn: $showIgnored).disabled(location == "base")
            Spacer()
            Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }.help("Refresh files").disabled(loading)
        }.controlSize(.small)
    }
    private var fileControls: some View { HStack { locationPicker; fileOptions } }
    private var fileList: some View {
        VStack {
            TextField("Find a file", text: $query).textFieldStyle(.roundedBorder).padding(12)
            if loading { ProgressView().controlSize(.small) }
            List(selection: $selection) {
                if query.isEmpty {
                    ProjectFileRows(nodes: tree, expanded: Binding(get: { project.expandedFolders }, set: { value in projects.update(projectID) { $0.expandedFolders = value } }))
                } else {
                    ForEach(files.filter { $0.localizedCaseInsensitiveContains(query) }, id: \.self) { file in Label(file, systemImage: "doc").font(.callout).help(file).tag(file) }
                }
            }.scrollContentBackground(.hidden)
        }
    }
    private var filePreview: some View {
                VStack(alignment: .leading) {
                    if let selection {
                        HStack {
                            Text(selection).font(.headline).lineLimit(2)
                            Spacer()
                            Button("Add to Context") { projects.update(projectID) {
                                if !$0.context.references.contains(selection) { $0.context.references.append(selection); $0.context.revision = UUID().uuidString }
                            }}
                            Button(project.selectedSession == nil ? "Attach to new session" : "Attach to session") { attach(selection) }
                            if location != "base" {
                                Button("Open externally") { NSWorkspace.shared.open(URL(fileURLWithPath: folder).appendingPathComponent(selection)) }
                            }
                        }.padding(14)
                        if let image { ScrollView([.horizontal, .vertical]) { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 800) } }
                        else { ScrollView([.horizontal, .vertical]) { Text(preview).font(.system(.body, design: .monospaced)).textSelection(.enabled).padding(16) } }
                    } else { ContentUnavailableView("Choose a file", systemImage: "doc.text.magnifyingglass") }
                }.frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func loadPreview() async {
            preview = ""; image = nil
            guard let selection, files.contains(selection) else { return }
            do {
                if let revision, ["png", "jpg", "jpeg", "gif", "webp"].contains(URL(fileURLWithPath: selection).pathExtension.lowercased()) {
                    let data = try await ProjectCommand.data("/usr/bin/git", ["-C", folder, "show", revision + ":" + selection])
                    if !Task.isCancelled { image = NSImage(data: data) }
                    return
                }
                let result = try await ProjectGit.preview(folder: folder, path: selection, revision: revision)
                if !Task.isCancelled { preview = result }
            } catch {
                if !Task.isCancelled {
                    let url = URL(fileURLWithPath: folder).appendingPathComponent(selection)
                    if revision == nil, ["png", "jpg", "jpeg", "gif", "webp"].contains(url.pathExtension.lowercased()),
                       let attrs = try? url.resourceValues(forKeys: [.fileSizeKey]), (attrs.fileSize ?? Int.max) < 20 * 1024 * 1024 {
                        image = NSImage(contentsOf: url)
                    }
                    preview = error.localizedDescription
                }
            }
    }
    private func load() async {
        loading = true; error = nil; selection = nil; files = []; preview = ""; revision = nil
        defer { loading = false }
        do {
            let resolved = location == "base" ? try await ProjectCommand.git(project.folder, ["rev-parse", "--verify", project.base + "^{commit}"]) : nil
            let result = try await ProjectGit.files(folder: folder, revision: resolved, showIgnored: showIgnored)
            guard !Task.isCancelled else { return }
            revision = resolved; files = result; tree = ProjectFileNode.tree(result)
            if let saved = project.fileSelection, result.contains(saved) { selection = saved }
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func attach(_ path: String) {
        Task {
            do {
                let url: URL
                if let revision { url = try await ProjectGit.snapshot(folder: folder, path: path, revision: revision) }
                else { url = URL(fileURLWithPath: folder).appendingPathComponent(path) }
                let attachment = try ConversationAttachment(url: url)
                if let id = project.selectedSession, let session = library.sessions.first(where: { $0.id == id }), [Provider.codex, .claude].contains(session.provider) {
                    let draft = library.drafts[id] ?? ConversationDraft()
                    var attachments = draft.attachments.compactMap { try? ConversationAttachment(url: URL(fileURLWithPath: $0)) }
                    if !attachments.contains(where: { $0.id == attachment.id }) { attachments.append(attachment) }
                    library.saveDraft(id, text: draft.text, attachments: attachments)
                    projects.update(projectID) { $0.section = "Sessions" }
                } else {
                    projects.update(projectID) { if !$0.draftAttachments.contains(url.path) { $0.draftAttachments.append(url.path) }; $0.selectedSession = nil; $0.section = "Sessions" }
                }
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct ProjectFileRows: View {
    let nodes: [ProjectFileNode]
    @Binding var expanded: Set<String>
    var body: some View {
        ForEach(nodes) { node in
            if let children = node.children {
                DisclosureGroup(isExpanded: Binding(get: { expanded.contains(node.id) }, set: { value in
                    if value { expanded.insert(node.id) } else { expanded.remove(node.id) }
                })) {
                    ProjectFileRows(nodes: children, expanded: $expanded)
                } label: { Label(node.name, systemImage: "folder").font(.callout) }
            } else {
                Label(node.name, systemImage: "doc").font(.callout).help(node.id).tag(node.id)
            }
        }
    }
}
