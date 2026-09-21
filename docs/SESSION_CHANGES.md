# Session Changes and linked PRs

Build 0.5.0 (41) adds provider-neutral review for project sessions with recorded worktrees.

- Changes opens a resizable panel beside the conversation at widths of 1000pt or greater, and replaces the conversation below that width with a Conversation return action.
- Session changes compares against the recorded starting commit. Uncommitted changes compares against HEAD. Manual and agent edits are both included.
- Local snapshots use Git only; selected-file diffs are loaded separately. Polling occurs every two seconds while the panel is visible and active, plus focus and execution-phase changes.
- GitHub PR discovery uses branch, head repository owner/name, and host. Results come from `gh` JSON, not model calls. Ambiguous matches expose a chooser. Verified links and timestamps persist in the workspace record.
- CI refreshes every 60 seconds while its view is active. Failures retain the last known result. Local revisions not included in published CI are explicitly identified.
- Fix with agent fetches bounded failure output where available and appends an editable prompt to the existing draft. It does not submit, interrupt, or switch provider.
- Project PRs aggregate linked workspaces, including retained links for cleaned worktrees. Legacy repository-wide caches are not read.

## Verification

187 tests / 48 suites passed on the final source. Release build 41 packaged successfully and passed codesign verification. Regression fixtures cover worktree isolation, committed/staged/unstaged/untracked changes, rename/deletion/conflict/binary/large-file behavior, unusual paths, disabled external diff execution, repository identity, concurrent discovery deduplication, offline Git independence, link persistence, CI states, diff line numbers, and per-session view state.

Native production-panel fixture was inspected through computer use at wide and 480pt content widths. Scope selection changed successfully. CI disclosure and Fix with agent were exercised; existing draft remained and CI context was appended. The fixture does not connect to providers or modify saved user projects. Live GitHub CI lifecycle, full-app wide/narrow transitions while an agent writes files, and a spoken VoiceOver walkthrough remain unverified. Accessibility labels and native controls are present.

## UI review

| Before | After | Why |
| --- | --- | --- |
| Repository-wide PR inbox | Session-linked PR list | Focus on the user's work |
| Provider execution diff entry point | Local worktree Changes panel | Review remains useful offline and after committing |
| CI details separate from local work | Compact PR row and expandable checks | Keep status near the work it describes |
| Diff lines wrapped at narrow widths in initial fixture | Unwrapped lines with horizontal scrolling | Preserve readable code structure |

## Limits

Read-only review: no stage, revert, commit, publish, automatic fix, or merge controls. Sessions without recorded worktrees retain their existing review experience. Diff previews are capped at 512 KB; command output is bounded and commands time out after 60 seconds. GitHub discovery considers up to 100 matching historical PRs per branch. Links are not fetched while the app is closed.
