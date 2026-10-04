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
`error_react`, `present_review`, `wait_review`, `celebrate_done`, `unknown_wait`, `cancel_cleanup`, `pickup`, `putdown`.
