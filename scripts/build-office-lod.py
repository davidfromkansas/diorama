"""Run with Blender --background --python scripts/build-office-lod.py from repository root."""
import bpy
from pathlib import Path
root=Path.cwd(); dest=root/'Sources/DioramaApp/Resources/OfficeFurniture'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(root/'Sources/DioramaApp/Resources/Capybara/Capybara.glb'))
mesh=bpy.data.objects['Capybara_Surface']; rig=bpy.data.objects['Capybara_Rig']
rig.data.pose_position='REST'
bpy.context.view_layer.objects.active=mesh
modifier=mesh.modifiers.new('Office distant detail','DECIMATE');modifier.ratio=.16
bpy.ops.object.modifier_apply(modifier=modifier.name)
rig.data.pose_position='POSE'
bpy.ops.object.select_all(action='DESELECT');mesh.select_set(True);rig.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(dest/'CapybaraOfficeLow.glb'),export_format='GLB',use_selection=True,export_animation_mode='ACTIONS',export_animations=True,export_skins=True,export_force_sampling=True)
print('LOW AVATAR VERTICES',len(mesh.data.vertices))
for name in ['AeronESD','NeviC']:
 bpy.ops.wm.read_factory_settings(use_empty=True)
 bpy.ops.wm.obj_import(filepath=str(dest/(name+'.obj')))
 for ob in list(bpy.context.scene.objects):
  if ob.type!='MESH' or len(ob.data.polygons) < 24:continue
  bpy.context.view_layer.objects.active=ob
  mod=ob.modifiers.new('Office distant detail','DECIMATE');mod.ratio=.15
  bpy.ops.object.modifier_apply(modifier=mod.name)
 bpy.ops.wm.obj_export(filepath=str(dest/(name+'Low.obj')),export_materials=True,forward_axis='NEGATIVE_Z',up_axis='Y')

 # Explicit material per object also preserves CAD groups in ModelIO.
 path=dest/(name+'Low.obj')
 lines=[]
 for line in path.read_text().splitlines():
  lines.append(line)
  if line.startswith('o '):lines.append('usemtl '+line[2:])
 path.write_text('\n'.join(lines)+'\n')
