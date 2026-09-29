# Office meadow

`OfficeMeadow` owns the decorative ground and batched grass meshes. `SpatialSceneView`
passes the project identity, office footprint, orthographic camera coverage and lifecycle.
The existing office geometry, camera framing and provider execution paths are unchanged.

- Stable FNV/mixed coordinate seeds generate metre-scale clumps; candidates retain their
  positions when the office expands or detail drops. Roots are excluded by 60 cm from
  the office footprint, beyond the maximum authored curve and shader displacement.
- Blades are 35–65 cm with occasional 75 cm tips. Shared matte, double-sided materials
  use darker roots and lighter tips. Grass has no shadow casting or selection targets.
- Each patch is one mesh. Near patches use four segments and distant patches two.
  Density is bounded to 48,000 rendered blades, with smooth world-space thinning farther
  from the office. A uniform orthographic candidate budget avoids square density islands.
  At extreme zoom-out blades become sparse to respect the cap.
- Coverage follows the camera's intersection with the ground, with a margin for blade
  height and bending. SceneKit performs frustum culling; at most 512 patches are cached.
- One shared GPU geometry shader bends tips, preserving roots. A 5.5-second sway is
  combined with a traveling 10-second gust and independent phase variations.
- Only the wind-time uniform changes each frame. The 30 Hz clock stops on Home, inactive
  windows, teardown and Reduced Motion. Resuming retains elapsed wind time, without
  including hidden time. No per-blade CPU animation or execution calls are used.

References: [Ghost of Tsushima](https://www.gdcvault.com/play/1027033/Advanced-Graphics-Summit-Procedural-Grass),
[Horizon Zero Dawn](https://gdcvault.com/play/1025066/Between-Tech-and-Art-The), and
[AMD procedural grass](https://gpuopen.com/learn/mesh_shaders/mesh_shaders-procedural_grass_rendering/).
These informed blade batching, variation and coherent wind; no reference assets are bundled.

## Verification (2026-09-29)

61 selected tests passed serially across meadow, shared office, spatial navigation,
portfolio, external observations/viewers, and scene/motion suites. The final LOD adjustment
was followed by another passing five-test meadow run. Tests cover deterministic roots,
exclusion and expansion, detail subsets, geometry/cache limits, lifecycle and shader output.

Stills cover four orbit quadrants at minimum and maximum zoom/elevation. A 12-second,
10-fps close-up GIF covers one gust cycle. Artifacts are generated under `/tmp/diorama-meadow-*`.
The final run's synchronous 1200×800 snapshots (including GPU readback) measured:

| Fixture | Blades | Median | p95 |
| --- | ---: | ---: | ---: |
| 16 empty desks | 34,089 | 4.25 ms | 5.79 ms |
| 64 agents | 29,202 | 8.22 ms | 10.24 ms |

These are offscreen rendering timings with wind updates and static avatar poses, not a
sustained interactive frame-rate or power benchmark. Both are below the 33.3 ms target.
The local app was rebuilt, signed and launched; project → existing agent work screen →
office → Home navigation was exercised. The selected historical agent's transcript was
unavailable, and no reconnect, prompt, or paid agent turn was triggered.
