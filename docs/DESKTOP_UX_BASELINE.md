# Diorama desktop UX baseline — proposal v1

**Current checkpoint:** the user authorized implementation, and the agreed priorities 1–11 baseline is implemented in 0.3.18. See the [full functionality report](PRIORITIES_1_11_REPORT.md), including validation and explicit limits. Approval-pending and not-started statements below are historical proposal-stage notes, not the current status.

Researched 2026-09-20 11:35 CST. **Approval pending; no app implementation in this batch.**

Research complete; implementation awaits your confirmation. This replaces the 33-option design exercise with one proposed baseline across all 11 priorities.

## Research scope
Official documentation was checked against the existing [App Server audit](APP_SERVER_AUDIT.md). This is documentation-verified behavior, not a pixel-perfect inspection of installed app builds. Current OpenAI app documentation describes Codex in the ChatGPT desktop app. Claude is rolling out unified chat/Cowork, while its Code surface has separate conventions. Availability can vary by account and version. Borrowing a Claude UX pattern does not add Claude execution to Diorama.

## Proposed baseline

### 1. Mid-turn steering

**Proposed UX:** Send a correction in the existing composer while work continues. Keep Stop separate. Default to steering, with a setting for next-run follow-ups.

**Documented evidence:** Codex documents steering versus waiting; Claude Code accepts corrections during work. Sources: [Codex follow-up settings](https://learn.chatgpt.com/docs/reference/settings) · [Claude Code desktop](https://code.claude.com/docs/en/desktop).

**Boundary / uncertainty:** Default selection is our recommendation. Preserve drafts if delivery races with turn completion.

### 2. Plan + changes

**Proposed UX:** Show a compact structured plan in the conversation. Change statistics open a right-side file list and diff, initially labeled Last turn.

**Documented evidence:** Codex has a scoped review pane; Claude Code opens file-and-diff review from change statistics. Sources: [Codex review pane](https://learn.chatgpt.com/docs/code-review) · [Claude Code desktop](https://code.claude.com/docs/en/desktop).

**Boundary / uncertainty:** Plan placement is a Diorama adaptation. A turn diff is not the entire working-tree diff.

### 3. Questions + approvals

**Proposed UX:** Extend the existing request UI with inline questions, explicit permission scope, and connector forms. Keep permission policy by the composer.

**Documented evidence:** Codex places permission modes below the composer. Sources: [Codex permission modes](https://learn.chatgpt.com/docs/permission-modes).

**Boundary / uncertainty:** Exact form layout is our adaptation. Blocking and optional requests must have different execution states; render only decisions actually offered.

### 4. Goals + usage/context

**Proposed UX:** Put the goal above the composer with pause, resume, edit and clear. Put context and account usage in a popover near the model control.

**Documented evidence:** Codex documents a goal row; Claude Code documents a usage indicator near the model picker. Sources: [Codex long-running work](https://learn.chatgpt.com/docs/long-running-work) · [Claude Code desktop](https://code.claude.com/docs/en/desktop).

**Boundary / uncertainty:** Keep goal budget, context capacity and account limits separate. No invented percentages or cost estimates.

### 5. Conversation management

**Proposed UX:** Offer rename, pin, archive and restore through conversation menus; keep archived conversations reachable from the sidebar.

**Documented evidence:** Codex documents rename, pin and archive commands; Claude Code supports rename and archive. Sources: [Codex keyboard commands](https://learn.chatgpt.com/docs/reference/commands) · [Claude Code desktop](https://code.claude.com/docs/en/desktop).

**Boundary / uncertainty:** Restore placement is a Diorama adaptation backed by the audited API. Pinning is not claimed as a shared Claude convention.

### 6. History + search

**Proposed UX:** Use Command-F for this conversation and a Search chats entry for cross-conversation search. Load older turns progressively without introducing a timeline.

**Documented evidence:** Codex distinguishes Find in chat from Search chats. Sources: [Codex keyboard commands](https://learn.chatgpt.com/docs/reference/commands).

**Boundary / uncertainty:** Pagination is implementation plumbing. Search coverage and older-runtime fallback must be labeled; tool-output search is not promised.

### 7. Plan mode

**Proposed UX:** Expose Plan through /plan and a visible composer control. Present the plan in the conversation with a clear transition to execution.

**Documented evidence:** Codex offers /plan; Claude Code exposes Plan in its composer mode menu. Sources: [Codex slash commands](https://learn.chatgpt.com/docs/reference/slash-commands) · [Claude Code desktop](https://code.claude.com/docs/en/desktop).

**Boundary / uncertainty:** Planning may read files and explore. Keep planning intent separate from permission policy; the products do not model them identically.

### 8. Skills + connectors

**Proposed UX:** Use a composer picker for skills and integrations, plus a management screen for installed capabilities, connection status and authentication.

**Documented evidence:** Codex uses $ for skills and has a Plugins directory. Claude exposes connectors through composer tools and Customize. Sources: [Codex skills](https://learn.chatgpt.com/docs/skills-and-plugins) · [Codex plugins](https://learn.chatgpt.com/docs/plugins) · [Claude connectors](https://support.claude.com/en/articles/11176164-use-connectors-to-extend-claude-s-capabilities).

**Boundary / uncertainty:** Keep Codex invocation syntax and protocol. Connection does not imply consent for every action. No new setup wizard.

### 9. Branching + code review

**Proposed UX:** Provide /fork and an appropriate conversation action that creates a new conversation. Start /review from the same diff surface and show findings with file locations.

**Documented evidence:** Codex documents /fork and /review. The new unified Claude chat experience currently does not support conversation branching. Sources: [Codex slash commands](https://learn.chatgpt.com/docs/reference/slash-commands) · [Codex review pane](https://learn.chatgpt.com/docs/code-review) · [Claude chat/Cowork rollout](https://support.claude.com/en/articles/16761823-claude-cowork-and-chat-are-one-claude).

**Boundary / uncertainty:** This follows Codex specifically. Forking a chat does not isolate files. Worktree creation, merging and branch graphs are outside this proposal.

### 10. Prompt queues

**Proposed UX:** Reuse the active composer for a clearly labeled next-run send option. Show pending delivery compactly and never silently reinterpret a steer as a queued turn.

**Documented evidence:** Codex documents follow-ups that wait for the next run. Sources: [Codex follow-up settings](https://learn.chatgpt.com/docs/reference/settings).

**Boundary / uncertainty:** The pending presentation is an adaptation. An editable, reorderable, durable queue is not verified as a shared desktop standard; defer that expanded scope.

### 11. Richer tool results

**Proposed UX:** Show typed inline summaries for commands, files, images and sources. Expand to details or raw output; open previews when supported. Retain existing canvas behavior.

**Documented evidence:** Claude Code collapses tool summaries; Claude chat can render interactive connector content. Sources: [Claude Code desktop](https://code.claude.com/docs/en/desktop) · [Claude interactive connectors](https://support.claude.com/en/articles/13454812-use-interactive-connectors-in-claude).

**Boundary / uncertainty:** Arbitrary interactive connector apps require a separate renderer contract. Do not equate basic rich results with that runtime.

## Proposed implementation sequence — only after confirmation
1. Execution foundation: priorities 1, 3 and 7; distinguish steer, interrupt, planning and permission state.
2. Work visibility: priorities 2, 4 and 11; route structured events and preserve thread/turn ownership.
3. Navigation and capabilities: priorities 5, 6, 8 and 9; check runtime support and show honest fallback states.
4. Next-run follow-ups: priority 10; validate queue support before enabling. Advanced queue editing, reordering, scheduling and restart persistence remain deferred.

## Scope to confirm
Adopt the 11 proposed experiences above, with Codex as the behavior source for App Server features and Claude as a reference for compact presentation. Defer custom approval/mission dashboards, branch graphs, worktree management, a batch queue editor and arbitrary interactive connector rendering. This is not approval to merge, publish or deploy.

## Remaining checks
Exact spacing, icons and animation in the installed official builds are unknown. Experimental App Server support must be tested against the installed runtime; documentation alone is not runtime certification. Account-specific feature availability must not be inferred from general documentation. The earlier audit remains the capability inventory; this proposal supersedes UX_OPTIONS.md as the proposed design direction.

## Status
Research and proposal: done. Native implementation: not started in this batch, awaiting the user-requested confirmation. No native app tests were run for this documentation-only update. The canvas is a schematic, not a screenshot or working app prototype.

## App Server backing clarified

All 11 priorities are App Server-backed. Diorama supplies the native interface; Claude is a UX reference, not an execution dependency. Some protocol features are experimental and require runtime validation.

| Priority | Official App Server surface | Diorama responsibility |
| --- | --- | --- |
| 1 · Steering | `turn/steer` | Composer and delivery feedback |
| 2 · Plans + changes | `turn/plan/updated; turn/diff/updated` | Checklist and diff viewer |
| 3 · Questions + approvals | `item/tool/requestUserInput; approval callbacks; mcpServer/elicitation/request` | Native cards/forms and exact offered decisions |
| 4 · Goals + usage | `thread/goal/get, set, clear; thread/tokenUsage/updated; account/rateLimits/read` | Goal row, usage popover; distinguish different limits |
| 5 · Conversation management | `thread/name/set; thread/metadata/update; thread/archive; thread/unarchive` | Sidebar menus and archive navigation |
| 6 · History + search | `thread/turns/list; thread/items/list; thread/search; thread/searchOccurrences` | Search interface and progressive loading; compatibility checks required |
| 7 · Plan mode | `collaborationMode/list; turn/start.collaborationMode` | Composer mode control; experimental support required |
| 8 · Skills + connectors | `skills/list; app/list; app/installed; mcpServerStatus/list; mcpServer/oauth/login` | Pickers, management and auth flow; typed skill/mention inputs |
| 9 · Fork + review | `thread/fork; review/start` | New conversation navigation and review findings; no automatic file isolation |
| 10 · Next-run queue | `thread/queue/add, list, start; thread/queue/changed` | Pending delivery presentation; experimental runtime verification required |
| 11 · Rich results | `Typed commandExecution, fileChange, webSearch, imageGeneration, mcpToolCall items` | Renderers, previews and expandable details |

These names come from the installed-schema/source audit. Slash commands are UI shortcuts to protocol operations, not a substitute for implementing those operations. App Server backing does not imply bundled desktop UI, arbitrary desktop tool access, or universal runtime support. Implementation approval remains pending.
