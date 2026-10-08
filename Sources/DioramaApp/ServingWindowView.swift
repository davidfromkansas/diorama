import DioramaCore
import SwiftUI

/// The kitchen's serving window: review an agent's finished work, then send feedback, mark it
/// done, commit, open a pull request, or merge. With a pull request open it follows CI and
/// GitHub's merge test live, and a conflict or failed check goes back to the agent from here.
/// The chef reacts to each decision.
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
    @State private var conflicts: PRConflicts?
    @State private var fixText = ""
    @State private var fixEdited = false
    @State private var mergeMethod: ServingWindowGit.MergeMethod = .squash
    @State private var refreshingPR = false
    private var reviews: KitchenReviews { .shared }
    private var project: DioramaProject? { library.projects.projects.first { $0.id == agent.projectID } }
    private var workspace: ProjectWorkspace? { project?.workspaces.first { $0.threadID == session.sessionID } }
    private var state: KitchenReviews.State { reviews.state(agent.conversationID) ?? .awaiting }
    private var active: Bool { library.execution.tasks.values.contains { $0.phase.active && $0.folder == workspace?.folder } }
    private var pr: LinkedPullRequest? { workspace?.pullRequest }
    private var openPR: LinkedPullRequest? { pr.flatMap { $0.state == "OPEN" ? $0 : nil } }
    private var fixPending: Bool { reviews.fixes[agent.conversationID] != nil }
    private var watcher: PRWatcher { .shared }

    var body: some View {
        let band = self.band
        VStack(spacing: 0) {
            ModalHeader(group: band.group, title: TaskTitle.full(session.displayTitle), status: statusWord, model: modelName, detail: finished) { dismiss() }
            ModalBand(group: band.group, title: band.title, detail: band.detail)
            // Desktop layout: what changed on the left, your feedback in its own column on the right.
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        if let pr { ServingPRSection(pr: pr, conflicts: pr.health == .conflicted ? conflicts : nil, refreshing: refreshingPR) }
                        changesSection
                        doneSection
                    }
                }
                .frame(maxWidth: .infinity)
                Group { if let openPR, openPR.health.needsFix || fixPending { fixSection(openPR) } else { feedbackSection } }
                    .frame(width: 300).frame(maxHeight: .infinity, alignment: .top)
                    .background(Color(red: 0.976, green: 0.965, blue: 0.945))
                    .overlay(alignment: .leading) { Rectangle().fill(SidebarStyle.divider).frame(width: 1) }
            }
            .frame(minHeight: 340, maxHeight: 520)
            if error != nil || notice != nil || watcher.errors[agent.conversationID] != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let error { Text(error).foregroundStyle(ModalStyle.red) }
                    else if let failure = watcher.errors[agent.conversationID] { Text(failure).foregroundStyle(ModalStyle.red) }
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
        .reviewModalSurface(width: 820)
        .task { message = Self.defaultMessage(agent.value.task); await refresh() }
        // Follow the pull request live while the window is open.
        .task(id: pr?.url) {
            guard pr != nil else { return }
            while !Task.isCancelled {
                await refreshPR()
                do { try await Task.sleep(for: .seconds(openPR?.health == .checking ? 10 : 30)) } catch { return }
            }
        }
        .sheet(isPresented: $showPR, onDismiss: { Task { await afterPR() } }) {
            if let project, let workspace { GitHubPRView(projectID: project.id, workspace: workspace, library: library) }
        }
    }

    // MARK: Header and band
    private var band: (group: AgentSidebarGroup, title: String, detail: String?) {
        switch state {
        case .awaiting: (.done, "Ready for your review", "stays in Done until you decide")
        case .committed: (.done, "Committed locally", reviews.note(agent.conversationID))
        case .shipped: (.done, reviews.note(agent.conversationID) ?? "Pull request open", pr.map { "#\($0.number)" })
        case .checking: (.inProgress, "CI is tasting the pull request", reviews.note(agent.conversationID))
        case .needsFix: (.needsYou, fixPending ? "Fix sent back" : "The pull request needs a fix", reviews.note(agent.conversationID))
        case .merged: (.done, "Merged", reviews.note(agent.conversationID))
        case .approved: (.done, "Done", nil)
        case .reworking: (.inProgress, fixPending ? "Back to work on the pull request" : "Back to work on your feedback", nil)
        }
    }
    private var statusWord: String {
        switch state {
        case .awaiting, .approved: "Done"; case .committed: "Committed"; case .shipped: "PR open"; case .reworking: "Reworking"
        case .checking: "Checking"; case .needsFix: "Needs fix"; case .merged: "Merged"
        }
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
            ModalSectionBand(title: "Not quite right?") { EmptyView() }
            VStack(alignment: .leading, spacing: 8) {
                Text("Tell \(providerName) what to change. It goes back to work on this task.").font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary)
                TextField("e.g. Keep the old icon for the dock…", text: $feedback, axis: .vertical).lineLimit(6...12)
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

    // MARK: Fix
    /// A conflict or failed check: what goes back to the agent, editable before it's sent.
    private func fixSection(_ pr: LinkedPullRequest) -> some View {
        VStack(spacing: 0) {
            ModalSectionBand(title: "Send back to fix") { EmptyView() }
            VStack(alignment: .leading, spacing: 8) {
                if fixPending {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(watcher.pushing.contains(agent.conversationID) ? "Pushing the fix to #\(pr.number)…"
                             : "\(providerName) is fixing #\(pr.number). When it finishes, Diorama pushes to the same pull request and CI runs again.")
                            .font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(pr.health == .conflicted
                         ? "Diorama merges \(pr.baseRefName ?? "the base branch") into this branch, then \(providerName) resolves the conflicts. You can edit the instructions."
                         : "\(providerName) gets the failing checks and their logs. You can edit the instructions.")
                        .font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary).fixedSize(horizontal: false, vertical: true)
                    TextField("Instructions", text: Binding(get: { fixText }, set: { if $0 != fixText { fixText = $0; fixEdited = !$0.isEmpty } }), axis: .vertical).lineLimit(8...14)
                        .textFieldStyle(.plain).font(.system(size: 12)).padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(ModalStyle.field))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ModalStyle.border))
                    Text("After the fix, Diorama pushes to #\(pr.number) and checks again.").font(.system(size: 11.5)).foregroundStyle(SidebarStyle.secondary)
                    HStack {
                        Spacer()
                        Button(busy == "fix" ? "Sending…" : "Send to \(providerName) to fix") { Task { await sendFix(pr) } }
                            .buttonStyle(ModalPrimaryButtonStyle(height: 28))
                            .disabled(fixText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy != nil || active)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    // MARK: Footer
    @ViewBuilder private var footerActions: some View {
        if let openPR, workspace != nil {
            if uncommitted {
                Button(busy == "commit" ? "Committing…" : "Commit") { Task { await commit() } }
                    .buttonStyle(ModalSecondaryButtonStyle()).disabled(busy != nil || active || message.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Update PR…") { showPR = true }.buttonStyle(ModalSecondaryButtonStyle()).disabled(busy != nil || active)
            }
            if openPR.health == .behind {
                Button(busy == "update" ? "Updating…" : "Update branch") { Task { await updateBranch(openPR) } }
                    .buttonStyle(ModalSecondaryButtonStyle()).disabled(busy != nil || active || uncommitted)
                    .help("Merges the latest \(openPR.baseRefName ?? "base") into this branch and pushes it.")
            }
            Button("Mark done") { approve(note: nil) }.buttonStyle(ModalSecondaryButtonStyle()).disabled(busy != nil)
            Picker("Merge method", selection: $mergeMethod) {
                ForEach(ServingWindowGit.MergeMethod.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).fixedSize().disabled(openPR.health != .ready)
            let ready = openPR.health == .ready
            Group {
                if ready {
                    Button(busy == "merge" ? "Merging…" : "Merge PR") { Task { await merge() } }.buttonStyle(ModalPrimaryButtonStyle())
                } else {
                    Button("Merge PR") {}.buttonStyle(ModalSecondaryButtonStyle()).disabled(true)
                }
            }
            .disabled(busy != nil || active)
            .help(ready ? "Merges #\(openPR.number) on GitHub, then updates your local \(openPR.baseRefName ?? "base")." : "Merging waits until checks pass and #\(openPR.number) merges cleanly.")
        } else if workspace != nil, pr?.state != "MERGED" {
            // A merged pull request has nothing left to commit, push or merge.
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
        if openPR == nil || workspace == nil {
            Button("Mark done") { approve(note: nil) }.buttonStyle(ModalPrimaryButtonStyle()).disabled(busy != nil)
        }
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
            // A new or updated PR starts in CI; the live refresh moves it on from there.
            if pr.state == "MERGED" { reviews.set(agent.conversationID, .merged, note: "Merged #\(pr.number)") }
            else { reviews.set(agent.conversationID, .checking, note: "PR #\(pr.number) · waiting for checks") }
            await refreshPR()
        }
    }
    /// Re-reads the pull request, moves the chef to match, and works out conflicting files.
    private func refreshPR() async {
        guard let project, let workspace, let current = workspace.pullRequest else { return }
        refreshingPR = true; defer { refreshingPR = false }
        guard let fresh = try? await GitHubPullRequests.get(current.url).carrying(from: current) else { return }
        if fresh != current { library.projects.updateWorkspace(project.id, id: workspace.id) { $0.pullRequest = fresh } }
        if !fixPending { PRWatcher.apply(fresh, conversation: agent.conversationID, reviews: reviews) }
        if fresh.health == .conflicted, let base = fresh.baseRefName, conflicts == nil {
            try? await PullRequestRepair.fetchBase(worktree: workspace.folder, base: base)
            conflicts = try? await PullRequestRepair.conflicts(worktree: workspace.folder, base: base)
        }
        if fresh.health.needsFix, !fixEdited {
            fixText = PullRequestRepair.fixPrompt(fresh, conflicts: fresh.health == .conflicted ? conflicts : nil, mergeStarted: fresh.health == .conflicted)
        }
    }
    /// Sends a conflict or failed check back to the agent. On a conflict Diorama starts the merge
    /// itself (agents may not reach the network or the shared Git directory); a clean merge with
    /// nothing else wrong is pushed straight away.
    private func sendFix(_ pr: LinkedPullRequest) async {
        guard let workspace else { return }
        var text = fixText.trimmingCharacters(in: .whitespacesAndNewlines)
        await run("fix") {
            var merged: [String] = []
            if pr.health == .conflicted, let base = pr.baseRefName {
                try await PullRequestRepair.fetchBase(worktree: workspace.folder, base: base)
                merged = try await PullRequestRepair.mergeBase(worktree: workspace.folder, base: base)
                if merged.isEmpty {
                    if pr.failedChecks.isEmpty {
                        try await pushNow(pr, message: "Merge \(base)")
                        notice = "\(base) merged cleanly into this branch and was pushed to #\(pr.number)."
                        return
                    }
                    if !fixEdited { text = PullRequestRepair.fixPrompt(pr, conflicts: nil, mergeStarted: false) }
                }
            }
            reviews.setFix(agent.conversationID, .init(pullRequest: pr.url, mergedFiles: merged))
            do { try await library.execution.send(in: session, prompt: text) }
            catch {
                reviews.setFix(agent.conversationID, nil)
                if !merged.isEmpty { _ = try? await ProjectCommand.git(workspace.folder, ["merge", "--abort"]) }
                throw error
            }
            reviews.set(agent.conversationID, .reworking)
            fixEdited = false
            dismiss()
        }
    }
    /// Brings a branch that's behind its base up to date and pushes it, without the agent.
    private func updateBranch(_ pr: LinkedPullRequest) async {
        guard let workspace, let base = pr.baseRefName else { return }
        await run("update") {
            try await PullRequestRepair.fetchBase(worktree: workspace.folder, base: base)
            let conflicted = try await PullRequestRepair.mergeBase(worktree: workspace.folder, base: base)
            guard conflicted.isEmpty else {
                _ = try? await ProjectCommand.git(workspace.folder, ["merge", "--abort"])
                throw AppServerFailure("\(base) conflicts with this branch in \(conflicted.joined(separator: ", ")). Send it back to the agent to resolve.")
            }
            try await pushNow(pr, message: "Merge \(base)")
            notice = "Brought \(base) into this branch and pushed it to #\(pr.number)."
        }
    }
    private func pushNow(_ pr: LinkedPullRequest, message: String) async throws {
        guard let project, let workspace else { return }
        let execution = library.execution
        let fresh = try await PullRequestRepair.pushFollowUp(worktree: workspace.folder, pullRequest: pr, message: message) { folder in
            await MainActor.run { execution.tasks.values.contains { $0.phase.active && $0.folder == folder } }
        }
        library.projects.updateWorkspace(project.id, id: workspace.id) { $0.pullRequest = fresh }
        reviews.set(agent.conversationID, .checking, note: "PR #\(pr.number) · waiting for checks")
        await refresh()
    }
    private func merge() async {
        guard let project, let workspace else { return }
        await run("merge") {
            if let pr = workspace.pullRequest, pr.state == "OPEN" {
                // Merge what was checked: refuse if GitHub's view changed since the last refresh.
                let current = try await GitHubPullRequests.get(pr.url)
                try await ServingWindowGit.mergeOnGitHub(current, method: mergeMethod)
                let merged = try await GitHubPullRequests.confirmMerged(pr.url, merged: true)
                library.projects.updateWorkspace(project.id, id: workspace.id) { $0.pullRequest = merged }
                reviews.set(agent.conversationID, .merged, note: "Merged #\(pr.number)")
                do {
                    try await GitHubBranchUpdate.update(projectFolder: project.folder, pullRequest: merged) { folder in
                        await MainActor.run { library.execution.tasks.values.contains { $0.phase.active && $0.folder == folder } }
                    }
                    dismiss()
                } catch {
                    notice = "Merged #\(pr.number). Your local \(merged.baseRefName ?? project.base) wasn't updated: \(error.localizedDescription)"
                }
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
