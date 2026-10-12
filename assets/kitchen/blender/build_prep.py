"""Builds the Prep station: a French dresser and kitchen library on the back wall, either side of
the window. Open oak shelves edged in brass hold leather cookbooks with gilt bands, white
tureens, copper moulds and jars of dry goods; tall glass-fronted cabinets with brass mullions
close each end; a framed cork recipe board with cards pinned in brass; a carved ivory cornice.
An enamel "PRÉPARATION" plaque sits under the window, herbs either side; a brass scale and a
mortar and pestle at the counter's ends. Exports prep.glb for the app.

    Blender -b --factory-startup -P build_prep.py -- <out.glb> [review_dir]

Contract (see README.md): footprint 9.2 x 1.2 (x -4.6..4.6, y -0.6..0.6), worktop at 0.707,
front strip of the top (y < -0.05) clear: chefs set their plate down there. The wall's window
(x -1.33..1.33, from 0.95 up) stays open.
"""
import bpy, math, random, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kitchen_kit import *
from french_back import *

WIDTH = 9.2
WINDOW = (-1.36, 1.36, 0.94)          # x range and sill height of the room's window
rng = random.Random(41)
OAK = mat("oak_shelf", "8a5a32", 0.6)
IVORY = mat("ivory_cornice", "e9e1cc", 0.5)
GLASS = mat("cabinet_glass", "1d2b29", 0.06, 0.1)
CORK = mat("cork", "b88a5c", 0.95)
FRAME_OAK = mat("frame_oak", "6e4426", 0.5)
CARD = mat("recipe_card", "fbf6e8", 0.85)
INK = mat("recipe_ink", "3b3a36", 0.8)
BOOKS = [mat(f"book_{i}", c, 0.55) for i, c in enumerate(["7a2a24", "234235", "5a3a22", "27344f", "8b5a2b", "3d2c3e"])]
GILT = mat("gilt", "d1aa52", 0.25, 0.9)
PORCELAIN = mat("porcelain", "f6f2ea", 0.25)
COPPER = mat("copper", "c47a46", 0.3, 0.9)
JAR = mat("jar_glass", "c9d3c8", 0.08)
GRAIN = [mat(f"dry_goods_{i}", c, 0.9) for i, c in enumerate(["e3c88f", "b6532f", "efe7d2", "6b4a2b"])]
POT = mat("terracotta", "c46a3e", 0.8)
LEAF = mat("herb", "4f8a3a", 0.7)
STONE = mat("mortar_stone", "a9a49a", 0.85)

SHELVES = (1.08, 1.48, 1.88)
TOP_Z = 2.28
BACK_Y = WALL_Y - 0.01
SHELF_DEPTH = 0.32

def dresser(x0, x1):
    """A dresser section from x0 to x1 standing on the counter's back."""
    yc = WALL_Y - SHELF_DEPTH / 2
    box((x1 - x0, 0.02, TOP_Z - TOP), ((x0 + x1) / 2, BACK_Y, TOP + (TOP_Z - TOP) / 2), LACQUER, 0.0)
    for x in (x0 + 0.03, x1 - 0.03):
        box((0.06, SHELF_DEPTH, TOP_Z - TOP), (x, yc, TOP + (TOP_Z - TOP) / 2), LACQUER, 0.01, 2)
    # Carved cornice: a stepped ivory crown with a row of dentils.
    box((x1 - x0 + 0.08, SHELF_DEPTH + 0.06, 0.06), ((x0 + x1) / 2, yc - 0.02, TOP_Z + 0.03), IVORY, 0.01, 2)
    box((x1 - x0 + 0.14, SHELF_DEPTH + 0.1, 0.04), ((x0 + x1) / 2, yc - 0.03, TOP_Z + 0.08), IVORY, 0.012, 2)
    n = int((x1 - x0) / 0.09)
    for k in range(n):
        box((0.04, 0.03, 0.04), (x0 + 0.045 + k * (x1 - x0 - 0.09) / max(1, n - 1), yc - SHELF_DEPTH / 2 - 0.03, TOP_Z - 0.005), IVORY, 0.004, 1)

def shelves(x0, x1):
    yc = WALL_Y - SHELF_DEPTH / 2
    for z in SHELVES:
        box((x1 - x0, SHELF_DEPTH - 0.02, 0.035), ((x0 + x1) / 2, yc, z), OAK, 0.006, 1)
        box((x1 - x0, 0.012, 0.018), ((x0 + x1) / 2, yc - SHELF_DEPTH / 2 + 0.006, z + 0.008), BRASS, 0.003, 1)

def books(x0, x1, z):
    """A run of leather cookbooks on a shelf, with gilt bands, some leaning at the end."""
    x = x0 + 0.03
    while x < x1 - 0.06:
        w, h = rng.uniform(0.035, 0.06), rng.uniform(0.24, 0.32)
        c = rng.choice(BOOKS)
        box((w - 0.004, 0.2, h), (x + w / 2, WALL_Y - 0.13, z + 0.0175 + h / 2), c, 0.004, 1)
        for dz in (0.04, h - 0.05):
            box((w - 0.002, 0.004, 0.012), (x + w / 2, WALL_Y - 0.232, z + 0.0175 + dz), GILT, 0.0)
        x += w

def tureens(x0, x1, z):
    for k, x in enumerate((x0 + 0.18, x0 + 0.5)):
        if x > x1 - 0.12: break
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, segments=24, ring_count=12, location=(x, WALL_Y - 0.15, z + 0.0175 + 0.09))
        o = bpy.context.active_object; o.scale = (1, 1, 0.75); bpy.ops.object.transform_apply(scale=True)
        finish(o, PORCELAIN, smooth=True)
        cyl(0.02, 0.03, (x, WALL_Y - 0.15, z + 0.2), PORCELAIN, 12)

def moulds_and_jars(x0, x1, z):
    x = x0 + 0.1
    for k in range(int((x1 - x0 - 0.1) / 0.17)):
        if k % 2 == 0:
            cyl(0.07, 0.09, (x, WALL_Y - 0.15, z + 0.06), COPPER, 24, r2=0.05, bevel=0.006)     # copper mould
        else:
            cyl(0.06, 0.2, (x, WALL_Y - 0.15, z + 0.12), JAR, 20, bevel=0.01)
            cyl(0.055, 0.12, (x, WALL_Y - 0.15, z + 0.08), rng.choice(GRAIN), 20)
            cyl(0.062, 0.03, (x, WALL_Y - 0.15, z + 0.235), BRASS, 20, bevel=0.005)
        x += 0.17

def glass_cabinet(x0, x1):
    """A tall glazed cabinet: lacquered frame, dark glass, brass glazing bars and knob."""
    yc = WALL_Y - SHELF_DEPTH / 2
    box((x1 - x0, SHELF_DEPTH, TOP_Z - TOP), ((x0 + x1) / 2, yc, TOP + (TOP_Z - TOP) / 2), LACQUER, 0.012, 2)
    fy = WALL_Y - SHELF_DEPTH - 0.01
    box((x1 - x0 - 0.1, 0.01, TOP_Z - TOP - 0.14), ((x0 + x1) / 2, fy, TOP + (TOP_Z - TOP) / 2), GLASS, 0.0)
    for k in range(1, 4):
        z = TOP + 0.07 + k * (TOP_Z - TOP - 0.14) / 4
        box((x1 - x0 - 0.1, 0.012, 0.012), ((x0 + x1) / 2, fy - 0.005, z), BRASS, 0.003, 1)
    box((0.012, 0.012, TOP_Z - TOP - 0.14), ((x0 + x1) / 2, fy - 0.005, TOP + (TOP_Z - TOP) / 2), BRASS, 0.003, 1)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.018, segments=12, ring_count=8, location=(x1 - 0.08 if x0 < 0 else x0 + 0.08, fy - 0.02, TOP + 0.75))
    finish(bpy.context.active_object, BRASS_BRIGHT, smooth=True)

def recipe_board(x0, x1, z0, z1):
    y = WALL_Y - 0.03
    box((x1 - x0, 0.03, z1 - z0), ((x0 + x1) / 2, y, (z0 + z1) / 2), FRAME_OAK, 0.008, 2)
    box((x1 - x0 - 0.1, 0.03, z1 - z0 - 0.1), ((x0 + x1) / 2, y - 0.008, (z0 + z1) / 2), CORK, 0.0)
    for i in range(6):
        cx = x0 + 0.2 + (i % 3) * (x1 - x0 - 0.4) / 2 + rng.uniform(-0.03, 0.03)
        cz = z1 - 0.22 - (i // 3) * 0.36 + rng.uniform(-0.02, 0.02)
        c = box((0.2, 0.004, 0.27), (cx, y - 0.026, cz), CARD, 0.002, 1)
        c.rotation_euler = (0, rng.uniform(-0.08, 0.08), 0)
        for k in range(4):
            l = box((rng.uniform(0.08, 0.14), 0.002, 0.007), (cx - 0.015, y - 0.03, cz + 0.08 - k * 0.045), INK, 0.0)
            l.rotation_euler = c.rotation_euler
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.012, segments=10, ring_count=6, location=(cx, y - 0.034, cz + 0.115))
        finish(bpy.context.active_object, BRASS_BRIGHT, smooth=True)

def counter_things():
    z = TOP
    # Brass scale (left end).
    cyl(0.09, 0.03, (-4.25, 0.2, z + 0.015), BRASS, 24, bevel=0.005)
    rod((-4.25, 0.2, z + 0.03), (-4.25, 0.2, z + 0.18), 0.012, BRASS, 10)
    cyl(0.12, 0.02, (-4.25, 0.2, z + 0.19), BRASS_BRIGHT, 28, r2=0.1, bevel=0.004)
    # Mortar and pestle (right end).
    cyl(0.09, 0.1, (4.25, 0.2, z + 0.05), STONE, 24, r2=0.07, bevel=0.01)
    rod((4.25, 0.2, z + 0.08), (4.31, 0.15, z + 0.2), 0.018, STONE, 10)
    # Herbs either side of the plaque, under the window.
    for x in (-0.95, 0.95):
        cyl(0.08, 0.12, (x, 0.32, z + 0.06), POT, 20, r2=0.1, bevel=0.008)
        for k in range(7):
            a = k * math.tau / 7
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.05, location=(x + 0.045 * math.cos(a), 0.32 + 0.045 * math.sin(a), z + 0.16 + 0.02 * (k % 2)))
            finish(bpy.context.active_object, LEAF)

def in_window(x0, x1, z0, z1):
    return x1 > WINDOW[0] and x0 < WINDOW[1] and z1 > WINDOW[2]

def build():
    for o in list(bpy.context.scene.objects): bpy.data.objects.remove(o, do_unlink=True)
    counter(WIDTH, seed=13)
    splashback(WIDTH, 1.157, skip=in_window)
    # Left: glass cabinet, a bay of shelves, the recipe board. Right: shelves, glass cabinet.
    lx0, lx1, rx0, rx1 = -4.52, -1.5, 1.5, 4.52     # the cornice overhangs 0.07: stay in the footprint
    dresser(lx0, lx1); dresser(rx0, rx1)
    glass_cabinet(lx0, lx0 + 0.65); glass_cabinet(rx1 - 0.65, rx1)
    shelves(lx0 + 0.65, lx0 + 1.45)
    for z in SHELVES: books(lx0 + 0.65, lx0 + 1.45, z) if z != SHELVES[1] else moulds_and_jars(lx0 + 0.65, lx0 + 1.45, z)
    recipe_board(lx0 + 1.5, lx1 - 0.08, 1.0, 2.15)
    shelves(rx0, rx1 - 0.65)
    books(rx0, rx1 - 0.65, SHELVES[2])
    books(rx0, rx0 + 1.4, SHELVES[0]); tureens(rx0 + 1.4, rx1 - 0.65, SHELVES[0])
    moulds_and_jars(rx0, rx1 - 0.65, SHELVES[1])
    plaque("PRÉPARATION", (0, WALL_Y - 0.02, 0.84), 1.25, 0.16)
    counter_things()
    root, merged, stats = assemble("prep", [], keep_uvs=("carrara_back",))
    print("PREP", stats)
    return root, merged

VIEWS = (("kitchen_view", (0, -9.5, 12.0), (0, 0, 0.9), (1600, 900)),
         ("left", (-2.4, -3.2, 1.5), (-2.8, 0.3, 1.4), (1600, 1000)),
         ("right", (2.6, -3.0, 1.5), (3.0, 0.3, 1.4), (1600, 1000)))

if __name__ == "__main__" and "--" in sys.argv:
    args = sys.argv[sys.argv.index("--") + 1:]
    root, meshes = build()
    export(args[0], root, meshes)
    print("PREP exported", args[0])
    if len(args) > 1: review(args[1], VIEWS)
