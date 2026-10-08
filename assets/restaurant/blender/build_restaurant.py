"""Builds the Mediterranean restaurant around the Diorama kitchen and exports restaurant.glb.

Run inside Blender (the Blender MCP runs it in the live session while iterating):
    exec(open(".../build_restaurant.py").read())
or headless (assets/restaurant/build.sh):
    Blender -b --factory-startup -P build_restaurant.py -- <out.glb>

Coordinates are kitchen world units. Blender is Z-up; the glTF exporter's +Y-up conversion maps
Blender (x, y, z) to SceneKit (x, z, -y), so SceneKit's +z (toward the camera, the dining
terrace) is Blender's -y. The kitchen itself (x -12..12, y -8..8, back wall at y 7.87, 2.9 high)
is not part of this model; `KitchenRef` boxes stand in for it while reviewing.

Colours are authored as the sRGB values the app shows: Diorama's GLB loader reads
baseColorFactor as sRGB, so Blender's own renders look slightly lighter than the app.
Anchors for the app: empties `seat_NN` (where a diner's root stands, between chair and table)
and `dish_NN` (the plate spot on the table in front of it), nearest the serving pass first.
"""
import bpy, bmesh, math, random, sys, os
from mathutils import Vector, Matrix

rng = random.Random(7)
ROOT_NAME = "restaurant"
TERRACE_TOP = 0.02
SEAT_TOP = 0.64          # chef sits with hips at 0.54 chef units x 1.4 scale, a little above the seat
TABLE_TOP = 0.98
SIT_BACK = 0.11          # a seated chef's hips sit this far behind its root

# ---------------------------------------------------------------- scene setup
def reset():
    for collection in list(bpy.data.collections):
        if collection.name in ("Restaurant", "KitchenRef"):
            for obj in list(collection.objects): bpy.data.objects.remove(obj, do_unlink=True)
            bpy.data.collections.remove(collection)
    for item in list(bpy.data.meshes):
        if item.users == 0: bpy.data.meshes.remove(item)

def collection(name):
    c = bpy.data.collections.new(name); bpy.context.scene.collection.children.link(c); return c

MATS = {}
def mat(name, rgb, rough=0.8, metal=0.0):
    if name in MATS: return MATS[name]
    m = bpy.data.materials.new(name); m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    MATS[name] = m
    return m

def hexrgb(h): return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))

# Palette (sRGB as the app shows it)
SAND = [mat(f"sandstone_{i}", hexrgb(c), 0.9) for i, c in enumerate(["e6ca98", "e0c18b", "ead1a3"])]
CLAY = [mat(f"clay_tile_{i}", hexrgb(c), 0.85) for i, c in enumerate(["c98a5c", "c3834f"])]
GROUT = mat("grout", hexrgb("9c7f5a"), 0.95)
COPING = mat("coping", hexrgb("d2b88d"), 0.9)
QUAY = mat("quay_wall", hexrgb("b08f66"), 0.95)
WHITEWASH = mat("whitewash", hexrgb("f6f1e7"), 0.85)
TERRACOTTA = [mat(f"terracotta_{i}", hexrgb(c), 0.75) for i, c in enumerate(["c8643b", "b9552f", "d6764a"])]
POT = mat("pot", hexrgb("c46a3e"), 0.8)
SOIL = mat("soil", hexrgb("5a3b26"), 1.0)
LEAF = [mat(f"leaf_{i}", hexrgb(c), 0.7) for i, c in enumerate(["4f9a3c", "3f8532", "62ad48"])]
GERANIUM = [mat(f"bloom_{i}", hexrgb(c), 0.6) for i, c in enumerate(["e8383f", "f05b8e", "ffffff"])]
LEMON = mat("lemon", hexrgb("f6d63d"), 0.5)
TRUNK = mat("trunk", hexrgb("7a5434"), 0.9)
CHAIR = mat("chair_blue", hexrgb("2e7fc0"), 0.55)
CLOTH = mat("tablecloth", hexrgb("fbfaf6"), 0.8)
CLOTH_EDGE = mat("tablecloth_edge", hexrgb("2e7fc0"), 0.8)
IRON = mat("iron", hexrgb("2c2a28"), 0.45, 0.6)
WATER = mat("water", hexrgb("1f93ab"), 0.15)
LILY = [mat(f"lily_{i}", hexrgb(c), 0.6) for i, c in enumerate(["5aa83a", "4c9631"])]
LILY_FLOWER = mat("lily_flower", hexrgb("f7a1c4"), 0.5)
WOOD = [mat(f"wood_{i}", hexrgb(c), 0.85) for i, c in enumerate(["a8774a", "946540"])]
BOAT = mat("boat_white", hexrgb("f4efe6"), 0.6)
BOAT_STRIPE = mat("boat_stripe", hexrgb("d8402f"), 0.6)
CANVAS = [mat(f"canvas_{i}", hexrgb(c), 0.8) for i, c in enumerate(["f4efe6", "d8402f"])]
GLASS = mat("lamp_glass", hexrgb("ffe9a8"), 0.2)
JAR = mat("olive_jar", hexrgb("b86b3f"), 0.7)
FOUNTAIN_WATER = mat("fountain_water", hexrgb("6fd3e0"), 0.1)

# ---------------------------------------------------------------- primitives
def finish(obj, material, bevel=0.0, segments=2, coll=None):
    obj.data.materials.clear(); obj.data.materials.append(material)
    if bevel > 0:
        mod = obj.modifiers.new("bevel", "BEVEL"); mod.width = bevel; mod.segments = segments; mod.limit_method = "ANGLE"
    for poly in obj.data.polygons: poly.use_smooth = False
    if coll is not None:
        for c in list(obj.users_collection): c.objects.unlink(obj)
        coll.objects.link(obj)
    return obj

def box(name, size, loc, material, bevel=0.03, segments=2, rot=0.0, coll=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=(0, 0, rot))
    o = bpy.context.active_object; o.name = name; o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(o, material, bevel, segments, coll)

def cyl(name, r, h, loc, material, verts=16, bevel=0.0, rot=(0, 0, 0), r2=None, coll=None):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=loc, rotation=rot)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r2, depth=h, location=loc, rotation=rot)
    o = bpy.context.active_object; o.name = name
    o = finish(o, material, bevel, 2, coll)
    for poly in o.data.polygons: poly.use_smooth = len(poly.vertices) == 4
    return o

def blob(name, r, loc, material, scale=(1, 1, 1), subdiv=1, coll=None):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=r, location=loc)
    o = bpy.context.active_object; o.name = name; o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for v in o.data.vertices: v.co *= 1 + rng.uniform(-0.12, 0.12)
    return finish(o, material, 0, 2, coll)

def empty(name, loc, coll):
    o = bpy.data.objects.new(name, None); o.location = loc; o.empty_display_size = 0.3; coll.objects.link(o); return o

def join(objects, name, coll):
    """Applies modifiers and merges `objects` into one mesh (keeping their materials)."""
    objects = [o for o in objects if o is not None]
    if not objects: return None
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    for o in objects:
        bpy.context.view_layer.objects.active = o
        for m in list(o.modifiers): bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.context.view_layer.objects.active = objects[0]
    if len(objects) > 1: bpy.ops.object.join()
    out = bpy.context.active_object; out.name = name
    for c in list(out.users_collection): c.objects.unlink(out)
    coll.objects.link(out)
    return out

# ---------------------------------------------------------------- pieces
def terrace(coll):
    parts = []
    # Grout bed under the whole platform, and the quay walls dropping to the water.
    parts.append(box("bed", (40, 26, 0.36), (0, -3, TERRACE_TOP - 0.2), GROUT, 0.0, coll=coll))
    parts += [box("quay_front", (40.6, 0.3, 0.7), (0, -16.15, -0.33), QUAY, 0.04, coll=coll),
              box("quay_back", (40.6, 0.3, 0.7), (0, 10.15, -0.33), QUAY, 0.04, coll=coll),
              box("quay_left", (0.3, 26.6, 0.7), (-20.15, -3, -0.33), QUAY, 0.04, coll=coll),
              box("quay_right", (0.3, 26.6, 0.7), (20.15, -3, -0.33), QUAY, 0.04, coll=coll)]
    tiles = {m.name: [] for m in SAND + CLAY}
    def tile_area(x0, x1, y0, y1, checker=False):
        y = y0
        row = 0
        while y < y1 - 0.01:
            x = x0 + (0.5 if row % 2 else 0.0)
            while x < x1 - 0.01:
                w = min(1.0, x1 - x) - 0.07
                if w > 0.25:
                    clay = checker and (int(math.floor(x)) + row) % 2 == 0
                    m = rng.choice(CLAY if clay else SAND); h = 0.08 + rng.uniform(0, 0.015)
                    tiles[m.name].append(box("tile", (w, 0.93, h), (x + (w + 0.07) / 2, y + 0.5, TERRACE_TOP - 0.04 + h / 2), m, 0.025, 1, coll=coll))
                x += 1.0 if x > x0 or row % 2 == 0 else 0.5
            y += 1.0; row += 1
    tile_area(-20, 20, -16, -8, checker=True)   # front terrace: a warm clay-and-sandstone checker
    tile_area(-20, -12, -8, 10, checker=True)   # left dining walkway
    tile_area(12, 20, -8, 10, checker=True)     # right dining walkway
    tile_area(-12, 12, 8, 10)            # behind the back wall (under the eaves)
    merged = [join(v, f"terrace_tiles_{k}", coll) for k, v in tiles.items()]
    # Coping stones along the platform edge.
    coping = []
    for x in [i + 0.5 for i in range(-20, 20)]:
        for y in (-15.85, 9.85):
            coping.append(box("coping", (0.96, 0.42, 0.14), (x, y, TERRACE_TOP + 0.05), COPING, 0.03, 1, coll=coll))
    for y in [i + 0.5 for i in range(-16, 10)]:
        for x in (-19.85, 19.85):
            coping.append(box("coping", (0.42, 0.96, 0.14), (x, y, TERRACE_TOP + 0.05), COPING, 0.03, 1, coll=coll))
    return [join(parts, "terrace_base", coll), *merged, join(coping, "terrace_coping", coll)]

def flower_box(x, y, along_x, parts, blooms, base=0.56, length=1.3):
    w, d = (length, 0.42) if along_x else (0.42, length)
    parts.append(box("planter", (w, d, 0.32), (x, y, base + 0.16), rng.choice(TERRACOTTA), 0.03, coll=None))
    parts.append(box("planter_soil", (w - 0.12, d - 0.12, 0.05), (x, y, base + 0.31), SOIL, 0.0, coll=None))
    for i in range(7):
        t = (i + 0.5) / 7 - 0.5
        px, py = (x + t * (w - 0.2), y + rng.uniform(-0.08, 0.08)) if along_x else (x + rng.uniform(-0.08, 0.08), y + t * (d - 0.2))
        blooms.append(blob("leaf", 0.16, (px, py, base + 0.42), rng.choice(LEAF), (1, 1, 0.75)))
        if i % 2 == 0:
            blooms.append(blob("bloom", 0.09, (px + rng.uniform(-0.05, 0.05), py, base + 0.54), rng.choice(GERANIUM[:2]), subdiv=1))

def parapet(coll):
    walls, extras = [], []
    # Front: two runs either side of the entrance; sides along the walkways.
    for x0, x1 in ((-19.6, -2.2), (2.2, 19.6)):
        walls.append(box("parapet", (x1 - x0, 0.36, 0.55), ((x0 + x1) / 2, -15.6, TERRACE_TOP + 0.27), WHITEWASH, 0.06, coll=coll))
        walls.append(box("parapet_cap", (x1 - x0 + 0.06, 0.44, 0.08), ((x0 + x1) / 2, -15.6, TERRACE_TOP + 0.59), COPING, 0.03, coll=coll))
    for x in (-19.6, 19.6):
        walls.append(box("parapet", (0.36, 25.2, 0.55), (x, -3.2, TERRACE_TOP + 0.27), WHITEWASH, 0.06, coll=coll))
        walls.append(box("parapet_cap", (0.44, 25.26, 0.08), (x, -3.2, TERRACE_TOP + 0.59), COPING, 0.03, coll=coll))
    # Entrance posts with lanterns.
    for x in (-2.2, 2.2):
        walls.append(box("gate_post", (0.5, 0.5, 1.1), (x, -15.6, TERRACE_TOP + 0.55), WHITEWASH, 0.06, coll=coll))
        walls.append(box("gate_cap", (0.6, 0.6, 0.1), (x, -15.6, TERRACE_TOP + 1.15), COPING, 0.03, coll=coll))
    planters, blooms = [], []
    for x in (-17.5, -13.5, -9.5, -5.5, 5.5, 9.5, 13.5, 17.5): flower_box(x, -15.6, True, planters, blooms)
    for y in (-12.5, -6.5, -0.5, 5.5):
        for x in (-19.6, 19.6): flower_box(x, y, False, planters, blooms)
    # Geraniums against the outside of the kitchen's low side walls, between the dining tables.
    for y in (6.75, 2.65, -1.05, -5.4):
        for x in (-12.48, 12.48): flower_box(x, y, False, planters, blooms, base=TERRACE_TOP, length=1.2)
    for o in planters + blooms:
        for c in list(o.users_collection): c.objects.unlink(o)
        coll.objects.link(o)
    return [join(walls, "parapet", coll), join(planters, "planters", coll), join(blooms, "planter_blooms", coll)]

def table_set(index, x, y, coll, seats, umbrella=False, along_y=False):
    def at(u, v):
        """Local (u along the chairs' axis, v across it) to Blender x, y."""
        return (x + v, y + u) if along_y else (x + u, y + v)
    def size(su, sv):
        return (sv, su) if along_y else (su, sv)
    parts = []
    parts.append(cyl("table_foot", 0.32, 0.06, (x, y, TERRACE_TOP + 0.03), IRON, 20, coll=coll))
    parts.append(cyl("table_stem", 0.05, TABLE_TOP - 0.1, (x, y, TERRACE_TOP + (TABLE_TOP - 0.1) / 2), IRON, 10, coll=coll))
    parts.append(cyl("tablecloth", 0.62, 0.05, (x, y, TERRACE_TOP + TABLE_TOP - 0.025), CLOTH, 28, coll=coll))
    parts.append(cyl("tablecloth_hem", 0.635, 0.14, (x, y, TERRACE_TOP + TABLE_TOP - 0.1), CLOTH_EDGE, 28, r2=0.625, coll=coll))
    vase = cyl("vase", 0.05, 0.14, (x, y, TERRACE_TOP + TABLE_TOP + 0.07), GLASS, 10, coll=coll)
    flower = blob("vase_flower", 0.06, (x, y, TERRACE_TOP + TABLE_TOP + 0.2), rng.choice(GERANIUM), coll=coll)
    parts += [vase, flower]
    for side in (-1, 1):
        cu = side * 0.98
        # A painted Greek-island chair whose back is away from the table.
        parts.append(box("chair_seat", (*size(0.52, 0.5), 0.07), (*at(cu, 0), TERRACE_TOP + SEAT_TOP - 0.035), CHAIR, 0.025, coll=coll))
        for du in (-0.21, 0.21):
            for dv in (-0.2, 0.2):
                parts.append(box("chair_leg", (0.05, 0.05, SEAT_TOP - 0.07), (*at(cu + du, dv), TERRACE_TOP + (SEAT_TOP - 0.07) / 2), CHAIR, 0.01, 1, coll=coll))
        back_u = cu + side * 0.24
        for dv in (-0.2, 0.2):
            parts.append(box("chair_post", (0.05, 0.05, 0.62), (*at(back_u, dv), TERRACE_TOP + SEAT_TOP + 0.31), CHAIR, 0.01, 1, coll=coll))
        for dz in (0.28, 0.5):
            parts.append(box("chair_rail", (*size(0.05, 0.44), 0.07), (*at(back_u, 0), TERRACE_TOP + SEAT_TOP + dz), CHAIR, 0.015, 1, coll=coll))
        # The diner's root stands just in front of the seat; its plate sits on the table before it.
        root = (*at(cu - side * SIT_BACK, 0), TERRACE_TOP)
        dish = (*at(side * 0.3, 0), TERRACE_TOP + TABLE_TOP)
        seats.append((root, dish))
    if umbrella:
        parts.append(cyl("umbrella_pole", 0.03, 2.3, (x, y, TERRACE_TOP + 1.15 + TABLE_TOP / 2), IRON, 8, coll=coll))
        for k in range(8):
            a0 = k * math.pi / 4
            bpy.ops.mesh.primitive_cone_add(vertices=3, radius1=1.35, depth=0.45, location=(x, y, TERRACE_TOP + 2.85))
            panel = bpy.context.active_object; panel.name = "umbrella_panel"
            mesh = panel.data
            bm = bmesh.new(); bm.from_mesh(mesh)
            bmesh.ops.delete(bm, geom=list(bm.verts), context="VERTS")
            top = bm.verts.new((0, 0, 0.3)); a = bm.verts.new((1.35 * math.cos(a0), 1.35 * math.sin(a0), -0.12))
            b = bm.verts.new((1.35 * math.cos(a0 + math.pi / 4), 1.35 * math.sin(a0 + math.pi / 4), -0.12))
            bm.faces.new((top, a, b)); bm.to_mesh(mesh); bm.free()
            finish(panel, CANVAS[k % 2], coll=coll); parts.append(panel)
    return join(parts, f"table_{index:02d}", coll)

def potted_lemon(x, y, coll, big=True):
    s = 1.0 if big else 0.75
    parts = [cyl("tree_pot", 0.38 * s, 0.62 * s, (x, y, TERRACE_TOP + 0.31 * s), POT, 18, r2=0.48 * s, coll=coll),
             cyl("tree_soil", 0.44 * s, 0.04, (x, y, TERRACE_TOP + 0.6 * s), SOIL, 18, coll=coll),
             cyl("tree_trunk", 0.07 * s, 1.0 * s, (x, y, TERRACE_TOP + 1.05 * s), TRUNK, 8, coll=coll)]
    for k in range(5):
        a = k * 2 * math.pi / 5 + rng.uniform(-0.3, 0.3)
        parts.append(blob("tree_leaves", 0.42 * s, (x + 0.32 * s * math.cos(a), y + 0.32 * s * math.sin(a), TERRACE_TOP + (1.6 + rng.uniform(-0.1, 0.15)) * s), rng.choice(LEAF), coll=coll))
    parts.append(blob("tree_crown", 0.5 * s, (x, y, TERRACE_TOP + 1.9 * s), rng.choice(LEAF), coll=coll))
    for k in range(7):
        a = rng.uniform(0, 2 * math.pi)
        parts.append(blob("lemon", 0.075 * s, (x + 0.5 * s * math.cos(a), y + 0.5 * s * math.sin(a), TERRACE_TOP + rng.uniform(1.4, 2.0) * s), LEMON, (1, 1, 1.25), coll=coll))
    return parts

def olive_jar(x, y, coll):
    return [cyl("jar_body", 0.26, 0.6, (x, y, TERRACE_TOP + 0.3), JAR, 16, r2=0.34, coll=coll),
            cyl("jar_neck", 0.2, 0.12, (x, y, TERRACE_TOP + 0.66), JAR, 16, r2=0.14, coll=coll)]

def street_lamp(x, y, coll):
    return [cyl("lamp_base", 0.14, 0.2, (x, y, TERRACE_TOP + 0.1), IRON, 12, coll=coll),
            cyl("lamp_post", 0.045, 2.6, (x, y, TERRACE_TOP + 1.4), IRON, 10, coll=coll),
            box("lamp_glass", (0.26, 0.26, 0.34), (x, y, TERRACE_TOP + 2.85), GLASS, 0.02, coll=coll),
            cyl("lamp_roof", 0.24, 0.16, (x, y, TERRACE_TOP + 3.1), IRON, 4, r2=0.02, coll=coll)]

def fountain(x, y, coll):
    parts = [cyl("fountain_basin", 1.3, 0.5, (x, y, TERRACE_TOP + 0.25), COPING, 32, coll=coll),
             cyl("fountain_water", 1.12, 0.06, (x, y, TERRACE_TOP + 0.45), FOUNTAIN_WATER, 32, coll=coll),
             cyl("fountain_column", 0.16, 1.0, (x, y, TERRACE_TOP + 0.9), WHITEWASH, 12, coll=coll),
             cyl("fountain_bowl", 0.55, 0.16, (x, y, TERRACE_TOP + 1.4), COPING, 24, r2=0.3, coll=coll),
             cyl("fountain_bowl_water", 0.48, 0.03, (x, y, TERRACE_TOP + 1.47), FOUNTAIN_WATER, 24, coll=coll),
             blob("fountain_spout", 0.12, (x, y, TERRACE_TOP + 1.62), FOUNTAIN_WATER, (1, 1, 1.6), coll=coll)]
    return parts

def roof(coll):
    """Barrel-tiled lean-to roof behind the back wall, sloping down toward the kitchen."""
    parts = []
    y0, y1, z0, z1 = 7.95, 12.6, 3.0, 4.7
    length = math.hypot(y1 - y0, z1 - z0); tilt = math.atan2(z1 - z0, y1 - y0)
    parts.append(box("roof_deck", (26.4, length + 0.2, 0.12), (0, (y0 + y1) / 2, (z0 + z1) / 2 - 0.08), TERRACOTTA[1], 0.0, rot=0, coll=coll))
    parts[-1].rotation_euler = (tilt, 0, 0)
    tiles = {m.name: [] for m in TERRACOTTA}
    step = 0.46
    count = int(26.0 / step)
    for i in range(count):
        x = -13.0 + (i + 0.5) * step
        for seg in range(3):
            m = rng.choice(TERRACOTTA)
            seg_len = length / 3
            centre_t = (seg + 0.5) * seg_len
            cy = y0 + math.cos(tilt) * centre_t; cz = z0 + math.sin(tilt) * centre_t + 0.02
            bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=0.22, depth=seg_len + 0.06, location=(x, cy, cz), rotation=(math.pi / 2 - tilt, 0, 0))
            t = bpy.context.active_object; t.name = "roof_tile"
            bm = bmesh.new(); bm.from_mesh(t.data)
            # Keep the upper half (a barrel tile), flattened a little.
            gone = [v for v in bm.verts if v.co.x * 0 + (v.co.y) < -0.02]
            bmesh.ops.delete(bm, geom=gone, context="VERTS"); bm.to_mesh(t.data); bm.free()
            t.scale = (1, 0.75, 1)
            finish(t, m, coll=coll)
            for poly in t.data.polygons: poly.use_smooth = True
            tiles[m.name].append(t)
    out = [join(parts, "roof_deck", coll)] + [join(v, f"roof_tiles_{k}", coll) for k, v in tiles.items()]
    # Ridge, eave board and a chimney.
    extra = [box("roof_ridge", (26.6, 0.5, 0.3), (0, y1, z1 + 0.1), TERRACOTTA[1], 0.08, coll=coll),
             box("eave", (26.6, 0.18, 0.22), (0, y0, z0 - 0.05), WHITEWASH, 0.03, coll=coll),
             box("chimney", (0.9, 0.9, 1.6), (-6.5, 11.2, z1), WHITEWASH, 0.06, coll=coll),
             box("chimney_cap", (1.1, 1.1, 0.14), (-6.5, 11.2, z1 + 0.86), COPING, 0.03, coll=coll),
             box("chimney_pot", (0.32, 0.32, 0.3), (-6.5, 11.2, z1 + 1.06), POT, 0.03, coll=coll)]
    for x in (-10.5, -2.0, 4.5, 10.0):
        extra.append(cyl("eave_pot", 0.2, 0.26, (x, y0 - 0.05, z0 + 0.16), POT, 12, r2=0.26, coll=coll))
        extra.append(blob("eave_plant", 0.22, (x, y0 - 0.05, z0 + 0.38), rng.choice(LEAF), coll=coll))
        extra.append(blob("eave_bloom", 0.08, (x + 0.1, y0 - 0.12, z0 + 0.5), rng.choice(GERANIUM[:2]), coll=coll))
    out.append(join(extra, "roof_details", coll))
    return out

def canal(coll):
    out = []
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, -3, -0.42))
    water = bpy.context.active_object; water.name = "water"; water.scale = (140, 140, 1)
    bpy.ops.object.transform_apply(scale=True)
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.subdivide(number_cuts=12); bpy.ops.object.mode_set(mode="OBJECT")
    finish(water, WATER, coll=coll); out.append(water)
    pads = []
    spots = []
    while len(spots) < 34:
        x, y = rng.uniform(-32, 32), rng.uniform(-26, 18)
        if -20.8 < x < 20.8 and -16.8 < y < 10.8: continue
        if 20.4 < x < 27 and -2.4 < y < 2.6: continue  # the jetty and the moored boat
        if any((x - a) ** 2 + (y - b) ** 2 < 2.2 for a, b in spots): continue
        spots.append((x, y))
    for x, y in spots:
        r = rng.uniform(0.35, 0.65)
        bpy.ops.mesh.primitive_circle_add(vertices=18, radius=r, fill_type="NGON", location=(x, y, -0.39))
        pad = bpy.context.active_object; pad.name = "lily_pad"; pad.rotation_euler.z = rng.uniform(0, 6.28)
        bm = bmesh.new(); bm.from_mesh(pad.data)
        # Notch: drop one rim vertex toward the centre.
        rim = [v for v in bm.verts if v.co.length > r * 0.5]
        rim[0].co *= 0.1
        bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.03); bm.to_mesh(pad.data); bm.free()
        finish(pad, rng.choice(LILY), coll=coll); pads.append(pad)
        if rng.random() < 0.35:
            pads.append(cyl("lily_flower", 0.11, 0.12, (x + 0.1, y + 0.05, -0.32), LILY_FLOWER, 6, r2=0.03, coll=coll))
    out.append(join(pads, "lily_pads", coll))
    # A wooden jetty off the right walkway with a moored rowboat.
    deck = []
    for i in range(10):
        deck.append(box("jetty_plank", (0.56, 2.2, 0.08), (20.6 + i * 0.6, 1.0, -0.02), rng.choice(WOOD), 0.015, 1, coll=coll))
    for x in (20.8, 23.2, 25.6):
        for y in (0.05, 1.95):
            deck.append(cyl("jetty_post", 0.09, 0.9, (x, y, -0.3), WOOD[1], 10, coll=coll))
    out.append(join(deck, "jetty", coll))
    boat = []
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=1, location=(24.0, -0.9, -0.12))
    hull = bpy.context.active_object; hull.name = "boat_hull"; hull.scale = (1.9, 0.68, 0.5)
    bm = bmesh.new(); bm.from_mesh(hull.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z > 0.05], context="VERTS"); bm.to_mesh(hull.data); bm.free()
    bpy.ops.object.transform_apply(scale=True)
    finish(hull, BOAT, coll=coll)
    sol = hull.modifiers.new("solid", "SOLIDIFY"); sol.thickness = 0.06
    boat.append(hull)
    bpy.ops.mesh.primitive_torus_add(major_radius=1.0, minor_radius=0.05, major_segments=32, minor_segments=6, location=(24.0, -0.9, -0.11))
    rim = bpy.context.active_object; rim.name = "boat_rim"; rim.scale = (1.9, 0.68, 1.2)
    bpy.ops.object.transform_apply(scale=True); finish(rim, BOAT_STRIPE)
    inner = cyl("boat_inner", 1.0, 0.04, (24.0, -0.9, -0.36), WOOD[1], 24)
    inner.scale = (1.6, 0.5, 1); bpy.ops.object.transform_apply(scale=True)
    boat += [rim, inner]
    boat.append(box("boat_bench", (0.3, 1.1, 0.07), (23.5, -0.9, -0.05), WOOD[0], 0.01))
    boat.append(box("boat_bench", (0.3, 1.1, 0.07), (24.6, -0.9, -0.05), WOOD[0], 0.01))
    for o in boat[1:]:
        for c in list(o.users_collection): c.objects.unlink(o)
        coll.objects.link(o)
    out.append(join(boat, "rowboat", coll))
    return out

def reference(coll):
    """Stand-ins for the kitchen so reviews show the restaurant in context (not exported)."""
    box("ref_floor", (24, 16, 0.2), (0, 0, 0), mat("ref_floor", hexrgb("9a6a45")), 0, coll=coll)
    box("ref_back_wall", (24, 0.26, 2.9), (0, 7.87, 1.45), mat("ref_wall", hexrgb("efe6d6")), 0, coll=coll)
    for x in (-11.85, 11.85):
        box("ref_side_wall", (0.26, 16, 0.75), (x, 0, 0.375), mat("ref_wall", hexrgb("efe6d6")), 0, coll=coll)
    box("ref_pass", (7.4, 1.2, 0.82), (6.9, -7.0, 0.41), mat("ref_counter", hexrgb("f4f1ea")), 0, coll=coll)
    box("ref_island", (9, 1.2, 0.82), (0, 2.2, 0.41), mat("ref_counter", hexrgb("f4f1ea")), 0, coll=coll)

def camera():
    """The app's home camera: 62 deg elevation, 38 deg vertical FOV, looking at (0, 0.65, 0)."""
    cam = bpy.data.objects.get("ReviewCamera")
    if cam is None:
        cam = bpy.data.objects.new("ReviewCamera", bpy.data.cameras.new("ReviewCamera")); bpy.context.scene.collection.objects.link(cam)
    cam.data.sensor_fit = "VERTICAL"; cam.data.angle_y = math.radians(38); cam.data.clip_end = 300
    d, e = 29.0, math.radians(62)
    cam.location = (0, -d * math.cos(e), d * math.sin(e) + 0.65)
    cam.rotation_euler = (math.pi / 2 - e, 0, 0)
    bpy.context.scene.camera = cam
    sun = bpy.data.objects.get("ReviewSun")
    if sun is None:
        sun = bpy.data.objects.new("ReviewSun", bpy.data.lights.new("ReviewSun", "SUN")); bpy.context.scene.collection.objects.link(sun)
    sun.data.energy = 3.5; sun.rotation_euler = (math.radians(45), math.radians(-20), math.radians(-35))
    world = bpy.context.scene.world or bpy.data.worlds.new("World"); bpy.context.scene.world = world
    world.use_nodes = True; world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.75, 0.85, 1)
    scene = bpy.context.scene; scene.render.resolution_x = 1600; scene.render.resolution_y = 900
    # The app shows authored colours as-is (its loader reads them as sRGB), so review raw.
    scene.view_settings.view_transform = "Raw"

# ---------------------------------------------------------------- build
def build():
    reset()
    coll = collection("Restaurant"); ref = collection("KitchenRef")
    root = empty(ROOT_NAME, (0, 0, 0), coll)
    pieces = []
    pieces += terrace(coll)
    pieces += parapet(coll)
    seats = []
    # Diners sit beside the kitchen, where the home camera sees them: a column of tables on each
    # walkway, chairs front and back so faces show.
    tables = [(sx * 13.6, y) for sx in (1, -1) for y in (4.5, 0.8, -2.9)]
    for i, (x, y) in enumerate(tables):
        pieces.append(table_set(i + 1, x, y, coll, seats, along_y=True))
    # Umbrella tables for show on the front terrace.
    for i, (x, y) in enumerate(((-11.0, -10.8), (-11.0, -13.8), (9.0, -11.5), (13.5, -13.6))):
        pieces.append(table_set(7 + i, x, y, coll, [], umbrella=True))
    decor = []
    decor += fountain(-5.6, -12.2, coll)
    for x, y, big in ((-16.6, 7.4, True), (16.6, 7.4, True), (-16.8, -6.6, True), (16.8, -6.6, True), (-1.2, -9.2, False), (5.0, -14.6, False)):
        decor += potted_lemon(x, y, coll, big)
    for x, y in ((-18.7, -14.7), (18.7, -14.7), (-17.9, -14.9), (18.2, 6.2), (-18.3, 6.0), (18.4, -5.0), (-18.4, -5.2)):
        decor += olive_jar(x, y, coll)
    for x, y in ((-16.9, 2.65), (16.9, 2.65), (-16.9, -1.05), (16.9, -1.05), (-2.9, -15.0), (2.9, -15.0)):
        decor += street_lamp(x, y, coll)
    pieces.append(join(decor, "terrace_decor", coll))
    pieces += roof(coll)
    pieces += canal(coll)
    # Anchors, nearest the serving pass (x 6.9, y -7) first.
    seats.sort(key=lambda s: (s[0][0] - 6.9) ** 2 + (s[0][1] + 7.0) ** 2)
    for i, (seat, dish) in enumerate(seats):
        empty(f"seat_{i + 1:02d}", seat, coll); empty(f"dish_{i + 1:02d}", dish, coll)
    for obj in coll.objects:
        if obj is not root and obj.parent is None: obj.parent = root
    reference(ref)
    camera()
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in coll.objects if o.type == "MESH")
    return {"objects": len(coll.objects), "triangles": tris, "seats": len(seats)}

def export(path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in bpy.data.collections["Restaurant"].objects: o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True, export_materials="EXPORT", export_extras=False)

if __name__ == "__main__" and "--" in sys.argv:
    out = sys.argv[sys.argv.index("--") + 1]
    print("RESTAURANT", build()); export(out); print("RESTAURANT exported", out)
