"""Builds the break room's coffee bar: a short cabinet in the kitchen's deep-green lacquer with
raised-panel doors, brass pulls and kick plate and a Carrara top at worktop height; stacked
espresso cups and saucers at one end. The espresso machine (BreakRoom/espresso.glb) stands on it
at the `machine` empty. Exports coffee_bar.glb.

    Blender -b --factory-startup -P build_coffee_bar.py -- <out.glb> [review_dir]

Units and axes as for the back stations: origin at the footprint's centre on the floor, x along
the bar, Blender -y the room. Footprint WIDTH x DEPTH; top at F.TOP.
"""
import bpy, math, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kitchen_kit import *
import french_back as F

WIDTH, DEPTH = 1.6, 0.72
PORCELAIN = mat("porcelain", "f6f2ea", 0.25)
COFFEE = mat("espresso", "3a2214", 0.3)

def cabinet():
    T = F.TOP
    box((WIDTH - 0.1, DEPTH - 0.14, 0.09), (0, 0.03, 0.045), F.PLINTH, 0.0)
    box((WIDTH - 0.04, 0.012, 0.085), (0, -DEPTH / 2 + 0.075, 0.05), F.BRONZE, 0.004, 1)        # kick plate
    box((WIDTH - 0.04, DEPTH - 0.06, T - F.SLAB - 0.09), (0, 0.02, 0.09 + (T - F.SLAB - 0.09) / 2), F.LACQUER, 0.02, 2)
    face, h = -DEPTH / 2 + 0.05, T - F.SLAB - 0.15
    for x in (-WIDTH / 4, WIDTH / 4):
        w = WIDTH / 2 - 0.08
        box((w, 0.03, h), (x, face, 0.11 + h / 2), F.LACQUER, 0.01, 2)
        box((w - 0.14, 0.02, h - 0.16), (x, face - 0.018, 0.11 + h / 2), F.LACQUER_PANEL, 0.03, 3)
        box((w - 0.09, 0.012, 0.012), (x, face - 0.022, 0.11 + h - 0.05), F.BRASS, 0.003, 1)
        rod((x - 0.1, face - 0.07, T - F.SLAB - 0.09), (x + 0.1, face - 0.07, T - F.SLAB - 0.09), 0.011, F.BRASS_BRIGHT, 12)
        for dx in (-0.1, 0.1):
            rod((x + dx, face - 0.015, T - F.SLAB - 0.09), (x + dx, face - 0.07, T - F.SLAB - 0.09), 0.008, F.BRASS, 8)
    marble_slab(WIDTH, DEPTH, F.SLAB, (0, 0, T - F.SLAB / 2), "carrara_bar", 41)

def cups():
    T = F.TOP
    x0 = WIDTH / 2 - 0.16
    for i in range(4):                                                     # a stack of saucers
        cyl(0.06, 0.008, (x0, 0.12, T + 0.004 + i * 0.009), PORCELAIN, 20)
    for k, (dx, dy) in enumerate(((0, -0.06), (0.0, -0.18), (-0.12, -0.12))):   # cups stacked two high
        for j in range(2):
            z = T + 0.02 + j * 0.045
            cyl(0.035, 0.045, (x0 + dx, dy, z), PORCELAIN, 16, r2=0.028)
    cyl(0.035, 0.045, (-WIDTH / 2 + 0.16, -0.1, T + 0.0225), PORCELAIN, 16, r2=0.028)
    cyl(0.028, 0.004, (-WIDTH / 2 + 0.16, -0.1, T + 0.044), COFFEE, 16)       # a fresh one, poured

def build():
    for o in list(bpy.context.scene.objects): bpy.data.objects.remove(o, do_unlink=True)
    cabinet(); cups()
    root, merged, stats = assemble("coffee_bar", [anchor("machine", (-0.12, 0.02, F.TOP))], keep_uvs=("carrara_bar",))
    print("COFFEE_BAR", stats)
    return root, merged

VIEWS = (("front", (1.2, -2.6, 1.8), (0, 0, 0.5), (1200, 900)),)

if __name__ == "__main__" and "--" in sys.argv:
    args = sys.argv[sys.argv.index("--") + 1:]
    root, meshes = build()
    export(args[0], root, meshes)
    print("COFFEE_BAR exported", args[0])
    if len(args) > 1: review(args[1], VIEWS)
