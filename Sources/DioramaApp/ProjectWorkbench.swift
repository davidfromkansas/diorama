import SwiftUI
import DioramaCore

struct ProjectWorkbench: View {
    let projectID: String
    @Bindable var library: LibraryModel
    @Environment(\.workspaceWide) private var wide
    @Environment(\.workspaceContentWidth) private var contentWidth
    @State private var inspectorDrag: Double?
    @State private var overlayOpen = false
    private var project: DioramaProject { library.projects.projects.first { $0.id == projectID } ?? .unavailable }
    private var session: Session? { library.sessions.first { $0.id == project.selectedSession } }
    private var work: ProjectWorkspace? { project.workspaces.first { $0.threadID != nil && $0.threadID == session?.sessionID } }
    private var navigation: WorkspaceNavigation { library.navigation }
    private var key: String { projectID + ":" + (project.selectedSession ?? "draft") }
    private var tab: WorkspaceTab { navigation.tabs[key] ?? .conversation }
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                tabStrip
                Divider()
                center.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            if wide && navigation.layout.inspectorVisible {
                Rectangle().fill(DioramaStyle.border).frame(width: 1).overlay {
                    Color.clear.frame(width: 7).contentShape(Rectangle()).gesture(DragGesture().onChanged { value in
                        if inspectorDrag == nil { inspectorDrag = navigation.layout.inspectorWidth }
                        navigation.layout.inspectorWidth = min(560, max(280, (inspectorDrag ?? 340) - value.translation.width))
                    }.onEnded { _ in inspectorDrag = nil })
                }
                inspector.frame(width: min(navigation.layout.inspectorWidth, max(280, contentWidth - 381)))
            }
        }
        .overlay(alignment: .trailing) {
            if !wide && overlayOpen {
                ZStack(alignment: .trailing) {
                    Color.black.opacity(0.3).onTapGesture { overlayOpen = false }
                    VStack(spacing: 0) {
                        HStack { Text("Inspector").font(.caption); Spacer(); Button { overlayOpen = false } label: { Image(systemName: "xmark") }.help("Close inspector") }.padding(12)
                        inspector
                    }.frame(width: 340).background(DioramaStyle.sidebar).shadow(radius: 16)
                }
            }
        }
        .onChange(of: navigation.layout.inspectorVisible) { if !wide { overlayOpen.toggle() } }
        .onChange(of: wide) { overlayOpen = false }
        .onChange(of: key, initial: true) { syncSection(); syncMode() }
        .onChange(of: project.section) { syncSection() }
        .onChange(of: tab) { syncMode() }
    }
    private var tabStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach([WorkspaceTab.conversation, .activity, .html], id: \.title) { value in
                    WorkspaceTabButton(title: value.title, selected: tab == value) { select(value) }
                        .disabled(session == nil && value != .conversation)
                }
                if tab == .context { WorkspaceTabButton(title: "Context", selected: true) { } }
                if tab == .pullRequests { WorkspaceTabButton(title: "Pull Requests", selected: true) { } }
                ForEach(navigation.documents[key] ?? []) { document in
                    HStack(spacing: 0) {
                        WorkspaceTabButton(title: document.title, selected: tab == .document(document)) { select(.document(document)) }
                        Button { navigation.close(document, key: key) } label: { Image(systemName: "xmark").font(.system(size: 9)) }.buttonStyle(.plain).padding(.trailing, 10).help("Close " + document.title)
                    }
                }
            }.padding(.horizontal, 4)
        }.scrollIndicators(.hidden).frame(height: 38).background(DioramaStyle.sidebar.opacity(0.65))
    }
    private var showsConversation: Bool {
        switch tab { case .conversation, .activity, .html: true; default: false }
    }
    private var center: some View {
        ZStack {
            Group {
                if let session {
                    SessionView(session: session, model: library, hasLocalReview: true, activityAction: { section in
                        library.activityState(session).section = section; select(.activity)
                    }, shellContent: true).id(session.id)
                } else { ProjectDraftView(projectID: projectID, projects: library.projects, library: library) }
            }.opacity(showsConversation ? 1 : 0).allowsHitTesting(showsConversation).accessibilityHidden(!showsConversation)
            if !showsConversation {
                VStack(spacing: 0) {
                    if let session, library.needsAttention(session) {
                        Button("Session needs attention — return to conversation") { select(.conversation) }
                            .font(.caption).foregroundStyle(.orange).padding(10)
                    }
                    switch tab {
                    case .context: ProjectContextView(projectID: projectID, projects: library.projects)
                    case .pullRequests: LinkedProjectPRView(projectID: projectID, library: library)
                    case .document(let document): WorkspaceDocumentView(document: document, projectID: projectID, library: library, returnToConversation: { select(.conversation) }).id(document.id)
                    default: EmptyView()
                    }
                }.background(DioramaStyle.canvas)
            }
        }
    }
    private var inspector: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(WorkspaceInspector.allCases, id: \.self) { value in
                    WorkspaceTabButton(title: value.rawValue, selected: navigation.layout.inspector == value) { navigation.layout.inspector = value }
                }
                Spacer(minLength: 0)
            }
            Divider()
            if navigation.layout.inspector == .files {
                ProjectFilesView(projectID: projectID, projects: library.projects, library: library, inspectorOnly: true, openDocument: openDocument).id(key)
            } else if let session, let work {
                SessionReviewContainer(session: session, workspaceID: work.id, projectID: projectID, library: library, review: library.reviews.state(work.id), inspectorTab: navigation.layout.inspector, openDocument: openDocument).id(work.id)
            } else if navigation.layout.inspector == .changes, let session {
                VStack {
                    ReviewChangesControls(model: library, session: session)
                    ExecutionChangesView(work: library.execution.tasks[session.sessionID]?.work ?? ExecutionWork())
                }
            } else {
                ContentUnavailableView(navigation.layout.inspector == .checks ? "No linked pull request" : "No session selected", systemImage: "arrow.triangle.branch", description: Text("Choose a project session to inspect its work."))
            }
        }.frame(maxHeight: .infinity).background(DioramaStyle.canvas)
    }
    private func openDocument(_ document: WorkspaceDocument) { navigation.open(document, key: key); overlayOpen = false }
    private func select(_ value: WorkspaceTab) {
        navigation.tabs[key] = value
        if project.section != "Sessions" { library.projects.update(projectID) { $0.section = "Sessions" } }
    }
    private func syncSection() {
        switch project.section {
        case "Context": navigation.tabs[key] = .context
        case "Pull Requests": navigation.tabs[key] = .pullRequests
        case "Files": navigation.layout.inspector = .files; navigation.layout.inspectorVisible = true; if !wide { overlayOpen = true }
        default:
            if tab == .context || tab == .pullRequests { navigation.tabs[key] = .conversation }
        }
    }
    private func syncMode() {
        switch tab {
        case .activity: library.viewMode = .activity
        case .html: library.viewMode = .html
        default: library.viewMode = .conversation
        }
    }
}

struct WorkspaceDocumentView: View {
    let document: WorkspaceDocument
    let projectID: String
    @Bindable var library: LibraryModel
    var returnToConversation: () -> Void
    @State private var text = ""
    @State private var image: NSImage?
    @State private var error: String?
    @State private var loading = true
    @State private var refresh = UUID()
    private var project: DioramaProject? { library.projects.projects.first { $0.id == projectID } }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.path).font(.system(size: 12, weight: .medium)).textSelection(.enabled)
                    Text(document.changeScope ?? (document.revision.map { "Project base · " + String($0.prefix(8)) } ?? "Working files")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Open externally") { openExternal() }
                    Button("Attach to session") { attach() }
                    Button("Add to shared context") {
                        library.projects.update(projectID) {
                            if !$0.context.references.contains(document.path) { $0.context.references.append(document.path); $0.context.revision = UUID().uuidString }
                        }
                    }
                    Button("Refresh") { refresh = UUID() }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
            }.padding(16)
            Divider()
            if loading { ProgressView("Loading document…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if let error { ContentUnavailableView("Document unavailable", systemImage: "doc.badge.ellipsis", description: Text(error)) }
            else if let image { ScrollView([.horizontal, .vertical]) { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 900).padding() } }
            else if document.changeScope != nil { DiffTextView(patch: text) }
            else { ScrollView([.horizontal, .vertical]) { Text(text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(20) } }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).task(id: refresh) { await load() }
    }
    private func load() async {
        loading = true; error = nil; image = nil
        defer { loading = false }
        do {
            if let id = document.workspaceID, let scope = document.changeScope.flatMap(ChangeScope.init(rawValue:)), let work = project?.workspaces.first(where: { $0.id == id }) {
                let snapshot = try await SessionChanges.snapshot(work, scope: scope)
                if let file = snapshot.files.first(where: { $0.path == document.path }) {
                    let result = try await SessionChanges.diff(file, workspace: work, scope: scope)
                    if !Task.isCancelled { text = result }
                } else { text = "This file no longer has changes in the selected comparison." }
            } else if document.workspaceID != nil { throw AppServerFailure("The session worktree is no longer available.") }
            else {
                let url = URL(fileURLWithPath: document.folder).appendingPathComponent(document.path)
                if ["png", "jpg", "jpeg", "gif", "webp"].contains(url.pathExtension.lowercased()) {
                    let data: Data
                    if let revision = document.revision { data = try await ProjectCommand.data("/usr/bin/git", ["-C", document.folder, "show", revision + ":" + document.path]) }
                    else {
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                        guard size <= 20 * 1024 * 1024 else { throw AppServerFailure("Image exceeds 20 MiB. Open externally to inspect it.") }
                        data = try Data(contentsOf: url)
                    }
                    guard let decoded = NSImage(data: data) else { throw AppServerFailure("Image could not be decoded.") }
                    if !Task.isCancelled { image = decoded }
                } else {
                    let result = try await ProjectGit.preview(folder: document.folder, path: document.path, revision: document.revision)
                    if !Task.isCancelled { text = result }
                }
            }
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func fileURL() async throws -> URL {
        if let revision = document.revision { return try await ProjectGit.snapshot(folder: document.folder, path: document.path, revision: revision) }
        return URL(fileURLWithPath: document.folder).appendingPathComponent(document.path)
    }
    private func openExternal() {
        Task { do { let url = try await fileURL(); NSWorkspace.shared.open(url) } catch { self.error = error.localizedDescription } }
    }
    private func attach() {
        Task { do {
            let url = try await fileURL()
            let attachment = try ConversationAttachment(url: url)
            if let id = project?.selectedSession {
                let draft = library.drafts[id] ?? ConversationDraft()
                var attachments = draft.attachments.compactMap { try? ConversationAttachment(url: URL(fileURLWithPath: $0)) }
                if !attachments.contains(where: { $0.id == attachment.id }) { attachments.append(attachment) }
                library.saveDraft(id, text: draft.text, attachments: attachments)
            } else { library.projects.update(projectID) { if !$0.draftAttachments.contains(url.path) { $0.draftAttachments.append(url.path) } } }
            returnToConversation()
        } catch { self.error = error.localizedDescription } }
    }
}
