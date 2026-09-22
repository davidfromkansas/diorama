# Shared activity implementation

Codex and Claude are both in scope. Codex retains App Server. Claude supports the direct CLI and a pinned Agent SDK helper behind the existing execution transport. Packaged apps discover the bundled SDK helper automatically; `DIORAMA_CLAUDE_BACKEND=cli` retains the CLI fallback. Authentication continues through the installed Claude Code subscription login. No global Claude settings are changed.

## Support matrix

| Information | Codex | Claude CLI / SDK | UI |
|---|---|---|---|
| Proposed plans | Native plan items and deltas | ExitPlanMode plan text | Distinct conversation card and selectable Plan panel |
| Execution steps | turn/plan/updated revisions | TaskCreate/TaskUpdate, TodoWrite | Steps with reported status; turn completion does not finish remaining steps |
| Child agents | Collaboration variants and explicit child metadata | Task lifecycle and delegation metadata | Agents with parent indentation, status and read-only saved history |
| Tool activity | Structured tool items | Tool use/results | Timeline and details |
| Approvals and input | Native request events | Existing permission bridge and status events | Existing permission controls plus activity where reported |
| Usage and duration | Provider-reported counters | Result, model and task usage | Details at the reported scope; no overlapping totals |
| Compaction and limits | Supported structured events | System and rate-limit events | Timeline |
| Restart | Bounded journal restores last known state | Same | Last known label; no automatic execution |

Provider facts are preserved rather than inferred from assistant prose. Hidden reasoning is excluded. Child inspection uses read-only APIs, never resume. Changes and Activity share a single panel host.

## Verification on 2026-09-22

- Full Swift suite: **206 tests across 55 suites passed**.
- Node helper protocol tests: **4 passed**.
- Real Claude SDK subscription, permission, interrupt/steer, goal and structured activity probes passed.
- Controlled Claude task produced completed steps, child activity and readable saved child history; journal restoration passed.
- Native narrow panel walkthrough covered all sections, child unavailable state and preservation of an unsent composer draft.
- Packaged arm64 app built at `/tmp/DioramaActivityBuild.app`; deep strict signature verification passed. Its embedded Node/helper completed a real subscription turn.
- Tests exposed a Swift exclusivity crash while restoring the activity dictionary. Separating the read from the mutation fixed it.

## Coverage still to close

Codex's strict live checklist and nested-agent tests now pass on both desktop-bundled 0.154.0-alpha.6.2 (gpt-5.5) and standalone 0.153.4 (gpt-6-astra). The earlier missing-tool diagnosis was incomplete: checklists require an explicit opt-in, V1 delegation defaults to depth 1, and Diorama's allowlist omitted read-only thread/list. These are fixed with process-local launch settings and a transport allowlist correction. See [root-cause details](CODEX_TOOL_AVAILABILITY.md).

Notifications identifying only a turn resolve to its unique task. Ambiguous IDs are discarded. Read-only discovery pages descendants and verifies explicit ancestry before accepting results, so an ignored filter cannot introduce unrelated tasks.

Full VoiceOver interaction, Intel packaging and notarized distribution have not been verified in this batch. This build is local, not a published release.

Journal limits now apply across registered provider segments: 10,000 events or 25 MiB, retaining bounded current-state baselines and truncation flags. Tests cover combined count/byte limits and persistence across a store restart. Conversation membership comes from the existing saved conversation record.

Nested agents are ordered by explicit parent edges, with accessible nesting labels. Command-Option-1 through 4 select activity sections without stealing composer focus. Narrow-window keyboard switching and draft preservation passed manual verification. Section scroll anchors are retained separately; a full VoiceOver audio walkthrough remains unverified. The corrected two-level live probe passes on both tested runtimes. Nested discovery and rendering also pass fixture checks. Existing history remains readable when the activity journal is absent or damaged.
