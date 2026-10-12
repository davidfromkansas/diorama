"""Builds the Tasting station as a Michelin-style pass (after the marble-and-brass passes of
starred kitchens such as Mamani in Dallas, and the classic heat-lamp pass): the shared French
counter in deep-green lacquer with a Carrara top, and over its back a polished brass gantry
holding a marble plate shelf with stacked white plates and a row of extendable brass pass lamps,
one over each taster. On the counter's back: brass bar sinks (dipper wells) between the tasters,
tasting-spoon crocks, squeeze bottles, plating tweezers and folded linen. Exports tasting.glb.

    Blender -b --factory-startup -P build_tasting.py -- <out.glb> [review_dir]

Contract (see README.md): built like the back stations (x along the counter, Blender -y the room);
the app turns it to stand against the right wall. Footprint 4.8 x 1.2; worktop at 0.707; the
top's front strip (y < -0.05) clear: chefs set the dish they taste down there.
"""
import bpy, math, random, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kitchen_kit import *
from french_back import *

WIDTH = 4.8
SPOTS = [-1.6, 0.0, 1.6]
rng = random.Random(7)
PORCELAIN = mat("porcelain", "f6f2ea", 0.25)
LAMP_INSIDE = mat("lamp_glow", "fff0c4", 0.4)
SQUEEZE = [mat(f"squeeze_{i}", c, 0.3) for i, c in enumerate(["e9e3d4", "c9482f", "5b7a3a"])]
STEEL = mat("tweezer_steel", "b9bcbe", 0.25, 0.9)
LINEN = mat("linen", "e7e0d2", 0.95)
LINEN_STRIPE = mat("linen_stripe", "1f3a35", 0.95)
DARK = mat("sink_well", "1a1c1c", 0.3, 0.6)
WATER = mat("sink_water", "6f8f96", 0.05)

GANTRY_Y = 0.42          # the gantry's posts and shelf, over the back of the counter
SHELF_Z = 1.42

def gantry():
    for x in (-2.3, -0.8, 0.8, 2.3):
        rod((x, GANTRY_Y, TOP), (x, GANTRY_Y, SHELF_Z), 0.022, BRASS_BRIGHT, 16)
        cyl(0.04, 0.02, (x, GANTRY_Y, TOP + 0.01), BRASS, 20)
    # Marble plate shelf on a brass frame, with a brass gallery rail.
    marble_slab(WIDTH - 0.2, 0.3, 0.035, (0, GANTRY_Y, SHELF_Z + 0.0175), "carrara_shelf", 17)
    box((WIDTH - 0.18, 0.32, 0.02), (0, GANTRY_Y, SHELF_Z - 0.01), BRASS, 0.004, 1)
    rod((-2.3, GANTRY_Y - 0.15, SHELF_Z + 0.09), (2.3, GANTRY_Y - 0.15, SHELF_Z + 0.09), 0.009, BRASS_BRIGHT, 12)
    for x in (-2.3, -0.8, 0.8, 2.3):
        rod((x, GANTRY_Y - 0.15, SHELF_Z + 0.035), (x, GANTRY_Y - 0.15, SHELF_Z + 0.09), 0.006, BRASS, 8)
    # Stacks of white plates on the shelf, between the lamps.
    for x in (-2.0, -0.8, 0.8, 2.0):
        for k in range(rng.randint(5, 8)):
            cyl(0.13, 0.012, (x, GANTRY_Y + 0.02, SHELF_Z + 0.04 + k * 0.014), PORCELAIN, 28, r2=0.115)

def pass_lamp(x):
    """An extendable brass pass lamp hanging from the shelf over a taster's spot."""
    z0 = SHELF_Z - 0.02
    rod((x, GANTRY_Y - 0.05, z0), (x, GANTRY_Y - 0.28, z0 - 0.08), 0.01, BRASS, 10)
    rod((x, GANTRY_Y - 0.28, z0 - 0.08), (x, GANTRY_Y - 0.28, z0 - 0.26), 0.006, BRASS_BRIGHT, 8)
    cyl(0.12, 0.13, (x, GANTRY_Y - 0.28, z0 - 0.32), BRASS_BRIGHT, 32, r2=0.035, bevel=0.006)
    cyl(0.105, 0.01, (x, GANTRY_Y - 0.28, z0 - 0.385), LAMP_INSIDE, 32)

def dipper_well(x):
    """A small round brass bar sink sunk in the marble, with a swan-neck tap."""
    y = 0.22
    cyl(0.12, 0.012, (x, y, TOP + 0.003), BRASS_BRIGHT, 32, bevel=0.004)
    cyl(0.1, 0.012, (x, y, TOP + 0.006), DARK, 32)
    cyl(0.085, 0.004, (x, y, TOP + 0.011), WATER, 28)
    rod((x, y + 0.16, TOP), (x, y + 0.16, TOP + 0.22), 0.012, BRASS, 10)
    rod((x, y + 0.16, TOP + 0.22), (x, y + 0.05, TOP + 0.24), 0.01, BRASS, 10)
    rod((x, y + 0.05, TOP + 0.24), (x, y + 0.05, TOP + 0.17), 0.008, BRASS, 8)

def tools(x):
    """Between tasters: a crock of tasting spoons, squeeze bottles, tweezers and a folded towel."""
    y = 0.3
    cyl(0.055, 0.12, (x - 0.15, y, TOP + 0.06), PORCELAIN, 20, bevel=0.008)
    for k in range(6):
        a = k * math.tau / 6
        rod((x - 0.15, y, TOP + 0.04), (x - 0.15 + 0.03 * math.cos(a), y + 0.03 * math.sin(a), TOP + 0.2), 0.005, STEEL, 6)
    for k, c in enumerate(SQUEEZE):
        bx = x + 0.08 + k * 0.07
        cyl(0.028, 0.14, (bx, y + 0.02, TOP + 0.07), c, 16, bevel=0.006)
        cyl(0.01, 0.04, (bx, y + 0.02, TOP + 0.16), c, 10, r2=0.003)
    for dx in (-0.01, 0.01):
        r = rod((x + 0.05 + dx, y - 0.13, TOP + 0.005), (x + 0.25 + dx * 0.3, y - 0.13, TOP + 0.005), 0.004, STEEL, 6)
    box((0.3, 0.2, 0.03), (x - 0.02, y - 0.02, TOP + 0.015), LINEN, 0.008, 2)
    box((0.3, 0.03, 0.031), (x - 0.02, y - 0.1, TOP + 0.016), LINEN_STRIPE, 0.004, 1)

def build():
    for o in list(bpy.context.scene.objects): bpy.data.objects.remove(o, do_unlink=True)
    counter(WIDTH, seed=21)
    gantry()
    for x in SPOTS: pass_lamp(x)
    for x in (-0.8, 0.8): dipper_well(x)
    for x in (-2.1, 2.05): tools(x)
    # The station's plaque stands on brass posts at the back of the plate shelf.
    py = GANTRY_Y + 0.1
    for x in (-0.5, 0.5):
        rod((x, py + 0.012, SHELF_Z + 0.035), (x, py + 0.012, SHELF_Z + 0.2), 0.01, BRASS, 10)
    plaque("DÉGUSTATION", (0, py, SHELF_Z + 0.24), 1.3, 0.16)
    root, merged, stats = assemble("tasting", [], keep_uvs=("carrara_back", "carrara_shelf"))
    print("TASTING", stats)
    return root, merged

VIEWS = (("kitchen_view", (0, -7.5, 9.5), (0, 0, 0.8), (1600, 900)),
         ("front", (0.8, -3.0, 1.6), (0.2, 0.2, 1.0), (1600, 1000)))

if __name__ == "__main__" and "--" in sys.argv:
    args = sys.argv[sys.argv.index("--") + 1:]
    root, meshes = build()
    export(args[0], root, meshes)
    print("TASTING exported", args[0])
    if len(args) > 1: review(args[1], VIEWS)
