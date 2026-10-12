"""Builds the cabinets that join the back and side stations, matching them: deep-green lacquered
raised-panel doors, brass bar pulls, a bronze kick plate and a Carrara marble top (the shared
French back counter). Exports connectors.glb for the app.

    Blender -b --factory-startup -P build_connectors.py -- <out.glb> [review_dir]

Unlike the stations, this model is in kitchen space: origin at the kitchen's centre on the floor
(the app places it at height `KitchenLayout.floorTop`). The rectangles are
`KitchenLayout.connectors` (x, z, width, depth in kitchen x/z); cabinets on the right wall face
the room (-x).

The long right-wall run carries two brushed-stainless drop-in sinks: one wide basin with rounded
corners under a thin rim on the marble, a pull-down faucet wound with an open coil spring, and a
soap pump. The side wall is low there, so the faucets are deck-mounted and there is no splashback.
"""
import bpy, math, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kitchen_kit import *
import french_back as F

SINK_RUN = 4                      # the right wall's long run
SINK_BAYS = (2, 5)                # centred on these door bays (kitchen z ≈ 2.4 and 4.8)
SINK_W, SINK_D, SINK_H = 1.0, 0.62, 0.23     # outer size: along the run, across, deep
SINK_Y = -0.17                    # its centre across the counter (front edge clear of the doors)
STAINLESS = mat("stainless", "dfe2e3", 0.32, 0.4)     # half-metal: the kitchen has little to reflect
STAINLESS_DARK = mat("stainless_dark", "9fa4a6", 0.4, 0.4)
COPPER = mat("copper", "c47a46", 0.3, 0.9)

def bay_centre(length, i):
    bays = max(2, round(length / 0.8))
    return -length / 2 + 0.05 + (length - 0.1) / bays * (i + 0.5)

def cut(target, size, loc, round_by=0.0):
    """Boolean the box `size` at `loc` (its edges rounded by `round_by`) out of `target`."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    c = bpy.context.active_object; c.scale = size
    if round_by:
        b = c.modifiers.new("round", "BEVEL"); b.width = round_by; b.segments = 4
    m = target.modifiers.new("cut", "BOOLEAN"); m.operation = "DIFFERENCE"; m.object = c; m.solver = "EXACT"
    return c

def pull_down_faucet(x, y):
    """A stainless pull-down kitchen faucet: a column wound with an open coil spring, arching over
    to a spray head that hangs down over the basin, and a side lever."""
    T = F.TOP
    cyl(0.032, 0.02, (x, y, T + 0.01), STAINLESS, 20, bevel=0.004)                 # deck plate
    cyl(0.022, 0.12, (x, y, T + 0.08), STAINLESS, 16, bevel=0.004)                 # body
    rod((x + 0.02, y, T + 0.12), (x + 0.09, y + 0.02, T + 0.14), 0.007, STAINLESS, 8)   # lever
    rod((x, y, T + 0.14), (x, y, T + 0.5), 0.009, STAINLESS, 10)                   # hose inside the coil
    for k in range(14):                                                           # the coil
        torus(0.03, 0.0045, (x, y, T + 0.16 + k * 0.024), STAINLESS, seg=16, ring=5)
    # The arching neck, out toward the basin (-y), and the spray head hanging from it.
    pts = []
    for k in range(9):
        a = math.pi * k / 8
        pts.append((x, y - 0.11 * (1 - math.cos(a)), T + 0.5 + 0.11 * math.sin(a)))
    for p, q in zip(pts, pts[1:]): rod(p, q, 0.011, STAINLESS, 10)
    rod((x, y - 0.22, T + 0.5), (x, y - 0.22, T + 0.4), 0.016, STAINLESS, 14)        # spray head
    cyl(0.02, 0.012, (x, y - 0.22, T + 0.394), STAINLESS_DARK, 14)
    # A soap pump beside it.
    cyl(0.018, 0.03, (x + 0.16, y, T + 0.015), STAINLESS, 14, bevel=0.003)
    rod((x + 0.16, y, T + 0.03), (x + 0.16, y, T + 0.08), 0.006, STAINLESS, 8)
    rod((x + 0.16, y, T + 0.08), (x + 0.16, y - 0.04, T + 0.08), 0.005, STAINLESS, 8)

def sink(length, i, bowls):
    """A brushed-stainless drop-in sink centred on door bay `i` (station space, before the run is
    turned): one wide basin with rounded corners under a thin flat rim on the marble."""
    T = F.TOP
    x = bay_centre(length, i)
    top = T + 0.012                                # the rim sits on the marble
    body = box((SINK_W, SINK_D, SINK_H), (x, SINK_Y, top - SINK_H / 2), STAINLESS, 0.01, 2)
    floor = top - SINK_H + 0.02
    cutters = [cut(body, (SINK_W - 0.08, SINK_D - 0.08, 0.5), (x, SINK_Y, floor + 0.25), round_by=0.045)]
    cyl(0.045, 0.004, (x, SINK_Y, floor + 0.002), STAINLESS_DARK, 24)             # drain
    torus(0.045, 0.006, (x, SINK_Y, floor + 0.004), STAINLESS, seg=24, ring=6)
    pull_down_faucet(x - 0.05, SINK_Y + SINK_D / 2 + 0.09)
    if bowls:                                      # copper bowls drying beside it
        for k in range(4):
            cyl(0.13 - k * 0.012, 0.04, (x + SINK_W / 2 + 0.2, 0.25, T + 0.02 + k * 0.032), COPPER, 24, r2=0.08 - k * 0.008)
    return x, SINK_Y, cutters

CONNECTORS = [(-9.2, -7.8, 0.8, 1.2), (-3.6, -7.8, 2.4, 1.2), (8.0, -7.8, 3.8, 1.2),
              (10.6, -6.6, 1.2, 2.2), (10.6, 0.4, 1.2, 7.2)]

def build():
    for o in list(bpy.context.scene.objects): bpy.data.objects.remove(o, do_unlink=True)
    sinks = []
    for i, (x, z, w, d) in enumerate(CONNECTORS):
        sideways = x >= 10.6              # against the right wall (not the narrow one by the elevator)
        length = d if sideways else w
        start = len(PARTS)
        F.counter(length, seed=30 + i, name=f"carrara_connector_{i}")
        # Kitchen x/z to Blender x/y (Blender y = -z); sideways ones turn to face -x.
        cx, cz = x + w / 2, z + d / 2
        cutters = []
        if i == SINK_RUN:
            slab, cabinet = PARTS[-1], PARTS[start + 2]
            for n, bay_i in enumerate(SINK_BAYS):
                hole = (SINK_W - 0.04, SINK_D - 0.04, 0.5)    # under the rim
                at = (bay_centre(length, bay_i), SINK_Y, F.TOP)
                cutters += [cut(slab, hole, at), cut(cabinet, hole, (at[0], at[1], at[2] - 0.05))]
                sx, sy, more = sink(length, bay_i, bowls=(n == 1))
                cutters += more
                # Station (x, y) turns to kitchen Blender (cx + y, -cz - x) on the sideways run.
                sinks.append(anchor(f"sink_{n}", (cx + sy, -cz - sx, F.TOP)))
        for o in PARTS[start:]:
            # Bake the part's own placement into its mesh, then turn and move the whole cabinet.
            bpy.ops.object.select_all(action="DESELECT")
            o.select_set(True); bpy.context.view_layer.objects.active = o
            for m in list(o.modifiers): bpy.ops.object.modifier_apply(modifier=m.name)
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
            o.rotation_mode = "XYZ"
            o.rotation_euler = (0, 0, -math.pi / 2 if sideways else 0)
            o.location = (cx, -cz, 0)
        for c in cutters: bpy.data.objects.remove(c, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in PARTS:
        o.select_set(True); bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    root, merged, stats = assemble("connectors", sinks, keep_uvs=tuple(f"carrara_connector_{i}" for i in range(len(CONNECTORS))))
    print("CONNECTORS", stats)
    return root, merged

VIEWS = (("back_right", (6.0, 2.0, 5.0), (9.5, 7.0, 0.5), (1600, 1000)),
         ("sinks", (8.4, -2.6, 2.3), (11.2, -3.6, 0.75), (1600, 1000)))

if __name__ == "__main__" and "--" in sys.argv:
    args = sys.argv[sys.argv.index("--") + 1:]
    root, meshes = build()
    export(args[0], root, meshes)
    print("CONNECTORS exported", args[0])
    if len(args) > 1: review(args[1], VIEWS)
