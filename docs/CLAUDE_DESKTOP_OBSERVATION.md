# Claude Code Desktop observation

Diorama discovers local Claude Code Desktop sessions automatically, including older readable history. Desktop sessions are view-only: continue, send, steering, goal/review mutations and approval handling remain in Claude Desktop. Chat, Cowork, cloud and SSH sessions are outside this integration.

## Discovery and identity

The macOS adapter inspects `~/Library/Application Support/Claude/claude-code-sessions/` for `local_<UUID>.json` metadata. This is an observed, version-tested storage format, not a promised Anthropic public API. It decodes only session identity, working directory, title, archive status and last activity time. Unsupported/unreadable metadata generates diagnostics in Connections.

Desktop's `cliSessionId` links to the embedded `sessionId` in the existing Claude JSONL transcripts under `~/.claude/projects/` (`CLAUDE_CONFIG_DIR` overrides the Claude configuration root). The metadata's `sessionId` identifies the Desktop UI session. Diorama keeps the existing `Claude Code:<cliSessionId>` identity, so previously imported transcripts are not duplicated. Desktop `cwd`, rather than `originCwd`, determines grouping, preserving separate worktrees. A folder name such as `Claude` has no special meaning.

Missing transcripts remain visible with an unavailable message. An unrelated transcript is never substituted based on a similar title or folder. A matched Desktop session and its subagents are marked Desktop-origin; shared Claude transcripts without Desktop evidence retain unknown origin unless a CLI hook establishes it.

## Live updates and setup

Transcript viewing needs no hook installation. Discovery responds to changes and reconciles every 15 seconds; selected history refreshes every two seconds after the source writes it. Pausing observation pauses both. Closing or restarting Diorama does not control Desktop sessions.

For activity reporting, open **Connections → Claude Code Desktop → Enable Desktop activity reporting…**. Review and apply the preview, then follow Claude's workspace-trust/restart flow. Configuration is shared with Claude Code CLI. Reapplying either setup preserves the other installed Diorama event types and unrelated settings; removing the shared reporter removes it for both clients. Installation makes a backup and checks for concurrent settings edits.

Hook `session_id`, `transcript_path`, `cwd` and receipt time are retained in `~/Library/Application Support/Diorama/ClaudeSessions/`, separately from the seven-day activity store. Clearing activity does not erase discovery. Records contain paths and IDs, not prompt or response bodies. The reporter remains bounded, emits no approval decisions, and does not require the GUI. Hook-discovered files must be inside the configured Claude transcript or Desktop storage roots and match their embedded identity. Remote/SSH hook environments and subagent hooks are not registered as main sessions.

Connections separates reporter configuration, last hook observed, and readable-history availability. A reported event is not an authoritative current-status signal. A supported setup profile is scoped to Desktop version independently of the installed CLI version.

## Validation

The installed Desktop version is 2.7032.0. Metadata field structure and links to local transcript identities were inspected without exporting conversation contents. The read-only adapter probe found 282 Desktop-origin records, including subagents, with 263 readable transcripts on September 25, 2026. This is a point-in-time local result, not a guarantee for every account or installation.

The complete offline suite passes 242 tests. Eleven Desktop-specific checks, including the opt-in read-only local probe, pass. The reporter executable also passed a synthetic stdin-to-activity/registry test with neutral output (see `evidence/claude-desktop-reporter-fixture.json`).

Fixture tests cover older/new/resumed discovery, stable IDs, archive state, duplicate metadata, worktree grouping, app-reader reconstruction, partial writes, missing/mismatched transcripts, remote exclusions, symlink escapes, reporter registry retention and shared configuration. Controller tests reject Desktop resume/send before any transport call, including stale journal-style identities. A native rendering fixture checks the view-only branch even when an attached-task record exists.

On September 25, 2026, the user created a local Code conversation titled Testing in their selected home directory. Its Desktop metadata identity matched the readable JSONL transcript and Diorama discovery registry. The transcript contained the user test message and the assistant response shown in Desktop. Diorama received SessionStart, UserPromptSubmit and Stop events for the same session. This verifies real Desktop hook delivery outside the disposable test folder. A subsequent native UI retry verified Testing in Diorama search and opened its transcript: both messages, the Claude Code Desktop label and the view-only notice were present, with no composer. Sending a follow-up in Claude remained blocked by its input automation returning noWindowsAvailable, so automatic refresh after a further message is not yet verified. Tool/approval activity, resume, background operation and restart verification remain pending; these successes must not be inferred from fixture tests.

Read-only verification command:

```sh
DIORAMA_DESKTOP_READ_PROBE=1 swift test --filter ClaudeDesktopHistoryTests
```

References: [Desktop shared configuration](https://code.claude.com/docs/en/desktop#shared-configuration), [hook input fields](https://code.claude.com/docs/en/hooks#common-input-fields).

The rebuilt native app was launched and its Connections panel confirmed the same discovery counts. Shared Claude reporter hooks were installed through the native preview/apply flow, with a settings backup. The preview now displays only Diorama-owned hook entries; unrelated provider settings are preserved without being displayed. A final targeted run passed 34 tests after that change.

A subsequent live retry successfully sent follow-ups in the same Desktop conversation. It exposed a stale working-folder selection that caused discovery reconciliation to switch away from imported history. Imported navigation now synchronizes the working folder; a regression test covers reconciliation. After rebuilding, strict signature verification and relaunch, the selected Testing transcript automatically displayed DIORAMA_REFRESH_FIXED_OK without reselecting or manually refreshing. Refresh latency was not precisely measured. Tool/approval activity and restarting Claude remain unverified.
