# Priorities 1–11 acceptance results

20 September 2026. This report distinguishes automated fixtures, real App Server/controller execution, and visible native UI testing. It does not treat those as interchangeable.

## Scope and environment

Testing uses the native `ExecutionController` and production `CodexExecutionTransport`, the installed account/runtime, disposable conversations and temporary Git projects. Real model calls and mutations were authorized by “continue — and test it all.” Existing user conversations were not resumed or changed by these probes.

The initial 117-test suite passed again. The existing live execution and imported-resume suites both passed, including real approval responses and user-input responses. A new opt-in workflow probe covers the added methods. **Final regression result: 120 tests in 27 suites passed.** The three opt-in live suites also passed when run separately. The workflow JSON records **11 successful checks and one blocked live structured-plan emission check**; a passing harness does not erase that blocked result.

## Per-priority evidence

| Priority | Observed result | Remaining acceptance boundary |
|---|---|---|
| 1 · Steering | Real correction accepted during a terminal command; completion history includes the correction marker. | Composer click path was not fully completed through UI automation. |
| 2 · Plan + changes | Real typed command/file results and a 236-character diff received from a disposable `demo.py` edit. Structured plan rendering has fixture coverage. | The live model reported `update_plan` unavailable. No emitted structured checklist was certified in that session. |
| 3 · Questions + approvals | Real command approval accepted/resolved, real Plan-mode choice answered, resumed-conversation approval resolved. File approvals are restricted by the probe to its own `demo.py`. | Provider MCP elicitation forms/URL completion remain fixture-tested; no designated provider OAuth test was completed. |
| 4 · Goals + usage | Real paused goal creation/edit/read/clear, active goal pause/clear, account limits and compaction request exercised. Active test work is interrupted during cleanup. | Compaction acceptance alone is not proof of every long-history compaction outcome. |
| 5 · Organization | Real rename round trip, archive, restore and re-archive passed. Pin persistence has a dedicated model test. | Native rename and pin/unpin menus were exercised successfully. Pin persistence across model recreation passed; full GUI relaunch appearance was not rechecked. |
| 6 · History/search | Both search APIs found the test marker; a second history page loaded. | Native Find returned both marker matches and displayed the matching assistant turn. Extremely long-history GUI behavior was not exhaustively tested. |
| 7 · Plan mode | Actual advertised Plan preset selected through native controller; real planning response received, followed by default execution. | No claim that planning always emits a structured checklist. |
| 8 · Skills/connectors | Project-local test skill discovered and invoked as a typed capability; expected skill marker returned. App/MCP discovery exercised. | Native picker selection changed Use to Remove. No real provider OAuth, external connector write or global skill-setting change was performed; those paths retain fixture coverage. |
| 9 · Fork/review | New idle fork created; real uncommitted-change review completed with a result; disposable fork archived. | Base-branch review and every UI navigation path are not independently live-certified. |
| 10 · Queue | Real next-run delivery followed successful completion; separate pending message removed during an active turn. | Failure/interruption/uncertain delivery safeguards retain automated fixture coverage; no restart-drain guarantee is claimed. |
| 11 · Rich results | Real commands and file edits exercise typed results; light/dark native rendering fixtures cover presentation. | Live generated images, arbitrary MCP result types and worker navigation were not all produced in this run. |

## UI findings and changes

Version **0.3.19 (build 22)** includes three app fixes discovered during testing:

1. Folder and attachment pickers use asynchronous `NSOpenPanel.begin` callbacks instead of nesting `runModal()` inside a SwiftUI/accessibility action.
2. Newly created conversations select the same normalized folder ID used by the sidebar. Previously, `/private/tmp` versus `/tmp` could send selection back to another conversation. A regression test reproduces this condition and verifies retained selection.
3. Display titles omit appended `<diorama_html_view>` instructions when App Server derives a title from combined prompt inputs. A regression assertion covers the observed contamination; underlying conversation records are unchanged.

UI automation initially timed out after folder selection. Resetting the automation connection recovered the app and showed the correct selected folder. The isolated rebuilt app then successfully prepared/sent a Plan-mode test, displayed its answer, created/cleared a paused goal, showed usage, found the matching turn, renamed the conversation, pinned/unpinned it, and selected a skill. The final two presentation fixes were regression-tested after that UI run.

Automation remained intermittent and a later cleanup reconnection timed out. This is not a claim that every GUI path passed. The isolated copy at `/tmp/DioramaAcceptance.app` may remain open; its test conversation is idle with its goal cleared and pin removed. No user conversation was modified. The copy uses a separate bundle identifier/preferences. The latest production build is `dist/Diorama.app`.

The final production executable compiled successfully. Finder/file-provider attributes briefly prevented bundle signing; stripping extended attributes from the generated bundle and re-signing resolved it. Strict deep signature verification now passes. The build script performs that cleanup and verification for future builds.

## Test-harness corrections

Early workflow attempts had harness mistakes: calling new-turn `send` instead of `steer`, comparing `/var` and `/private/var` skill paths literally, and testing deletion at idle where queue delivery could start. The corrected harness uses `steer`, the returned skill path, and deletion during a live wait command. Those earlier failures are not presented as application defects or final passing results.

The live structured-plan assertion was separated from command/file verification once the model explicitly reported the plan tool unavailable. Its status remains **blocked**, not silently converted into a successful live check.

## Reproduce

```sh
swift test
DIORAMA_EXECUTION_PROBE=1 swift test --filter ExecutionLiveProbe
DIORAMA_RESUME_PROBE=1 swift test --filter ImportedResumeLiveProbe
DIORAMA_WORKFLOW_PROBE=1 swift test --filter WorkflowLiveProbe
zsh build-macos.sh
codesign --verify --deep --strict dist/Diorama.app
```

Live probes consume normal Codex usage and create disposable test records. The workflow probe archives its successful test conversations, pauses/clears test goals and shuts down its connection. It never acquires an unrelated conversation. Inspect the JSON statuses as well as the test exit code: unavailable structured-plan emission is recorded separately.

Evidence: [native UI observations](../evidence/workflow-ui.json), [workflow live checks](../evidence/workflow-live.json), [execution lifecycle](../evidence/execution-native.json), [imported resume](../evidence/imported-resume-native.json), [workflow harness](../Tests/DioramaCoreTests/WorkflowLiveProbe.swift), [pin persistence test](../Tests/DioramaRenderingTests/ConversationOrganizationTests.swift). See the [manual checklist](USER_TEST_CHECKLIST.md) for GUI steps.
