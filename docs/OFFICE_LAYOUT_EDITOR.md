# Office furniture edit mode

With the office visible, press E to enter edit mode. Text-entry fields keep their
normal E/1/2 keys. Click furniture to select it, then drag on the horizontal floor
plane. 1 rotates counterclockwise and 2 clockwise by 15 degrees per press.
E or Escape finishes editing. Scroll still adjusts camera framing; dragging does
not orbit or open conversations while editing. The floor and walls are fixed.

Each desk, chair, and monitor moves as a group. Working agents remain with their
desks; standing agents retain their world positions when their reserved desks
move or rotate. Arcade, pinball, TV, each sectional, and each Eames chair are
independently editable. A blue outline identifies the selection. Transforms are
clamped to the office floor and wall clearances; other furniture can overlap
intentionally during arranging (there is no collision solver).

Drafts are per project and keyed by stable furniture identity. They survive
observation updates, empty/occupied desk replacement, and app restart. They do
not change provider execution or the compiled default arrangement. Home,
project changes, backgrounding, and teardown end editing and save the draft.

The development app writes an atomic JSON export to:
`.local/office-layout-drafts.json`

The top-level key is project identity, then furniture identity. Each transform
contains world-floor `x`, `z`, and `rotationRadians` of its placement node.
For leisure assets this rotation is added to the existing authored/base
orientation. Desk slots use `desk:N` identities and keep their ownership.
Drafts also live in the `officeLayoutDraft.v1` UserDefaults field. Export I/O
runs on a serial background queue at drag end, rotation, and edit completion,
not per mouse movement. An export failure retains local settings and shows an
error while editing.

To bake a user-approved arrangement later, read that JSON and map the selected
project's transforms into the built-in placement defaults. Remove only the
corresponding overrides once the new defaults are verified, so stale draft
coordinates do not mask subsequent default changes. Do not bake without the
user's follow-up request.

## Verification (2026-10-02)

The release-configured editor, shared-office, lounge, and navigation suites passed
24 tests serially. They cover floor-ray intersection, drag grab offsets, paired
rotation, persistence, project isolation, clamping, and standing-agent positions.
The canonical development app was staged and safely relaunched. Native UI checks
confirmed E entry, furniture selection, a 15-degree rotation, and its reversal;
the JSON export reflected both changes. Live dragging could not be completed
because the UI automation surface became unavailable. Code-signature validation
and `git diff --check` passed. No paid agent turns were started.
