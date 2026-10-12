import Foundation
import DioramaCore

/// The development demo's made-up portfolio (`--record-demo`): projects, conversations and
/// agents shown through the real Home, agent panel, kitchen and conversation views. Nothing
/// here talks to Codex, Claude or GitHub.
struct DemoFixture {
    var projects: [DioramaProject] = []
    var sessions: [Session] = []
    /// By conversation.
    var agents: [String: [WorkspaceAgent]] = [:]
    var models: [String: String] = [:]
    var questions: [String: String] = [:]
    /// What led up to a question, shown above it when it's answered.
    var contexts: [String: String] = [:]
    var transcripts: [String: Transcript] = [:]
    var projectDays: [String: [TokenSplit]] = [:]
    var usages: [String: PortfolioUsageSummary] = [:]
    /// The project and conversation the demo opens from Home at the end.
    var target = (project: "", conversation: "")

    /// One conversation with its main agent.
    struct Agent {
        let name: String
        let provider: Provider
        let model: String
        let title: String
        let status: WorkspaceAgentStatus
        var reason: WorkspaceAttentionReason = .other
        var tool = ""
        var detail = ""
        var minutes = 1.0
        var question: String? = nil
        var steps: [(String, String)] = []
        var branch: String? = nil
        var feed: [(FeedEntry.Kind, String, String)] = []
        /// Last heard from long ago: idle, resting in the break room.
        var stale = false
    }
    struct Project {
        let name: String
        var github = true
        var agents: [Agent]
        var days: [Int] = [3, 5, 4, 7, 6, 8, 9]
        /// Its repository has uncommitted edits, for the Changes tab.
        var changed = false
    }

    /// Builds the portfolio, with each project's folder (a small git repository) under `root`.
    static func make(root: URL, now: Date = Date()) -> DemoFixture {
        var fixture = build(portfolio, root: root, now: now)
        fixture.target = ("demo-atlas-api", "demo-atlas-api-0")
        fixture.transcripts[fixture.target.conversation] = rateLimiterTranscript
        return fixture
    }
    /// The kitchen demo: one busy project, Atlas API, with a second tab beside it.
    static func kitchen(root: URL, now: Date = Date()) -> DemoFixture {
        var fixture = build([kitchenProject, portfolio[0]], root: root, now: now)
        fixture.target = ("demo-atlas-api", "demo-atlas-api-0")
        fixture.transcripts["demo-atlas-api-1"] = webhookTranscript
        return fixture
    }
    /// One conversation's main agent, as the kitchen reads it.
    static func agentValue(_ agent: Agent, id: String, updated: Date) -> WorkspaceAgent { value(agent, id: id, updated: updated) }

    static func build(_ specs: [Project], root: URL, now: Date) -> DemoFixture {
        var fixture = DemoFixture()
        for (index, spec) in specs.enumerated() {
            let slug = spec.name.lowercased().replacingOccurrences(of: " ", with: "-")
            let folder = root.appendingPathComponent(slug).path
            DemoRepository.prepare(folder, changed: spec.changed || spec.name == "Atlas API")
            var project = DioramaProject(name: spec.name, folder: folder, commonDirectory: folder + "/.git", base: "main",
                                         remote: spec.github ? "git@github.com:northwind-labs/\(slug).git" : nil)
            project.id = "demo-" + slug
            for (number, agent) in spec.agents.enumerated() {
                let id = "demo-\(slug)-\(number)"
                let updated = now.addingTimeInterval(-agent.minutes * 60 - Double(index))
                fixture.sessions.append(.demo(id: id, provider: agent.provider, title: agent.title, folder: folder, modified: updated))
                fixture.agents[id] = [value(agent, id: id, updated: updated)]
                fixture.models[id] = agent.model
                if let question = agent.question { fixture.questions[id] = question }
                if let branch = agent.branch {
                    var workspace = ProjectWorkspace(id: id, folder: folder, branch: branch, baseCommit: DemoRepository.base(folder) ?? "", context: ProjectContext())
                    workspace.threadID = id; workspace.direct = true
                    project.workspaces.append(workspace)
                }
            }
            fixture.projects.append(project)
            fixture.projectDays[project.id] = spec.days.map { TokenSplit(input: Int64($0) * 210_000, output: Int64($0) * 46_000) }
            fixture.usages[project.id] = PortfolioUsageSummary(tokens: Int64(spec.days.reduce(0, +)) * 256_000, coverage: .reported, observedAt: now)
        }
        return fixture
    }

    private static func value(_ agent: Agent, id: String, updated: Date) -> WorkspaceAgent {
        let reported = agent.status == .waiting ? (agent.reason == .approval ? "awaitingApproval" : "waitingForInput") : agent.status.rawValue
        var value = WorkspaceAgent(id: "main", name: agent.name, provider: agent.provider.rawValue, task: agent.title,
                                   action: agent.status == .working ? "Working" : agent.status.rawValue,
                                   status: agent.status, reportedStatus: reported,
                                   freshness: agent.status == .ready || agent.stale ? .lastKnown : .live)
        value.attentionReason = agent.reason
        value.latestTool = agent.tool
        value.latestToolDetail = agent.detail
        value.turnHasEdits = ["edit", "write", "multiedit"].contains(agent.tool.lowercased())
        value.reportedModel = agent.model
        value.branch = agent.branch
        value.completionKey = id
        value.meaningfulUpdatedAt = updated
        value.observedAt = updated
        value.lastToolAt = agent.tool.isEmpty ? nil : updated
        if !agent.steps.isEmpty { value.plan = .demo(agent.steps, provider: agent.provider, sessionID: id, at: updated) }
        value.feed = agent.feed.enumerated().map { index, item in
            FeedEntry(id: "\(id).feed\(index)", kind: item.0, title: item.1, detail: item.2,
                      outcome: index == agent.feed.count - 1 && agent.status == .working ? .running : .done,
                      time: updated.addingTimeInterval(Double(index - agent.feed.count) * 50))
        }
        return value
    }

    // MARK: The portfolio

    static let portfolio: [Project] = [
        // Needs you
        Project(name: "Checkout v2", agents: [
            Agent(name: "Maya", provider: .claude, model: "Opus 5.5", title: "Migrate payments to Stripe Billing", status: .waiting, reason: .approval, minutes: 3,
                  question: "Wants to run rails db:migrate (0042_stripe_customers)",
                  steps: [("Map current charge flow", "completed"), ("Create Stripe customers", "completed"), ("Write migration", "completed"), ("Run migration", "in_progress"), ("Switch webhooks", "pending")],
                  branch: "feat/stripe-billing"),
            Agent(name: "Leo", provider: .codex, model: "GPT-5.5", title: "Add EU VAT at checkout", status: .waiting, reason: .input, minutes: 6,
                  question: "Should EU VAT use Stripe Tax or TaxJar?", branch: "feat/eu-vat"),
            Agent(name: "Priya", provider: .claude, model: "Sonnet 5.5", title: "Apple Pay on mobile web", status: .working, tool: "Edit", detail: "src/checkout/ApplePayButton.tsx",
                  steps: [("Add merchant validation", "completed"), ("Build button", "in_progress"), ("Test on Safari", "pending")], branch: "feat/apple-pay"),
        ], days: [6, 8, 7, 9, 11, 10, 12]),
        Project(name: "Mobile Onboarding", agents: [
            Agent(name: "Sam", provider: .claude, model: "Opus 5.5", title: "Welcome carousel in SwiftUI", status: .waiting, reason: .input, minutes: 4,
                  question: "Keep the Skip button on the first screen?", branch: "feat/welcome-carousel"),
            Agent(name: "Ana", provider: .codex, model: "GPT-5.5", title: "Push permission priming", status: .working, tool: "Bash", detail: "xcodebuild test -scheme Onboarding",
                  steps: [("Design priming sheet", "completed"), ("Wire permission request", "completed"), ("UI tests", "in_progress")]),
            Agent(name: "Kai", provider: .claude, model: "Sonnet 5.5", title: "Localize onboarding in 6 languages", status: .working, tool: "Edit", detail: "Onboarding/Localizable.xcstrings"),
        ], days: [2, 3, 5, 4, 6, 7, 6]),
        // Active
        Project(name: "Atlas API", agents: [
            Agent(name: "Nova", provider: .claude, model: "Opus 5.5", title: "Rate limiter for the public API", status: .working, tool: "Edit", detail: "Sources/Middleware/RateLimiter.swift", minutes: 0.3,
                  steps: [("Read the request pipeline", "completed"), ("Token bucket in Redis", "completed"), ("RateLimiter middleware", "completed"),
                          ("Wire into router", "in_progress"), ("429 with Retry-After", "pending"), ("Load test", "pending")],
                  branch: "feat/rate-limiter",
                  feed: [(.research, "Read the request pipeline", "Router.swift, Middleware/"), (.planning, "Planned 6 steps", ""),
                         (.editing, "Added TokenBucket.swift", "+84"), (.command, "redis-cli ping", "PONG"), (.test, "swift test --filter TokenBucket", "12 passed"),
                         (.editing, "Editing RateLimiter.swift", "")]),
            Agent(name: "Theo", provider: .codex, model: "GPT-5.5", title: "Generate OpenAPI docs", status: .working, tool: "Bash", detail: "npx redocly build-docs openapi.yaml", minutes: 0.5,
                  steps: [("Annotate routes", "completed"), ("Build docs", "in_progress"), ("Publish preview", "pending")], branch: "docs/openapi"),
            Agent(name: "Iris", provider: .claude, model: "Sonnet 5.5", title: "Fix flaky webhook test", status: .working, tool: "Bash", detail: "swift test --filter WebhookTests", minutes: 0.4, branch: "fix/webhook-flake"),
            Agent(name: "Omar", provider: .codex, model: "GPT-5.5", title: "Index orders by customer", status: .working, tool: "Read", detail: "Sources/DB/OrdersRepository.swift", minutes: 0.6, branch: "perf/orders-index"),
            Agent(name: "Jade", provider: .claude, model: "Sonnet 5.5", title: "Cursor pagination for /v2/orders", status: .done, minutes: 9, branch: "feat/cursor-pagination"),
        ], days: [9, 12, 10, 14, 13, 16, 18]),
        Project(name: "Insights Dashboard", agents: [
            Agent(name: "Ruby", provider: .claude, model: "Opus 5.5", title: "Cohort retention chart", status: .working, tool: "Edit", detail: "app/charts/RetentionChart.tsx",
                  steps: [("Query cohorts", "completed"), ("Chart", "in_progress"), ("Empty states", "pending")]),
            Agent(name: "Felix", provider: .codex, model: "GPT-5.5", title: "Export reports to CSV", status: .working, tool: "Bash", detail: "pnpm test export"),
        ], days: [4, 4, 6, 5, 7, 6, 8]),
        Project(name: "Support Copilot", github: false, agents: [
            Agent(name: "Zoe", provider: .claude, model: "Sonnet 5.5", title: "Summarize long ticket threads", status: .working, tool: "Edit", detail: "copilot/summarize.py"),
            Agent(name: "Hugo", provider: .codex, model: "GPT-5.5", title: "Slack alerts for escalations", status: .done, minutes: 14),
        ], days: [1, 3, 2, 4, 3, 5, 4]),
        Project(name: "Design System", agents: [
            Agent(name: "Lena", provider: .claude, model: "Opus 5.5", title: "Dark mode color tokens", status: .working, tool: "Edit", detail: "tokens/color.json"),
        ], days: [2, 2, 3, 2, 4, 3, 3]),
        // Needs review
        Project(name: "Billing Service", agents: [
            Agent(name: "Max", provider: .codex, model: "GPT-5.5", title: "Prorated plan upgrades", status: .done, minutes: 12),
            Agent(name: "Ivy", provider: .claude, model: "Opus 5.5", title: "Redesign invoice PDFs", status: .done, minutes: 25),
            Agent(name: "Noah", provider: .claude, model: "Sonnet 5.5", title: "Dunning emails for failed cards", status: .done, minutes: 41),
        ], days: [5, 6, 8, 7, 9, 6, 4]),
        Project(name: "Marketing Site", agents: [
            Agent(name: "Eli", provider: .claude, model: "Sonnet 5.5", title: "Pricing page A/B test", status: .done, minutes: 18),
        ], days: [1, 2, 1, 3, 2, 2, 1]),
        Project(name: "Data Pipeline", agents: [
            Agent(name: "Mia", provider: .codex, model: "GPT-5.5", title: "Backfill events to BigQuery", status: .done, minutes: 33),
            Agent(name: "Owen", provider: .claude, model: "Opus 5.5", title: "dbt models for revenue", status: .done, minutes: 52),
        ], days: [3, 5, 4, 6, 8, 7, 5]),
        // Recent projects
        Project(name: "Receipt Scanner", agents: [Agent(name: "Ada", provider: .claude, model: "Sonnet 5.5", title: "OCR for crumpled receipts", status: .ready, minutes: 2_900)], days: [2, 1, 0, 3, 1, 0, 0]),
        Project(name: "Infra Terraform", agents: [Agent(name: "Rex", provider: .codex, model: "GPT-5.5", title: "Move staging to ECS", status: .ready, minutes: 4_400)], days: [0, 2, 1, 0, 0, 1, 0]),
        Project(name: "iOS Widgets", agents: [Agent(name: "Luz", provider: .claude, model: "Opus 5.5", title: "Live Activity for deliveries", status: .ready, minutes: 6_100)], days: [1, 0, 2, 1, 0, 0, 0]),
        Project(name: "Docs Portal", github: false, agents: [Agent(name: "Ben", provider: .codex, model: "GPT-5.5", title: "Search with Algolia", status: .ready, minutes: 8_700)], days: [0, 0, 1, 0, 1, 0, 0]),
        Project(name: "CLI Tools", agents: [Agent(name: "Gus", provider: .claude, model: "Sonnet 5.5", title: "Shell completions", status: .ready, minutes: 11_000)], days: [0, 1, 0, 0, 0, 0, 1]),
    ]

    /// The kitchen demo's project: seven cooks at every station, two dishes at the pass, four on a break.
    static let kitchenProject = Project(name: "Atlas API", agents: [
        Agent(name: "Nova", provider: .claude, model: "Opus 5.5", title: "Rate limiter for the public API", status: .working, tool: "Edit", detail: "Sources/Middleware/RateLimiter.swift", minutes: 0.3,
              steps: [("Token bucket in Redis", "completed"), ("RateLimiter middleware", "completed"), ("Wire into router", "in_progress"), ("Load test", "pending")], branch: "feat/rate-limiter"),
        Agent(name: "Sam", provider: .claude, model: "Sonnet 5.5", title: "Retry failed webhooks with backoff", status: .working, tool: "Bash", detail: "swift build --product Webhooks", minutes: 0.2,
              steps: [("Retry queue", "completed"), ("Exponential backoff", "in_progress"), ("Dead-letter alerts", "pending")], branch: "feat/webhook-retries",
              feed: [(.research, "Read WebhookSender.swift", ""), (.editing, "Added RetryQueue.swift", "+61"), (.editing, "Editing RetryQueue.swift", "")]),
        Agent(name: "Theo", provider: .codex, model: "GPT-5.5", title: "Generate OpenAPI docs", status: .working, tool: "Edit", detail: "docs/openapi.yaml", minutes: 0.4, branch: "docs/openapi"),
        Agent(name: "Iris", provider: .claude, model: "Sonnet 5.5", title: "Fix flaky webhook test", status: .working, tool: "Bash", detail: "swift test --filter WebhookTests", minutes: 0.3, branch: "fix/webhook-flake"),
        Agent(name: "Omar", provider: .codex, model: "GPT-5.5", title: "Index orders by customer", status: .working, tool: "Read", detail: "Sources/DB/OrdersRepository.swift", minutes: 0.5, branch: "perf/orders-index"),
        Agent(name: "Kai", provider: .claude, model: "Opus 5.5", title: "Plan multi-region failover", status: .working, tool: "TodoWrite", detail: "", minutes: 0.6),
        Agent(name: "Lena", provider: .codex, model: "GPT-5.5", title: "Triage Sentry errors", status: .working, tool: "mcp__sentry__search_issues", detail: "", minutes: 0.4),
        Agent(name: "Jade", provider: .claude, model: "Sonnet 5.5", title: "Cursor pagination for /v2/orders", status: .done, minutes: 6, branch: "feat/cursor-pagination"),
        Agent(name: "Hugo", provider: .codex, model: "GPT-5.5", title: "Slack alerts for escalations", status: .done, minutes: 11),
        Agent(name: "Ada", provider: .claude, model: "Sonnet 5.5", title: "Upgrade to Swift 6.2", status: .done, minutes: 1_900, stale: true),
        Agent(name: "Rex", provider: .codex, model: "GPT-5.5", title: "Dockerfile cleanup", status: .done, minutes: 2_300, stale: true),
        Agent(name: "Luz", provider: .claude, model: "Opus 5.5", title: "Health check endpoint", status: .done, minutes: 2_800, stale: true),
        Agent(name: "Ben", provider: .codex, model: "GPT-5.5", title: "Remove legacy v1 routes", status: .done, minutes: 3_400, stale: true),
    ], days: [9, 12, 10, 14, 13, 16, 18])
    /// The new cook the kitchen demo opens on.
    static let arrival = Agent(name: "Pixel", provider: .claude, model: "Opus 5.5", title: "Audit log for admin actions", status: .working, tool: "Read", detail: "Sources/Admin/AdminController.swift", minutes: 0)

    /// Sam's conversation: working, then a question, then your answer.
    private static var webhookTranscript: Transcript {
        var transcript = Transcript()
        transcript.entries = [
            .demo("w1", "You", "Failed webhooks are dropped today. Retry them with exponential backoff and alert us when they give up."),
            .demo("w2", "Assistant", "I'll add a retry queue with exponential backoff (1 min, doubling) and a dead-letter alert. The queue is in; now the backoff schedule."),
        ]
        return transcript
    }

    /// The conversation the demo opens: a request, the agent's plan, its first steps, and where it is now.
    private static var rateLimiterTranscript: Transcript {
        var transcript = Transcript()
        transcript.state = "Working"
        transcript.entries = [
            .demo("t1", "You", "Add a rate limiter to the public API: 100 requests a minute per API key, backed by Redis. Over the limit, return 429 with a Retry-After header."),
            .demo("t2", "Assistant", "I'll put a token bucket per API key in Redis and enforce it in a middleware, so every public route gets it without touching the handlers. First I'll read how requests flow through the router."),
            Entry.demoTool("t3", ["type": "commandExecution", "command": "rg -n \"Middleware\" Sources/Router", "status": "completed"]),
            .demo("t4", "Assistant", "The router already runs an auth middleware, which resolves the API key. The limiter goes right after it.\n\n1. Token bucket in Redis (atomic Lua script)\n2. RateLimiter middleware\n3. Wire it into the router after auth\n4. 429 with Retry-After\n5. Load test"),
            Entry.demoTool("t5", ["type": "commandExecution", "command": "swift test --filter TokenBucketTests", "status": "completed", "aggregatedOutput": "Executed 12 tests, with 0 failures"]),
            .demo("t6", "Assistant", "The token bucket passes its 12 tests, including bursts and refill. Now wiring RateLimiter into the router after auth."),
        ].compactMap { $0 }
        return transcript
    }
}

/// Each demo project's folder: a small git repository, so the project screen reads a real branch
/// and the Changes tab lists real edits.
enum DemoRepository {
    static func prepare(_ folder: String, changed: Bool) {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: folder + "/.git") else { return }
        try? manager.createDirectory(atPath: folder + "/Sources/Middleware", withIntermediateDirectories: true)
        write(folder + "/README.md", "# \(URL(fileURLWithPath: folder).lastPathComponent)\n")
        write(folder + "/Sources/Router.swift", "struct Router {\n    var middleware: [Middleware] = [AuthMiddleware()]\n}\n")
        write(folder + "/Sources/Middleware/AuthMiddleware.swift", "struct AuthMiddleware: Middleware {}\n")
        git(folder, "init", "-q", "-b", "main")
        git(folder, "add", "-A")
        git(folder, "-c", "user.name=Demo", "-c", "user.email=demo@example.com", "commit", "-q", "-m", "Initial commit")
        guard changed else { return }
        write(folder + "/Sources/Middleware/RateLimiter.swift", "struct RateLimiter: Middleware {\n    let limit = 100\n    let window: Duration = .seconds(60)\n}\n")
        write(folder + "/Sources/Middleware/TokenBucket.swift", "struct TokenBucket {\n    var tokens: Int\n    var refilledAt: Date\n}\n")
        write(folder + "/Sources/Router.swift", "struct Router {\n    var middleware: [Middleware] = [AuthMiddleware(), RateLimiter()]\n}\n")
        write(folder + "/Tests/TokenBucketTests.swift", "import Testing\n\n@Test func refills() {}\n@Test func bursts() {}\n")
    }
    static func base(_ folder: String) -> String? {
        let pipe = Pipe(), process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", folder, "rev-parse", "HEAD"]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func write(_ path: String, _ text: String) {
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
    }
    private static func git(_ folder: String, _ arguments: String...) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", folder] + arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        process.waitUntilExit()
    }
}
