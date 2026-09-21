# Diorama priorities 1–11: functionality report

**Acceptance update:** 0.3.19 (build 22) adds three fixes found during testing. The final regression suite passes 120 tests; three opt-in live suites also pass, with one structured-plan emission check explicitly blocked. Native UI checks now cover the main controls. See [acceptance results and remaining gaps](ACCEPTANCE_RESULTS.md). The original release evidence below is historical.

**Delivered:** native Diorama **0.3.18 (build 21)**, 20 September 2026. All 11 experiences in the agreed [desktop UX baseline](DESKTOP_UX_BASELINE.md) have implementation coverage. Priorities 1–3 came in 0.3.17; this release adds 4–11 and integrates their execution states.

**This completes the scoped checklist, not full Codex App Server or official desktop feature parity.** The original opportunity audit included broader ideas that the subsequent desktop baseline explicitly deferred. Those remain deferred, including advanced queue editing and worktree management. Live end-to-end certification of every mutation is also not complete.

The rebuilt app is at [`dist/Diorama.app`](../dist/Diorama.app). The running app was not restarted. Reopen the rebuilt app after active work finishes to use this release.

## What you can do now

### 1. Correct Codex while it is working

Use the existing composer to send a correction without stopping the turn. Stop remains a separate action. Steering targets the exact active turn through `turn/steer` and `expectedTurnId`; it does not silently become a new run when the turn ends. Drafts survive rejected delivery, and uncertain delivery is not automatically retried. Model and permission changes do not ride along with a correction.

### 2. Follow the plan and inspect changes

Structured plan updates appear as a native checklist. The changes inspector shows the reported file list and diff for the last turn beside the conversation. This helps you follow progress and inspect edits without reading raw protocol events.

The inputs are `turn/plan/updated`, `turn/diff/updated`, and typed file-change items. The inspector is scoped to reported turn changes, not the entire Git working tree. A complete reconstruction of historical plan updates is not promised.

### 3. Answer questions and approvals with the right scope

Requests distinguish optional questions from input that blocks execution. Approval controls preserve the exact choices and structured rule amendments offered by App Server. Supported MCP connector forms and URL flows have native response controls; automatic-review notices remain distinct from user approvals.

Unsupported custom form schemas fail closed instead of inventing responses. The app does not override automatic approval review or grant permissions simply because a connector is present. See the [priority 1–3 review report](PRIORITIES_1_3_REVIEW.md) for detailed coverage.

### 4. Manage goals and understand usage

A goal row above the composer provides create, edit, pause/resume and clear actions, including an optional token budget. These use `thread/goal/get`, `thread/goal/set` and `thread/goal/clear`. Creating or resuming an active goal can authorize continued work; it is an explicit user action. Stop pauses an active goal before interrupting. Imported conversations blocked by an active goal offer an explicit pause-and-reconnect action.

**Usage** shows reported last-turn and conversation token counts, model context capacity, account rate limits and reset information. **Compact conversation** requests `thread/compact/start` when idle. Token totals, capacity and account limits stay separate; there is no invented dollar estimate or exact context-fill percentage. Leaving an existing goal budget blank omits the update; it does not promise to clear the previous budget. Other-client ownership can still prevent resume.

### 5. Organize conversations

Conversation menus offer rename, pin, archive and restore. The sidebar has an archive filter, and pinned items sort within the existing folder organization.

Rename/archive/restore use official `thread/name/set`, `thread/archive` and `thread/unarchive` requests. **Pins are local to Diorama**, persisted in its preferences. The installed schema has no `isPinned` field; the earlier audit's proposed server pin mapping was incorrect and has been corrected. Pins do not synchronize to the official Codex app.

### 6. Search messages and load long histories progressively

Use **Find** or **Command-F** inside a conversation, or **Search chats** for cross-conversation search. Results can be paged and filtered by archive state. In-conversation matches load their associated turn and highlight/scroll to the matching message. Cross-conversation results open the matching conversation.

History uses bounded `thread/items/list` pages, with older content loaded on demand. Legacy `thread/read` and local history fallbacks remain available. Search uses `thread/search` and `thread/searchOccurrences`; it does not promise to index arbitrary tool output. Availability and coverage depend on the installed runtime and its stored messages.

### 7. Use real Plan mode

Choose **Plan** in the composer mode control, or use `/plan`. Available modes come from `collaborationMode/list`, and new runs send the actual `turn/start.collaborationMode` setting. This is not a text-only instruction pretending to be Plan mode.

The transition to implementation selects the default mode; sending the next prompt remains explicit. Planning can still inspect files and explore. Mode and permission policy remain separate, and mid-turn steering does not change the run's mode. Unsupported experimental capabilities produce visible availability feedback. The broader original idea of new speed-tier and named permission-profile catalogs was not part of the agreed Plan-mode baseline.

### 8. Discover and select skills and connectors

Open **Skills & connectors** beside the composer to inspect available skills, installed apps and MCP connection status. Select supported capabilities as typed skill/mention inputs. Explicit controls enable/disable a skill, reload MCP configuration, or begin a connector's OAuth flow. Merely opening the picker does not authenticate or change configuration.

The implementation uses `skills/list`, skill configuration updates, `app/installed`, `app/list`, `mcpServerStatus/list`, MCP reload and `mcpServer/oauth/login`. Installed apps load before the broader catalog. In the read-only runtime probe, **`app/list` timed out**, but **`app/installed` returned 11 configured apps**; the picker retains that installed-app fallback and displays the catalog warning.

This is not a new plugin marketplace, arbitrary desktop tool host, or interactive connector-app renderer. OAuth completion and provider-specific behavior still depend on the external provider and configuration.

### 9. Fork an approach and request code review

Use the conversation menu or `/fork` to create a new conversation from history; turn actions support forking through a selected turn. `thread/fork` defers goal continuation, so creating a branch does not itself submit a prompt or start goal work.

Use **Review** in the changes surface or `/review` to ask Codex to review uncommitted changes, or changes against a base branch. This uses `review/start` and displays review output in the conversation. It is actual Codex work and can consume usage.

**Forking copies conversation history and shares the working files.** It does not create a Git branch/worktree, isolate edits, stage files or merge changes. Those workflows remain outside this baseline.

### 10. Queue a follow-up for the next run

While a turn is working, select **Send for next run**. The composer visibly changes from a correction to a queued-message action. Pending messages can be inspected, removed, refreshed or explicitly started through **Run next message**.

Official `thread/queue/add`, `list`, `delete` and `start` requests back delivery. A message queued in this app session automatically starts after successful completion of the current turn, subject to goal state. Stop, interruption or failure pauses automatic delivery. Uncertain acknowledgements require queue inspection before another attempt, reducing duplicate submissions.

The app does not automatically drain recovered queues after restart. Advanced editing, reordering, scheduling and restart-persistence guarantees were explicitly deferred by the agreed UX baseline; they are not claimed complete here.

### 11. Read richer tool results

Commands show status, exit code, duration and expandable output; streamed command output updates the result. File changes expose diffs. Web searches expose returned sources. Generated/local images and supported embedded image results have bounded previews. MCP calls show progress and supported text/resource results. Worker references provide navigation, and review output receives a readable presentation.

Raw details remain available, with image payloads masked and large raw previews bounded. Image decoding is limited to 20 MiB inputs and 1,200-pixel thumbnails. Missing or unsupported results remain understandable rather than implying success. Remote image URLs are not fetched automatically. Arbitrary interactive connector applications remain a separate, unimplemented renderer contract.

## Architecture and App Server coverage

User action → native SwiftUI controls → execution controller → official Codex App Server request → response/notification → native conversation, inspector or library update.

Read-only discovery/history uses a separate connection from execution. Local presentation state, including pins, remains a Diorama responsibility. Claude influenced compact desktop presentation; Claude is not an execution backend.

Native request coverage is now **36 methods including initialization**, up from **11** at the initial audit. The version-pinned inventory contains **155 experimental-inclusive client request methods**. These are request counts, not a feature-completeness percentage: many methods are administrative, deprecated, platform-specific or unrelated to this UX baseline. Event rendering and server-initiated request handling also cannot be measured by client-method counts alone.

Full parity would require a separate acceptance matrix. Areas outside this release include realtime/voice, remote execution/environment management, additional host-provided dynamic tools, broader administrative/destructive APIs, platform-specific operations, full Git/worktree workflows, and arbitrary interactive connector rendering.

## Validation and evidence

- **117 tests in 25 suites passed** in the final `swift test` run. Coverage includes existing execution/HTML-canvas behavior, steering and approvals, goal recovery/stop ordering, queue acknowledgement and interruption handling, Plan-mode serialization, typed capability validation, catalog fallback, search/pagination, fork/review scope, streamed tool output and native rendering.
- **Five opt-in live tests were skipped**, including model execution/resume and desktop-exit lifecycle probes. Test success is not a claim that all features were exercised against a live account.
- **Read-only runtime checks** succeeded for mode discovery, skills, MCP status, account limits, thread listing/paging, goals, queue inspection and message search. The broader app catalog timed out; a separate installed-app check succeeded with 11 apps. No model turn, goal mutation, OAuth login or configuration write was performed by these probes.
- **Production build succeeded:** 0.3.18, build 21. `codesign --verify --deep --strict` passed after removing Finder-added bundle metadata. This remains a local ad-hoc-signed build, not a notarized distribution.
- **Native light/dark rendering artifacts** were generated and visually inspected. They use controlled fixtures, not a live-account screenshot. The fixture includes a disconnected Plan-mode state; its warning is not evidence that live mode discovery failed.

Evidence: [runtime probe](../artifacts/workflows/runtime-probe.json), [installed-app probe](../artifacts/workflows/installed-apps-probe.json), [light native rendering](../artifacts/workflows/workflow-light.png), [dark native rendering](../artifacts/workflows/workflow-dark.png), [method inventory](app-server-capability-audit.json).

Implementation entry points: [workflow controller](../Sources/DioramaCore/WorkflowFeatures.swift), [workflow controls](../Sources/DioramaApp/WorkflowViews.swift), [conversation actions and tool rendering](../Sources/DioramaApp/ConversationWorkflowViews.swift), [history paging](../Sources/DioramaCore/AppServerHistory.swift), [workflow tests](../Tests/DioramaCoreTests/WorkflowTests.swift).

## Review next

Reopen the rebuilt app after current work finishes. Start with Plan mode and the capability picker, then try a correction versus a next-run message, search/fork a conversation, and inspect a review result. Goal continuation and provider OAuth should be reviewed deliberately because they can initiate work or change connection state.

**Turn finished:** implementation, automated validation, release build and this report are delivered. **Scoped implementation goal finished:** the agreed 11-experience baseline is implemented. **Still unverified:** exhaustive live mutation behavior and full protocol/official-desktop parity; neither is claimed by this release.
