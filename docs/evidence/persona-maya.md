# Maya — solo app developer

Test date: 2026-09-22. Real production QA bundle `/tmp/DioramaPersonaQA.app`, isolated data `/tmp/diorama-persona-home`, native computer use only for workflow actions. Fixture `/tmp/diorama-persona-maya`.

## Realistic tasks and outcome

1. Finish onboarding with connected account — passed: OpenAI and Anthropic both detected; default OpenAI.
2. Open local repository — imported and retained on restart. CUA timed out after NSOpenPanel dismissal; process sample reportedly showed normal idle event loop. This is an unresolved automation/accessibility observation, not an established app hang.
3. Start an isolated session and send a bounded edit with Enter — passed. Branch `codex/session-2123037c-2825-47ab-bb0f-40a4c328ba14`; worktree in isolated app data. Requested only index.html heading and paragraph, no network or commit.
4. Approve own file edit and review diff — edit succeeded; diff shows “Maya’s focus timer” heading and “One task at a time.” paragraph.
5. Inspect Activity and keyboard navigation — Timeline displays operations/outcomes/approval transition; Cmd-Option-2 switches to Steps. No structured steps reported for this simple request (honest empty state).
6. Preserve draft during Activity roundtrip — passed: `Maya draft: check page title next.` retained.
7. Stop task — passed: white square changed to send arrow, state Interrupted. No Maya task left running. Draft remains unsent.

## Findings

- **P1 approval details omit reviewable action:** File-change approval title “Allow these file changes?”; Review details modal displayed only “Review the requested changes and scope.”, Additional options, Allow for session, Cancel turn, and collapsed Raw request. No file or diff surfaced. Screenshot was emitted in CUA `Inspect permission review details readability` call. Raw request not captured before approval. Parent informed for extraction fix.
- **P1 transient clipping during approval:** At 1170×768 default window, awaiting approval screenshot showed only header and user bubble; composer and permission controls extended below bottom. AX Message click returned `cannotClickOffscreenElement`. Review details action remained accessible and approval could be completed; after approval same-sized window showed composer normally. Parent informed; needs reproduction/fix validation.
- **P2 generated canvas pollutes Changes:** Untracked `.diorama/canvases/<64hex>.html` selected by default, +7 lines of generated HTML/CSS/JS appeared before index.html edit. Parent reports targeted exclusion implemented; this agent has not retested rebuilt binary.
- **P3 activity section selection reset:** After choosing Steps and closing Activity, reopening through Activity button selected Timeline. Draft preserved. If per-session selection preservation is intended, avoid forcing Timeline on open.
- **Copy inconsistency:** Send tooltip says `Send message (⌘Return)` although plain Return successfully sends.

## Evidence boundaries

Native AX states and screenshots were emitted in the agent tool conversation. No screenshots saved to filesystem (CUA screenshot API emitted bytes only). Workflow had one real model request. After local edit and verification command completed, task remained Working for several minutes; explicitly stopped for bounded testing, so final agent completion was not assessed. No changes to user original app or real repository through test workflow.

## Fix retest (2026-09-22, second pass)

Verified in updated QA production bundle:
- Generated untracked canvas absent from Changes; only index.html listed and its diff preserved.
- Draft retained across restarts and Changes/Activity navigation.
- Steps section stays selected on Activity close/reopen.
- Send tooltip now correctly documents Return and Shift-Return.

Importer remains unsuccessful: native managed folder sheet allows navigation into `/tmp/diorama-persona-nina` and selection of that folder from `/tmp`, but Open stays disabled in both cases. Cancel succeeds and app remains responsive. Parent notified.

Submitted one further bounded Codex request in Maya's same session: change only index.html title to Maya Focus Timer with apply_patch. Submission confirmed Working and user message visible. Mac locked immediately afterward, before approval details could be inspected or task stopped. Parent notified; actual approval-layout retest pending unlock. Do not count it as passed.

## Final live permission retest after layout-loop fix

Fresh session branch `codex/session-ecd2af3c-038a-428d-ac0f-2d69951dda1a` completed normally. Actual request changed only index.html title Garden Club → Maya Timer. UI showed `Last turn finished` and final `Done`; no Maya task left running.

Verified with native computer use:
- Compact permission copy now names `1 file · index.html`.
- Review details now shows exact file path and unified +/- patch. Allow once applied that patch.
- Changes shows only index.html (+1 −1), matching approved title change.
- App remained responsive through execution, approval modal, diff navigation, and completion after local-scroll-state fix. Root separately sampled main-thread responsiveness; this agent did not measure memory.

Still reproduced: at 1170×768, the inline awaiting-approval state expands conversation content below the window, hiding approval card/composer visually; opening Review details via AX works. Screenshot emitted in `Verify approval and composer both fit viewport`. Parent/Leo investigating enclosing review-container sizing. This issue is not marked fixed by this retest.

## Final viewport acceptance — PASS

Latest QA with redundant-inspector fix, real session `codex/session-7e3ac209-6206-4e26-9fc4-7f9baf1a13dc`:
- At 1170×768 while actual Codex patch awaited approval, screenshot visibly showed the entire compact permission card, filename, Review details, Deny, Allow once, and composer simultaneously. Transcript correctly shrank and scrolled above it. Prior clipping no longer reproduced.
- Review details showed exact index.html diff Garden Club → Maya Final.
- Allow once applied patch; Changes showed only index.html +1 −1 with the expected title change.
- Task completed with final Done, Last turn finished, send arrow restored. No active Maya tasks remain.
- Screenshot emitted in CUA call `Verify final inline approval stays visible`.

This supersedes the earlier clipping-failure result for the latest tested build. Folder-import result remains separately unresolved in this persona report unless another agent retests its final fix.

## Source audit and deterministic regressions while desktop locked

Found and fixed new-project draft mode loss: Plan/Goal were view-only state while text/model persisted. Project draft now persists optional mode/goal fields, keeps toggles mutually exclusive, snapshots intent before async session creation, and clears it after successful send. Storage regression confirms Plan and Goal restoration and older saved projects without these fields still decode. This is source/test verified, not an additional live UI claim.

Added a controlled suspended-transport regression for goal refresh. Before root's split-await fix, the awaited nested dictionary assignment overwrote newer task phase, turn ID, transcript, and activity state (four deterministic failures). After fix both reentrancy regressions pass, including removal while awaiting without resurrecting the task. Combined targeted run: three tests passed, log `/tmp/diorama-workflow-reentrancy-after.log`; pre-fix evidence `/tmp/diorama-workflow-reentrancy-before.log`.
