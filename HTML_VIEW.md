# Conversation HTML view

HTML view sits beside Conversation and Activity. It shows one self-contained, agent-maintained document for the selected conversation, with the composer and native approval controls still available below it.

## The update loop

1. Diorama creates a starter page on the first send or first visit to HTML view. Existing pages are never overwritten by the app.
2. Every Codex turn sent through Diorama includes a separate text block identifying the file and asking the agent to rewrite it after meaningful batches and before its final reply. The user's original message is unchanged; the maintenance block appears as collapsed system context in Diorama.
3. The agent reads the previous page and updates the same file. A sibling temporary file followed by an atomic rename is recommended.
4. The selected HTML view checks the file every second and displays changed, complete content. No model call is made by opening or refreshing the view. A partial write, missing file, or invalid update leaves the last successfully read page visible with an error notice.
5. The document persists across app restarts. The toolbar separately displays the file timestamp and the attached execution phase. Page contents are an agent-authored report, not a guarantee that an agent is still running or that a goal is complete.

The HTML file contains `<meta http-equiv="refresh" content="3">` for standalone browser viewing. The embedded renderer removes that tag from its in-memory copy, uses file-change detection, and preserves the scroll offset across document replacement. This avoids flicker and repeated reloads while reading. Pause updates freezes the embedded view only; it does not pause the agent.

## Storage

`<working folder>/.diorama/canvases/<SHA256(provider + ":" + sessionID)>.html`

The hash gives every conversation a stable path and separates Codex/Claude IDs without trusting IDs as filesystem paths. Agents can write inside the existing working folder with ordinary tool permissions. The feature does not expand writable roots, alter global provider settings, create AGENTS.md, or publish the page.

The app rejects symlinks in the canvas storage path and limits loaded pages to 2 MiB. Pages are private working artifacts; avoid committing them. Diorama's own repository ignores `.diorama/canvases/`; other project ignore files are not silently changed.

If Diorama cannot prepare the page for a turn, it shows an HTML-view notice and still sends the user's task. An unavailable canvas does not block ordinary conversation work.

## Page contract

- Goal
- Current state
- Flow / architecture: labeled boxes and arrows, including an accessible description
- Plan: ordered next batches
- Status: done / in progress / blocked, backed by evidence
- Decisions + open questions
- What changed since last update
- Next action
- Visible update timestamp

Prefer diagrams and tables. Use progress bars only when there is a real denominator. Replace obsolete content instead of appending a history log. Chat should briefly identify the update and ask a question only when an answer is needed. Keep actual approvals in Diorama's native controls.

## Embedded rendering

The WebKit view uses an ephemeral data store and a sandboxed `srcdoc` frame with scripts permitted but no same-origin access, forms, popups, or native message handlers. Content Security Policy blocks external resources and network requests. CSS, inline SVG, data images, and inline JavaScript can render. The parent accepts only bounded scroll and disclosure-state messages from its own child. Expanded/collapsed `<details>` elements with stable IDs retain their state across file updates; this is in-memory viewer state, not a change to the saved HTML. Native navigation is restricted to the owned `about:` documents.

Open in browser opens the original file, including its refresh tag, using the system browser's normal security behavior. The embedded sandbox does not carry over to an external browser.

## Existing conversations and other clients

Old conversations get a starter page when HTML view is first opened. They are not automatically summarized by a background model request. Continue the conversation through Diorama to have Codex populate and maintain the page. This implementation also seeds the current development conversation as an example.

An already-running turn does not receive new instructions retroactively. For agents running elsewhere, use **Copy agent instructions** from the HTML view menu and send those instructions in that client. Claude history can have a page, but Diorama does not start Claude turns. Agent compliance with the update contract is prompt-based; the viewer cannot force a file rewrite or infer architecture/decisions from raw tool logs.

## Protocol reference

[CONVERSATION_ITEMS.md](CONVERSATION_ITEMS.md) inventories all item variants, user input variants, server notifications, and server requests in the installed Codex schema, with suggested visual treatments and a regenerable JSON inventory.

## Visual design (0.3.14)

The starter page uses an editorial hierarchy: a large serif goal, ordered milestone rail, dominant relationship diagram, cobalt next-action panel, compact evidence rows, and expandable rationale. It adapts to light/dark appearance and narrow viewports. Semantic state labels accompany color; keyboard focus remains visible. Empty starters do not imply work has begun.

Agent instructions treat the section list as an information checklist, not a fixed card layout. They ask for task-specific comparisons, annotated diffs, dependency diagrams, timelines, and evidence-backed charts. Supporting detail belongs in disclosures with stable IDs. Any local editing interaction must offer selectable text to paste back into chat; it cannot send messages itself.

The design was informed by [Thariq’s HTML examples](https://thariqs.github.io/html-effectiveness/) and the [author’s published article](https://claude.com/blog/using-claude-code-the-unreasonable-effectiveness-of-html). The supplied X permalink returned 403; the published counterpart was used. A shell-generated random seed inspired paired rhythm, asymmetric composition, and an ivory/ink/cobalt palette. The seed is not part of any rendered artifact. The [imagegen concept](artifacts/html-view-design/concept.png) and [generation prompt](artifacts/html-view-design/prompt.md) record the visual exploration; the implementation uses real HTML/CSS, not a flattened image.

Existing agent-authored pages are never restyled automatically. This development conversation and the demo are updated; new conversations use the new starter and future Diorama turns receive the improved guidance.

## Activity and the first update (0.3.15)

New starter files are explicitly empty: a task title, a short waiting explanation, and space for the first real update. They no longer render placeholder architecture, milestones, or decisions. The embedded viewer sends its actual execution phase to the child via a one-way `diorama-execution` postMessage. Phase-only changes do not replace the frame or require an agent file write. Starter copy distinguishes submission, active work, approval, and input waits. Disconnected, failed, and finished turns never imply ongoing work.

A persistent viewer activity dot and the starter’s three marks use a slow 1.8-second opacity/transform cycle solely as an indeterminate activity signal. A 200ms opacity cue acknowledges file updates. Text remains stationary. Reduce Motion disables repeating movement. The viewer indicator works with existing pages; agent-authored node accents can opt into the same phase message and must default to inactive outside Diorama. A running signal means the execution is active, not that private model reasoning is observable. Pause updates freezes file content, not the real execution signal.

Verification covers phase-only changes without a frame rewrite, active/approval starter copy, stopping activity for input/terminal/disconnected states, existing sandbox restrictions, file updates, and disclosure preservation. Previously authored pages, including older saved starters, remain untouched.

## Contextual loaders (0.3.16)

Six lightweight patterns inspired by Generative Loaders are supplied by the embedded viewer, with no React dependency: empty-state orbit, current-action signal bars, active-step dots, mapped-node halo, pending-image tiles, and a 200ms changed-section dissolve. Continuous indicators use a 1.8-second cycle for indeterminate activity. All respect Reduce Motion; content stays readable and stationary.

The execution payload includes `activities: [{id, tool, label, target}]`. Only unfinished tool calls in the attached current turn appear (up to eight concurrent calls). Completion, failure, approval, input, and disconnected states remove contextual activity. Tool labels describe observed calls, not inferred private reasoning; command details are available on hover over the current-action label.

Agent-authored HTML opts into contextual markers:

```html
<li data-canvas-loader="step" data-canvas-activity="commandExecution">
  <span data-canvas-step-marker>3</span> Verify the result
</li>
<div data-canvas-loader="halo" data-canvas-activity="fileChange">Renderer</div>
<div data-canvas-loader="image" data-canvas-activity="imageGeneration"
     data-canvas-call="actual-call-id"></div>
```

Use comma-separated exact tool names, optionally narrowed to a call ID. `any` is reserved for an overall agent-work step or node; image regions cannot use it. Existing images suppress pending tiles. Supply stable section IDs for changed-section detection. The native wrapper compares section markup on file replacement, then reveals only changed sections. Phase-only updates leave the document intact. Arbitrary old pages gain the global activity signal and section reveals automatically; contextual markers require the agent to map the actual task using these attributes. New turn instructions describe this contract.

Patterns reference: https://generativeloaders.com/docs . This is an independent dependency-free implementation, not the React package.

## Observed tasks (0.3.17)

HTML view now also consumes the selected task’s local activity summary when no owned execution connection exists. Timestamped working activity within 90 seconds drives the orbit and signal with an explicit “Recent activity” label. The empty state says “Agent activity detected…” rather than claiming an execution connection. Approval/input/terminal reports stop working motion. Missing timestamps, read errors, and stale activity do not animate; expiry is checked each second while the view is open, even when canvas file updates are paused. Attached execution state remains authoritative. An observed task with no recent records can still be working; Diorama cannot infer that from an unchanged file.
