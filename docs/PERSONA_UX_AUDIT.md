# Diorama persona usability audit

Three independent agents tested the real Diorama app through computer use. Desktop access was sequential to avoid conflicting clicks. These are simulated personas, not human usability research.

## Final visual checks — 2026-09-22T21:59:28+08:00

The Mac was accessible. The current QA app completed the following real UI checks:

| Check | Result |
| --- | --- |
| Claude Sonnet planning turn | Passed: Return submitted, stop square displayed while working, VISUAL_PLAN_OK response completed, send arrow restored, no crash. |
| Activity inspection | Passed: Timeline reports completed turn, usage, configuration and rate-limit events. Plain assistant plan text correctly does not pretend to be a structured plan item. |
| Multiline composer | Passed: Shift-Return inserted a newline without sending. |
| Draft and mode retention | Passed: two-line session draft and Plan Mode survived project navigation; new-session Goal survived navigation and remained exclusive with Plan. |
| Native project picker | Passed with automation caveat: correct fixture folder, Open enabled, existing project selected without duplicate. Automation lost the window handle after closing picker; app activation restored access without process restart. |
| Narrow layout | Passed at761×893 using native half-screen sizing: controls wrap, composer visible, session list collapses, Changes provides Conversation return and readable local diff. Original size restored. |
| Accessibility | Control labels/roles verified through accessibility tree; Return/Shift-Return exercised. Spoken VoiceOver and exhaustive keyboard-only navigation were not tested. |

No source changes in this verification turn. Prior220 Swift and4 helper test results still apply. No publishing or replacement of the user's installed app. One minor observation remains: a fresh session briefly shows transcript/history unavailable before live content arrives; it resolves once history is loaded. No new blocking app failure reproduced.

## Latest status — remaining issues addressed

- **Workflow race fixed and reproduced:** a nested dictionary assignment held across an `await` overwrote newer task state. Four pre-fix assertions failed; post-fix state preservation and task-removal tests pass.
- **Claude startup cause isolated and fixed:** GUI launch inherited a stale `PWD`. The same minimal native probe timed out with inherited environment but initialized in about1.4s with the working directory corrected. Claude launches now set `PWD` to their actual folder and remove `OLDPWD`, preserving other settings and subscription credential filtering. Startup timeout copy now clearly says no message was sent.
- **Draft mode persistence fixed:** new-project Plan/Goal choices survive navigation/storage; legacy project files still decode.
- **Native Claude integration passes:** real Sonnet Plan response,231 layout updates,11 view recreations,final teardown,no crash; Working never reverted to Ready after send.
- **Full regression:**220 Swift tests in62 suites and4 helper tests pass. Production build and deep strict signature verification passed. QA copy has the same binary UUID5EC2F028-19CA-3470-ABAF-70A4B1583794.
- **Still unverified:** final manual Claude/picker/narrow-window/VoiceOver walkthrough. Computer use reports the Mac locked. Automated native integration is not being represented as manual acceptance.

The chronological notes below preserve earlier failures and investigations; this section supersedes their interim status.

## Personas and tasks

| Persona | Realistic workflow | Observed result |
| --- | --- | --- |
| Maya — solo developer | Import repository, create session, edit a page, approve changes, review diff, retain draft, stop work | Completed real Codex edits; worktree/diff, permission decisions, draft retention, Activity selection and Stop verified. |
| Leo — technical lead | Create two sessions, verify worktree isolation, switch drafts, inspect models, activity and linked PRs | Separate branches/files/drafts verified. Provider choices and session-scoped PR empty state verified. |
| Nina — product designer | Create project, add context, choose Claude, request a safe plan, inspect settings and mode controls | Project/context/reference feedback/mode exclusivity and Settings verified. Claude UI submission exposed a native crash; final retest pending. |

## Fixes

| Before | After | Why / evidence |
| --- | --- | --- |
| File-change approval was generic | Show exact filename and provider-reported diff in Review details | Maya verified live index.html approval, exact diff and successful Allow once. |
| Pending approval pushed composer below the project window | Project sessions no longer install a redundant native inspector | Native-window regression passes at520/600pt heights. Maya also verified the final release live at1170×768: all actions and composer visible, exact diff approved, task completed. |
| Generated canvas appeared in Changes | Ignore only generated untracked canvas artifacts; tracked/user files remain visible | Maya verified real Changes list. Git regression passes. |
| Activity reopened Timeline | Preserve selected section | Maya verified Steps reopening. |
| Tooltip described the wrong send shortcut | Return sends; Shift-Return adds a line | Live tooltip verified. |
| Saved/local Codex messages duplicated live items | Reconcile explicit turn/item identities | Regression passes; repeated text in distinct turns remains valid. Final live duplication check incomplete. |
| Transcript scrolling synchronously invalidated shared model during layout | Local scroll state with delayed persistence | Pre-fix sample showed sustained SwiftUI layout churn; rebuilt app stayed responsive through a complete edit. |
| Plan Mode reset across navigation/restart | Save mode with composer draft, including first project submission | Backward-compatible draft regression passes; live retest pending. |
| Restored connection error was hidden | Display saved task error beside detached composer | Source fixed; no silent execution restart added. |
| Settings copy clipped and briefly said Not connected while loading | Wrapped copy and Checking state | Nina verified both live. |
| Claude session presentation crashed | Workflow controls use a small presentation projection instead of retaining full execution snapshots | Two native SIGSEGV crash reports implicate workflow popover teardown. Mitigation built; release UI verification remains blocked and is not claimed complete. |

## Issues and limits

- Original native project picker imported Maya/Leo repositories, but later computer-use targeting became unreliable. Experimental sheet/importer versions left Open disabled and were reverted. Original picker remains; final retest pending.
- Native crash reports prove Nina’s first two Claude runs crashed; the earlier explanation that a deliberate QA restart interrupted them was incorrect. Reports: `~/Library/Logs/DiagnosticReports/DioramaPersonaQA-2026-09-22-124615.ips` and `DioramaPersonaQA-2026-09-22-135003.ips`.
- A separate real Claude Sonnet planning test through AgentExecutionTransport/ExecutionController completed in14.4s. It verifies the backend path, not the native UI crash fix.
- CUA intermittently lost window handles; after Settings, process sampling showed the main thread idle despite targeting timeouts. These tool failures are distinct from the confirmed app crash/layout bugs.
- Full narrow-window interaction and spoken VoiceOver walkthrough remain unverified. Rendering tests are not a substitute for those checks.

## Verification

- Latest full suite: **214 tests passed in59 suites**.
- Production release build and deep strict QA signature verification passed.
- Native-window approval test includes a long transcript and pending request, catching the issue missed by the initial standalone view test.
- Only isolated QA app/data and disposable projects were used. Original running Diorama and user project contents were not modified by persona actions.
- No commit, push, release or DMG publication performed.

## Evidence

- [Maya](evidence/persona-maya.md)
- [Leo](evidence/persona-leo.md)
- [Nina](evidence/persona-nina.md)
- QA app: `/tmp/DioramaPersonaQA.app`; data: `/tmp/diorama-persona-home`.
- Latest build: `/tmp/DioramaPersonaFixed.app`.

## Next action

After unlocking, complete one uninterrupted Claude planning run on the final build. The Codex approval-layout retest is complete. The audit goal remains incomplete until the Claude UI issue is resolved and verified.

Updated: 2026-09-22T13:57:45+08:00

Diagnostic update: a third release run and an Address Sanitizer run also crashed. The sanitizer trace identifies destruction of ExecutedTask retained by the workflow view. The intermediate reference-box approach was insufficient and replaced with a projection containing only ID/provider/phase/workflow fields. This remains unverified until a complete release UI run passes. Model selector now provides Refresh models and does not label missing catalog entries as proof of being logged out.

## Final status of this resumed turn

- Maya completed the final live approval layout acceptance and a normal Codex edit. No Maya task remains active.
- Claude presentation lifetime fixture passes in both debug and release; routed real Claude Sonnet planning probe passes in both debug (14.4s) and release (11.9s). These do not prove the native desktop crash is fixed.
- Verified fresh release retest could not reach submission because app-launched Claude initialization timed out. Both SDK and direct CLI paths reproduced the timeout. Direct helper initialization from the shell, including a minimal PATH, succeeded in1.7s. Tracing confirmed valid initialization JSON and a running reader; CLI sampling showed blocking file-open activity. Cause remains unknown; no claim that the lock caused it.
- Computer use explicitly reported the Mac locked again at the final inspection. This prevents completing the native UI retest.
- Fixed helper signal handling: close the SDK, destroy stdin, and allow its delayed child cleanup instead of immediate process.exit. A real initialize/terminate check confirmed helper exit0 and child stopped; four helper tests pass. Removed orphaned probes belonging only to the isolated QA home.
- Removed temporary transport instrumentation from source. Preserved diagnostic logs and crash reports; original user app untouched. Isolated QA process stopped.
- Some attempts used an auto-relaunched old QA process; they are excluded from final-build acceptance. Later deployment verified a fresh PID and matching binary UUID.
- No release/push/commit. Do not describe the Claude UI crash mitigation as production-verified.

## Remaining-issues investigation — resumed 2026-09-22

- Controlled workflow regression reproduced four lost updates: while `thread/goal/get` was awaiting, a later turn phase, turn ID, transcript notice, and structured activity were overwritten by an old task snapshot. Split provider await from nested dictionary mutation. Post-fix regression passes, including removal during the wait without resurrecting the task.
- New project drafts now persist Plan/Goal selection across navigation and storage, with mutually exclusive bindings and backward-compatible optional fields. Storage roundtrip and legacy decoding regression passes.
- Real Claude/native release-window probe passed after the state-race fix: 231 layout updates, eleven view recreations, completed Plan response and final teardown. Working never reverted to Ready after send. This is automated integration evidence, not a manual UI pass.
- Minimal Foundation-only GUI launch reproduced Claude initialization timeout outside Diorama. Identical shell launch succeeded; minimal inherited environment also made GUI launch succeed. Stale inherited PWD/OLDPWD values are isolated: removing those values makes GUI initialization succeed in about1.2s. The child environment is corrected to reflect its actual working folder; two environment regressions pass. macOS file-access checks were observed but are not established as the cause.
- Computer use still explicitly reports the Mac locked; visual checks remain pending. No security settings changed.

Final resumed-turn verification: latest QA deployment matched the clean production binary. Computer use again explicitly reported the Mac locked. Automated checks complete; final visual acceptance remains pending. Fresh local build: `/tmp/DioramaPersonaFixed.app`. No publication or user-app replacement performed.
