"""Shared pieces for the kitchen's Blender-built fixtures (the range, the cooking island):
materials, primitives, assembly and export. Units are kitchen world units; Blender -y is the
camera side (SceneKit +z). Colours are the sRGB the app shows (the GLB loader reads
baseColorFactor as sRGB)."""
import bpy, bmesh, math, os
from mathutils import Vector

MATS = {}
def mat(name, hexcode, rough=0.6, metal=0.0):
    if name in MATS: return MATS[name]
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*[int(hexcode[i:i + 2], 16) / 255 for i in (0, 2, 4)], 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    MATS[name] = m
    return m

# ---------------------------------------------------------------- primitives
PARTS = []
def finish(o, material, bevel=0.0, segments=2, smooth=False):
    o.data.materials.clear(); o.data.materials.append(material)
    if bevel > 0:
        m = o.modifiers.new("bevel", "BEVEL"); m.width = bevel; m.segments = segments; m.limit_method = "ANGLE"
    for p in o.data.polygons: p.use_smooth = smooth
    PARTS.append(o)
    return o

def box(size, loc, material, bevel=0.01, segments=2):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object; o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(o, material, bevel, segments)

def cyl(r, h, loc, material, verts=32, rot=(0, 0, 0), bevel=0.0, r2=None):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=loc, rotation=rot)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r2, depth=h, location=loc, rotation=rot)
    o = bpy.context.active_object
    finish(o, material, bevel, 2)
    for p in o.data.polygons: p.use_smooth = len(p.vertices) == 4
    return o

def torus(major, minor, loc, material, rot=(0, 0, 0), seg=40, ring=10):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=seg, minor_segments=ring, location=loc, rotation=rot)
    o = bpy.context.active_object
    return finish(o, material, smooth=True)

def rod(a, b, r, material, verts=16):
    a, b = Vector(a), Vector(b)
    d = b - a
    o = cyl(r, d.length, (a + b) / 2, material, verts)
    o.rotation_mode = "QUATERNION"; o.rotation_quaternion = d.to_track_quat("Z", "Y")
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    for p in o.data.polygons: p.use_smooth = True
    return o

# ---------------------------------------------------------------- marble
def marble_image(name, width, height, metres_x, metres_y, seed=5):
    """Honed Carrara: warm white with soft grey veins drifting diagonally, a few sharper
    hairline veins, faint cloudiness. Sampled in world metres, so veins don't stretch."""
    import numpy as np
    r = np.random.default_rng(seed)
    ys, xs = np.mgrid[0:height, 0:width].astype(np.float32)
    X = xs / width * metres_x; Y = ys / height * metres_y
    def noise(scale, octaves):
        total = np.zeros_like(X); amp = 1.0; norm = 0.0
        for o in range(octaves):
            f = scale * (2 ** o)
            gx, gy = int(metres_x * f) + 3, int(metres_y * f) + 3
            grid = r.random((gy, gx)).astype(np.float32)
            u, v = X * f, Y * f
            i, j = u.astype(int), v.astype(int)
            fu, fv = u - i, v - j
            fu, fv = fu * fu * (3 - 2 * fu), fv * fv * (3 - 2 * fv)
            a = grid[j, i]; b = grid[j, i + 1]; c = grid[j + 1, i]; d = grid[j + 1, i + 1]
            total += amp * ((a * (1 - fu) + b * fu) * (1 - fv) + (c * (1 - fu) + d * fu) * fv)
            norm += amp; amp *= 0.5
        return total / norm
    warp = noise(1.2, 5)
    broad = np.abs(np.sin((X * 1.3 + Y * 2.1 + warp * 4.0) * 2.2))
    veins = np.clip(1 - broad / 0.18, 0, 1) ** 1.6
    fine = np.abs(np.sin((X * 3.1 - Y * 1.7 + noise(2.5, 4) * 3.0) * 4.5))
    hair = np.clip(1 - fine / 0.14, 0, 1) ** 2.5 * 0.3       # wide enough not to break into dots
    cloud = noise(0.8, 4)
    base = np.array([0.945, 0.935, 0.905], np.float32)
    vein = np.array([0.60, 0.61, 0.63], np.float32)
    v = np.clip(veins * 0.65 + hair, 0, 1)[..., None]
    col = base * (0.97 + 0.05 * cloud[..., None]) * (1 - v) + vein * v
    img = bpy.data.images.new(name, width, height, alpha=False)
    rgba = np.concatenate([col, np.ones((height, width, 1), np.float32)], axis=2)
    img.pixels.foreach_set(rgba.ravel())
    img.file_format = "JPEG"
    img.pack()
    return img

def marble_material(name, width, depth, seed=5):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    # About 224 px per metre (the island's density), at most 2048 px on a side.
    px = lambda metres: max(64, min(2048, int(224 * metres) // 16 * 16))
    tex.image = marble_image(name, px(width + 0.2), px(depth + 0.2), width + 0.2, depth + 0.2, seed)
    nt.links.new(tex.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.42
    return m

def marble_slab(width, depth, thickness, loc, name="carrara", seed=5):
    """A Carrara slab with a softly rounded edge; UVs projected from above, in metres."""
    MARBLE = marble_material(name, width, depth, seed)
    o = box((width, depth, thickness), loc, MARBLE, 0.022, 4)
    bpy.context.view_layer.objects.active = o
    for m in list(o.modifiers): bpy.ops.object.modifier_apply(modifier=m.name)
    me = o.data
    uv = me.uv_layers.new(name="UVMap") if not me.uv_layers else me.uv_layers[0]
    for loop in me.loops:
        co = me.vertices[loop.vertex_index].co
        uv.data[loop.index].uv = ((co.x - loc[0] + width / 2 + 0.1) / (width + 0.2), (co.y - loc[1] + depth / 2 + 0.1) / (depth + 0.2))
    return MARBLE

# ---------------------------------------------------------------- assembly and export
def strip_unseen(objects):
    """The kitchen camera looks down at 62°: faces turned well below horizontal are never seen."""
    n = 0
    for ob in objects:
        bm = bmesh.new(); bm.from_mesh(ob.data)
        mw = ob.matrix_world.to_3x3()
        hidden = [f for f in bm.faces if (mw @ f.normal).normalized().z < -0.6 and all(len(e.link_faces) == 2 for e in f.edges)]
        bmesh.ops.delete(bm, geom=hidden, context="FACES"); bm.to_mesh(ob.data); bm.free(); n += len(hidden)
    return n


def assemble(root_name, anchors, keep_uvs=()):
    """Applies modifiers, joins the parts into one mesh per material (few draw calls), drops
    faces the camera never sees and texture coordinates nothing uses, and parents it all and
    the anchor empties under one root."""
    for o in PARTS:
        bpy.context.view_layer.objects.active = o
        for m in list(o.modifiers): bpy.ops.object.modifier_apply(modifier=m.name)
        if o.data.materials[0].name not in keep_uvs:
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
        # Bake the joined mesh's frame (it inherits the first part's, which may be tilted), so
        # its bounds in the app are the parts' own.
        bpy.ops.object.select_all(action="DESELECT"); out.select_set(True)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    removed = strip_unseen(merged)
    root = bpy.data.objects.new(root_name, None); bpy.context.scene.collection.objects.link(root)
    for o in merged + list(anchors): o.parent = root
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in merged)
    return root, merged, {"meshes": len(merged), "triangles": tris, "hidden_faces_removed": removed}

def anchor(name, loc):
    e = bpy.data.objects.new(name, None); e.location = loc; e.empty_display_size = 0.15
    bpy.context.scene.collection.objects.link(e)
    return e

def export(path, root, meshes):
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for c in root.children: c.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True, export_materials="EXPORT", export_extras=False,
                              export_image_format="JPEG", export_image_quality=85)

def review(out_dir, views):
    """Renders `views`: (name, eye, look-at, resolution)."""
    os.makedirs(out_dir, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w"); scene.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.42, 0.33, 0.25, 1)
    floor = bpy.data.meshes.new("floor"); fo = bpy.data.objects.new("floor", floor); scene.collection.objects.link(fo)
    bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=8); bm.to_mesh(floor); bm.free()
    floor.materials.append(mat("floor", "6b4a2f", 0.8))
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(40), 0, math.radians(-35)); sun.data.energy = 3.5
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); scene.collection.objects.link(cam); scene.camera = cam
    cam.data.lens = 50
    for name, eye, look, res in views:
        cam.location = eye
        cam.rotation_euler = (Vector(look) - Vector(eye)).to_track_quat("-Z", "Y").to_euler()
        scene.render.resolution_x, scene.render.resolution_y = res
        scene.render.filepath = os.path.join(out_dir, name + ".png")
        bpy.ops.render.render(write_still=True)

