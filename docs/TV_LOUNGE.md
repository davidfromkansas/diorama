# TV lounge

The office contains two complete Luva corner sectionals and four Eames Lounge
Chairs without ottomans. The official Eames Classic CAD included an ottoman;
its disconnected geometry beyond CAD X=20 inches is omitted during conversion.
All manufacturer dimensions are retained. Shared low-detail instances contain
approximately 12,000 triangles per sectional and 4,000 per chair.

The supplied television is stored at 1.9 metres wide, then uniformly scaled 2×
at presentation per the user's follow-up: 3.8 metres wide and approximately
2.47 metres tall. Its back aligns with the right-hand wall. It is static artwork,
not a media player or live feed.

OfficeLeisureLayout reads measured asset dimensions and provides furniture
transforms, occupied bounds, and a reserved seating zone. The central aisle and
space between sofa/chair rows are at least 1.2 metres. The existing arcade,
pinball, and desks keep their world positions. Additional idle agents use the
clear corridor left of the lounge. Stable slot identities and existing saved
assignments are preserved; known overflow slot coordinates change to avoid the
new furniture. Furniture nodes and shared geometry survive floor resizing.

Reproduction:
- Download the official source DWGs linked in Resources/OfficeFurniture/SOURCES.md.
- Convert DWG to DXF using LibreDWG dwg2dxf.
- Run scripts/convert-lounge-furniture.py with ezdxf.
- Run Blender with scripts/prepare-office-arcade.py, the supplied TV GLB,
  output directory, LoungeTV, 24000, width.
- Run Blender with scripts/prepare-lounge-lod.py on that directory.
- Source hashes, dimensions, and triangle counts are captured with the assets.

Verification results are appended after final regression and render checks.

## Verification — 2026-10-02

27 release-configuration tests passed serially across OfficeLoungeTests,
SharedOfficeTests, OfficeWallTests, OfficeMeadowTests, and
WorkspaceNavigationTests. Covered model counts, 2× TV dimensions and wall
alignment, 1.2 m aisles, non-overlap, furniture identity across expansion,
standing-slot exclusions, and existing navigation behavior.

Inspected empty, 16-agent, and 64-agent fixture renders across all four orbit
directions and a close-up. Also inspected the updated lounge in the running
Taipei office and confirmed agent selection still changes the selected agent.
No paid turns were started. The single development app safely reloaded at
2026-10-03 00:52:07 UTC.

Thirty measured synchronous snapshots per condition after six warm-up frames,
1200×800-point offscreen view, static avatars; visible/hidden lounge samples
were interleaved in the same scene to isolate incremental furniture cost:

| Agents | Lounge | Median | p95 |
|---|---|---|---|
| 16 | Hidden | 5.67 ms | 8.83 ms |
| 16 | Visible | 5.72 ms | 7.71 ms |
| 64 | Hidden | 8.91 ms | 10.41 ms |
| 64 | Visible | 8.85 ms | 10.66 ms |

The measured median difference is negligible in this fixture; variation in p95
is mixed. This is not a sustained native-display FPS measurement and does not
establish a 60 FPS guarantee during wind, typing, or camera motion. Hiding only
new furniture also does not measure the cost of the enlarged floor. Timing
output: /tmp/diorama-lounge-render-cost.txt. Native interaction remained usable
during visual inspection; a full sustained Retina performance capture was not
performed for this furniture addition.

## Foosball addition

Added the user-supplied Flame Striker model as `loungeFoosball`, beyond the
seating with 1.2 m clearance. Original textures and proportions are preserved at
0.9 m height; the footprint includes protruding handles. The same shared layout
extends the floor and keeps idle agents clear. Edit mode selects it independently.
Conversion details and source hash are in `OfficeFurniture/SOURCES.md`.

Verification: 17 release tests passed across lounge, shared-office, and layout-editor
suites. Inspected 16-agent and reverse-angle 64-agent snapshots. Static 1200×800
offscreen medians with all lounge furniture visible were 5.20 ms (16 agents) and
8.25 ms (64); these are not sustained native-display FPS measurements.
