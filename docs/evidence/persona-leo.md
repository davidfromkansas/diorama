# Persona usability audit — Leo, technical lead

Date: 2026-09-22. Real native app `/tmp/DioramaPersonaQA.app`, isolated QA home; production-source audit build before parent fixes. All app interaction used `mcp__cua_repl`. No product-source edits by this agent.

## Persona and realistic tasks
Leo manages multiple small coding tasks and reviews them before publishing. He needs clear worktree isolation, drafts that survive interruptions, model choice, read-only activity, and focused PR navigation.

1. Open an existing local repository.
2. Pick a fast OpenAI model and low reasoning for a tiny task; inspect Anthropic options.
3. Start task A to add one fixture file, review its permission request, then keep an unsent follow-up draft.
4. Start task B independently, compare branch/changes, and keep another draft.
5. Switch sessions and review panels without mixing drafts or changes.
6. Inspect Plan, Steps, Agents, Timeline and scoped PR empty states.

## Observed results

- Imported `/tmp/diorama-persona-leo`. After native picker Open, repeated app-target CUA timeouts occurred. Global CUA inventory remained responsive; exact bundle targeting did not resolve it. Parent gracefully restarted QA and saved project appeared. This is an observed automation/accessibility lifecycle failure; user-visible app freeze not established.
- Model popover listed OpenAI GPT-5.6-Sol, GPT-6-Astra, GPT-5.6-Terra, GPT-5.6-Luna, GPT-5.5 and Anthropic Default, Opus, Fable, Sonnet, Haiku. Selected Luna Low for A. No provider switch was submitted.
- A prompt: `Persona QA Leo A: In this disposable worktree create leo-a.txt containing exactly alpha. Do not modify other files, commit, publish, use network, or delegate. Then reply Done.`
- First file approval allowed once. File appeared in Changes. Stopped A when it requested a second approval for the automatically injected canvas update.
- B prompt: `Persona QA Leo B: Reply B READY only. Do not use tools or modify files.` Completed with `B READY`.
- A branch: `codex/session-c7a0e574-3ebc-4908-9021-1e8418c5899c`; B branch: `codex/session-e2e97013-dc40-4571-9001-23e73bc0e1f6`. A Changes includes `leo-a.txt`; B Changes does not. Independent worktrees visibly maintained.
- Draft A `Leo draft A: review alpha before publishing.` and B `Leo draft B: compare the independent branch.` survived session switches and Changes/Activity/PR navigation without crossing sessions.
- Plan, Steps, Agents showed clear no-reported-data states. Timeline showed in-progress/completed turn and reported token usage. Inspection did not start a task. Activity selection survived project-section navigation.
- Pull Requests showed Open/Merged/Closed filters and `Pull requests linked to your sessions will appear here.`
- Normal 1170×768 window kept approval controls visible; no clipping observed in this persona's workflow.

## Findings

### L1 — Permission details omit actionable file scope (P1, confirmed original build)
Steps: A's file-change request → Review details. Expected: filename and diff/scope. Actual: title `Allow these file changes?`, generic text `Review the requested changes and scope.`, Additional options, Raw request disclosure; no filename or diff in normal view. Screenshot captured in CUA response shows empty generic sheet. AX sheet59 title,61 generic copy,64 Raw request,67 Allow once. Parent reports correlated file-scope fix already implemented; this agent did not retest fixed build.

### L2 — App-generated canvas pollutes local code review (P2, confirmed)
B requested no tools or file changes, yet Changes showed one added `.diorama/canvases/bff24944f73c1ea67de9ed45480c38cd6931ff757af9da872a731b109df88670.html` (+7−0) with full internal HTML/CSS/JS. A likewise showed canvas before `leo-a.txt`. Expected: app-owned generated state should not look like task source changes or dominate first selected diff. Parent informed.

### L3 — Transient saved/live duplication during navigation (P2 candidate)
After B finished, navigate Changes → A → B. One AX snapshot contained saved timestamped user/assistant (`B READY`) entries and the same live user/assistant entries again (AX74/76 and78/80). After Activity → Pull Requests → Sessions → Back, full tree and screenshot contained one pair. Therefore transient reconciliation duplication observed, not persistent duplicate proven. Parent informed; reproduction may depend on timing.

### L4 — Post-folder-picker accessibility target failure (investigation)
Open local repository via native picker, then CUA app AX and screenshot requests time out while global inventory works. Exact bundle retry fails. Restart recovers saved import. This matches another persona's observation. Do not equate tool timeouts alone with a user-visible freeze.

## Limitations and handoff
Two bounded live prompts used. No publishing, network operations by test agent, commits, or user projects modified. Model selection was inspected but cross-provider submission was not exercised. Keyboard text entry/coordinate click sometimes returned CUA noWindowsAvailable or stale AX; AX setValue reliably populated composer. Narrow resize and VoiceOver audio not tested. Final state: A interrupted, B completed; neither running. QA remains on Leo B conversation with unsent draft. Desktop lease released to parent.
