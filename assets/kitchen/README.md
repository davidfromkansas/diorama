# Kitchen range, cooking island and back stations

## Range

The stove island is an Italian metalwork range (Officine Gullo style): sage enamel deck and
body, a brushed-steel plate framed in brass under each of six brass burner crowns with cast-iron
grates, knurled brass knobs on an engraved rail, a full-width polished brass towel bar, three
framed ovens with brass handles, and warming drawers. No hood, so chefs and flames stay in view.

| Path | What |
|---|---|
| `blender/kitchen_kit.py` | Shared materials, primitives, assembly and export |
| `blender/build_stove.py` | Builds the range and exports `stove.glb` (source of truth) |
| `blender/build_island.py` | Builds the cooking island and exports `island.glb` |
| `blender/french_back.py` | The back-wall stations' shared counter, splashback and enamel plaques |
| `blender/build_order.py`, `build_prep.py`, `build_tasting.py`, `build_pantry.py` | Build the Orders pass, Prep dresser, Tasting pass and Pantry (`order.glb`, `prep.glb`, `tasting.glb`, `pantry.glb`) |
| `blender/build_connectors.py` | Builds the cabinets between the wall stations (`connectors.glb`, in kitchen space) |
| `build.sh` | Headless rebuild of both into `Sources/DioramaApp/Resources/KitchenStations/`, plus review renders |
| `../../docs/kitchen/stove/`, `island/` | Review renders (kitchen view, three-quarter, close-up) |

```sh
assets/kitchen/build.sh
```

## Contract with the app (`KitchenStove.swift`)

- Kitchen world units. Origin: the stove footprint's centre on the kitchen floor; the app places
  the root `stove` at the footprint centre, at `KitchenLayout.floorTop`. Blender -y is the camera
  side (SceneKit +z).
- Everything stays inside the footprint (9.0 x 1.2): chefs walk around the footprint, not the
  mesh. The body is set back 0.16 on the camera side so the towel bar and handles fit.
- The deck is at 0.707 (worktop 0.819 minus floor 0.112) and flat on the chefs' side, where a
  chef sets its pot down.
- Empties `burner_0`..`burner_5`, left to right under the chefs' stove spots, sit on each burner
  crown; the app lights each `stove#N` flame there (`KitchenSceneView.updateFlames`). If the model
  can't load, the old procedural counter and flame spots are used.
- About 26k triangles, flat PBR colours (no textures), faces the 62° kitchen camera can't see
  removed; under 1.5 MB.

## Cooking island

French industrial: a honed Carrara marble top (veins generated in the script and baked to a
2048 x 288 texture, sampled in metres so they don't stretch), a blackened-steel frame flush
under the slab's edge with turned bronze shoes, collars, corner gussets, a riveted apron with a
bronze band and a bronze rail, and two tiers of oak shelves stocked with copper pots, stacked
bowls, utensil crocks and striped linens. A bronze salt cellar and an oil cruet sit on the
camera side of the top.

Contract with the app (`KitchenIsland.swift`):
- Same units and origin as the range; root `island`; inside the cooking footprint (9.0 x 1.2);
  marble top at 0.707 above the floor (the worktop).
- Empties `board_0`..`board_5`, left to right, 0.38 in from the chefs' edge: the app puts a
  plain `"cutting board"` on each, so the kitchen's board logic (the resting cleaver on free
  boards, chefs chopping on them) works unchanged. If the model can't load, the old counter is used.
- About 20k triangles; only the marble is textured; about 1 MB.

## Back stations: Orders and Prep

Both share a French back counter (`french_back.py`): deep-green lacquered base with raised-panel
doors, polished brass bar pulls and a bronze kick plate; a Carrara marble top (the island's
generator, `kitchen_kit.marble_slab`); a crackle-glaze tiled splashback in brick bond edged in brass;
and deep-green enamel plaques with ivory lettering.

- **Orders (`order.glb`)**: a polished brass ticket rail with handwritten orders clipped to it under
  a *COMMANDES* plaque and two brass picture lights, a black enamel station clock, and on the
  counter's back a brass ticket spike, a service bell and slate menu boards.
- **Prep (`prep.glb`)**: dresser sections either side of the window: open oak shelves edged in
  brass with leather cookbooks (gilt bands), tureens, copper moulds and jars; tall glass-fronted
  cabinets with brass glazing bars at the ends; a framed cork recipe board with cards pinned in
  brass; a carved ivory cornice with dentils. A *PRÉPARATION* plaque under the window with herbs
  either side, a brass scale and a mortar and pestle at the ends.

Contract with the app (`KitchenFixtures.swift`): root named `order` / `prep`, origin at the
footprint's centre on the floor, Blender -y toward the room; inside the footprint; worktop at
0.707; the top's front strip (y < -0.05) clear, where chefs set their idea or plate down; the
room's window (x -1.36..1.36 of the Prep counter, from 0.94 up) left open. If a model can't load,
the procedural counter is used.

## Tasting pass and connecting cabinets

- **Tasting (`tasting.glb`)**, after Michelin passes (the marble-and-brass pass at Mamani, Dallas;
  the classic heat-lamp pass): the shared counter with, over its back, a polished brass gantry
  holding a marble plate shelf with stacks of white plates and a brass gallery rail, an extendable
  brass pass lamp over each taster, and a *DÉGUSTATION* plaque on brass posts. On the counter's
  back: two brass bar sinks (dipper wells) with swan-neck taps between the tasters, crocks of
  tasting spoons, squeeze bottles, plating tweezers and striped linen. Built like the back
  stations; the app turns it to stand against the right wall. The front strip stays clear: the
  dish a chef tastes sits there (`ChefAvatar.tastingSpot`).
- **Connecting cabinets (`connectors.glb`)**: the shared counter at each `KitchenLayout.connectors`
  rectangle, in kitchen space (origin at the kitchen's centre on the floor); the right-wall ones
  turned to face the room. If it can't load, the old plain cabinets are used.

- **Sinks**: the right wall's long connecting run carries two brushed-stainless drop-in sinks:
  one wide basin with rounded corners under a thin rim on the marble, a centre drain, a
  pull-down faucet wound with an open coil spring and a soap pump, with copper bowls drying beside
  the second. The cabinet doors below are unchanged. The side wall is low there, so the faucets
  are deck-mounted (no splashback). Anchors `sink_0`, `sink_1` mark the basins.

## Pantry

- **Pantry (`pantry.glb`)**, a Provençal garde-manger after Michelin kitchens' open dry stores
  and Southern French country pantries: the shared Carrara counter with a green-lacquer hutch
  on its back (ivory dentil cornice, brass gallery rails, a "GARDE-MANGER" plaque). The shelves
  hold Le Parfait preserve jars, ochre and emerald confit pots, olive oil and tins; garlic
  braids, lavender and thyme hang in the end bays, with copper pans on the end posts.
- The counter keeps the front strip clear for chefs and carries produce crates (lemons,
  tomatoes, aubergines), a wicker basket of garlic and three cream-enamel appliances (the MCP
  servers). Their `status_light` material glows green in the app (`KitchenFixtures` sets the
  emission; the GLB has none).
- Built facing the room like the back stations (6.7 × 1.2 footprint); the app turns it for the
  left wall. The root is named `pantry`, which is what a click on it looks for to open the pantry.

## Service gong

- **Gong (`bell.glb`, the `bell` station)**: a hammered bronze gong on red cords in a deep-green
  lacquered frame with brass caps, ball finials and a "SERVICE" plaque, a spare felt mallet on its
  post. Its face centre is 1.29 above world 0, where a chef's mallet lands in `strike_gong`
  (`KitchenLayout.gongStrike`; a test checks the animated mallet head against the gong). The
  gong's meshes (`gong_*`) hang from the `gong_pivot` empty; the app swings them when struck.
- A chef that needs you runs to the strike spot, strikes once (mallet in hand only then), and
  waits in the curve behind the gong. The manager (`Chef/staff-manager.glb`, see
  `assets/chef/staff.json`) comes in from the dining room, talks with each waiting chef in turn
  until you answer, then walks back out.

## Break room floor

- `floor/make_lounge.py` writes the salon floor: oak parquet laid point de Hongrie
  (`floor_parquet*`, two chevron columns per repeat) and a deep-green wool rug with an ivory border
  under the lounge chairs (`floor_rug*`). `KitchenFloor` lays them over the break room only.
- The break room itself (`BreakRoomLayout`): three arcade cabinets on the far wall, the vending
  machine and the coffee bar (`build_coffee_bar.py`, the espresso machine on it) on the left wall,
  two lounge chairs across a side table, and two standing circles on the rug. See
  `assets/breakroom/README.md`.
