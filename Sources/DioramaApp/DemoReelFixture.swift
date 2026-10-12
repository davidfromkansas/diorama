import Foundation
import DioramaCore

/// The reel demo's portfolio (`--demo-scene reel`): four busy projects (3–6 cooks at every
/// station) and a few quiet ones. Ranked by work in progress, Atlas API leads Active and
/// Insights Dashboard is third; nobody needs you until the script says so.
extension DemoFixture {
    /// Where a made-up agent is, as the tool it last used (the kitchen routes by it).
    enum Station {
        case cook(String), stove(String), research(String), plan, taste(String), mcp(String), skill(String), done, rest
    }

    static func reel(root: URL, now: Date = Date()) -> DemoFixture {
        let specs = [atlas, payments, insights, checkout] + portfolio.suffix(5)
        var fixture = build(specs, root: root, now: now)
        // Every conversation reads like real work: the request, a plan, a step, and progress.
        for (id, values) in fixture.agents {
            guard let value = values.first, value.status != .ready else { continue }
            fixture.transcripts[id] = conversation(value)
        }
        fixture.target = ("demo-atlas-api", "")
        return fixture
    }

    /// One agent at a station.
    static func a(_ name: String, _ provider: Provider, _ title: String, _ station: Station, minutes: Double = 0.4) -> Agent {
        let model = provider == .codex ? "GPT-5.5" : (name.count % 2 == 0 ? "Opus 5.5" : "Sonnet 5.5")
        let branch = "feat/" + title.lowercased().split { !$0.isLetter && !$0.isNumber }.prefix(4).joined(separator: "-")
        var agent = Agent(name: name, provider: provider, model: model, title: title, status: .working, minutes: minutes, branch: branch)
        let steps = ["Read the code involved", "Plan the change", "Make the change", "Run the tests", "Write it up"]
        func progress(_ done: Int) -> [(String, String)] {
            steps.enumerated().map { ($1, $0 < done ? "completed" : $0 == done ? "in_progress" : "pending") }
        }
        switch station {
        case .cook(let file):
            agent.tool = "Edit"; agent.detail = file; agent.steps = progress(2)
            agent.feed = [(.research, "Read " + (file as NSString).lastPathComponent, ""), (.planning, "Planned 5 steps", ""), (.editing, "Editing " + (file as NSString).lastPathComponent, "")]
        case .stove(let command):
            agent.tool = "Bash"; agent.detail = command; agent.steps = progress(2)
            agent.feed = [(.planning, "Planned 5 steps", ""), (.editing, "Edited 3 files", "+48 −12"), (.command, command, "")]
        case .research(let file):
            agent.tool = file.contains(" ") ? "Grep" : "Read"; agent.detail = file; agent.steps = progress(0)
            agent.feed = [(.research, "Searched the codebase", "14 matches"), (.research, "Reading " + (file as NSString).lastPathComponent, "")]
        case .plan:
            agent.tool = "TodoWrite"; agent.steps = progress(1)
            agent.feed = [(.research, "Read the design doc", ""), (.planning, "Planning the rollout", "")]
        case .taste(let command):
            agent.tool = "Bash"; agent.detail = command; agent.steps = progress(3)
            agent.feed = [(.editing, "Edited 4 files", "+120 −31"), (.test, command, "")]
        case .mcp(let tool):
            agent.tool = tool; agent.steps = progress(1)
            let server = tool.components(separatedBy: "__").dropFirst().first?.split(separator: "_").last.map(String.init) ?? "a connector"
            agent.feed = [(.resource, "Using " + server.capitalized, "")]
        case .skill(let skill):
            agent.tool = "Skill"; agent.detail = skill; agent.steps = progress(1)
            agent.feed = [(.resource, "Using the \(skill) skill", "")]
        case .done:
            agent = Agent(name: name, provider: provider, model: model, title: title, status: .done, minutes: minutes, steps: progress(5), branch: branch)
        case .rest:
            agent = Agent(name: name, provider: provider, model: model, title: title, status: .done, minutes: minutes, steps: progress(5), stale: true)
        }
        return agent
    }

    /// A conversation for an agent: your request, its plan, a tool step and where it is now.
    static func conversation(_ value: WorkspaceAgent) -> Transcript {
        var transcript = Transcript()
        let steps = MilestoneList.milestones(value.plan).map(\.title)
        let plan = steps.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: "\n")
        var entries: [Entry?] = [
            .demo("c1", "You", value.task + "."),
            .demo("c2", "Assistant", "On it. Here's the plan:\n\n" + plan),
        ]
        if !value.latestToolDetail.isEmpty, value.latestTool == "Bash" {
            entries.append(Entry.demoTool("c3", ["type": "commandExecution", "command": value.latestToolDetail, "status": "completed"]))
        }
        let now = MilestoneList.milestones(value.plan).first { $0.state == .now }?.title
        entries.append(.demo("c4", "Assistant", value.status == .done ? "Done. Everything passes; it's ready for your review."
                             : "Making good progress" + (now.map { ". Now: " + $0.lowercased() + "." } ?? ".")))
        transcript.entries = entries.compactMap { $0 }
        return transcript
    }

    // MARK: The projects

    static let atlas = Project(name: "Atlas API", agents: [
        a("Nova", .claude, "Rate limiter for the public API", .cook("Sources/Middleware/RateLimiter.swift")),
        a("Theo", .codex, "Idempotency keys for POST /orders", .cook("Sources/Middleware/Idempotency.swift")),
        a("Iris", .claude, "GraphQL schema for invoices", .cook("Sources/GraphQL/InvoiceSchema.graphql")),
        a("Omar", .codex, "Soft-delete for customer records", .cook("Sources/DB/CustomerRepository.swift")),
        a("Kai", .claude, "Containerize the worker fleet", .stove("docker build -t atlas-worker .")),
        a("Lena", .codex, "Move background jobs to Temporal", .stove("make migrate-jobs")),
        a("Hugo", .codex, "Blue-green deploy pipeline", .stove("terraform plan -out deploy.plan")),
        a("Ivy", .claude, "Seed staging with fixtures", .stove("npm run seed:staging")),
        a("Max", .claude, "Investigate the p95 latency spike", .research("Sources/Telemetry/LatencyHistogram.swift")),
        a("Eli", .codex, "Find N+1 queries in the orders API", .research("SELECT * FROM orders")),
        a("Mia", .claude, "Plan multi-region failover", .plan),
        a("Owen", .claude, "Plan the API v3 deprecation", .plan),
        a("Ada", .claude, "Contract tests for partner API", .taste("swift test --filter PartnerContractTests")),
        a("Rex", .codex, "Load test checkout endpoints", .taste("npm run test:load")),
        a("Luz", .claude, "Fuzz the JSON parser", .taste("swift test --filter ParserFuzzTests")),
        a("Ben", .codex, "File Linear issues from Sentry alerts", .mcp("mcp__linear__create_issue")),
        a("Gus", .claude, "Cursor pagination for /v2/orders", .done, minutes: 4),
        a("Jade", .claude, "OpenAPI docs for webhooks", .done, minutes: 7),
        a("Noah", .codex, "Retry failed webhooks", .done, minutes: 9),
        a("Pia", .claude, "Upgrade to Swift 6.2", .rest, minutes: 1_900),
        a("Rio", .codex, "Dockerfile cleanup", .rest, minutes: 2_100),
        a("Tess", .claude, "Health check endpoint", .rest, minutes: 2_400),
        a("Vik", .codex, "Remove legacy v1 routes", .rest, minutes: 2_700),
        a("Wes", .claude, "Structured logging", .rest, minutes: 3_000),
        a("Yui", .claude, "Rotate API keys", .rest, minutes: 3_300),
    ], days: [9, 12, 10, 14, 13, 16, 18], changed: true)

    static let payments = Project(name: "Payments Gateway", agents: [
        a("Ava", .claude, "Usage-based billing meter", .cook("Sources/Billing/UsageMeter.swift")),
        a("Bo", .codex, "Multi-currency payouts", .cook("Sources/Payouts/FX.swift")),
        a("Cy", .claude, "3-D Secure 2 challenge flow", .cook("Sources/Cards/ThreeDS.swift")),
        a("Dee", .codex, "Refund API for partial refunds", .cook("Sources/Refunds/RefundController.swift")),
        a("Eve", .claude, "Ledger reconciliation job", .stove("make reconcile")),
        a("Finn", .codex, "Build the payouts service", .stove("go build ./cmd/payouts")),
        a("Gia", .claude, "Bundle the card vault", .stove("npm run build:vault")),
        a("Hal", .codex, "Why do payouts settle late?", .research("Sources/Payouts/Settlement.swift")),
        a("Ida", .claude, "Map chargeback reasons", .research("docs/chargebacks.md")),
        a("Jon", .claude, "Plan the SOC 2 audit log", .plan),
        a("Kit", .codex, "Idempotent webhook tests", .taste("go test ./webhooks/...")),
        a("Lou", .claude, "Tests for currency rounding", .taste("swift test --filter RoundingTests")),
        a("Moe", .codex, "Post payout summaries to Slack", .mcp("mcp__claude_ai_Slack__send_message")),
        a("Ned", .claude, "Apple Pay merchant validation", .done, minutes: 5),
        a("Oli", .codex, "Dispute evidence upload", .done, minutes: 12),
        a("Pam", .claude, "Bump Stripe SDK", .rest, minutes: 2_000),
        a("Quin", .codex, "Tidy the payouts README", .rest, minutes: 2_500),
        a("Ray", .claude, "Remove dead feature flags", .rest, minutes: 2_900),
        a("Sol", .codex, "Rename settlement tables", .rest, minutes: 3_200),
    ], days: [6, 8, 7, 9, 11, 10, 12], changed: true)

    static let insights = Project(name: "Insights Dashboard", agents: [
        a("Zoe", .claude, "Cohort retention chart", .cook("app/charts/RetentionChart.tsx")),
        a("Ruby", .claude, "Revenue by plan widget", .cook("app/widgets/RevenueByPlan.tsx")),
        a("Arlo", .codex, "Dark mode for dashboards", .cook("app/theme/dark.css")),
        a("Bea", .claude, "Nightly ETL to Snowflake", .stove("dbt run --select marts")),
        a("Cal", .codex, "Warm the query cache", .stove("npm run cache:warm")),
        a("Dot", .claude, "Embeddable charts SDK", .stove("pnpm build --filter charts-sdk")),
        a("Fox", .codex, "Preview environments", .stove("vercel build")),
        a("Gil", .claude, "Why do funnels double-count?", .research("app/funnels/dedupe.ts")),
        a("Hana", .codex, "Benchmark ClickHouse vs Postgres", .research("docs/benchmarks.md")),
        a("Felix", .claude, "Polish the onboarding charts", .research("app/onboarding/Charts.tsx")),
        a("Ike", .claude, "Plan usage alerts", .plan),
        a("Jo", .codex, "Snapshot tests for charts", .taste("pnpm test charts")),
        a("Lia", .claude, "CSV export for reports", .done, minutes: 6),
        a("Nia", .codex, "Saved dashboard views", .done, minutes: 10),
        a("Oz", .claude, "Bump React to 19", .rest, minutes: 2_000),
        a("Pip", .codex, "Fix flaky date picker", .rest, minutes: 2_600),
        a("Quy", .claude, "Lint fixes", .rest, minutes: 3_000),
        a("Rae", .codex, "Archive old dashboards", .rest, minutes: 3_400),
    ], days: [4, 4, 6, 5, 7, 6, 8], changed: true)

    static let checkout = Project(name: "Checkout v2", agents: [
        a("Priya", .claude, "Apple Pay on mobile web", .cook("src/checkout/ApplePayButton.tsx")),
        a("Sam", .claude, "One-click upsell after purchase", .cook("src/checkout/Upsell.tsx")),
        a("Tom", .codex, "Address autocomplete", .cook("src/checkout/AddressField.tsx")),
        a("Leo", .codex, "Add EU VAT at checkout", .stove("npm run build")),
        a("Uma", .claude, "Rebuild the Stripe webhooks handler", .stove("npm run dev:webhooks")),
        a("Val", .codex, "Docker image for the checkout API", .stove("docker build -t checkout-api .")),
        a("Wil", .claude, "Why do carts expire early?", .research("src/cart/session.ts")),
        a("Xia", .claude, "Plan buy-now-pay-later with Klarna", .plan),
        a("Maya", .claude, "Fraud rules for card testing", .taste("npm test -- fraud")),
        a("Yan", .codex, "End-to-end checkout tests", .taste("npx playwright test checkout")),
        a("Ana", .claude, "Gift cards", .done, minutes: 5),
        a("Cleo", .codex, "Promo codes v2", .done, minutes: 11),
        a("Dan", .claude, "Bump Next.js", .rest, minutes: 2_000),
        a("Ezra", .codex, "Remove old cart API", .rest, minutes: 2_400),
        a("Fay", .claude, "Copy tweaks on receipts", .rest, minutes: 2_800),
        a("Hank", .codex, "Prune unused CSS", .rest, minutes: 3_100),
        a("Isa", .claude, "Tidy test fixtures", .rest, minutes: 3_500),
    ], days: [6, 8, 7, 9, 11, 10, 12], changed: true)
}
