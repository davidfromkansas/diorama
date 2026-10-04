# Agent plan inspection

Agents expose **View plan** only for a proposed plan and **View tasks · completed/total** only for a task checklist. Both controls share a camera-facing row above the office label and are also available in the keyboard-accessible Agents list. Opening either preserves the camera and does not select, attach, resume, or run a conversation.

The modal is read-only. It preserves provider wording and statuses, displays only the selected artifact, and independently labels its timestamp and previous-turn state. Paused, unavailable, and truncated observation labels remain visible. Task progress counts only explicitly completed, nondeleted reported tasks; it does not verify outcomes or imply complete historical coverage. A completed, stopped, or failed turn clears neither artifact. Clearing a proposal leaves its checklist intact, and vice versa. Escape closes the modal before spatial navigation and restores focus to the invoking action. Existing office roster retention still determines which agents are on the floor; selecting an older conversation lets its agents be inspected again.

## Supported evidence

- Codex: `turn/plan/updated`, streamed/final plan items, saved `update_plan` calls, and explicit `<proposed_plan>` blocks in saved assistant messages.
- Claude: successful `TodoWrite`, correlated `TaskCreate`/`TaskUpdate` results, and plan text exposed by `ExitPlanMode` input or result.
- Missing plan content stays absent. Permission mode, reasoning text, and generic activity are not treated as plans or evidence that an agent is generating a plan.

Provider/session/agent ownership is preserved. Main agents use the current provider segment; subagents never fall back to the parent's plan. Failed task tool results do not update checklists. Final proposals replace drafts, and late draft deltas cannot overwrite final content.

## Observation and lifecycle

The visible office reads available sources in the background, two at a time, using the existing bounded history parser. Unchanged files are cached by modification time and size. An open modal's conversation is prioritized. Discovery pauses when hidden, inactive, or observation is paused; no new rendering loop is introduced.

Missing or truncated files retain previously observed plans. Explicit empty checklist/proposal records and deleted tasks update the displayed state. This is an in-memory inspection cache; existing provider journals and source histories remain authoritative after app restart.

## Verification

Core and rendering tests cover plan retention, ownership, merged providers, successful and failed tool results, streamed/final replacement, explicit clears, replay, previous turns, external changes, missing/truncated sources, narrow modal rendering, and 64 desks. Native preview images are written to `/tmp/diorama-plan-previews` by the rendering tests.

The local app was exercised against an existing external Codex conversation, including overhead and agent-list opening and Escape dismissal. Claude paths use deterministic recorded-event fixtures; no paid turns are started for verification. Full VoiceOver narration is not automated.
