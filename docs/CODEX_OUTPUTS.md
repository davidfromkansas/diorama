# Codex output coverage — 2026-09-27

Latest combined build: `dist/Diorama.app`. See [Independent provider outputs](DEEP_PROVIDER_OUTPUTS.md) for the subsequent search aliases, metrics, source inspection, tests and remaining acceptance gaps. Build names below describe earlier verification runs.

Diorama now presents more of the evidence already exposed by Codex. External viewing remains passive; this change does not resume a task, attach execution, answer approvals, or install hooks. It does not claim complete coverage or certified real-time delivery.

## Sources audited

- Installed Codex CLI **0.153.4**, including its locally generated experimental App Server JSON schema (`codex app-server generate-json-schema`).
- Metadata-only inspection of this development task's saved rollout: PascalCase UI items coexist with model-facing response records; command durations and file changes differ from public App Server JSON shapes.
- A designated Codex CLI session in `/private/tmp/diorama-codex-outputs`: native FileChange, CommandExecution, user/assistant messages and turn completion. No private conversation bodies were copied into fixtures.
- [Official App Server documentation](https://learn.chatgpt.com/docs/app-server), particularly item types and their lifecycle. The generated installed-version schema supplements newer types not described on that page.

## Gaps addressed

| Output | Previous gap | Current behavior | Verification |
|---|---|---|---|
| Commands | Passive reader flattened model tool text and skipped typed command evidence | Command cards retain output, exit code, status and duration | Fixtures, existing workflow tests, real CLI saved evidence |
| File changes | Typed rollout changes absent from conversation; no explicit file output preview | Per-file source diffs, completed-file references and explicit local previews; deletion/failed edits do not become produced files | Fixtures and real CLI HTML output |
| MCP results | Raw UI items skipped; media/resource handling inconsistent | Correlated cards with inputs, errors, text, images, embedded resources and resource links | Fixtures; actual rollout shape audit |
| Dynamic/function calls | Dynamic items had no typed renderer; local calls/results were disconnected | Dynamic content and correlated call/result cards; missing-call results stay inspectable | Fixtures and installed schema |
| Plans | Local typed plan exists, but raw update_plan input was opaque | Proposed plans plus reported step/status lists; no generated progress | Fixtures, existing activity pipeline |
| Web search | Typed rollout Extension items omitted | Search query/action/results and safe source links | Installed schema and shape audit; native live comparison pending |
| Generated/viewed images | Rollout media often omitted or base64 flattened | Explicit image output previews; viewed images are labeled as views rather than created artifacts | Fixtures/schema; real image generation not run |
| User attachments | App Server flattened media to a placeholder | Separate attachment outputs alongside readable message text | Normalization tests; broader live media matrix pending |
| Agent work | Inspector details were Claude-only | Shared agent inspector displays observed tools, plans, outputs and conversation links | Existing workspace tests; large live subagent comparison pending |
| Unknown formats | One unknown App Server item rejected the whole history | Keep known rows, show unknown-item placeholders and diagnostic counts without unknown bodies | Regression tests |
| Row identity | App Server IDs depended on preceding row count; local fallback IDs depended on loaded tail indexing | Native turn/item identities or byte offsets; stable row when a tool result arrives | Append, duplicate, missing-call and pagination tests |

## Boundaries and remaining gaps

- **Codex CLI transcript buffering remains degraded by provider.** No synthetic streaming, no independent App Server idle-state inference, and no observation-triggered resume. Existing buffering notices remain in the UI.
- **Codex Desktop live comparison is not verified.** Its Computer Use restriction has not been bypassed. Reading supported saved-record formats is not equivalent to testing the source app live.
- Embedded/remote MCP app widgets are not automatically fetched or executed. Structured local/embedded HTML can use the isolated preview; remote artifacts remain external links. Opaque `ui://` resources need a separately designed read-only resource path.
- Audio/video playback and unrecognized media types are explicit unsupported outputs. Supported local documents share the existing image/text/Markdown/PDF/HTML viewer; other types use external opening where a safe URL exists.
- Arbitrary prose paths and shell commands do not establish file production. Older rollouts exposing only generic tool text retain text cards; they may lack inspectable file outputs.
- Raw call outcomes without success evidence are labeled **Returned**, not assumed successful. Known MCP/dynamic errors are displayed as failed. Plans show reported steps; ownership/progress is never invented.
- Previews of historical file references show the current file. Historical diffs are shown only when supplied by Codex.
- Reasoning/encrypted content stays excluded. Inline media is redacted from raw details. Preview data and output lists remain bounded; oversized/unsupported content is explained.
- Source-visible-to-pixel latency, multi-turn Desktop/CLI comparisons, richer generated-image/media scenarios, and native focus/accessibility/selection verification remain separate acceptance work.

## Validation

- Full Swift suite: **343 tests / 84 suites passed** (`/tmp/diorama-codex-full.log`).
- Final focused rerun: **24 tests / 4 suites passed**, covering final text retention/card presentation and long-history regression (`/tmp/diorama-codex-final-focused.log`).
- Final media compatibility/bounds rerun: **47 tests / 4 suites passed** (`/tmp/diorama-codex-bounds-tests.log`), including both plain base64 and data-URI image output.
- Shared Claude helper: **6 tests passed** (`/tmp/diorama-codex-helper-regression.log`).
- Real CLI smoke: completed bounded HTML creation and file-read task; opt-in test read the actual saved transcript, found the completed file output and command card, and loaded the HTML preview. This verifies ingestion, not rendered latency.
- Native fixture rendering inspected at 420/900 points: `artifacts/codex-outputs/cards-*.png`.
- HTML isolation tests passed unchanged: opaque iframe, no parent/native access, blocked networking, explicit opening. Shared companion-file bounds and traversal protection remain in place.
- Packaged `dist/Diorama-Codex-Outputs.app` with bundled models/helper and verified ad-hoc signature. No installed app was replaced and no release was published.
- Packaged native check after unlock, **2026-09-27 08:39–08:42 HKT: passed for the designated saved CLI output**. Opened the discovered disposable session from Home; inspected completed file/command cards; explicitly opened `codex-counter.html`; clicked Increment counter and inspected screenshots showing **0 → 1**. Escape dismissed the preview. The main-agent inspector exposed its tools/output, and the file's conversation link returned to the matching conversation card. This is functional pixel verification, not a latency measurement or live source-client comparison.
- Native inspection found a real omission: persisted `AgentMessage.content` uses capitalized `Text` blocks, which produced blank assistant rows. Fixed text normalization and user-text attachment classification; added a regression for native user/assistant records, deduplication, and App Server history. **11 Codex output tests passed**, including the actual disposable transcript (`/tmp/diorama-codex-native-fix-tests.log`). Rebuilt the package and visually verified its complete assistant completion message.
- UI automation intermittently failed to activate the Open project menu/file chooser with multiple Diorama copies registered. The session was already discoverable from Home, so this run used that path; adding the folder through the chooser is not counted as verified by this run. No execution controls were used.

## Try it

Open `dist/Diorama-Codex-Outputs.app`. From **Home**, search `codex-counter` and select the disposable Codex conversation (or add `/private/tmp/diorama-codex-outputs`). Choose **Conversation**, then **Preview** on `codex-counter.html`. The button increments the visible counter. Selecting the main desk exposes the same recent tools/output and conversation links.
