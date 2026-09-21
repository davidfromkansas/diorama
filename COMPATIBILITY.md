## Direct continuation — 0.3.5

Successful resume/reconnect now opens the composer without the Diorama-only settings confirmation. Effective settings remain inspectable. No approval policy or permission settings were changed; provider approval requests still require an explicit response. Regression checks verify resume sends no prompt and that an explicit Send works immediately afterward. Twelve execution/rendering tests passed; live probes were not repeated for this UI change. Earlier settings-review evidence below describes historical versions.

# Codex / Claude observation feasibility

## Installed UI continuation check — September 19, 2026

Clicked **Continue here** in the installed Diorama window for the designated test conversation while Desktop held its writer. The UI displayed the provider-backed in-use explanation and **Retry**. The user then reported completing the manual Desktop quit → Diorama Retry/settings review/send → Diorama quit → Desktop reopen steps. Read-only inspection of the designated transcript independently confirmed the exact UI-test prompt, response `DESKTOP-CEDAR-8426 UI_VERIFIED`, and matching completion for turn `01a0b6e3-ff9c-7490-880c-0753b0ba94d7` at `2026-09-18T23:39:53.690Z`. Thus the manual UI flow is verified with transcript corroboration; the successful UI clicks were user-operated, not observed through automation. A new Desktop return message was not requested in this UI test; that direction was verified separately below. Evidence: `evidence/imported-resume-ui-roundtrip.json`.

## Actual Desktop exit and native resume — verified September 19, 2026

The designated conversation `01a0b6cc-6ea4-7f51-842c-112fe57860db` completed a Desktop turn, then a separate probe confirmed its writer was held. A detached runner gracefully quit the actual Desktop app, observed that it exited, and ran Diorama's native ExecutionController against the same ID. Resume started no turn. After explicit settings review and Send, the response recalled both the earlier context and Desktop's new marker, then recorded a new verification marker. Diorama's execution connection shut down and Desktop automatically reopened. Native test exit code: 0.

Evidence: `evidence/desktop-exit-lifecycle.json`, `evidence/desktop-exit-native.json`. This verifies the actual Desktop exit → native Diorama resume portion; it does not claim a GUI click-through test. No archiving, forking, lock deletion, or force quit occurred.

**Return to Desktop: verified.** The user manually sent the requested message after Desktop reopened. Turn `01a0b6db-045a-7211-a108-d612e995fab4` completed at `2026-09-18T23:30:05.471Z`, recalling both `INDEPENDENT_AFTER_QUIT_5291` and `DESKTOP-CEDAR-8426` without either full marker value appearing in the prompt. The transcript ties the user prompt, assistant reply and completion to the same turn. Desktop reported version `26.908.40834` on follow-up; App Server was `0.153.4`. This establishes the round trip for one disposable tool-free conversation, not simultaneous writers or universal Desktop-tool compatibility.

## Official imported conversation resume — Diorama 0.3.1

**Continue here** now uses `thread/read`, `thread/goal/get` and `thread/resume` for the selected Codex conversation. Only explicit user action acquires execution; no prompt is sent. Model and permission settings appear before **Use these settings** enables the composer. Approval reviewer is set to user for the resumed connection, without modifying global settings. Restored ownership also requires review again after restart.

Writer conflicts leave the import unowned and readable, with a clear **in use** explanation and **Retry**. Internal reviews/subagents, archived records, missing folders, recorded in-progress turns and active goals are refused. Unknown/unsupported API responses fail visibly; no automatic archive, fork, lock removal, process exit or prompt retry is attempted. Desktop client tools are not implemented; unsupported requests return errors and a visible limitation.

Native Swift tests cover preserved identity, no turn before explicit Send, settings review, writer rejection/retry, archived/internal exclusion and active-turn/goal checks. The opt-in native probe uses a fresh conversation and exercises occupied-writer rejection, owner exit, retry, retained context, a real explicitly accepted approval with provider resolution, resumed interruption/shutdown and a fresh-client return. The full Swift suite reported 55 tests with no failures (opt-in probes skipped in the normal run); the imported-resume probe passed separately. See `evidence/imported-resume-native.json` for exact passed scenarios.

**Subsequent Desktop quit/reopen validation passed**, as recorded above. The initial implementation probe kept Desktop running; the later designated test exercised actual exit and return. The feature offers official resume when Codex accepts it and accurately reports conflicts; it does not promise seamless Desktop handoff.

## Continuation options investigation — September 19, 2026

Fresh disposable tests verified same-ID resume after an independent owner process exits, a subsequent return to a fresh client with retained context, forking while the original owner remains open, and two clients continuing one persisted conversation through a shared loopback WebSocket App Server. Immediate unsubscribe did not release the writer to another process. These tests do not establish Desktop quit/reopen or third-party attachment to Desktop; the official default daemon socket is absent on this Mac. See [HANDOFF_OPTIONS.md](HANDOFF_OPTIONS.md), `evidence/handoff-options.json`, and the two `scripts/verify_*server`/handoff probe scripts for exact scope. Existing product behavior is unchanged.

## Native task execution — September 19, 2026

Diorama 0.3.0 adds a separate owned-task execution connection, retaining stage 1's read-only import path. Tested against Codex CLI 0.153.4; Swift 6.3.1. Official protocol reference: [Codex App Server](https://learn.chatgpt.com/docs/app-server). Current installed JSON schemas were used for request/response fields.

| Capability | Result |
|---|---|
| Model discovery, task creation, streaming and follow-ups | **Verified** with the native Swift transport/controller and two disposable tasks. Five models were returned; default model was gpt-6-astra. |
| Effective settings | **Verified** before the prompt: workspace permission profile, on-request approval policy, user approval reviewer. Global settings unchanged. |
| Terminal start/result | **Verified** with a harmless printf command. |
| Command approval and correlated resolution | **Verified**: a synthetic escalated printf request was explicitly accepted and resolved by the provider. No automatic approval behavior in the product. |
| User question and correlated resolution | **Verified** using a disposable plan-mode question with Alpha/Beta choices. Product UI supports received questions; a plan-mode selector is not included. |
| Concurrent tasks, interruption | **Verified**: one task answered while another ran a sleep command; turn interruption was acknowledged. |
| Quit with surviving terminal process | **Verified** after an initial probe exposed that interruption alone can leave a terminal process. Stop-and-quit now lists and terminates owned background terminals and confirms their absence. |
| Restart and explicit owned-task reconnect | **Verified**: a fresh controller loaded ownership metadata without running work, then explicitly resumed its own saved task. |
| Subagent independence, missing/late events, unavailable decisions, unsupported tools, uncertain submission | **Fixture-tested**, not all independently live-probed. Parent completion never completes workers. Unknown submissions are not retried. |
| File and permission-profile approvals | **Implemented and protocol-validated**; command approvals were the live-tested approval type. |
| Imported Desktop/CLI handoff in 0.3.0 | Initially gated. Version 0.3.1 adds ordinary official resume with writer-conflict handling; Desktop exit, native resume and return were subsequently verified in the designated test above. No archive/unarchive workaround. |
| Claude execution | **Deferred**; existing Claude Code observation remains supported. |

Evidence: `evidence/execution-native.json` and `evidence/execution-installed-ui.json`. The installed signed 0.3.0 window shows the new-task toolbar, imported-task handoff gate, and working history import. Automated sheet clicking was unavailable because osascript lacks assistive access; do not treat the controller probe as an end-to-end UI click test. The successful live probe completed in about 42 seconds and verified shutdown and owned reconnection. `swift test` reported 51 tests with no failures; opt-in probes are skipped unless requested. Ownership metadata is local and does not contain full prompts or responses. Live memory is bounded; full available source execution records remain in provider history.

The execution UI supports new/follow-up prompts, provider model/effort choices, streamed Markdown, explicit approval/input responses, interruption, and reconnection. Closing the window keeps the process running; quitting uses a confirmation and shutdown check when needed. No persistent service or seamless imported-conversation takeover is claimed.

## Native App Server history integration (September 19, 2026)

Stage 1 shipped in Diorama 0.2.0: read-only App Server discovery/history, with the existing Claude adapter and hook/transcript activity tracking. The 0.3.0 execution addition is documented above.

- Tested the Swift transport against Codex CLI 0.153.4. It explicitly allows only `thread/list` and `thread/read`, plus its initialization handshake. Requests are bounded; disconnection triggers a labeled local fallback. No task is loaded or resumed.
- Paginated active and archived discovery returned 999 Codex records. The combined library contained 1,305 records, with four archived records. The live body read was limited to the disposable round-trip conversation and returned eight rendered entries through App Server, including the final Desktop reply.
- The designated Diorama main conversation stayed classified as a conversation, and its internal reviews stayed hidden by default. A real compatibility gap was found and covered by a regression: App Server returns `threadSource: null` and a generic subagent source for the known guardian review. The importer therefore preserves explicit local `guardian_review` evidence rather than exposing it as an ordinary worker.
- Provider names and explicit parent metadata are imported. The current connection's runtime status is ignored for global activity. Missing source files are supported; the reveal action is shown only when a source URL exists.
- Local-file history is retained for API errors, unsupported item types, empty turns, and missing latest assistant replies. Both-source failures preserve the last successful selected history with a visible warning. Unknown session types remain visible; reasoning records remain excluded.
- `DIORAMA_APPSERVER_PROBE=1 swift test` reported 42 tests with no failures (one unrelated opt-in activity probe skipped). Coverage includes pagination/source filters, archives, guardian supplementation, unknown metadata, Markdown/context parsing, tool details, empty/partial history, disconnection, Claude fallback, and rejection of execution methods.

API discovery uses `useStateDbOnly` and local metadata supplementation. This avoids requesting index repair, but App Server itself may maintain ordinary runtime metadata. File-format fallbacks remain version-dependent. This validation does not establish cross-client live subscriptions, execution controls, or seamless handoff.

## Desktop → independent App Server → Desktop continuation (September 19, 2026)

**Verified sequential conversation continuity on Codex CLI 0.153.4. This is a diagnostic, not an implemented Diorama UI feature.** Disposable Desktop task `01a0b54c-d0a1-7f01-8866-0c2ae746a94e` was created and continued through Codex Desktop task tools; the intermediate turn ran in a separate `codex app-server --stdio` process. No existing user tasks or provider settings were changed. The disposable task was archived after testing.

- Direct `thread/resume` after the Desktop turn completed failed with `already has an active writer`. Idle does not mean released. This verifies a writer safeguard for this tested path, not all concurrency scenarios.
- Archiving through Desktop then attempting resume failed because the session was archived. Calling `thread/unarchive` through the independent server, then `thread/resume`, succeeded. This sequence is an experimental transfer procedure, not a recommendation to hide archive mutations inside a production Continue button.
- The resumed model recalled the original token `DIORAMA-CEDAR-7291`, executed only `/usr/bin/printf APP_SERVER_TOOL_OK` (exit 0), and returned `APP_SERVER_RETURN_TOKEN=MAPLE-4836`. Live item start/completion and turn completion events were received.
- Resume reported model `gpt-6-astra`, the original working directory, approval policy `on-request`, reviewer `auto_review`, and permission profile `:workspace`. Exact Desktop tool/permission equivalence was not tested; no approval was requested by the harmless command.
- After the independent server exited, Desktop accepted a follow-up and its persisted response correctly recalled both tokens and terminal output, without tools or file reads. Assertions against the designated transcript passed.
- Desktop's `read_thread` showed the App Server turn, but twice returned an empty items list for its own final completed turn. The final assistant response exists in the transcript. UI rendering/automatic refresh was not visually verified; do not claim seamless synchronization.

Evidence: `evidence/codex-appserver-roundtrip.json`, `evidence/codex-appserver-roundtrip-active-writer.json`, `evidence/codex-appserver-roundtrip-archived.json`, and `evidence/codex-appserver-desktop-readback.json`. An initial sandboxed probe timed out before initialization; the successful probes used authorized access to the local Codex session store and network. No simultaneous turns, Desktop restarts, dynamic client tools, or approval handoff were tested.

Product implication: saved-conversation continuation is feasible, but a reliable explicit release/attach workflow and complete history readback need validation before shipping same-conversation handoff. Passive history reads remain independent of execution ownership.

Test date: September 17, 2026. Host: macOS. Scope: existing local sessions, without replacing the source client.

## Follow-up: native prototype

The subsequent automatic-import prototype is now built as `dist/Diorama.app` using SwiftUI and a separate Swift file-reader module. Native UI inspection confirmed **1,291 deduplicated existing local sessions** imported from Codex, archived Codex, and Claude Code storage. It provides provider filters, search, selected-transcript refresh, and explicit connection limitations. Five native Swift tests passed. See README for build/run instructions and read limits.

This supersedes the initial diagnostic's lack of a macOS bundle and automatic discovery. It does **not** establish unified Claude Desktop access or authoritative live Claude status. The earlier matrix below records the initial isolated-probe results, not new integration claims. The app is locally ad-hoc signed, not notarized for distribution; it currently runs as a native session browser rather than a 3D world.

## Decision

**Proceed with a Codex-first prototype. Do not claim complete four-client support.** External access to Codex CLI and desktop conversation history is verified on this Mac. Live transcript observation is verified for an independently running CLI, including resume and observer reconnect. Claude CLI exposes readable records but successful execution was blocked by the configured account's credit balance. Unified Claude Desktop remains unverified.

The diagnostic is working locally; it is not a signed, notarized, packaged macOS app. A future native shell can host the observer, but packaging does not supply missing provider interfaces.

## Installed clients and actual probes

| Client | Installed version | Result | Evidence |
|---|---|---|---|
| Codex CLI | 0.153.4 | Partial overall; history and live observation verified | Independent fixed-reply session succeeded; resume ran `/bin/sleep 3`; observer saw completed → working → completed, calls/results, and growth while CLI was running. |
| Codex Desktop | 26.901.51231, bundle `com.openai.codex`, installed as ChatGPT.app | Partial overall; history and growing transcript verified | Current implementation task used as designated session. Separate App Server read its turns, messages, commands and file-change records without resume. Repeated transcript snapshots grew during this task. |
| Claude Code CLI | 1.0.108 | Partial: failed-session records verified; successful live execution untested | Isolated config returned `Invalid API key`; normal configuration returned `Credit balance is too low`. Both persisted readable user and assistant error messages with session IDs and working directories. |
| Unified Claude Desktop | 1.52386.3 | Unavailable in this prototype; feasibility unresolved | App inventory verified. Native automation returned an empty window shell after a long delay. No desktop test conversation or supported external event/history feed was verified. |

No unrelated transcript bodies, browser caches, cookies, tokens, or private network endpoints were inspected. Filename-only searches located known test IDs. CLI probes created their normal test session metadata. No provider hooks or permissions were modified. The observation service makes no agent calls.

## Capability matrix

V = verified with real session data; P = partial; U = untested/unavailable in this build. U does **not** mean the provider can never support it.

| Capability | Codex CLI | Codex Desktop | Claude CLI | Unified Claude Desktop |
|---|---|---|---|---|
| Locate exact designated session | V | V | V | U |
| Automatically discover all sessions | U | U | U | U |
| Session ID and working directory | V | V | V | U |
| User-facing session title | U | U | U | U |
| Read user/assistant messages | V | V | P: prompt + error | U |
| Read tool calls/results | V | V | U: fixtures only | U |
| Available code changes | U: no edits requested | P: App Server fileChange items and patch text | U | U |
| Live updates from independent client | V: file polling | P: current task transcript grows | U | U |
| Working/completed states | V: explicit transcript events | V: current/past turn events | U | U |
| Approval / interrupted states | U: fixtures only | U | U | U |
| Subagent parent relationships | U | U | U: fixtures do not prove integration | U |
| Several sources shown together | V | V | P: failed-session sources | U |
| Multiple simultaneous active agents | U | U | U | U |
| Resume same agent session | V | U | U | U |
| Recreate observer during active work | V | U | U | U |
| Source application restart | U | U | U | U |
| Observe background process | V: independent CLI | U: no controlled foreground/background experiment | U | U |
| Observer disconnect does not stop agent | V: recreated observer; CLI completed | P: separate App Server terminated; desktop task continued | U | U |

### What App Server proved

A separate `codex app-server --stdio` accepted `thread/read` with `includeTurns: true` for the designated CLI and desktop IDs. It returned CLI user/agent messages and desktop user/agent messages, commandExecution and fileChange records. The evidence retains only item types/counts and field names, not message content.

Both sessions returned `status.type = notLoaded` in the independent server. This cannot be interpreted as globally idle: the desktop task was active in another client. Cross-client event subscriptions and authoritative live status were not verified. The diagnostic therefore uses transcript events for its explicitly labeled last-recorded state.

### Interface stability

| Access method | Classification | Product consequence |
|---|---|---|
| Codex App Server `thread/read` | Documented interface; installed command identifies App Server as experimental | Promising history adapter; pin and test supported client versions. |
| Codex JSONL transcript | Version-dependent local-file parsing | Works on tested versions; requires regression fixtures and compatibility gates. Official hooks docs explicitly say transcript format is not stable. |
| Claude Code transcript | Documented storage location; version-dependent record parsing | Actual failed-session storage verified. Do not infer compatibility with unified desktop conversations. |
| Codex / Claude hooks | Documented lifecycle mechanism | No hooks installed; live hooks are not verified by fixture tests. Useful next step for approvals and subagent events. |
| Unified Claude external feed | No supported feed established in this investigation | Defer integration; absence of evidence is not proof of impossibility. |
| Screen scraping / private endpoints | Not an accepted production integration | No such adapter implemented. |

## Viewer checks

Seven automated tests passed, including loopback HTTP authentication/Host checks, parser exclusions, partial UTF-8 records, malformed records, source replacement, missing sources, two allowlisted sources, observer reconstruction, and fixture hook-state mapping. The live CLI probe separately verified actual file growth and state transitions. Browser verification confirmed a connected viewer with designated source entries and real CLI conversation/tool output. These checks do not establish all provider lifecycle behaviors.

The server binds only to 127.0.0.1, requires a fresh bearer token for data access, serves no arbitrary files, sends no CORS permission, uses no third-party scripts, and renders transcript text without interpreting HTML. It polls each requested snapshot at approximately one-second UI intervals; source write/flush latency is unknown. It is not token-by-token streaming. Display is limited to the latest 2,000 entries per source. Attachments, structured diffs, automatic subagent discovery, global titles and session discovery are outside the current diagnostic.

## Remaining release gates

1. Funded Claude CLI verification now passes on 2.1.276; finish the interactive approval, typed-notification and interruption scenarios listed in the latest results below.
2. Obtain a usable unified Claude Desktop test session and identify a documented external feed. Do not extend Code hook claims to unified conversations without evidence.
3. Install opt-in test hooks in disposable configurations, verifying approvals, interruptions and subagent start/stop for each supported client version.
4. Run controlled application restart, background, simultaneous-active-session, and source-disconnect scenarios. Keep unknown states explicit.
5. Prefer the proven App Server history interface for a production Codex adapter; validate live events separately. Preserve version-gated transcript parsing only where needed.

## Primary documentation

- [Official OpenAI App Server documentation](https://learn.chatgpt.com/docs/app-server)
- [Official OpenAI hooks documentation](https://learn.chatgpt.com/docs/hooks)
- [Claude Code hooks](https://code.claude.com/docs/en/hooks)
- [Claude Code session storage](https://code.claude.com/docs/en/sessions)
- [Claude Code desktop configuration](https://code.claude.com/docs/en/desktop)
- [September 16 unified Claude announcement](https://claude.com/blog/cowork-is-now-claude)

The announcement establishes the chat/Cowork merger, not a public subscription API for third-party observers.

## Activity implementation follow-up — September 18, 2026

Diorama now observes all imported sessions with FSEvents (500 ms stream latency and 500 ms application debounce), a 15-second reconciliation scan, and wake/resume refresh. Activity parsing bootstraps from 512 KiB, searches up to 16 MiB for a missing Codex lifecycle state, then consumes new complete lines. Each session retains at most 500 recent activity records plus its pending bounded line buffer; conversation bodies remain selection-only. A large append is consumed in bounded 2 MiB batches. No token-level streaming is claimed.

The UI includes last-reported badges, current tool/compaction labels, folder counts, Working/Needs attention filters, an attention inbox, and an Activity timeline. Approval resolution requires explicit call/turn correlation; requests without that evidence remain Resolution unverified. A Stop hook is shown as response stopping, since another hook can continue execution. Tool failures never imply global blocking. Unknown and stale states remain explicit. Internal reviews are excluded from activity aggregates.

| Integration | Version | Evidence and limitations |
|---|---|---|
| Codex transcript adapter | CLI 0.153.4 / designated desktop conversation | New Swift activity adapter read the actual designated Diorama transcript, recovered explicit state within its bounded tail, and produced stable event identity after observer recreation. `evidence/activity-codex-desktop.json` contains counts/types only. Existing independent CLI live-transition evidence remains in `evidence/live-codex.json`. |
| Codex hooks | CLI 0.153.4 | Optional experimental setup matches documented lifecycle names. Live delivery and desktop hook coverage remain unverified; provider trust is never bypassed. |
| Claude Code hooks | 1.0.108 | Installed package's event schema was inspected. A disposable disconnected CLI invocation delivered SessionStart and UserPromptSubmit to the native reporter. Tool/approval/subagent delivery and successful model execution remain unverified. See `evidence/activity-reporter.json`. This version has no PermissionRequest, SubagentStart, PostCompact, or PostToolUseFailure; only its supported event set is configured. |
| Unified Claude Desktop | Unchanged | No supported adapter verified. |

The isolated Claude probe used a temporary HOME/configuration and an intentionally unreachable local API endpoint. It timed out during unavailable model execution; no normal settings were modified. This proves those two hooks can fire, not successful turns or cross-client equivalence. Other installed versions are gated off until inspected and tested.

The native reporter accepts bounded stdin, writes only allowlisted metadata/previews (maximum 1,000 characters each), emits neutral `{}` output, and exits successfully on malformed input or storage failures. Direct subprocess checks prove it operates without a running GUI. The optional setup previews the resulting JSON, backs up settings, preserves other handlers, rejects concurrent settings edits, and removes only its exact reporter command. Provider trust must still be reviewed in the original client. No hooks were installed in normal user configuration during implementation.

Hook records are stored privately under `~/Library/Application Support/Diorama/Activity`, retained for seven days and capped at 50 MiB. Clearing activity history removes hook records only; transcript-derived activity is reconstructed from original files. Commands, paths, and error excerpts can contain sensitive information and remain local.

Sources remain authoritative for event semantics, not proof of installed-version support:
- [Codex hooks](https://learn.chatgpt.com/docs/hooks)
- [Claude Code hooks reference](https://code.claude.com/docs/en/hooks)
- [Codex App Server](https://learn.chatgpt.com/docs/app-server)

Remaining live gates: successful Claude execution, real approval/denial and input requests, Codex hook trust/delivery in CLI and desktop, actual subagent lifecycle, and source-app restart/background combinations. Automated fixtures cover these state transitions where schemas are available; they do not substitute for live validation. No Idle/Blocked capability is claimed without explicit supported events, and generic old Claude notifications are not interpreted by message text.

## Live hook verification — September 18, 2026

This follow-up supersedes the hook-delivery limitations above **only for the CLI cases listed here**. The tests used the packaged native DioramaReporter, existing accounts, and disposable configurations. Codex hooks were reviewed and trusted through the normal CLI `/hooks` screen; no trust, permission, or sandbox bypass flags were used. Normal provider hook settings were not changed.

| Client / scenario | Result |
|---|---|
| Codex CLI 0.153.4 — SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Stop, SessionEnd | Verified in a successful real model turn. `/bin/echo` returned 0 and intentionally failing `/usr/bin/false` returned 1. Both produced tool lifecycle hooks; PostToolUse alone does not mean success. |
| Codex CLI — PermissionRequest, one-time approval | Verified: the native reporter received the event while the approval dialog was visibly awaiting an answer. A harmless echo ran only after approval. |
| Codex CLI — cancellation / Interrupt | Verified: canceling a second harmless echo approval emitted Interrupt and no tool-result hook for that rejected call. This is an approval-cancellation test, not a separate mid-command kill test. |
| Codex CLI — SubagentStart / SubagentStop | Verified with one explicitly requested, tool-free worker. Hook agent_id matched the child's transcript ID; session_id identified the parent. Recorded agent_type was `default`. |
| Codex CLI — PreCompact / PostCompact | Verified with manual `/compact` in the designated test conversation. Automatic compaction was not forced. |
| Claude Code 1.0.108 — SessionStart, UserPromptSubmit, Stop, SessionEnd | Verified against the real configured account, which returned **Credit balance is too low**. A Stop event is therefore not proof of successful completion. |
| Claude Code — tool execution, approvals, successful subagents | Blocked by account credit. The old installed schema also lacks PermissionRequest and SubagentStart. No billing, authentication, or client upgrade changes were made. |
| Codex Desktop / unified Claude Desktop | Not established by these CLI tests. Desktop hook loading, background behavior, and application restart remain unverified. |

Evidence: `evidence/codex-live-hook-verification.json`, `evidence/claude-live-hook-verification.json`, `evidence/codex-subagent-hooks.json`, and the approval fixtures. The first Codex exec attempt used `--ignore-user-config`, which suppressed its user hooks; that attempt was not counted as successful hook verification. The corrected invocation used the isolated user configuration and persisted normal hook trust.

The captured PermissionRequest has a turn ID but no tool-call ID. The real-evidence Swift regression test proves Diorama retains the unresolved request after tool-result/Stop hooks and clears it only after the explicit matching transcript turn-completion record. It also verifies the final state becomes Last turn finished. All examples are designated synthetic test commands; no unrelated conversation content was captured.

The final Codex source-process restart/resume probe also passed: hooks retained the same session ID, arrived while the independent CLI was running, and continued after the file observer discarded/recreated its own state. The agent returned the expected completion marker. See `evidence/codex-resume-hook-verification.json` and `evidence/codex-interactive-hook-verification.json`. This proves CLI process restart and passive collector independence, not restarting the macOS Desktop app. All disposable test processes were closed; the temporary authentication symlink was removed without modifying its target.


## Updated Claude CLI verification — September 18, 2026

The user funded the API account and requested a CLI update. The shell initially selected root-owned npm Claude Code **1.0.108**, even though a native **2.1.251** copy existed. An in-place npm update failed with OS permission error EACCES. Anthropic's official native installer successfully installed **2.1.276**, the latest release reported by its release endpoint during this test. The user's `.zshrc` was backed up and now prepends `~/.local/bin`; a fresh interactive zsh resolves the native 2.1.276 binary. The old root-owned npm copy remains on disk. Diorama's Connections detection now prefers the native binary over old npm package metadata.

The old CLI's default `claude-sonnet-4-20250514` returned an API model-not-found error after funding. All successful probes used `--model claude-haiku-4-5-20251001` per invocation, without changing the saved model. This model is listed in the [official model overview](https://platform.claude.com/docs/en/models/overview). Installation followed the [official setup documentation](https://code.claude.com/docs/en/setup); event schemas were checked against the [hooks reference](https://code.claude.com/docs/en/hooks).

| Claude Code 2.1.276 capability | Tested result |
|---|---|
| SessionStart, UserPromptSubmit, Stop, SessionEnd | Verified during a successful funded model turn. Stop still does not assert completed/idle. |
| PreToolUse, PostToolUse, PostToolUseFailure | Verified with a successful echo and intentional exit-code-1 command. Explicit matching tool-use IDs, recorded durations, and failure excerpt reached the native reporter. |
| SubagentStart, SubagentStop | Verified with one tool-free general-purpose worker. Start/stop share an explicit agent ID; session ID names the parent. |
| Source-process restart / resume | Verified: new CLI process resumed the same session ID. Hooks arrived while it ran and after the passive file collector recreated its state. |
| PermissionRequest | Verified for a Write request in noninteractive mode. Reporter returned neutral `{}`; provider denied the call and no file was written. Interactive approval/denial dialogs were not tested in this round. |
| Approval resolution | Partial: request has no tool-use or turn ID. Diorama retains Resolution unverified rather than guessing resolution from Stop/SessionEnd or matching by tool text. A regression test preserves this behavior. |
| PreCompact / PostCompact | Verified using manual `/compact` on the designated session. Automatic compaction was not forced. |
| Notification / interrupt / input waiting | Typed notifications and user-interruption scenarios remain unverified. No silence-based state inference. |
| Desktop variants | CLI results do not establish Codex Desktop hook delivery or unified Claude Desktop support. |

Evidence is in `evidence/claude-live-hook-verification.json`, `claude-funded-turn-hooks.json`, `claude-resume-hook-verification.json`, `claude-resume-hooks.json`, `claude-permission-hook-verification.json`, `claude-permission-hooks.json`, `claude-compaction-hook-verification.json`, and `claude-compaction-hooks.json`. Native reporter records contain allowlisted metadata only. Swift tests consume the real tool, worker and permission captures.

The funded legacy checks are retained with `-1.0.108.json` suffixes. That version delivered successful tool and subagent-stop hooks, but lacked failure hooks and worker identity. Its resume invocation returned a different session ID, so same-session resume was **not verified** for 1.0.108. The later 2.1.276 test passed that requirement.

Reported CLI costs for the six successful funded runs sum to approximately **$0.24** (CLI-reported estimates, not a billing-ledger reconciliation). Each new-version invocation had a $0.25–$0.50 budget cap. These tests used temporary additional hook settings and the existing account; normal provider hook settings and source transcripts were not edited by Diorama. Native CLI execution naturally writes its own designated transcripts. No GUI process was required for the reporter or passive collector tests.

The designated worker transcript also confirms the nested parent/subagent layout, `isSidechain`, explicit agent ID and parent session ID agree with the hook records (`evidence/claude-worker-transcript-identity.json`). The rebuilt macOS bundle passed strict deep code-signature verification after copying without extended attributes to `~/Applications/Diorama.app`. The synced Documents build location reintroduced FinderInfo metadata, which caused strict verification there to fail; the installed copy avoids that location.

## Interactive and desktop follow-up — September 18, 2026

These tests supersede the earlier blanket “interactive and desktop unverified” statement for the specific scenarios below.

| Scenario | Evidence and classification |
|---|---|
| Claude Code 2.1.276 interactive approval | **Verified.** The actual Write approval dialog stayed open while PermissionRequest and delayed permission notification events arrived. Selecting one-time Yes created the synthetic file and produced PostToolUse. No persistent allow rule was selected. |
| Interactive denial | **Verified delivery, partial resolution.** Selecting No prevented the file creation. The transcript records the explicitly identified tool rejection. No hook provided a request-to-resolution identifier, so the inbox must retain Resolution unverified for those requests. |
| Waiting for input | **Verified, partial labeling.** AskUserQuestion showed Alpha/Beta choices; selecting Alpha generated a matching tool result. PreToolUse and PermissionRequest identify AskUserQuestion explicitly, now mapped to Waiting for input. A later generic permission notification has no tool identity and may supersede the specific badge with Awaiting approval; no correlation is invented. MCP elicitation forms were not part of this test. |
| Permission notification | **Verified.** A second approval-shaped event arrived roughly six seconds after each waiting dialog, matching the documented Notification permission_prompt timing. |
| Idle notification | **Verified.** An explicit Idle event arrived about 60 seconds after the final response; no idle state was inferred from silence. |
| Running command interruption | **Exercised; dedicated hook unavailable in the tested case.** After one-time approval of `/bin/sleep 30`, Escape visibly interrupted the running tool. The transcript carries an is_error rejection result linked to its tool-use ID. No interruption or PostToolUseFailure hook arrived. The same generic rejection text also occurred for denial, so Diorama does not guess Interrupted from that text. |
| Codex Desktop 26.901.51231 resume | **Verified for session-start, tool start/result and stop.** A designated CLI-seeded task was closed in the CLI, then resumed via the desktop app's task API. The desktop completed an echo and the independent reporter recorded matching turn/tool IDs. The desktop dispatch path did not emit UserPromptSubmit. |
| Codex Desktop background | **Verified for tool start/result and stop.** Claude was explicitly made the foreground app before dispatching a second designated Codex desktop turn, which completed sleep/echo and emitted the events. This is not an application-restart test. |
| Unified Claude Desktop 2.2553.0 | **Unavailable with the current account/integration.** The visible new-chat UI showed Free plan and Chat/Cowork controls. The documented Cowork OTel feed requires Team or Enterprise; cross-product inference hooks require Enterprise and a hosted allow/deny service. Neither establishes a local observational integration for this account. No claim that consumer plugin hooks are universally impossible is made. |

Evidence: `evidence/claude-interactive-hook-verification.json`, `claude-interactive-hooks.json`, `claude-interactive-tool-results.json`, `codex-desktop-hook-verification.json`, and `codex-desktop-resume-hooks.json`. Only the designated synthetic transcripts were inspected. Legacy captures predate the new source labels; new reporter events preserve hook name and notification type in their source field for inspection. Tests cover the captured idle event and explicit question metadata.

The CLI dialogs were exercised through a real PTY. Approvals and answers were test actions in the source client; Diorama's reporter remained neutral and the product gained no agent-control functionality. A normal trust review enabled only seven test-owned project-local Codex hooks. The CLI processes were closed after testing. The desktop test task was completed before cleanup. The main working conversation and unrelated tasks were not interrupted or restarted.

A broad native accessibility query was rejected by automatic approval review because it could expose unrelated Claude conversation contents. That query was not retried through another mechanism. The remaining desktop assessment used already-visible account information, version metadata, official documentation, and a narrow foreground-app-name check. Desktop application restart and remaining unexercised hook types are still separate release gates, not implied successes.

Primary references:
- [Claude Code hooks: notifications and failure semantics](https://code.claude.com/docs/en/hooks)
- [Codex hooks: discovery and normal trust review](https://learn.chatgpt.com/docs/hooks)
- [Cowork OpenTelemetry: Team/Enterprise access and event coverage](https://support.claude.com/en/articles/14477985-monitor-claude-cowork-activity-with-opentelemetry)
- [Inference hooks: Enterprise access and hosted policy enforcement](https://support.claude.com/en/articles/16059458-inference-hooks-overview)

## Desktop-held writer baseline — September 19, 2026

After the user sent READY in Desktop and confirmed leaving it open, the designated transcript recorded a completed reply in turn `01a0b6f8-b04f-7532-9bed-9f2891d23020`. A separate CLI 0.153.4 App Server rejected same-ID resume with `already has an active writer`, returned `notLoaded` to its own `thread/unsubscribe`, and rejected resume again afterward. This directly verifies that a separate observer cannot release this Desktop-held writer through its own unsubscribe. It does not test owner-side unsubscribe or its 30-minute grace period. No prompts, archive changes, Desktop shutdown or lock manipulation occurred. Evidence: `evidence/desktop-release-baseline.json`; probe: `scripts/verify_desktop_release_baseline.py`.

Next Desktop-side check: manually archive only the designated disposable conversation while leaving Desktop open, then verify archive state and same-ID unarchive/resume externally. This repeats the previously successful archive route against a newly confirmed held-writer baseline; it is not yet an enabled Diorama handoff workflow.

## Desktop archive release — verified September 19, 2026

Following the freshly verified held-writer baseline, the user archived only the designated conversation and reported leaving Desktop open. The archived transcript was confirmed. Official `thread/unarchive` restored the same ID, `thread/resume` succeeded, and a new completed turn recalled the prior Desktop marker and returned `DESKTOP-CEDAR-8426 ARCHIVE_RELEASE_VERIFIED`. The prompt did not supply the prior marker value. No tool items were observed, and the probe connection was closed afterward. CLI: 0.153.4. Evidence: `evidence/desktop-archive-release.json`; turn: `01a0b6fc-30ea-70e3-98eb-b9ed18fb6b80`.

This demonstrates an alternative to quitting Desktop: explicit Desktop archive followed by external restore/resume. It is not yet implemented in Diorama and is not documented as an atomic handoff operation. Archive may affect descendants; this test concerns the designated root conversation only. Desktop remaining open is based on the user's confirmed action, not the earlier unreliable process-name check. A return message from Desktop was not tested in this repeat. Initial archived `thread/read` returned not-found; unarchive-before-read succeeded, preserved separately in `desktop-archive-release-initial-read.json`.

### Attachment input validation — 2026-09-19, Diorama 0.3.7

Official [App Server turn inputs](https://learn.chatgpt.com/docs/app-server#turns) support `text`, `image`, and `localImage`. Diorama sends local images as `localImage`; non-image files are text path references, not a claimed native file-upload input. Existing sandbox and approval settings remain unchanged.

A designated independent App Server probe on **codex-cli 0.153.4** successfully accepted a synthetic PNG and answered “Red”; evidence: `.local/attachment-probe/evidence.json`, reproducible with `scripts/verify_image_attachment.py`. This verifies local PNG delivery and model interpretation, not every supported image format. Nineteen targeted unit/rendering tests passed, covering input construction, image-only/mixed input, file-only writer retry, missing/deleted files, invalid images, and existing approval/uncertain-send behavior. Native conversation fixture visually checked at 520-point width. Interactive macOS picker and Finder drop smoke tests remain manual. Claude remains observation-only.

### Approval settings — Diorama 0.3.8, 2026-09-19

Supersedes earlier statements that resumed/new conversations always use the user reviewer. `thread/start` and `thread/resume` now omit approval overrides. The composer supports explicit `user` or `auto_review` choices via official `turn/start.approvalsReviewer`; the installed generated schema documents these as applying to the turn and subsequent turns. Other permission settings remain untouched.

Live disposable probe (`scripts/verify_approval_settings.py`, `.local/approval-settings-probe/evidence.json`) verified both requested modes are reported by a subsequent resume, with approval policy remaining `on-request`. Initial independent-server default was `user`; Desktop preference parity is not assumed. This tool-free test verifies configuration acceptance and retention, not review decisions on privileged commands. Seventeen targeted execution/rendering tests passed, including inherited settings, explicit overrides, conversation isolation, and approval handling. Native 520-point conversation fixture inspected. Global settings were not edited.

## Official project registration investigation — September 19–20, 2026

Codex CLI 0.153.4 exposes experimental project APIs in its generated schema. Live `project/import`, idempotent retry, `project/create`, and `thread/start.projectId` succeeded on designated disposable records; project identity and conversation membership survived fresh App Server connections. Merely creating a folder and conversation did not register a project in the sampled `project/list`. **User subsequently verified Desktop conversation discovery:** BIRCH-7392 appears under Recents as a standalone thread. **Automatic project-folder grouping was not observed**, despite persisted API project membership. Installed Desktop version: 26.908.40834 (8881). See [PROJECT_DISCOVERY.md](PROJECT_DISCOVERY.md) for evidence, limitations, and test records. No product integration changes were made.

Desktop folder-add follow-up: user added/opened `Diorama Created Project Test 20260919`; supplied screenshot shows **No chats**. Matching the folder did not automatically group the existing BIRCH-7392 conversation. See PROJECT_DISCOVERY.md.

Further investigation established duplicate IDs for the same test folder/name: Desktop addition created a second project while the conversation remained assigned to the first. Official `thread/metadata/update.projectId` successfully reassigned BIRCH-7392 to the Desktop-added project; fresh read and project-filtered list confirm membership. Desktop rendering after reassignment is pending. This supersedes the suggestion that the systems necessarily require separate organization; the APIs share the observed project registry, but initial sidebar visibility remains unexplained.

Fresh MAPLE-8264 reassignment visual check: despite official API membership in the Desktop-added project and fresh-server verification, the user screenshot still shows **No chats**. Desktop grouping is not verified by matching project ID alone. Full Desktop restart has not been tested; do not claim a cache cause or reliable Desktop project synchronization.

Desktop-native control confirmed visually: DESKTOP-4192 appears beneath the test project although both CLI 0.153.4 and Desktop bundled 0.154.0-alpha.6.2 report its local projectId as null. MAPLE-8264 has the matching local projectId but is absent from that grouping. Therefore the tested local App Server project membership is insufficient to reproduce Desktop sidebar membership. The additional mechanism is unknown.


## Claude execution integration — 0.5.0 (30)

Added a native Claude Code process adapter, provider routing, one-time default-model onboarding, Settings (Models & accounts), and a grouped OpenAI/Anthropic composer picker. The Claude adapter uses the installed unmodified CLI and its official login. It clears process-level API overrides and refuses to submit prompts when the initialization account reports API-key authentication or cannot establish token-based login; it never silently falls back to API billing. The current local account reports `/login managed key` and no subscription type, so end-to-end subscription verification remains pending.

Claude events are normalized for the existing conversation, tool activity, approval, question, interruption, and attachment UI. Queue files persist locally; uncertain delivery stops automatic advancement. Cross-provider changes open an editable linked-session draft based on the source commit, preserving the original and making uncommitted-file exclusion visible. Project instructions/references are captured in the new worktree context.

Validation: 151 tests across 35 suites passed. Added real subprocess fixture tests for streaming, request decisions, stopping and continuing, billing rejection before submission, catalog capability filtering, and queue restart. Settings and grouped model picker rendered and visually inspected. Prior live CLI probes established images, model switching, approvals, questions, interruption and resume, but used a managed API credential and are not proof of subscription billing. This build has not been verified end to end with an actual subscription login.

Limits: Claude persistent Goal and Codex-style Steer are not exposed. Dynamic reasoning-effort changes returned an unsupported-control error in a live, no-inference probe, so the Claude picker does not advertise them. Claude uses configured native skills/MCP; the Codex-specific integrations picker is not presented for Claude. Cross-app simultaneous ownership and automatic Desktop synchronization remain unverified.


### Claude Max subscription verification — 2026-09-21T10:08:32.025608+08:00

Official `claude auth status` reports claude.ai, Max, and no API key source. Current initialize account uses `subscriptionType: Claude Max`, `apiProvider: firstParty`, and omits tokenSource. Updated the subscription gate to recognize these explicit subscription types while rejecting API credentials. Opt-in ClaudeSubscriptionLiveProbe passed through the production transport and controller with the expected real Haiku response. Evidence: `evidence/claude-subscription-live.json`. Billing dashboard was not inspected. Regression run: 153 tests in 36 suites passed. Build 0.5.0 (31) signed and verified at `/tmp/diorama-subscription-release/Diorama.app`; packaging in synced dist hit Finder metadata signing errors. Installed app was not replaced.


### Native Claude UI verification — 2026-09-21T10:46:54.926851+08:00

Build 0.5.0 (33): 155 tests across 37 suites passed; code signature verified. Native walkthrough passed project session/worktree creation and context inheritance, subscription replies, image interpretation, file reading, allow/deny, resume, Haiku/Sonnet switching, queue/send-next, Plan Mode and interactive questions. Stop returned to interrupted state; OS command termination was not independently observed. Fixed project mutation exclusivity crash and replaced duplicated adaptive composer controls with stable layout; formerly crashing Plan Mode/send transitions passed on retest. Also separated Claude canvas context from user text, bounded the attachment tray, guarded redundant scroll writes, and restored parent focus after the native file picker. Final picker selection and return to composer passed.

Evidence: `evidence/claude-ui-verification.json`. Artifact: `/tmp/diorama-stable-release/Diorama.app`. Installed Applications copy was not replaced. Clipboard paste, drag/drop, long-running stability and cross-app synchronization were not verified in this UI pass. Claude Goal, Steer and dynamic reasoning effort remain unsupported.


### Claude goals and steering — 2026-09-21T13:30:45.236854+08:00

Build 0.5.0 (34) supersedes the earlier unsupported Goal/Steer statements. Claude now supports Diorama-owned persistent goals and explicitly labeled Interrupt & steer. Neither requires Codex. Goals checkpoint progress and selected model, pause on restart/disconnect/declined permission or ambiguous results, and default to ten responses and 100,000 reported tokens checked between responses. Steering waits for native interruption before sending a correction, and pauses a goal. Codex behavior remains server-backed.

165 tests in 39 suites passed. Final real-subscription production transport/controller probe passed interruption/correction plus two-response goal completion, including hidden internal markers. See evidence/claude-workflow-live.json and docs/CLAUDE_WORKFLOWS.md. Signed build: /tmp/diorama-claude-workflows/Diorama.app. Installed copy unchanged; new native controls still need a full manual walkthrough.


### Native Claude workflow walkthrough — 2026-09-21T13:41:38.460294+08:00

Build 0.5.0 (35): native UI verified Goal/Plan exclusion, two-response completion, edit/save-paused, pause/resume, square Stop, direct steering, queued steering with one delivery, clear, and reopen recovery. Review goal reconnects without resuming or sending a prompt. Fixed automatic continuation appearing as user text, missing saved-goal recovery controls, block-format history status markers, and model-control metadata. 167 tests in 39 suites passed. Evidence: evidence/claude-workflow-ui.json. Artifact: /tmp/diorama-ui-verified/Diorama.app. This supersedes the earlier full-manual-walkthrough limitation for these controls.


### First-run onboarding verification — 2026-09-21T14:01:30.984563+08:00

Build 0.5.0 (36): fixed Claude-only initial model selection, unavailable-model completion gating, and onboarding dismissal protection. Saved unavailable defaults are preserved for reconnect; composer overrides do not change the saved default. Isolated native UI checks passed Claude-only, Codex-only, both, and neither, including simulated login plus refresh. These use production views/controller with fixture account states and isolated preferences. Real packaged Settings separately showed both OpenAI and Anthropic Connected and the existing OpenAI default unchanged. No real credentials were changed; fresh OAuth issuance and CLI installation were not exercised. 169 tests in 40 suites passed. Evidence: evidence/onboarding-verification.json. Signed artifact: /tmp/diorama-onboarding-verified/Diorama.app. Installed Applications copy was not replaced.


### Permission review — 2026-09-21T18:34:22.974003+08:00

Build 0.5.0 (37) replaces capped scrolling approvals with a fixed decision card and separate details sheet. Claude tool metadata stays structured. The shared presenter shows file paths, commands, URLs and explicit turn scope without generating a speculative explanation. Additional provider-offered decisions remain in review details. 173 tests / 42 suites passed. Isolated native UI verified accept, decline, turn grants, persistent footer during scrolling, draft preservation and disabled disconnected controls. See evidence/permission-review-ui.json for limits. Signed artifact: /tmp/diorama-permissions-verified/Diorama.app.


### Send latency and history payload fix — 2026-09-21T19:08:33.640518+08:00

Build 0.5.0 (38): imported resume now uses metadata-only thread/read, one descending turn with itemsView notLoaded, and excludeTurns on resume. Active-turn and goal checks remain. Execution pipe drains up to 32 ready chunks per poll and scans only new partial-frame bytes. Mode catalog is reused until disconnect. Read-only timeouts no longer claim uncertain submission. 174 tests in 43 suites passed, including 4 MiB subprocess framing and timeout copy. Live read-only metadata/status probe returned 1,621 bytes in approximately 5 ms total request time; no inference or ownership acquisition. End-to-end send latency was not benchmarked. Evidence: evidence/send-latency-fix.json. Artifact: /tmp/diorama-send-fix/Diorama.app.


### Immediate message presentation — 2026-09-21T19:16:41.516163+08:00

Build 0.5.0 (39) inserts a local user bubble and clears the composer before async connection/submission work for ordinary sends and steering. No Sending indicator. New drafts remain editable and are not cleared on the previous send acknowledgement. Provider echoes replace the local bubble; confirmed failure has inline Retry during the current app session, while uncertain delivery has no automatic retry. Local outgoing records persist and pending records reopen uncertain. Queue and cross-provider linked-draft paths are unchanged. 178 tests in 45 suites passed; evidence/instant-send.json records scope and limits. Artifact: /tmp/diorama-instant-send/Diorama.app.


### Bubble tail and Enter to send — 2026-09-21T19:20:29.262499+08:00

Build 0.5.0 (40) gives user bubbles a curved lower-right tail. The conversation composer sends on Enter or keypad Enter with nonempty text or attachments, retains Command+Enter, and preserves Shift+Enter and input-method marked text handling. Editors with no send callback retain normal newline behavior. 180 tests in 46 suites passed, including native keyboard events; tail rendering was visually inspected. Artifact: /tmp/diorama-bubble-keyboard/Diorama.app.
