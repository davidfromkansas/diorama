# Fixed office capacity

The office footprint is fixed at X −10…10 m, Z −5.4…23.1 m, with the current
baked sixteen desk groups and eighteen furniture interaction places. The visual
cap never limits provider execution or removes sidebar conversations.

Desk visibility prioritizes approval/input and failures, then working agents,
then remaining desk states. Within each tier, meaningful activity is newest first,
with stable agent identity breaking ties. Idle visibility uses the same activity
recency and retains only the newest eighteen finished/stopped agents. The shared
roster reducer rejects replayed events; persisted recency checkpoints preserve
receipt times across restart. Stale observations preserve known placement.

Surviving visible agents retain slots. Idle agents release physical desk slots;
returning agents prefer their previous desk if available. Overflow avatars are
not instantiated. The scene resolves only furniture anchors, never standing
conversation groups. An unreachable leisure destination hides that avatar while
its complete conversation remains accessible from the sidebar.

Saved unbounded placement maps are migrated into bounded assignments. Editing
clamps transformed furniture bounds inside the floor and wall clearance. Saved
out-of-bounds transforms are copied once to the UserDefaults recovery key
`officeLayoutDraft.fixedBoundsBackup.v1` before constrained values replace them.
Extra legacy desk edit records are retained for recovery but are not rendered.

Verification results follow after the release fixtures and regression run.

## Verification — October 2, 2026

- 67 release tests passed serially across eleven suites, including the fixed
  capacity, leisure, editor, shared office, lounge, roster, wall, meadow,
  external-observation, motion, and navigation regressions.
- The 64-agent mixed fixture renders 34 avatars, with exactly sixteen occupied
  desk groups and eighteen leisure destinations. Selecting a hidden agent
  preserves the camera and does not instantiate another avatar. The complete
  64-agent roster remains available. Snapshot: `/tmp/diorama-fixed-64.png`.
- Zero-overflow anchor generation and blocked destination handling were checked;
  no standing-group destinations are generated for the office.
- The single release development app was installed through the safe reload flow
  at 8:52 PM America/Los_Angeles. Its signature and DevelopmentRoot resource were
  verified. No provider turns were started or interrupted.
- File → Benchmark fixed office opens a provider-free, mixed 64-agent/34-avatar
  native fixture with wind, typing, leisure gestures, and camera movement. The
  attempted native capture became invalid when its window lost visibility
  (`/tmp/diorama-fixed-native-64.txt`). No sustained FPS result is claimed.
- Native UI inspection also intermittently timed out. A read-only sample of the
  previously running app showed substantial main-thread spatial projection/name
  resolution work. That is separate from this rendering-cap change; general UI
  latency is not claimed to be resolved by limiting avatars.
