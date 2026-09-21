# Conversation continuation options

Tested September 19, 2026, with Codex CLI 0.153.4. Desktop inventory: 26.901.51231 (8109). This investigation changes no product behavior or normal provider settings. Disposable probes use the existing account and tool-free synthetic prompts. Source: [official App Server documentation](https://learn.chatgpt.com/docs/app-server).

## Options and evidence

| Option | User experience | Evidence | Tradeoff |
|---|---|---|---|
| Official same-conversation resume | Select a conversation, click Continue here; if another writer owns it, show an in-use explanation and Retry. | Independent App Server resumed the same ID after the owner process exited; a further fresh client resumed it again. New replies recalled prior context. | Simplest API change. Subsequent designated Desktop quit → native Diorama resume → Desktop return test passed; see COMPATIBILITY.md. |
| Shared App Server | Two interfaces connect to the same runtime and conversation. | **Verified between two test clients** on one loopback WebSocket server: same ID, retained context, and the first client received completion of the second client’s turn. Desktop attachment remains unverified. | Could avoid writer transfer entirely, but requires access to the same official endpoint. Desktop's default control socket is absent on this Mac. |
| Explicit archive then resume | User archives the source task in Desktop; Diorama explicitly unarchives and resumes that ID. | Earlier designated Desktop → App Server → Desktop test passed (COMPATIBILITY.md). | Changes archive state, can affect descendants, and is not documented as a handoff workflow. Technically demonstrated, not recommended for a simple product. |
| Fork saved history | Branch into Diorama creates a new conversation linked to its original. | Fresh `thread/fork` while the owner remained open succeeded, returned a distinct ID and forkedFromId, and recalled the token in its new reply. | Simple official API; future messages diverge. Does not satisfy same-conversation requirement. The fresh test used a separate App Server owner, not Desktop. |
| Observe in Diorama; execute in original client | Keep the existing browser/activity interface; reply and approve in Desktop. | Existing imported-history integration and previous designated Desktop activity probes. | Least disruption and no ownership conflict, but execution stays in Desktop. |

Immediate `thread/unsubscribe` did not release ownership to a second server. This agrees with the documented 30-minute no-subscriber inactivity grace period; we did not wait 30 minutes or establish Desktop subscription behavior. No lock files were edited and no source histories were copied manually.

## Shared-server details

The official CLI proxy over a private Unix socket did not complete initialization in our probe; no production path relies on it. Two clients using Node’s built-in WebSocket against one loopback App Server succeeded. The first client completed a seed turn before the second called `thread/resume`; attempting to resume an empty, unpersisted thread had returned `no rollout found`. Both clients observed completion of the second client’s turn. Approval routing, simultaneous submissions and Desktop attachment were not tested. Script: `scripts/verify_shared_server.mjs`.

## Desktop and support boundaries

`codex app-server daemon version` failed because the documented default control socket at `~/.codex/app-server-control/app-server-control.sock` is absent. This does not prove Desktop has no internal endpoint; it establishes that this standard daemon connection is unavailable in this setup. No private endpoint was discovered or accessed.

Official Remote/host handoff documentation describes first-party device connections and SSH hosts, not a public third-party attachment contract for the already-running local Desktop process. The docs explicitly label App Server and its WebSocket transport experimental and not supported for production workloads. Documented functionality is not a stability or production-support guarantee.

Desktop was kept running because it hosts the current work and other user tasks. Closing it or relying on its private internals was not substituted for evidence. That initial probe verified independent-owner exit only. The subsequent designated Desktop exit/native resume/return test passed; see evidence/desktop-exit-lifecycle.json.

## Recommendation

Prefer official `thread/resume` for a simple, same-conversation UX, with an honest in-use error and no automatic workaround. If simultaneous Desktop and Diorama use of the same conversation is essential, shared-server access is the relevant architecture, but Desktop endpoint support remains the unresolved prerequisite. Keep forks optional rather than silently replacing continuation.

Evidence: `evidence/handoff-options.json`; reproducible probe: `scripts/verify_handoff_options.py`. Earlier Desktop archive/unarchive evidence: `evidence/codex-appserver-roundtrip.json`. No option was enabled in the application during this investigation.

## Selected approach

User approved ordinary `thread/resume`. Diorama 0.3.1 implements Continue here with explicit acquisition, settings review and writer-conflict Retry. The shared-server, fork and archive-transfer alternatives remain deferred. See COMPATIBILITY.md and evidence/imported-resume-native.json; Actual Desktop quit/reopen and a return reply retaining Diorama context subsequently passed; see evidence/desktop-exit-lifecycle.json.

## Follow-up unsubscribe probe — September 19, 2026

Using CLI 0.153.4, the designated conversation returned `notLoaded` to `thread/unsubscribe` on a separate App Server, then ordinary resume succeeded with the same ID. No prompt, archive mutation, or Desktop shutdown occurred. However, the main Desktop process was not detected before or after, including a follow-up exact executable-name check. This is not evidence that unsubscribe released Desktop’s writer. The documented unsubscribe applies to the calling connection only; owner-side last-unsubscribe has a 30-minute inactivity grace period. No accessible standard daemon socket or Desktop task-control tool was available in this follow-up. Evidence: `evidence/desktop-unsubscribe.json`.

Correction to conversational guidance: an earlier explicit Desktop archive → independent unarchive/resume → Desktop return test already passed while Desktop remained open. Quitting is the verified ordinary-resume workflow, not the only demonstrated way to continue without a fork. Archive remains an opt-in alternative with archive-state and descendant effects, not a documented transfer primitive.

## Desktop-held writer baseline — September 19, 2026

After the user sent READY in Desktop and confirmed leaving it open, the designated transcript recorded a completed reply in turn `01a0b6f8-b04f-7532-9bed-9f2891d23020`. A separate CLI 0.153.4 App Server rejected same-ID resume with `already has an active writer`, returned `notLoaded` to its own `thread/unsubscribe`, and rejected resume again afterward. This directly verifies that a separate observer cannot release this Desktop-held writer through its own unsubscribe. It does not test owner-side unsubscribe or its 30-minute grace period. No prompts, archive changes, Desktop shutdown or lock manipulation occurred. Evidence: `evidence/desktop-release-baseline.json`; probe: `scripts/verify_desktop_release_baseline.py`.

Next Desktop-side check: manually archive only the designated disposable conversation while leaving Desktop open, then verify archive state and same-ID unarchive/resume externally. This repeats the previously successful archive route against a newly confirmed held-writer baseline; it is not yet an enabled Diorama handoff workflow.

## Desktop archive release — verified September 19, 2026

Following the freshly verified held-writer baseline, the user archived only the designated conversation and reported leaving Desktop open. The archived transcript was confirmed. Official `thread/unarchive` restored the same ID, `thread/resume` succeeded, and a new completed turn recalled the prior Desktop marker and returned `DESKTOP-CEDAR-8426 ARCHIVE_RELEASE_VERIFIED`. The prompt did not supply the prior marker value. No tool items were observed, and the probe connection was closed afterward. CLI: 0.153.4. Evidence: `evidence/desktop-archive-release.json`; turn: `01a0b6fc-30ea-70e3-98eb-b9ed18fb6b80`.

This demonstrates an alternative to quitting Desktop: explicit Desktop archive followed by external restore/resume. It is not yet implemented in Diorama and is not documented as an atomic handoff operation. Archive may affect descendants; this test concerns the designated root conversation only. Desktop remaining open is based on the user's confirmed action, not the earlier unreliable process-name check. A return message from Desktop was not tested in this repeat. Initial archived `thread/read` returned not-found; unarchive-before-read succeeded, preserved separately in `desktop-archive-release-initial-read.json`.
