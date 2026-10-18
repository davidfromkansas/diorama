# Office scene

Each project shows its agents in the kitchen or the office. The gear in the scene's bottom-right
corner opens the project's settings (Scene: Kitchen / Office, and Sounds). The choice is per
project, shared by every window and kept across launches (`ProjectScenes`, UserDefaults
`projectScenes.v1`); projects without one show the kitchen. Switching swaps the project's scene at
once: every chef appears where its agent's state puts it, with the camera at its home view.

## One engine, two themes

`DioramaSceneView` runs both scenes. What differs is a `SceneTheme` (`KitchenTheme`,
`OfficeTheme`):

- **Floor plan and station table** (`SceneLayout`): stations, stand slots, walkable floor. Agent
  state → station is shared (`SceneRouting.route`), so tags, emotes, reviews and the log mean the
  same in both scenes; a scene's `SceneDressing` only changes the props (and whether a chef that
  needs you strikes the gong or rings the desk bell on arrival).
- **Fixtures, room, light and surroundings**: the kitchen's French kitchen and restaurant; the
  office's oak floor, window wall and client lobby at golden hour.
- **What chefs carry and serve** (`ChefAvatar.Kit`): dishes and pantry jars, or deliverable boxes
  and binders, toolboxes and devices.
- **Station effects** (`SceneStationEffect`): burner flames and idle cutting boards, or lit
  laptop screens and blinking rack lights.
- **Sounds**: the office's own files (`Resources/OfficeSounds`) replace the kitchen's of the same
  name; the rest play the kitchen's.

The office uses the kitchen's footprints, so slots, walkways and framing carry over:

| Station (role) | Kitchen | Office |
|---|---|---|
| `elevator` | Elevator | Elevator |
| `order` | Order rail | Ticket board |
| `prep` | Prep | Whiteboards |
| `cooking` | Cooking island | Desks |
| `stove` | Stove | Server rack |
| `tasting` | Tasting | QA bench |
| `bell` | Service gong | Manager's desk bell |
| `serving` | Serving window | Demo table |
| `break` | Break room | Lounge |
| `pantry` | Pantry | Supply closet |

`KitchenParityTests` pins the kitchen to how it behaved before the engine was shared
(`Fixtures/kitchen-parity.json`; re-record with `DIORAMA_RECORD_PARITY=1` only for intended kitchen
changes). `OfficeSceneTests` covers the office. Assets: `assets/office/`, `assets/office-sounds/`.
`--demo-scene office` records the kitchen demo's day in the office.
