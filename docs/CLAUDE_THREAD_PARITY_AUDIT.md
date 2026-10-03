# Claude thread → Diorama: practical parity audit

Date: 2026-09-28. Scope: V2nycsim / NYC Sim project onboarding.

## Evidence and limits

Compared prior native observations in V2NYCSIM_OBSERVATION_LOG.md with the current saved Claude parent transcript and Diorama source. Verified transcript title and session ID `290541a4-7f17-47b4-880d-2b504a94b575`. No source execution, approval or transcript modification performed. This is not a new full native UI/latency acceptance run. Desktop findings do not certify CLI parity.

Saved evidence includes 18 Agent invocations and 18 child transcript files, 3 AskUserQuestion calls, 3 ExitPlanMode calls, 1 Workflow call, 52 Write calls, 10 Edit calls, 255 Bash calls and 42 browser-batch calls. These are raw parent-record counts, not deduplicated task/output totals. Parent call IDs all have matching result IDs at this snapshot; latest record timestamp is 2026-09-28T00:56:06.227Z. Consequently the earlier observed pending Workflow must not be described as still pending without a fresh check. Outcome of that result was not classified in this audit.

## Gaps and proposed behavior

| Area | What Diorama does now | Missing / proposed behavior | Evidence |
|---|---|---|---|
| External permissions | Desktop session is explicitly observation-only. Header can say Awaiting approval while Workflow card says Running. | Recognize pending request with tool/action, scope, request identity and resolved outcome. Offer approve/deny only through a verified channel to the same running source session. | C12; ExecutionController.requireControllable; ClaudeNormalizer tool-use default. |
| Answering questions | AskUserQuestion is recognized; inputs/details collapsed; no external answer control. | Readable question, single/multiple choices and free text, recorded answer, pending/resolved state. Direct submission requires the same verified response channel. | C01; ClaudeEntryView; three source calls. |
| Plan review | Plan text exists, but Activity shows an older proposal. | Latest evidenced plan revision, historical versions and approval state; review content without leaving Diorama. Approval subject to external response-channel gate. | A01; three ExitPlanMode calls and subsequent edits. |
| Outputs/files | Recognized Write/Edit and structured media can produce Preview/Open externally cards. | Discover supported outputs consistently across tool types; group by producing agent, expose missing-file reasons and explicit local/remote links. Shell-created files need structured evidence, not guesses from arbitrary prose. | ClaudeNormalizer file-output handling; 33 edited_text_file attachments fall through. |
| Local web previews | Source reports localhost output; dedicated server affordance is only an idea. | Actual reported local URL/port, readiness evidence, See local preview on task/desk; multiple servers; no automatic startup or browsing. | Existing proposed improvement in observation log. |
| HTML tab | Separate agent-maintained canvas, empty and labeled Not connected/No recent activity during active observation. | Distinguish canvas publication from connection health; provide a clear outputs index or route to output previews. Do not imply this tab mirrors Claude's browser. | H01. |
| Background work | Agent desks exist; commands and subagents are not a unified readable task inventory. | Separate agent identities from background processes/workflows; parent ownership, lifecycle and output links. Servers are service indicators, not endlessly working avatars. | Native background panels vs desks; source Agent/Workflow/TaskStop/Bash tools. |
| Workspace | Child discovery grows; active avatars can be obscured; desk labels emphasize Last known and long prompts. | Readable identities, visible activity/outcome plus freshness; inspect tool/task/output details. Verify animation against evidence before calling it broken. | W01–W05. |
| Timeline | Historical child entries receive newer displayed times on later checks. | Preserve source event times and stable order; distinguish import/sync times. | A02; underlying cause not yet proven. |
| Internal metadata | Literal system reminder leaks into normal conversation; several metadata subtypes create noisy cards. | Exclude internal reminders/prompt snapshots; compact meaningful system events; retain legitimate surrounding messages. | C10; subtype inventory below. |
| Usage | Large message-level charts interrupt the conversation. | Compact default, optional cache/input/output details; preserve measurement semantics and avoid summing duplicate message usage. | C02; per-message dedup already exists. |

## Additional subtype audit

Raw attachment counts: deferred_tools_record 237; edited_text_file 33; queued_command 34; silent_turn_reminder 22; plan_mode 1; plan_mode_exit 1. Also 172 relocated records and 49 file-history-delta records. Counts may include repeated source records and are not counts of distinct visible events.

- `edited_text_file` fields: filename, snippet, type. Supports a file/snippet presentation, not necessarily a complete historical diff.
- `queued_command` fields: commandMode, prompt, source_uuid, timestamp, type, usage. Inspect origin and deduplicate against the eventual user message before presenting queued input. It is not automatically a shell/background command.
- `deferred_tools_record` fields: entries, toolInputCopies, type. Needs semantic inspection before retaining tool evidence versus hiding bookkeeping.
- `plan_mode` / `plan_mode_exit`: planExists, planFilePath and mode metadata. Potential plan-link evidence; a path alone does not establish the historical revision.
- `silent_turn_reminder`: text/type. Internal-guidance candidate; excluded from ordinary chat after confirming semantics.
- `relocated` and `file-history-delta`: generic fallback today; inspect schema for project migration and source-backed file changes. Do not manufacture diffs from current files.

## Interaction boundary: requires a separate implementation gate

The user's requested product direction now includes responding inside Diorama, expanding beyond the earlier passive-viewer scope. This audit does not approve any pending source request.

Diorama already has ClaudeExecutionTransport.respond for requests received by its own controlled CLI/SDK transport. That is not evidence it can answer requests owned by an independently running Claude Desktop or CLI. Desktop IDs are deliberately blocked by ExecutionController, and transcript observation alone cannot return an answer.

Before enabling external controls, verify a supported, session-bound response mechanism separately for Desktop and CLI. Requirements: exact session/request identity; allowed decision choices and scope; stale-request rejection; at-most-once delivery; source acknowledgement; resolution in both clients; reconnect handling without replay; no second execution owner or resumed duplicate task. Do not remove the view-only guard merely to enable buttons, write answers into transcripts, or silently resume sessions. If the mechanism is unavailable, keep an honest Open/Respond in Claude handoff and mark in-app response unsupported for that client. Current audit does not claim no provider mechanism exists; that investigation remains open.

## Practical order

1. Fix displayed request states/questions, internal-reminder leakage and stale plans.
2. Make files, images and local previews easy to find through outputs and desk inspectors.
3. Verify Desktop and external CLI response mechanisms before implementing approve/answer controls.
4. Improve background-task/workspace clarity and source timestamps.
5. Run live source-to-Diorama checks independently per client, including request resolution in either client and stale/repeated clicks.

No shipping code changes or new live acceptance claims in this audit.
