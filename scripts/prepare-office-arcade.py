#!/usr/bin/env python3
"""Blender: prepare a user-supplied leisure GLB as a static Y-up office asset.
blender -b --python scripts/prepare-office-arcade.py -- INPUT.glb OUTPUT_DIRECTORY [NAME] [TRIANGLES] [height|width] [METRES]
"""
import bpy, sys, json, struct, hashlib
from pathlib import Path
args = sys.argv[sys.argv.index('--') + 1:]
source, destination = map(Path, args[:2])
asset_name = args[2] if len(args) > 2 else 'Starcade'
triangle_budget = int(args[3]) if len(args) > 3 else 24000
size_axis = args[4] if len(args) > 4 else 'height'
assert size_axis in ('height','width')
target_metres = float(args[5]) if len(args) > 5 else 1.9
destination.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(source))
obj = next(o for o in bpy.context.scene.objects if o.type == 'MESH')
bpy.context.view_layer.objects.active = obj
modifier = obj.modifiers.new('Office silhouette', 'DECIMATE')
modifier.ratio = min(1, triangle_budget / len(obj.data.polygons))
bpy.ops.object.modifier_apply(modifier=modifier.name)
mesh = obj.data
mesh.calc_loop_triangles()
points = [obj.matrix_world @ v.co for v in mesh.vertices]
min_z = min(v.z for v in points)
center_x = (min(v.x for v in points) + max(v.x for v in points)) / 2
center_y = (min(v.y for v in points) + max(v.y for v in points)) / 2
scale = target_metres / ((max(v.x for v in points)-min(v.x for v in points)) if size_axis=='width' else (max(v.z for v in points)-min_z))
lines = [f'# {asset_name}: {target_metres} m {size_axis}; Y-up; controls face +Z.']
for v in points: lines.append(f'v {(v.x-center_x)*scale:.7f} {(v.z-min_z)*scale:.7f} {-(v.y-center_y)*scale:.7f}')
for loop in mesh.loops:
 uv = mesh.uv_layers.active.data[loop.index].uv
 lines.append(f'vt {uv.x:.7f} {uv.y:.7f}')
for v in mesh.vertices:
 n = v.normal
 lines.append(f'vn {n.x:.7f} {n.z:.7f} {-n.y:.7f}')
for tri in mesh.loop_triangles:
 lines.append('f ' + ' '.join(f'{mesh.loops[i].vertex_index+1}/{i+1}/{mesh.loops[i].vertex_index+1}' for i in tri.loops))
(destination / f'{asset_name}.obj').write_text('\n'.join(lines)+'\n')
raw = source.read_bytes(); size = struct.unpack_from('<I',raw,12)[0]; doc = json.loads(raw[20:20+size]); binary = raw[28+size:]
for name,image in zip(['Color','MetalRough','Normal'], doc['images']):
 view = doc['bufferViews'][image['bufferView']]; offset = view.get('byteOffset',0)
 (destination / f'{asset_name}{name}.jpg').write_bytes(binary[offset:offset+view['byteLength']])
(destination / f'{asset_name}.json').write_text(json.dumps({'source':source.name,'sha256':hashlib.sha256(raw).hexdigest(),'triangles':len(mesh.loop_triangles),size_axis+'Metres':target_metres,'front':'+Z'},indent=2)+'\n')
print('Prepared triangles:',len(mesh.loop_triangles))
