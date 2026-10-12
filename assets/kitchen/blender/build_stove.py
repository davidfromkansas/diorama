"""Builds the kitchen's range: an Italian metalwork cooker in sage enamel and brass, and exports
stove.glb for the app.

    Blender -b --factory-startup -P build_stove.py -- <out.glb> [review_dir]

Units are kitchen world units. Origin: the centre of the stove's footprint, on the kitchen floor
(the app places the model at the footprint's centre, at `KitchenLayout.floorTop`). Blender is Z-up
and the glTF exporter maps Blender (x, y, z) to SceneKit (x, z, -y), so Blender -y is the camera
side (ovens, knobs, towel bar) and +y is where the chefs stand.

Contract with the app (see README.md):
- footprint x -4.5..4.5, y -0.6..0.6; nothing may stick out of it (chefs path around it);
- cooktop at TOP (0.707 = worktop 0.819 - floor 0.112): the chef-side strip (y 0.35..0.6) is
  flat there, where a chef sets down its pot;
- empties `burner_0`..`burner_5` (left to right) sit on each burner crown's centre: the app lights
  its flames there.
Colours are the sRGB the app shows (Diorama's GLB loader reads baseColorFactor as sRGB).
"""
import bpy, bmesh, math, sys, os
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kitchen_kit import *

WIDTH, DEPTH = 9.0, 1.2
TOP = 0.707
BURNERS = [-3.75, -2.25, -0.75, 0.75, 2.25, 3.75]
BACK = DEPTH / 2              # chefs' side, at the footprint's edge
FRONT = -DEPTH / 2 + 0.16     # camera-side face, set back so the towel bar and handles stay inside
BODY_Y, BODY_D = (BACK + FRONT) / 2, BACK - FRONT
BURNER_Y = 0.0

# ---------------------------------------------------------------- materials
ENAMEL = mat("sage_enamel", "8fb09c", 0.32)
ENAMEL_DEEP = mat("sage_enamel_deep", "7c9d89", 0.4)
BRASS = mat("brass", "c9a04e", 0.3, 0.85)
BRASS_BRIGHT = mat("brass_polished", "dcb663", 0.16, 0.92)
BRASS_DARK = mat("brass_aged", "9c7a3a", 0.42, 0.8)
STEEL = mat("brushed_steel", "a3a6a8", 0.34, 0.8)
IRON = mat("cast_iron", "1d1d1c", 0.7, 0.35)
BURNER_CAP = mat("burner_cap", "141414", 0.55, 0.3)
GLASS = mat("oven_glass", "151a19", 0.08, 0.1)
PLINTH = mat("plinth", "2b302d", 0.8)
ENGRAVE = mat("engraving", "3a2e18", 0.6, 0.4)

# ---------------------------------------------------------------- the range
def body():
    box((WIDTH - 0.24, BODY_D - 0.16, 0.07), (0, BODY_Y, 0.035), PLINTH, 0.0)
    # Folded-steel body in enamel, the front frame standing slightly proud.
    box((WIDTH, BODY_D, TOP - 0.07 - 0.035), (0, BODY_Y, 0.07 + (TOP - 0.105) / 2), ENAMEL, 0.03, 3)
    box((WIDTH - 0.02, 0.03, TOP - 0.1), (0, FRONT - 0.01, 0.07 + (TOP - 0.1) / 2), ENAMEL_DEEP, 0.012, 2)
    # Brass corner posts: the range reads as a piece of furniture.
    for x in (-WIDTH / 2 + 0.03, WIDTH / 2 - 0.03):
        box((0.07, 0.07, TOP - 0.07), (x, FRONT + 0.02, 0.07 + (TOP - 0.07) / 2), BRASS, 0.02, 3)

def cooktop():
    # The deck is enamel, so the range reads sage from the kitchen camera above; each burner sits
    # on its own brushed-steel plate framed in brass.
    box((WIDTH, BODY_D, 0.035), (0, BODY_Y, TOP - 0.0175), ENAMEL, 0.012, 2)
    for x in BURNERS:
        box((0.82, 0.82, 0.01), (x, BURNER_Y, TOP + 0.001), STEEL, 0.004, 1)
        for dx, dy, sx, sy in ((0, -0.415, 0.86, 0.022), (0, 0.415, 0.86, 0.022), (-0.415, 0, 0.022, 0.86), (0.415, 0, 0.022, 0.86)):
            box((sx, sy, 0.014), (x + dx, BURNER_Y + dy, TOP + 0.004), BRASS, 0.005, 1)
    # Raised brass lip on the camera side and the ends; a low brass splash rail on the chefs' side.
    box((WIDTH + 0.02, 0.05, 0.035), (0, FRONT + 0.02, TOP + 0.012), BRASS_BRIGHT, 0.015, 3)
    for x in (-WIDTH / 2 + 0.02, WIDTH / 2 - 0.02):
        box((0.05, BODY_D, 0.035), (x, BODY_Y, TOP + 0.012), BRASS_BRIGHT, 0.015, 3)
    box((WIDTH, 0.04, 0.03), (0, BACK - 0.02, TOP + 0.01), BRASS, 0.012, 2)
    # Between the burner pairs: a brass seam over the three cooking zones.
    for x in (-1.5, 1.5):
        box((0.035, BODY_D - 0.1, 0.012), (x, BODY_Y, TOP + 0.004), BRASS, 0.004, 1)

def burner(x):
    """A cast-iron well, a brass crown ringed with flame ports, a black cap, and a heavy grate."""
    y, z = BURNER_Y, TOP
    cyl(0.27, 0.012, (x, y, z + 0.002), IRON, 48, bevel=0.004)
    cyl(0.155, 0.03, (x, y, z + 0.02), BRASS, 48, bevel=0.006)
    torus(0.155, 0.008, (x, y, z + 0.033), BRASS_DARK, seg=48, ring=8)
    for k in range(24):                       # flame ports
        a = k * math.tau / 24
        box((0.012, 0.012, 0.012), (x + 0.158 * math.cos(a), y + 0.158 * math.sin(a), z + 0.022), BURNER_CAP, 0.0)
    cyl(0.1, 0.014, (x, y, z + 0.041), BURNER_CAP, 40, bevel=0.004)
    cyl(0.035, 0.008, (x, y, z + 0.049), BRASS_BRIGHT, 24)
    # Grate: a square frame on four feet, four fingers reaching in toward the crown.
    s, h, t = 0.31, z + 0.07, 0.022
    for a, b in (((-s, -s), (s, -s)), ((s, -s), (s, s)), ((s, s), (-s, s)), ((-s, s), (-s, -s))):
        rod((x + a[0], y + a[1], h), (x + b[0], y + b[1], h), t, IRON, 10)
    for cx, cy in ((-s, -s), (s, -s), (s, s), (-s, s)):
        rod((x + cx, y + cy, z), (x + cx, y + cy, h), t * 0.9, IRON, 10)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        rod((x + dx * s, y + dy * s, h), (x + dx * 0.19, y + dy * 0.19, h + 0.006), t, IRON, 10)
        rod((x + dx * 0.19, y + dy * 0.19, h + 0.006), (x + dx * 0.19, y + dy * 0.19, z + 0.04), t * 0.85, IRON, 10)
    return anchor(f"burner_{BURNERS.index(x)}", (x, y, z + 0.05))

def controls():
    """Knob rail: a large knurled brass knob under each burner, on an engraved bezel."""
    y0, z = FRONT - 0.02, 0.6
    box((WIDTH - 0.3, 0.02, 0.15), (0, y0 + 0.005, z), BRASS_DARK, 0.01, 2)
    box((WIDTH - 0.34, 0.025, 0.13), (0, y0, z), ENAMEL, 0.01, 2)
    for x in BURNERS:
        torus(0.058, 0.009, (x, y0 - 0.015, z), BRASS, rot=(math.pi / 2, 0, 0), seg=40, ring=8)
        knob = cyl(0.05, 0.05, (x, y0 - 0.04, z), BRASS_BRIGHT, 24, rot=(math.pi / 2, 0, 0))
        bm = bmesh.new(); bm.from_mesh(knob.data)
        for v in bm.verts:                     # knurled skirt: alternate the rim radius
            r = math.hypot(v.co.x, v.co.y)
            if r > 0.04:
                a = math.atan2(v.co.y, v.co.x); k = 1.0 + 0.06 * math.cos(a * 24)
                v.co.x *= k; v.co.y *= k
        bm.to_mesh(knob.data); bm.free()
        cyl(0.034, 0.02, (x, y0 - 0.072, z), BRASS, 24, rot=(math.pi / 2, 0, 0), bevel=0.008)
        box((0.008, 0.01, 0.03), (x, y0 - 0.083, z + 0.015), ENGRAVE, 0.0)
    # Nameplate between the middle burners.
    box((0.5, 0.012, 0.07), (0, y0 - 0.012, z), BRASS_BRIGHT, 0.006, 2)
    box((0.42, 0.004, 0.012), (0, y0 - 0.019, z), ENGRAVE, 0.0)

def towel_bar():
    y, z = FRONT - 0.12, 0.47
    rod((-WIDTH / 2 + 0.12, y, z), (WIDTH / 2 - 0.12, y, z), 0.022, BRASS_BRIGHT, 20)
    for x in (-WIDTH / 2 + 0.14, -1.5, 1.5, WIDTH / 2 - 0.14):
        rod((x, FRONT - 0.01, z), (x, y, z), 0.016, BRASS, 14)
        cyl(0.032, 0.02, (x, FRONT - 0.015, z), BRASS, 20, rot=(math.pi / 2, 0, 0))
    for x in (-WIDTH / 2 + 0.12, WIDTH / 2 - 0.12):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.03, segments=16, ring_count=10, location=(x, y, z))
        finish(bpy.context.active_object, BRASS_BRIGHT, smooth=True)

def ovens():
    """Three wide ovens: thick brass frame, dark window with a brass bead, a handle on stand-offs."""
    y, zc, w, h = FRONT - 0.02, 0.27, 2.75, 0.3
    for x in (-3.0, 0.0, 3.0):
        box((w, 0.03, h + 0.07), (x, y + 0.005, zc), BRASS_DARK, 0.014, 2)
        box((w - 0.06, 0.03, h + 0.01), (x, y - 0.01, zc), ENAMEL, 0.012, 2)
        box((w - 0.3, 0.02, h - 0.1), (x, y - 0.025, zc - 0.01), GLASS, 0.008, 1)
        for dz in (-(h - 0.1) / 2 - 0.006, (h - 0.1) / 2 + 0.006):
            box((w - 0.28, 0.012, 0.012), (x, y - 0.032, zc - 0.01 + dz), BRASS, 0.004, 1)
        for dx in (-(w - 0.3) / 2 - 0.006, (w - 0.3) / 2 + 0.006):
            box((0.012, 0.012, h - 0.1), (x + dx, y - 0.032, zc - 0.01), BRASS, 0.004, 1)
        hz, hy = zc + h / 2 - 0.035, y - 0.09
        rod((x - w / 2 + 0.25, hy, hz), (x + w / 2 - 0.25, hy, hz), 0.017, BRASS_BRIGHT, 16)
        for dx in (-w / 2 + 0.3, w / 2 - 0.3):
            rod((x + dx, y - 0.02, hz), (x + dx, hy, hz), 0.012, BRASS, 12)
    # Pilasters between the ovens.
    for x in (-1.5, 1.5):
        box((0.06, 0.04, 0.42), (x, FRONT - 0.02, 0.29), BRASS, 0.015, 3)

def drawers():
    y, z = FRONT - 0.015, 0.1
    for x in (-3.0, 0.0, 3.0):
        box((2.75, 0.025, 0.07), (x, y, z), ENAMEL_DEEP, 0.01, 2)
        box((0.36, 0.02, 0.022), (x, y - 0.025, z + 0.005), BRASS_BRIGHT, 0.008, 2)

# ---------------------------------------------------------------- export
def build():
    # (Run with --factory-startup: the scene starts empty, and the materials above already exist.)
    for o in list(bpy.context.scene.objects): bpy.data.objects.remove(o, do_unlink=True)
    body(); cooktop()
    anchors = [burner(x) for x in BURNERS]
    controls(); towel_bar(); ovens(); drawers()
    root, merged, stats = assemble("stove", anchors)
    print("STOVE", stats)
    return root, merged

VIEWS = (("kitchen_view", (0, -9.5, 13.0), (0, 0, 0.5), (1600, 900)),
         ("three_quarter", (3.2, -3.4, 1.9), (0.8, 0, 0.55), (1600, 1000)),
         ("cooktop", (-0.75, -1.5, 2.1), (-0.75, 0, 0.7), (1200, 900)))

if __name__ == "__main__" and "--" in sys.argv:
    args = sys.argv[sys.argv.index("--") + 1:]
    root, meshes = build()
    export(args[0], root, meshes)
    print("STOVE exported", args[0])
    if len(args) > 1: review(args[1], VIEWS)
