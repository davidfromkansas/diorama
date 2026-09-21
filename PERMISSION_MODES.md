# Permissions menu — Diorama 0.3.11

The composer permissions icon opens three selectable rows, with a checkmark and an official documentation link:

- Ask for approval: `approvalPolicy=on-request`, `approvalsReviewer=user`, workspace-write sandbox with the conversation folder and network disabled.
- Approve for me: the same sandbox and policy, with `approvalsReviewer=auto_review`.
- Full access: `approvalPolicy=never`, `approvalsReviewer=user`, `sandboxPolicy.type=dangerFullAccess`.

This supersedes the reviewer-only behavior in 0.3.8–0.3.10. Selecting a row explicitly chooses the whole preset for the next message and subsequent turns. No selection means no overrides: Codex’s current settings are retained. Unknown/custom settings are not falsely checkmarked as one of the three modes. Pending choices can be undone in the menu. Controls remain disabled during active turns, and global configuration is untouched. Existing grants and provider/organization restrictions may still affect behavior.

Validation: 19 targeted execution/preset/rendering tests passed. The native menu fixture was rendered and visually checked. A tool-free live probe verified all three settings through subsequent `thread/resume` responses, including Full access → Ask for approval → Approve for me. No tool commands were executed under Full access. Evidence: `.local/permission-presets-probe/evidence.json`; script: `scripts/verify_permission_presets.py`. The provider normalizes the working folder out of `writableRoots` because it is implicitly included.

Official reference: https://learn.chatgpt.com/docs/sandboxing
