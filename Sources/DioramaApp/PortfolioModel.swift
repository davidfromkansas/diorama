import Foundation
import Observation
import DioramaCore

struct PortfolioException: Identifiable, Equatable {
    let agent: SpatialAgent
    let conversation: String
    var id: String { agent.id }
    var priority: Int { agent.value.attentionReason == .approval ? 0 : agent.needsAttention ? 1 : 2 }
    var label: String { priority == 0 ? "Approval needed" : priority == 1 ? "Input needed" : "Reported failure" }
    var destination: SpatialFocus {
        .agent(project: agent.projectID, conversation: agent.conversationID, agent: agent.id, expanded: true)
    }
    static func ordered(_ project: SpatialProject) -> [Self] {
        var seen = Set<String>()
        return project.teams.flatMap { team in
            team.agents.filter { $0.needsAttention || $0.value.status == .failed }.compactMap { agent in
                seen.insert(agent.id).inserted ? Self(agent: agent, conversation: team.title) : nil
            }
        }.sorted {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            let a = $0.agent.value.observedAt ?? .distantFuture, b = $1.agent.value.observedAt ?? .distantFuture
            return a == b ? $0.id < $1.id : a < b
        }
    }
}

/// Presentation coordinates remain independent of the Canvas or a future SceneKit renderer.
/// Agent overlays will use the same unit square and project identity; v1 contains no markers.
nonisolated struct PortfolioSurface: Equatable, Sendable {
    let projectID: String
    func project(u: Double, v: Double, width: Double, height: Double) -> CGPoint {
        CGPoint(x: width * (0.5 + (u - v) * 0.46), y: height * (0.08 + (u + v) * 0.36))
    }
    func contains(u: Double, v: Double) -> Bool { (0...1).contains(u) && (0...1).contains(v) }
}

@Observable final class PortfolioStore {
    var usages: [String: PortfolioUsageSummary] = [:]
    var observations: [String: ExternalObservationSnapshot] = [:]
    var projectOrder: [String] = []
    var scrollID: String?
    private var restored = false
    private var sourceFolders: [String: String] = [:]
    private var primarySources: [String: Session] = [:]
    private var childrenByParent: [String: [String: Session]] = [:]
    private var discovered: [String: Session] = [:]
    private var knownSources: [String: [String: Session]] = [:]
    private var liveLedgers: [String: PortfolioUsageLedger] = [:]
    private var liveValues: [String: WireValue] = [:]
    private let index: PortfolioUsageIndex
    private let activity = ActivityLibrary()
    private var refreshing = false

    init(cache: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Diorama/portfolio-usage-v1.json")) {
        index = PortfolioUsageIndex(cache: cache)
    }
    func register(_ sessions: [Session]) {
        for session in sessions {
            let key = PortfolioUsageIndex.identity(session)
            if let old = discovered[key], session.url == nil && old.url != nil { continue }
            if let old = discovered[key], let parent = old.parentID, parent != session.parentID {
                childrenByParent[old.provider.rawValue + ":" + parent]?[key] = nil
            }
            if let parent = session.parentID {
                childrenByParent[session.provider.rawValue + ":" + parent, default: [:]][key] = session
            }
            if discovered[key]?.project != session.project {
                sourceFolders[key] = URL(fileURLWithPath: session.project).standardizedFileURL.resolvingSymlinksInPath().path
            }
            discovered[key] = session
            if session.classification != .subagent { primarySources[session.provider.rawValue + ":" + session.sessionID] = session }
        }
    }
    func ordered(_ projects: [SpatialProject]) -> [SpatialProject] {
        let lookup = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        return projectOrder.compactMap { lookup[$0] } + projects.filter { !projectOrder.contains($0.id) }
    }
    func usage(_ id: String) -> PortfolioUsageSummary { usages[id] ?? .init() }

    func refresh(_ library: LibraryModel) async {
        guard !refreshing, !library.paused else { return }
        refreshing = true; defer { refreshing = false }
        if !restored {
            let cached = await index.cachedSessions()
            let recent = Array(discovered.values)
            register(cached); register(recent); restored = true
        }
        register(library.sessions)
        for project in library.projects.projects where !projectOrder.contains(project.id) { projectOrder.append(project.id) }
        var all: [String: Session] = [:]
        for project in library.projects.projects {
            let members = library.projects.sessions(project, library: library)
            let segments = members.flatMap { session in
                library.conversations.record(session.id)?.segments ?? [ConversationSegment(nativeID: session.sessionID, provider: session.provider, model: "")]
            }
            let nativeKeys = Set(segments.map { $0.provider + ":" + $0.nativeID })
            let folders = Set(([project.folder] + project.workspaces.map(\.folder)).map { URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path })
            var sources = knownSources[project.id] ?? [:]
            for source in discovered.values where nativeKeys.contains(source.provider.rawValue + ":" + source.sessionID)
                || folders.contains(sourceFolders[PortfolioUsageIndex.identity(source)] ?? source.project) {
                sources[PortfolioUsageIndex.identity(source)] = source
            }
            // Explicitly linked descendants need not share a folder with their parent.
            for _ in 0..<8 {
                let parents = Set(sources.values.map { $0.provider.rawValue + ":" + $0.sessionID })
                let children = discovered.values.filter { child in
                    child.parentID.map { parents.contains(child.provider.rawValue + ":" + $0) } == true
                }
                let before = sources.count
                for child in children { sources[PortfolioUsageIndex.identity(child)] = child }
                if before == sources.count { break }
            }
            for segment in segments where !sources.values.contains(where: { $0.provider.rawValue == segment.provider && $0.sessionID == segment.nativeID }) {
                if let provider = Provider(rawValue: segment.provider) {
                    let source = PortfolioUsageIndex.unavailableSession(provider: provider, nativeID: segment.nativeID, project: project.folder)
                    sources[PortfolioUsageIndex.identity(source)] = source
                }
            }
            knownSources[project.id] = sources
            all.merge(sources) { _, latest in latest }
        }
        let sources = Array(all.values)
        async let read = index.read(sources)
        async let summaries = activity.scan(sources.filter { $0.url != nil }, hookDirectory: library.observationHookDirectory)
        let (saved, states) = await (read, summaries)
        guard !Task.isCancelled, !library.paused else { return }
        var nextObservations: [String: ExternalObservationSnapshot] = [:]
        for source in sources {
            if let state = states[source.id] {
                nextObservations[source.id] = ExternalObservationSnapshot(sessionID: source.id, transcript: Transcript(),
                    activity: state, structured: .init(), sourceModifiedAt: source.modified, synchronizedAt: Date(), error: state.error)
            }
            let key = PortfolioUsageIndex.identity(source)
            var ledger = liveLedgers[key] ?? PortfolioUsageLedger()
            if let task = library.execution.tasks[source.sessionID], task.provider == source.provider, source.classification != .subagent {
                if liveValues[key] != task.workflow.usage {
                    liveValues[key] = task.workflow.usage
                    ledger.ingestCumulative(task.workflow.usage["total"], provider: source.provider, at: Date())
                }
                for record in task.structuredActivity.records where record.kind == "usage" {
                    if source.provider == .codex {
                        let value = record.data["total"] == .null ? record.data["total_token_usage"] : record.data["total"]
                        ledger.ingestCumulative(value, provider: .codex, at: record.recordedAt ?? record.observedAt)
                    } else {
                        ledger.ingestResponse(record.data["usage"], id: record.turnID ?? record.nativeID, provider: .claude, result: true, at: record.recordedAt ?? record.observedAt)
                    }
                }
            }
            liveLedgers[key] = ledger
        }
        // Publish only changed evidence; clock-based expiry is handled by the existing observation clock.
        for (id, next) in nextObservations {
            let old = observations[id]
            if old?.activity.events != next.activity.events || old?.error != next.error { observations[id] = next }
        }
        for project in library.projects.projects {
            let members = knownSources[project.id] ?? [:]
            var total: Int64 = 0, found = false, partial = false, loading = false
            var last: Date?, contributing = Set<String>()
            for (key, source) in members {
                // Parent totals can include delegated work. Without provider proof of disjoint scope,
                // expose a partial lower bound rather than double-counting child transcripts.
                if source.classification == .subagent || source.parentID != nil { partial = true; continue }
                let file = saved[key] ?? PortfolioUsageSource()
                let live = liveLedgers[key] ?? PortfolioUsageLedger()
                let values = [file.ledger.total, live.total].compactMap { $0 }
                if let value = values.max() {
                    found = true
                    let (sum, overflow) = total.addingReportingOverflow(value)
                    total = overflow ? Int64.max : sum; contributing.insert(key)
                } else { partial = true }
                // Live result scopes and saved message scopes are alternatives, not additive.
                if source.provider == .claude && live.total != nil && file.ledger.total != nil { partial = true }
                partial = partial || file.missing || file.ledger.partial || live.partial
                loading = loading || file.loading
                if let date = [file.ledger.observedAt, live.observedAt].compactMap({ $0 }).max() { last = max(last ?? .distantPast, date) }
            }
            let summary = PortfolioUsageSummary(tokens: found ? total : nil,
                coverage: loading ? .loading : !found ? .unavailable : partial ? .partial : .reported, observedAt: last, sources: contributing)
            if usages[project.id] != summary { usages[project.id] = summary }
        }
    }

    func planSources(provider: Provider, nativeID: String) -> [Session] {
        let parent = primarySources[provider.rawValue + ":" + nativeID]
        let children = Array(childrenByParent[provider.rawValue + ":" + nativeID, default: [:]].values)
        return [parent].compactMap { $0 } + children
    }
    func observation(for provider: Provider, nativeID: String) -> ExternalObservationSnapshot? {
        guard let source = primarySources[provider.rawValue + ":" + nativeID] else { return nil }
        return observations[source.id]
    }
    func childRecords(provider: Provider, nativeID: String) -> [SessionActivityRecord] {
        guard let parent = primarySources[provider.rawValue + ":" + nativeID] else { return [] }
        var parents = Set([nativeID]), seen = Set<String>(), records: [SessionActivityRecord] = []
        for _ in 0..<8 {
            let children = parents.flatMap { Array(childrenByParent[provider.rawValue + ":" + $0, default: [:]].values) }
                .filter { !seen.contains($0.id) }
            if children.isEmpty { break }
            parents.removeAll(keepingCapacity: true)
            for child in children {
                seen.insert(child.id); parents.insert(child.sessionID)
                if let observation = observations[child.id] { records.append(observation.agentRecord(child, parent: parent)) }
            }
        }
        return records
    }
}
