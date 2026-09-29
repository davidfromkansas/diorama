# Shared project office

The compact Portfolio Home remains a grid of blank Canvas platforms and metadata cards.
Project scopes now use one continuous floor. Conversation and agent scopes frame the same
floor rather than rebuilding separate team islands. Imported standalone conversations retain
the existing team renderer.

## Membership and placement

`OfficeRoster` projects the existing provider-aware spatial hierarchy. Explicitly reported
subagents retain their scoped identity; merged conversations and worktree membership continue
to use existing discovery. Desk proximity has no semantic meaning. Working, waiting, failed,
unknown and stale agents stay visible. Finished/stopped turns remain for 30 minutes from their
reported state time; historical completions with no reliable time are not treated as recent.
Opening an older conversation explicitly includes its agents. All conversations provides that
path, with the existing archive filter available in the menu.

`SharedOfficeLayout` assigns permanent slots for the in-memory session. Four desks form a
spatial cluster; clusters expand outwards around a clear central cross. Floor extents never
shrink and status/order changes do not move existing assignments. Desk transforms and local
avatar transforms are separate, leaving room for later movement without changing identity.
There are no facilities, implied workflow dependencies or walking behavior in this version.

## Rendering and actions

Aeron ESD C-size and Nevi C-foot source meshes are converted from official DWGs. See
`Resources/OfficeFurniture/SOURCES.md` and `manifest.json` for provenance and the owner's
permission confirmation. Metre dimensions are preserved. The existing capybara is uniformly
scaled and seated with length-preserving arm rotations; working agents have restrained typing.
The generated lower-detail avatar retains its skeleton; distant furniture uses simplified
versions of the same meshes. Geometry/materials are shared across instances. SceneKit culls
geometry, and frustum visibility gates animation. Home and inactive/reduced-motion states stop
motion. Home retains the mounted office scene.

Agent and monitor targets route to the original expanded work screen. Escape and the return
button return directly to the project office. Existing transcript renderers, provider controls,
observation-only restrictions and child activity readers remain authoritative. Navigation does
not create or resume a turn. The native Agents list provides an equivalent keyboard path.

## Verification

The complete serial suite passed 396 tests in 96 suites. Subsequent focused tests cover final
pose/material/culling refinements. Tests include source dimensions, supported paw positions,
completion expiry and uncertainty, 204 stable placements, retained scene nodes across Home,
64-agent rendering, provider fixtures updated without conversation selection, and navigation.
Local snapshots are written to `/tmp/diorama-workstation-{front,side,office}.png` and
`/tmp/diorama-shared-office-64.png`. No paid turn is generated for verification.

Final local verification: `dist/Diorama Office.app` built and launched with bundle identifier
`local.diorama.office`. Checked Home → live project → native Agents list → existing work
screen → Escape → office; All conversations → historical conversation on the same floor;
and return to Home with blank platforms and retained scrolling. The current externally
started Codex task appeared without opening its conversation first. External Claude updates
were verified through deterministic provider fixtures. Narrow rendering and Reduced Motion
were exercised by fixtures; manual VoiceOver traversal was not performed. The CUA coordinate
click tool returned `noWindowsAvailable`, so physical avatar clicking was not verified in the
live app; native list routing was verified. Approval, steering and stop paths were not exercised
against paid live turns. No execution was started for verification.

## Minimum furnished office

An office now starts with sixteen physical desks and chairs, even with no agents. Empty desks
have no avatar, activity indicator or action target, and do not contribute to agent counts.
The same stable slot becomes occupied when an agent arrives and returns to empty furniture
when that occupant leaves. Capacity grows beyond sixteen without moving assigned seats.
The project camera defaults to 30° elevation and 45° azimuth, with a beveled 38 cm display
base and soft directional shadows. Project framing includes empty seats; team/agent focus
still frames the relevant work. Fourteen office/navigation tests passed after this change,
including an empty → occupied → empty regression and a rendered empty-office fixture.

Desk finish correction: Nevi uses a neutral white tabletop/edge, gray frame and dark glides,
matching the supplied product reference rather than the previous green presentation tint.
CAD material groups are copied before assigning finishes. The low-detail export now preserves
small planar parts; the tabletop had previously been decimated away. Six shared-office tests
passed, including a low-detail tabletop-height regression; near and distant renders inspected.

The floor surface uses the user-supplied OfficeFloorBaseColor.png unchanged, as base color
with physically based roughness 0.95 and metalness 0. Mirrored wrapping removes color jumps
seen with ordinary repeats; overview and close-up seam renders were inspected. Each image
spans 3.2 metres, with world-anchored UVs and anisotropic/mipmap filtering. The display base
and walls retain separate materials. Close-up fixture: /tmp/diorama-floor-seams.png.

## Cream-and-walnut walls

The two far walls now use `OfficeWall`: 2.90 m tall, 0.64 m thick, with 1.16 m
walnut wainscoting, physically recessed panels, horizontal rails, vertical stiles,
warm cream modules, and a softly chamfered cap. Nominal modules target 1.8 m.
Procedural grain follows each piece's local axes and requires no downloaded texture.
Both faces and free ends are finished. The corner uses matching clipped mitre planes
for the core, trim and caps instead of overlapping wall boxes. Wall nodes continue to
rebuild only when the office floor dimensions change.

Verification: 27 wall/office/meadow/spatial/navigation tests passed, followed by eight
wall/office tests after final cap and inset fixes. Four corner views and the 16-desk
and 64-agent office fixtures were rendered. Shader fallback color is checked by the
rendering test, alongside height, module sizing and the mitre clipping plane.
