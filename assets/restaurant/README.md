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
| `../chef/blender/diner_outfits.py` | Paints the six diner outfits (`Resources/Restaurant/diner_NN.jpg`) from the chef texture |
| `../../docs/restaurant/` | Review renders from the app's renderer (home, terrace, side, diners) |

```sh
assets/restaurant/build.sh
Blender -b --factory-startup -P assets/chef/blender/diner_outfits.py -- \
  Sources/DioramaApp/Resources/Chef/chef-animated.glb Sources/DioramaApp/Resources/Restaurant
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
