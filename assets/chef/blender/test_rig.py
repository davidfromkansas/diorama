"""Rig verification: weight-region colours + deformation stress poses.
blender -b --factory-startup -P tools/blender/test_rig.py -- <src.glb> <outdir>"""
import bpy, sys, os, colorsys
sys.path.insert(0, os.path.dirname(__file__))
import chef_rig as R, render_util as U
argv = sys.argv[sys.argv.index("--") + 1:]
src, out = argv[0], argv[1]
os.makedirs(out, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
mesh = R.import_chef(src)
arm = R.build_armature()
n = R.skin_mesh(mesh, arm)
print("unique positions", n, "pole", R.setup_leg_ik(arm))
U.setup_scene()
mode = argv[2] if len(argv) > 2 else "all"
if mode in ("all", "weights"):
    # colour by weighted bone hue
    names = [b.name for b in arm.data.bones if b.use_deform]
    hues = {nm: (i * 0.618) % 1.0 for i, nm in enumerate(names)}
    me = mesh.data
    attr = me.color_attributes.new("wviz", "FLOAT_COLOR", "POINT")
    gi = {g.index: g.name for g in mesh.vertex_groups}
    for v in me.vertices:
        c = [0, 0, 0]
        for g in v.groups:
            r, gg, b = colorsys.hsv_to_rgb(hues[gi[g.group]], 0.8, 0.9)
            c[0] += r * g.weight; c[1] += gg * g.weight; c[2] += b * g.weight
        attr.data[v.index].color = (*c, 1)
    orig = me.materials[0]
    mat = bpy.data.materials.new("wviz"); mat.use_nodes = True
    nt = mat.node_tree
    a = nt.nodes.new("ShaderNodeAttribute"); a.attribute_name = "wviz"
    nt.links.new(a.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    me.materials[0] = mat
    for v in ("front", "side", "back"):
        U.shot(f"{out}/w_{v}.png", v)
    me.materials[0] = orig
if mode in ("all", "poses"):
    P = arm.pose.bones
    def reset():
        for pb in P:
            pb.rotation_quaternion = (1, 0, 0, 0); pb.location = (0, 0, 0)
    def rot(b, rx=0, ry=0, rz=0):
        P[b].rotation_quaternion = R.arm_space_rot(arm, b, rx, ry, rz)
    poses = {
        "shoulder_lift": lambda: (rot("upperarm.L", 0, -60, 0), rot("upperarm.R", -80, 0, 0), rot("clavicle.L", 0, -15, 0)),
        "elbow_bend": lambda: (rot("forearm.L", -100, 0, 0), rot("forearm.R", -60, 0, 30), rot("upperarm.R", -30, 25, 0)),
        "head_turn": lambda: (rot("head", 10, 0, 35), rot("neck", 0, 0, 10)),
        "knee_bend": lambda: (P["hips"].__setattr__("location", R.arm_space_rot(arm, "hips").inverted() @ __import__("mathutils").Vector((0, 0, -0.10))),),
        "step": lambda: (P["foot_ik.L"].__setattr__("location", (0, 0.0, 0.12)), P["foot_ik.R"].__setattr__("location", (0, -0.0, -0.10)), rot("hips", 0, 0, 0)),
    }
    for name, fn in poses.items():
        reset(); fn(); bpy.context.view_layer.update()
        for v in ("front", "side", "back"):
            U.shot(f"{out}/p_{name}_{v}.png", v)
