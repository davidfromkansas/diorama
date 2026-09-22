# Claude Agent SDK feasibility

Date: 2026-09-22. Historical feasibility investigation. For subsequent implementation and current verification, see [Shared activity implementation](SHARED_ACTIVITY_IMPLEMENTATION.md).

## Decision

Proceed with an SDK-backed adapter prototype behind Diorama's existing transport interface. Keep the direct CLI adapter available until packaging and app-level regression checks pass. The SDK offers maintained control and history APIs; this experiment found no exclusive activity information compared with the same CLI's stream-json output.

The tested combination is Agent SDK 0.3.278 with the installed Claude Code 2.1.276 executable, selected explicitly with `pathToClaudeCodeExecutable`. This is a tested pair, not a claim that arbitrary SDK/CLI versions are compatible.

## Experiment

Both transports ran a bounded synthetic task in a temporary directory, using the same CLI, model alias `sonnet`, tools, and isolated settings. The task created and updated two checklist items, delegated a fixture read to one general-purpose child, attempted a denied write, then answered a follow-up recalling the fixture marker. API credential overrides were removed. Initialization reported Claude Max and firstParty before prompts were submitted. No account identifiers or credentials are included in the saved evidence.

A separate SDK probe reopened the saved session, allowed one fixture write, entered plan mode, received an ExitPlanMode proposal and denied implementation, interrupted a foreground sleep, then successfully submitted another turn. It generated a synthetic plan in Claude's local plans directory as well as temporary fixtures. No Diorama application source or global Claude settings were modified.

## Capability results and intended UI

| Capability | Observed result | Diorama presentation / integration |
|---|---|---|
| Subscription authentication | Both paths initialized as Claude Max / firstParty and completed model calls | Retain subscription login and fail-closed account checks; never silently choose API credentials |
| Execution checklist | Both emitted TaskCreate/TaskUpdate inputs and structured task results | Steps panel, native task IDs, explicit status changes |
| Delegation and parent attribution | Both emitted Agent calls, parent_tool_use_id and task_started/progress/updated/notification | Agents tree and timeline; do not classify every background task as a child agent |
| Read-only saved history | SDK read 24 parent messages and 4 messages for one discovered child | Child detail/history panel without starting or resuming execution |
| Proposed plan | SDK received plan Markdown and planFilePath in ExitPlanMode; denial kept implementation unapproved | Distinct proposal card and explicit permission decision; deduplicate tool input and callback observations |
| Permission denial and approval | Denied file absent; explicitly allowed fixture file created | Existing approval UX maps to SDK canUseTool callbacks |
| Follow-up and resume | Same-process follow-up retained fixture marker; reopened session accepted subsequent work | Preserve provider session identity and worktree; broader restart/history tests still required |
| Interrupt and continue | interrupt returned still_queued: []; interrupted turn reported error_during_execution; next turn returned INTERRUPT_RECOVERED | Track explicit interruption intent so a stopped turn is not shown as an unexplained failure; never infer all errors are interruptions |
| Runtime settings | setPermissionMode plan/default and setModel sonnet calls succeeded | Existing controls can use SDK APIs; cross-model change behavior was not tested |
| Usage and limits | Rate-limit events, task usage, result usage and modelUsage were present | Show the reported scope; list-price estimates are not subscription charges; do not sum overlapping totals |
| Queue and goals | Not tested in the application | Keep Diorama's local scheduling policies; SDK is not a replacement for them |

## Responsiveness

One sample per transport, including real inference and tool execution:

| Measurement | SDK | Direct CLI |
|---|---:|---:|
| Initialization | 1,267 ms | 1,250 ms |
| Send to first text | 14,802 ms | 15,122 ms |
| Two-turn probe total | 24,272 ms | 24,522 ms |

These values do not establish a speed advantage. First text came after tool activity, so that measurement is not message-dispatch latency. A persistent helper and immediate optimistic composer updates remain necessary; changing wrappers alone will not make message sending faster.

## Information the current adapter drops

Inspection of `Sources/DioramaCore/ClaudeExecutionTransport.swift` found that most system activity is ignored, structured tool results and child attribution are reduced, and usage is used primarily for local goal bookkeeping. The tested direct CLI already exposes the activity required for steps and agent visualization. Normalize those provider facts into the shared activity model irrespective of transport choice. Never display hidden reasoning as an activity stage.

## Packaging and subscription boundaries

The development SDK installation occupied about 255 MiB, including an optional bundled arm64 CLI of about 208 MiB. The SDK package itself was about 5 MiB. The available universal Node executable was about 214 MiB and linked only system libraries. These are development footprints, not final compressed DMG costs. Reusing the installed CLI may avoid shipping the optional CLI, but packaging, runtime discovery, offline startup, signing, notarization, and both Mac architectures still need validation. Do not require users to install a development Node toolchain.

Technical subscription authentication succeeded. This does not settle redistribution policy or prove invoice treatment. The [subscription support article](https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan) says the announced changes are paused and SDK/third-party use continues to draw from subscription limits. The [Agent SDK overview](https://code.claude.com/docs/en/agent-sdk/overview) still contains restrictions on offering claude.ai login in third-party products without approval. This discrepancy is not an implementation gate; the user directed the work to focus on technical subscription support. The [hosting guide](https://code.claude.com/docs/en/agent-sdk/hosting) describes the SDK supervising a Claude Code process, consistent with the measured architecture.

## Next implementation batches

1. Add a versioned Swift-to-local-helper protocol and SDK adapter, with pinned dependencies, explicit CLI discovery, subscription gating and supervised cleanup. Keep conversation/worktree identities stable and the existing adapter selectable for rollback.
2. Feed proposals, tasks, agents, tool activity, wait states, usage and rate-limit events into the shared journal. Add fixture tests for duplicates, unsupported variants, stale state and interrupted results. Enable task tools only in Diorama-launched processes, as agreed.
3. Exercise existing permission, queue, goal, provider-switching and optimistic composer flows against the adapter. Test restart, cancellation, process death, pending approvals and resume in real isolated worktrees.
4. Package the helper without relying on development tools; validate signed builds and both architectures. Run the full manual UI walkthrough and retain a direct CLI fallback.

## Evidence and limits

Sanitized measurements: [evidence/claude-sdk-feasibility.json](evidence/claude-sdk-feasibility.json). Temporary probe programs and raw reports: `/tmp/diorama-sdk-probe` (not durable or committed). This was a bounded local feasibility test, not a production rollout or complete parity certification. No build, release, queue/goal regression, multi-level agent tree, or full permission UI walkthrough was performed in this investigation.
