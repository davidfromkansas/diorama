import DioramaCore
import SwiftUI

/// The kitchen's serving window: review an agent's finished work, then send feedback, mark it
/// done, commit, open a pull request, or merge. The chef reacts to each decision.
struct ServingWindowView: View {
    let agent: SpatialAgent
    let session: Session
    @Bindable var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var changes: ChangesSnapshot?
    @State private var uncommitted = false
    @State private var feedback = ""
    @State private var message = ""
    @State private var busy: String?
    @State private var error: String?
    @State private var notice: String?
    @State private var showPR = false
    private var reviews: KitchenReviews { .shared }
    private var project: DioramaProject? { library.projects.projects.first { $0.id == agent.projectID } }
    private var workspace: ProjectWorkspace? { project?.workspaces.first { $0.threadID == session.sessionID } }
    private var state: KitchenReviews.State { reviews.state(agent.conversationID) ?? .awaiting }
    private var active: Bool { library.execution.tasks.values.contains { $0.phase.active && $0.folder == workspace?.folder } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            changesSection
            Divider()
            feedbackSection
            Divider()
            shipSection
            if let error { Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            if let notice { Text(notice).font(.callout).foregroundStyle(.secondary) }
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 560)
        .task { message = Self.defaultMessage(agent.value.task); await refresh() }
        .sheet(isPresented: $showPR, onDismiss: { Task { await afterPR() } }) {
            if let project, let workspace { GitHubPRView(projectID: project.id, workspace: workspace, library: library) }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "fork.knife.circle.fill").font(.system(size: 34)).foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 3) {
                Text("Serving window · \(agent.value.name)").font(.title3.weight(.semibold))
                Text(TaskTitle.full(agent.value.task)).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                Text(statusText).font(.caption.weight(.medium)).foregroundStyle(.teal)
            }
        }
    }
    private var statusText: String {
        switch state {
        case .awaiting: "Ready for your review"
        case .committed: "Committed locally" + (reviews.entries[agent.conversationID]?.note.map { " · \($0)" } ?? "")
        case .shipped: "Pull request open" + (workspace?.pullRequest.map { " · #\($0.number)" } ?? "")
        case .approved: "Done"
        }
    }

    private var changesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The dish").font(.headline)
            if let workspace {
                Text("Branch \(workspace.branch)").font(.caption).foregroundStyle(.secondary)
                if let changes {
                    if changes.files.isEmpty {
                        Text("No file changes in this task.").font(.callout).foregroundStyle(.secondary)
                    } else {
                        Text("\(changes.files.count) file\(changes.files.count == 1 ? "" : "s") changed · +\(changes.added) −\(changes.removed)" + (uncommitted ? " · not committed yet" : ""))
                            .font(.callout)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(changes.files) { file in
                                    Text("\(file.status)  \(file.path)").font(.system(.caption, design: .monospaced)).lineLimit(1)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 110)
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            } else {
                Text("This conversation has no Diorama worktree, so git steps are unavailable. You can still send feedback or mark it done.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Not quite right?").font(.headline)
            TextField("Tell the agent what to change…", text: $feedback, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
            Button(busy == "feedback" ? "Sending…" : "Send feedback") { Task { await sendFeedback() } }
                .disabled(feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy != nil)
        }
    }

    private var shipSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Happy with it?").font(.headline)
            if workspace != nil {
                HStack {
                    TextField("Commit message", text: $message).textFieldStyle(.roundedBorder)
                    Button(busy == "commit" ? "Committing…" : "Commit") { Task { await commit() } }
                        .disabled(!uncommitted || busy != nil || active)
                }
                HStack(spacing: 10) {
                    Button(workspace?.pullRequest == nil ? "Push & open PR…" : "Update PR…") { showPR = true }
                        .disabled(busy != nil || active)
                    Button(busy == "merge" ? "Merging…" : mergeTitle) { Task { await merge() } }
                        .disabled(busy != nil || active || (uncommitted && workspace?.pullRequest == nil))
                    Spacer()
                    Button("Done") { approve(note: nil) }.buttonStyle(.borderedProminent).disabled(busy != nil)
                }
                Text(mergeHint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                HStack { Spacer(); Button("Done") { approve(note: nil) }.buttonStyle(.borderedProminent) }
            }
        }
    }
    private var mergeTitle: String {
        if let pr = workspace?.pullRequest, pr.state == "OPEN" { return "Merge PR on GitHub" }
        return "Merge into \(project?.base ?? "base")"
    }
    private var mergeHint: String {
        if let pr = workspace?.pullRequest, pr.state == "OPEN" { return "Merges pull request #\(pr.number) on GitHub, then updates your local \(pr.baseRefName ?? project?.base ?? "base")." }
        return "Done finishes without git. Commit saves the changes on this task's branch. Merge brings the committed branch into \(project?.base ?? "the base branch") in \(project?.folder ?? "your project folder")."
    }

    /// The task's first sentence, kept under a conventional 72-character subject line.
    static func defaultMessage(_ task: String) -> String {
        let line = task.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Update"
        // A sentence ends at ". ", not at the dot in a file name like README.md.
        let sentence = line.components(separatedBy: ". ").first ?? line
        var subject = sentence.trimmingCharacters(in: .whitespaces)
        if subject.count > 72 {
            subject = String(subject.prefix(72))
            if let space = subject.lastIndex(of: " ") { subject = String(subject[..<space]) }
        }
        return subject.isEmpty ? "Update" : subject
    }

    // MARK: Actions

    private func refresh() async {
        guard let workspace else { return }
        changes = try? await SessionChanges.snapshot(workspace, scope: .session)
        uncommitted = (try? await ServingWindowGit.hasUncommittedChanges(worktree: workspace.folder)) ?? false
    }
    private func run(_ name: String, _ body: () async throws -> Void) async {
        busy = name; error = nil; notice = nil
        defer { busy = nil }
        do { try await body() } catch { self.error = error.localizedDescription }
    }
    private func sendFeedback() async {
        let text = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        await run("feedback") {
            try await library.execution.send(in: session, prompt: text)
            reviews.clear(agent.conversationID)
            feedback = ""
            dismiss()
        }
    }
    private func commit() async {
        guard let workspace else { return }
        await run("commit") {
            let sha = try await ServingWindowGit.commitAll(worktree: workspace.folder, message: message)
            reviews.set(agent.conversationID, .committed, note: sha)
            notice = "Committed \(sha) on \(workspace.branch)."
            await refresh()
        }
    }
    private func afterPR() async {
        await refresh()
        if let pr = project?.workspaces.first(where: { $0.threadID == session.sessionID })?.pullRequest {
            reviews.set(agent.conversationID, pr.state == "MERGED" ? .approved : .shipped, note: "#\(pr.number)")
        }
    }
    private func merge() async {
        guard let project, let workspace else { return }
        await run("merge") {
            if let pr = workspace.pullRequest, pr.state == "OPEN" {
                try await ServingWindowGit.mergeOnGitHub(pr)
                let merged = try await GitHubPullRequests.get(pr.url)
                library.projects.updateWorkspace(project.id, id: workspace.id) { $0.pullRequest = merged }
                try? await GitHubBranchUpdate.update(projectFolder: project.folder, pullRequest: merged) { folder in
                    await MainActor.run { library.execution.tasks.values.contains { $0.phase.active && $0.folder == folder } }
                }
                approve(note: "Merged #\(pr.number)")
            } else {
                try await ServingWindowGit.mergeLocally(projectFolder: project.folder, base: project.base, branch: workspace.branch, worktree: workspace.folder)
                approve(note: "Merged into \(project.base)")
            }
        }
    }
    private func approve(note: String?) {
        reviews.set(agent.conversationID, .approved, note: note)
        dismiss()
    }
}
