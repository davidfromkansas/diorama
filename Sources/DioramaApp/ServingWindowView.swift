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
        let band = self.band
        VStack(spacing: 0) {
            ModalHeader(group: band.group, title: TaskTitle.full(session.displayTitle), status: statusWord, model: modelName, detail: finished) { dismiss() }
            ModalBand(group: band.group, title: band.title, detail: band.detail)
            ScrollView {
                VStack(spacing: 0) {
                    changesSection
                    doneSection
                    feedbackSection
                }
            }
            .frame(maxHeight: 600)
            if error != nil || notice != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let error { Text(error).foregroundStyle(ModalStyle.red) }
                    if let notice { Text(notice).foregroundStyle(SidebarStyle.secondary) }
                }
                .font(.system(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            }
            ModalFooter {
                if workspace != nil {
                    Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary).help(mergeHint).accessibilityLabel(mergeHint)
                }
            } actions: { footerActions }
        }
        .foregroundStyle(SidebarStyle.title)
        .reviewModalSurface()
        .task { message = Self.defaultMessage(agent.value.task); await refresh() }
        .sheet(isPresented: $showPR, onDismiss: { Task { await afterPR() } }) {
            if let project, let workspace { GitHubPRView(projectID: project.id, workspace: workspace, library: library) }
        }
    }

    // MARK: Header and band
    private var band: (group: AgentSidebarGroup, title: String, detail: String?) {
        switch state {
        case .awaiting: (.done, "Ready for your review", "stays in Done until you decide")
        case .committed: (.done, "Committed locally", reviews.entries[agent.conversationID]?.note)
        case .shipped: (.done, "Pull request open", workspace?.pullRequest.map { "#\($0.number)" })
        case .approved: (.done, "Done", nil)
        case .reworking: (.inProgress, "Back to work on your feedback", nil)
        }
    }
    private var statusWord: String {
        switch state { case .awaiting, .approved: "Done"; case .committed: "Committed"; case .shipped: "PR open"; case .reworking: "Reworking" }
    }
    private var modelName: String {
        let task = library.execution.tasks[session.sessionID]
        return AgentSidebar.modelName(task.flatMap { $0.model.isEmpty ? nil : $0.model } ?? agent.value.reportedModel, provider: agent.value.provider, catalog: library.execution.models)
    }
    private var finished: String? {
        guard let date = agent.value.meaningfulUpdatedAt else { return nil }
        return "finished " + RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
    private var providerName: String { agent.value.provider == Provider.claude.rawValue ? "Claude" : agent.value.provider == Provider.codex.rawValue ? "Codex" : "the agent" }

    // MARK: Changes
    static let fileLimit = 8
    private var changesSection: some View {
        VStack(spacing: 0) {
            ModalSectionBand(title: "Changes") {
                if let changes, !changes.files.isEmpty {
                    (Text("\(changes.files.count) file\(changes.files.count == 1 ? "" : "s") · ")
                     + Text("+\(changes.added)").foregroundColor(SidebarStyle.tint(.done).text) + Text(" ")
                     + Text("−\(changes.removed)").foregroundColor(ModalStyle.red)
                     + Text(uncommitted ? " · not committed" : ""))
                }
            }
            if let workspace {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 11)).foregroundStyle(SidebarStyle.secondary)
                    Text(workspace.branch).font(.system(size: 11.5, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                }
                .padding(.horizontal, 16).frame(height: 34).overlay(alignment: .bottom) { ModalDivider() }
                if let changes {
                    if changes.files.isEmpty {
                        note("No file changes in this task.")
                    } else {
                        ForEach(changes.files.prefix(Self.fileLimit)) { file in fileRow(file) }
                        if changes.files.count > Self.fileLimit { note("and \(changes.files.count - Self.fileLimit) more") }
                    }
                } else {
                    ProgressView().controlSize(.small).frame(height: 34)
                }
                if uncommitted {
                    HStack(spacing: 8) {
                        Text("Commit message").font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary)
                        TextField("Commit message", text: $message).textFieldStyle(.plain).font(.system(size: 12.5))
                            .padding(.horizontal, 8).frame(height: 26)
                            .background(RoundedRectangle(cornerRadius: 6).fill(ModalStyle.field))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(ModalStyle.border))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8).overlay(alignment: .bottom) { ModalDivider() }
                }
            } else {
                note("This conversation has no Diorama worktree, so git steps are unavailable. You can still send feedback or mark it done.")
            }
        }
    }
    private func fileRow(_ file: ChangedFile) -> some View {
        let letter = file.untracked ? "A" : String(file.status.prefix(1)).uppercased()
        let color: Color = switch letter {
        case "A": SidebarStyle.tint(.done).text
        case "D": ModalStyle.red
        case "R": SidebarStyle.tint(.inProgress).text
        default: SidebarStyle.tint(.needsYou).text
        }
        return HStack(spacing: 10) {
            Text(letter).font(.system(size: 11, weight: .bold)).foregroundStyle(color).frame(width: 16, alignment: .leading)
            Text(file.path).font(ModalStyle.mono).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
            (Text("+\(file.added)").foregroundColor(SidebarStyle.tint(.done).text) + Text(" ") + Text("−\(file.removed)").foregroundColor(ModalStyle.red))
                .font(.system(size: 11.5)).monospacedDigit().frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 16).frame(height: 34).overlay(alignment: .bottom) { ModalDivider() }
        .accessibilityElement(children: .combine)
    }
    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { ModalDivider() }
    }

    // MARK: What was done
    private var plan: AgentPlan? { agent.value.plan.flatMap { $0.hasTasks && !$0.tasksPreviousTurn ? $0 : nil } }
    private var doneSummary: String {
        var parts: [String] = []
        if let plan { parts.append("\(plan.completedTaskCount) of \(plan.checklist.count) steps") }
        let tests = agent.value.turnWork.tests
        if tests.contains(where: { $0.outcome == .failed }) { parts.append("tests failed") }
        else if !tests.isEmpty, tests.allSatisfy({ $0.outcome == .passed }) { parts.append("tests passed") }
        return parts.joined(separator: " · ")
    }
    private var doneSection: some View {
        let work = agent.value.turnWork
        return VStack(spacing: 0) {
            ModalSectionBand(title: "What was done") { Text(doneSummary) }
            VStack(alignment: .leading, spacing: 0) {
                if let plan {
                    ForEach(plan.checklist, id: \.id) { step in
                        HStack(spacing: 10) {
                            Image(systemName: step.status == "completed" ? "checkmark.circle.fill" : ["inProgress", "in_progress"].contains(step.status) ? "circle.lefthalf.filled" : "circle")
                                .font(.system(size: 13)).foregroundStyle(step.status == "completed" ? SidebarStyle.tint(.done).dot : SidebarStyle.secondary)
                            Text(step.title).font(.system(size: 12.5)).lineLimit(2)
                        }
                        .frame(minHeight: 28, alignment: .leading)
                    }
                } else {
                    let lines = [work.files.isEmpty ? nil : "Edited \(work.files.count) file\(work.files.count == 1 ? "" : "s")",
                                 work.commands == 0 ? nil : "Ran \(work.commands) command\(work.commands == 1 ? "" : "s")" + (work.failedCommands > 0 ? " (\(work.failedCommands) failed)" : "")].compactMap { $0 }
                    if lines.isEmpty { Text("No steps reported for this turn.").font(.system(size: 12.5)).foregroundStyle(SidebarStyle.secondary).frame(minHeight: 28) }
                    ForEach(lines, id: \.self) { line in Text(line).font(.system(size: 12.5)).frame(minHeight: 28, alignment: .leading) }
                }
                if !work.tests.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(work.tests.suffix(3).enumerated()), id: \.offset) { _, test in testPill(test) }
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func testPill(_ test: TurnWork.TestRun) -> some View {
        let command = String((test.command.split(separator: "\n").first.map(String.init) ?? "tests").prefix(28))
        let outcome: String
        switch test.outcome { case .passed: outcome = "passed"; case .failed: outcome = "failed"; case .running: outcome = "running"; case .unknown: outcome = "unknown" }
        let tint: Color = test.outcome == .passed ? SidebarStyle.tint(.done).text : test.outcome == .failed ? ModalStyle.red : SidebarStyle.secondary
        return Text(command + " · " + outcome).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            .foregroundStyle(tint).padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.12)))
    }

    // MARK: Feedback
    private var feedbackSection: some View {
        VStack(spacing: 0) {
            ModalSectionBand(title: "Not quite right?") { EmptyView() }.overlay(alignment: .top) { ModalDivider() }
            VStack(alignment: .leading, spacing: 8) {
                Text("Tell \(providerName) what to change. It goes back to work on this task.").font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary)
                TextField("e.g. Keep the old icon for the dock…", text: $feedback, axis: .vertical).lineLimit(3...5)
                    .textFieldStyle(.plain).font(.system(size: 13)).padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(ModalStyle.field))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ModalStyle.border))
                HStack {
                    Spacer()
                    Button(busy == "feedback" ? "Sending…" : "Send feedback") { Task { await sendFeedback() } }
                        .buttonStyle(ModalSecondaryButtonStyle(height: 28))
                        .disabled(feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy != nil)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    // MARK: Footer
    @ViewBuilder private var footerActions: some View {
        if workspace != nil {
            if uncommitted {
                Button(busy == "commit" ? "Committing…" : "Commit") { Task { await commit() } }
                    .buttonStyle(ModalSecondaryButtonStyle()).disabled(busy != nil || active || message.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Button(workspace?.pullRequest == nil ? "Push & open PR…" : "Update PR…") { showPR = true }
                .buttonStyle(ModalSecondaryButtonStyle()).disabled(busy != nil || active)
            if workspace?.pullRequest != nil || !uncommitted {
                Button(busy == "merge" ? "Merging…" : mergeTitle) { Task { await merge() } }
                    .buttonStyle(ModalSecondaryButtonStyle()).disabled(busy != nil || active || (uncommitted && workspace?.pullRequest == nil))
            }
        }
        Button("Mark done") { approve(note: nil) }.buttonStyle(ModalPrimaryButtonStyle()).disabled(busy != nil)
    }
    private var mergeTitle: String {
        if let pr = workspace?.pullRequest, pr.state == "OPEN" { return "Merge PR" }
        return "Merge into \(project?.base ?? "base")"
    }
    private var mergeHint: String {
        if let pr = workspace?.pullRequest, pr.state == "OPEN" { return "Merges pull request #\(pr.number) on GitHub, then updates your local \(pr.baseRefName ?? project?.base ?? "base")." }
        return "Mark done finishes without git. Commit saves the changes on this task's branch. Merge brings the committed branch into \(project?.base ?? "the base branch") in \(project?.folder ?? "your project folder")."
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
            // Not cleared: until the new turn shows up, the chef would look finished and idle.
            reviews.set(agent.conversationID, .reworking)
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
