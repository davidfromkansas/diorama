# Diorama 0.3.19 user acceptance checklist

Use this to test the user experience, without compiling or running developer tests. Record Pass, Fail, or Not tested for each row. These are repeatable instructions. See [the recorded acceptance results](ACCEPTANCE_RESULTS.md) for completed automated, live-controller and native UI checks and the remaining gaps.

## Set up

1. Finish active work before quitting the existing Diorama app. Open this repository's `dist/Diorama.app` in Finder; use version **0.3.19, build 22**, not an older installed copy.
2. Use a Mac with the locally configured Codex CLI/account. This is a local ad-hoc-signed build, not a public notarized installer. A new tester needs their own configured account; do not share account credentials.
3. Create an empty folder named `Diorama UX Test`. Use **New Codex task** (Command-N), select that folder and choose **Prepare task**. If discovery fails, record the displayed error before trying execution tests.
4. Use the sample prompts below in this disposable folder. Model runs, reviews and active goals consume normal Codex usage. A Git-enabled disposable project is needed for meaningful code-review testing.

## First pass: a small task

Choose Plan in **Mode** (or use **Load Plan mode** if discovery has not loaded). Send:

> Plan a tiny static task-list page using index.html, styles.css and app.js. Include adding a task and marking it complete. Do not implement it yet. Include the phrase DIORAMA-TEST-42 in your final response.

After the plan arrives, select **Implement plan** or the default mode, then send:

> Implement the plan in this folder. Use local HTML, CSS and JavaScript without dependencies. Run an appropriate check and summarize the changes.

While it works, try the steering and queue checks below. If it completes too quickly, start another small task and retry; that is not a feature failure.

## All 11 checks

| # | What to do | Expected result / pass condition |
|---|---|---|
| 1 · Steering | While implementation is working, leave **Send for next run** off and send “Use the heading My test tasks.” | Correction is delivered to the current run without stopping it or creating an unintended second run. If completion races with send, rejection/uncertainty is visible and the draft is preserved. Check that the final page reflects the correction; model compliance alone is not protocol proof. |
| 2 · Plans + changes | Observe the structured checklist when emitted. After files change, open the changes inspector. | Reported plan steps update; reported files and diff are readable. No changes from an unrelated turn are presented as this turn's changes. If no structured plan event is emitted, record that part as Not tested. |
| 3 · Questions + approvals | In Plan mode, ask “Ask me a multiple-choice question about the page color before proceeding.” Answer if a native question appears. For approval, exercise a benign operation that genuinely requires approval under your existing policy. | Native answers submit and the blocking state clears. Approval offers the actual available choices/scope; denial does not authorize the requested operation. Connector forms need a configured provider that emits one. A text-only question or no approval request means Not tested for that surface, not Pass. Do not change permissions merely to force a prompt. |
| 4 · Goals + usage | When idle, **Set goal** → enter “Review the demo for keyboard accessibility” → **Save paused**. Edit it, then clear it. Open **Usage** after a run. Optionally start/resume a small goal and then use Pause/Stop. | Paused goal appears without starting work; edit and clear update it. Usage shows reported tokens/limits or an honest unavailable state. Start/resume can continue work automatically. Pause prevents future continuation; use Stop to interrupt current work. Clear alone does not stop a running turn. |
| 5 · Management | Rename the test chat, **Pin in Diorama**, archive it, switch to the archive view, then restore it. | Title updates, local pin appears, archived chat leaves the active list and can be restored. Pin persistence can be checked after a later clean relaunch; synchronization to other apps is not expected. |
| 6 · Search + history | Use **Find** or Command-F for `DIORAMA-TEST-42`; select a match. Try **Search chats** too. In a genuinely long conversation, load older history. | Find opens/highlights the matching message; global search opens the matching conversation. Older content appears progressively without losing the recent content. A short chat cannot validate long-history paging. |
| 7 · Plan mode | Use the sample planning prompt, then explicitly switch to default/Implement plan and send the implementation request. | Available Plan mode can be selected and the planning response arrives before implementation is requested. Switching modes alone does not silently submit a prompt. Unsupported mode discovery displays an error; record it as blocked, not successful. |
| 8 · Skills/connectors | Open **Skills & connectors**, inspect available skills/apps/MCP status, select an available skill or app and send a relevant prompt. Only test OAuth with a provider you intend to connect. | Picker shows available entries and selected capability chips. Opening it alone does not authenticate or modify config. Installed entries remain usable if the broader directory times out. Empty account capabilities cannot validate invocation. |
| 9 · Fork/review | When idle, choose **Fork conversation**; verify both chats remain reachable. In a disposable Git project with a change, open **Review** and choose **Review changes**. | A distinct conversation opens with inherited history. Forking does not itself start a task. Review returns findings or an explicit error/no-findings result. Files remain shared between forks; isolation is not expected. |
| 10 · Queue | While a turn works, turn on **Send for next run** and send “Then summarize the keyboard controls.” Inspect Pending messages. Separately queue a message and remove it, or press Stop before delivery. | The queued message waits rather than steering. Following successful completion it runs once. Removal prevents delivery. Stop/interruption/failure pauses automatic delivery; use explicit Run next message when appropriate. Relaunch does not automatically drain recovered messages. |
| 11 · Rich results | Ask for a local file change and a simple check. Expand the resulting tool cards. If available, separately exercise search, images, MCP and worker navigation. | Commands show output/status and available exit information; file results show readable diffs. Sources, images and worker links render when supported data is returned. Raw details remain available. A command-only task does not certify every rich result type. |

## Finish and report

After all work is idle, quit/reopen once to check history, local pins and pending-message visibility. Do not expect automatic replay or automatic queue drain. Clear test goals and remove pending test messages before closing the test conversation.

For each failure, provide the app version, priority number, exact steps, expected result, actual result, and whether work was active. Include the displayed error and a screenshot if useful; omit credentials and unrelated private conversation content. Avoid repeatedly resending when delivery is marked uncertain: inspect the pending messages/history first.

Copy this result template:

```text
Diorama version/build:
macOS version:
Priority:
Result: Pass / Fail / Not tested / Blocked
Steps:
Expected:
Actual / displayed error:
Was a turn or goal active?:
Screenshot or relevant test conversation:
```

A passed user check validates that path on that account/runtime. It does not establish full App Server parity. Developer evidence remains 117 passing tests plus the read-only probes described in [the functionality report](PRIORITIES_1_11_REPORT.md); no new app tests were run to write this checklist.
