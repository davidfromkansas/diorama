import SwiftUI
import DioramaCore

struct LinkedProjectPRView: View {
    let projectID: String
    @Bindable var library: LibraryModel
    @State private var filter = "OPEN"
    @State private var refreshing = false
    @Environment(\.scenePhase) private var phase
    private var project: DioramaProject? { library.projects.projects.first { $0.id == projectID } }
    private var rows: [LinkedPullRequest] {
        var seen = Set<String>()
        return (project?.workspaces.compactMap(\.pullRequest) ?? []).filter { $0.state == filter && seen.insert($0.id).inserted }.sorted { $0.number > $1.number }
    }
    var body: some View {
        VStack {
            HStack {
                Picker("Pull requests", selection: $filter) { Text("Open").tag("OPEN"); Text("Merged").tag("MERGED"); Text("Closed").tag("CLOSED") }.pointingHand().pickerStyle(.segmented).frame(maxWidth: 320)
                Spacer(); Button("Refresh") { Task { await refresh(force: true) } }.pointingHand().disabled(refreshing)
            }.padding(16)
            if rows.isEmpty { ContentUnavailableView("No linked pull requests", systemImage: "arrow.triangle.pull", description: Text("Pull requests linked to your sessions will appear here.")) }
            List {
                ForEach(rows) { pr in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(pr.title).font(.headline)
                        Text(pr.summary).font(.callout).foregroundStyle(.secondary)
                        if let url = URL(string: pr.url) { Link("Open on GitHub", destination: url).pointingHand() }
                        ForEach(project?.workspaces.filter { $0.pullRequest?.id == pr.id } ?? []) { work in
                            Button { open(work) } label: { Label(sessionTitle(work), systemImage: "bubble.left") }.pointingHand()
                                .disabled(!library.sessions.contains { $0.sessionID == work.threadID })
                            if let error = library.reviews.state(work.id).prError { Text("Last known status · " + error).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                        }
                    }.padding(.vertical, 8)
                }
                ForEach(project?.workspaces.filter { library.reviews.state($0.id).prError != nil && $0.pullRequest == nil } ?? []) { work in
                    VStack(alignment: .leading) {
                        Button(sessionTitle(work)) { open(work) }.pointingHand()
                        Text(library.reviews.state(work.id).prError ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(project?.workspaces.filter { !library.reviews.state($0.id).candidates.isEmpty } ?? []) { work in
                    Menu("Choose PR for " + sessionTitle(work)) {
                        ForEach(library.reviews.state(work.id).candidates) { pr in
                            Button("#\(pr.number) · \(pr.title)") {
                                library.projects.updateWorkspace(projectID, id: work.id) { $0.pullRequest = pr }
                                library.reviews.state(work.id).candidates = []
                            }.pointingHand()
                        }
                    }.pointingHand()
                }
            }
        }
        .task(id: projectID) {
            while !Task.isCancelled {
                if phase == .active { await refresh() }
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
        .onChange(of: phase) { if phase == .active { Task { await refresh(force: true) } } }
    }
    private func sessionTitle(_ work: ProjectWorkspace) -> String { library.sessions.first { $0.sessionID == work.threadID }?.title ?? work.branch }
    private func open(_ work: ProjectWorkspace) {
        guard let session = library.sessions.first(where: { $0.sessionID == work.threadID }) else { return }
        library.reviews.state(work.id).visible = true
        library.projects.update(projectID) { $0.selectedSession = session.id; $0.section = "Sessions" }; library.selectedID = session.id
    }
    private func refresh(force: Bool = false) async {
        guard let project, !refreshing else { return }; refreshing = true
        defer { refreshing = false }
        for work in project.workspaces where work.threadID != nil {
            guard !Task.isCancelled else { return }
            let state = library.reviews.state(work.id)
            do {
                let matches = try await PullRequestService.shared.discover(project: project, workspace: work, force: force)
                guard !Task.isCancelled else { return }
                state.prError = nil
                let match = matches.first { $0.id == work.pullRequest?.id } ?? (matches.count == 1 ? matches[0] : nil)
                library.projects.updateWorkspace(projectID, id: work.id) { $0.pullRequest = match }
                state.candidates = matches.count > 1 ? matches : []
            } catch { state.prError = error.localizedDescription }
        }
    }
}
