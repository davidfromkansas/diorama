# Break room machines

The break room's machines (`Sources/DioramaApp/Resources/BreakRoom/`), from Meshy downloads:

| id | Machine | Placed |
|---|---|---|
| `arcade_cosmic`, `arcade_jungle`, `arcade_blue` | Cosmic, Jungle and Deep Blue arcade cabinets | far wall, facing the camera |
| `vending` | Retro red vending machine | left wall, facing the room |
| `espresso` | Stainless espresso machine | on the coffee bar (`KitchenStations/coffee_bar.glb`, `assets/kitchen/blender/build_coffee_bar.py`) against the left wall |

```sh
assets/breakroom/build.sh [id ...]      # FACES=20000 TEXTURE=1024
```

The originals (15–34 MB each) live in `source/<id>.glb` and are not in git. `build.sh` runs the
food pipeline's `optimize_food.py`: joined, decimated, textures shrunk, centred with the base at 0
and the widest side 1.0. `BreakRoomLayout` (Sources/DioramaApp/BreakRoom.swift) scales each to the
chef (arcades 2 m tall with their control panels at the chef's hands, the vending machine 2.1 m)
and places it; a test checks the layout's sizes against the models.

Each machine has one use spot. Resting chefs take a free machine first, then one of the two lounge
chairs, then a place in a standing circle; every 45–90 s a machine changes hands. Clips:
`play_arcade`, `use_vending` / `brew_espresso` then `stand_sip` with a can or a coffee; in the
circles `talk_reply`, `stand_listen` and `stand_laugh`, with emoji bubbles (`ChefBubbleView`).
