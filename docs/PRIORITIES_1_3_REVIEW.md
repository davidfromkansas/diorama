# Priorities 1–3: implementation review

Implemented 2026-09-20. This is the agreed review checkpoint before priorities 4–11.

## Checklist

| Priority | Implementation | Joint review |
| --- | --- | --- |
| 1 · Mid-turn steering | Implemented; execution regression tests pass | Pending |
| 2 · Plans and changes | Implemented; routing/parser tests and native rendering pass | Pending |
| 3 · Questions and approvals | Implemented; request/validation tests and native rendering pass | Pending |
| 4–11 | Not started in this batch | Wait until this review |

### 1. Send a correction while work continues

The existing composer sends `turn/steer` with the captured `expectedTurnId`. Stop remains a separate control. Models and permissions stay fixed during an active turn. The draft and attachments clear only on confirmed acceptance. A stale turn never silently becomes a new turn; uncertain delivery requires history reconciliation before another send. Required questions and approvals temporarily disable steering; optional questions do not.

Review: during a disposable task, send a correction and confirm the same run incorporates it. Check that Stop is still available. If the turn finishes before Send, Diorama should preserve the draft and report that the turn changed.

### 2. Inspect the reported plan and last-turn changes

`turn/plan/updated` drives an expandable checklist with explicit Pending, In progress and Done states. Turn completion does not fabricate plan completion. `turn/diff/updated` drives a Changes summary and native right-side inspector with a file list and selectable unified diff. The view is labeled Last turn; it does not claim to show the entire Git working tree. Plan/diff state is kept for the most recent live turn and reset on the next send. It is not persisted or reconstructed for historical turns in this batch.

Review: ask for a small change with a plan, expand/collapse the checklist, open Changes, switch files, and inspect additions/deletions. Check that another conversation's events cannot replace this view. Code-review actions and forking remain priority 9.

### 3. Answer questions and review the actual approval scope

Optional questions say work continues. Required questions pause the relevant task. Multiple requests resolve independently; optional questions remain available until the server resolves them, even after a turn finishes. Structured command/network policy amendments preserve the exact offered payload and display persistent scope before the action. Existing per-turn permission grants remain per-turn. Automatic approval-review notices are visible; this UI never invokes a denied-action override.

MCP elicitation requests now display native forms for supported standard scalar and enum schemas, including booleans, numeric limits, formats, single choice, and multiple choice. Optional values may be omitted. Unsupported/custom schema shapes remain visible with decline/cancel actions; acceptance is disabled rather than inferred. URL requests expose a user-clicked HTTP(S) browser link and an explicit acknowledgement; simply opening the page does not send a response. A connector request can have no turn ID without inventing an active turn.

Review: inspect an optional question while work continues, then a required question. Inspect any persistent rule before selecting it. For a test connector, try an invalid numeric value, omit an optional field, and decline/cancel another request. No real-account connector flow was run automatically.

## Evidence

- Full Swift suite: **100 tests passed**, with **five opt-in live probes skipped** in the recorded run. After the final steering acknowledgement guard, all **26 execution tests passed** again.
- Native light/dark fixtures and a connector form were rendered and visually inspected. These are controlled view fixtures, not screenshots of an authenticated live task.
- [Light preview](../artifacts/priority-1-3/priorities-1-3-light.png), [dark preview](../artifacts/priority-1-3/priorities-1-3-dark.png), [connector form](../artifacts/priority-1-3/priority-3-connector.png).
- Release bundle: **Diorama 0.3.17 (build 20)** built successfully; deep/strict ad-hoc signature verification passed. Finder-added metadata was removed from the generated bundle before verification.

## Changed implementation

`ExecutionController.swift` and `ExecutionTransport.swift` handle routing, steering and request lifecycles. `ExecutionPresentation.swift` models plans, diffs, decisions and connector fields. `ExecutionWorkViews.swift`, `ExecutionViews.swift` and `DioramaApp.swift` present the native controls. Tests cover races, isolation, exact decision matching, form limits, and native rendering.

The running app has not been restarted. Reopen the rebuilt `dist/Diorama.app` after this turn and any active work finish to use the new binary. No provider account settings, connector configuration, or external approval rules were changed by this implementation work.
