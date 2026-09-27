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

## Activity-triggered probe window

The observer probe now separates waiting from measurement. `DIORAMA_VIEWER_PROBE_WAIT_SECONDS` defaults to 7200 seconds (bounded to 5–43200); `DIORAMA_VIEWER_PROBE_SECONDS` still controls the full measurement interval, default 60 seconds (bounded to 5–900). The measurement clock starts on the first newly observed conversation entry after baseline loading, not on readiness or a filesystem notification. A later event does not extend the measurement window. The clock is monotonic.

The report includes the waiting limit, actual wait, and explicit measurement status. No-activity expiry is Not verified and continues failing the probe's nonempty-samples assertion. It must never be presented as a latency pass. `VIEWER_LIVE_PROBE_READY` means waiting; `VIEWER_LIVE_PROBE_MEASURING` means new activity started the measurement window. An unrelated new event in the selected session can start the window, so use only the designated disposable session.

Deterministic regressions cover a 53-minute delay followed by a full 180-second recording, repeated activity not extending the deadline, and a quiet source reaching its separate wait deadline. This is test-harness code only; the shipping app and execution transports are unchanged.

To run: set `DIORAMA_VIEWER_PROBE_SESSION`, `DIORAMA_VIEWER_PROBE_OUTPUT` to an existing evidence directory, `DIORAMA_VIEWER_PROBE_IGNORE_HOOKS=1`, and the desired wait/measurement durations, then run `swift test --no-parallel --filter LiveExternalViewerProbe/measuresDesignatedExternalSession`. Wait for READY before source interaction. Stop the process if cancelling a verification session; SwiftPM can hold its build lock while the test waits. Do not leave a quiet probe running as a substitute for coordinated testing.

This change only fixes test coordination. The probe records model timings, not screen presentation. Paired pixel capture and the remaining client/lifecycle checks are still required; the draft PR must not be marked ready based on these harness tests.

## Practical conversation fix — duplicated Claude usage cards

The designated Desktop transcript contained 46 usage-bearing records for 25 native assistant message IDs because Claude persists content blocks separately. Diorama emitted a usage card for every block. The normalizer now retains one usage card per session/agent/message identity, updates it with the latest reported values, and retains each source reference. It does not remove text or tool blocks, sum repeated measurements, or combine different agents. Records without a native message identity stay separate.

Validation: 9 Claude output tests passed; 5 additional real-history/source/rendering checks passed, including the designated three-turn Desktop output acceptance. Narrow/wide card fixtures rendered successfully. No new latency instrumentation or source prompts were needed. This practical fix does not alter the outstanding live-timing classification.
