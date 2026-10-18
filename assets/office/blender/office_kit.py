"""Shared pieces for the office's Blender-built fixtures, lobby and props: the kitchen's kit
(materials, primitives, export) plus the office palette, glowing materials, plants, and an
assembly that keeps the parts the app animates as separate, named objects.

Units are scene world units; Blender -y is the camera side (SceneKit +z). Colours are the sRGB the
app shows (its GLB loader reads baseColorFactor as sRGB, and emissiveFactor for lit parts)."""
import bpy, bmesh, math, os, sys
from mathutils import Vector
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "kitchen", "blender"))
from kitchen_kit import mat, finish, box, cyl, torus, rod, strip_unseen, anchor, export, review, PARTS  # noqa: F401

# The chef's worktop above a station's root (ChefMetrics.worktopHeight - floorTop).
TOP = 1.4 * 0.585 - 0.112

OAK = mat("oak", "d6b385", 0.55)
OAK_EDGE = mat("oak_edge", "b8916a", 0.6)
WHITE = mat("white", "f2f0e8", 0.7)
PLASTER = mat("plaster", "ede5d9", 0.85)
BLACK = mat("black", "212124", 0.5)
GRAPHITE = mat("graphite", "3d4047", 0.45)
ALUMINIUM = mat("aluminium", "c7c9cc", 0.3, 0.75)
BRASS = mat("office_brass", "d4a352", 0.28, 0.8)
CORK = mat("cork", "c29466", 0.95)
PAPER = mat("paper", "fcfaf2", 0.9)
LEAF = mat("leaf", "599451", 0.8)
LEAF_LIGHT = mat("leaf_light", "80b36b", 0.8)
TERRACOTTA = mat("terracotta", "cc805c", 0.85)
SOIL = mat("soil", "45332a", 0.95)
SAGE, PEACH, LILAC, SKY = mat("sage", "9ec4a8", 0.6), mat("peach", "f2b899", 0.6), mat("lilac", "bdadde", 0.6), mat("sky", "9ec4e8", 0.6)
BUTTER, CORAL, MINT = mat("butter", "f5d98c", 0.6), mat("coral", "ed948c", 0.6), mat("mint", "99d6cc", 0.6)
PASTELS = [SKY, CORAL, MINT, BUTTER, LILAC, PEACH, SAGE]

def glow(name, hexcode, strength=1.0):
    """A lit-from-within material (screens, status lights)."""
    m = mat(name, hexcode, 0.4)
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Emission Color"].default_value = (*[int(hexcode[i:i + 2], 16) / 255 for i in (0, 2, 4)], 1)
    b.inputs["Emission Strength"].default_value = strength
    return m

def sphere(r, loc, material, segments=16, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=segments, ring_count=max(6, segments // 2), location=loc)
    o = bpy.context.active_object; o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(o, material, smooth=True)

def blob(r, loc, material, seed=0, scale=(1, 1, 1)):
    """A soft leafy lump: an icosphere nudged out of round."""
    import random
    rng = random.Random(seed)
    bpy.ops.mesh.primitive_ico_sphere_add(radius=r, subdivisions=2, location=loc)
    o = bpy.context.active_object
    for v in o.data.vertices: v.co *= 1 + rng.uniform(-0.12, 0.12)
    o.scale = scale; bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(o, material, smooth=True)

def plant(x, y, z, height=1.2, pot=WHITE, seed=0):
    """A potted plant about `height` tall standing at (x, y, z)."""
    ph, r = height * 0.32, height * 0.17
    cyl(r, ph, (x, y, z + ph / 2), pot, 24, r2=r * 0.78, bevel=0.01)
    cyl(r * 0.9, 0.02, (x, y, z + ph - 0.01), SOIL, 20)
    for i in range(6):
        a = (i + seed) * 2.4; spread = 0 if i == 0 else r * 0.8
        size = height * (0.25 if i == 0 else 0.17)
        blob(size, (x + math.cos(a) * spread, y + math.sin(a) * spread, z + ph + height * (0.44 if i == 0 else 0.26 + 0.1 * (i % 2))),
             LEAF if (i + seed) % 2 else LEAF_LIGHT, seed * 7 + i)

KEEP = []
def keep(o, name, pivot=None):
    """Keeps a part the app animates out of the merge, named, with its origin at `pivot`."""
    o.name = name
    if o in PARTS: PARTS.remove(o)
    KEEP.append((o, pivot))
    return o

def join(objects, name):
    """Joins parts into one object (for a kept, animated group)."""
    for o in objects:
        if o in PARTS: PARTS.remove(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        bpy.context.view_layer.objects.active = o
        for m in list(o.modifiers): bpy.ops.object.modifier_apply(modifier=m.name)
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    out = bpy.context.active_object; out.name = name
    return out

def assemble(root_name, anchors=()):
    """The kitchen's assembly (one mesh per material, unseen faces dropped), plus the kept parts:
    each its own object, named, its transform baked about its pivot. Texture coordinates stay only
    on textured materials (the skyline's facades)."""
    def textured(o):
        m = o.data.materials[0]
        return m.use_nodes and any(n.type == "TEX_IMAGE" for n in m.node_tree.nodes)
    for o in PARTS:
        bpy.context.view_layer.objects.active = o
        for m in list(o.modifiers): bpy.ops.object.modifier_apply(modifier=m.name)
        if not textured(o):
            while o.data.uv_layers: o.data.uv_layers.remove(o.data.uv_layers[0])
    by_mat = {}
    for o in PARTS: by_mat.setdefault(o.data.materials[0].name, []).append(o)
    merged = []
    for name, objs in by_mat.items():
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs: o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        if len(objs) > 1: bpy.ops.object.join()
        out = bpy.context.active_object; out.name = root_name + "_" + name; merged.append(out)
        bpy.ops.object.select_all(action="DESELECT"); out.select_set(True)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    removed = strip_unseen(merged)
    kept = []
    for o, pivot in KEEP:
        bpy.context.view_layer.objects.active = o
        for m in list(o.modifiers): bpy.ops.object.modifier_apply(modifier=m.name)
        while o.data.uv_layers: o.data.uv_layers.remove(o.data.uv_layers[0])
        bpy.ops.object.select_all(action="DESELECT"); o.select_set(True)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        bpy.context.scene.cursor.location = pivot or o.data.vertices[0].co * 0 + Vector(o.bound_box[0]).lerp(Vector(o.bound_box[6]), 0.5)
        bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
        kept.append(o)
    root = bpy.data.objects.new(root_name, None); bpy.context.scene.collection.objects.link(root)
    for o in merged + kept + list(anchors): o.parent = root
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in merged + kept)
    return root, merged + kept, {"meshes": len(merged) + len(kept), "triangles": tris, "hidden_faces_removed": removed}
