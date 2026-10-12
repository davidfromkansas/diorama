"""Builds the Pantry (where agents fetch skills, plugins and MCP servers) as a Provençal
garde-manger with a Michelin larder's order: the shared French counter (deep-green lacquer,
Carrara top), and on its back a green lacquered hutch with an ivory cornice and a *GARDE-MANGER*
plaque. Its open shelves, edged in brass, hold ordered rows of Le Parfait preserve jars (skills)
and Provençal confit pots glazed yellow-ochre and emerald, olive-oil bottles and blue tins;
garlic braids, lavender and thyme bundles hang in the end bays, copper pans on the posts. On the
counter: produce crates of lemons, tomatoes and aubergines (plugins), and three cream-enamel
appliances with brass trim and a status light (MCP servers). Exports pantry.glb.

    Blender -b --factory-startup -P build_pantry.py -- <out.glb> [review_dir]

Contract (see README.md): built like the back stations (x along the counter, Blender -y the room);
the app turns it to stand against the left wall. Footprint 6.7 x 1.2; worktop at 0.707; the
top's front strip (y < -0.05) clear. Status lights use the material `status_light` (the app makes
it glow). The root is named `pantry`: clicking it opens the pantry.
"""
import bpy, math, random, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kitchen_kit import *
from french_back import *

WIDTH = 6.7
rng = random.Random(1789)
HUTCH_Y = 0.42           # the hutch's shelves sit over the counter's back
SHELF_D = 0.3
SHELVES = (1.08, 1.46)
CORNICE = 1.86
POSTS = [-3.3, -1.1, 1.1, 3.3]

OAK = mat("oak_shelf", "8a5a32", 0.6)
IVORY = mat("ivory_cornice", "e9e1cc", 0.5)
JAR = mat("jar_glass", "d5e0dc", 0.06)
SEAL = mat("jar_seal", "e0742f", 0.6)
WIRE = mat("jar_wire", "c3c6c8", 0.3, 0.9)
PRESERVES = [mat(f"preserve_{i}", c, 0.45) for i, c in enumerate(["e8a23a", "8e2b3a", "6b4a8f", "c84a2a", "5f7a2e", "d9c25a", "3f2a4f"])]
OCHRE = mat("confit_ochre", "c9952f", 0.18)
EMERALD = mat("confit_emerald", "1f6b4a", 0.18)
CLAY = mat("confit_clay", "b9784c", 0.7)
OIL_GLASS = mat("oil_glass", "3f5a2a", 0.08)
TIN_BLUE = mat("tin_blue", "1f4fa0", 0.35, 0.4)
TIN_YELLOW = mat("tin_yellow", "e7c23d", 0.35, 0.4)
GARLIC = mat("garlic", "efe6d2", 0.6)
STRAW = mat("straw", "b89b5a", 0.9)
LAVENDER = mat("lavender", "7d6bb3", 0.8)
THYME = mat("thyme", "5d7a45", 0.85)
COPPER = mat("copper", "c47a46", 0.3, 0.9)
CRATE = mat("crate_wood", "c99a62", 0.85)
CRATE_DARK = mat("crate_slat", "8f6438", 0.85)
LEMON = mat("lemon", "f1cd3a", 0.5)
TOMATO = mat("tomato", "c9322a", 0.35)
AUBERGINE = mat("aubergine", "3d2245", 0.3)
LEAF = mat("leaf", "4f8a3a", 0.7)
ENAMEL_CREAM = mat("appliance_cream", "efe6d0", 0.3)
DIAL = mat("dial_black", "1c1c1c", 0.4)
LIGHT = mat("status_light", "5cff9e", 0.3)
BASKET = mat("wicker", "a57a45", 0.9)

def hutch():
    yc = HUTCH_Y
    box((WIDTH - 0.1, 0.03, CORNICE - TOP), (0, yc + SHELF_D / 2, TOP + (CORNICE - TOP) / 2), LACQUER, 0.0)
    for x in POSTS:
        box((0.07, SHELF_D, CORNICE - TOP), (x, yc, TOP + (CORNICE - TOP) / 2), LACQUER, 0.012, 2)
    for z in SHELVES:
        box((WIDTH - 0.2, SHELF_D, 0.035), (0, yc, z), OAK, 0.006, 1)
        rod((-WIDTH / 2 + 0.15, yc - SHELF_D / 2 + 0.01, z + 0.06), (WIDTH / 2 - 0.15, yc - SHELF_D / 2 + 0.01, z + 0.06), 0.006, BRASS_BRIGHT, 8)
        for x in POSTS:
            rod((x, yc - SHELF_D / 2 + 0.01, z + 0.0175), (x, yc - SHELF_D / 2 + 0.01, z + 0.06), 0.005, BRASS, 6)
    box((WIDTH - 0.08, SHELF_D + 0.06, 0.06), (0, yc - 0.02, CORNICE + 0.03), IVORY, 0.01, 2)
    box((WIDTH - 0.02, SHELF_D + 0.1, 0.04), (0, yc - 0.03, CORNICE + 0.08), IVORY, 0.012, 2)
    for k in range(int(WIDTH / 0.09)):
        box((0.04, 0.03, 0.04), (-WIDTH / 2 + 0.045 + k * 0.09, yc - SHELF_D / 2 - 0.03, CORNICE - 0.005), IVORY, 0.004, 1)
    # A brass hanging rail under the cornice, for the herbs and garlic in the end bays.
    rod((-WIDTH / 2 + 0.1, yc - SHELF_D / 2 - 0.06, CORNICE - 0.06), (WIDTH / 2 - 0.1, yc - SHELF_D / 2 - 0.06, CORNICE - 0.06), 0.01, BRASS, 10)

def parfait_jar(x, y, z, h=0.2):
    # The app draws no see-through glass, so the jar shows its preserves, under a clear shoulder.
    r = 0.065
    cyl(r, h * 0.82, (x, y, z + h * 0.41), rng.choice(PRESERVES), 14)
    cyl(r, h * 0.18, (x, y, z + h * 0.91), JAR, 14)
    torus(r - 0.004, 0.006, (x, y, z + h + 0.002), SEAL, seg=14, ring=5)
    cyl(r - 0.002, 0.03, (x, y, z + h + 0.018), JAR, 14, r2=r - 0.02)
    rod((x, y - r, z + h - 0.02), (x, y - r - 0.004, z + h + 0.03), 0.003, WIRE, 6)

def confit_pot(x, y, z, glaze):
    """A Provençal confit pot: glazed above, bare clay at the foot, two little handles."""
    cyl(0.085, 0.05, (x, y, z + 0.025), CLAY, 16, r2=0.1)
    cyl(0.1, 0.17, (x, y, z + 0.135), glaze, 16, r2=0.075, bevel=0.01)
    torus(0.075, 0.01, (x, y, z + 0.22), glaze, seg=14, ring=5)
    for s in (-1, 1):
        torus(0.025, 0.007, (x + s * 0.1, y, z + 0.15), glaze, rot=(math.pi / 2, 0, 0), seg=8, ring=4)

def oil(x, y, z):
    cyl(0.04, 0.22, (x, y, z + 0.11), OIL_GLASS, 12)
    cyl(0.014, 0.07, (x, y, z + 0.255), OIL_GLASS, 10)
    cyl(0.016, 0.02, (x, y, z + 0.3), STRAW, 10)

def tin(x, y, z):
    box((0.12, 0.09, 0.2), (x, y, z + 0.1), TIN_BLUE, 0.008, 2)
    box((0.122, 0.092, 0.05), (x, y, z + 0.1), TIN_YELLOW, 0.004, 1)

def garlic_braid(x, y, z_top, length=0.3):
    for k in range(7):
        t = k / 6
        cx = x + 0.035 * math.sin(t * 7)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.035 + 0.008 * math.sin(t * 3), segments=8, ring_count=5, location=(cx, y, z_top - 0.05 - t * length))
        o = bpy.context.active_object; o.scale = (1, 1, 1.15); bpy.ops.object.transform_apply(scale=True)
        finish(o, GARLIC, smooth=True)
    rod((x, y, z_top), (x, y, z_top - length - 0.08), 0.008, STRAW, 6)

def herb_bundle(x, y, z_top, material):
    rod((x, y, z_top), (x, y, z_top - 0.08), 0.004, STRAW, 6)
    cyl(0.05, 0.26, (x, y, z_top - 0.22), material, 12, r2=0.015)          # heads down, stems up
    torus(0.02, 0.006, (x, y, z_top - 0.1), STRAW, seg=12, ring=6)

def copper_pan(x, y, z, r):
    cyl(r, 0.012, (x, y, z), COPPER, 28, rot=(math.pi / 2, 0, 0))
    torus(r, 0.008, (x, y + 0.006, z), COPPER, rot=(math.pi / 2, 0, 0), seg=28, ring=6)
    rod((x, y, z + r), (x, y, z + r + 0.16), 0.01, BRASS, 8)

def shelves_stock():
    y = HUTCH_Y - 0.03
    bays = list(zip(POSTS, POSTS[1:]))
    # Top shelf: ordered rows of preserve jars (the skills), the middle bay a full row.
    for a, b in bays:
        x = a + 0.12
        while x < b - 0.1:
            parfait_jar(x, y, SHELVES[1] + 0.0175); x += 0.15
    # Middle shelf: confit pots, olive oil and tins, alternating by bay.
    for i, (a, b) in enumerate(bays):
        x = a + 0.16
        k = 0
        while x < b - 0.14:
            if i == 1: confit_pot(x, y, SHELVES[0] + 0.0175, OCHRE if k % 2 == 0 else EMERALD); x += 0.24
            elif k % 3 == 2: tin(x, y, SHELVES[0] + 0.0175); x += 0.16
            else: oil(x, y, SHELVES[0] + 0.0175); x += 0.12
            k += 1
    # Lower shelf (the counter's back, inside the hutch): wicker baskets and big confit pots.
    for i, x in enumerate((-2.6, -1.6, 1.6, 2.6)):
        confit_pot(x, y + 0.02, TOP, EMERALD if i % 2 else OCHRE)
    # Hanging under the cornice in the end bays: garlic, lavender, thyme; copper on the posts.
    rail_y, rail_z = HUTCH_Y - SHELF_D / 2 - 0.06, CORNICE - 0.06
    for x0 in (-3.15, 1.2):
        for j, kind in enumerate(("garlic", "lavender", "thyme", "garlic", "lavender", "thyme", "garlic")):
            x = x0 + 0.15 + j * 0.27
            if kind == "garlic": garlic_braid(x, rail_y, rail_z)
            else: herb_bundle(x, rail_y, rail_z, LAVENDER if kind == "lavender" else THYME)
    for x, r in ((-3.22, 0.11), (3.22, 0.1)):   # inside the end posts
        copper_pan(x, HUTCH_Y - SHELF_D / 2 - 0.02, 1.25, r)

def crate(x, y, produce):
    w, d, h = 0.5, 0.36, 0.18
    for s in (-1, 1):
        box((w, 0.02, h), (x, y + s * (d / 2 - 0.01), TOP + h / 2), CRATE, 0.004, 1)
        box((0.02, d, h), (x + s * (w / 2 - 0.01), y, TOP + h / 2), CRATE_DARK, 0.004, 1)
    box((w - 0.02, d - 0.02, 0.015), (x, y, TOP + 0.01), CRATE_DARK, 0.002, 1)
    for i in range(6):
        px = x - 0.15 + (i % 3) * 0.15 + rng.uniform(-0.02, 0.02)
        py = y - 0.07 + (i // 3) * 0.14
        if produce is AUBERGINE:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.06, segments=10, ring_count=6, location=(px, py, TOP + 0.13))
            o = bpy.context.active_object; o.scale = (1.6, 0.9, 0.9); o.rotation_euler = (0, 0, rng.uniform(-0.4, 0.4))
        else:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.055, segments=10, ring_count=6, location=(px, py, TOP + 0.13))
            o = bpy.context.active_object
            if produce is LEMON: o.scale = (1.0, 1.0, 1.25)
        bpy.ops.object.transform_apply(rotation=True, scale=True)
        finish(o, produce, smooth=True)
    if produce is LEMON:
        for i in range(3):
            l = box((0.1, 0.04, 0.008), (x - 0.1 + i * 0.12, y + 0.12, TOP + 0.2), LEAF, 0.0)
            l.rotation_euler = (0, 0.2, rng.uniform(-0.6, 0.6))

def appliance(x, y):
    """A cream-enamel appliance with brass trim, a dial and a status light (an MCP server)."""
    box((0.38, 0.3, 0.32), (x, y, TOP + 0.16), ENAMEL_CREAM, 0.06, 4)
    box((0.392, 0.31, 0.025), (x, y, TOP + 0.08), BRASS, 0.006, 1)
    cyl(0.045, 0.025, (x - 0.07, y - 0.155, TOP + 0.21), DIAL, 20, rot=(math.pi / 2, 0, 0), bevel=0.006)
    torus(0.047, 0.006, (x - 0.07, y - 0.16, TOP + 0.21), BRASS_BRIGHT, rot=(math.pi / 2, 0, 0), seg=20, ring=6)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.022, segments=12, ring_count=8, location=(x + 0.1, y - 0.15, TOP + 0.24))
    finish(bpy.context.active_object, LIGHT, smooth=True)

def counter_things():
    y = 0.08
    for x, produce in ((-2.75, LEMON), (-1.25, TOMATO), (1.25, AUBERGINE), (2.75, LEMON)):
        crate(x, y, produce)
    for x in (-2.0, 0.0, 2.0):
        appliance(x, y + 0.04)
    # A wicker basket of garlic heads by the middle appliance.
    cyl(0.14, 0.12, (0.55, y + 0.05, TOP + 0.06), BASKET, 20, r2=0.17, bevel=0.01)
    for k in range(5):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.045, segments=10, ring_count=6, location=(0.55 + 0.06 * math.cos(k * 1.3), y + 0.05 + 0.06 * math.sin(k * 1.3), TOP + 0.15))
        finish(bpy.context.active_object, GARLIC, smooth=True)

def build():
    for o in list(bpy.context.scene.objects): bpy.data.objects.remove(o, do_unlink=True)
    counter(WIDTH, seed=27)
    hutch()
    shelves_stock()
    counter_things()
    plaque("GARDE-MANGER", (0, HUTCH_Y - SHELF_D / 2 - 0.075, CORNICE + 0.04), 1.4, 0.15)
    root, merged, stats = assemble("pantry", [], keep_uvs=("carrara_back",))
    print("PANTRY", stats)
    return root, merged

VIEWS = (("kitchen_view", (0, -9.0, 10.0), (0, 0, 0.9), (1600, 900)),
         ("front", (-1.2, -3.0, 1.6), (-1.6, 0.3, 1.3), (1600, 1000)),
         ("counter", (1.6, -2.4, 1.6), (1.8, 0.1, 0.8), (1600, 1000)))

if __name__ == "__main__" and "--" in sys.argv:
    args = sys.argv[sys.argv.index("--") + 1:]
    root, meshes = build()
    export(args[0], root, meshes)
    print("PANTRY exported", args[0])
    if len(args) > 1: review(args[1], VIEWS)
