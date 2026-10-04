# Finished office agents

Finished and stopped agents remain in the project office for as long as their conversation passes the existing membership and archive filters. Working, waiting, and failed agents retain desk presentation. Missing observations do not imply completion.

The office owns two independent placements per scoped agent: a reserved desk and a stable leisure-area standing slot. The first sixteen desks form two centered rows of eight at z = ±1.4 m. Further desk rows extend behind the work area. Standing slots fill pairs beside the right-hand (+X) wall first, then inward, with two-metre spacing. The leisure area uses the same bare wood floor as the office; there is no rug. The floor and leisure area extend forward as needed without moving existing standing slots or desks. Per-project slot assignments and last-known placement are stored locally in versioned UserDefaults data. Geometry and skeleton assets remain shared. Standing uses the authored idle pose without a motion loop. Placement changes fade in over 180 ms; inactive or Reduced Motion transitions are immediate.

The avatar, selection ring, task/status label, and plan/task controls move together. Furniture remains at the reserved desk. Existing conversation destinations and camera-preserving panel behavior remain unchanged. Cached subagents omitted by a bounded history refresh remain in the projection as last known; conversation removal and archive filtering still remove them from the office.

## Verification — 2026-10-02

- 47 release-configuration tests passed across SharedOfficeTests, FinishedAgentRetentionTests, OfficeScrollingTitleTests, WorkspaceAgentTests, ScenePerformanceTests, SpatialWorkspaceTests, and WorkspaceNavigationTests.
- Covered no time-based expiry, bounded-history child retention, working/waiting/failure/stale placement, stop/resume, desk ownership, serialized slot restoration, clearances, existing scene reuse and camera preservation.
- Rendered small and 64-finished-agent offices from all four orbit directions. Inspected central spacing and separation from desks and walls. Snapshots: `/tmp/diorama-standing-{4,64}-{0,1,2,3}.png`.
- Inspected the 16-agent native diagnostic window with upright standing poses and empty reserved chairs.
- Added development File → Benchmark standing office to capture 16/64-agent native frame intervals. The first capture was interrupted by source auto-reload. After the final release reload, native UI automation repeatedly returned `noWindowsAvailable`; no valid uninterrupted frame timing result was obtained. Sustained FPS for retained avatars is therefore **not yet verified**.
- Updated the single `dist/Diorama.app` through safe staging/reload (22:39:54 UTC build success), retaining its DevelopmentRoot. No paid turns were started.

Known verification limits: live provider completion/resumption was exercised with deterministic fixtures rather than new paid turns. Slot restoration is covered by serialization tests; uninterrupted interactive restart/selection and native FPS checks remain incomplete after the UI automation window failure.

## Leisure layout update — 2026-10-02

- 21 release-configuration tests passed across SharedOfficeTests, SpatialWorkspaceTests, and FinishedAgentRetentionTests.
- Verified exact two-row spacing, stable desks during leisure expansion, saved slot restoration, desk/avatar clearances, and floor bounds.
- Inspected empty-office and four-finished-agent default-direction renders, plus the 64-finished-agent reverse view. The leisure area stays separate from the desks.
- Native sustained frame timing was not repeated for this layout change.
