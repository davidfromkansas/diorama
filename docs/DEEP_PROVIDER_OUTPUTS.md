# Independent provider outputs — 2026-09-27

The combined build is `dist/Diorama.app`. This iteration expands both providers, but does **not** establish complete native-event coverage or four-client real-time acceptance. Earlier provider reports describe their own dated builds; this report supersedes their build path and adds the changes below.

## Architecture and content preservation

The stored `Entry` envelope now has separate optional `CodexPresentation` and `ClaudePresentation` payloads. Existing entries decode without either. Provider dispatch, metric interpretation, and evidence normalization remain separate; low-level chart drawing, file previews, and source loading are reused.

Saved transcript rows retain immutable file/byte-range/SHA-256 references. Expanding source details reads that record off the main actor, verifies its digest, and offers progressively larger bounded reads independently of history pagination. A replaced record produces an error instead of substituting content. Correlated tool cards retain both call and result references. Copy is labeled as copying loaded source. Reasoning, encrypted content, internal prompt snapshots, and media payload bytes stay excluded from normal source inspection. Unknown visible records retain their type, position, bounded inspectable fields, and type/count diagnostics.

No execution transport or ownership request was added. External observation remains passive. Runtime-only evidence is not obtained through resume or attachment.

## Codex coverage

“Fixture” means parsed/presented regression coverage, not a live client pass. Desktop and CLI have independent acceptance results even where records share a format.

| Evidence / variant | Parsed fields and conversation | Workspace | CLI verification | Desktop verification |
|---|---|---|---|---|
| Native messages and model-facing text | PascalCase and public API text; keep distinct assistant output while deduplicating actual duplicate text | Existing conversation links | Saved disposable CLI evidence passed previously; fixtures passed | Fixtures; live not verified |
| Extension `web.search`, `web_search`, WebSearch | Action/query/results; static browser-style card, safe source links and raw details | Tool detail | Alias fixtures and sanitized shape audit; live not verified | Encountered saved shape; live not verified |
| Command/file/MCP/dynamic calls and results | Correlated inputs/output/status, existing supplied diffs/media; exact GitHub server mark, generic connector fallback | Tool outcome and output links | Fixture and prior saved CLI smoke | Fixture; live not verified |
| Native versus wrapper outcomes | Native failure is authoritative; generic result is Returned, never assumed Completed | Same turn-scoped outcome; native records override weaker wrappers | Incremental activity regression passed | Same format fixture; live not verified |
| Token count and usage records | Last reported, cumulative, and response measurements remain distinct; cached input labeled as subset | Provider event details | Fixture; live metric comparison not verified | Fixture; live metric comparison not verified |
| Plans, collaboration, generated/viewed images, reviews, compaction | Existing typed cards retained; provider payload dispatch and source inspection added | Existing agent tools/plans/output references | Fixtures; full native capability matrix not verified | Fixtures; full native capability matrix not verified |
| Warning/error/input/approval notice variants | Recognized saved notices remain inspectable; no interactive resolution | Evidence available through conversation; bespoke lifecycle UI incomplete | Not verified | Not verified |
| Goal/queue/connector lifecycle and other runtime-only notices | Unknown visible evidence remains inspectable; specialized reduction not yet implemented for every variant | Dedicated activity mapping not yet implemented for every variant | Source availability not established for every subtype | Source availability not established for every subtype |
| Unknown item/event | Type and bounded source details; diagnostic counts | Conversation access; no invented activity | Fixtures passed | Fixtures passed |

CLI transcript buffering remains **Degraded by provider** based on the prior observation work. This change does not synthesize partial output. Desktop source-app control remains restricted; its live gate is **Not verified**. A broad runtime schema is not proof that those events are exposed to a passive external viewer.

## Claude Code coverage

| Evidence / variant | Parsed fields and conversation | Workspace | CLI verification | Local Code-tab Desktop verification |
|---|---|---|---|---|
| Messages/tool calls/results | UUID/block/tool-use scope and correlated results; original inputs/results preserved; structured tool-result metadata retained | Agent tool/output links | Fixtures and prior saved smoke; full live gate not verified | Fixtures; full live gate not verified |
| Artifact guidance and outputs | Artifact · Quickstart label; guidance remains tool output; recognized successful files have explicit preview actions | Produced outputs when established by evidence | Fixtures; prior counter preview passed | Saved-shape fixtures; live artifact matrix not verified |
| Search/fetch | Claude query/URL presentation with preserved tool results, independent of Codex search schema | Tool details | Fixture-level presentation; live not verified | Live not verified |
| Task/Agent delegation | Reported description/type and returned agent ID; no inferred ownership | Existing verified identity associations only | Fixture-level; full delegation scenarios not verified | Not verified |
| Task/system notifications | task_id, tool_use_id, description, summary, status, errors and output_file retained | Dedicated task/activity coverage remains partial | Not verified | Not verified |
| Progress subtypes | agent_progress, bash_progress, mcp_progress, hook_progress retained as reported evidence | Specialized reduction of every subtype not yet implemented | Sanitized fixtures | Sanitized fixtures; live not verified |
| Attachments | Internal subtypes excluded; unrecognized visible subtypes inspectable rather than silently counted | No speculative produced files | Fixtures; subtype audit incomplete | Fixtures; subtype audit incomplete |
| Usage/cache/cost/duration | Separate message/turn measurements; native input/output, cache read/creation, reported cost/duration | Provider detail cards | Fixtures; live accounting comparison not verified | Fixtures; live accounting comparison not verified |
| Input requests | Passive request card; AskUserQuestion result becomes Resolved; Respond in Claude | Existing attention behavior | Fixtures; complete approval lifecycle not verified | Not verified |
| Unknown records | Explicit fallback and sanitized source fields | No invented lifecycle | Fixtures passed | Fixtures passed |

The helper adapter now preserves message usage, task/system/result metadata, attachments, progress data and tool_use_result within explicit size bounds. These fields were previously lost in that path. Unknown content-block specialization and reconstruction of every streaming delta remain incomplete. Source evidence absent from a path is not labeled unsupported without a source audit.

## Visuals and Paper status

Six original Paper concepts establish the direction: search, usage, structured results, HTML, connectors, and requests/errors. New Codex and Claude state sheets were started but are **incomplete and unreviewed**: Paper returned “Weekly MCP limit reached. It resets in 6 days.” No upgrade was purchased. Resume design work after access returns; do not count these sheets as delivered.

Implemented cards use graphite surfaces, amethyst/sage usage segments, static search evidence, explicit HTML previews, and a bundled GitHub SVG with generic fallback. Native fixture images at 420 and 900 points were visually inspected: `artifacts/deep-provider-outputs/provider-cards-420.png` and `provider-cards-900.png`. These are rendered fixtures, not live source-client latency evidence.

## Validation results

- Final focused Swift run: **27 tests / 7 suites passed**, including provider formats, source replacement protection, independent presentation, and native activity precedence (`/tmp/diorama-deep-final-focused.log`).
- Additional relevant regression runs: 35 tests / 8 suites and 18 tests / 7 suites passed before the final small refinements.
- Full Swift run: **352 tests / 87 suites, 9 issues** in timing/scene tests under concurrent rendering load (`/tmp/diorama-deep-full.log`). This is a failed full-suite run, not a clean acceptance pass.
- Affected timing/scene suites rerun in isolation: **13 tests / 2 suites passed** (`/tmp/diorama-deep-timing-rerun.log`). Thirty observer/model updates measured p95 69 ms, maximum 315 ms. These are not pixel timings; concurrent-load reliability remains an open validation item.
- Final Claude helper run: **7 tests passed** (`/tmp/diorama-deep-helper-final.log`). An initial simultaneous run collided with packaging's dependency reinstall; rerunning after packaging passed.
- Final combined debug package built with bundled assets/helper and signature verification (`/tmp/diorama-deep-package-final.log`). No installed app or published release was replaced.
- Outside-checkout native smoke at approximately 10:30 HKT: launched `/private/tmp/diorama-deep-verification/Diorama.app`, selected the designated `codex-counter` history from Home and inspected actual pixels showing file/command cards and reported usage. The buffering notice remained visible. No source prompt or execution control was used. This validates packaged saved-history rendering, not the four-client live gate.

## Remaining acceptance work

All four 30-update / three-turn **visible-pixel** acceptance gates remain **Not verified** by this iteration. Existing fixture, saved-history, and model timing results do not substitute for them. Codex CLI additionally retains its provider-buffering limitation. Respect Codex Desktop access restrictions and use user-operated source interactions for that gate.

Complete the Paper sheets; finish native subtype audit and specialized lifecycle mapping; test long-output responsiveness and concurrent timing failures; run approval/resolution, delegation, generated media, background/recovery, keyboard/VoiceOver/reduced-motion and selection/camera checks separately per client. Retain p95 ≤500 ms and maximum 1 second from readable evidence to visible pixels. Do not relax those targets or infer completion from silence.

Remote MCP widgets, audio/video playback, new scene props, capability management and release publishing remain intentionally excluded.

## Follow-up verification — 2026-09-27, 11:50 HKT

This follow-up retains the independent acceptance gates above. Durable logs and aggregate measurements are under `artifacts/output-acceptance-20260927/`.

### Fixes from real source evidence

- Passive observation used a session/inode identity as the source filename, which silently prevented expandable source references from being retained. Both provider normalizers now receive the actual transcript path independently of the stable identity scope. Parameterized regression coverage verifies source loading and stable row identity after appends, including leading blank lines.
- Actual Claude CLI evidence exposed `mode` and `cost-state` records. Mode is now a named event; cumulative session usage has its own view, with native per-model input/output/cache measurements, reported cost and duration. Cumulative snapshots are explicitly not additive. Helper history preserves the same reported fields. No estimated cost is introduced.
- The final full-suite run found one long-history parsing failure (531 ms against its unchanged 500 ms budget). Source-reference digests performed 32 locale-aware formatting calls per row. Direct UTF-8 hexadecimal encoding preserves the stored digest format and removes that overhead. The targeted rerun passed at 365 ms maximum; source loading/replacement regressions also passed. Full rerun status is recorded below when complete.

### Source-client evidence and measurement limits

| Client | This follow-up established | Still not established |
|---|---|---|
| Claude CLI 2.1.283 | Three bounded source turns; 125 observer updates with hooks disabled; correlated Read/Write results, three HTML output references, source inspection, and terminal state passed against saved evidence | Pixel latency, complete lifecycle/approval/subagent matrix |
| Codex CLI 0.153.4 | Three completed source turns; native command/output, usage, source inspection, and terminal state passed against saved evidence | Corrected-run timing report was lost during environment interruption; pixel latency and full lifecycle matrix |
| Claude Code Desktop | Primer and one six-Read/HTML-Write tool turn confirmed in the source UI and saved history; login recovered | Remaining two tool turns and pixel gate. Temporary folder disappeared and was restored; source window later remained on loading placeholders |
| Codex Desktop | No additional live acceptance claim | Automated source-app access remains restricted; user-operated run pending |

Claude CLI aggregate file-mtime-to-model latency was p95 50.4 ms / maximum 68.6 ms; source-timestamp-to-model was p95 662.3 ms / maximum 696.3 ms. File mtime is a proxy for readable evidence, and neither measure establishes displayed pixels. Temporary per-event files disappeared during an environment interruption; these aggregates were recovered from tool results and are explicitly labeled in the durable JSON. Do not treat them as a complete correlation dataset.

The Codex source driver initially left stdin open and stalled. It now closes stdin, bounds each source turn to 150 seconds, and avoids a blocked stderr pipe. That initial failure was in the test driver and is not evidence of provider buffering. The previously established Codex buffering limitation is not overturned by saved-history checks.

A separate 30-append test with a mounted SwiftUI conversation measured evidence-to-layout p95 65 ms / maximum 71 ms. Layout completion is not proof of pixel presentation. The 300-second Desktop probe received no new events while source recovery was in progress and is **Not verified**, not a latency pass. No probe execution requests were sent.

Older concurrently running Diorama copies showed sustained CPU activity; one sample was dominated by SwiftUI layout. A 3.9% spot reading from the combined build is not a controlled performance pass. This remains an open investigation.

### Final regression and package result

The full post-fix serial run passed **359 tests in 90 suites**. Long-history append maximum was **381 ms**; 30 watcher/model updates were p95/max **61 ms**; the 30 mounted conversation updates were p95/max **58 ms** to layout, with pixel measurement explicitly false. All budgets were retained. Claude helper tests passed **8/8**. Serial execution avoids unrelated SwiftUI snapshot suites competing for the main actor; this does not establish performance under arbitrary concurrent load.

The existing combined debug package at `dist/Diorama.app` was rebuilt with these fixes and signature verification. The package log is retained in the dated artifact folder. No release was published and no installed app was replaced. Native inspection of the designated Desktop history showed the completed Write card, HTML reference, usage cards, source-provided completion text, and the view-only Desktop footer. The first relaunch control timed out; a subsequent connection succeeded. Process inspection confirmed the rebuilt dist binary launched at 11:48:50 HKT. Native pixels then showed the Desktop Write card and its newly restored Source input / output disclosure; opening it loaded the actual correlated source record. This is a final-package saved-history smoke pass, not live pixel-latency acceptance.
