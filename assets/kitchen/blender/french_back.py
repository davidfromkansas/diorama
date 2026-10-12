"""The French back counter both wall stations share (orders, prep): a deep-green lacquered base
with raised-panel doors and brass pulls on a bronze kick plate, a Carrara marble top, a
crackle-glaze tiled splashback edged in brass, and enamel station plaques.

Model space as for the range: origin at the footprint's centre on the kitchen floor; x along the
counter; Blender -y is the room (where the chefs stand), +y the back wall. The wall's face is at
WALL_Y. The counter's front strip (y < FRONT_CLEAR) stays empty: chefs set things down there.
"""
import bpy, math
from kitchen_kit import *

DEPTH = 1.2
TOP = 0.707
SLAB = 0.06
WALL_Y = 0.56                  # the back wall's face (world z -7.76)
FRONT_CLEAR = -0.05            # nothing on the top in front of this

LACQUER = mat("green_lacquer", "26403b", 0.22, 0.05)
LACQUER_PANEL = mat("green_lacquer_panel", "2f4d47", 0.26, 0.05)
BRASS = mat("brass", "c9a04e", 0.3, 0.85)
BRASS_BRIGHT = mat("brass_polished", "dcb663", 0.16, 0.92)
BRONZE = mat("bronze", "8c6a3e", 0.36, 0.85)
PLINTH = mat("plinth", "1c2220", 0.8)
TILE = [mat(f"crackle_tile_{i}", c, 0.2) for i, c in enumerate(["f1ece0", "ece5d6", "f4f0e6"])]
GROUT = mat("splash_grout", "cfc6b4", 0.9)
ENAMEL = mat("enamel_plaque", "1f3a35", 0.25)
ENAMEL_IVORY = mat("enamel_ivory", "efe6cf", 0.25)

def counter(width, seed, name="carrara_back"):
    """Base, doors and marble top, `width` long."""
    box((width - 0.2, DEPTH - 0.3, 0.09), (0, 0.05, 0.045), PLINTH, 0.0)
    box((width - 0.1, 0.012, 0.085), (0, -DEPTH / 2 + 0.165, 0.05), BRONZE, 0.004, 1)       # kick plate
    box((width - 0.06, DEPTH - 0.1, TOP - SLAB - 0.09), (0, 0.04, 0.09 + (TOP - SLAB - 0.09) / 2), LACQUER, 0.02, 2)
    bays = max(2, round(width / 0.8))
    bay = (width - 0.1) / bays
    face = -DEPTH / 2 + 0.09
    h = TOP - SLAB - 0.15
    for i in range(bays):
        x = -width / 2 + 0.05 + bay * (i + 0.5)
        box((bay - 0.03, 0.03, h), (x, face, 0.11 + h / 2), LACQUER, 0.01, 2)                # door
        box((bay - 0.17, 0.02, h - 0.16), (x, face - 0.018, 0.11 + h / 2), LACQUER_PANEL, 0.03, 3)  # raised panel
        box((bay - 0.12, 0.012, 0.012), (x, face - 0.022, 0.11 + h - 0.05), BRASS, 0.003, 1)  # brass bead
        rod((x - 0.12, face - 0.07, TOP - SLAB - 0.09), (x + 0.12, face - 0.07, TOP - SLAB - 0.09), 0.011, BRASS_BRIGHT, 12)
        for dx in (-0.12, 0.12):
            rod((x + dx, face - 0.015, TOP - SLAB - 0.09), (x + dx, face - 0.07, TOP - SLAB - 0.09), 0.008, BRASS, 8)
    marble_slab(width, DEPTH, SLAB, (0, 0, TOP - SLAB / 2), name, seed)

def splashback(width, top, skip=None):
    """Crackle-glaze tiles in a brick bond on the wall from the worktop up to `top`, edged in
    brass. `skip(x0, x1, z0, z1)` leaves out tiles (behind a window)."""
    w, h = 0.3, 0.15
    y = WALL_Y - 0.006
    box((width, 0.004, top - TOP), (0, WALL_Y - 0.002, TOP + (top - TOP) / 2), GROUT, 0.0)
    row = 0
    z = TOP
    while z + h <= top + 1e-6:
        x = -width / 2 + (w / 2 if row % 2 else 0)
        while x < width / 2 - 0.02:
            x0, x1 = max(x, -width / 2), min(x + w, width / 2)
            if x1 - x0 > 0.04 and not (skip and skip(x0, x1, z, z + h)):
                box((x1 - x0 - 0.008, 0.012, h - 0.008), ((x0 + x1) / 2, y, z + h / 2), TILE[(row * 7 + int((x + 10) / w)) % 3], 0.003, 1)
            x += w
        z += h; row += 1
    box((width, 0.02, 0.025), (0, WALL_Y - 0.01, z + 0.0125), BRASS, 0.004, 1)

def plaque(text, loc, width, height=0.2):
    """A deep-green enamel plaque with an ivory border and lettering, fixed to the wall."""
    x, y, z = loc
    box((width + 0.04, 0.012, height + 0.04), (x, y + 0.004, z), BRASS, 0.004, 1)
    box((width, 0.012, height), (x, y - 0.004, z), ENAMEL, 0.004, 1)
    for dz in (-height / 2 + 0.025, height / 2 - 0.025):
        box((width - 0.05, 0.006, 0.008), (x, y - 0.012, z + dz), ENAMEL_IVORY, 0.0)
    bpy.ops.object.text_add(location=(0, 0, 0))
    t = bpy.context.active_object
    t.data.body = text; t.data.align_x = "CENTER"; t.data.align_y = "CENTER"
    t.data.size = height * 0.42; t.data.extrude = 0.002
    bpy.ops.object.convert(target="MESH")
    t.rotation_euler = (math.pi / 2, 0, 0)
    t.location = (x, y - 0.012, z)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    xs = [v.co.x for v in t.data.vertices]
    span = max(xs) - min(xs)
    if span > width - 0.08:                       # fit the lettering inside the border
        k = (width - 0.08) / span
        for v in t.data.vertices:
            v.co.x = x + (v.co.x - x) * k; v.co.z = z + (v.co.z - z) * k
    finish(t, ENAMEL_IVORY)
