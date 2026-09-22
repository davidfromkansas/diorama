# Nina — product designer new to coding agents

## Persona and realistic tasks
Nina understands product design and familiar chat apps, but not Git worktrees or provider-specific controls. She wants safe planning before an agent changes files.

1. Open a local repository or create an unpublished project.
2. Add design instructions and a reference; recover from a missing reference.
3. Find account/model defaults without changing them.
4. Select Claude for a session, enable Plan Mode, send a concise planning prompt with Enter.
5. Understand Goal/Queue, inspect inherited context and activity, and navigate narrow layouts.

## Environment and scope
Real production app build in `/tmp/DioramaPersonaQA.app`, isolated app storage under `/tmp/diorama-persona-home`. Computer use via CUA only. Project created through UI: `Persona QA Nina`, under isolated home Documents/ChatGPT. No account/default changes, publishing, global settings, or source edits. One read-only planning prompt submitted; no duplicate retry.

## Observed results
| Task | Result | Evidence |
|---|---|---|
| Add project discoverability | Pass | Add menu clearly exposes Open project, Open GitHub project, New Project. |
| Open local project | Initially failed; fix needs final retest | First window-attached picker action silently returned without sheet. After parent fallback fix sheet appeared, but Open remained disabled for selected `/tmp/diorama-persona-nina` both inside folder and selected from `/tmp`. Parent later replaced implementation with managed importer; this latest replacement not retested by Nina. |
| New Project | Pass | Created Persona QA Nina with Publish to GitHub unchecked; selected project opens clean composer. |
| Instructions | Pass | Saved plain-language/accessibility design guidance; later session context sheet displays exact saved guidance and explains snapshot timing. |
| Missing reference recovery | Pass | Adding `docs/missing-design-brief.md` clearly shows `Not found in the current base revision`; Remove reference removes it. |
| Settings/account discovery | Pass with issues fixed by parent | Standard app Settings has default model and OpenAI/Anthropic connected/login affordances. Initial check briefly said Not connected; subscription text truncated in 520px window. Parent changed checking state and wrapping. Final visual retest pending. |
| Plan/Goal exclusivity | Pass | Enabling Goal turns Plan off; enabling Plan turns Goal off. Queue disabled before session; tooltip explains next-run behavior. |
| Model selection | Pass after automation recovery | Sonnet selected in model popover, confirmed composer screenshot `Sonnet Default`; global default untouched. |
| Enter submission | Partially passes | Creates Claude Code session, clears composer, user message appears in blue bubble. |
| Planning response/status | Fail, requires investigation | After minutes, no assistant response and no Stop control. Header `Claude Code · Last reported: Unknown · Observing`; Activity says no structured activity. Immediately after submit temporarily `Transcript unavailable`. Plan toggle reads off after creation although on before submission. No resend. |
| Inherited context | Pass | Project context → View this session’s context opens sheet with exact saved instructions and snapshot explanation. |
| Activity navigation | Pass | Activity opens full panel at current conversation-column width; Plan/Timeline empty states honest; Back to conversation works. |
| Narrow window | Not verified | CUA coordinate drag returns `noWindowsAvailable`; AX clicks work. Do not treat this as confirmed product layout defect. |

## Reproducible findings

### N1 — Opening a local project blocked (high)
Add → Open project initially no-ops when main window is not key. Following fallback fix, the native folder picker appears but selected folder's Open button stays disabled. AX URL `file:///private/tmp/diorama-persona-nina/`, blue selected Folder row in screenshot, no Go To overlay. Tried exact folder via Go To, parent directory plus typed selection, and direct AX row click. Escape cancels cleanly. Parent owns fixes; latest managed importer remains to verify.

### N2 — Settings copy truncation and false connection state (low/medium)
Settings displayed Not connected while Checking, then both Connected. Subscription explanation truncated visually to `Diorama does no…` though full AX text was available. Parent has fixed both; final UI retest pending.

### N3 — First Claude planning session appears abandoned (high)
Set Plan Mode on, choose Sonnet, submit with Return: `Persona QA Nina: Propose a concise three-point plan for a friendly landing page for a neighborhood pottery class. Follow the project design guidance. Do not use tools, edit files, use the network, or delegate. Reply with the plan only.`
Expected visible running/approval/error state followed by plan; actual user message only, Unknown·Observing, no Stop or error, empty activity. Session branch label `codex/…a8b98d26`. Parent notified immediately; backend diagnosis pending. Plan Mode visibly resets off; whether it reached backend is unverified.

## Automation caveats
Initial Mac lock prevented testing until manual unlock. CUA repeatedly returned noWindowsAvailable for coordinate actions and sometimes elementHasNoFrame for model options, despite AX interactions working. QA executable renamed uniquely and tool reset; model selection subsequently worked. These are not claimed app defects without independent reproduction. No manual VoiceOver or narrow-window completion claimed.

## End state
Nina project and one Claude session retained in isolated QA state. No visible active task/Stop control, but parent must inspect backend before restarting. Lease released for parent diagnosis and Maya retest. No real user data changed.

## Follow-up diagnosis — interrupted QA run, not reproduced transport defect
Read-only inspection on 2026-09-22 confirmed native Claude session `f8fc85a2-4b08-438b-b46d-478c0938cb08`:

- User prompt recorded at **04:46:08.709 UTC**.
- Native `plan_mode` attachment at that same timestamp (`reminderType: full`, `isSubAgent: false`) proves Plan Mode reached Claude correctly.
- Transcript last modified **04:46:10.628 UTC**; no assistant/result records.
- Current isolated QA app process PID 40538 started **04:46:12 UTC**, about three seconds after the prompt. Thus the process used to inspect the stalled session had restarted after submission.
- Restored activity journal has zero records/events and `lastKnown: true`. `ExecutionController` bookmark restoration sets disconnected state and does not persist workflow mode; the later off toggle is consistent with restoration.
- Parent's separately routed Claude planning live probe passed. This reduces support for a general Claude transport failure.

**Reclassification:** N3 is an interrupted QA execution with incomplete evidence about the exact termination mechanism, not a confirmed first-session Claude defect. Restart recovery still merits UX improvement: the conversation displayed Unknown / Observing instead of clearly explaining that the previous connection ended. No resumed execution was initiated during this investigation.

## Critical correction after fresh UI retest
A fresh Sonnet Plan session on the rebuilt QA app, with no requested app restart during the run, reproduced immediate disappearance and restored-disconnected state. macOS crash reports prove **both runs crashed**, rather than being interrupted by an intentional QA redeploy:

- `~/Library/Logs/DiagnosticReports/DioramaPersonaQA-2026-09-22-124615.ips`: captured 12:46:09 HKT, matching the original prompt.
- `~/Library/Logs/DiagnosticReports/DioramaPersonaQA-2026-09-22-135003.ips`: captured 13:50:01 HKT, fresh prompt branch suffix `9bec0a8a`.
- Both `EXC_BAD_ACCESS / SIGSEGV`, main thread, `_swift_release_dealloc` → app `objectdestroy.6Tm` → `destroy for PopoverConditionalStateProvider`.
- Faulting thread registers include `WorkflowControls` and `ExecutedTask` type metadata. Hypothesis: SwiftUI goal popover closure capturing the large workflow/task view value; this is a source hypothesis, not established root cause.

**N3 is a confirmed high-severity native UI crash on fresh Claude Plan submission**, despite the headless transport probe passing. Prior restart-only reclassification is superseded. Parent notified promptly and owns source fix. Fresh Plan toggle restoration now remains on, and the disconnected explanation is visible—those fixes are verified. No active Nina run remains after crash.

## Second fix retest
On the build replacing WorkflowControls' embedded task snapshot with a task ID, fresh Sonnet Plan submission initially succeeds visibly: Working header, Plan on, Stop task present (branch `7ea4fd12`). However the app then crashes before response completion. Latest crash `DioramaPersonaQA-2026-09-22-135714.ips`, captured13:57:11 HKT: `EXC_BREAKPOINT / SIGTRAP`, `__CFCheckCFInfoPACSignature` → `_CFRelease` → NSDictionary/NSArray deallocation → autorelease pool → Swift concurrency job. This means the first fix is insufficient; a broader memory/lifetime issue remains. Parent notified; no extra message submitted.

Settings visual retest passes: Checking state shown during lookup, both providers Connected, complete subscription/billing explanation wraps to two readable lines in native Settings window. Closing Settings caused CUA target timeout until parent activated app (process idle, no crash at that moment).

## Native live integration regression (Mac locked)
Added opt-in `Tests/DioramaRenderingTests/ClaudeLivePresentationTests.swift`. This combines the production SessionView in a native NSWindow/NSHostingView with a real routed Sonnet Plan turn, layouts during live events, repeated view teardown/recreation, and final native presentation destruction. It does not use computer automation or bring windows forward.

Release-mode run passed in **13.546 seconds**: **191** layout updates, **9** view recreations, completed assistant response beginning `NATIVE_PLAN_OK`, Plan Mode retained, final task/view teardown survived. Evidence `/tmp/diorama-claude-native-presentation.json`. Observed phase briefly Ready after send, then Working and finished; parent found an await-in-dictionary-writeback hazard in loadWorkflow and is adding a separate regression/fix. This test increases backend/native-view confidence but does not replace the still-needed successful manual Claude UI walkthrough.

## Post-race-fix acceptance
After splitting the awaited workflow request from dictionary mutation, the real native release test passed again in **17.952 seconds**, with **231 layout updates**, **11 view recreations**, Plan retained, and completed `NATIVE_PLAN_OK` response. The strengthened assertion that Ready must never reappear after awaited send passes: observed phases were only Working before completion. Final view/task destruction survived. This directly verifies the stale-state symptom is fixed in the live native integration; manual UI walkthrough remains separate.
