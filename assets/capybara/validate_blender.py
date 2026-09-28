"""Validate the authored rig and render deformation/expression evidence.
Run Blender -b assets/capybara/capybara.blend --python assets/capybara/validate_blender.py.
"""
import bpy,json,math
from pathlib import Path
from mathutils import Vector,Quaternion
OUT=Path(__file__).resolve().parent;S=bpy.context.scene;rig=bpy.data.objects['Capybara_Rig'];face=bpy.data.objects['Capybara_Face'];cam=S.camera
for tr in rig.animation_data.nla_tracks:tr.mute=True
keys=face.data.shape_keys.key_blocks
for k in keys:k.value=0
meshes=[o for o in bpy.data.objects if o.type=='MESH' and o.parent==rig]
manifest=json.loads((OUT/'manifest.json').read_text())
report={'skin':{},'clips':{},'morphs':{},'limits':[]}
for o in meshes:
    bad=[]
    for v in o.data.vertices:
        total=sum(g.weight for g in v.groups)
        if abs(total-1)>1e-5 or len([g for g in v.groups if g.weight>1e-5])>4:bad.append(v.index)
    report['skin'][o.name]={'vertices':len(o.data.vertices),'invalid_weights':len(bad)}
    assert not bad,(o.name,bad[:10])

def use_clip(name,t):
    rig.animation_data.action=bpy.data.actions[name]
    # In Blender 5 actions have slots; restore the compatible rig slot explicitly.
    rig.animation_data.action_slot=bpy.data.actions[name].slots[0]
    S.frame_set(1+round(t*30));bpy.context.view_layer.update()

def bounds():
    dg=bpy.context.evaluated_depsgraph_get();pts=[]
    for o in meshes:
        e=o.evaluated_get(dg);me=e.to_mesh();pts.extend([e.matrix_world@v.co for v in me.vertices]);e.to_mesh_clear()
    return [min(v[k] for v in pts) for k in range(3)],[max(v[k] for v in pts) for k in range(3)]

def matrices():return {p.name:[v for row in p.matrix for v in row] for p in rig.pose.bones}
for clip in manifest['clips']:
    n=clip['name'];d=clip['duration'];use_clip(n,0);start=matrices();use_clip(n,d);end=matrices()
    gap=max(abs(a-b) for name in start for a,b in zip(start[name],end[name]))
    mins=[];hands=[]
    for t in [0,d*.25,d*.5,d*.75,d]:
        use_clip(n,t);lo,hi=bounds();mins.append(lo[2]);hands.append({side:list(rig.matrix_world@rig.pose.bones['hand.'+side].tail) for side in ['L','R']})
    report['clips'][n]={'loop_endpoint_matrix_delta':gap,'minimum_sampled_ground_z':min(mins),'hand_positions':hands}
    if clip['loop']:assert gap<1e-5,(n,gap)
    if min(mins)<-.015:report['limits'].append(f'{n}: ground penetration {min(mins):.4f} m')
# Match a fixed orthographic camera for all pose renders.
S.render.resolution_x=560;S.render.resolution_y=560;S.cycles.samples=24
cam.data.ortho_scale=1.25;cam.location=(1.8,-3,1.35);cam.rotation_euler=(Vector((0,0,.5))-cam.location).to_track_quat('-Z','Y').to_euler()
for n,t in [('idle',0),('walk',.3),('run',.2),('sit_idle',0),('wave',1.2),('type_at_computer',.5),('think',1),('pick_up_object',1),('carry_object',.3),('jump',.65),('celebrate',1.3),('sleep',0)]:
    use_clip(n,t);S.render.filepath=str(OUT/'renders'/f'pose_{n}.png');bpy.ops.render.render(write_still=True)
use_clip('idle',0)
for name in manifest['morphs']:
    for k in keys:k.value=0
    keys[name].value=1
    delta=max((a.co-b.co).length for a,b in zip(keys[name].data,keys['Basis'].data))
    report['morphs'][name]={'max_vertex_delta':delta}
    if name!='neutral':assert delta>1e-4,(name,delta)
    cam.location=(.7,-3,.92);target=Vector((0,-.04,.81));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=.51
    S.render.filepath=str(OUT/'renders'/f'face_{name}.png');bpy.ops.render.render(write_still=True)
(OUT/'validation_blender.json').write_text(json.dumps(report,indent=2)+'\n');print('VALIDATION',json.dumps(report['limits']))
