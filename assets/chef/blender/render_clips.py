"""Render verification frames of baked clips with props + stations attached.
blender -b <chef-rigged.blend> -P tools/blender/render_clips.py -- <manifest.json> <outdir> [clip,clip] [views]"""
import bpy, sys, os, json
from mathutils import Matrix, Vector
sys.path.insert(0, os.path.dirname(__file__))
import render_util as U
argv = sys.argv[sys.argv.index("--") + 1:]
man = json.load(open(argv[0])); out = argv[1]
clips = argv[2].split(",") if len(argv) > 2 and argv[2] else list(man["clips"])
views = argv[3].split(",") if len(argv) > 3 else ["front", "side", "production"]
os.makedirs(out, exist_ok=True)
arm = bpy.data.objects["chef_rig"]
U.setup_scene((360, 480))
props = {o.name: o for o in bpy.data.objects if o.name.startswith("prop_")}
st = man["stations"]
# simple station counter for context
cm = bpy.data.materials.new("counter"); cm.use_nodes = True
cm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.55, 0.6, 0.65, 1)
bpy.ops.mesh.primitive_cube_add(size=1)
counter = bpy.context.active_object; counter.name = "verify_counter"
counter.scale = (1.0, 0.45, st["counter_top"]); counter.location = (0, -st["counter_front_from_root"] - 0.225, st["counter_top"] / 2)
counter.data.materials.append(cm)
STATION_CLIPS = {"working_chop", "testing_dish", "waiting_tool", "present_review", "putdown", "pickup", "cancel_cleanup"}
def place(name, loc):
    o = props[name]; o.hide_render = False
    o.matrix_world = Matrix.Translation(loc)
HELD = {"planning_recipe": [("prop_recipe_card", "planning_recipe")], "researching_book": [("prop_cookbook", "researching_book")],
        "working_chop": [("prop_knife", "working_chop")], "testing_dish": [("prop_spoon", "testing_dish")],
        "carry_idle": [("prop_plate", "carry_idle")], "carry_walk": [("prop_plate", "carry_idle")]}
bfront = -st["counter_front_from_root"] - 0.14
for clip in clips:
    meta = man["clips"][clip]
    act = bpy.data.actions[clip]
    # play the baked action without the authoring constraints
    for pb in arm.pose.bones:
        for c in pb.constraints: c.mute = True
    arm.animation_data.action = act
    n = meta["frames"] - 1
    frames = sorted(set([0, n // 4, n // 2, (3 * n) // 4] + [round(v * n) for v in meta["markers"].values()]))
    for o in props.values(): o.hide_render = True
    counter.hide_render = clip not in STATION_CLIPS
    for f in frames:
        bpy.context.scene.frame_set(f)
        for o in props.values(): o.hide_render = True
        held = list(HELD.get(clip, []))
        plate_clips = {"present_review": "release", "putdown": "release", "cancel_cleanup": "release", "pickup": "attach"}
        if clip in plate_clips:
            mk = round(meta["markers"][plate_clips[clip]] * n)
            holding = (f < mk) if clip != "pickup" else (f >= mk)
            if holding: held.append(("prop_plate", "carry_idle"))
            else: place("prop_plate", Vector((0, bfront, st["counter_top"])))
        if clip == "working_chop":
            place("prop_cutting_board", Vector((0, bfront, st["counter_top"])))
            props["prop_ingredient"].hide_render = False
            props["prop_ingredient"].matrix_world = Matrix.Translation((0.03, bfront - 0.02, st["counter_top"] + 0.02))
        if clip == "testing_dish": place("prop_plate", Vector((-0.12, bfront, st["counter_top"])))
        if clip == "waiting_tool": place("prop_pot", Vector((-0.12, bfront, st["counter_top"])))
        for prop, fit in held:
            a = man["attach"][prop][fit]
            off = Matrix(a["blender"])
            o = props[prop]; o.hide_render = False
            o.matrix_world = arm.matrix_world @ arm.pose.bones[a["socket"]].matrix @ off
        for v in views:
            U.shot(f"{out}/{clip}_{f:03d}_{v}.png", v)
print("RENDERED")
