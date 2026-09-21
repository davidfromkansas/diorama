# Diorama UX options — 11 priorities, 33 concepts

Created 2026-09-20T02:33:03+00:00. Visual companion: the conversation’s live HTML view. All UI examples are illustrative proposals, not implemented features.

The original audit is [APP_SERVER_AUDIT.md](APP_SERVER_AUDIT.md). Goal controls are folded into priority 4; all five requested additions are explicit priorities 7–11.

## Recommended combination

- **1. Mid-turn steering: A — The composer stays open**
- **2. Native plan + changes inspector: A — A collapsible right inspector**
- **3. Questions, approvals + connector forms: B — An attention inbox**
- **4. Goals, usage + context: B — A mission inspector**
- **5. Conversation management: A — Sidebar actions**
- **6. History pagination + message search: B — A global search workspace**
- **7. Plan mode: A — A mode switch in the composer**
- **8. Skills + connectors: A — An @ picker in the composer**
- **9. Branching + code review: A — Message actions + a review entry point**
- **10. Prompt queues: A — A queue just above the composer**
- **11. Richer tool results: A — Compact inline result cards**

## 1. Mid-turn steering

Correct the agent while it works, without interrupting the task.

Protocol boundary: Use turn/steer with the expected active turn ID. If the turn ends first, preserve the draft and offer a new turn; never silently resend.

### A. The composer stays open (recommended)

Keep the familiar message box available during work; its primary action becomes “Send correction”.

**Flow:** Type in composer → Send correction → See acceptance inline.

**Best for:** Lowest learning cost; stays inside the conversation.

**Tradeoff:** The action label must make steering versus a new turn unmistakable.

**Behavior:** Show “Sending…” until acknowledged, then “Added to current turn”. Stop remains separate. If delivery is uncertain, keep the draft and show an unresolved state.

### B. Attach a correction to a step

Target a visible plan step or tool action and leave a short contextual instruction.

**Flow:** Select a step → Add correction → Show linked reply.

**Best for:** Precise when several things are happening.

**Tradeoff:** Can imply finer execution control than the server provides.

**Behavior:** Send the selected step’s visible label as context with the correction. The link is a UI reference; it does not cancel or surgically edit that one operation.

### C. A dedicated direction drawer

A persistent “Adjust direction” control opens a small instruction drawer beside current work.

**Flow:** Open direction drawer → Write one adjustment → Review receipt.

**Best for:** Separates task controls from conversational follow-ups.

**Tradeoff:** Adds a second writing surface and takes more room.

**Behavior:** Keep one correction per submission and show pending/accepted receipts. An inactive turn switches the drawer to “Send as next message”, with user action required.

## 2. Native plan + changes inspector

Understand what is planned and what actually changed while the conversation continues.

Protocol boundary: Plan steps and turn diffs come from structured events. Preserve per-turn state and do not infer completion from a finished reply.

### A. A collapsible right inspector (recommended)

Keep the chat centered; reveal Plan and Changes in a native inspector.

**Flow:** Open inspector → Follow steps → Select file diff.

**Best for:** Continuous context without filling the transcript.

**Tradeoff:** Needs width; becomes a sheet in a narrow window.

**Behavior:** The latest turn is selected by default. Selecting a file opens its diff; switching turns pins the inspector to that turn and labels it “Earlier turn”.

### B. Checkpoints in the conversation

Insert compact live plan cards and changed-file summaries at the relevant point in the transcript.

**Flow:** Read a checkpoint → Expand its changes → Continue below.

**Best for:** Excellent in narrow windows; history tells a complete story.

**Tradeoff:** Long tasks can become repetitive and push replies away.

**Behavior:** Update one card per turn in place. Collapse completed checkpoints; retain the ability to reopen the exact turn’s plan and diff.

### C. A dedicated work view

Add a Work view alongside Conversation, Activity and HTML, with the plan and diff occupying the main pane.

**Flow:** Switch to Work → Inspect plan and diff → Return to conversation.

**Best for:** Best for reviewing code and long plans in detail.

**Tradeoff:** Requires switching away from discussion.

**Behavior:** A small live status strip stays visible across views. Selecting a plan step filters associated evidence only where explicit associations exist; otherwise show turn-level changes.

## 3. Questions, approvals + connector forms

Ask for attention without misrepresenting whether work is blocked.

Protocol boundary: Respect isBlocking and the exact offered decisions. MCP elicitation may have no turn ID. A mockup choice never sends an approval.

### A. Requests stay beside the work

Use inline request cards with distinct “Waiting for you” and “Optional answer · work continues” labels.

**Flow:** Notice inline card → Inspect scope → Answer or decline.

**Best for:** Keeps the reason and action in the same conversation.

**Tradeoff:** Requests from other conversations are easy to miss.

**Behavior:** Sticky attention badges link to the card. Show command, folder and exact approval scope; keep any persistent rule choice separate. Connector cards render the supplied fields.

### B. An attention inbox (recommended)

Collect requests across conversations in a focused inbox with source, urgency and resolution state.

**Flow:** Open attention inbox → Choose request → Respond in detail pane.

**Best for:** Best for managing several active tasks.

**Tradeoff:** More navigation for a single conversation.

**Behavior:** Separate blocking approvals from optional questions. Clicking the source opens its conversation. Resolved requests leave the actionable list only after provider confirmation.

### C. An attention tray above the composer

Stack pending requests in a compact tray; expand one into an anchored sheet.

**Flow:** Open request tray → Review one sheet → Return to typing.

**Best for:** Always reachable without inserting large transcript cards.

**Tradeoff:** The sheet can obscure relevant conversation context.

**Behavior:** Show the conversation name and request source in the sheet. Optional questions can be dismissed from the foreground while remaining pending. Never pre-submit a selected default.

## 4. Goals, usage + context

Know whether the turn ended, the goal finished, or a limit stopped progress.

Protocol boundary: Show supplied goal/token/rate-limit data, never inferred billing. Creating or resuming a goal is an explicit action. Sample numbers below are illustrative.

### A. A compact status strip

Keep goal status in the header; a disclosure reveals budgets, context and account limits.

**Flow:** Read status strip → Open details → Take a relevant action.

**Best for:** Quiet and visible in every conversation.

**Tradeoff:** Detailed long-running work needs one extra click.

**Behavior:** Display “Turn finished · Goal active” as two facts. Missing budget/window limits say “Not provided”. Goal Pause and Stop turn remain separate controls.

### B. A mission inspector (recommended)

A dedicated Goal inspector combines objective, goal lifecycle, usage and the latest blocker.

**Flow:** Open Goal inspector → Read objective and limits → Pause or resume explicitly.

**Best for:** Clear home for persistent goals and budgets.

**Tradeoff:** Competes with the Plan/Changes inspector for attention.

**Behavior:** Use tabs within the same inspector rather than another permanent pane. Budget edits are intentional settings changes, not prompt text. Separate measured usage from unknown completion progress.

### C. A portfolio status list

Make goals a first-class list across conversations, with drill-down for usage and controls.

**Flow:** Open Goals view → Compare active work → Open one goal.

**Best for:** Best for supervising many concurrent tasks.

**Tradeoff:** Too much structure for casual conversations.

**Behavior:** Only explicitly created goals appear. A conversation without a goal remains ordinary chat. Paused/blocked/limited rows say why rather than using a generic error badge.

## 5. Conversation management

Organize growing history without needing to return to the original client.

Protocol boundary: Rename/pin/archive/restore use server methods; archive scope can include descendants. Pinned order is not a promise of Desktop sidebar synchronization.

### A. Sidebar actions (recommended)

Add a visible row menu and right-click actions to each conversation.

**Flow:** Open row menu → Choose action → Show updated row.

**Best for:** Feels native; smallest change to the existing app.

**Tradeoff:** Batch organization is slower.

**Behavior:** Rename edits the row in place. Pin moves it to a Pinned group. Archive previews descendant scope when relevant; Archived has an explicit Restore action.

### B. A library table

Provide a Library view for sorting, multi-selection and bulk organization.

**Flow:** Open Library → Select conversations → Apply one scoped action.

**Best for:** Efficient for large archives.

**Tradeoff:** Feels heavier than the current conversation-first sidebar.

**Behavior:** Show provider, folder and updated time. A bulk action previews its actual scope and excludes unsupported items explicitly; never silently partially succeed.

### C. A conversation command palette

Offer keyboard-first organization through a searchable command palette tied to the selected conversation.

**Flow:** Open command palette → Find “Pin” or “Restore” → Apply to named conversation.

**Best for:** Fast for frequent keyboard users.

**Tradeoff:** Least discoverable without visible menu equivalents.

**Behavior:** Always display the target conversation and scope. Use a proposed shortcut such as ⇧⌘P only after checking conflicts. Rename and archive expand into clear second steps.

## 6. History pagination + message search

Find an exact past exchange and load long histories without losing your place.

Protocol boundary: Label search scope. In-thread search covers visible user/final assistant messages, not arbitrary tool output. Preserve cursor and scroll anchors.

### A. Find in this conversation

A familiar Find bar highlights matches and jumps between them while loading the required turns.

**Flow:** Press ⌘F → Move between matches → Read surrounding turn.

**Best for:** Easy to learn; minimal interface overhead.

**Tradeoff:** Does not solve “which conversation was it in?” alone.

**Behavior:** Keep the current match anchored as pages load. Show “Searching…” separately from no results; offer an explicit broader search action.

### B. A global search workspace (recommended)

Search across conversations with snippet results, folder/provider filters and a preview pane.

**Flow:** Search all conversations → Inspect snippets → Open matched turn.

**Best for:** Best when the user remembers content but not location.

**Tradeoff:** Consumes the main pane and needs careful scope labels.

**Behavior:** Archived inclusion is explicit. Selecting a result previews context before navigation. Unsupported backends show their actual search scope rather than pretending to search everything.

### C. A turn navigator

Place a compact turn outline beside the transcript, with dates, user prompt previews and search markers.

**Flow:** Open turn navigator → Choose a turn or match → Load its context.

**Best for:** Excellent for very long, structured sessions.

**Tradeoff:** A new navigation model with more visual chrome.

**Behavior:** Use known turn metadata to populate the outline progressively. Mark unloaded history rather than inventing turn counts. Keyboard selection follows visible order.

## 7. Plan mode

Let users develop an approach and deliberately hand it over for execution.

Protocol boundary: Use the advertised collaboration mode. Plan mode is distinct from the plan checklist; do not portray it as a sandbox guarantee.

### A. A mode switch in the composer (recommended)

Choose Plan or Work beside the model selector; the selected mode applies to the next submission.

**Flow:** Choose Plan → Discuss the approach → Choose Work and send.

**Best for:** Fits the existing composer without a new workflow.

**Tradeoff:** Easy to forget the current mode unless it is clearly labeled.

**Behavior:** While a turn runs, label changes “For next message”. A transition to Work does not submit or execute by itself. Preserve the plan in the conversation.

### B. A brief → plan → work handoff

Start with a concise brief, review the proposed approach, then explicitly start work.

**Flow:** Write the brief → Revise the plan → Start work.

**Best for:** Clear commitment boundary for substantial changes.

**Tradeoff:** Too many steps for a small everyday request.

**Behavior:** The plan review shows scope, constraints and unresolved decisions. “Start work” submits an explicit instruction; it is not a blanket approval for future commands.

### C. A planning document

Use a focused plan document with comments, revisions and a deliberate handoff to execution.

**Flow:** Open plan document → Annotate and revise → Send selected plan to Work.

**Best for:** Strong for collaborative or lengthy planning.

**Tradeoff:** Highest complexity; the document must stay in sync with the conversation.

**Behavior:** Edits and comments are local drafts until explicitly sent. Record the plan revision used for the handoff; later edits do not secretly change already-running work.

## 8. Skills + connectors

Make available capabilities discoverable at the moment they are useful.

Protocol boundary: Use typed skill/mention inputs and actual installation/auth state. Selecting a capability is separate from granting access or installing it.

### A. An @ picker in the composer (recommended)

Mention a skill or connector while composing; insert a named capability chip into the draft.

**Flow:** Type @ → Choose an available capability → Send with a visible chip.

**Best for:** Fast and contextual; familiar to chat users.

**Tradeoff:** Poorer for browsing unfamiliar capabilities.

**Behavior:** Group Skills and Connectors. A disconnected connector offers “Connect…” rather than pretending it is ready. Keep its chip pending until authentication succeeds.

### B. A capability library

Provide a browsable library with descriptions, availability and “Use in conversation”.

**Flow:** Browse library → Read capability details → Add to draft.

**Best for:** Best discovery and understanding of access.

**Tradeoff:** Requires leaving the immediate composition flow.

**Behavior:** The detail view explains source, scope and current connection state. “Use” inserts a draft chip only. Installation and sign-in are explicit separate actions.

### C. A workspace setup checklist

Curate capabilities per working folder and resolve missing connections before starting a task.

**Flow:** Open workspace setup → Choose relevant capabilities → Finish required connections.

**Best for:** Good for repeatable team/project workflows.

**Tradeoff:** Workspace scoping requires app-side state and careful semantics.

**Behavior:** Describe selections as Diorama workspace defaults, not an access boundary. A task can still explicitly add or remove draft mentions; permissions remain independently enforced.

## 9. Branching + code review

Explore an alternative conversation and inspect code findings without confusing history with file state.

Protocol boundary: Fork conversation history explicitly. A fork is not an isolated filesystem/worktree. Reviews may be inline or detached; findings need file/line provenance.

### A. Message actions + a review entry point (recommended)

Branch from a message menu and start review from the Changes inspector.

**Flow:** Choose branch point or Review → Name the target → Open linked conversation.

**Best for:** A small, contextual extension of the existing interface.

**Tradeoff:** Relationships are less visible once many branches exist.

**Behavior:** Show “Branch through this turn” precisely. New branches link back to their origin and display the working folder. Review prompts let users choose working changes or another supported target.

### B. A branch map

Show conversation ancestry as a small graph, with a selected branch’s review status beside it.

**Flow:** Open branch map → Choose an alternative → Review that branch’s current files.

**Best for:** Makes competing approaches easy to understand.

**Tradeoff:** Graph complexity grows quickly and can suggest Git isolation.

**Behavior:** Use “Conversation branches” as the label. Never draw a merge action unless a separate implementation exists. Review results refer to the filesystem/commit target, not a frozen chat snapshot.

### C. A review workbench

Make code review a focused workspace with findings, diff context and a “Try fix in a new conversation” action.

**Flow:** Start a review → Inspect findings in diff → Branch a fix discussion.

**Best for:** Best for serious code review and resolving findings.

**Tradeoff:** Largest feature; more than a simple branching menu.

**Behavior:** Keep review findings separate from agent-applied edits. “Try fix” forks the discussion, not the repository; any isolated worktree is a separate explicit setup.

## 10. Prompt queues

Prepare the next instructions without accidentally steering the work already running.

Protocol boundary: Queue is experimental. Show pending, starting and accepted states from server evidence; do not promise dependencies or scheduling the API does not provide.

### A. A queue just above the composer (recommended)

Keep upcoming messages in a compact ordered tray, with explicit “Queue next” and “Send correction” actions.

**Flow:** Write next request → Queue next → Edit or reorder before start.

**Best for:** Best fit with steering and the existing composer.

**Tradeoff:** Two send intentions need clear labeling.

**Behavior:** Show the exact queued text and edit/remove actions until it begins. Use keyboard Move up/down alternatives to drag-and-drop. Once starting, disable edits and reconcile with the server.

### B. An execution timeline

Make Now, Next and Later a vertical timeline beside the conversation.

**Flow:** Open timeline → Add a next message → Move it earlier or later.

**Best for:** Clear chronological model for long work.

**Tradeoff:** Takes a persistent pane and can look like a scheduler.

**Behavior:** “Later” means queue order, not a clock time. Show which entry is starting and why the queue is paused, if known. Restart restores server-backed state rather than replaying drafts.

### C. A batch outbox

Compose several independent follow-up messages in a batch editor before adding them to the queue.

**Flow:** Draft a batch → Review exact order → Add to queue.

**Best for:** Good for a prepared sequence of follow-ups.

**Tradeoff:** Higher risk of stale instructions as earlier results change.

**Behavior:** These are editable messages, not a dependency graph. Let users review each before submission. Preserve per-entry outcomes if only some adds succeed; never retry the whole batch blindly.

## 11. Richer tool results

Turn raw event payloads into readable evidence without hiding provenance.

Protocol boundary: Render known typed items and keep raw details. Distinguish running, successful, failed and unknown outcomes; only display available assets and verified associations.

### A. Compact inline result cards (recommended)

Replace generic tool rows with recognizable command, source, file and image cards.

**Flow:** Read result summary → Expand evidence → Open referenced asset.

**Best for:** Preserves the conversation as the main narrative.

**Tradeoff:** A busy tool run can create many cards.

**Behavior:** Collapse repeated operations into an expandable group. Success requires an explicit completion/exit result. An unavailable image gets a clear placeholder, not a fabricated thumbnail.

### B. An evidence inspector

Keep activity compact in the transcript; selecting a tool opens detailed evidence in the shared inspector.

**Flow:** Select an activity row → Inspect typed details → Return to conversation.

**Best for:** Keeps long conversations clean while exposing detail.

**Tradeoff:** Information is less visible until selected.

**Behavior:** Inspector tabs switch between Result, Metadata and Raw. Pinned evidence stays labeled with its source turn; it never silently changes to another tool.

### C. An artifacts and evidence shelf

Collect files, images, sources and verification results in a dedicated shelf linked back to the conversation.

**Flow:** Open shelf → Choose an artifact or check → Jump to source event.

**Best for:** Best for deliverables and visual work.

**Tradeoff:** Needs deduplication and careful handling of mutable file paths.

**Behavior:** Group by actual result type and retain provenance. Label local previews as current file contents unless snapshots exist. Worker cards link to known child conversations, not inferred relationships.

## Recommended shared structure

Keep Conversation and its composer as the main workspace. Reuse a single inspector for Plan, Changes, Goal and Evidence. Use cross-conversation views for Attention and Search. Avoid adding a permanent pane for every capability.

Choices remain local in the comparison page; the selectable export can be pasted into chat. Choosing an option is not implementation approval.

## Validation

All 11 priorities have three visual concepts. HTML nesting, unique IDs, asset restrictions and JavaScript syntax were checked. A DOM fixture verified individual selection, navigation, recommended-set selection, clearing and multiline export. Browser preview was blocked by local-file URL policy, so rendered layout and actual-browser interaction were not verified. No native app code changed.
