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

/// What Home's usage column shows: weekly allowances and the last seven days of tokens.
struct HomeUsage: Equatable {
    struct Node: Equatable, Identifiable { var id: String; var name: String; var tokens: TokenSplit }
    var weekly: [Provider: LimitWindow] = [:]
    var plans: [Provider: String] = [:]
    var tokens = TokenSplit()
    var byProject: [Node] = []
    var byPlan: [Node] = []
    var loading = false
    func planName(_ provider: Provider) -> String { ProviderLimits.planName(provider, plans[provider]) }
}

@Observable final class PortfolioStore {
    var usages: [String: PortfolioUsageSummary] = [:]
    var home = HomeUsage()
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
    private let limitsURL: URL?
    private var limits: ProviderLimitsCache
    private var codexLimitsSource: (path: String, modified: Date)?
    private var appServerLimits: WireValue = .null
    private var checkingClaudePlan = false
    private var checkingClaudeUsage = false
    private var checkingCodexUsage = false
    private var codexUsageCheckedAt: Date?

    init(cache: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Diorama/portfolio-usage-v2.json")) {
        index = PortfolioUsageIndex(cache: cache)
        // Without a cache (tests) nothing is persisted and no provider command runs.
        limitsURL = cache?.deletingLastPathComponent().appendingPathComponent("provider-limits-v1.json")
        limits = ProviderLimitsCache.load(limitsURL)
        if let old = cache?.deletingLastPathComponent().appendingPathComponent("portfolio-usage-v1.json") { try? FileManager.default.removeItem(at: old) }
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
        // Home's token flow covers the whole account: recent sessions outside any project count too.
        let horizon = Date().addingTimeInterval(-8 * 86_400)
        let unassigned = discovered.filter { all[$0.key] == nil && $0.value.url != nil && $0.value.modified >= horizon }
        async let read = index.read(sources + Array(unassigned.values))
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
        refreshLimits(library)
        let next = homeUsage(library, saved: saved, unassigned: unassigned)
        if home != next { home = next }
    }

    /// Seven-day tokens come from the saved transcripts only: providers write them as they work, and a
    /// live counter's first snapshot would otherwise land a whole session's history on today.
    private func homeUsage(_ library: LibraryModel, saved: [String: PortfolioUsageSource], unassigned: [String: Session]) -> HomeUsage {
        var next = HomeUsage(weekly: limits.weekly.reduce(into: [:]) { result, item in
            if let provider = Provider(rawValue: item.key) { result[provider] = item.value }
        }, plans: limits.plans.reduce(into: [:]) { result, item in
            if let provider = Provider(rawValue: item.key) { result[provider] = item.value }
        })
        var counted = Set<String>(), projects: [HomeUsage.Node] = [], plans: [Provider: TokenSplit] = [:]
        for project in library.projects.projects {
            var tokens = TokenSplit()
            // Subagent transcripts are separate model calls, so unlike the all-time lower bound they are included.
            for (key, source) in knownSources[project.id] ?? [:] where counted.insert(key).inserted {
                guard let file = saved[key] else { continue }
                next.loading = next.loading || file.loading
                let recent = file.ledger.recent(days: 7)
                tokens = tokens + recent
                plans[source.provider, default: TokenSplit()] = plans[source.provider, default: TokenSplit()] + recent
            }
            if tokens.total > 0 { projects.append(.init(id: project.id, name: project.name, tokens: tokens)) }
        }
        // Sessions outside Diorama projects are grouped by the folder they ran in.
        var folders: [String: TokenSplit] = [:]
        for (key, source) in unassigned where counted.insert(key).inserted {
            guard let file = saved[key] else { continue }
            let recent = file.ledger.recent(days: 7)
            guard recent.total > 0 else { continue }
            folders[sourceFolders[key] ?? source.project, default: TokenSplit()] = folders[sourceFolders[key] ?? source.project, default: TokenSplit()] + recent
            plans[source.provider, default: TokenSplit()] = plans[source.provider, default: TokenSplit()] + recent
        }
        for (folder, tokens) in folders {
            let name = URL(fileURLWithPath: folder).lastPathComponent
            projects.append(.init(id: "folder:" + folder, name: name.isEmpty ? folder : name, tokens: tokens))
        }
        projects.sort { $0.tokens.total == $1.tokens.total ? $0.name < $1.name : $0.tokens.total > $1.tokens.total }
        if projects.count > 6 {
            let rest = projects[5...]
            projects = Array(projects.prefix(5)) + [.init(id: "others", name: "+\(rest.count) others", tokens: rest.reduce(TokenSplit()) { $0 + $1.tokens })]
        }
        next.byProject = projects
        next.byPlan = [Provider.claude, .codex].compactMap { provider in
            guard let tokens = plans[provider], tokens.total > 0 else { return nil }
            return .init(id: provider.rawValue, name: next.planName(provider), tokens: tokens)
        }.sorted { $0.tokens.total > $1.tokens.total }
        next.tokens = projects.reduce(TokenSplit()) { $0 + $1.tokens }
        return next
    }

    /// Weekly limits from what the providers already report: Codex writes them into every transcript
    /// turn and the app server, Claude Code sends them as rate-limit events during a turn.
    private func refreshLimits(_ library: LibraryModel) {
        var next = limits
        func merge(_ window: LimitWindow?) {
            guard let window else { return }
            next.weekly[window.provider.rawValue] = ProviderLimits.merge(next.weekly[window.provider.rawValue], window)
        }
        let newestCodex = discovered.values.filter { $0.provider == .codex && $0.url != nil }.max { $0.modified < $1.modified }
        if let url = newestCodex?.url {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if codexLimitsSource?.path != url.path || codexLimitsSource?.modified != modified {
                codexLimitsSource = (url.path, modified)
                if let latest = ProviderLimits.latestCodexRateLimits(url) {
                    merge(ProviderLimits.codexWeekly(latest.value, at: latest.at))
                    if let plan = ProviderLimits.codexPlan(latest.value) { next.plans[Provider.codex.rawValue] = plan }
                }
            }
        }
        if library.execution.rateLimits != .null, library.execution.rateLimits != appServerLimits {
            appServerLimits = library.execution.rateLimits
            merge(ProviderLimits.codexWeekly(appServerLimits, at: Date()))
            if let plan = ProviderLimits.codexPlan(appServerLimits) { next.plans[Provider.codex.rawValue] = plan }
        }
        for task in library.execution.tasks.values where task.provider == .claude {
            for record in task.structuredActivity.records where record.kind == "limits" {
                merge(ProviderLimits.claudeWeekly(record.data, at: record.recordedAt ?? record.observedAt))
            }
        }
        if next != limits { limits = next; next.save(limitsURL) }
        checkClaudePlan()
        checkClaudeUsage()
        checkCodexUsage(library)
    }

    /// Codex's app server reports the account's limits even before any Codex session exists.
    private func checkCodexUsage(_ library: LibraryModel) {
        guard limitsURL != nil, library.execution.connected, !checkingCodexUsage,
              (codexUsageCheckedAt.map { Date().timeIntervalSince($0) > 300 } ?? true) else { return }
        checkingCodexUsage = true; codexUsageCheckedAt = Date()
        Task { @MainActor in
            defer { checkingCodexUsage = false }
            await library.execution.loadUsage()
        }
    }

    /// Claude Code's `/usage` report covers the whole account, including use outside Diorama.
    /// It makes no model call; checked at most every 10 minutes while the app is in use.
    private func checkClaudeUsage() {
        guard limitsURL != nil, !checkingClaudeUsage, (limits.claudeUsageCheckedAt.map { Date().timeIntervalSince($0) > 600 } ?? true),
              let claude = AgentExecutable.resolve("claude") else { return }
        checkingClaudeUsage = true
        Task { @MainActor in
            defer { checkingClaudeUsage = false }
            let report = try? await ProjectCommand.data(claude.path, ProviderLimits.claudeUsageArguments, folder: FileManager.default.temporaryDirectory.path, timeout: 30)
            limits.claudeUsageCheckedAt = Date()
            if let window = report.flatMap({ ProviderLimits.claudeWeekly(usageReport: $0) }) {
                limits.weekly[Provider.claude.rawValue] = ProviderLimits.merge(limits.weekly[Provider.claude.rawValue], window)
            }
            limits.save(limitsURL)
        }
    }

    /// `claude auth status` is the CLI's own account summary; checked at most every 30 minutes.
    private func checkClaudePlan() {
        guard limitsURL != nil, !checkingClaudePlan, (limits.claudePlanCheckedAt.map { Date().timeIntervalSince($0) > 1800 } ?? true),
              let claude = AgentExecutable.resolve("claude") else { return }
        checkingClaudePlan = true
        Task { @MainActor in
            defer { checkingClaudePlan = false }
            let plan = (try? await ProjectCommand.data(claude.path, ["auth", "status"], timeout: 10)).flatMap(ProviderLimits.claudePlan(authStatus:))
            limits.claudePlanCheckedAt = Date()
            if let plan { limits.plans[Provider.claude.rawValue] = plan }
            limits.save(limitsURL)
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
