# Office

The startup office: the second scene a project can show (the gear in the scene's corner →
Scene → Office). Its fixtures, client lobby and props are modelled procedurally in Blender by
`blender/build_office.py`; the app also builds every piece procedurally in SceneKit
(`OfficeStationGeometry`, `OfficeLobby`, `OfficeProps`) and uses those whenever a model isn't bundled.

| Path | What |
|---|---|
| `blender/build_office.py` | Builds one piece (a station, the lobby, a prop) and exports its GLB |
| `blender/office_kit.py` | Palette, glowing materials, plants and the assembly (uses `../kitchen/blender/kitchen_kit.py`) |
| `build.sh` | Headless rebuild of every piece into `Sources/DioramaApp/Resources/Office{Stations,Lobby,Props}`; `REVIEW=1` also renders `docs/office/` |
| `../office-sounds/` | The office's sounds |

```sh
assets/office/build.sh
```

## Contract with the app

- **Stations** (`OfficeStations/<area id>.glb`, `OfficeFixtures`): modelled in the station's own
  frame, centred on its footprint and standing on the floor, x along the station, Blender -y toward
  the room (SceneKit +z); the app turns wall stations. The worktop is at 0.707 above the root
  (`ChefMetrics.worktopHeight - floorTop`), where the chef's hands land; everything stays inside
  the footprint (`OfficeSceneTests`). Footprints are the kitchen's (`SceneLayout.office`).
- Parts the app animates are separate objects with these names: `desk screen#i` and `desk logo#i`
  on the desks (lit while a chef types, `DeskScreens`), `rack lights#i` and `rack screen#i` on the
  server rack (blinking while a command runs, `RackLights`), and `desk bell` (it hops as a chef
  that needs you arrives; its origin is the bell's base).
- **Lobby** (`OfficeLobby/lobby.glb`): root `lobby`, empties `seat_NN` (where a seated client's
  root stands) and `dish_NN` (the spot on the table in front of it), numbered nearest the demo
  table first, at the restaurant's spots so clients sit where diners do. Seats 0.64 high and tables
  0.98 high fit the chef rig's `sit_*` clips at the 1.4 scale.
- **Props** (`OfficeProps/<id>.glb`): the deliverable boxes (`box_*`), and what chefs carry from the
  supply closet (`binder` for a skill, `toolbox` for a plugin, `device` for an MCP server) and the
  whiteboards (`plan_board`). Base at 0, widest side under 1.
- Colours are authored as the sRGB values the app shows; lit parts use emission, which the GLB
  loader reads as `emissiveFactor`.
