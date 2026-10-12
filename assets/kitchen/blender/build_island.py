"""Builds the kitchen's cooking island, French industrial: a honed Carrara marble top on a
blackened-steel frame with cast-bronze fittings and open oak shelves stocked with copper pots,
bowls and linens. Exports island.glb for the app.

    Blender -b --factory-startup -P build_island.py -- <out.glb> [review_dir]

Units, origin and axes as for the range (kitchen_kit.py): origin at the centre of the island's
footprint on the kitchen floor; Blender -y is the camera side, +y the chefs' side.

Contract with the app (see README.md):
- footprint x -4.5..4.5, y -0.6..0.6, nothing outside it;
- marble top at TOP (0.707 above the floor = the kitchen worktop);
- empties `board_0`..`board_5` (left to right) at the centre of each cutting board's footprint
  on the marble: the app puts the boards (and their resting cleavers) there, and chefs chop on
  them exactly as before.
"""
import bpy, bmesh, math, random, sys, os
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kitchen_kit import *

WIDTH, DEPTH = 9.0, 1.2
TOP = 0.707
SLAB = 0.06
SPOTS = [-3.75, -2.25, -0.75, 0.75, 2.25, 3.75]
BOARD_Y = DEPTH / 2 - 0.38            # the boards sit toward the chefs' side, as before
LEGS = [-4.36, -2.25, 0.0, 2.25, 4.36]
LEG_Y = 0.545            # frame flush under the slab's edge, so the kitchen camera sees it
rng = random.Random(11)

# ---------------------------------------------------------------- materials
STEEL = mat("blackened_steel", "2a2826", 0.48, 0.75)
BRONZE = mat("bronze", "8c6a3e", 0.36, 0.85)
BRONZE_DARK = mat("bronze_dark", "6e5230", 0.45, 0.8)
OAK = mat("brushed_oak", "b48a5a", 0.72)
OAK_DARK = mat("oak_end", "9a7246", 0.75)
COPPER = mat("copper", "c47a46", 0.3, 0.9)
CERAMIC = mat("ceramic", "f1ede4", 0.35)
LINEN = mat("linen", "e7e0d2", 0.95)
LINEN_STRIPE = mat("linen_stripe", "5b6f8a", 0.95)
UTENSIL = mat("olive_wood", "a7804f", 0.6)
GLASS = mat("cruet_glass", "a9b58a", 0.1)

# ---------------------------------------------------------------- the marble
def top():
    """The slab, with a softly rounded edge."""
    return marble_slab(WIDTH, DEPTH, SLAB, (0, 0, TOP - SLAB / 2), "carrara")

# ---------------------------------------------------------------- frame
def frame():
    leg = 0.085
    for x in LEGS:
        for y in (-LEG_Y, LEG_Y):
            box((leg, leg, TOP - SLAB - 0.05), (x, y, 0.05 + (TOP - SLAB - 0.05) / 2), STEEL, 0.008, 2)
            cyl(0.06, 0.05, (x, y, 0.025), BRONZE, 28, r2=0.045, bevel=0.006)     # turned bronze shoe
            box((leg + 0.02, leg + 0.02, 0.03), (x, y, TOP - SLAB - 0.09), BRONZE, 0.006, 2)  # collar under the apron
    # Deep apron under the slab, with a bronze band along the camera side and the ends.
    h = 0.12
    for y in (-LEG_Y, LEG_Y):
        box((WIDTH - 0.24, 0.035, h), (0, y, TOP - SLAB - h / 2), STEEL, 0.006, 2)
    for x in (LEGS[0], LEGS[-1]):
        box((0.035, 2 * LEG_Y, h), (x, 0, TOP - SLAB - h / 2), STEEL, 0.006, 2)
    box((WIDTH - 0.2, 0.012, 0.024), (0, -LEG_Y - 0.02, TOP - SLAB - 0.02), BRONZE, 0.004, 1)
    for x in (LEGS[0], LEGS[-1]):
        box((0.012, 2 * LEG_Y, 0.024), (x + (-0.02 if x < 0 else 0.02), 0, TOP - SLAB - 0.02), BRONZE, 0.004, 1)
    # Rivets along the apron's camera side.
    for i in range(46):
        x = -WIDTH / 2 + 0.2 + i * (WIDTH - 0.4) / 45
        if any(abs(x - lx) < 0.08 for lx in LEGS): continue
        cyl(0.009, 0.01, (x, -LEG_Y - 0.022, TOP - SLAB - 0.09), BRONZE_DARK, 10, rot=(math.pi / 2, 0, 0))
    # Corner brackets: bronze gussets where the legs meet the apron.
    for x in LEGS:
        for y in (-LEG_Y, LEG_Y):
            for dx in (-1, 1):
                if (x == LEGS[0] and dx < 0) or (x == LEGS[-1] and dx > 0): continue
                b = box((0.11, 0.012, 0.11), (x + dx * 0.09, y + (-0.02 if y < 0 else 0.02), TOP - SLAB - 0.15), BRONZE, 0.003, 1)
                b.rotation_euler = (0, math.radians(45 * dx), 0)
    # Low stretcher and the camera-side bronze rail (inside the footprint, under the overhang).
    for y in (-LEG_Y, LEG_Y):
        box((WIDTH - 0.24, 0.03, 0.03), (0, y, 0.11), STEEL, 0.005, 1)
    ry, rz = -DEPTH / 2 + 0.02, 0.3
    rod((-WIDTH / 2 + 0.2, ry, rz), (WIDTH / 2 - 0.2, ry, rz), 0.018, BRONZE, 18)
    for x in LEGS:
        rod((x, -LEG_Y - 0.04, rz), (x, ry, rz), 0.013, BRONZE_DARK, 12)

# ---------------------------------------------------------------- shelves and what's on them
def shelves():
    for z in (0.17, 0.4):
        for a, b in zip(LEGS, LEGS[1:]):
            n = 5
            for k in range(n):                       # planks, slightly varied
                w = (2 * LEG_Y - 0.02) / n
                y = -LEG_Y + 0.01 + w * (k + 0.5)
                box((b - a - 0.09, w - 0.006, 0.026), ((a + b) / 2, y, z), OAK if k % 2 else OAK_DARK, 0.004, 1)

def pot(x, y, z, r, h, material=COPPER):
    cyl(r, h, (x, y, z + h / 2), material, 28, bevel=0.006)
    torus(r, 0.008, (x, y, z + h), material, seg=28, ring=6)
    rod((x + r, y, z + h * 0.75), (x + r + 0.12, y, z + h * 0.8), 0.009, BRONZE_DARK, 8)

def stock():
    """Copper pots and pans, stacked bowls, an utensil crock and folded linens on the shelves."""
    for i, (a, b) in enumerate(zip(LEGS, LEGS[1:])):
        mid = (a + b) / 2
        upper, lower = 0.4 + 0.013, 0.17 + 0.013
        # Upper shelf: a row of copper pots, largest in the middle, and a stack of bowls.
        for dx, r, h in ((-0.6, 0.11, 0.12), (-0.3, 0.14, 0.15), (0.0, 0.12, 0.1)):
            pot(mid + dx, -0.33 + rng.uniform(-0.04, 0.04), upper, r, h, COPPER if rng.random() > 0.25 else BRONZE)
        for k in range(4):
            cyl(0.13 - k * 0.012, 0.035, (mid + 0.5, -0.33, upper + 0.02 + k * 0.03), CERAMIC, 28, r2=0.09 - k * 0.01)
        # Lower shelf: a big stockpot or a crock of utensils, and folded linens.
        if i % 2 == 0:
            pot(mid - 0.45, -0.33, lower, 0.17, 0.17)
        else:
            cyl(0.09, 0.16, (mid - 0.45, -0.33, lower + 0.08), CERAMIC, 24, bevel=0.01)
            for k in range(5):
                a2 = k * math.tau / 5
                top_pt = (mid - 0.45 + 0.04 * math.cos(a2), -0.33 + 0.04 * math.sin(a2), lower + 0.32)
                rod((mid - 0.45, -0.33, lower + 0.05), top_pt, 0.009, UTENSIL, 8)
        for k in range(3):
            box((0.42, 0.3, 0.035), (mid + 0.3, -0.32, lower + 0.02 + k * 0.037), LINEN, 0.01, 2)
            box((0.42, 0.04, 0.036), (mid + 0.3, -0.41, lower + 0.02 + k * 0.037), LINEN_STRIPE, 0.005, 1)

def accents():
    """Two small things on the camera side of the top, clear of the boards."""
    z = TOP
    for x in (-1.5, 1.5):
        cyl(0.06, 0.05, (x, -0.38, z + 0.025), BRONZE, 24, r2=0.05, bevel=0.006)          # salt cellar
        cyl(0.04, 0.16, (x + 0.16, -0.38, z + 0.08), GLASS, 20, r2=0.03)                   # olive-oil cruet
        cyl(0.012, 0.05, (x + 0.16, -0.38, z + 0.185), BRONZE_DARK, 10)

# ---------------------------------------------------------------- build
def build():
    for o in list(bpy.context.scene.objects): bpy.data.objects.remove(o, do_unlink=True)
    marble = top()
    frame(); shelves(); stock(); accents()
    anchors = [anchor(f"board_{i}", (x, BOARD_Y, TOP)) for i, x in enumerate(SPOTS)]
    root, merged, stats = assemble("island", anchors, keep_uvs=(marble.name,))
    print("ISLAND", stats)
    return root, merged

VIEWS = (("kitchen_view", (0, -9.5, 13.0), (0, 0, 0.5), (1600, 900)),
         ("three_quarter", (3.0, -3.2, 1.8), (1.0, 0, 0.45), (1600, 1000)),
         ("top", (-0.75, -1.4, 2.4), (-0.75, 0.05, 0.7), (1200, 900)))

if __name__ == "__main__" and "--" in sys.argv:
    args = sys.argv[sys.argv.index("--") + 1:]
    root, meshes = build()
    if len(args) > 1:
        # Stand-in boards for the review renders only (the app adds the real ones).
        for x in SPOTS:
            b = box((0.9 * 0.707 / 0.707, 0.55, 0.035), (x, BOARD_Y, TOP + 0.0175), mat("board_preview", "a0703f", 0.7), 0.008, 2)
            PARTS.remove(b)
    export(args[0], root, meshes)
    print("ISLAND exported", args[0])
    if len(args) > 1: review(args[1], VIEWS)
