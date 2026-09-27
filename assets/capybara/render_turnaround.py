"""Render true cardinal orthographic views from the saved Blender source."""
import bpy
from pathlib import Path
from mathutils import Vector,Quaternion

def render_turnaround(scene,out,preview=False):
    rig=bpy.data.objects['Capybara_Rig'];rig.animation_data.action=None
    for track in rig.animation_data.nla_tracks:track.mute=True
    scene.frame_set(1)
    for bone in rig.pose.bones:bone.rotation_quaternion=Quaternion();bone.location=(0,0,0);bone.scale=(1,1,1)
    for key in bpy.data.objects['Capybara_Face'].data.shape_keys.key_blocks:key.value=0
    bpy.context.view_layer.update();cam=scene.camera;cam.data.type='ORTHO';cam.data.ortho_scale=1.20
    scene.render.resolution_x=scene.render.resolution_y=700;scene.render.resolution_percentage=100
    views={'front':(0,-3,.5),'back':(0,3,.5),'left':(3,0,.5),'right':(-3,0,.5),'front_three_quarter':(2,-3,1.25),'rear_three_quarter':(-2,3,1.25)}
    if preview:views={k:v for k,v in views.items() if k in ['front','front_three_quarter']}
    for name,pos in views.items():
        cam.location=pos;cam.rotation_euler=(Vector((0,0,.5))-cam.location).to_track_quat('-Z','Y').to_euler();scene.render.filepath=str(out/'renders'/f'{name}.png');bpy.ops.render.render(write_still=True)
if __name__=='__main__':render_turnaround(bpy.context.scene,Path(__file__).resolve().parent)
