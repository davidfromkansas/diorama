# Kitchen sounds

Foley for the Kitchen scene's chefs, played by `KitchenAudio` at the cue points in
`KitchenSound.cues` (`Sources/DioramaApp/KitchenSound.swift`). All clips are CC0 from Kenney
(kenney.nl, see `licenses/Kenney-Audio.txt`), converted from Ogg Vorbis to 44.1 kHz mono 16-bit CAF:

```sh
ffmpeg -i <source>.ogg -ac 1 -ar 44100 -c:a pcm_s16le Sources/DioramaApp/Resources/KitchenSounds/<sound>-<n>.caf
```

| Sound | Plays on | Source files (pack) |
|---|---|---|
| `step-0…4` | `walk`, `run`, `carry_walk` footfalls | `footstep_concrete_000…004` (Impact Sounds) |
| `chop-0…2` | `working_chop` impacts | `chop`, `knifeSlice`, `knifeSlice2` (RPG Audio) |
| `clink-0…2` | `testing_dish` taste, `sit_sip` sip | `impactGlass_light_000…002` (Impact Sounds) |
| `tap-0…2` | `planning_recipe` tap | `click_001…003` (Interface Sounds) |
| `page-0…2` | `researching_book`, `read_ticket` | `bookFlip1…3` (RPG Audio) |
| `pot-0…2` | `waiting_tool` at the stove | `metalPot1…3` (RPG Audio) |
| `grab-0…1` | `pickup` attach | `handleSmallLeather`, `handleSmallLeather2` (RPG Audio) |
| `plate-0…2` | `present_review`, `putdown` release | `impactPlate_light_000…002` (Impact Sounds) |
| `cloche-0…1` | `cover_dish` release | `impactMetal_light_000…001` (Impact Sounds) |
| `clatter-0…1` | `cancel_cleanup` release | `impactTin_medium_000…001` (Impact Sounds) |
| `bell-0…1` | `request_input`, `blocked_react` | `impactBell_heavy_000…001` (Impact Sounds) |
| `error-0` | `error_react` | `error_004` (Interface Sounds) |
| `cheer-0` | `celebrate_done` | `confirmation_002` (Interface Sounds) |
| `ding-0` | `arrive_wave` (elevator arrival) | `bong_001` (Interface Sounds) |
| `chair-0…2` | `sit_down`, `stand_up` | `creak1…3` (RPG Audio) |
