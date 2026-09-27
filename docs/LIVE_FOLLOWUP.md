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
