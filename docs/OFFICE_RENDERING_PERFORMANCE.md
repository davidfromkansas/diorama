# Office rendering performance

## Implemented

- The shared office uses a view-associated AppKit display link and requests the screen's refresh rate, capped at 120 Hz. Screen changes update the request. Camera input accumulates until the next display frame; camera travel remains interruptible.
- Hidden/Home, inactive, and occluded views stop continuous rendering and wind time. Reduced Motion retains static rendering, including completion of pending resource preparation.
- Meadow requests compute coverage only. A detached worker produces deterministic immutable vertex/index buffers; main-actor installation has a 2 ms scheduling budget per frame. A single installation cannot be preempted, so individual upload duration is instrumented.
- Geometry is prepared before replacing visible coverage. Cancelled project/footprint jobs are rejected; visibility-obsolete results are filtered. Preparation cancelled by hiding can resume without leaving the stream stuck.
- Grass retains world-space roots across density/detail variants, uses discrete tiers and hysteresis, and prefetches a patch ring. The LRU accounts for vertex/index bytes (128 MiB cap), with a separate 48,000 rendered-blade cap. This byte metric is not total process/GPU resident memory.
- Empty and occupied furniture share projected-size detail selection, with hysteresis. Geometry/materials remain shared across cloned instances.
- Agent presentation results are cached by relevant source values and freshness boundaries, including child freshness expiration. Unrelated project updates do not reconcile the focused office. Project membership assembly still runs; it is not a fully incremental library index.
- The quality hysteresis policy is implemented and unit-tested, but automatic GPU-driven quality changes are disabled pending reliable onscreen GPU timing. Live verification exposed a Metal assertion in the original offscreen multisampling probe with deferred shadows. A regression test reproduces that configuration. The fixed probe uses single-sample targets, is profiling-only, and cannot drive onscreen quality because it excludes MSAA. Normal rendering requests the display rate up to 120 Hz with the current visual quality.


## Diagnostics

Opt in with `DIORAMA_PROFILE_SCENE=1`. Signposts cover camera updates, meadow generation/upload, reconciliation, spatial projection and rendered frames. Individual comparison switches are `DIORAMA_DISABLE_MEADOW=1`, `DIORAMA_DISABLE_FURNITURE=1`, `DIORAMA_DISABLE_SHADOWS=1`, and `DIORAMA_DISABLE_OVERLAYS=1`; they require the profiling opt-in.

Launch the packaged app with `--scene-benchmark` (or set the diagnostic bundle-only `DioramaSceneBenchmark` Boolean). This explicit mode uses 16 and 64 working-agent fixtures without provider execution. Each fixture warms up, captures 30 seconds of wind/typing/orbit/zoom and periodic observation changes, and writes `/tmp/diorama-native-16.txt` or `/tmp/diorama-native-64.txt`. Results include backing resolution, requested refresh rate, cold load plus warm-up, median/p95 intervals, stalls above 33 ms, and cache bytes. Renderer callbacks measure CPU-side delivered cadence, not display presentation timestamps; corroborate with Instruments Game Performance/Metal tracing.

Normal launch always opens the real workspace. No saved settings migration, paid turns, or execution changes are involved.

## Verification on 2026-09-29

- Serial rendering/navigation/external-viewer regression run: 141 tests passed.
- Serial core/provider regression run: 266 tests passed.
- Additional performance tests passed for quality hysteresis, obsolete requests, cache bounds, cancelled preparation/resume, projection invalidation, child freshness expiration, and GPU command-buffer timing.
- Deterministic camera interruption and meadow lifecycle/placement tests passed. Inspected generated office snapshot for retained floor, furniture, walls and meadow.
- Optimized release build packaged locally as `dist/Diorama Office.app`.

## Valid native capture results

Both fixtures completed visible captures at **3024 × 1898 backing pixels**, requesting **120 Hz**, on this Mac. Each ran for at least 30 seconds after warm-up, with live avatar typing, wind, continuous orbit/zoom and periodic fixture observation updates. These are renderer callback frame intervals, not proof of 120 distinct displayed frames every second.

| Fixture | Samples | Median | p95 | Intervals >33 ms | Cold load + 2 s warm-up | Cached mesh buffers |
|---|---:|---:|---:|---:|---:|---:|
| 16 agents | 3,771 | 8.32 ms | 9.70 ms | 0 | 5.55 s | 23.52 MiB |
| 64 agents | 4,128 | 8.25 ms | 11.73 ms | 0 | 2.60 s | 16.73 MiB |

Both meet the requested 60 FPS callback-interval threshold (95% within approximately 17 ms) with no >33 ms intervals in the captures. Median cadence is approximately 120 Hz; sustained 120 FPS is not claimed because p95 exceeds 8.33 ms. Counts exceed 3,600 because the sampling loop awaits 300 intervals of at least 100 ms; captures can be longer than 30 seconds under load. The 64-agent load follows the 16-agent run and benefits from warmed assets; its startup is not an independent cold launch.

Reports are retained in `artifacts/office-performance/native-16.txt` and `native-64.txt`. Instruments Game Performance was attached during the valid run (`/tmp/diorama-visible-game.trace`); The trace saved successfully and its table of contents exported successfully; detailed CPU/GPU attribution has not yet been analyzed because the frame-interval acceptance threshold passed. No diagnostic visual-quality switches were enabled for these passing captures, and the GPU probe and automatic quality adjustment were disabled.

Real project → agent work screen → office → Home navigation passed without executing a paid turn. Remaining coverage: a separate 60 Hz display, cross-display moves, VoiceOver/Reduced Motion UI checks, and isolated comparisons of meadow/furniture/shadows/overlays. These captures establish steady-state cadence for the tested workload, not universal performance across every project or display.

## Follow-up capture attempt

The release app was launched through computer use and an Instruments Game Performance trace was recorded at `/tmp/diorama-release-game.trace`. Both fixture runs reported an occluded window and zero delivered frames; this trace is not a valid sustained-FPS result. The benchmark now waits for a visible window and rejects captures interrupted by occlusion or producing no frames. The guarded benchmark remains open awaiting a visible desktop; the packaged app’s next normal launch opens the real workspace. Native acceptance remains pending.

A subsequent diagnostic run confirmed the view has a window on the built-in Retina display (`isVisible=true`, `isMiniaturized=false`, app not hidden), but `isOnActiveSpace=false` and occlusion visibility remains false. Floating/cross-Space diagnostic behavior did not resolve this. Captures now monitor visibility throughout the run, and low frame counts are reported as performance failures rather than automatically classified as occlusion. The blocked benchmark was closed and the normal release bundle restored. Live FPS acceptance remains blocked pending an active desktop session.

## Crash fix and navigation follow-up

Live activation exposed a Metal texture assertion in `SceneGPUProbe.Job.run`: SceneKit deferred-shadow resources could not use the externally multisampled pass. The new deferred-shadow regression test failed before the fix and passed afterward. The probe now uses single-sample targets and is isolated behind diagnostic opt-in; automatic adaptation is disabled rather than using misleading single-sample timings. Nineteen focused rendering tests passed after the fix. The rebuilt app successfully entered full screen; real project → agent work screen → office → Home navigation was verified without executing a turn.

The valid captures above supersede the earlier blocked attempts below; those attempts remain documented to avoid confusing invalid files/traces with acceptance evidence.
