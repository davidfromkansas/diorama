# Diorama macOS prototype

The native SwiftUI prototype is built at `dist/Diorama.app`. Open it in Finder, or build and launch it:

```sh
zsh build-macos.sh
open dist/Diorama.app
```

Requires macOS 14 or later. This local build targets Apple Silicon and is ad-hoc signed; it is not notarized for public distribution. Building requires Xcode with Swift 6.2 or later (tested with Swift 6.3.1). The native app does not depend on Python or a web server. Codex execution uses the locally configured Codex account.

### Claude Code Desktop observation

Local conversations from Claude Desktop’s **Code tab** are discovered through Desktop metadata and matched to local Claude transcripts. Older readable history and selected conversation updates appear automatically; Desktop imports are view-only. Connections includes a separate Desktop reporter setup and hook-delivery status. Chat, Cowork, cloud and SSH sessions are excluded. See [setup, storage details and verification limits](docs/CLAUDE_DESKTOP_OBSERVATION.md).

### Acceptance-tested update (0.3.19)

Build 22 fixes asynchronous file pickers, normalized-folder selection for new tasks, and canvas instructions leaking into displayed titles. The final suite passes 120 tests; real execution, approvals, resume, goals, queue, search, skills, fork and review paths were exercised. See [the acceptance report](docs/ACCEPTANCE_RESULTS.md) for native UI results and remaining live-provider gaps.

### Priorities 1–11 implemented (0.3.18)

The agreed desktop UX baseline now includes steering, plans/diffs, richer questions and approvals, goals/usage, conversation management, message search/paging, real Plan mode, skills/connectors, forks/reviews, next-run messages and rich tool results. See the [full functionality report and limitations](docs/PRIORITIES_1_11_REPORT.md). All 117 tests pass; the production bundle is build 21. This completes the scoped baseline, not full App Server parity. Pins are local, advanced queues/worktrees remain deferred, and live mutation verification is incomplete.

### Live HTML view (0.3.13)

Choose **HTML view** beside Conversation and Activity to see an agent-maintained page for the conversation: goal, diagram, plan, status, decisions, changes, and next action. Diorama provides the agent with the page path on every new Codex turn, and the view updates when that file changes. Pages persist in the working folder under `.diorama/canvases/`. Existing conversations start with a placeholder until their next agent update; opening the tab never starts a model turn. See [HTML_VIEW.md](HTML_VIEW.md) for the update contract and limitations, and [CONVERSATION_ITEMS.md](CONVERSATION_ITEMS.md) for the version-pinned protocol reference.

### Inline tool images (0.3.12)

Codex `imageView` items now display a local image preview directly in the conversation, in both App Server history and live turns. Click the image to open it at full size, or use **Show in Finder**. Raw metadata remains under **Image details**. Missing, unreadable, or oversized files show an unavailable placeholder. Previews use thumbnails capped at 1,200 pixels and accept files up to 20 MiB. They reference the current local file, so later edits to the same path can change what an older image event displays. Remote URLs, arbitrary paths in message text, and local JSONL fallback tool calls do not automatically render images.

### Priorities 1–3 review build (0.3.17)

The composer can send corrections to a working Codex turn without stopping it. Structured plan events now render as a checklist; reported last-turn changes open a file/diff inspector. Requests distinguish optional questions from blocking input, preserve exact structured approval rules, and render supported MCP connector forms and URL flows. See the [review checklist and validation evidence](docs/PRIORITIES_1_3_REVIEW.md). Priorities 4–11 were subsequently implemented in 0.3.18; see the full report above.

### Run and continue Codex tasks in Diorama (0.3.1)

Use **New Codex task** (⌘N), choose an existing working folder, enter a prompt, and select a model/reasoning effort from the provider catalog. **Prepare task** creates an empty conversation and shows its effective permissions, approval policy and model. **Send prompt** starts execution using your existing Codex account and usage. No worktree is created automatically.

Diorama-owned tasks stream replies and tool activity, accept follow-ups, and show approval requests and questions with explicit response controls. **Stop turn** requests interruption; **Stop remaining terminal commands** also handles commands that survived a turn interruption. Closing the window keeps work running. Quitting checks owned tasks and terminal processes, offers **Keep running** or **Stop tasks and quit**, and waits for confirmed shutdown. No background launch service is installed.

A private local ownership journal saves only task IDs, titles, folders and explicit parent IDs. Restarting never replays a prompt. For eligible conversations, Send connects automatically. Ambiguous submissions are not automatically retried. Eligible imported Codex conversations show a composer immediately; Send uses the official `thread/resume` API with the same conversation ID before submitting. A writer conflict leaves history readable and offers **Retry**. Successful resume opens the composer immediately; effective settings remain under **Execution details**, and only **Send** starts a turn. Internal reviews, subagents, archived records, unavailable working folders, recorded in-progress turns and active goals are not automatically resumed. Restore archived conversations or resolve work in the original client first. Desktop-specific client tools may be unavailable and are never executed by Diorama. Claude execution is not implemented.

Execution has a separate App Server connection from the read-only history transport. New tasks route approvals to the user without changing global provider settings. Unsupported client-executed tools are rejected. Live display is bounded to 500 entries and 256 KiB per entry; turn history remains available through the conversation reader. Pausing transcript observation does not pause an executing task.

Verification: `swift test` exercises deterministic execution and observation regressions. The opt-in `DIORAMA_EXECUTION_PROBE=1 swift test --filter ExecutionLiveProbe` creates disposable tasks, consumes normal Codex usage, and explicitly answers only synthetic test requests. Measured results and remaining gates are in [COMPATIBILITY.md](COMPATIBILITY.md).

### Automatic import

The native interface is organized by **actual working folders**: choose a folder in the sidebar, then a session in the middle column, then read its transcript. Codex and Claude Code sessions sharing the same absolute working path appear together. Full paths distinguish folders with identical names. Nested working folders and separate worktrees remain separate; Diorama does not guess a repository root or recreate source-app sidebar projects. Missing/relative paths appear under “Unknown working folder.” Search and provider filters apply across these groups. Grouping uses standardized recorded paths; it does not resolve symlink aliases or require historical folders to still exist.

On launch, Diorama lists Codex conversations through a local `codex app-server --stdio` connection. Both active and archived listings are paginated, with all documented source kinds explicitly requested. DB-only discovery avoids requesting transcript-index repair. Provider names take precedence over prompt-derived titles. The existing local scanner supplements records missing from the API and supplies activity and classification metadata, including `guardian_review` when App Server omits it. Claude Code remains on its local adapter.

Codex must be installed at `~/.local/bin/codex`, `/opt/homebrew/bin/codex`, or `/usr/local/bin/codex`. Sources remain `~/.codex/sessions`, `~/.codex/archived_sessions`, and `~/.claude/projects`; `CODEX_HOME` and `CLAUDE_CONFIG_DIR` override these roots when supplied to the app process. Finder-launched apps typically do not inherit shell configuration.

The library reconciles every 15 seconds and responds to directory changes; selected history refreshes every two seconds. Search covers title, working directory, and session ID. Provider filters, manual refresh, pause observation, optional source-file reveal, and a connections panel are included. There is no lunar-base/3D scene yet.

Codex history uses `thread/read` without resume or event subscription. The transport allows only initialization, listing, and reading; it never starts model turns, answers approvals, or executes client tools. The App Server process may maintain its own runtime metadata; Diorama does not change provider settings or source transcripts. Missing CLI, connection failure, unknown history items, empty turns, or a missing latest recorded assistant reply cause an explicitly labeled local-file fallback. If both sources fail, the last successfully read selected history remains visible with a warning. App Server runtime status is never interpreted as global activity.

Conversation bodies are loaded only on selection. App Server responses are capped at 64 MiB and requests have a 12-second timeout with a 15-second reconnect delay. File fallback displays entries from the last 16 MiB. The visible limit starts at 300 and can increase to 5,000. Unknown session types remain visible; reasoning records are excluded. Connections reports the current source and fallback reason; each transcript identifies its actual source. Unified Claude Desktop remains unsupported.

Same-conversation resume was live-tested between independent clients with writer rejection, explicit retry after owner exit, retained context, interruption and return to another client. An actual Desktop exit followed by native Diorama resume and context retention has now passed, and Desktop reopened automatically. A manually sent return message in Desktop recalled both the Desktop marker and the marker added through Diorama, verifying the full same-conversation round trip for this disposable test. That automated Diorama leg used its native controller. A subsequent user-operated UI test also passed: Retry, settings review and Send produced the expected context-retaining response in the same conversation, independently confirmed in the transcript. It never closes Desktop or uses archive/fork/lock-removal workarounds. Run `DIORAMA_RESUME_PROBE=1 swift test --filter ImportedResumeLiveProbe` only for authorized disposable tests using normal Codex usage.

### App Server validation

The native integration was tested against Codex CLI 0.153.4. Run deterministic regression tests with `swift test`. The opt-in read-only check lists local metadata and reads only the archived disposable round-trip test conversation:

```sh
DIORAMA_APPSERVER_PROBE=1 swift test --filter AppServerHistoryTests.designatedLiveHistoryAndDiscovery
```

The live check also validates the designated Diorama folder's main conversation and internal-review classification. It does not send prompts, resume tasks, or exercise execution controls. See [COMPATIBILITY.md](COMPATIBILITY.md) for evidence and limitations, and the [App Server documentation](https://learn.chatgpt.com/docs/app-server) for the protocol.

### Conversation organization

Internal Codex approval reviews (`thread_source=guardian_review`) are now hidden by default. Use **Show internal sessions** to reveal them; this preference is saved locally. Folder summaries count conversations, subagents, hidden reviews, and unknown types separately. Unknown records remain visible. Work subagents are indented beneath their parent within the folder when an explicit, same-provider relationship resolves; unlinked records say **Subagent · parent unknown**. No source files are changed.

Classification details in the transcript header expose the metadata evidence and recorded parent ID. Titles come from recognizable user requests; missing titles say **Untitled conversation** plus a short ID. Internal reviews have a fixed **Internal approval review** title. **Last turn finished** replaces the ambiguous Completed label, and does not imply the project is finished.

System/developer messages, Claude messages explicitly marked `isMeta`, and recognized Codex environment/plugin/AGENTS instruction envelopes appear as collapsed **System context**. Mixed user text is retained. Unknown XML, inline examples, incomplete envelopes, and fenced examples remain user text. Recognition of legacy injected envelopes is deliberately narrow and version-dependent. Tool records remain compact and expandable. Thinking and encrypted reasoning records are still omitted.

### Markdown rendering

Native user/assistant messages and expanded context/tool results render GitHub-flavored Markdown, including headings, emphasis, links, tables, lists, quotations, and fenced code. Titles show readable text without Markdown delimiters. Tool calls and JSON payloads retain literal formatting; every entry offers a **Raw text** disclosure. Images appear as placeholders without network requests. Web/email links open only when clicked. Code wraps within the transcript pane. The earlier browser diagnostic remains a raw-record inspection tool.

Rendering uses pinned MarkdownUI 2.4.1; the first build downloads dependencies. Dependency licenses are included in the app bundle.

### Native tests (current)

```sh
swift test
```

The Swift Testing suite covers discovery, grouping, classification, parent relationships, filtering and selection, injected context, partial records, source preservation, title formatting, structured payloads, and a native Markdown rendering fixture. The fixture writes `/tmp/diorama-markdown-preview.png` for visual inspection. A read-only acceptance check against the actual Diorama records confirmed one visible conversation and one hidden internal review, with context labeled separately. The rebuilt app passes signature verification. The Python diagnostic tests below remain independent.

## Earlier access diagnostic

The earlier local, read-only feasibility tool is retained as a Python diagnostic server with a browser viewer. No external packages or account are required for that viewer. Actual probe agent execution uses the source client's existing account.

## Run on this Mac

```sh
cd /Users/david_lietjauw/Documents/ChatGPT/Diorama
python3 diagnostic.py --manifest .local/manifest.json
```

Open the complete loopback link printed by the command. The random access token is in the URL fragment and is removed from the address bar after loading. Keep the terminal open; Ctrl+C stops the observer without stopping agents. The default chooses an available port. Pass `--port 8765` for a fixed port if free.

The existing `.local/manifest.json` contains only four designated sources: this Codex desktop task, the isolated Codex CLI probe, and two Claude CLI probes. `.local/` is git-ignored because test transcripts, paths, and server access tokens are private. Never publish it.

## Observe another designated transcript

Create a manifest with exact absolute paths:

```json
{
  "sources": [
    {
      "provider": "codex",
      "client": "Codex CLI — supply tested version",
      "label": "My designated test session",
      "path": "/absolute/path/to/designated-transcript.jsonl"
    }
  ]
}
```

`provider` accepts `codex`, `claude`, or `hooks`. `client` and `label` are operator-supplied descriptions, not automatic client detection. `parent_id` is optional, and must be supplied from verified parent-agent metadata, never Claude's `parentUuid` message pointer. A hook file must contain events for **one session only**. No hooks are installed or enabled by this project. Restart the observer after editing the manifest.

The observer never scans history folders. It polls allowlisted JSONL files, waits for complete lines, and reparses after detected replacement/truncation. Each poll handles at most 5,000 records; lines over 4 MiB stop that source with a visible error. The viewer retains the latest 2,000 normalized entries per source. It omits system/developer instructions, reasoning records, thinking blocks, and encrypted payloads. Tool output is displayed as text and may contain source code or other private information.

Status is the **last recorded state**, not a heartbeat. In particular, Claude transcript text alone is not interpreted as working/completed. Hook status mapping is fixture-tested but not validated against a live installed hook. Subagents are not automatically discovered. Structured diffs are not rendered; available patch tool calls appear as text. Attachments and unknown record types are not fully rendered. Unsupported capabilities remain unavailable.

## Verification and probes

```sh
python3 -m unittest -v test_diagnostic.py
python3 probe_appserver.py EXACT_TEST_THREAD_ID
```

The first command exercises parsing, partial UTF-8 writes, reconnection, rotation, malformed/missing files, exclusions, and HTTP authorization. The HTTP test needs permission to bind a loopback socket.

The App Server probe issues only initialize/initialized and `thread/read`; it does not list, start, resume, or interrupt tasks. App Server itself may write its usual runtime metadata. Output records field names and item counts rather than conversation text.

`live_probe.py` is an **active test harness**, not part of the observer: it resumes the manifest entry labeled `Codex CLI isolated probe`, asks for a three-second sleep command and a fixed reply, watches its transcript concurrently, recreates the observer mid-run, and saves a content-free summary under `.local/evidence/`. This incurs a normal Codex model request. Run it only against a designated disposable test session.

See [COMPATIBILITY.md](COMPATIBILITY.md) for measured results, blockers, and remaining release gates. Sanitized probe evidence is in `evidence/`.

## Activity and optional reporting

Every imported session is now observed for recorded activity, even when unselected. The sidebar displays last-reported status and per-folder conversation/subagent counts. Use **Working** or **Needs attention**, open the **Attention inbox**, or select **Activity** beside **Conversation** for a compact timeline. Matched tool operations show outcomes and durations; incomplete ones say **No completion observed**. Approval/input requests remain **Resolution unverified** until matching evidence resolves them. Observation health is separate from agent status.

**Connections → Enable activity reporting…** previews optional provider hook configuration before applying it. Diorama backs up settings, preserves unrelated hooks, and provides removal. Review hook trust and restart the source client when required. Setup currently gates on inspected Codex 0.153.4 and Claude Code 1.0.108 profiles; their verified capabilities differ. See the September 18 section of [COMPATIBILITY.md](COMPATIBILITY.md). Normal provider settings were not modified during development.

The bundle includes `DioramaReporter`, copied to a stable Application Support location when enabled. It never depends on the GUI or returns approval/continuation decisions. It stores limited tool names, paths, command previews, and error excerpts locally for seven days / 50 MiB; these can contain sensitive information. **Clear activity history** removes retained hook records, not original transcripts. Neither image hosts nor telemetry services receive this data.

Run `swift test` for state ordering, long-running turns, incremental files, configuration merging/removal, privacy, retention, UI filters, and native filesystem notification coverage. `python3 scripts/probe_reporter.py` tests the reporter and a disposable, disconnected Claude invocation without using normal credentials/settings. The optional `DesignatedActivityProbe` test requires `DIORAMA_PROBE_TRANSCRIPT` and writes content-free evidence to `DIORAMA_PROBE_OUTPUT` when supplied.

## Conversation interface — 0.3.2

The conversation uses a compact header, a centered reading column, right-aligned user bubbles, and unboxed assistant replies. Tool activity and system context expand inline. Conversation metadata and transcript access are under the info button; right-click a message to copy it or inspect its raw text.

For conversations connected through Diorama, the rounded multiline composer stays below the transcript, with model/effort choices and Send. Return inserts a newline; Command-Return sends. Provider approvals, interruption and writer-conflict checks still apply. The live-turn versus saved-history switch remains explicit.

Validation: the existing 56-test suite passed (opt-in live probes skipped); an additional offline native rendering fixture was inspected at 520- and 800-point widths. No live model prompt was sent for this visual update.

### Connection states — 0.3.4

Previously connected conversations now use the same continuation controls as other imports: **Not connected** and **Continue here**, followed by the shared lock/Retry card if the provider reports an active writer. Previous-run diagnostics remain under Connection details instead of appearing as an orange error. As of 0.3.5, reconnection opens the composer directly and never sends a prompt automatically. The existing execution and rendering checks passed (12 tests).

### Composer-first continuation — 0.3.6

Eligible Codex conversations show the composer immediately. Send connects/resumes and submits the message. Writer conflicts preserve the draft in the current conversation view and show the lock card; explicit Retry attempts acquisition and sends only after success. Uncertain submission outcomes require a separate history/reconnection check and are never automatically resent. Archived/internal/subagent restrictions and provider approvals remain enforced. Fifteen execution/rendering tests passed, including new acquire/send ordering, conflict/retry and ambiguous-submission checks.

### Attachments (0.3.7)

Codex composers support **Attach files** (native macOS picker) and Finder file drops, with removable attachment chips. Image-only and file-only messages are supported. PNG, JPEG, WebP, and GIF files use official App Server `localImage` inputs; other files are explicitly labeled local file references and sent as JSON-quoted paths in text input. Codex reads referenced files using its existing tools and permissions; this is not a generic upload API and does not grant new filesystem access. Files must remain available until sent. Up to 20 files, 20 MiB per image; unsupported image formats require conversion.

Attachments remain in the current composer draft on writer conflict or failed sending, and clear after acknowledged submission. Uncertain submissions are never automatically replayed. Clipboard-only images, promised files from other apps, folder drops, persistent drafts across navigation/restart, and Claude sending are not included. Finder URL drops are implemented; interactive picker/drop smoke testing remains manual.

Reference: [Official Codex App Server input types](https://learn.chatgpt.com/docs/app-server#turns).

### Approval review control (0.3.8)

The composer’s shield control offers **Use current Codex settings**, **Ask me**, and **Review automatically**. Starting/resuming no longer forces `approvalsReviewer=user`. Codex supplies the effective settings; this does not guarantee all Desktop-only preferences are available to an independent App Server. The reported reviewer is shown after connection.

An explicit choice is sent through official `turn/start.approvalsReviewer` on the next message and remains effective for subsequent turns. “Use current” omits the override; it does not reset a previously selected mode. No global configuration, sandbox boundary, or approval policy is changed. Controls are disabled during an active turn; pending approval requests still require their ordinary resolution. Existing conversations previously changed to manual review can select **Review automatically** explicitly.
