# One Diorama conversation across providers

Build 0.5.0 (42).

Choosing a model from another provider applies when the next message is sent. The user remains in the same Diorama conversation, with the same title, draft identity, working folder, workspace record, branch, base commit, PR association, and HTML canvas. Switching within one provider retains its native session as before.

Diorama creates a fresh native session for each cross-provider transition. The conversation journal (`Projects/conversations.json`) records the ordered native segments under the original stable UI identity. Previous displayed messages, images and tool records are snapshotted locally, and a disclosure marker exposes the incoming provider's handoff. A switch back includes intervening work rather than resuming stale native context. The provider's private reasoning and hidden runtime memory are not transferred.

The handoff contains project instructions, current folder, paused goal, and bounded recent user/assistant excerpts (60,000 characters total, up to 12,000 per entry). Providers are told to inspect the existing files and Git status. Historical text is marked as reference material. Source history is read through the existing transcript reader with a 5,000-entry cap; this does not promise an unlimited transcript migration.

## Pending work and errors

- Switching requires an idle main session with no unresolved message/queue delivery. A switch lock prevents concurrent send, queue start, or goal activation through Diorama during preparation.
- Source goals are paused and their objectives are recreated paused on the destination. The target receives the remaining recorded token budget (minimum one token because the goal API requires a positive value). Provider-specific counters are not portable; the target runtime reports its own usage.
- Queued input remains in its original native queue until explicitly resumed. A carried-queue tray preserves its ordering and offers Resume/Remove. Resume journals a stable transfer identity, checks for an existing destination copy, verifies source removal, then starts it only if it is first in the destination queue. Other destination messages keep their ordering.
- A pending queue transfer must be resolved before another provider switch. Retired native sessions are blocked from new work through Diorama, including after restart. Other external clients are outside Diorama's control.
- Selection and draft are retained if provider preparation fails. Once a message is submitted to the destination, uncertain results remain visible and are not automatically replayed.
- Existing permission choices are mapped when recognizable; otherwise the new turn uses Ask for approval. Selected provider-specific skills/connectors must be removed before switching. No silent provider fallback occurs.

## Verification

Automated tests cover round-trip OpenAI → Claude → OpenAI switching with simulated transports, stable sidebar identity, preserved history/workspace/PR/uncommitted file contents, persisted journal restoration, no turn or fork during preparation, active-turn rejection, account rejection and draft retention, and idempotent carried-queue import. The broader regression suite also runs.

Fresh authenticated end-to-end provider switching and a full manual UI walkthrough have not been verified in this build. Existing native sessions remain visible separately in their official provider apps; Diorama's unified conversation is an application-level grouping.

| Before | After | Why |
| --- | --- | --- |
| Provider switch opened a new project draft/worktree | Next send continues in the same conversation and folder | Preserve work and navigation |
| Only a small handoff in a separate session | Continuous visible history with an expandable switch marker | Make continuity clear and context inspectable |
| Workflow tied to one native thread | Explicit paused goal and carried queue | Avoid surprise execution during handoff |
