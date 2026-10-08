import AppKit
import SwiftUI
import DioramaCore

/// Add a GitHub project: connect if needed, pick one of the account's repositories, then watch it
/// clone. Modelled on agentsim's GitHub project dialog. The project opens as soon as it clones.
struct GitHubProjectSheet: View {
    let opened: (DioramaProject) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var identity: GitHubIdentity?
    @State private var checked = false
    @State private var repositories: [GitHubRepo] = []
    @State private var loading = false
    @State private var page = 0
    @State private var hasMore = true
    @State private var query = ""
    @State private var parent = ProjectStorage.newProjectsDirectory.path
    @State private var status: String?
    @State private var clone: CloneRun?
    @State private var cloneTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Text("Choose a repository to clone into \(Self.abbreviate(parent)). Connect once and use GitHub across every project.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.vertical, 14)
            Divider()
            Group {
                if let clone { clonePanel(clone) }
                else if identity != nil { repositoryPanel }
                else if checked { GitHubConnectPanel { if let value = $0 { connected(value) } }.padding(20) }
                else { ProgressView().controlSize(.small).accessibilityLabel("Checking GitHub connection") }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            footer
        }
        .frame(width: 680, height: 600)
        .task { await checkConnection() }
        .onDisappear { cloneTask?.cancel() }
    }

    // MARK: Header and footer

    private var header: some View {
        HStack(spacing: 12) {
            GitHubMarkTile(size: 36, mark: 19)
            VStack(alignment: .leading, spacing: 3) {
                Text("GITHUB").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(.secondary)
                Text("Add a GitHub project").font(.system(size: 20, weight: .semibold)).tracking(-0.4)
            }
            Spacer()
            Button { cloneTask?.cancel(); dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .medium)).frame(width: 30, height: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).help("Close").accessibilityLabel("Close")
            .keyboardShortcut(.cancelAction).pointingHand()
        }.padding(.horizontal, 20).padding(.vertical, 16)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.green.opacity(0.7)).frame(width: 6, height: 6)
                .overlay(Circle().stroke(Color.green.opacity(0.15), lineWidth: 3))
            Text("Clones go to \(Self.abbreviate(parent))").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            Button("Change…", action: chooseParent).buttonStyle(.link).font(.system(size: 10)).pointingHand()
                .disabled(clone?.state == .running)
            Spacer(minLength: 12)
            if let status {
                Text(status).font(.system(size: 10, design: .monospaced)).foregroundStyle(.orange)
                    .lineLimit(2).multilineTextAlignment(.trailing).textSelection(.enabled)
            }
        }.padding(.horizontal, 20).frame(minHeight: 42)
    }

    // MARK: Repositories

    private var repositoryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your repositories").font(.system(size: 13, weight: .semibold))
                    Text(identity.map { "Connected as @" + $0.login } ?? "").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("Search by repository name", text: $query).textFieldStyle(.plain).font(.system(size: 12)).focused($searchFocused)
                }
                .padding(.horizontal, 9).padding(.vertical, 8).frame(width: 300)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(searchFocused ? 0.3 : 0.14)))
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    let rows = filtered
                    if rows.isEmpty && !loading {
                        Text(query.isEmpty ? "No repositories are available for this account." : "No repositories match this search.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 54).frame(maxWidth: .infinity)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, repository in
                        RepositoryRow(repository: repository) { start(repository) }
                        if index < rows.count - 1 { Divider() }
                    }
                    if hasMore && !repositories.isEmpty {
                        // Pages arrive 100 at a time, most recently updated first.
                        ProgressView().controlSize(.small).padding(14).onAppear { Task { await loadPage() } }
                    } else if loading {
                        ProgressView().controlSize(.small).padding(30)
                    }
                }
            }
            .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.12)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(loading && repositories.isEmpty ? 0.6 : 1)
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 14)
        .onAppear { searchFocused = true }
    }

    private var filtered: [GitHubRepo] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return repositories }
        return repositories.filter { ($0.full_name + " " + ($0.description ?? "")).lowercased().contains(needle) }
    }

    private struct RepositoryRow: View {
        let repository: GitHubRepo
        let add: () -> Void
        @State private var hovering = false
        var body: some View {
            HStack(spacing: 11) {
                Text(String(repository.full_name.split(separator: "/").last ?? "GH").prefix(2).uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.12)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(repository.full_name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(meta).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text(repository.description?.isEmpty == false ? repository.description! : "No description")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Button("Add project", action: add).controlSize(.small).pointingHand()
                    .accessibilityLabel("Add \(repository.full_name) to Diorama")
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(hovering ? Color.primary.opacity(0.04) : .clear)
            .onHover { hovering = $0 }
        }
        private var meta: String {
            var parts = [repository.private ? "Private" : "Public"]
            if let value = repository.updated_at, let date = try? Date(value, strategy: .iso8601) {
                parts.append("Updated " + date.formatted(.dateTime.month(.abbreviated).day()))
            }
            return parts.joined(separator: " · ")
        }
    }

    // MARK: Clone

    struct CloneRun {
        enum State: Equatable { case running, success, failed, cancelled }
        let repository: GitHubRepo
        let destination: String
        var state = State.running
        var lines: [String] = []
        var partial = ""
        var text: String { (partial.isEmpty ? lines : lines + [partial]).joined(separator: "\n") }

        /// Git rewrites progress lines with carriage returns; keep only each line's latest state.
        mutating func append(_ chunk: String) {
            let clean = chunk.replacingOccurrences(of: "\u{1B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\r\n", with: "\n")
            for character in clean {
                if character == "\n" { lines.append(partial); partial = "" }
                else if character == "\r" { partial = "" }
                else { partial.append(character) }
            }
            if lines.count > 320 { lines.removeFirst(lines.count - 320) }
        }
    }

    private func clonePanel(_ run: CloneRun) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                CloneStatusIcon(state: run.state)
                VStack(alignment: .leading, spacing: 3) {
                    Text(stateLabel(run.state)).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(0.4)
                        .foregroundStyle(run.state == .success ? Color.green : run.state == .running ? Color.secondary : Color.red.opacity(0.85))
                    Text(run.repository.full_name).font(.system(size: 14, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Text(Self.abbreviate(run.destination)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.head)
            }
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    ForEach([Color(red: 0.5, green: 0.33, blue: 0.3), Color(red: 0.46, green: 0.42, blue: 0.29), Color(white: 0.25)], id: \.self) { color in
                        Circle().fill(color).frame(width: 7, height: 7)
                    }
                    Text("git clone").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).padding(.leading, 6)
                    Spacer()
                }.padding(.horizontal, 11).frame(height: 30).background(Color(white: 0.1))
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(run.text.isEmpty ? "Starting…" : run.text)
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(Color(white: 0.74))
                            .lineSpacing(4).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        Color.clear.frame(height: 1).id("end")
                    }
                    .onChange(of: run.text) { proxy.scrollTo("end", anchor: .bottom) }
                }
                .accessibilityLabel("Live Git clone output")
            }
            .background(Color(white: 0.055), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.1)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .environment(\.colorScheme, .dark)
            HStack(spacing: 8) {
                Spacer()
                switch run.state {
                case .running:
                    Button("Cancel clone") { cloneTask?.cancel() }.pointingHand()
                case .failed, .cancelled:
                    Button("Back to repositories") { clone = nil; status = nil }.pointingHand()
                    Button("Try again") { start(run.repository) }.keyboardShortcut(.defaultAction).pointingHand()
                case .success:
                    Text("Opening project…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.frame(minHeight: 30)
        }.padding(.horizontal, 20).padding(.vertical, 18)
    }

    private func stateLabel(_ state: CloneRun.State) -> String {
        switch state {
        case .running: "CLONING REPOSITORY"
        case .success: "CLONED"
        case .failed: "CLONE FAILED"
        case .cancelled: "CLONE CANCELLED"
        }
    }

    private struct CloneStatusIcon: View {
        let state: CloneRun.State
        var body: some View {
            Group {
                switch state {
                case .running: ProgressView().controlSize(.small)
                case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed, .cancelled: Image(systemName: "xmark.circle.fill").foregroundStyle(.red.opacity(0.8))
                }
            }.font(.system(size: 24)).frame(width: 30, height: 30).accessibilityHidden(true)
        }
    }

    // MARK: Actions

    private func checkConnection() async {
        identity = try? await GitHubAccount.shared.identity()
        checked = true
        if identity != nil { await loadPage() }
    }

    private func connected(_ value: GitHubIdentity) {
        identity = value; repositories = []; page = 0; hasMore = true
        Task { await loadPage() }
    }

    private func loadPage() async {
        guard !loading, hasMore else { return }
        loading = true; defer { loading = false }
        do {
            let rows = try await GitHubAccount.shared.repositories(page: page + 1)
            let known = Set(repositories.map(\.id))
            repositories += rows.filter { !known.contains($0.id) }
            page += 1; hasMore = rows.count == 100
        } catch { status = error.localizedDescription; hasMore = false }
    }

    private func chooseParent() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "Choose"; panel.directoryURL = URL(fileURLWithPath: parent)
        panel.begin { if $0 == .OK, let url = panel.url { parent = url.path } }
    }

    private func start(_ repository: GitHubRepo) {
        status = nil
        let name = String(repository.full_name.split(separator: "/").last ?? "")
        let destination = URL(fileURLWithPath: parent).appendingPathComponent(name).path
        guard !FileManager.default.fileExists(atPath: destination) else {
            status = "\(Self.abbreviate(destination)) already exists. Use Change… to clone somewhere else."
            return
        }
        clone = CloneRun(repository: repository, destination: destination)
        let (output, sink) = AsyncStream.makeStream(of: String.self)
        cloneTask = Task {
            let reader = Task { for await chunk in output { clone?.append(chunk) } }
            do {
                try await GitHubRepositoryService.shared.clone(repository.full_name, to: destination) { sink.yield($0) }
                sink.finish(); await reader.value
                let project = try await ProjectGit.discover(destination)
                clone?.state = .success
                // Let the check register before the sheet gives way to the project.
                try? await Task.sleep(for: .milliseconds(700))
                opened(project)
            } catch is CancellationError {
                sink.finish(); await reader.value
                clone?.append("\nClone cancelled. The partial folder was removed.\n"); clone?.state = .cancelled
            } catch {
                sink.finish(); await reader.value
                clone?.state = .failed; status = error.localizedDescription
            }
            cloneTask = nil
        }
    }

    static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
