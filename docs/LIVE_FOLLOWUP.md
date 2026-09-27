# Native verification follow-up — 2026-09-28

## Claude Code Desktop

The designated local session remains `e0cd3e9c-06e9-4c87-a734-e75964447741` (Disposable Diorama Desktop verification). Login and the working folder are available. Native accessibility navigation reports the existing conversation, but screen capture still shows Home. Paste times out, setValue/typeText leave the prompt empty, and screenshot-coordinate input fails with `noWindowsAvailable`. No new prompt submission is claimed. User-operated turn 2 was requested.

Classification: **Not verified — source control/capture blocker**. Do not interpret an inactive probe window as a successful live-latency run. No source access restriction was bypassed.

## Diorama native checks

- Pause changes the accessible status to Observation paused and exposes Resume observation. Resume returns to Observing and restores the Pause control. This verifies control/status behavior, not missed-event recovery timing.
- Existing Desktop Read/Write cards, usage, output reference and source disclosures remain present; the footer directs continuation to Claude Desktop.
- The disposable HTML file is missing following temporary-folder loss. Explicit Preview displays Preview unavailable with the missing-file explanation, verified in captured pixels.
- Escape dismisses that preview. The same conversation remains selected and the scroll value is unchanged (0.9265956011334503). Keyboard focus returns to the window; exact opening-control focus was not established.

These limited checks do not complete the three-turn live comparison, subagent/lifecycle matrix, or pixel-latency gate. PR #1 remains a draft. No implementation change was made during this follow-up.

The 180-second hook-free observer probe recorded zero notifications, zero samples and zero execution requests (`artifacts/live-followup/claude-desktop.json`). Its minimum-update assertion failed because the source prompt could not be submitted. This is a blocked verification attempt, not a measured latency failure or pass.

## User-operated turn 2 — 00:07 HKT

The user sent turn 2 in Claude Desktop. The saved source records contain six numbered assistant steps, a Write result for acceptance-desktop-2.html, and end_turn evidence at 2026-09-27T16:07:16Z. Diorama, still observing the same selected conversation, reported Working and subsequently Last turn finished. Its native accessibility view included the new user prompt, completed Write card, usage and final assistant response without reselecting or refreshing the session. The source prompt contained duplicated instruction text; only one execution of the six-step test was observed.

Explicit Preview opened an isolated HTML view exposing counter value 0 and an Increment button. Subsequent native control returned stale-element errors, so interactive increment and pixel presentation are not marked passed. Timing collection was not armed before this user submission; no turn-2 latency claim is made. The next timing probe is armed before requesting user-operated turn 3.

## Completed three-turn Desktop history — 01:02 HKT

The user-operated third turn completed. An independent Desktop-specific opt-in test passed through SessionLibrary and ExternalSessionObserver with hook reads disabled. All 18 Read calls and 3 Write calls have corresponding source results; all three final response markers and HTML output references are retained. Each output's correlated source records loaded successfully and the activity reducer reported finished. Unlike the CLI check, this Desktop check does not require CLI-specific cumulative cost-state metadata.

Classification: **Passed — three-turn saved-output coverage**. This is not the 30 correlated live-update/pixel-latency acceptance gate. The pre-armed 180-second probe ended before the user submitted turn 3 approximately 53 minutes later; its empty report remains a failed measurement attempt with no execution requests. Native scroll controls again failed or returned inconsistent positions, so this run does not claim a turn-3 pixel comparison. No further user prompt is required merely to confirm the saved-output result.

Evidence: `artifacts/live-followup/desktop-three-turns.log` and `desktop-three-turns-summary.json`. Remaining work includes reliably coordinated screen timing, lifecycle/recovery cases, and the independent Codex gate. PR #1 remains a draft.
