# Project agent sidebar

The native virtualized table presents every nonarchived project agent. Status sorts first (Blocked, Working, Done, Unknown, Idle), then the roster's existing meaningful-activity timestamp, then stable identity. Existing replay protection and scroll anchors remain in use. Status acknowledgement does not alter provider execution or office placement.

Rows contain task, status/reason, provider/reported model, and branch. Missing metadata is explicit. The supplied SVGs are bundled under Resources/AgentStatus; the Working indicator is a native Core Animation adaptation of Pixel Drift, with upstream MIT attribution in that directory. Only realized active rows animate. Hover/focus title and branch scrolling uses clipped native text and stops when the cell is reused. Reduced Motion retains static text and full tooltips.

Completion acknowledgement is separate from Inbox read state. Native provider turn/message identities connect terminal updates to the sidebar. A native clipping probe acknowledges an update only while its ending is visible in the key window. Approval and question states do not clear on viewing. Historical completions default to viewed unless existing unread evidence says otherwise. Acknowledgements survive relaunch and are persisted in coalesced writes.

Right-click archive carries the clicked row's stable identity through the existing confirmation flow. Unsupported destinations have a disabled action and never fall back to archiving the parent conversation.

Validation uses release tests, native table fixtures, existing observations, and an optional office-plus-roster scrolling benchmark. No paid agent turns are needed.

## Verification (2026-10-03)

- Final focused release run: 34 tests passed, covering sidebar status/acknowledgement, SVG loading, marquee reuse, archive targeting, conversation history, roster anchors/coalescing, and agent rendering.
- Broader serial regression run: 127/128 passed. `ProjectViewsTests.explicitProjectsDeduplicateAndRetainNavigation` still expects `Context` to be stored in shared project storage; the existing window-scoped navigation implementation restores `Sessions` instead. This task does not change that persistence design.
- Inspected the installed native app: supplied icons, flat list, task/status/provider/model/branch hierarchy, and clicked-row archive menu were present.
- The optional 64-agent office/scroll benchmark was attempted, but macOS reported its window as not visible and recorded zero frames. It is not a valid FPS result. Sustained frame timing, memory plateau, and full VoiceOver narration remain unverified.
- No paid agent turns were started. Installation uses the existing release staging and safe relaunch mechanism.
