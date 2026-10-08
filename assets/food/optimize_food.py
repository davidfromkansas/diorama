"""Make a lightweight, normalized copy of a food model for the kitchen.

Usage: Blender -b --factory-startup -P optimize_food.py -- SRC.glb OUT.glb FACES TEXTURE
- joins meshes and applies transforms
- decimates to at most FACES triangles
- resizes textures so their longest side is at most TEXTURE pixels
- centres the dish in X/Y (Blender ground plane), puts its base at Z = 0 and scales it uniformly
  so its largest horizontal extent is 1.0 (proportions preserved); the app sizes dishes from that
"""
import sys
import bpy
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
src, out, faces, texture = argv[0], argv[1], int(argv[2]), int(argv[3])

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
assert meshes, "no mesh in " + src
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
if len(meshes) > 1:
    bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
for o in list(bpy.context.scene.objects):
    if o != ob:
        bpy.data.objects.remove(o)

before = len(ob.data.vertices)
triangles = sum(len(p.vertices) - 2 for p in ob.data.polygons)
if triangles > faces:
    mod = ob.modifiers.new("decimate", "DECIMATE")
    mod.ratio = faces / triangles
    mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=mod.name)

points = [ob.matrix_world @ v.co for v in ob.data.vertices]
low = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
high = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
scale = 1.0 / max(high.x - low.x, high.y - low.y)
centre = Vector(((low.x + high.x) / 2, (low.y + high.y) / 2, low.z))
ob.data.transform(Matrix.Scale(scale, 4) @ Matrix.Translation(-centre))
ob.matrix_world = Matrix.Identity(4)

for image in bpy.data.images:
    w, h = image.size
    if max(w, h) > texture:
        k = texture / max(w, h)
        image.scale(max(1, int(w * k)), max(1, int(h * k)))

bpy.ops.object.select_all(action="DESELECT")
ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True,
                          export_apply=True, export_texcoords=True, export_normals=True,
                          export_image_format="JPEG", export_jpeg_quality=85, export_animations=False)
print(f"FOOD {src} -> {out}: {before} -> {len(ob.data.vertices)} vertices")
