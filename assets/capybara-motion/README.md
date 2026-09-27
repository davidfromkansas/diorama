# Supplied capybara — motion foundation

This is the model supplied from `/Users/david_lietjauw/Downloads/capybara.glb`, not the previously authored model in `assets/capybara`. The original is preserved byte-for-byte as `source.glb`. Its SHA-256 is `15756a7fd49fbec04e61643e0efe7be81014eff4fc280a941f3f7c9ed1de8ae0`.

## Inspection before rigging

- Binary glTF 2.0, one unnamed identity node, one mesh/primitive, one double-sided PBR material.
- 79,040 exported vertices, 142,240 triangles, UVs and normals.
- Three embedded JPEGs: base color, metallic/roughness, tangent-space normal. All three image payloads remain **byte-identical** in the animated export.
- No skeleton, skin weights, animation, morph targets, or separate facial controls.
- Right-handed, Y up, +Z forward. Original bounds: X −0.59845…0.59756, Y −0.95060…0.94974, Z −0.48082…0.47969. Origin at body center; approximately 1.90034 units tall. Source units had no physical scale metadata.
- Stylized biped with short legs, outstretched arms, large rigid head, rounded belly, and small ears. No visible articulated tail.

The derived mesh is uniformly normalized to one metre tall with the sole plane at Y=0. Geometry, topology, UVs, textures, and material appearance are retained. No remeshing or replacement character was used.

## Deliverables

- `capybara-animated.glb`: self-contained mesh, original textures, 25 deform joints, normalized weights (maximum four influences), idle/walk/run loops.
- `capybara-rigged.blend`: editable rig, vertex groups, and three NLA actions.
- `build.py`: reproducible Blender authoring script. Bone-heat skinning failed on the dense source; explicit anatomical blend masks are used instead. Hip masks keep the belly from following either thigh across the center seam.
- `controller.mjs`: semantic movement API with separate global travel and local animation. Smooth acceleration/deceleration, bounded turning, shared gait phase, walk/run blending, idle transitions, reduced idle motion, runtime inspection, input validation, and disposal.
- `index.html` / `playground.mjs`: standalone floor with click-to-move, walk/run switch, left/right turns, stop, pause, reset, skeleton/grid toggles, and live state/layer readout.
- `renders/`: idle, walk and run deformation checks.
- `validation.json`: checks against the exported GLB, including sampled deformed mesh bounds.

## Run

From the repository root:

```sh
python3 assets/capybara-motion/serve.py
```

Open http://127.0.0.1:8767/capybara-motion/. This uses the existing vendored Three.js files and their MIT license under `assets/capybara/viewer/vendor`; no CDN or package installation is needed.

## Runtime contract

```js
const motion = new CapybaraMotion(gltf.scene, gltf.animations, manifest);
scene.add(motion.root); // Keep the outer group directly in world space.
motion.moveTo(new THREE.Vector3(1, 0, -1), {gait: 'walk'});
motion.setGait('run'); // Retains phase and smoothly accelerates.
motion.stop(); // Decelerates from current velocity.
motion.turnTo(Math.PI / 2);
motion.followPath(navigatorWaypoints, {gait: 'walk'});
motion.update(deltaSeconds);
```

Feet use analytical two-bone IK during clip authoring, with a constant backwards stance velocity. Runtime travel cancels that velocity at nominal speed: walk 0.15457 m/s (1.2 s cycle); run 0.64626 m/s (0.7 s cycle). Running has shorter stance, longer strides, more arm swing and a brief airborne phase. Root height, torso sway, stabilized head and small ear motion are baked. Idle has subtle breathing/postural movement; there is no blink control in this mesh.

The three clips are **base-layer primitives**, not one clip per semantic action. Starting/stopping and left/right/in-place turning are runtime behavior. The controller exposes base weights so future gesture/head/IK layers can be composed separately.

## Validation

```sh
node --test assets/capybara-motion/controller.test.mjs
/Applications/Blender.app/Contents/MacOS/Blender -b --python assets/capybara-motion/build.py
/Applications/Blender.app/Contents/MacOS/Blender -b --python assets/capybara-motion/validate.py
```

Ten controller tests cover 30/60/120 Hz arrival, destinations behind the character, deceleration, interrupted turns, path completion, invalid inputs, delayed frames, missing clips, and gait changes. Exported animation samples are finite, every loop endpoint matches, and skin weights sum to one. At 21 sampled poses per clip the deepest floor penetration is 0.38 mm; walking stays within 0.022 mm of the floor. The run clears the floor by up to 10.65 mm at the sampled airborne poses. These bounds check the mesh, not just joint origins.

## Native workspace follow-up

The capybara now also runs inside the actual SceneKit workspace through its **Movement Lab** button. This native controller adds furniture-aware navigation, planted-foot IK with pelvis reach correction, head anticipation, torso lean and turn banking. See `../../docs/CAPYBARA_MOVEMENT.md` for setup, tests and the native review video. The limitations below describe the standalone browser P0 controller.

## Scope and next integration step

This directory contains the browser **P0 foundation** and source rig. The native workspace now uses this capybara for every agent desk, including a seated pose, typing and status gestures. The original mesh is materially different from the older capybara asset; this directory is the source for the bundled character.

P0 limits: travel assumes a level open floor. `followPath` accepts waypoints but does not implement obstacle avoidance. Foot contact is authored, not a runtime terrain solver; sharp turns and blended transitions can still slide. The dense source and anatomically masked linear skinning need further art-direction review, particularly deep knee/hip compression. No runtime arm/foot IK, sitting/typing, object interactions, gesture layer, facial morphs, carrying/flailing, or ragdoll is claimed here. Those are subsequent P1–P3 milestones from the brief.

Native integration preserves `WorkspaceAvatarMotion`'s semantic activity handling and loads the actual skinned hierarchy through `WorkspaceCapybaraAsset`. Status gestures are mapped relative to the capybara's bind transforms and anatomical arm directions.
