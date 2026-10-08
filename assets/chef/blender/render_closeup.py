"""Close-up renders of the chop hands/knife for every frame of a clip.
blender -b chef-rigged.blend -P render_closeup.py -- manifest.json outdir clip"""
import bpy, sys, os, json
from mathutils import Matrix, Vector
sys.path.insert(0, os.path.dirname(__file__))
import render_util as U
argv = sys.argv[sys.argv.index("--") + 1:]
man = json.load(open(argv[0])); out = argv[1]; clip = argv[2]
os.makedirs(out, exist_ok=True)
arm = bpy.data.objects["chef_rig"]
for pb in arm.pose.bones:
    for c in pb.constraints: c.mute = True
arm.animation_data.action = bpy.data.actions[clip]
U.setup_scene((480, 400))
st = man["stations"]
bpy.ops.mesh.primitive_cube_add(size=1)
counter = bpy.context.active_object
counter.scale = (1.0, 0.45, st["counter_top"]); counter.location = (0, -st["counter_front_from_root"] - 0.225, st["counter_top"] / 2)
props = {o.name: o for o in bpy.data.objects if o.name.startswith("prop_")}
for o in props.values(): o.hide_render = True
bf = -st["counter_front_from_root"] - 0.14
props["prop_cutting_board"].hide_render = False
props["prop_cutting_board"].matrix_world = Matrix.Translation((0, bf, st["counter_top"]))
props["prop_ingredient"].hide_render = False
props["prop_ingredient"].matrix_world = Matrix.Translation((0.03, bf - 0.02, st["counter_top"] + 0.02))
k = props["prop_knife"]; k.hide_render = False
a = man["attach"]["prop_knife"]["working_chop"]
U.VIEWS["close34"] = (Vector((-2.2, -4.0, 2.6)), 0.75)
U.VIEWS["closeside"] = (Vector((-6, 0, 1.0)), 0.75)
n = man["clips"][clip]["frames"] - 1
for f in range(0, n):
    bpy.context.scene.frame_set(f)
    k.matrix_world = arm.matrix_world @ arm.pose.bones[a["socket"]].matrix @ Matrix(a["blender"])
    for v in ("close34", "closeside"):
        U.shot(f"{out}/{clip}_{f:03d}_{v}.png", v, target=Vector((-0.02, -0.45, 0.72)))
print("RENDERED")
