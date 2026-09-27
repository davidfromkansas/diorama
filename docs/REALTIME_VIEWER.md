# External task observation

Diorama can observe local Codex and Claude Code conversations without resuming them or owning their execution. Open the same project folder; matching worktrees are associated through Git metadata. Claude Desktop support means the local Code tab, not Chat, Cowork, SSH, or cloud tasks.

**Latest verification (September 26, 2026):** Claude CLI cancellation, source-process restart/recovery, and source-only approval resolution now pass through the real passive observer. A cancellation parsing bug was fixed and its scene animation regression passes. Paired screen latency and the remaining Desktop interruption/recovery scenarios are still **Not verified** because native input/capture failed. See the final verification section below; neither Claude client is fully certified yet.

## Update path

Filesystem notifications use a 50 ms delivery latency and a 50 ms bounded coalescing window. Selected-session reads bypass full discovery and Codex App Server history requests. File I/O reads only appended bytes after bootstrap, keeps incomplete lines until complete, and resets on replacement/truncation. Conversation formatting reparses the bounded retained tail when it changes; structured activity is reduced incrementally. Unchanged files reuse their transcript. Cursor data is capped at 64 MiB across up to 24 recently observed sessions, with a 16 MiB per-file window.

Changed JSONL files receive targeted metadata discovery. The full scan still reconciles archives, Desktop metadata and missed notifications every 15 seconds. The selected conversation has an independent two-second fallback even in the background, and foreground activation requests an immediate refresh. Notifications and fallback reads share a single selected-read gate. Previous selections and paused/cancelled work cannot overwrite the visible conversation.

The external snapshot includes source modification time, successful-read time, transcript, activity, structured records, and errors. Reading uses no execution transport. Previously readable content remains visible if a source disappears. Pausing stops filesystem subscriptions; resuming reconciles before claiming recent work.

## Meaning of the scene

- **Live:** existing attached execution evidence. External file observation alone never earns this label.
- **Recently observed:** source activity within the preceding 30 seconds. Working agents may animate, including externally started tasks and their discovered subagents.
- **Last known:** older evidence or paused observation. No working animation; silence is not completion.
- **Unavailable:** the observer cannot read the source. Last readable conversation remains available.

A visible-scene clock expires freshness without requiring another event. Re-reading a file does not renew source timestamps. Untimestamped historical records do not become recent merely because they were imported. Claude child files sharing the parent's session ID have distinct roster identities. Terminal and attention states use provider evidence; stale tool events belonging to an earlier known turn cannot revive the current turn.

Conversation visibility does not require hooks. Hooks improve lifecycle and approval/input coverage where supported. Existing Connections setup previews remain the configuration path. No new hook configuration is silently installed by opening a project.

## Acceptance targets

Targets remain: evidence to visible UI p95 <= 500 ms / maximum 1 s; source-visible event to UI p95 <= 1 s / maximum 2 s when evidence is exposed promptly; new session/subagent discovery p95 <= 1 s / maximum 2 s; missed-notification recovery <= 3 s; foreground recovery <= 1 s when already observed or <= 3 s after reconciliation.

These are requirements, not guarantees established by the current measurements. Model-update timings do not measure rendered pixels or the source client's visible update. Source buffering and message-level transcript persistence must be reported separately; token streaming is not synthesized.

## Verification on September 26, 2026

Installed clients inspected: Codex CLI 0.153.4, Claude Code CLI 2.1.282, Claude Desktop 2.9939.2, Codex desktop bundle 26.917.62051.

| Client | Evidence obtained | Remaining acceptance work |
| --- | --- | --- |
| Codex CLI | **Degraded by provider.** Three bounded turns completed; native working state verified. A further timed turn delivered 35 transcript entries in one filesystem notification, after substantial buffering. | Streaming requirement fails for this file-only path. Pixel timing, approval/input, cancellation, restart, and worktree matrix remain unverified. |
| Claude Code CLI | Three bounded turns completed; 73 source-output events. Native search showed Working during a follow-up. A 90-second probe received 37 new entries across 30 notifications: evidence-to-model p95 31.0 ms / maximum 32.2 ms; source-timestamp-to-model p95 726.3 ms / maximum 742.2 ms. Zero execution requests. | Complete native lifecycle and pixel-timing matrix; source-client label remains unknown without explicit CLI origin evidence. |
| Claude Code Desktop | Three turns completed. Native Diorama followed tool/progress messages, remained view-only, added a second desk for a real subagent, and showed that child Done while the main agent worked. | Full >=30-sample pixel timing, approval/input, cancellation, restart, and worktree matrix. |
| Codex Desktop | Existing read-only history/discovery integration is covered by prior probes and regression tests. | This run's native interaction was blocked: Computer rejects access to `com.openai.codex` for safety reasons. No bypass attempted. Full live acceptance is **Not verified**. |

A real Codex CLI 90-second probe received 35 new entries in one notification: evidence-to-model p95/max 111.3 ms, but source-timestamp-to-model p95 53,952.7 ms and maximum 58,651.7 ms. This is a **degraded real-time** result: prompt processing continued in the source client while the saved transcript withheld updates. Diorama now explicitly warns that Codex transcript updates may be buffered. The installed protocol schema exposed no separate thread subscription; the [official App Server documentation](https://developers.openai.com/codex/app-server/) describes `thread/read` as reading stored history without resuming or subscribing. We did not use `thread/resume` to circumvent the passive-viewing requirement. Hooks can improve activity coverage but do not establish streamed conversation delivery.

A real Claude Desktop 90-second read-only probe captured 20 new transcript entries: evidence-to-model p95/max 73.3 ms; source-timestamp-to-model p95/max 2822.4 ms. The latter includes delay before observation, but does not identify exactly when the source UI displayed each event. Do not report it as pixel latency or claim all targets passed.

The 30-update native filesystem fixture passed without polling; recorded runs ranged from p95 56–60 ms, with maximum 57–462 ms. These are fixture/model timings, not four-client end-to-end acceptance.

The final Swift suite passed 310 tests after fixing a reproducible large-pipe-response timeout. The transport now searches newline bytes without a generic per-byte collection scan and drains ongoing bursts promptly while retaining the idle polling interval. Five Claude bridge tests passed. Subsequent targeted viewer tests cover stale-turn suppression and foreground/background refresh wiring.

See `artifacts/realtime-viewer/verification.json` and native screenshots. Full four-client real-time certification remains incomplete; unverified scenarios above are not inferred from fixture coverage.

## Repeating the checks

Run offline coverage:

```sh
swift test --no-parallel
node --test helpers/claude/bridge.test.mjs
```

For the observer latency probe, start a designated conversation in its source client first. Then run:

```sh
DIORAMA_VIEWER_PROBE_SESSION=<native-session-id> \
DIORAMA_VIEWER_PROBE_SECONDS=90 \
DIORAMA_VIEWER_PROBE_OUTPUT=/tmp/viewer-latency.json \
swift test --filter LiveExternalViewerProbe
```

Wait for `/tmp/viewer-latency.json.ready` to exist (test stdout may be buffered), then send bounded follow-ups from the source client. The probe does not send prompts, attach execution, or retain conversation bodies in its report. It records file-modification-to-model and source-timestamp-to-model timings, notification count, and explicit false flags for unmeasured pixel/source-visible timing. A quiet run fails rather than claiming success.

Complete acceptance requires at least 30 observable updates over three turns per client, with source and Diorama screen recording/timestamps, followed by cancellation, attention, background/foreground, restart and worktree checks. Classify each scenario Passed, Degraded by provider, Failed, or Not verified. Keep provider delay distinct from observer delay and rerun each failing scenario after its fix.

Initial local session discovery is published before the richer history scan finishes, so slow App Server discovery does not keep locally readable conversations out of the project picker. Selected-session observation runs independently of both scans.

## Packaged delivery

`dist/Diorama-Realtime.app` contains the final debug build, bundled USDZ resources, and Claude helper. Deep/strict code-signature verification passed. Earlier `/tmp` packaged builds were launched independently of the checkout and inspected. The final build’s native launch attempt was blocked by the Mac being locked; Computer could not unlock it. Final-build visual validation remains **Not verified**, as do the uncompleted acceptance scenarios listed above. Unlocking the Mac is necessary to finish these native checks.

## Follow-up verification — September 26, 2026

The Claude-first follow-up added per-event timing records, independently sampled transcript readability, and explicit null fields for unmeasured source/display presentation times. IDs are hashed; only designated `VIEWER_V2_…` test markers are retained. Samples are capped at 2,000 and readability records at 4,000. Notification processing uses one active reader plus one pending notification timestamp, avoiding an unbounded task queue. The independent sampler polls every 20 ms for measurement only; the product observer remains event-driven.

Each client completed three new bounded turns and produced **51 observed entries**. Existing user hooks were configured during these runs; they must not be described as hook-free source runs. A separate real CLI worktree check disabled hook reads in the observer and successfully verified discovery, history, an intentional tool failure, and completion.

| Measurement | Claude CLI | Claude Code Desktop |
| --- | --- | --- |
| Notifications / new entries | 48 / 51 | 42 / 51 |
| Notification receipt → model p95 / max | 28.8 / 31.0 ms | 54.9 / 67.0 ms |
| Estimated readable-evidence → model, conservative sampled endpoint p95 / max | 56.2 / 101.1 ms | 99.2 / 108.9 ms |
| Source timestamp → model p95 / max | 868.8 / 48,397.0 ms | 2,125.4 / 2,340.6 ms |
| Observer execution requests | 0 | 0 |
| Source-visible / rendered-pixel latency | Not verified | Not verified |

Readability is sampled, not a kernel timestamp for the first readable byte. The full intervals and file-mtime proxy aggregates are retained in `artifacts/realtime-viewer/claude-*-v2-timing.json`. The follow-up sampler now timestamps the beginning of each metadata check so writes during a check cannot advance its lower bound. Existing measurements have sampling uncertainty and are not pixel acceptance measurements.

The Desktop delay is predominantly **before transcript readability**: the slowest stamped entry was already roughly 2.3 seconds old when the sampler found it. This explains where the previous 2.8-second result arose but does not establish when Claude first displayed the message. CLI turn C also contained an outlier with a source timestamp about 48 seconds before readable evidence. That turn completed successfully in about 67 seconds. We cannot distinguish generation/retry delay from source-visible buffering using those timestamps alone; it remains an explicit limitation, not a discarded sample.

### Fixes found and rerun

- Separate parent/subagent reads previously evicted each other's activity cursors. A Claude parent could lose its working state once its start record fell outside the 512 KiB bootstrap tail. Cursors now remain bounded across separate reads; the regression preserves the original lifecycle event.
- Transcript `AskUserQuestion` now produces Waiting for input without requiring hooks, and its matched result clears that state. Generic permission notifications no longer override a specific pending question; explicit terminal/new-turn evidence clears unscoped old attention requests.
- Successful synchronization time is retained separately from a failed read attempt. Missing files retain the last readable history and the last successful synchronization time.
- Sampling the standalone app found repeated whole-buffer newline searches in read-only App Server history responses. The reader now scans only new bytes and reuses its read buffer. A 4 MiB response regression passes. Old temporary verification apps were closed; the installed app was not touched. A post-fix CPU snapshot was 11.9%, versus approximately 95% for the superseded verification copies; this is diagnostic evidence, not a controlled energy benchmark.
- Long-history appends over an approximately 7 MiB fixture took at most 157 ms in recorded runs. The targeted native-filesystem fixture delivered 30 updates with p95 around 60 ms. Pause/resume with a 100-message burst and a parent with twenty child agents also passed. Tail formatting remains bounded rather than fully incremental because the measured formatter stayed within its observer budget.

### Acceptance matrix after this pass

| Scenario | Claude CLI | Claude Code Desktop |
| --- | --- | --- |
| Three successive turns, ≥30 model-correlated entries | Passed (51) | Passed (51); native latest history inspected |
| Native pixel/source-visible latency | Not verified | Not verified |
| Real subagent lifecycle | Not verified in this follow-up | Prior native two-desk check passed; no new latency certification |
| Input request and source-only resolution | Hook-free regression passed; live UI not verified | Source question and source answer observed; viewer reached finished; corrected label covered by regression |
| Approval requiring a grant | Not verified | Not verified; generic permission notification was a question, not an authorization test |
| Tool failure and completion | Passed, real disposable worktree with observer hook reads disabled | Completion passed; task-level failure not verified |
| Cancellation | Not verified | Not verified: source harness blocked the foreground sleep before it ran; no bypass attempted |
| CLI process restart between turns | Passed for history continuity across three separate invocations | Source Desktop restart not verified |
| Diorama restart / background / foreground | Automated coverage only; timed live recovery not verified | Standalone relaunch restored selected history; timed recovery during work not verified |
| Worktree association and targeted discovery | Passed through real read-only model probe | Native worktree flow not verified |
| Custom-root live workflow | Not verified | Not verified |
| Pause/resume, freshness expiry, missing source, burst, stable twenty-agent IDs | Passed in automated tests | Shared automated path passed; native timings not verified |
| Hooks absent/present setup preview/apply comparison | Observer-without-hooks worktree check passed; complete setup matrix not verified | Existing hooks present; hook-free native run and setup matrix not verified |
| Final narrow/wide, keyboard, reduced-motion native matrix | Not verified | Wide designated conversation inspected; remaining matrix not verified |

Native inspection saved `desktop-v2-three-turns.png` with unrelated project titles hidden. Computer intermittently returned stale handles, `elementHasNoFrame`, `noWindowsAvailable`, and a ScreenCaptureKit capture failure. These captures cannot establish paired sub-second screen timing. The source answer later arrived, and the standalone viewer visibly showed the answer and completed turn. The earlier locked-Mac launch blocker is cleared: the follow-up standalone builds launched outside the checkout.

**Neither Claude client has full real-time certification yet.** The remaining gates are paired source/viewer presentation measurements, the unverified live lifecycle/recovery/configuration rows above, and final native layout checks. Codex CLI retains its previously documented degraded file-stream result; Codex Desktop still requires user-operated source interactions because Computer access is prohibited. No execution attachment or security-boundary workaround was added.

To repeat hook-free observation, set `DIORAMA_VIEWER_PROBE_IGNORE_HOOKS=1` alongside the existing timing probe variables. This disables hook reads by the observer, not the source client's hook configuration. To repeat the real worktree check, set `DIORAMA_WORKTREE_PROBE_SESSION` to the designated session and `DIORAMA_WORKTREE_PROBE_PROJECT` to its main checkout, then run `swift test --filter LiveExternalViewerProbe`. Neither probe submits prompts or resolves approvals.

Final follow-up validation: **317 Swift tests in 80 suites passed**, plus **5 Claude helper tests**. The targeted live worktree run passed separately. An earlier full-suite startup fixture timed out once while obsolete high-CPU test apps were running; targeted reruns and both subsequent complete suites passed.

The final follow-up package was copied to `dist/Diorama-Realtime.app`, passed deep/strict code-signature verification, and contains all three USDZ assets. The identical standalone `/tmp/diorama-viewer-final/Diorama.app` launched successfully after packaging. Full layout and presentation-latency certification remains pending.

## Three-priority follow-up — September 26, 2026, 14:10–14:20 UTC

### 1. Paired presentation measurements: Not verified

Attempted to arrange the designated Claude Desktop conversation beside the standalone viewer and prepare a new Screen Studio recording. Diorama's native window controls repeatedly returned stale element IDs, including after reconnecting. Its screenshot was unavailable. Claude prompt paste later timed out waiting for the application to read the clipboard; a direct accessibility field update also left the prompt empty. No Desktop test prompt was submitted in this pass, and no paired recording was captured. The existing Screen Studio project was not edited. User assistance was requested to arrange the two designated windows and start their recording.

The earlier 48.4-second CLI source-timestamp outlier remains unresolved as a **source-visible** measurement: the stored timestamp predates readable evidence, but neither it nor model timing establishes when pixels appeared. No samples were discarded or relabeled as a pass. The Desktop pre-persistence delay is likewise separate from Diorama's measured observer/model processing.

### 2. Real CLI interruption and recovery: Passed at observer level

Claude Code CLI 2.1.282 ran a disposable read-only task with successive README reads. The test driver sent SIGINT to its own source CLI process after the first Bash tool-start event. Claude persisted a rejected tool result followed by the exact synthetic user message `[Request interrupted by user for tool use]`. Its stream reported `error_during_execution`, despite process exit code zero; exit code alone is therefore not a completion signal.

The live read-only probe verified **Interrupted** with hook reads disabled. A separate source CLI invocation then resumed that same disposable conversation, read README once, and returned `VIEWER_V3_RECOVERED`. A fresh passive observer verified the preserved cancellation history and the new **Finished** state. Execution/resume occurred only in the source CLI test driver, never through Diorama observation.

A separate interactive CLI scenario used normal permission prompts and disabled browser integration. It requested a single write to `approval-check.txt` inside the disposable project. Before granting it, the live observer verified **Awaiting approval** using existing hooks. A transcript-only read remained **Working**, demonstrating the actual coverage gap without hooks. The one-time **Yes** choice was made in Claude CLI; no persistent permission was granted. The file contained the expected fixture line, Claude returned `VIEWER_V3_APPROVAL_DONE`, and the observer verified **Finished** with an empty attention queue.

These are real source-client and observer checks, not rendered Diorama pixel tests. Desktop cancellation/approval/restart, timed background/foreground recovery, and restart-during-work remain **Not verified**. Previously documented automated recovery checks remain valid but do not substitute for those native scenarios.

### 3. Fix, regression, rerun and package: Passed

The real cancellation reproduced a bug: the synthetic interruption record was treated as a new user prompt, keeping the external agent working. The Claude activity parser now recognizes the exact cancellation sentinels as **Interrupted**. It does not match ordinary prompts merely containing those phrases. Regression tests cover tool rejection, interruption, a subsequent turn, and immediate scene transition to **Stopped** without execution attachment.

The final full run passed **321 Swift tests in 80 suites** and **5 Claude helper tests**. The four opt-in real checks (cancelled transcript, recovered transcript, pending approval, resolved approval) passed separately. Evidence contains event types, identifiers and timestamps rather than conversation bodies in `artifacts/realtime-viewer/claude-cli-v3-lifecycle.json`.

Repeat the read-only lifecycle probes with `DIORAMA_CANCELLATION_PROBE_SESSION` and optionally `DIORAMA_CANCELLATION_PROBE_RECOVERED=1`, filtering `observesRealCancellationOrRecoveryWithoutHooks`. For approvals, use `DIORAMA_APPROVAL_PROBE_SESSION` and optionally `DIORAMA_APPROVAL_PROBE_RESOLVED=1`, filtering `observesRealApprovalWithoutResolvingIt`. Start and control the designated source conversation separately; these probes only read it.

The cancellation-fix package at `dist/Diorama-Realtime.app` passed deep/strict signature verification and contains all three USDZ assets. After closing only the two obsolete verification copies, `/tmp/diorama-viewer-v5/Diorama.app` launched outside the checkout, restored the selected Desktop conversation, and allowed a native screenshot (`packaged-v3-restored-history.png`). This cleared the viewer capture blocker. Claude Desktop input still failed with `noWindowsAvailable` after its window could be captured; paired recording and live Desktop lifecycle verification remain pending. No installed application was terminated.
