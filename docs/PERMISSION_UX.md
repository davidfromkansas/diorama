# Permission review UX

Status: core card and review sheet implemented in 0.5.0 (37). September 21, 2026.

Verified: 173 tests across 42 suites; isolated native UI checked accept, decline, turn grants, scrolling footer, disconnected state and draft preservation. Evidence: `evidence/permission-review-ui.json`. Full-window short-height behavior and VoiceOver remain unverified. The detailed interaction section below is the design target: compact draft previews, specialized diff rendering and persistent acknowledgement history are not added by this patch.

## Core interaction

Use a full-width permission card immediately above the composer, outside the transcript scroll view. Present one pending request at a time, ordered by arrival, with “1 of 3 requests” only when needed. Preserve the user's draft and keep the conversation browsable. A permission is a decision about one action, not a change to the user's global permission mode.

The card contains: provider and waiting state; a concrete action heading; exact target or command; an agent-provided purpose only when useful; scope; and a fixed decision row. “Deny” and “Allow once” remain visible. Do not collapse the entire approval into a small scroll view. Keep the composer to a compact draft preview during blocking approvals, expandable without losing text. Nonblocking questions must not be treated as permissions or labeled “work paused.”

| Before | After | Why |
| --- | --- | --- |
| Entire request in a max-height 260 scroll view | Summary and decision row outside scrolling content | The decision never disappears below JSON |
| “Approval requested” + generic reason | “Read this file?” / “Run this command?” | Names what the user authorizes |
| Tool name concatenated with JSON | Structured target, purpose and scope | Legible without interpreting a protocol |
| All decisions vertically stacked | Deny and narrowest Allow side by side; additional scopes secondary | Fast scan without hiding the negative choice |
| Technical details expand in the same constrained panel | Resizable review sheet with a fixed footer | Long commands and diffs get usable space |

## Copy rules

Derive headings from structured tool identity, not an additional model call. Retain tool name and raw arguments for inspection. Never infer that an arbitrary shell command is safe, read-only, or limited to the displayed working folder.

| Request | Heading | Visible target / supporting text |
| --- | --- | --- |
| Read | Read this file? | Exact file path; “Allows this read only.” |
| Write/Edit | Edit this file? | Exact file path; change count if known; Review changes |
| Bash/command execution | Run this command? | Exact short command and working folder; “Runs with the requested permissions.” |
| WebFetch | Fetch this page? | Host and full URL; no claim of domain-only scope unless enforced |
| Network permission grant | Allow network access? | Actual domains, or “Network access is not restricted to a single domain.” |
| Filesystem permission grant | Allow access to these locations? | Read/write distinction and all affected paths |
| Unknown MCP tool | Allow this tool action? | Connector and exact tool name; key arguments; no guessed purpose |

Agent explanations are labeled “Agent's reason” and supplementary; they do not override the actual command or permission scope. Unknown effects are explicitly unknown. Long targets wrap, can be selected/copied, and are never hidden solely behind hover. Large scripts get an honest “Run a shell script? · 48 lines” summary and Review full command, not a misleading first-line paraphrase. Raw request JSON is a last-level disclosure in the review sheet.

## Layout and behavior

- Card: neutral opaque surface, subtle border, 16px radius, 20–24px padding. Amber belongs on the waiting indicator, not the entire background. Heading 20px semibold; body 14–15px; technical text 13px minimum, selectable, high contrast.
- Short requests fit in roughly 200–280px. Complex content opens a centered resizable native sheet, approximately 720px wide and up to 75% of window height. Only its body scrolls; heading and decision footer remain fixed. At short window heights show a concise card with Review details rather than clipping buttons.
- Review sheet shows full command and cwd, file diff when supplied, complete scope, then optional raw request. Review closes without deciding. Escape closes details only, never silently denies or allows.
- Primary narrow decision: Allow once (or Allow for this turn when that is the actual grant). Deny remains equally legible. Additional provider-supported scopes use a labeled “More options” menu with exact duration and matching rule; do not invent Always allow or session grants.
- No default Enter-to-approve: a prompt may arrive while the user is typing. Tab navigation and explicitly focused button activation work. Do not steal composer focus on arrival; announce “Permission needed” through accessibility.
- Click feedback is immediate. No decorative entry, bounce or stagger: these prompts occur frequently. Keyboard actions have no animation. Native button press feedback and visible focus are sufficient.
- On response, disable decision controls and show “Sending decision…”. Preserve the request on failure with Retry. On provider acknowledgement, replace it with “Allowed once” or “Denied” in conversation history and advance the queue. Do not imply denial stops all work; the provider decides how to continue.
- On disconnect show “Connection lost. Reconnect to respond.” Disable approval; reconcile request identity before retry. Handle resolved-elsewhere requests without sending stale answers. Never auto-approve on timeout.
- Draft and attachment state survive all decisions and review-sheet transitions.

## Implementation boundaries

1. Preserve Claude `tool_name` and `input` as structured presentation metadata in ClaudeExecutionTransport; currently they are concatenated into `command` with pretty JSON. Preserve original wire request and response semantics.
2. Add a shared permission presentation value in DioramaCore: action title, targets, exact command, cwd, agent reason, scope, details and provider-offered decisions. Adapt Codex and Claude independently; unknown schemas use an explicit generic fallback.
3. Extract PermissionReviewCard and PermissionReviewSheet from ExecutionRequestView. Keep questions and connector forms separate. Remove the outer capped approval ScrollView in ExecutionControls. Do not simply increase its height.
4. Render decision values from the existing offered decisions. Claude currently supports accept/decline in this adapter. Codex turn grants must retain their distinct scope label. Broader options require provider support, never inferred UI shortcuts.
5. Verify native UI at narrow and short window sizes, light/dark appearance, long command, multiline script, file edit, network scope, unknown tool, multiple pending requests, disconnect, slow response, double click, keyboard focus, VoiceOver and draft preservation. Test protocol routing separately so polished copy cannot change granted scope.

## Research and adaptations

- [Claude permission documentation](https://code.claude.com/docs/en/permissions): one-time and remembered decisions have different scopes; broader choices are omitted when their coverage cannot be clearly presented. Borrow explicit scopes and capability-aware choices.
- [OpenAI Codex product design](https://openai.com/index/introducing-upgrades-to-codex/): clearer tool and diff formatting, with approvals tied to execution boundaries. Borrow inspectable actions and readable details, not a generic JSON wall.
- [Cognition's Devin plan confirmation](https://cognition.com/blog/devin-2-1): asks for input when uncertain and otherwise permits asynchronous feedback. This is a plan interaction, not evidence for tool-permission semantics. Borrow clear waiting state, not automatic permission approval.

These are documented interaction principles, not a claim that this proposal duplicates today's exact proprietary app layouts.
