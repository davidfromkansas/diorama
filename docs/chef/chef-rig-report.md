# Tiny chef: rig, animation and agent-state integration report

Source: `assets/source/Meshy_AI_Tiny_Chef_Mascot_1004162827_texture.glb`. The SHA-256 is
`25c78e34…12fafdc`, which matches the brief. The file is kept byte-for-byte; all work reads from it.

## Repository context

The repository contained only an initial empty commit, so there was no existing engine,
state model or backend to plug into. I built:

- a **Vite + three.js** runtime (`app/`),
- an agent-state layer driven by the real **Claude Agent SDK** message types
  (`@anthropic-ai/claude-agent-sdk@0.3.289`, type definitions read from its `sdk.d.ts`),
- a WebSocket bridge (`app/server/bridge.ts`) that runs `query()`.

If you have a different host engine or agent backend, port these pieces. The reducer, the
visual planner, the director and the prop ledger are engine-independent TypeScript.

## Asset changes

| Item | Decision |
|---|---|
| Geometry | Unchanged: 26,437 vertices and 30,934 triangles, no remesh, no welds. The mesh is 1,567 UV-seam islands, so skin weights are a pure function of vertex position. That gives seam duplicates identical weights, so seams cannot crack. |
| Placement | Vertices are translated by Blender (0, +0.06, +0.9506), which is glTF (0, +0.9506, −0.06). The soles sit on the floor and the root sits between the ankles. There is no rotation or scale. |
| Facing / units | The chef faces **+Z in glTF** (−Y in Blender). 1 unit equals 1 source unit. Height is **1.90** from sole to the top of the toque. The skull top is about 1.46; the toque is above that. |
| Material | The original `BakedMaterial` is kept: base colour (sRGB), normal map, and packed metallic/roughness (non-colour, G→roughness, B→metallic), double-sided. Textures were not resized or recompressed. The 4K metallic/roughness texture is why the GLB is 17.6 MB. |
| Skeleton | 26 exported joints: `root`, `hips`, `spine`, `chest`, `neck`, `head`, `hat`, and `clavicle`/`upperarm`/`forearm`/`hand` plus `thigh`/`shin`/`foot`/`toe` with `.L` and `.R`. Sockets: `socket_hand.L`, `socket_hand.R`, `socket_carry`. `.L` is the chef's left, which is +X. |
| Controls (.blend only) | `hand_ik.*` and `elbow_pole.*` (arm IK), `foot_ik.*`, `knee_pole.*` and `mch_foot.*` (planted-foot leg IK). These are stripped from the runtime export after baking. |
| Weights | Region rules measured from the mesh: arm membership by torso width per height, legs below the apron with crotch and apron falloff, and the hat blended onto a `hat` bone above 0.60. Maximum 4 influences, normalised. The apron is mostly on hips, with at most 30% thigh influence on the front and sides. |

Joint placement was taken from slice measurements of the mesh, not from a human template:

- shoulders sit under the sleeves at x ±0.25,
- elbows sit at the sleeve hem at x ±0.44,
- wrists sit at the mitten base,
- hips, knees and ankles are inside the short trousers at heights 0.50, 0.27 and 0.12.

The mittens have no finger rig.

## Clips (glTF animation names match the semantic names exactly)

All clips are in place: the `root` never translates, which the verifier checks. They play at
30 fps and are baked to FK on deform and socket bones only.

| Clip | s | Loop | Markers (normalised) | Notes |
|---|---|---|---|---|
| `idle_available` | 4.0 | ✓ | | breathing, weight shift, glance |
| `planning_recipe` | 2.4 | ✓ | tap 0.13 | recipe clipboard held low and out to the left; torso twists toward it; right mitten taps down three lines; head reads and tilts |
| `researching_book` | 2.8 | ✓ | | open cookbook, page reach, line scanning |
| `working_chop` | 0.4 | ✓ | impact 0.167, impact_2 0.667 | Overcooked 2-style 5 Hz chop: two short, snappy strokes per loop (about 8.5 cm lift), steady fist via `hand_aim`, blade edge meets the carrot at each impact, small hip/chest bounce and hat lag on every hit; feet planted (IK); left hand steadies the far end |
| `waiting_tool` | 3.6 | ✓ | | watches the pot, leans in to check once per loop |
| `testing_dish` | 2.6 | ✓ | taste 0.29 | spoon to the lips, then hand to chin, head tilt; no success gesture |
| `walk` / `run` | 0.533 / 0.4 | ✓ | | nominal speeds 0.75 and 1.36 u/s, quick short steps |
| `carry_idle` / `carry_walk` | 2.0 / 0.533 | ✓ | | both mittens under the plate rim; nominal 0.68 u/s |
| `request_input` → `wait_input` | 1.0 / 2.4 | once / ✓ | | dip, raised right hand, small wave, then attentive |
| `blocked_react` → `blocked_wait` | 1.0 / 3.2 | once / ✓ | | looks aside, shrugs with palms up, subdued loop |
| `error_react` | 0.8 | once | | recoil, shoulders drop, looks down; settles into `blocked_wait` |
| `present_review` → `wait_review` | 1.4 / 2.6 | once / ✓ | release 0.36 | puts the plate on the pass and gestures to it; hands on hips |
| `celebrate_done` | 1.0 | once | | crouch, small hop with fists up, satisfied nod |
| `unknown_wait` | 4.0 | ✓ | | neutral, uncertain glances left and right |
| `cancel_cleanup` | 0.6 | once | release 0.47 | puts down anything held and relaxes |
| `pickup` / `putdown` | 0.5 / 0.5 | once | attach 0.48 / release 0.52 | two-hand plate at the counter |

`app/public/assets/chef-manifest.json` contains:

- the clip table, markers and nominal speeds,
- prop attach transforms per socket, in the socket node frame,
- the station heights,
- the bone lists.

glTF does not carry custom events, so markers live only there. Prop fits were computed in
Blender against the baked pose at the reference frame (`fit_frame`). The socket-to-prop gap is:

| Prop | Gap |
|---|---|
| clipboard | 3.2 cm |
| book | 3.7 cm |
| plate | 2.1 cm |
| spoon | 0 |
| knife | the fist closes on the last 2 cm of the handle (grip point 11 cm behind the bolster), so the rest of the handle and the whole blade stay visible in front of the mitten. The impact wrist height is fitted so the edge meets the board within 4 mm. |

Station geometry the clips were authored against:

- counter top 0.585,
- board top 0.605,
- counter front 0.43 in front of the root.

## Agent-state mapping (actual events)

| Source event | Lifecycle | Activity | One-shot |
|---|---|---|---|
| bridge `run_started` (new `runOrdinal`) | running | working (generic) | clears the previous run |
| SDK `system/init` (`permissionMode:'plan'` → planning) | running | — | |
| SDK `assistant` `tool_use` block | running | by tool name, see below | |
| SDK `tool_progress` with `elapsed_time_seconds ≥ 5` | waiting | unchanged | |
| SDK `user` `tool_result` | running (waiting ends) | the remaining in-flight tool, if any | |
| bridge `permission_request` (SDK `canUseTool` callback) | needs_input, with `pendingApproval` | — | `request_input` |
| bridge `permission_resolved` | running | — | |
| SDK `system/session_state_changed` `requires_action` | needs_input | — | |
| SDK `system/api_retry`, `system/permission_denied`, `rate_limit_event` with status `rejected` | blocked; the next `assistant` message resumes | — | `blocked` |
| SDK `result` `success` with `!is_error` | **ready_for_review**, with `pendingReview` | presenting | `present` |
| SDK `result` error subtypes, or `is_error` | failed, keeping `error.subtype` | none | `error` |
| bridge `review_decision: accepted` (app completion policy) | **completed**, completion badge kept | none | `celebrate` (once per run) |
| bridge `run_cancelled` (AbortController) | cancelled | none | `cancel` |
| transport disconnect | lifecycle **unchanged**; `connection` set to disconnected | — | shows `unknown_wait` and a "? Disconnected · last known: …" badge |

Tool-to-activity mapping, configurable in `app/src/agent/mapping.ts`:

- **Researching:** Read, Grep, Glob, WebSearch, WebFetch.
- **Planning:** TodoWrite, Task*, Enter/ExitPlanMode.
- **Working:** Edit, Write, NotebookEdit, Bash, Agent, `mcp__*`.
- **Testing:** Bash whose command matches a test-runner pattern.
- **Anything else:** generic working.

Thinking blocks and elapsed wall-clock time never change state.

Activity, lifecycle and clip line up as follows (`app/src/avatar/visualPlan.ts`):

| Activity / lifecycle | Station, loop and prop |
|---|---|
| planning | recipe counter (front-left, facing the camera), `planning_recipe`, clipboard |
| researching | books, `researching_book`, cookbook |
| working | prep, `working_chop`, knife |
| testing | tasting, `testing_dish`, spoon |
| waiting | stove, `waiting_tool` |
| needs input / blocked / failed / cancelled | stay put, play the one-shot, then the loop |
| ready_for_review | pick up the dish at tasting, `carry_walk` to the pass, `present_review`, then `wait_review` |

Locomotion (stationary, walking, running) belongs to the navigation layer only.

Run identity rules:

- Envelopes from another `runOrdinal`, or with `seq ≤ lastSeq`, are ignored. So are SDK
  messages with an already-seen `uuid`.
- One-shot ids are per run and cause, for example `done:<runId>`.
- The director plays each id at most once.
- A reconnect snapshot marks its one-shot as `restored`, so the end pose shows without replaying it.

## Runtime composition

- `ChefAvatar.root` carries the navigation translation and yaw and is never scaled. `visual`
  is the decorative child.
- Each avatar is a `SkeletonUtils.clone`, so it has its own skeleton, mixer and pose while sharing
  geometry and textures.
- Crossfades are 0.22 s, or 0.12 s for urgent states (input, blocked, failed, cancelled, unknown).
- Stride playback is `speed / nominal_speed`, clamped to 0.6–1.5. Stepping stops when movement stops.
- The chef turns toward travel, then toward the station's facing before working.
- `PropLedger` enforces one owner per prop and one prop per slot, plus station reservations.
  Interrupted one-shots run their release handler, so a plate can never be in two places.
- If a station is unavailable, the chef shows the real lifecycle in place without fake station work.

## Verification

- `npm run verify:glb` reimports the runtime GLB with glTF-Transform. All checks pass:
  - 1 skin, 26 joints, inverse bind matrices,
  - every vertex weighted, with weights normalised to within 1e-7,
  - vertex and triangle counts preserved,
  - all three texture slots connected,
  - 22 clips with the manifest durations (no stray authoring actions),
  - each clip drives the arm, leg and head joints,
  - loop seams are bit-identical,
  - no root translation.

  Socket rest frames are identity in glTF, confirmed by reading the node world matrices, so
  the manifest attach offsets apply directly.
- Blender verification renders (`build/renders`, contact sheets in `docs/clip-sheets/`) show
  front, side and production views of every clip, with props and counter, rendered from the
  baked actions.
- `npm test` runs 21 vitest tests:
  - state transitions and test/tool classification,
  - duplicate and late-event suppression,
  - the snapshot reconnect path,
  - approval interrupts chopping, cancellation interrupts carrying, error interrupts testing,
  - the cancel marker is reconciled when preempted,
  - one celebration across duplicate, repeated and re-planned completions,
  - reconnect does not resurrect work or props,
  - station fallback, two independent avatars, and reduced motion.
- Runtime captures (`docs/screenshots/`) come from headless Chrome 154 (ANGLE Metal) on an
  Apple M5 Pro, running the real three.js `GLTFLoader` and WebGL renderer:

  | Avatars | Frame rate | Worst frame (CPU) | Draw calls |
  |---|---|---|---|
  | 6 | 60 fps (vsync-capped) | 2.7 ms | 237 |
  | 24 | 60 fps | 4.8 ms | 481 |

  These numbers are for this machine only. There are no console errors.

## Known limitations

- **Arm reach.** The chef's wrist reach is about 0.38 units and the belly sticks out 0.41, so
  two-handed poses near the midline (book, plate) cross the forearms in front of the chest.
  Planning avoids this with a one-handed clipboard and a torso twist. Every hand pose relies on clavicle protraction and a small lean.
- **Deformation.**
  - Elbows pinch slightly past about 100° of flexion.
  - The sleeve and armpit stretch when the hand is raised above the head.
  - Large thigh lifts push into the apron, so walk and run lift the feet only 5.5 and 8 cm.
  - Weights are procedural and were checked visually; they are not hand-painted.
- **Props.**
  - Hand tools attach instantly on arrival; only the plate uses the `pickup` and `putdown` clips.
  - A tool released away from its station returns to its home slot (it teleports).
  - The dish resets to the tasting counter when a new run starts.
  - The spoon reaches the lips and comes close to the nose in side view.
- **No turn-in-place clip.** Turning is a yaw over the idle or walk pose. Navigation is
  straight-line with no obstacle avoidance; the layout keeps paths clear.
- **Live bridge untested.** `server/bridge.ts` typechecks against the SDK but was **not run
  against a live Claude session** in this work. All event verification used SDK-shaped
  fixtures (`sdkFixtures.ts`), which fill only the fields the normaliser reads.
- **Reduced motion** holds loops at 35% of the clip and skips one-shots. Walking still animates
  the legs.
- **Upper-body masking** is not used; carrying relies on dedicated clips.

## Changes since the first delivery

- **Planning rework:** the recipe station moved to the front-left of each lane and faces the
  camera. The card is now a larger clipboard printed on both sides. The pose holds it in one
  hand with a torso twist and right-hand taps.
- **Bug fix:** three.js `GLTFLoader` strips `.` from node names, so `socket_hand.L` loads as
  `socket_handL`. Hand props (card, book, knife, spoon) failed to attach and were silently
  hidden in the web app; only the plate showed. `ChefAvatar.socket()` now resolves sanitised
  names, and a missing socket logs a console error. That error fails the capture script's
  error check.

## Working / chopping rework (Overcooked 2 reference)

**Research.** Public sources describe Overcooked 2 chopping like this:

- The knife rests on a small white chopping board.
- The chef uses it to chop an ingredient in about three seconds, slower in single-player.
- Two chefs on one board chop faster.

The detail on rhythm comes from an open-source Overcooked 2 TAS framework built against the
game's own code. It hooks the workstation's chop callback, which reads the chef's
`AnimationEventData` trigger `"Chop"`/`"Impact"`. Each impact calls `OnChop` and plays the
board's chop particle effect at the item, and the framework models **0.2 s per impact**. So
chopping is a fast, rhythmic sequence of knife impacts, each with a particle burst.

Sources:

- https://overcooked.fandom.com/wiki/Chopping
- https://overcooked.fandom.com/wiki/Chopping_Board
- https://github.com/hpmv/overcooked-supercharged, specifically:
  - `patch/Extensions/ServerWorkstationExt.cs`
  - `controller/Data/SpecificEntityData.cs`
  - `planner/CarnivalRecipes.cs`

The exact pose shapes in the game were not available as data. The motion below follows that
cadence and the series' short-stroke, bouncy style.

**What changed:**

- **Clip:** `working_chop` is 0.4 s with two impacts that land exactly on baked frames 2 and 8,
  so it runs at 5 impacts per second. The knife falls fast (2 frames), rebounds, and
  cocks back up. The second chop lands 1.4 cm further along the carrot.
- **Grip:** a new authoring control, `hand_aim.L/R` (a world-space COPY_ROTATION on the hand,
  with influence keyed per clip), holds the fist at a steady angle while the forearm drives
  the chop. Before, the wrist swung about 60° per stroke and the tip pointed at the face.
  The control is baked out of the runtime export like the other controls.
- **Knife:** chunkier Overcooked-style proportions (20 cm blade, 12 cm riveted handle). The fist
  grips only the butt of the handle, so handle and blade are both visible; the stroke lands
  where the cut slices meet the whole carrot. The build reports the edge height at impact; currently it is
  0.608 against a board at 0.605.
- **Steel:** dropped to 0.3 metalness so it reads as steel in the WebGL preview, which has no
  environment map. Fully metallic props rendered black there.
- **Runtime:** `AvatarDirector` now fires looping-clip markers through `onEvent`. Each
  `impact*` marker in `working_chop` spawns a small burst of carrot bits at the blade
  (`scene/chopFx.ts`). Reduced motion turns the bursts off.
- **No progress bar:** we can't truthfully report backend progress, so there isn't one.
- **Test:** a new test checks the 0.2 s impact cadence.
