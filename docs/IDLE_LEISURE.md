# Idle leisure activities

The approved layout is recorded in `OfficeFurniture/BakedOfficeLayout.json`.
Placement-node transforms preserve authored model rotations. Matching overrides
are removed only for the captured source project and only after comparing them
with instantiated defaults; other projects' edits remain intact.

Finished/stopped agents reserve a stable leisure slot. Priority is arcade (1),
pinball (1), foosball (4), sofas (8), and chairs (4). The subsequent fixed-capacity
change limits visibility to the eighteen most recently active idle agents, with
no standing overflow; see `FIXED_OFFICE_CAPACITY.md`. Returning
to work or leaving the visible roster releases a slot; retained idle occupants
stay put.
This code cannot send messages or resume provider execution.

Interaction anchors are in asset coordinates; scene transforms carry them along
with editor changes. The existing scene frame clock advances travel and gestures.
Routing uses a serial background actor with bounded navigation expansion and
request generations. Furniture editing pauses animation and exit replans routes.
Unknown/stale observations follow the existing placement rules.

Verification results are recorded after fixture inspection and native timing.

## Verification

52 release tests passed serially across nine suites: leisure, editor, shared office,
lounge, navigation, capybara motion, walls, meadow, and external observation.
Tests cover occupancy thresholds through 64 agents, stable vacancies, old saved
state, scoped bake migration, pause/resume, mid-route redirection, blocked routes,
and reachable approaches for all 18 furniture places. Four-angle 18/64-agent
snapshots were inspected. Matching source-project draft transforms were removed
after the baked layout comparison; the export now contains an empty override map.

No provider execution or message-submission paths were changed. No paid turns were
started. The native benchmark results are recorded separately below.

A subsequent 28-test targeted rerun passed after eliminating redundant layout
persistence and tightening rapid route cancellation. The standalone test-host
native benchmark was invalid: both windows reported occluded and produced zero
frame samples at 2294×1340 backing pixels. Zero samples are not a performance pass.
The installed app also exposes File → Benchmark standing office for a native,
provider-free 16/64-agent capture including orbit, zoom, and observation updates.

The installed release app's native 16-agent standing fixture captured 9,062 frame
intervals at 2294×1560 backing pixels with a requested 120 FPS. Median was 9.45 ms,
p95 17.16 ms, and one interval exceeded 33 ms. The benchmark reported PASS for its
approximately-60-FPS acceptance threshold; this is not sustained 120 FPS. Cold load
plus warm-up took 8.78 seconds. Meadow cache used 17,497,152 bytes.

The subsequent native 64-agent capture became invalid when its window was no
longer visible/playing. Retrying app inspection returned `cgWindowNotFound`, so
64-agent native performance remains unverified. No claim of a 64-agent 60-FPS pass
is made. Functional and four-angle fixture checks above still passed. The release
app was safely installed and launched through the development reload flow at
2026-10-03 02:03:22 UTC; its code signature was verified.
