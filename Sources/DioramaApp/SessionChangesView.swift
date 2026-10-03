import SwiftUI
import Observation
import DioramaCore

@Observable final class SessionReviewState {
    var visible = false
    var scope = ChangeScope.session
    var selected: String?
    var snapshot: ChangesSnapshot?
    var patch = ""
    var error: String?
    var prError: String?
    var candidates: [LinkedPullRequest] = []
    var busy = false
    var prBusy = false
    var preparingFix = false
    var checksExpanded = false
}
@Observable final class SessionReviewStore {
    var states: [String: SessionReviewState] = [:]
    func state(_ id: String) -> SessionReviewState {
        if let value = states[id] { return value }
        let value = SessionReviewState(); states[id] = value; return value
    }
}

struct SessionReviewContainer: View {
    let session: Session
    let workspaceID: String
    let projectID: String
    @Bindable var library: LibraryModel
    @Bindable var review: SessionReviewState
    var inspectorTab: WorkspaceInspector? = nil
    var openDocument: ((WorkspaceDocument) -> Void)? = nil
    @Environment(\.scenePhase) private var phase
    @State private var showPR = false
    @State private var updatingBranch = false
    private var project: DioramaProject? { library.projects.projects.first { $0.id == projectID } }
    private var work: ProjectWorkspace? { project?.workspaces.first { $0.id == workspaceID } }
    var body: some View {
        Group {
            if let inspectorTab { compactInspector(inspectorTab) } else {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { review.visible.toggle(); library.activityState(session).visible = false } label: {
                    let snapshot = review.snapshot
                    Text("Changes" + (snapshot.map { " · \($0.files.count) files · +\($0.added) −\($0.removed)" } ?? ""))
                }.pointingHand().accessibilityLabel("Review session changes")
                if let pr = work?.pullRequest { Button(pr.summary) { library.activityState(session).visible = false; review.visible = true; review.checksExpanded.toggle() }.pointingHand() }
                Spacer(minLength: 0)
            }.font(.callout).padding(.horizontal, 20).padding(.vertical, 10)
            GeometryReader { geometry in
                if (review.visible || library.activityState(session).visible), let work {
                    if geometry.size.width >= 1000 {
                        HSplitView {
                            SessionView(session: session, model: library, hasLocalReview: true, activityAction: { section in review.visible = false; library.activityState(session).section = section; library.activityState(session).visible = true }).frame(minWidth: 450)
                            reviewPanel(work).frame(minWidth: 380, idealWidth: 520)
                        }
                    } else { reviewPanel(work) }
                } else { SessionView(session: session, model: library, hasLocalReview: true, activityAction: { section in review.visible = false; library.activityState(session).section = section; library.activityState(session).visible = true }) }
            }
        }
        }
        }
        .task(id: workspaceID) {
            await refreshLocal()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
                if (review.visible || inspectorTab != nil) && phase == .active { await refreshLocal() }
            }
        }
        .task(id: workspaceID + "pr") {
            while !Task.isCancelled {
                if phase == .active { await refreshPR() }
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
        .task(id: review.scope) { await refreshLocal() }
        .task(id: review.selected) { await refreshPatch() }
        .onChange(of: review.visible) { if review.visible { Task { await refreshLocal() } } }
        .onChange(of: phase) { if phase == .active { Task { await refreshLocal() }; Task { await refreshPR(force: true) } } }
        .onChange(of: library.execution.tasks[session.sessionID]?.phase) { Task { await refreshLocal() }; Task { await refreshPR(force: true) } }
        .sheet(isPresented: $showPR) {
            if let work, !session.observationOnly { GitHubPRView(projectID: projectID, workspace: work, library: library) }
        }
    }
    @ViewBuilder private func compactInspector(_ tab: WorkspaceInspector) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(work?.pullRequest?.summary ?? (review.snapshot?.branch ?? "Session changes")).font(.caption).lineLimit(2)
                Spacer()
                Button { Task { await refreshLocal(); await refreshPR(force: true) } } label: { Image(systemName: "arrow.clockwise") }.pointingHand().help("Refresh review")
            }.padding(.horizontal, 12).padding(.top, 12)
            if !session.observationOnly, work?.cleaned == false, project?.remote.flatMap({ try? GitHubGit.https($0) }) != nil {
                Button(work?.pullRequest?.state == "OPEN" ? "Update PR" : "Create PR") { showPR = true }.pointingHand()
                    .buttonStyle(.borderedProminent).padding(.horizontal, 12)
                    .disabled(library.execution.tasks.values.contains { $0.phase.active && $0.folder == work?.folder })
            }
            if tab == .checks {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let pr = work?.pullRequest { prDetails(pr) }
                        else if review.prBusy { ProgressView("Checking pull requests…") }
                        else { Text("No linked pull request").foregroundStyle(.secondary) }
                        if !review.candidates.isEmpty {
                            Menu("Choose pull request") { ForEach(review.candidates) { pr in Button(pr.title) { savePR(pr) }.pointingHand() } }.pointingHand()
                        }
                        if let error = review.prError { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
                    }.padding(12)
                }
            } else {
                Picker("Changes scope", selection: $review.scope) { ForEach(ChangeScope.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pointingHand().labelsHidden().padding(.horizontal, 12)
                if let error = review.error { ContentUnavailableView("Changes unavailable", systemImage: "folder.badge.questionmark", description: Text(error)) }
                else if review.snapshot == nil { ProgressView("Reading changes…").frame(maxWidth: .infinity, maxHeight: .infinity) }
                else if review.snapshot?.files.isEmpty == true { ContentUnavailableView("No file changes", systemImage: "arrow.triangle.branch", description: Text("This worktree matches the comparison.")) }
                else {
                    List {
                        ForEach(review.snapshot?.files ?? []) { file in
                            Button {
                                review.selected = file.path
                                if let work { openDocument?(WorkspaceDocument(folder: work.folder, path: file.path, workspaceID: work.id, changeScope: review.scope.rawValue)) }
                            } label: {
                                HStack {
                                    Image(systemName: "doc.text")
                                    Text(file.path).lineLimit(2).help(file.path)
                                    Spacer(minLength: 4)
                                    Text("+\(file.added)").foregroundStyle(.green)
                                    Text("−\(file.removed)").foregroundStyle(.red)
                                }.font(.system(size: 11)).padding(.vertical, 4).contentShape(Rectangle())
                            }.pointingHand().buttonStyle(.plain)
                        }
                    }.scrollContentBackground(.hidden)
                }
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear { if tab == .checks { review.checksExpanded = true } }
            .onChange(of: tab) { if tab == .checks { review.checksExpanded = true } }
    }
    @ViewBuilder private func reviewPanel(_ workspace: ProjectWorkspace) -> some View {
        if library.activityState(session).visible {
            SessionActivityPanel(session: session, library: library, state: library.activityState(session), close: { library.activityState(session).visible = false })
        } else { panel(workspace) }
    }
    func panel(_ workspace: ProjectWorkspace) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { review.visible = false } label: { Label("Conversation", systemImage: "chevron.left") }.pointingHand()
                Spacer()
                Button("Refresh") { Task { await refreshLocal() }; Task { await refreshPR(force: true) } }.pointingHand()
            }
            Text(review.snapshot?.branch ?? workspace.branch).font(.headline).textSelection(.enabled)
            Picker("Changes scope", selection: $review.scope) { ForEach(ChangeScope.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pointingHand().labelsHidden()
            if let pr = workspace.pullRequest { prDetails(pr) }
            if !review.candidates.isEmpty {
                Menu("Choose this session’s pull request…") {
                    ForEach(review.candidates) { pr in Button("#\(pr.number) · \(pr.title)") { savePR(pr); review.candidates = [] }.pointingHand() }
                }.pointingHand()
            }
            if let error = review.prError {
                Text("PR status unavailable. " + error).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                Text("Manage your GitHub account in Diorama Settings.").font(.caption)
            }
            if let error = review.error { ContentUnavailableView("Changes unavailable", systemImage: "folder.badge.questionmark", description: Text(error)) }
            else if review.snapshot?.files.isEmpty == true { ContentUnavailableView("No changes", systemImage: "checkmark", description: Text("This worktree matches the selected comparison.")) }
            else {
                VSplitView {
                    List(selection: $review.selected) {
                        ForEach(review.snapshot?.files ?? []) { file in
                            HStack {
                                VStack(alignment: .leading) { Text(file.path).lineLimit(2); Text(file.status).font(.caption).foregroundStyle(.secondary) }
                                Spacer(); Text("+\(file.added) −\(file.removed)").font(.caption.monospacedDigit())
                            }.pointingHand().tag(file.path)
                        }
                    }.frame(minHeight: 95, idealHeight: 180, maxHeight: 260)
                    VStack(alignment: .leading, spacing: 8) {
                        if let path = review.selected {
                            HStack {
                                Text(path).font(.caption).lineLimit(1); Spacer()
                                Button("Open externally") { NSWorkspace.shared.open(URL(fileURLWithPath: workspace.folder).appendingPathComponent(path)) }.pointingHand()
                            }
                        }
                        DiffTextView(patch: review.patch).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }.frame(minHeight: 140)
                }
            }
        }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func prDetails(_ pr: LinkedPullRequest) -> some View {
        DisclosureGroup(isExpanded: $review.checksExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Text(pr.title).font(.headline)
                if let date = pr.updatedAt { Text("\(review.prError == nil ? "Updated" : "Last known status") \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                if let snapshot = review.snapshot, pr.excludesLocalChanges(snapshot) { Text("Local changes aren’t included in these checks").font(.caption).foregroundStyle(.orange) }
                ForEach(pr.checks) { check in
                    HStack { Text(check.title); Spacer(); Text(check.result); if let value = check.url, let url = URL(string: value) { Link("Details", destination: url).pointingHand() } }
                }
                HStack {
                    if let url = URL(string: pr.url) { Link("Open on GitHub", destination: url).pointingHand() }
                    if pr.state == "MERGED", let base = pr.baseRefName, !session.observationOnly {
                        Button(updatingBranch ? "Updating…" : "Update local " + base) {
                            guard let project else { return }
                            updatingBranch = true
                            Task {
                                defer { updatingBranch = false }
                                do {
                                    try await GitHubBranchUpdate.update(projectFolder: project.folder, pullRequest: pr) { folder in
                                        await MainActor.run { library.execution.tasks.values.contains { $0.phase.active && $0.folder == folder } }
                                    }
                                    review.prError = nil; await refreshLocal()
                                } catch { review.prError = error.localizedDescription }
                            }
                        }.pointingHand().disabled(updatingBranch || review.prError != nil)
                    }
                    if pr.checks.contains(where: { $0.result == "Failed" }) {
                        Button(review.preparingFix ? "Preparing context…" : "Fix with agent") {
                            review.preparingFix = true
                            Task {
                                let prompt = await PullRequestService.fixPrompt(pr)
                                library.appendReviewDraft(session.id, text: prompt)
                                review.preparingFix = false; review.visible = false
                            }
                        }.pointingHand().disabled(review.preparingFix)
                    }
                }
            }.padding(.top, 8)
        } label: { Group { Text(pr.summary).font(.callout)  }.disclosurePointingHand() }
    }
    private func savePR(_ value: LinkedPullRequest?) { library.projects.updateWorkspace(projectID, id: workspaceID) { $0.pullRequest = value } }
    private func refreshLocal() async {
        guard let work, !review.busy else { return }; review.busy = true
        let scope = review.scope
        defer { review.busy = false }
        do {
            let snapshot = try await SessionChanges.snapshot(work, scope: scope)
            guard !Task.isCancelled, scope == review.scope else { return }
            review.snapshot = snapshot; review.error = nil
            if !snapshot.files.contains(where: { $0.path == review.selected }) { review.selected = snapshot.files.first?.path }
            await refreshPatch()
        } catch { if !Task.isCancelled { review.error = error.localizedDescription } }
    }
    private func refreshPatch() async {
        guard let work, let file = review.snapshot?.files.first(where: { $0.path == review.selected }) else { review.patch = ""; return }
        let scope = review.scope
        do {
            let patch = try await SessionChanges.diff(file, workspace: work, scope: scope)
            if !Task.isCancelled, review.selected == file.path, review.scope == scope, review.patch != patch { review.patch = patch }
        } catch { if review.selected == file.path { review.patch = error.localizedDescription } }
    }
    private func refreshPR(force: Bool = false) async {
        guard let project, let work, !review.prBusy else { return }; review.prBusy = true
        defer { review.prBusy = false }
        do {
            let rows = try await PullRequestService.shared.discover(project: project, workspace: work, force: force)
            guard !Task.isCancelled else { return }; review.prError = nil
            if let saved = work.pullRequest, let updated = rows.first(where: { $0.id == saved.id }) { savePR(updated); review.candidates = rows.count > 1 ? rows : [] }
            else if rows.count == 1 { savePR(rows[0]); review.candidates = [] }
            else { savePR(nil); review.candidates = rows }
        } catch { if !Task.isCancelled { review.prError = error.localizedDescription } }
    }
}

struct DiffTextView: View {
    let patch: String
    private var rows: [DiffLine] { DiffLine.parse(patch) }
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: 12) {
                        Text(row.old.map(String.init) ?? "").frame(width: 38, alignment: .trailing).foregroundStyle(.secondary)
                        Text(row.new.map(String.init) ?? "").frame(width: 38, alignment: .trailing).foregroundStyle(.secondary)
                        Text(row.text).textSelection(.enabled).fixedSize(horizontal: true, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.system(size: 12, design: .monospaced)).padding(.vertical, 2)
                        .background(row.text.hasPrefix("+") ? Color.green.opacity(0.12) : row.text.hasPrefix("-") ? Color.red.opacity(0.12) : .clear)
                }
            }
        }.background(.background).defaultScrollAnchor(.topLeading)
    }
}
struct DiffLine: Identifiable {
    let id: Int; let text: String; let old: Int?; let new: Int?
    static func parse(_ patch: String) -> [Self] {
        var old = 0; var new = 0; var inHunk = false
        return patch.components(separatedBy: "\n").enumerated().map { index, text in
            if text.hasPrefix("@@ ") {
                let parts = text.split(separator: " ")
                if parts.count >= 3 { old = Int(parts[1].dropFirst().split(separator: ",")[0]) ?? 0; new = Int(parts[2].dropFirst().split(separator: ",")[0]) ?? 0; inHunk = true }
                return Self(id: index, text: text, old: nil, new: nil)
            }
            guard inHunk, let first = text.first, ["+", "-", " "].contains(first) else { return Self(id: index, text: text, old: nil, new: nil) }
            let result = Self(id: index, text: text, old: first == "+" ? nil : old, new: first == "-" ? nil : new)
            if first != "+" { old += 1 }; if first != "-" { new += 1 }; return result
        }
    }
}
