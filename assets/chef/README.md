# Chef avatar

Rigged, animated chef used by the Kitchen scene to represent coding agents. Vendored from
[davidfromkansas/avatar_animation_repro](https://github.com/davidfromkansas/avatar_animation_repro)
at `eb325d2e7aef2dfda83bec89118bd1ae463d19df` (2026-10-04); this folder is now the source of truth.

| Path | What |
|---|---|
| `source/…_texture.glb` | Untouched Meshy source model (SHA-256 `25c78e34…`, see the manifest) |
| `chef-rigged.blend` | Editable source: mesh, deform skeleton, IK controls, `ctrl_*` authoring actions, baked clips |
| `blender/` | Pipeline: `build_chef.py` (rig, weights, clips, bake, export), `chef_anims.py` (pose keys per clip), `chef_props.py`, `render_clips.py` (review renders) |
| `verify/` | Re-imports the exported GLB with glTF-Transform and checks skin, weights, clips and sockets |
| `../../Sources/DioramaApp/Resources/Chef/` | Runtime outputs bundled in the app: `chef-animated.glb`, `chef-props.glb`, `chef-manifest.json` |
| `../../docs/chef/` | Rig report and per-clip review sheets |

## Rebuild (needs Blender 5.x; the app never needs Blender)

```sh
assets/chef/build.sh             # build, copy into Resources/Chef, verify, render review sheets
RENDER=0 assets/chef/build.sh    # skip the review renders
```

Intermediate files go to `.local/chef-build/`. Review sheets need Pillow.

## Runtime contract (checked by the app's loader and tests)

- One skinned mesh, one material (embedded base colour, normal, packed metallic-roughness), skin `chef_rig` with 26 joints.
- Clips are in place, sampled at 30 fps, LINEAR. Navigation moves the avatar root.
- Sockets `socket_hand.L`, `socket_hand.R`, `socket_carry`; prop attach transforms live in the manifest.
- glTF has no events: clip markers (chop impact, plate attach/release…) live only in `chef-manifest.json`.
- The chef faces +Z, soles at y = 0, height 1.90 source units. Diorama scales the visual node only.

Clips: `idle_available`, `planning_recipe`, `researching_book`, `working_chop`, `waiting_tool`, `testing_dish`,
`walk`, `run`, `carry_idle`, `carry_walk`, `request_input`, `wait_input`, `blocked_react`, `blocked_wait`,
`error_react`, `present_review`, `wait_review`, `celebrate_done`, `unknown_wait`, `cancel_cleanup`, `pickup`, `putdown`,
`strike_gong` (a chef that needs you strikes the service gong), `talk_reply` (talking it over with the manager), `manager_talk` (the manager), the break room's `play_arcade`, `use_vending`, `brew_espresso`, `stand_sip`, `stand_listen` and `stand_laugh`,
and the kitchen lifecycle clips `arrive_wave` (elevator arrival), `read_ticket` (reading the order), `sit_down`, `stand_up`,
`sit_idle`, `sit_sip`, `sit_chat` (break-room lounge chairs) and `cover_dish` (serving window).

Props: recipe card, cookbook, knife, spoon, plate, ingredient, cutting board, pot, plus `prop_ticket`, `prop_mug`, `prop_cloche`, `prop_gong_mallet` and `prop_can`.
Sitting clips are authored for the bundled Eames Lounge Chair–Classic scaled 1.45× (`KitchenStationGeometry.loungeChairScale`).

## Chef characters

Besides the original chef, nine more characters (capybara, cat, pig, monkey, tiger, bunny, mouse,
little chef, puppy) wear the chef's skeleton and play its clips. Each new chef in a kitchen gets
a random character that no other chef there is wearing; characters repeat only once all ten are
in use. The choice is saved per agent (`~/Library/Application Support/Diorama/ChefCharacters.json`).

```sh
assets/chef/build_variants.sh [id,id]      # RENDER=0 skips the review sheets
```

- `variants.json` lists the characters: id, display name, source GLB and an optional tail region
  (which follows the hips). The source GLBs are the original Meshy downloads (about 20 MB each);
  they are not in git. To rebuild, put them in `variants/source/` (the file names are in
  `variants.json`, and each character's SHA-256 is recorded in `chef-variants.json`).
- `blender/build_variant.py` fits one character:
  - decimates it to the chef's triangle budget;
  - stands it on the chef's ankle point;
  - finds its arms with Blender's bone heat, then swings and slightly stretches them from the
    shoulder so its hands sit where the chef's do, so props land in its hands;
  - removes the triangles where a hand was fused to the body;
  - skins it with the chef's weights, with three changes: tails follow the hips, apron (found by
    its colour) drapes over the thighs, and the waist-to-knee weights are smoothed;
  - exports `chef-<id>.glb` (mesh, skin and the chef's 28 nodes, 1024 px textures, no clips).
- `verify/verify-variants.mjs` checks every character against `chef-animated.glb`: the same nodes
  in the same order (clips address nodes by index), the same joints, complete weights, three
  textures, and the triangle budget.
- Review sheets for each character go to `docs/chef/variants/`.

In the app, `ChefAssets.characters` lists them from `Resources/Chef/chef-variants.json`.
`ChefAssets.rig(for:)` loads a character on first use, borrowing the chef's clips
(`WorkspaceCapybaraAsset(data:spec:clipsFrom:)`), and `preload()` warms them in the background.
Restaurant diners and the title screen keep the original chef.

### Budgets and baking

Each list sets its budget (`variants.json`, `guests.json`): chefs 5k triangles with 1024 px colour,
guests 3k with 512 px colour (both 512 px normal maps, 256 px metal/roughness, JPEG). After
simplifying, `blender/bake_detail.py` bakes the full model onto the simplified one (Cycles,
selected-to-active): its surface normals become the normal map, and its colours are re-projected
onto the simplified mesh's UVs (without that, simplification stretches painted eyes and mouths).
Seams are welded before simplifying so they don't crack open. Comparison:
`docs/restaurant/guests/bake-comparison.png`. The original chef's export drops animation channels
that never change (`export_optimize_animation_size`), which halves its clip data.

## Kitchen staff

`staff.json` lists characters that work in the kitchen without being an agent: the manager (head
chef), fitted like the chef characters (`assets/chef/build_variants.sh --staff`, source in
`staff/source/`, not in git) to `Resources/Chef/staff-manager.glb` and `staff-list.json`.
