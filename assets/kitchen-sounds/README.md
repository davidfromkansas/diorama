# Kitchen sounds

Foley for the Kitchen scene's chefs, played by `KitchenAudio` at the cue points in
`KitchenSound.cues` (`Sources/DioramaApp/KitchenSound.swift`). Every clip is synthesised in code
(Diorama owns them; nothing to license): mostly Overcooked-style sounds, short, punchy and
cartoon-bright, picked by ear on the Kitchen Sounds audition page. Clips are 44.1 kHz mono 16-bit CAF.

| Sound | Plays on | Synth option |
|---|---|---|
| `step-0…4` | `walk`, `run`, `carry_walk` footfalls | `oc-step`: pitter-pat |
| `chop-0…2` | `working_chop` impacts | `oc-chop`: knife strike, veggie snap, board thunk |
| `clink-0…2` | `testing_dish` taste, `sit_sip` sip | `oc-clink`: spoon-on-bowl tink |
| `tap-0…2` | `planning_recipe` tap | `oc-tap`: recipe boop |
| `page-0…2` | `researching_book`, `read_ticket` | `flip`: paper flip |
| `pot-0…2` | `waiting_tool` at the stove | `oc-pot`: bubbling pot |
| `grab-0…1` | `pickup` attach | `oc-grab`: pickup pop |
| `plate-0…2` | `present_review`, `putdown` release | `oc-plate`: plate clunk |
| `cloche-0…1` | `cover_dish` release | `oc-cloche`: order served jingle |
| `clatter-0…1` | `cancel_cleanup` release | `oc-clatter`: dish drop |
| `gong-0…1` | `strike_gong` impact (a chef that needs you strikes the gong) | `softgong`: soft gong |
| `error-0` | `error_react` | `oc-error`: failed order |
| `cheer-0` | `celebrate_done` | `oc-cheer`: tip jingle |
| `ding-0` | `arrive_wave` (elevator arrival) | `musicbox`: music box |
| `chair-0…2` | `sit_down`, `stand_up` | `oc-chair`: stool bonk |

## Regenerating

`synth-render.html` holds the synthesis (Web Audio, rendered offline) and the picks above. Each sound
plays through the audition page's small room echo and gentle compressor, and is stored without its
in-app volume (`KitchenSound.volume` applies it), so the app sounds like the page. To render:

1. Serve this folder on localhost (Web Audio needs a page, not a file) and open `synth-render.html`.
2. When the page shows JSON, save it as `rendered.json`.
3. Write each `<sound>` array's variants to `Sources/DioramaApp/Resources/KitchenSounds/<sound>-<n>.caf`
   (16-bit PCM WAV, then `afconvert -f caff -d LEI16@44100 -c 1 in.wav out.caf`), trimming the silent tail.

`make_gong.py` is the earlier bronze gong, kept for reference; `licenses/Kenney-Audio.txt` covers the
Kenney clips the kitchen used before.
