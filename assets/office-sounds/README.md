# Office sounds

Foley for the Office scene. The office plays the kitchen's cues (`KitchenSound.cues`); a file in
`Sources/DioramaApp/Resources/OfficeSounds/` replaces the kitchen sound of the same name, and any
sound the office doesn't have plays the kitchen's (`KitchenAudio.play(_:folder:)`). Synthesised in
code by `make_sounds.py` (nothing to license), 44.1 kHz mono 16-bit CAF.

| Sound | Plays on | In the office |
|---|---|---|
| `chop-0…2` | `working_chop` at the desks | a burst of typing |
| `pot-0…2` | `waiting_tool` at the server rack | the terminal's two-tone blip |
| `tap-0…2` | `planning_recipe` at the whiteboards | a marker squeak |
| `plate-0…2` | `present_review`, `putdown` | a boxed deliverable set down |
| `gong-0…1` | a chef reaching the manager's desk bell | the desk bell's ring |
| `ding-0` | `arrive_wave` | the elevator's two-tone chime |

```sh
python3 assets/office-sounds/make_sounds.py
```
