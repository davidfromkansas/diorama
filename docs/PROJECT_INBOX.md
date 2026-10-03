# Project Inbox

The office inbox groups reported main-agent handoffs by logical conversation. It does not classify their value, verify results, or authorize execution. Reply opens the existing conversation and focuses its composer without submitting a message.

## Data and lifecycle

- `ProjectInboxStore` is an actor. Each thread has a metadata file; each update has a separate body file under Application Support/Diorama/ProjectInbox. List queries never decode message bodies or image data.
- Native provider/session/turn identities deduplicate observed and attached updates. Claude uses its final native assistant-message identity, shared by SDK events and saved history. Merged provider segments reconcile into the logical conversation.
- Runtime-reported terminal outcomes take precedence over less-specific saved history. Unknown completion boundaries are not treated as success.
- Initial history is read; new arrivals after the persisted project baseline are unread. Read state uses update identities, so later arrivals and late enrichment do not reset previously read content.
- Archive returns to the inbox on new work. Not a delivery stays excluded until restored.
- Existing discovery/file events schedule at most two background history reads. Completion fingerprints avoid repeatedly normalizing histories during streamed file changes. The existing bounded 16 MiB source window is labeled when partial.

## UI and memory

- The list fetches 50 summaries at a time and retains at most 250 loaded rows. Show newest returns to the first page after distant rows have been released.
- Thread detail starts with 20 updates and pages backward in groups of 20, retaining at most 100 bodies. Show latest returns to current work after distant bodies have been released.
- Existing asynchronous image thumbnails and Quick Look provide image display and enlargement.
- Thread updates display newest first. Older pages load at the bottom; new arrivals appear at the top when the reader is already there, otherwise a Show latest button preserves their reading position. Native row anchors preserve list/detail offsets. New arrivals do not force a reader away from older content.
- Store/index work is actor-isolated. UI publications are coalesced; no new polling or continuous rendering loop is introduced.

## Verification

Run the ProjectInbox core/rendering tests plus conversation scrolling, image, observation, and navigation regressions serially in release configuration.

`--inbox-benchmark` is an explicit diagnostic entry point in the existing app, separate from production workspace data. It creates 10,000 temporary threads, attached image references, and a long-report thread, then captures 30 seconds of inbox scrolling with each of the 16- and 64-agent office fixtures. Results are written to `/tmp/diorama-inbox-native-16.txt` and `/tmp/diorama-inbox-native-64.txt`. The fixture performs no provider execution or paid turns.

The SwiftPM native-window capture is opt-in with `DIORAMA_INBOX_BENCHMARK=1`. An occluded window or zero rendered frames invalidates that capture; it must not be reported as a passing FPS measurement. Use the app diagnostic entry point when the test runner cannot obtain a visible rendering window.

## Local verification, October 2, 2026

- 41 Swift regression tests passed across inbox, external observation, scrolling/paging, images, observation invalidation, and workspace navigation. Nine Claude bridge tests passed.
- A 50-summary query over 10,000 persisted threads took approximately 11 ms on the store actor in the optimized test build.
- Inspected real Codex inbox rows, timestamp labels, collapsed/expanded states, and Reply opening the existing conversation and focusing its composer without sending.
- Built and signed the release-configured development app, installed through the existing safe relaunch script, and restored normal app mode and source auto-reload.
- **FPS acceptance is not yet verified.** Both the native test runner and app-level captures were invalidated by occlusion/the locked Mac; the app-level output explicitly reports INVALID. These captures are not evidence of a passing or failing steady-state FPS target. Active-scrolling memory plateau, narrow-window interaction, full VoiceOver narration, and live Claude execution remain unverified. No paid test turns were started.
