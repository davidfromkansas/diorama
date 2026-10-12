import DioramaCore
import SwiftUI

/// How many files each task changed since it began, the same count the Changes panel shows,
/// for a done chef's tag. Read from git in the background and kept for a short while.
@MainActor final class SessionChangeCounts {
    static let shared = SessionChangeCounts()
    static let freshFor: TimeInterval = 20
    /// Bumped when a count changes, so the kitchen knows to rewrite its tags.
    private(set) var revision = 0
    private var counts: [String: (files: Int, at: Date)] = [:]
    private var loading: Set<String> = []

    /// The last known count (nil until the first read finishes); refreshes it when it's old.
    func count(_ workspace: ProjectWorkspace, now: Date = Date()) -> Int? {
        let known = counts[workspace.id]
        if now.timeIntervalSince(known?.at ?? .distantPast) > Self.freshFor, !loading.contains(workspace.id) {
            loading.insert(workspace.id)
            Task { [weak self] in
                let snapshot = try? await SessionChanges.snapshot(workspace, scope: .session)
                guard let self else { return }
                self.loading.remove(workspace.id)
                if let snapshot { self.record(workspace, snapshot) }
            }
        }
        return known?.files
    }
    /// A snapshot read elsewhere (the Changes panel, the review): the tag follows it.
    func record(_ workspace: ProjectWorkspace, _ snapshot: ChangesSnapshot, now: Date = Date()) {
        if counts[workspace.id]?.files != snapshot.files.count { revision += 1 }
        counts[workspace.id] = (snapshot.files.count, now)
    }
}

/// Which changes to browse, and the file to open first.
struct ChangesBrowsing: Identifiable {
    let workspace: ProjectWorkspace
    var snapshot: ChangesSnapshot?
    var start: String?
    var id: String { workspace.id + (start ?? "") }
}

