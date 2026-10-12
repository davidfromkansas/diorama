# Restaurant

The Mediterranean restaurant around the kitchen (Overcooked 2 style). Diners sit at café tables
along both sides of the kitchen, where the home camera sees them (wide windows show only thin
strips in front of and behind the kitchen); a clay-and-sandstone checkered terrace wraps around
with a fountain and umbrella tables out front, lemon trees, lamps and geraniums,
a barrel-tiled terracotta roof behind the back wall, and a canal with lily pads, a jetty and a
rowboat. Original work, modelled procedurally in Blender.

| Path | What |
|---|---|
| `blender/build_restaurant.py` | Builds every piece and exports the GLB (source of truth) |
| `restaurant.blend` | The built scene, with `KitchenRef` stand-ins and the app's home camera for reviews |
| `build.sh` | Headless rebuild into `Sources/DioramaApp/Resources/Restaurant/restaurant.glb` |
| `../chef/guests.json` | The ten guests who sit at the tables (built by `assets/chef/build_variants.sh --guests` into `Resources/Restaurant/guest-*.glb`) |
| `../../docs/restaurant/` | Review renders from the app's renderer (home, terrace, side, diners) |

```sh
assets/restaurant/build.sh
assets/chef/build_variants.sh --guests     # the guests; sources (Meshy downloads) not in git
```

## Contract with the app (`KitchenRestaurant.swift`)

- Kitchen world units; the kitchen itself (x -12…12, z -8…8 in SceneKit) is not part of the model.
  Blender's -y is SceneKit's +z (toward the camera).
- Root node `restaurant`. Empties `seat_NN` (where a seated diner's root stands) and `dish_NN`
  (the plate spot on the table in front of it), numbered nearest the serving pass first.
  Chair seats are 0.64 high to fit the chef rig's `sit_*` clips at the kitchen's 1.4 scale.
- `water` is the canal plane; the app gives it a ripple shader.
- Colours are authored as the sRGB values the app shows (its loader reads `baseColorFactor` as
  sRGB); `restaurant.blend` reviews with the Raw view transform to match.
- About 70k triangles, flat-colour PBR materials (no textures), 4.9 MB.

## Guests

Ten characters (`assets/chef/guests.json`) fitted to the chef's skeleton like the chef characters,
at a lower budget since they're seen small: 3k triangles with the full model's detail baked into
512 px colour and normal maps (about 0.4 MB each, from 20 to 39 MB downloads). The original downloads go in
`assets/chef/guests/source/` and aren't in git.

In the app (`RestaurantGuests.swift`, `KitchenSceneView.seatDiners`) all twelve seats are filled:
each guest once, the two repeats at the seats farthest from their twin. Every table has food. Each
guest switches between `sit_talk`, `sit_gesture`, `sit_eat`, `sit_laugh`, `sit_sip` and `sit_idle` on
its own seeded clock; table partners take turns (one talks, the other listens, laughs or eats). A
served task's dish replaces a guest's plate: `sit_cheer`, then eating until the work is accepted.

## Size

`restaurant.glb` has no textures. The export drops what no kitchen camera can see: faces turned
well below horizontal on closed surfaces (every kitchen camera looks down at 62°), and texture
coordinates everywhere but the water (whose shimmer shader uses them). 5.0 MB → 3.0 MB, with
renders from the app's camera identical.
