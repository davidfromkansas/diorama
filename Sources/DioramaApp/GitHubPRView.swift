import SwiftUI
import DioramaCore

struct GitHubPRView: View {
    let projectID: String
    let workspace: ProjectWorkspace
    @Bindable var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var preview: GitHubPRPreview?
    @State private var selected = Set<String>()
    @State private var focusedFile: String?
    @State private var patch = ""
    @State private var base = ""
    @State private var title = ""
    @State private var description = ""
    @State private var error: String?
    @State private var busy = false
    @State private var submitted = false
    @State private var showAccount = false
    private var active: Bool { library.execution.tasks.values.contains { $0.phase.active && $0.folder == workspace.folder } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preview?.existing == nil ? "Create pull request" : "Update pull request").font(.title2.weight(.semibold))
                    Text(preview?.repository.full_name ?? "Review the code you’ll share on GitHub").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("GitHub account…") { showAccount = true }.pointingHand().disabled(busy)
            }
            if let preview {
                HStack {
                    Label(preview.source, systemImage: "arrow.triangle.branch").lineLimit(1).help(preview.source)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    TextField("Destination branch", text: $base).textFieldStyle(.roundedBorder).frame(maxWidth: 190)
                        .disabled(submitted || preview.existing != nil)
                    Button("Refresh preview") { Task { await load() } }.pointingHand().disabled(busy || submitted)
                }.font(.callout)
                if preview.createsBranch { Text("A new branch will keep these changes separate from \(preview.snapshot.branch).").font(.caption).foregroundStyle(.secondary) }
                DisclosureGroup {
                    ScrollView { Text(preview.commits.isEmpty ? "No additional commits yet." : preview.commits).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 100)
                } label: { Text("Commits to share").disclosurePointingHand() }
                if preview.pendingTitle != nil { Text("A previous submission is unfinished. Retry resumes its saved commit, branch, and PR details.").font(.callout).foregroundStyle(.secondary) }
                if !preview.snapshot.files.isEmpty && preview.pendingTitle == nil {
                    Text("Include files").font(.headline)
                    HSplitView {
                        List(preview.snapshot.files) { file in
                            HStack(alignment: .top) {
                                Toggle(file.path, isOn: Binding(get: { selected.contains(file.path) }, set: { value in
                                    if value { selected.insert(file.path) } else { selected.remove(file.path) }
                                })).pointingHand().labelsHidden().accessibilityLabel("Include " + file.path).disabled(submitted)
                                Button { focusedFile = file.path } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(file.path).lineLimit(2).help(file.path)
                                        Text(file.status).font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.pointingHand().buttonStyle(.plain)
                            }.padding(.vertical, 3)
                        }.frame(minWidth: 180, idealWidth: 220)
                        DiffTextView(patch: patch).frame(minWidth: 240)
                    }.frame(height: 200)
                    Text("Selected files use their current contents. Unselected edits and staged changes stay local.").font(.caption).foregroundStyle(.secondary)
                }
                TextField("Pull request title", text: $title).textFieldStyle(.roundedBorder).disabled(submitted)
                TextEditor(text: $description).font(.body).frame(height: 80).padding(6).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Pull request description").disabled(submitted)
                Text("Submitting commits the selected files, pushes this branch, and \(preview.existing == nil ? "creates" : "updates") the pull request. Review and merge on GitHub.").font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            if active { Text("Wait for active work in this checkout to finish.").font(.callout).foregroundStyle(.secondary) }
            HStack {
                Button("Close") { dismiss() }.pointingHand().keyboardShortcut(.cancelAction).disabled(busy)
                if submitted {
                    Button("Refresh changed files") {
                        Task {
                            do { try await GitHubPRSubmission.shared.refreshUncommittedPreparation(folder: workspace.folder); submitted = false; await load() }
                            catch { self.error = error.localizedDescription }
                        }
                    }.pointingHand().disabled(busy)
                }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                if preview == nil { Button("Load preview") { Task { await load() } }.pointingHand().disabled(busy || active) }
                else {
                    Button(submitted ? "Retry submission" : preview?.existing == nil ? "Create PR" : "Update PR") { Task { await submit() } }.pointingHand()
                        .buttonStyle(.borderedProminent).disabled(busy || active || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || base != preview?.base)
                }
            }
        }.padding(24).frame(width: 720).disabled(busy)
        .interactiveDismissDisabled(busy)
        .task { await load() }
        .task(id: focusedFile) {
            guard let preview, let file = preview.snapshot.files.first(where: { $0.path == focusedFile }) else { patch = ""; return }
            do { let result = try await SessionChanges.diff(file, workspace: workspace, scope: .uncommitted); if focusedFile == file.path { patch = result } }
            catch { patch = error.localizedDescription }
        }
        .sheet(isPresented: $showAccount) {
            VStack(alignment: .leading, spacing: 20) {
                GitHubSettingsView()
                HStack { Spacer(); Button("Done") { showAccount = false }.pointingHand() }
            }.padding(24).frame(width: 620)
        }
    }
    private func load() async {
        guard !active else { return }
        busy = true; defer { busy = false }
        do {
            let value = try await GitHubPRSubmission.shared.preview(workspace: workspace, base: base)
            preview = value; base = value.base; selected = Set(value.snapshot.files.map(\.path)); focusedFile = value.snapshot.files.first?.path
            if let pendingTitle = value.pendingTitle { title = pendingTitle; description = value.pendingBody ?? ""; submitted = true }
            if title.isEmpty { title = value.existing?.title ?? value.commits.split(separator: "\n").first.map { String($0.drop(while: { $0 != " " }).dropFirst()) } ?? "" }
            if description.isEmpty { description = value.existing?.body ?? "" }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func submit() async {
        guard let preview, !active else { return }
        busy = true; submitted = true; defer { busy = false }
        do {
            let pr = try await GitHubPRSubmission.shared.submit(preview, selected: selected, title: title, body: description) { folder in
                await MainActor.run { library.execution.tasks.values.contains { $0.phase.active && $0.folder == folder } }
            }
            library.projects.updateWorkspace(projectID, id: workspace.id) { $0.pullRequest = pr; $0.branch = pr.headRefName }
            try library.projects.checkpoint()
            try await GitHubPRSubmission.shared.acknowledge(folder: workspace.folder)
            dismiss()
        } catch {
            self.error = error.localizedDescription
            submitted = await GitHubPRSubmission.shared.hasPending(folder: workspace.folder)
        }
    }
}
