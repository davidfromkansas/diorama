# Codex App Server opportunities for Diorama

**Implementation update:** the agreed priorities 1–11 baseline is now implemented. See [the full functionality report](PRIORITIES_1_11_REPORT.md). Native request coverage is now 36 methods including initialization. The counts and gap descriptions below describe the pre-implementation audit unless noted. Correction: the installed schema has no `isPinned` metadata field; pins are local to Diorama.

Audited 2026-09-20 against the native Swift sources and **installed Codex CLI 0.153.4**. Recommendation: first make ongoing work easier to understand and direct; then add organization and integrations.

The largest immediate wins are **mid-turn steering, a native plan/changes inspector, goal and usage visibility, and completing the existing question/approval protocol support**.

## Evidence and scope

I generated ordinary and experimental JSON schemas locally, inspected the native transports, controller, history reader, composer and request UI, and checked the [official App Server documentation](https://learn.chatgpt.com/docs/app-server). Official documentation describes version-specific schema generation and experimental opt-in; this audit uses the installed schema for exact names and fields. Website documentation may describe a different version.

The ordinary export contains **99 client request methods**; the experimental-inclusive export contains **155**. Diorama calls **11**, including `initialize` (10 operational methods). These are method counts, **not a feature-completeness percentage**. Many unused methods are irrelevant, privileged, deprecated, or optional. The ordinary export also contains types described as experimental, so “ordinary” does not mean universally stable.

[Machine-readable inventory](app-server-capability-audit.json) lists all 155 methods, export membership, parameters and whether the native app uses them. Existing [conversation inventory](../CONVERSATION_ITEMS.md) covers items, notifications and server requests. Scripts and historical probes do not count as shipped native integration.

No feature code was changed, no model turn was started, and no account/project/settings mutations were performed. This is a source/schema audit, not runtime certification of the proposed features. Existing test files were inspected; tests were not rerun for documentation-only work.

## Already implemented — do not rebuild

- Separate read-only discovery/history and execution connections; paginated active/archived `thread/list`, `thread/read`, and local fallback.
- `thread/start`, same-ID `thread/resume`, `turn/start`, `turn/interrupt`, model/effort selection through `model/list`.
- Command/file approvals, turn-scoped permission grants, user questions, and request resolution.
- Background terminal listing/termination and deliberate shutdown/reconnection behavior.
- Text and local-image inputs, file references, Markdown, inline local `imageView`, live HTML canvas, basic worker discovery and activity.
- `thread/goal/get` as a resume precondition. This checks for active goals; it is not a goal dashboard.

Evidence: [request allowlist](../Sources/DioramaCore/ExecutionTransport.swift#L95), [controller](../Sources/DioramaCore/ExecutionController.swift#L114), [history transport](../Sources/DioramaCore/AppServerHistory.swift#L32), [attachment serialization](../Sources/DioramaCore/ConversationAttachment.swift#L35).

## Recommended sequence

Effort below is relative implementation scope, not a calendar estimate. “Partial” means Diorama supports some related behavior but omits the named protocol surface.

| Order | Capability | Current gap | Suggested experience | Effort |
| --- | --- | --- | --- | --- |
| 1 | Mid-turn steering | Missing | Send a correction while Codex works; preserve Stop as a separate action | Medium |
| 2 | Native plan + changes inspector | Partial: raw items, no structured turn plan/diff | Live checklist and per-file diff next to the conversation | Medium |
| 3 | Questions, approval fidelity and MCP elicitation | Partial; MCP prompts are canceled | Correct blocking state, complete decisions, native connector forms | Medium–large |
| 4 | Goal + usage/context visibility | Partial: goal checked only at resume | Objective/status/budget, token usage, rate-limit reset information | Medium |
| 5 | Rename, pin, archive, restore | Missing controls; archives can be read | Familiar conversation management, including restore inside Diorama | Small–medium |
| 6 | Long-history pagination + message search | Partial: whole-thread reads and metadata search | Load older turns on demand; find and jump to message matches | Medium |
| 7 | Plan mode and capability-aware settings | Partial: model/effort and permission presets | Plan/work selector, advertised speed tiers and named permission profiles | Medium |
| 8 | Skills/apps/MCP discovery | Missing native integration UI | Skill/connector picker, connection health and OAuth recovery | Medium–large |
| 9 | Fork from a turn + code review | Missing actions; review events render generically | Branch an approach; review working changes or a branch | Medium |
| 10 | Durable prompt queue | Missing | Queue, edit, reorder and cancel next messages independently of steering | Medium–large |
| 11 | Rich tool results + worker inspector | Partial: mostly raw JSON | Command result cards, sources, generated-image previews, linked workers | Medium |
| 12 | Native goal controls | Missing | Explicit create/pause/resume/clear with budget and lifecycle feedback | Medium–large |

### 1. Mid-turn steering

Use `turn/steer` with `threadId`, `expectedTurnId`, and `input`. The installed schema requires the expected active turn ID, which makes races detectable. Preserve the draft if the turn finishes before the steer is accepted; do not silently submit a new turn or retry an uncertain delivery. Keep model/permission changes out of a basic steer request.

Today `ExecutionController.send` rejects active tasks and `ConversationComposer` disables Send while active. This is one of the most visible differences between a conversation viewer and a fully interactive agent client. Evidence: [send guard](../Sources/DioramaCore/ExecutionController.swift#L181), [composer](../Sources/DioramaApp/ExecutionViews.swift#L308).

### 2. Native plan and changes inspector

Handle `turn/plan/updated` and `turn/diff/updated`. The former supplies ordered steps and `pending`/`inProgress`/`completed` states; the latter supplies the latest aggregated unified diff. Add `item/fileChange/patchUpdated` where incremental file-level patches improve the UI. Store this state by thread and turn, rather than guessing it from assistant prose.

Diorama currently shows plan text as an assistant message and file changes as raw tool data. The event switch drops the structured notifications. A native inspector remains useful even when the agent has not updated its HTML page. Keep HTML for explanations and diagrams; native events should remain authoritative for execution state. A turn ending must not automatically mark every plan step or the overall goal complete.

Evidence: [event switch](../Sources/DioramaCore/ExecutionController.swift#L412), [history item mapping](../Sources/DioramaCore/AppServerHistory.swift#L174). Schema: `TurnPlanUpdatedNotification`, `TurnDiffUpdatedNotification`.

### 3. Complete the existing question/approval path

This includes correctness improvements, not just new UI:

- `ToolRequestUserInputParams.isBlocking` is ignored. Every question sets the task phase to “Waiting for input.” Respect nonblocking questions and keep request presence separate from whether execution is paused.
- `availableDecisions` can contain structured command/network policy amendments. `ExecutionRequest.decisions` keeps only four string choices, and `answer` requires a string. Add typed decision support with the exact proposed rule and persistence scope visible before submission; retain ordinary accept/decline actions where offered.
- `mcpServer/elicitation/request` is currently answered with `cancel`. Add schema-backed form and URL flows, with accept/decline/cancel. The request's turn ID can be null, so do not require it to behave exactly like a turn-scoped approval.
- Handle `item/autoApprovalReview/started`, `item/autoApprovalReview/completed`, and `autoApprovalReview/strictReviewRequired` so “Approve for me” has understandable state. Do not automatically invoke `thread/approveGuardianDeniedAction`; any override needs an explicit product design and user action.

Evidence: [decision filtering](../Sources/DioramaCore/ExecutionController.swift#L73), [answer validation](../Sources/DioramaCore/ExecutionController.swift#L292), [cancellation and phase handling](../Sources/DioramaCore/ExecutionController.swift#L377), [request UI](../Sources/DioramaApp/ExecutionViews.swift#L90). Schema: `ToolRequestUserInputParams`, `CommandExecutionApprovalDecision`, `McpServerElicitationRequestParams`.

### 4. Goal, usage, account and context visibility

Use the existing `thread/goal/get` result in the UI, plus `thread/goal/updated` and `thread/goal/cleared`. Goals expose objective, status, tokens used, optional token budget and elapsed time. The status enum distinguishes active, paused, blocked, usage-limited, budget-limited and complete.

Add `thread/tokenUsage/updated`, `account/read`, `account/rateLimits/read`, and their relevant update events. Offer `thread/compact/start` once context visibility makes its purpose clear. Show tokens and actual supplied limits; do not infer dollar billing from token counts. Context-window utilization is distinct from a task's token budget.

Global account/warning events need routing **before** the controller's attached-thread guard. At present events without an attached thread fall through that guard. Also surface `warning`, `configWarning`, `deprecationNotice`, `model/rerouted`, and `thread/settings/updated` where relevant, rather than leaving stale settings or dropping explanations.

Evidence: [goal gate](../Sources/DioramaCore/ExecutionController.swift#L260), [event routing](../Sources/DioramaCore/ExecutionController.swift#L407). Goal controls themselves come later: setting an active goal can cause continued work and must not be an incidental side effect of browsing history.

### 5–6. Conversation management and scalable history

Add `thread/name/set`, local pin preferences, `thread/archive`, and `thread/unarchive`. Restore is especially useful because Diorama currently tells users to restore elsewhere before continuing. Preserve writer-conflict rules. Archive can affect spawned descendants, so describe its actual scope.

Add `thread/turns/list` and `thread/items/list` behind compatibility checks, using cursors and progressive loading. Current history requests hydrate all turns before applying display limits; increasing the visible limit alone does not fix transport/parse costs. Keep the existing read/local fallback for older or unsupported storage.

For search, the experimental `thread/search` and `thread/searchOccurrences` offer server-backed capabilities beyond title/path/ID filtering. The latter searches visible user and final assistant messages within a paginated thread; label those limits instead of promising tool-output search. Search both archive states intentionally.

Evidence: [full history read](../Sources/DioramaCore/AppServerHistory.swift#L263), [metadata-only search](../Sources/DioramaApp/DioramaApp.swift#L117), [archive resume rejection](../Sources/DioramaCore/ExecutionController.swift#L226). These pagination/search features require storage/runtime verification before rollout.

### 7–8. Modes, settings and integrations

Use experimental `collaborationMode/list` and `turn/start.collaborationMode` for an actual Plan mode. Use `model/list` service-tier and input-modality metadata, `permissionProfile/list`, `configRequirements/read`, and optionally experimental `thread/settings/update` to expose supported choices and explain restrictions. Diorama currently retains only model name, reasoning efforts and defaults from the catalog. Do not hardcode advertised speed tiers or treat a tier as universally available.

Build a skill/app picker using `skills/list`, `app/list`/`app/installed`, plugin metadata and typed `skill`/`mention` inputs. Add `mcpServerStatus/list`, `mcpServer/oauth/login`, and `config/mcpServer/reload` for connector health. Pair this with elicitation support before claiming integrations work end to end. Native sign-in through `account/login/start`/cancel and login completion would improve onboarding after the read-only account panel.

Evidence: [catalog projection](../Sources/DioramaCore/ExecutionController.swift#L128), [input construction](../Sources/DioramaCore/ConversationAttachment.swift#L35), [permission presets](../Sources/DioramaCore/ExecutionController.swift#L11). Config/install mutations should be explicit settings actions, not a side effect of opening a picker.

### 9–12. Branching, reviews, queues, rich results and goals

- **Fork/review:** `thread/fork` supports branching history through or before a turn; `review/start` supports inline or detached review. Preserve original-thread identity and show the relationship. Check active-goal continuation semantics before forking. Defer destructive history editing: `thread/revert` changes conversation history, **not files**; `thread/rollback` is deprecated.
- **Queue:** experimental `thread/queue/add`, `list`, `update`, `delete`, `reorder`, `start`, plus `thread/queue/changed`. Keep “steer now” distinct from “run next.” Refresh the queue on notification and test restart, duplication and cancellation semantics before presenting it as durable in Diorama.
- **Rich results:** render typed `commandExecution`, `fileChange`, `webSearch`, `imageGeneration`, `mcpToolCall` and collaboration items. Include exit code/duration, diff navigation, source links, generated-image previews and linked worker states. Consume `item/mcpToolCall/progress` and terminal interaction events. Local image viewing and basic worker association already exist; build on them.
- **Goals:** add explicit `thread/goal/set` and `clear`, including pause/resume statuses. A stopped turn, a paused goal and a completed goal are separate conditions. Test whether Stop should also pause an active goal before enabling goal-driven automatic continuation.

Evidence: [raw live item rendering](../Sources/DioramaCore/ExecutionController.swift#L432), [worker attachment](../Sources/DioramaCore/ExecutionController.swift#L371), [existing image support](../Sources/DioramaCore/TranscriptImage.swift), and the installed parameter/item schemas.

## Defer or deliberately omit

| Surface | Recommendation and reason |
| --- | --- |
| Experimental `project/*` and thread sections | Useful later for Diorama-owned organization. **Do not promise Desktop sidebar sync.** Prior probes established persisted App Server membership but not equivalent Desktop grouping; see [project investigation](../PROJECT_DISCOVERY.md). Keep cwd-based grouping as the default for now. |
| `item/tool/call` / dynamic client tools | Defer generic execution. These are host callbacks; arbitrary Desktop tools are not inherited by Diorama. A narrowly registered Diorama canvas tool could be a separate future feature with its own contract. |
| Remote control, environments and WebSocket transport | Defer until remote execution is a product requirement. They introduce connection identity, reconnection and process-lifetime work; a transport change alone does not solve Desktop writer ownership or project grouping. |
| `thread/realtime/*`, audio inputs | Larger voice feature, with capture/playback and lifecycle work. No current evidence that this outranks text workflow gaps. |
| `command/exec*`, `process/*`, filesystem methods | Optional integrated terminal/remote file browser. Do not conflate sandboxed commands with unsandboxed process/shell APIs. Existing native local files and agent commands already cover much of the current scope. |
| Delete, memory reset, raw item injection, broad config mutation | No immediate user-facing need. Avoid broad administrative controls merely to increase endpoint coverage. |
| Attestation/external token refresh | Host-specific authentication responsibilities, not missing generic UI features. Implement only if Diorama adopts those auth modes. |
| Windows sandbox methods | Not applicable to this macOS app. |
| Reasoning records and streams | Preserve the current deliberate exclusion. They are not a necessary parity feature. |
| Test-only and deprecated methods | Exclude from the product roadmap. |

## Implementation batches and acceptance evidence

1. **Interaction and state correctness:** steering, nonblocking questions, typed plan/diff state, global warnings/settings routing. Verify a correction during an active turn, a steer/completion race, nonblocking questions, interleaved threads, stale events and reconnect behavior.
2. **Visibility and organization:** goal/usage/account panel, rename/pin/archive/restore, paginated history/search. Verify large histories, cursors, fallback, archive scope, absent limits, and turn-vs-goal distinctions.
3. **Workflow breadth:** Plan mode, advertised settings, skills/connectors with elicitation, fork/review, rich results. Verify schema variants, login cancellation, exact offered approval decisions, source provenance and unsupported servers.
4. **Persistent automation:** prompt queue and goal controls. Verify restart, uncertain delivery, queue ordering, cancellation, and automatic continuation before exposing them broadly.

First add narrow typed models for these payloads and retain bounded raw details for forward compatibility. Extend the existing transport allowlist per feature, rather than allowing arbitrary methods. Route global, thread, turn and request events separately. Generate a small versioned capability fixture in CI; local schema presence and `experimentalFeature/list` are useful evidence but are not universal proof that a method will succeed for every account/storage backend.

The audit goal is complete. Implementation remains proposed; no feature batch has been started.

## UX design companion

[UX_OPTIONS.md](UX_OPTIONS.md) expands the roadmap into 11 user-facing priorities, each with three illustrated experiences in the live HTML view. Goal controls are combined with goal/usage visibility. Plan mode, skills/connectors, branching/code review, prompt queues and rich tool results are explicit priorities. These are design proposals, not implemented features.
