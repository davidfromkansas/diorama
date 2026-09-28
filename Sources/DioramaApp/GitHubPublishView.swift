import SwiftUI
import DioramaCore

struct GitHubPublishView: View {
    let project: DioramaProject
    @Bindable var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var account = ""
    @State private var owner = ""
    @State private var name = ""
    @State private var isPrivate = true
    @State private var commits = ""
    @State private var fingerprint: String?
    @State private var busy = false
    @State private var error: String?
    @State private var showAccount = false
    @State private var operation: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Publish to GitHub").font(.title2.weight(.semibold))
            HStack { Text(account.isEmpty ? "Connect your GitHub account to publish" : "Publishing as @" + account).foregroundStyle(.secondary); Spacer(); Button("GitHub account…") { showAccount = true }.disabled(busy) }
            HStack {
                TextField("Owner or organization", text: $owner)
                Text("/").foregroundStyle(.secondary)
                TextField("Repository name", text: $name)
            }.textFieldStyle(.roundedBorder).disabled(busy)
            Picker("Visibility", selection: $isPrivate) { Text("Private").tag(true); Text("Public").tag(false) }.pickerStyle(.segmented).disabled(busy)
            Text(isPrivate ? "Only people you grant access can see this repository." : "Anyone on the internet will be able to see this repository and its committed history.").font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Committed history to upload") {
                ScrollView { Text(commits).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 180)
            }
            Text("Publishes the current branch and its committed history. Uncommitted edits stay on this Mac.").font(.callout).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            HStack {
                Button("Cancel") { operation?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Button("Refresh preview") { Task { await load() } }.disabled(busy)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("Create repository and publish") { operation = Task { await publish() } }.buttonStyle(.borderedProminent)
                    .disabled(busy || fingerprint == nil || owner.isEmpty || name.isEmpty)
            }
        }.padding(24).frame(width: 580).interactiveDismissDisabled(busy)
        .task { name = project.name; await load() }
        .onDisappear { operation?.cancel() }
        .sheet(isPresented: $showAccount, onDismiss: { Task { await load() } }) {
            VStack(alignment: .leading, spacing: 20) { GitHubSettingsView(); HStack { Spacer(); Button("Done") { showAccount = false } } }.padding(24).frame(width: 620)
        }
    }
    private func load() async {
        busy = true; defer { busy = false }
        do {
            let identity = try await GitHubAccount.shared.identity(); account = identity.login
            if owner.isEmpty { owner = identity.login }
            commits = try await ProjectCommand.git(project.folder, ["log", "--oneline", "HEAD", "--"])
            fingerprint = try await GitHubPRSubmission.fingerprint(project.folder); error = nil
        } catch { fingerprint = nil; self.error = error.localizedDescription }
    }
    private func publish() async {
        busy = true; defer { busy = false }
        do {
            guard !library.execution.tasks.values.contains(where: { $0.phase.active && $0.folder == project.folder }) else { throw AppServerFailure("Wait for active work in this checkout to finish before publishing.") }
            guard try await GitHubPRSubmission.fingerprint(project.folder) == fingerprint else { throw AppServerFailure("The project changed. Refresh the preview before publishing.") }
            let repo = try await GitHubRepositoryService.shared.publish(folder: project.folder, name: owner + "/" + name, privateRepository: isPrivate)
            library.projects.update(project.id) { $0.remote = "https://github.com/" + repo.full_name + ".git" }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
