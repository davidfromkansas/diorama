import SwiftUI
import ImageIO
import DioramaCore

struct ConversationActions: View {
    let model: LibraryModel
    let session: Session
    var body: some View {
        if session.provider == .claude && session.classification != .internalReview {
            Button(session.archived ? "Restore conversation" : "Archive conversation…") { model.archiveSession = session }.pointingHand()
        }
        if session.provider == .codex && session.classification != .internalReview {
            Button("Rename…") { model.renameSession = session; model.renameText = session.title }.pointingHand()
            Button(model.pinned.contains(session.id) ? "Unpin in Diorama" : "Pin in Diorama") { model.togglePin(session) }.pointingHand()
            Button(session.archived ? "Restore conversation" : "Archive conversation…") { model.archiveSession = session }.pointingHand()
            Button("Fork conversation") { model.forkConversation(session) }.pointingHand().help("Copies conversation history. Project sessions receive a new worktree from the source’s committed revision; uncommitted files are not copied.").disabled(model.execution.tasks[session.sessionID]?.phase.active == true)
        }
    }
}

struct ConversationSearchView: View {
    let model: LibraryModel
    let threadID: String?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var archived = false
    @State private var results: [WireValue] = []
    @State private var nextCursor: String?
    @State private var error: String?
    @State private var busy = false
    @State private var searched = false
    @State private var preview: Transcript?
    @State private var matchPrefix = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text(threadID == nil ? "Search chats" : "Find in conversation").font(.title2); Spacer(); Button("Done") { dismiss() }.pointingHand() }
            HStack {
                TextField("Search message text", text: $query).onSubmit { search(more: false) }
                if threadID == nil { Toggle("Archived", isOn: $archived).pointingHand() }
                Button("Search") { search(more: false) }.pointingHand().disabled(busy || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.disabled(busy)
            Text(threadID == nil ? "Search uses the server's message index; existing sidebar search still matches titles and folders." : "Find searches visible user and final assistant messages. Tool output is outside the server search scope.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            if searched && results.isEmpty && error == nil { Text("No matches").foregroundStyle(.secondary) }
            HSplitView {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                            Button {
                                if let threadID, let turn = result["turnId"].string {
                                    matchPrefix = turn + ":" + (result["itemId"].string ?? "") + ":"
                                    busy = true
                                    Task { defer { busy = false }; do { preview = try await model.execution.searchTurn(threadID: threadID, turnID: turn) } catch { self.error = error.localizedDescription } }
                                } else { model.openSearchResult(result, archived: archived); dismiss() }
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    if threadID == nil { Text(result["thread"]["name"].string ?? result["thread"]["preview"].string ?? "Conversation").font(.headline).lineLimit(2) }
                                    Text(result["snippet"].string ?? "Match").lineLimit(5)
                                }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                            }.pointingHand().buttonStyle(.plain).disabled(busy)
                        }
                        if nextCursor != nil { Button("More matches") { search(more: true) }.pointingHand().disabled(busy) }
                    }
                }.frame(minWidth: 260)
                if let preview {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading) {
                                Text("Matching turn").font(.headline)
                                ForEach(preview.entries) { entry in
                                    EntryView(entry: entry).padding(6).background(entry.id.hasPrefix(matchPrefix) ? Color.accentColor.opacity(0.12) : .clear).id(entry.id)
                                }
                            }.padding(12)
                        }.task(id: matchPrefix) { await Task.yield(); if let match = preview.entries.first(where: { $0.id.hasPrefix(matchPrefix) }) { proxy.scrollTo(match.id, anchor: .center) } }
                    }.frame(minWidth: 300)
                }
            }
            if busy { ProgressView().controlSize(.small) }
        }.padding(24).frame(width: 820, height: 600)
            .onChange(of: query) { nextCursor = nil; searched = false; results = []; preview = nil }
            .onChange(of: archived) { nextCursor = nil; results = []; searched = false }
    }
    private func search(more: Bool) {
        guard !busy else { return }
        let term = query; let filter = archived; let cursor = more ? nextCursor : nil
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                let page = try await model.execution.searchMessages(query: term, threadID: threadID, archived: filter, cursor: cursor)
                guard query == term, archived == filter else { return }
                if more, page.nextCursor == cursor { throw AppServerFailure("Search cursor repeated") }
                results = more ? results + page.rows : page.rows; nextCursor = page.nextCursor; searched = true
            } catch { self.error = "Message search is unavailable: " + error.localizedDescription + ". Title/folder search remains available in the sidebar." }
        }
    }
}

struct ReviewChangesControls: View {
    let model: LibraryModel
    let session: Session
    @State private var branch = ""
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Code review").font(.headline)
            TextField("Optional base branch (blank = working changes)", text: $branch)
            Text("Review runs a Codex turn and uses your normal usage. It does not stage, commit or merge changes.").font(.caption).foregroundStyle(.secondary)
            Button("Review changes") {
                busy = true
                Task {
                    defer { busy = false }
                    do {
                        if model.execution.tasks[session.sessionID]?.attached != true { try await model.execution.resumeImported(session) }
                        try await model.execution.review(id: session.sessionID, baseBranch: branch)
                        
                    } catch { self.error = error.localizedDescription }
                }
            }.pointingHand().disabled(busy || session.archived || model.execution.tasks[session.sessionID]?.phase.active == true)
            if let error { Text(error).foregroundStyle(.orange).font(.caption) }
        }.padding(16)
    }
}

struct RichToolResultView: View {
    @Environment(\.historyDetails) private var historyDetails
    let result: ToolResult
    var selectWorker: ((String) -> Void)?
    var progress: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { if result.type == "mcpToolCall" { ConnectorMark(server: result.item["server"].string) }; Label(result.title, systemImage: result.type == "fileChange" ? "doc.text" : result.type == "webSearch" ? "magnifyingglass" : "terminal").lineLimit(2); Spacer(); Text(result.status).font(.caption).foregroundStyle(.secondary) }
            if result.type == "webSearch" { CodexSearchView(item: result.item) }
            if result.requestsInput { Text("Respond in Codex").foregroundStyle(.orange) }
            if !result.planSteps.isEmpty {
                Text("Reported plan update").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(result.planSteps.enumerated()), id: \.offset) { _, step in
                    Label((step["step"].string ?? "Step") + " · " + (step["status"].string ?? "Reported"), systemImage: step["status"].string == "completed" ? "checkmark.circle" : "circle")
                }
            }
            if let progress { Text(progress).font(.caption).foregroundStyle(.secondary) }
            if result.item["exitCode"] != .null || result.item["durationMs"] != .null {
                Text("Exit: \(result.item["exitCode"].scalarText) · \(result.item["durationMs"].scalarText) ms").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            if !result.outputs.isEmpty { ConversationOutputCards(outputs: result.outputs) }
            if result.item["arguments"] != .null {
                DisclosureGroup { TranscriptContent(text: CodexOutputEvidence.safeDetails(result.item["arguments"]).pretty, literal: true).textSelection(.enabled) } label: { Text("Inputs").disclosurePointingHand() }
            }
            if result.item["error"] != .null { Text(CodexOutputEvidence.safeDetails(result.item["error"]).pretty).foregroundStyle(.orange) }
            if let failure = result.item["failure"].string { Text(failure).foregroundStyle(.orange) }
            ForEach(result.type == "webSearch" ? [] : result.item["results"].array, id: \.pretty) { source in
                if let s = source["url"].string, let url = URL(string: s), ["http", "https"].contains(url.scheme ?? "") { Link(source["title"].string ?? s, destination: url).pointingHand() }
            }
            if !result.output.isEmpty { DisclosureGroup { TranscriptContent(text: result.output, literal: result.type == "commandExecution").textSelection(.enabled) } label: { Text("Output").disclosurePointingHand() } }
            ForEach(result.item["changes"].array, id: \.pretty) { change in
                DisclosureGroup { Text(change["diff"].string ?? "No historical diff was supplied by the source.").font(.caption.monospaced()).textSelection(.enabled) } label: { Text(change["path"].string ?? "Changed file").disclosurePointingHand() }
            }
            if result.type != "webSearch", let query = result.item["query"].string ?? result.item["action"]["query"].string { Text(query).font(.caption).foregroundStyle(.secondary) }
            ForEach(result.workers, id: \.self) { worker in
                if let selectWorker { Button("Open agent · " + String(worker.prefix(12))) { selectWorker(worker) }.pointingHand() }
                else { Text("Agent · " + worker).font(.caption).textSelection(.enabled) }
            }
            if historyDetails { DisclosureGroup { Text(result.rawPreview).font(.caption.monospaced()).textSelection(.enabled) } label: { Text("Raw tool details").disclosurePointingHand() } }
        }.font(.callout).padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }
}

extension LibraryModel {
    func togglePin(_ session: Session) {
        if pinned.contains(session.id) { pinned.remove(session.id) } else { pinned.insert(session.id) }
        UserDefaults.standard.set(Array(pinned), forKey: "pinnedConversations")
    }
    func renameConversation(_ session: Session) {
        let name = renameText; renameSession = nil
        Task {
            do {
                try await execution.rename(session: session, name: name)
                if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index] = session.updated(title: name) }
            } catch { workflowError = error.localizedDescription }
        }
    }
    func archiveConversation(_ session: Session) {
        archiveSession = nil
        Task {
            do { try await setArchived(session, archived: !session.archived) } catch { workflowError = error.localizedDescription }
        }
    }
    /// Archives (or restores) a Codex thread through its app-server, or a Claude conversation
    /// through Claude Desktop's session file and Diorama's own record (`ClaudeArchive`).
    func setArchived(_ session: Session, archived: Bool) async throws {
        switch session.provider {
        case .codex: try await execution.setArchived(session: session, archived: archived)
        case .claude:
            if archived, execution.tasks[session.sessionID]?.busy == true { throw AppServerFailure("Stop work before archiving") }
            try ClaudeArchive().setArchived(session, archived: archived)
        }
        if archived { archivedHere.insert(session.id) } else { archivedHere.remove(session.id) }
        if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index] = session.updated(archived: archived) }
        await refresh()
    }
    /// Why an agent can't be archived from the kitchen right now, or nil.
    func archiveBlocker(_ agent: SpatialAgent) -> String? {
        guard agent.value.isMain else { return "Sub-agents can't be archived" }
        guard let session = sessions.first(where: { $0.id == agent.conversationID }) else { return "This conversation can't be archived" }
        if session.classification == .internalReview { return "Reviews can't be archived" }
        if agent.value.status == .working || execution.tasks[session.sessionID]?.busy == true { return "Stop \(agent.value.name) first" }
        return nil
    }
    func forkConversation(_ session: Session, through turn: String? = nil) {
        Task {
            do {
                let existing = projects.projects.first(where: { projects.sessions($0, library: self).contains(where: { $0.id == session.id }) })
                let project: DioramaProject
                if let existing { project = existing }
                else { project = try await ProjectGit.discover(session.project); projects.add(project) }
                try projects.checkpoint()
                let commit = try await ProjectCommand.git(session.project, ["rev-parse", "HEAD"])
                let workspace = try await ProjectGit.createWorkspace(project: project, id: UUID().uuidString, base: commit, useCached: true, branchName: DescriptiveBranch.suggestion("fork " + session.title) ?? "fork-conversation")
                projects.update(project.id) { $0.workspaces.append(workspace) }
                projects.updateWorkspace(project.id, id: workspace.id) { $0.creationUncertain = true }
                try projects.checkpoint()
                let id = try await execution.fork(session: session, through: turn, folder: workspace.folder, projectContext: workspace.context.prompt(folder: workspace.folder, commit: workspace.baseCommit))
                projects.updateWorkspace(project.id, id: workspace.id) { $0.threadID = id; $0.creationUncertain = false }
                projects.selectedID = project.id
                projects.update(project.id) { $0.section = "Sessions"; $0.selectedSession = Provider.codex.rawValue + ":" + id }
                selectOwned(id)
                await readSelected()
            } catch { workflowError = error.localizedDescription }
        }
    }
    func openWorker(_ id: String) {
        syncOwnedSessions()
        guard let session = sessions.first(where: { $0.sessionID == id }) else { workflowError = "This worker is not available in local history yet. Refresh discovery and try again."; return }
        openAttention(session)
    }
    func openSearchResult(_ row: WireValue, archived: Bool) {
        do {
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(row["thread"])) as? [String: Any] ?? [:]
            guard let session = AppServerHistory.session(object, archived: archived) else { return }
            if !sessions.contains(where: { $0.id == session.id }) { sessions.append(session) }
            archiveFilter = "All"; query = ""; provider = "All"; activityFilter = "All"
            if !folderOrder.contains(session.project) { folderOrder.append(session.project) }
            selectedFolderID = session.project; openInWorkspace(session)
            Task { await readSelected() }
        } catch { workflowError = error.localizedDescription }
    }
}

struct EncodedToolImage: View {
    let encoded: String
    private var thumbnail: NSImage? {
        guard encoded.utf8.count <= 28 * 1024 * 1024 else { return nil }
        let base64 = encoded.hasPrefix("data:image/") ? String(encoded.split(separator: ",", maxSplits: 1).last ?? "") : encoded
        guard let data = Data(base64Encoded: base64), data.count <= 20 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1200, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }
    var body: some View {
        if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFit().frame(maxHeight: 360).accessibilityLabel("Tool result image") }
        else { Text("Image preview unavailable; inspect raw tool details.").font(.caption).foregroundStyle(.secondary) }
    }
}

