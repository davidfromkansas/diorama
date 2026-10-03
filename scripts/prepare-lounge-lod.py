#!/usr/bin/env python3
"""Blender: create shared lower-detail CAD lounge meshes; preserve materials.
blender -b --python scripts/prepare-lounge-lod.py -- ASSET_DIRECTORY
"""
import bpy,sys,json
from pathlib import Path
root=Path(sys.argv[sys.argv.index('--')+1])
for name,budget in [('EamesLounge',4000),('LuvaCorner',12000)]:
 bpy.ops.wm.read_factory_settings(use_empty=True)
 bpy.ops.wm.obj_import(filepath=str(root/(name+'.obj')),forward_axis='NEGATIVE_Z',up_axis='Y')
 meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']; total=sum(len(o.data.polygons) for o in meshes)
 for obj in meshes:
  bpy.context.view_layer.objects.active=obj
  modifier=obj.modifiers.new('Office detail','DECIMATE');modifier.ratio=min(1,budget/total)
  bpy.ops.object.modifier_apply(modifier=modifier.name)
  for poly in obj.data.polygons:poly.use_smooth=True
 bpy.ops.wm.obj_export(filepath=str(root/(name+'Low.obj')),forward_axis='NEGATIVE_Z',up_axis='Y',export_materials=True,export_triangulated_mesh=True)
 print(name,'polygons',sum(len(o.data.polygons) for o in meshes))
# Runtime layout consumes dimensions of the authored meshes, not arbitrary placement guesses.
cad=json.loads((root/'LoungeCAD.json').read_text())
vertices=[list(map(float,line.split()[1:])) for line in (root/'LoungeTV.obj').read_text().splitlines() if line.startswith('v ')]
dimensions={k:v['dimensions'] for k,v in cad.items()};dimensions['LoungeTV']=[max(v[i] for v in vertices)-min(v[i] for v in vertices) for i in range(3)]
(root/'LoungeDimensions.json').write_text(json.dumps(dimensions,indent=2)+'\n')
