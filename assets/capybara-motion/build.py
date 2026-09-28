"""Rig the supplied mesh without remeshing; bake contact-based P0 locomotion."""
import bpy, math, json, hashlib
from pathlib import Path
from mathutils import Vector, Matrix, Quaternion
D=Path(__file__).resolve().parent
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.import_scene.gltf(filepath=str(D/'source.glb'))
mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH');mesh.name='Capybara_Surface'
lo=min(v.co.z for v in mesh.data.vertices);height=max(v.co.z for v in mesh.data.vertices)-lo
for v in mesh.data.vertices:v.co=(v.co-Vector((0,0,lo)))/height
bpy.ops.object.armature_add();rig=bpy.context.object;rig.name='Capybara_Rig'
bpy.ops.object.mode_set(mode='EDIT');rig.data.edit_bones.remove(rig.data.edit_bones[0])
def bone(n,h,t,p=None):
 b=rig.data.edit_bones.new(n);b.head=h;b.tail=t
 if p:b.parent=rig.data.edit_bones[p]
bone('root',(0,0,0),(0,0,.1));bone('pelvis',(0,0,.31),(0,0,.40),'root');bone('spine',(0,0,.40),(0,0,.51),'pelvis');bone('chest',(0,0,.51),(0,0,.60),'spine');bone('neck',(0,0,.60),(0,0,.65),'chest');bone('head',(0,0,.65),(0,-.025,.89),'neck')
for s,sign in [('L',1),('R',-1)]:
 def B(n,h,t,p):bone(n+'.'+s,(h[0]*sign,*h[1:]),(t[0]*sign,*t[1:]),p if p in ['head','chest','pelvis'] else p+'.'+s)
 B('ear',(.14,.015,.91),(.16,.015,.985),'head')
 B('shoulder',(.045,0,.59),(.145,0,.59),'chest');B('upper_arm',(.145,0,.59),(.225,-.008,.575),'shoulder');B('lower_arm',(.225,-.008,.575),(.285,-.02,.56),'upper_arm');B('hand',(.285,-.02,.56),(.31,-.022,.555),'lower_arm')
 B('upper_leg',(.09,.015,.305),(.102,.005,.17),'pelvis');B('lower_leg',(.102,.005,.17),(.105,-.005,.045),'upper_leg');B('foot',(.105,-.005,.045),(.105,-.085,.035),'lower_leg');B('toe',(.105,-.085,.035),(.105,-.115,.03),'foot')
bone('tail',(0,.12,.33),(0,.17,.32),'pelvis')
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.select_all(action='DESELECT');mesh.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.object.parent_set(type='ARMATURE_NAME')
# The source is a dense reconstructed surface: bone heat cannot solve it reliably.
# Anatomy masks avoid leaking arm influence into the belly or face islands.
def smooth(a,b,x):
 t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)
def chain(x,knots):
 if x<=knots[0][0]:return {knots[0][1]:1}
 for (a,n),(b,m) in zip(knots,knots[1:]):
  if x<=b:
   t=smooth(a,b,x);return {n:1-t,m:t}
 return {knots[-1][1]:1}
for v in mesh.data.vertices:
 x,y,z=v.co;s='L' if x>=0 else 'R';x=abs(x)
 torso=chain(z,[(.36,'pelvis'),(.46,'spine'),(.55,'chest'),(.61,'neck'),(.67,'head')])
 arm=smooth(.12,.19,x)*smooth(.48,.54,z)*(1-smooth(.62,.67,z))
 legs=(1-smooth(.23,.35,z))*(1-smooth(.14,.22,z)*(1-smooth(.025,.085,x)))
 limb=chain(z,[(.065,'foot.'+s),(.12,'lower_leg.'+s),(.225,'upper_leg.'+s)])
 aw=chain(x,[(.155,'upper_arm.'+s),(.23,'lower_arm.'+s),(.29,'hand.'+s)])
 weights={}
 for mapping,factor in [(torso,(1-arm)*(1-legs)),(aw,arm),(limb,legs*(1-arm))]:
  for n,w in mapping.items():weights[n]=weights.get(n,0)+w*factor
 ear=smooth(.9,.955,z)*smooth(.085,.13,x)
 if ear:
  weights={n:w*(1-ear) for n,w in weights.items()};weights['ear.'+s]=ear
 weights=sorted([(n,w) for n,w in weights.items() if w>1e-6],key=lambda a:-a[1])[:4]
 total=sum(w for _,w in weights)
 for n,w in weights:mesh.vertex_groups[n].add([v.index],w/total,'REPLACE')
for p in rig.pose.bones:p.rotation_mode='QUATERNION'
rest={b.name:b.matrix_local.copy() for b in rig.data.bones}
def rotate(n,axis,angle):
 r=rest[n].to_quaternion();rig.pose.bones[n].rotation_quaternion=r.inverted()@Quaternion(axis,angle)@r

def aim(n,start,end):
 b=rig.data.bones[n];q=(b.tail_local-b.head_local).rotation_difference(end-start)
 rig.pose.bones[n].matrix=Matrix.Translation(start)@q.to_matrix().to_4x4()@rest[n].to_3x3().to_4x4()
 bpy.context.view_layer.update()

def leg(s,target):
 u=rig.pose.bones['upper_leg.'+s];hip=u.head.copy();b=rig.data.bones['upper_leg.'+s];a=b.length;bb=rig.data.bones['lower_leg.'+s].length
 d=target-hip;dist=min(d.length,a+bb-.0001);direction=d.normalized();along=(a*a-bb*bb+dist*dist)/(2*dist)
 pole=Vector((0,-1,0));pole=(pole-direction*pole.dot(direction)).normalized()
 knee=hip+direction*along+pole*math.sqrt(max(0,a*a-along*along))
 aim('upper_leg.'+s,hip,knee);aim('lower_leg.'+s,knee,target)
 rig.pose.bones['foot.'+s].matrix=Matrix.Translation(target)@rest['foot.'+s].to_3x3().to_4x4();bpy.context.view_layer.update()

def pose(name,t,duration):
 for p in rig.pose.bones:p.matrix_basis=Matrix.Identity(4)
 moving=name!='idle';run=name=='run';phase=t/duration;w=math.tau*phase
 bob=(.013 if run else .003)*(1-math.cos(2*w)) if moving else .0015*math.sin(w)
 rig.pose.bones['root'].location.z=-.013+bob
 rotate('spine',(0,1,0),(.018 if moving else .007)*math.sin(w));rotate('chest',(0,0,1),.025*math.sin(w) if moving else 0)
 rotate('head',(0,1,0),-.012*math.sin(w));rotate('neck',(1,0,0),.035 if run else 0)
 for s,sign in [('L',1),('R',-1)]:
  swing=(.40 if run else .20)*math.cos(w)*sign if moving else .015*math.sin(w)
  r=rest['upper_arm.'+s].to_quaternion();rig.pose.bones['upper_arm.'+s].rotation_quaternion=r.inverted()@Quaternion((1,0,0),swing)@Quaternion((0,1,0),sign*1.05)@r
  rotate('lower_arm.'+s,(1,0,0),-.18 if run else -.06)
  rotate('ear.'+s,(0,1,0),sign*.012*math.sin(w+.6));
 bpy.context.view_layer.update()
 for s,sign in [('L',1),('R',-1)]:
  p=(phase+(0 if sign==1 else .5))%1;stance=.42 if run else .62;stride=.19 if run else .115
  if not moving:y=-.005;z=.045
  elif p<stance:y=-.005-stride/2+stride*p/stance;z=.045
  else:
   f=(p-stance)/(1-stance);smooth=f*f*(3-2*f);y=-.005+stride/2-stride*smooth;z=.045+(.065 if run else .038)*math.sin(math.pi*f)
  leg(s,Vector((sign*.105,y,z)))

clips=[]
for name,duration in [('idle',4),('walk',1.2),('run',.7)]:
 action=bpy.data.actions.new(name);rig.animation_data_create();rig.animation_data.action=action
 frames=round(duration*30)
 for f in range(frames+1):
  bpy.context.scene.frame_set(f+1);pose(name,f/30,duration)
  for p in rig.pose.bones:
   p.keyframe_insert('location',frame=f+1);p.keyframe_insert('rotation_quaternion',frame=f+1);p.keyframe_insert('scale',frame=f+1)
 rig.animation_data.action=None;track=rig.animation_data.nla_tracks.new();track.name=name;track.strips.new(name,1,action);track.mute=True
 clips.append({'name':name,'duration':duration,'loop':True,'nominalSpeed':0 if name=='idle' else (.115/(1.2*.62) if name=='walk' else .19/(.7*.42))})
s=bpy.context.scene;s.render.fps=30;s.frame_start=1;s.frame_end=121
rig.animation_data.action=bpy.data.actions['idle'];s.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(D/'capybara-rigged.blend'))
bpy.ops.object.select_all(action='DESELECT');mesh.select_set(True);rig.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(D/'capybara-animated.glb'),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_frame_range=False,export_force_sampling=True,export_def_bones=True,export_skins=True,export_morph=False,export_yup=True)
manifest={'sourceSHA256':hashlib.sha256((D/'source.glb').read_bytes()).hexdigest(),'height':1,'forward':'+Z','up':'+Y','bones':[b.name for b in rig.data.bones],'clips':clips,'triangles':len(mesh.data.polygons),'sourceHeight':height,'sourceFloor':lo,'scope':'P0 foundation'}
(D/'manifest.json').write_text(json.dumps(manifest,indent=2))
# Portable deformation evidence, rendered with the original materials.
s.render.engine='BLENDER_EEVEE';s.render.resolution_x=700;s.render.resolution_y=700;s.render.resolution_percentage=100
s.world=bpy.data.worlds.new('Studio');s.world.use_nodes=True;s.world.node_tree.nodes['Background'].inputs[0].default_value=(.55,.55,.55,1);s.world.node_tree.nodes['Background'].inputs[1].default_value=.7
for pos,power,size in [((2,-3,4),300,3),((-2,-1,2),100,2)]:
 bpy.ops.object.light_add(type='AREA',location=pos);o=bpy.context.object;o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(Vector((0,0,.5))-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(1.4,-2.5,1.2));c=bpy.context.object;c.rotation_euler=(Vector((0,0,.5))-c.location).to_track_quat('-Z','Y').to_euler();c.data.type='ORTHO';c.data.ortho_scale=1.25;s.camera=c
(D/'renders').mkdir(exist_ok=True)
for name,frame in [('idle',1),('walk',10),('run',6)]:
 rig.animation_data.action=bpy.data.actions[name];s.frame_set(frame);s.render.filepath=str(D/'renders'/f'{name}.png');bpy.ops.render.render(write_still=True)
