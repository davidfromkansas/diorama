"""Write the asset contract from the generated manifest."""
import json
from pathlib import Path
P=Path(__file__).resolve().parent;m=json.loads((P/'manifest.json').read_text())
def tree(n,indent=0):return '  '*indent+n+'\n'+''.join(tree(k,indent+1) for k,v in m['skeleton'].items() if v['parent']==n)
text='''# Capybara asset reference

The updated orthographic sheet supplied on 2026-09-27 is the visual reference (`reference_orthographic.png`). The earlier sheet is superseded. This asset is authored geometry, not an image billboard. All views, expressions, and clips use the same mesh and skeleton.

## Files and opening the studio

- `capybara.glb`: self-contained runtime asset, with packed textures and clips.
- `capybara.blend`: editable quad body, rig, shape keys, NLA actions, and render studio. Render-only objects are named `STUDIO_*` and excluded from the GLB.
- `viewer/index.html`: orthographic interactive inspector, using vendored Three.js 0.180.0. No CDN, package installation, or build step is required.
- `manifest.json`: machine-readable skeleton, clip durations, loop flags, materials, and morph names.
- `renders/reference_comparison.jpg`: updated reference above the matching four cardinal renders, at a common character height.
- `renders/turnaround.jpg`: front, back, left, right, front three-quarter, rear three-quarter. The full-resolution PNGs are alongside it.
- `renders/animation_contact_sheet.jpg` and `renders/expressions.jpg`: deformation and face inspection sheets.
- `validation_gltf.json` and `validation_blender.json`: structural and deformation verification results.

Run from the repository root:

```sh
python3 assets/capybara/serve.py
```

Open http://127.0.0.1:8766/viewer/. Drag to orbit; scroll to zoom; right-drag to pan. The inspector provides all clips, smooth crossfades, speed, pause/restart, timeline scrubbing, independent facial intensity, procedural speech/blinks, skeleton, wireframe, a ground grid, and scaled example furniture. `T-pose` restores the canonical bind pose. The working-day demo layers the thinking upper body over the seated pelvis and legs.

## Coordinates and geometry

- GLB: right-handed, **Y up**, **+Z forward**, **+X character left**; metres.
- Blender source: Z up, -Y forward; the exporter performs the axis conversion.
- Nominal height: **1.0 m**, including ears. Voxel/quad reconstruction can soften the very top by a few millimetres.
- Canonical standing soles: Y=0 in GLB, Z=0 in Blender.
- Bind pose: symmetrical T-pose; displayed idle lowers the arms.
- Three skinned mesh objects: continuous golden body, brown paws/inner ears, and the face. Facial features are independent mesh islands within the face object, with a common head weight.
- Main body uses a continuous quad-dominant cage with additional density at neck, shoulder, hip, elbow, and knee junctions. Small surface features use quads and triangular end caps; GLB rendering uses triangles.
- Linear blend skinning, normalized weights, at most four effective joint influences per vertex. No runtime subdivision, strand hair, physics, or corrective skinning extension is required.
'''
text+=f"\nGeometry: **{m['triangles']:,} triangles**, **{m['vertices']:,} source vertices**, **{m['bones']} joints**. Exported vertex count is higher at UV/material/normal seams.\n"
text+='\n## Skeleton\n\n```text\n'+tree('root')+'```\n'
text+='''
All named bones are exported, including shoulder, neck, ears, and tail. The root bone is the runtime motion anchor. The enclosing `Capybara_Rig` is identity. Skinned mesh nodes are scene roots for portable glTF skin semantics. Place the **entire imported scene** beneath an application transform when positioning the character.

## Animation clips

Times are seconds, sampled at 30 Hz, with a zero-second first key. Loop endpoints are identical. One-shot clips should clamp their final frame or transition to the indicated idle.

| Clip | Duration | Loop | Use |
|---|---:|:---:|---|
'''
uses={'idle':'Neutral standing rest','walk':'In-place walk; nominal travel 0.1944 m/s','run':'In-place run; nominal travel 0.5769 m/s','sit_down':'Standing → seated','sit_idle':'Seated lower-body base','stand_up':'Seated → standing','wave':'Greeting, returns to standing','point':'Whole-paw pointing, returns to standing','think':'Standing thinking gesture; upper-body tracks can layer over seated','talk':'Standing conversational body motion','type_at_computer':'Seated typing; hands around 0.49–0.51 m high','read':'Standing reading/holding pose','pick_up_object':'Standing → low reach → carry stance; attach at 1.0 s','carry_object':'Carry-arm pose over in-place walk','put_down_object':'Carry → low reach → standing; release at 1.0 s','jump':'Anticipation, flight, landing, settle','celebrate':'Raised paws, restrained torso motion, returns to standing','sleep':'Side-lying rest; pair with content or blink_both'}
for c in m['clips']:text+=f"| `{c['name']}` | {c['duration']:.2f} | {'Yes' if c['loop'] else 'No'} | {uses[c['name']]} |\n"
text+='''
All clips are in place. The application owns global travel. Walk/run feet move backward at constant velocity during stance; advancing the application transform along +Z at the nominal speed cancels this motion. Scale travel speed with playback speed and avatar scale. Root vertical motion in jump and the root orientation/placement in sleep are intentional pose motion; they are not global navigation displacement.

Clip `extras` include loop status and duration, nominal locomotion speed where applicable, and attach/release events for object interaction. Events are metadata for the application to consume; glTF players do not automatically attach props.

## Facial targets

'''+', '.join('`'+n+'`' for n in m['morphs'])+'''

`neutral` is intentionally a zero-delta target, defining the default friendly smile. All other targets deform vertices. Set all targets to 0 for the neutral expression. Apply the same named weight to every primitive of `Capybara_Face`; glTF splits a multi-material mesh into separate primitives. Facial weights are independent of the skeleton and therefore combine with every body clip.

Blink-left and blink-right refer to the character's own left and right. Choose one main expression at a time. Blinks can be overlaid, but clamp overlapping eye expressions rather than summing them beyond 1. Speech targets are mouth-opening primitives, not a phoneme/viseme library. The viewer handles speech and blink composition and pairs the neutral sleep body with `content` automatically.

The mouth lines and dark opening patch conform to the muzzle surface and wrap around its sides. They have actual thickness, so the friendly smile remains visible from profile. The stylized opening is a surface patch, not a modeled oral cavity.

## Materials and textures

'''
for n in m['materials']:text+='- `'+n+'`\n'
text+='''
Updated sheet palette: body **#D9A772**, muzzle/paws **#7B5A3C**, cheeks **#F4B7A7**, eyes **#111111**. Render lighting can change perceived brightness; the underlying albedo matches these colors with subtle fibre variation.

| Texture | Resolution | Color space | Use |
|---|---:|---|---|
| `textures/body_albedo.png` | 1024² | sRGB | Golden fur |
| `textures/muzzle_albedo.png` | 1024² | sRGB | Brown muzzle/paws |
| `textures/inner_albedo.png` | 1024² | sRGB | Ear interior |
| `textures/plush_normal.png` | 1024² | Linear | Shared short-fibre tangent normal |
| `textures/cheek_blush.png` | 128² | sRGB + alpha | Soft radial blush |

Every referenced texture is embedded in the GLB and packed into the Blender source. Fur uses material normals, roughness and a subtle sheen, not costly geometry strands. Tangents are exported explicitly. The core metallic/roughness materials remain usable without optional sheen/specular support.

## Runtime state architecture

| State | Reusable primitives |
|---|---|
| IDLE | idle |
| MOVING | walk, run |
| WORKING | sit_down → sit_idle/type_at_computer → stand_up; read |
| THINKING | think upper body + standing or seated lower body |
| COMMUNICATING | wave, point, talk + facial/speech weights |
| INTERACTING | pick_up_object → carry_object → put_down_object |
| CELEBRATING | celebrate, jump |
| RESTING | sleep + content |

Use 0.2–0.4 s crossfades between compatible states. Use sit_down/stand_up when changing height; do not crossfade directly from a seated body to a standing thinking pose. `viewer.js` demonstrates a reusable track mask: root, pelvis, upper_leg, lower_leg, and foot tracks come from sit_idle; the remaining tracks come from think. Locomotion transitions should align gait phases. Sleep has a different root orientation and needs an application-level lie-down/get-up transition if entering it on screen.

For variable furniture and objects, add runtime IK for the hands and feet, adjust the chair/desk dimensions, and consume the contact events. The included desk is about 0.46 m high and the low chair about 0.115 m high. They are viewer-only props.

## Validation and remaining limitations

The authored character was inspected in front, back, both profiles, and both three-quarter views. The four cardinal cameras use one orthographic scale (1.20 m), identical 700×700 framing, and the same ground plane. Comparison iterations widened the head, extended the forward profile, reduced ear size, increased hip depth, joined body surfaces, and corrected shoulder and seated contact.

The Blender verifier checks normalized skin weights, maximum joint influences, matching loop endpoint matrices, independent nonzero morph deltas, and sampled ground bounds. It renders 12 representative body poses and all 12 expressions. Khronos glTF validation separately checks the actual runtime file; see its saved report. The inspector has also been exercised in the browser with combined expressions/body clips, crossfades, rig visibility, and alternate camera views.

Known limitations:

- The reference is an illustrated plush-fur character; this is a material-based realtime interpretation. It has a smooth silhouette, without the reference's fuzzy strand outline.
- The quad cage is generated and the motion is authored procedurally. The supplied renders expose the result for review; this is not a claim of motion-capture quality or a substitute for final art-direction approval.
- No fingers, jaw bone, teeth, tongue rig, collision volumes, cloth, physics, LOD chain, or phoneme-specific visemes. The rounded paw points as a whole.
- Crossfades, prop attachment, global navigation, and IK belong to the runtime. Contact for different furniture heights/prop sizes is not automatic.
- The sleeping loop is included; lie-down and get-up transitions are not in the requested initial library.
- The independent GLB viewer is the integration test scene. This task does not replace Diorama's existing SceneKit avatar or add a GLB importer to the native app.

## Rebuilding

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python assets/capybara/build.py
/Applications/Blender.app/Contents/MacOS/Blender -b assets/capybara/capybara.blend --python assets/capybara/validate_blender.py
python3 assets/capybara/contact_sheets.py
python3 assets/capybara/write_reference.py
```

Blender 5.2 was used. `build.py -- --no-render` skips studio renders. `-- --preview` renders only front and front three-quarter. Contact sheets need Pillow; the actual model generator only needs Blender's bundled Python and NumPy. `finalize_glb.py` removes unused attributes, flattens identity parents of skinned meshes, and attaches clip metadata without changing geometry or motion samples. Run `npm install && npm run validate` inside `assets/capybara` to reproduce the Khronos check and verify clip durations, morph names, embedded textures, and the triangle budget. This optional development dependency is not needed by the viewer. The viewer's Three.js MIT license is included in `viewer/vendor/LICENSE.three`.
'''
(P/'capybara_reference.md').write_text(text)
