# Claude goals and steering

Diorama uses the user's Claude Code subscription session for both features. No Codex dependency or API fallback.

## User experience

- Goal is mutually exclusive with Plan Mode. Describe the objective and send. The tray shows status and usage; Edit provides budget and Resume controls.
- Pause prevents further automatic responses. Stop also interrupts the current response. Clear removes the goal while any current response continues.
- Interrupt & steer waits for Claude's interruption to finish, then sends the correction in the same session. It also pauses an active goal.
- Goals run while Diorama is open. Restart or disconnection leaves them paused; uncertain delivery is never replayed automatically.
- Default limits: ten responses and 100,000 reported tokens (input, output, and cache). Usage is checked between responses, so the final response can exceed the budget. This is not a hard billing cap.
- Completion means Claude reported completion; its evidence remains in the conversation. Missing status, blocked work, declined permission, and failed responses pause continuation.

## Implementation

ClaudeGoal checkpoints state atomically under ~/Library/Application Support/Diorama/ClaudeGoals. A per-goal status marker indicates continue, complete, or blocked. Internal instructions are collapsed in saved history; rendered assistant messages omit the status marker. Pause, stop, clear, or a changed goal invalidates scheduled continuation.

Claude steering checks the expected turn, rejects stale requests or pending approvals, interrupts via the native control protocol, waits for its terminal event, then submits a replacement. Queued copies are protected against replay until delivery and removal are acknowledged. This does not establish termination behavior for every possible external tool subprocess.

Codex retains its existing server-backed goal and steering implementation.

## Verification

Automated tests cover continuation, completion, limits, restart recovery, blocked initial responses, stale steering, queued correction deduplication, and context separation. ClaudeWorkflowLiveProbe exercises the production transport/controller using a real subscription: interruption and correction, then two-response goal completion with hidden internal markers.

To intentionally run this subscription-consuming test:
DIORAMA_CLAUDE_WORKFLOW_PROBE=1 swift test --filter ClaudeWorkflowLiveProbe

Official reference: https://code.claude.com/docs/en/agent-sdk/streaming-vs-single-mode
The documentation describes queued streaming input and interruption; it does not establish equivalence to Codex's dedicated steering API.
