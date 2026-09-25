# Workspace interface

Diorama now uses a Conductor-inspired native SwiftUI workspace shell. Projects and Sessions retain their existing identities and execution behavior.

- The sidebar groups sessions beneath collapsible projects. Its project menu includes archive/internal-session filters and project creation. Pins, provider markers, recorded activity, and session context menus remain available.
- Home lists recent sessions with project, provider, archive, and activity filters. Search opens sessions through the same navigation path as the sidebar.
- Conversation, Activity, and HTML view occupy the center. Files and diffs open as document tabs, retaining the mounted composer and its unsent state.
- The inspector contains Files, Changes, and Checks. Project-base files remain revision-based; session files use their worktree. Imported sessions expose their supported existing review controls.
- The project menu contains shared Context, Pull Requests, folder access, session-context snapshots, rename, locate, repository connection, and cleanup actions where applicable.
- The sidebar defaults to 240 points, the inspector to 340. Both resize and collapse. Below 1,100 points the inspector opens as an overlay.
- Layout, selected destination, document tabs, and sidebar expansion persist under separate `workspace*.v1` preferences. Provider APIs and project storage formats are unchanged.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| New session | Command-N |
| Find session | Command-K |
| Focus composer | Command-L |
| Toggle sidebar | Command-B |
| Toggle inspector | Command-Option-B |
| Back / forward | Command-[ / Command-] |
| Home | Command-Shift-H |
| Refresh sessions | Command-R |
| Conversation / Pull Requests / Files / Context | Command-1 / 2 / 3 / 4 |

Sending retains Return/Command-Return to send and Shift-Return for a newline.

## Verification

`swift test` passed 226 tests across 63 suites. New tests cover restored document identity across worktrees, history navigation, draft and attachment preservation, composer lifetime across document tabs, and native rendering at 760, 1,100, and 1,440 points with approval controls. Empty, loading, and unavailable-document views also have native render fixtures. Existing provider, execution, approval, queue, goal, file, review, activity, and HTML-view regressions pass.

Native fixtures use no live model prompts. Screenshot outputs are written to `/tmp/diorama-workspace-*.png`. The initial release build and deep signature verification succeeded for `dist/Diorama-UX.app`. The subsequent responsiveness build is `dist/Diorama-Responsive.app`; it was signature-verified, launched after the approved relaunch, and checked through native project disclosure and inspector interactions.

The reference was the installed Conductor app and its public [workflow documentation](https://www.conductor.build/docs/concepts/workflow). No terminal, run-script system, cloud execution, City view, or codemap integration is introduced.

## Responsiveness follow-up

Profiling project disclosure clicks showed repeated `ProjectModel.sessions` scans from the shared sidebar body. The shell now observes individual layout properties, and project groups are separate lazy views. Disclosure arrows have a 22×30-point hit area. Preference encoding/writes are debounced for 200 ms and flushed at normal app termination. Project membership is cached with invalidation for library, worktree, and association changes; session hierarchy traversal is indexed and iterative. Sidebar title parsing is bounded by an in-memory cache, and Home groups its filtered session list once per render.

The complete suite passes 231 tests. In the native disclosure regression with 20,000 imported sessions and 100 project sessions, 20 layout updates measured a 2.2 ms median and 3.4 ms worst case on the development Mac. Disclosure changes cause zero unrelated pane-observer invalidations. A 10,000-level hierarchy takes approximately 30 ms and no longer depends on recursion or quadratic scans. These are local fixture measurements, not a guarantee for every machine or transcript.
