# Conversation permissions

New conversations request native automatic review. Codex uses workspace write with on-request approvals routed to its reviewer. Claude uses `auto` when supported; model metadata and the provider’s control response determine availability. Unsupported modes do not fall back automatically.

The hand control shows the selected mode. `Default` has not yet been confirmed by a provider; `Next message` is a pending choice. The effective mode is separate from the persisted conversation preference. Accepted changes are saved before sending a prompt so a later delivery failure does not lose them. Existing conversations without preferences retain reported settings; unresolved settings require an explicit choice.

Claude also offers Accept edits. Plan Mode temporarily changes its native mode and restores the saved execution preference afterward. Bypass permissions remains explicit. Provider SDK rules and approval callbacks remain authoritative.

Queue deliveries use the current accepted conversation permissions. Reconnects do not automatically start work. A provider disagreement, moved workspace, or unsupported mode blocks new submissions until resolved. Approval controls carry an instance token so a stale dialog cannot answer a reused request ID.

Validation uses fixture transports and helper tests. It does not send model prompts. Live automatic-classifier outcomes and organization-specific restrictions require observation of real user-authorized work; passing fixtures does not verify those outcomes.
