"""Builds the Orders station: a French chef's pass on the back wall. A polished brass ticket
rail with the orders clipped to it under an enamel "COMMANDES" plaque and two brass picture
lights, a black enamel station clock, and on the marble counter a brass ticket spike, a service
bell and a stack of slate menu boards. Exports order.glb for the app.

    Blender -b --factory-startup -P build_order.py -- <out.glb> [review_dir]

Contract (see README.md): footprint 4.8 x 1.2 (x -2.4..2.4, y -0.6..0.6), worktop at 0.707, the
front strip of the top (y < -0.05) clear: a chef sets its idea down there.
"""
import bpy, math, random, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kitchen_kit import *
from french_back import *

WIDTH = 4.8
rng = random.Random(23)
PAPER = [mat(f"ticket_{i}", c, 0.85) for i, c in enumerate(["fbf6e8", "f6efdc", "fdf9ef"])]
INK = mat("ticket_ink", "3b3a36", 0.8)
SLATE = mat("slate", "2e3133", 0.7)
CLOCK_FACE = mat("clock_face", "f5f0e2", 0.4)
CLOCK_BODY = mat("clock_body", "151515", 0.3, 0.2)
SHADE = mat("lamp_shade_inside", "fff1c8", 0.4)
CHALK = mat("chalk", "e8e6df", 0.9)

def ticket_rail():
    z, y = 1.35, WALL_Y - 0.06
    rod((-2.0, y, z), (2.0, y, z), 0.016, BRASS_BRIGHT, 18)
    rod((-2.0, y, z - 0.035), (2.0, y, z - 0.035), 0.008, BRASS, 12)          # the clip bar
    for x in (-2.05, 2.05):
        box((0.05, 0.08, 0.1), (x, WALL_Y - 0.04, z - 0.015), BRASS, 0.01, 2)
    xs = [-1.8 + i * 0.4 for i in range(10)]
    for x in xs:
        x += rng.uniform(-0.04, 0.04)
        t = box((0.21, 0.005, 0.29), (x, y - 0.012, z - 0.19), rng.choice(PAPER), 0.002, 1)
        t.rotation_euler = (0, rng.uniform(-0.06, 0.06), 0)
        for k in range(4):                                   # lines of a handwritten order
            l = box((rng.uniform(0.08, 0.15), 0.002, 0.008), (x - 0.02, y - 0.016, z - 0.09 - k * 0.045), INK, 0.0)
            l.rotation_euler = t.rotation_euler
        box((0.03, 0.012, 0.03), (x, y - 0.014, z - 0.04), BRASS, 0.003, 1)     # clip

def clock(x, z):
    y = WALL_Y - 0.03
    cyl(0.17, 0.05, (x, y, z), CLOCK_BODY, 40, rot=(math.pi / 2, 0, 0), bevel=0.01)
    torus(0.15, 0.012, (x, y - 0.03, z), BRASS_BRIGHT, rot=(math.pi / 2, 0, 0), seg=40, ring=8)
    cyl(0.14, 0.01, (x, y - 0.028, z), CLOCK_FACE, 40, rot=(math.pi / 2, 0, 0))
    for k in range(12):
        a = k * math.tau / 12
        box((0.008, 0.004, 0.025 if k % 3 else 0.04), (x + 0.115 * math.sin(a), y - 0.035, z + 0.115 * math.cos(a)), CLOCK_BODY, 0.0).rotation_euler = (0, -a, 0)
    box((0.012, 0.004, 0.075), (x + 0.02, y - 0.038, z + 0.03), CLOCK_BODY, 0.0).rotation_euler = (0, -0.6, 0)
    box((0.008, 0.004, 0.105), (x - 0.03, y - 0.039, z + 0.04), CLOCK_BODY, 0.0).rotation_euler = (0, 0.75, 0)
    cyl(0.012, 0.01, (x, y - 0.042, z), BRASS, 12, rot=(math.pi / 2, 0, 0))

def picture_light(x):
    """A brass arm reaching out over the tickets, with a little hooded lamp."""
    z = 1.68
    box((0.08, 0.012, 0.06), (x, WALL_Y - 0.006, z), BRASS, 0.005, 1)
    rod((x, WALL_Y - 0.01, z), (x, WALL_Y - 0.2, z + 0.06), 0.009, BRASS, 10)
    h = cyl(0.045, 0.32, (x, WALL_Y - 0.22, z + 0.05), BRASS_BRIGHT, 20, rot=(0, math.pi / 2, 0))
    cyl(0.038, 0.31, (x, WALL_Y - 0.225, z + 0.042), SHADE, 16, rot=(0, math.pi / 2, 0))

def counter_things():
    z = TOP
    # Ticket spike (back left), with a few spent orders on it.
    cyl(0.05, 0.02, (-2.05, 0.3, z + 0.01), BRASS, 24, bevel=0.004)
    rod((-2.05, 0.3, z + 0.02), (-2.05, 0.3, z + 0.24), 0.005, BRASS_BRIGHT, 8)
    for k in range(3):
        p = box((0.13, 0.17, 0.004), (-2.05, 0.3, z + 0.06 + k * 0.012), rng.choice(PAPER), 0.0)
        p.rotation_euler = (0, 0, rng.uniform(-0.6, 0.6))
    # Service bell (back right).
    cyl(0.06, 0.018, (2.05, 0.28, z + 0.009), CLOCK_BODY, 28, bevel=0.004)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.055, segments=24, ring_count=12, location=(2.05, 0.28, z + 0.02))
    b = bpy.context.active_object; b.scale = (1, 1, 0.85)
    bpy.ops.object.transform_apply(scale=True)
    bm_cut = [v for v in b.data.vertices if v.co.z < -0.002]
    finish(b, BRASS_BRIGHT, smooth=True)
    cyl(0.01, 0.025, (2.05, 0.28, z + 0.075), BRASS, 10)
    # A stack of slate menu boards, propped against the splashback.
    for k in range(3):
        s = box((0.36, 0.022, 0.48), (1.45 - k * 0.05, WALL_Y - 0.09 - k * 0.03, z + 0.24), SLATE, 0.006, 1)
        s.rotation_euler = (math.radians(-12), 0, 0)
    for k in range(4):
        box((0.24 - k * 0.03, 0.003, 0.012), (1.35, WALL_Y - 0.155, z + 0.36 - k * 0.07), CHALK, 0.0).rotation_euler = (math.radians(-12), 0, 0)

def build():
    for o in list(bpy.context.scene.objects): bpy.data.objects.remove(o, do_unlink=True)
    counter(WIDTH, seed=9)
    splashback(WIDTH, 1.157)
    ticket_rail()
    plaque("COMMANDES", (-0.2, WALL_Y - 0.01, 1.8), 1.3)
    clock(1.7, 1.8)
    for x in (-1.2, 0.8): picture_light(x)
    counter_things()
    root, merged, stats = assemble("order", [], keep_uvs=("carrara_back",))
    print("ORDER", stats)
    return root, merged

VIEWS = (("kitchen_view", (0, -7.5, 9.5), (0, 0, 0.8), (1600, 900)),
         ("front", (0.6, -3.0, 1.3), (0.2, 0.3, 1.1), (1600, 1000)))

if __name__ == "__main__" and "--" in sys.argv:
    args = sys.argv[sys.argv.index("--") + 1:]
    root, meshes = build()
    export(args[0], root, meshes)
    print("ORDER exported", args[0])
    if len(args) > 1: review(args[1], VIEWS)
