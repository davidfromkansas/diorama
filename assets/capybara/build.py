"""Deterministic capybara authoring pipeline. Blender 5.2, no external Python dependencies.
Run: /Applications/Blender.app/Contents/MacOS/Blender -b --python assets/capybara/build.py
Optional: -- --preview (only front/three-quarter renders), --no-render.
"""
import bpy, math, json, sys
import numpy as np
from mathutils import Vector, Quaternion, kdtree
import bmesh
from pathlib import Path
from math import sin, cos, pi, sqrt
OUT=Path(__file__).resolve().parent
sys.path.insert(0,str(OUT))
for d in ['textures','renders']: (OUT/d).mkdir(exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for a in list(bpy.data.actions): bpy.data.actions.remove(a)
bpy.context.preferences.filepaths.save_version=0
S=bpy.context.scene; S.render.fps=30
MORPHS=['neutral','smile','big_smile','blink_left','blink_right','blink_both','sad','surprised','angry','talk_open','talk_small','content']

def linear(h):
    v=[int(h[i:i+2],16)/255 for i in (0,2,4)]
    return [c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in v]

def image(name,pixels,noncolor=False):
    h,w=pixels.shape[:2]; im=bpy.data.images.new(name,width=w,height=h,alpha=True)
    if noncolor: im.colorspace_settings.name='Non-Color'
    im.pixels.foreach_set(pixels.astype(np.float32).ravel()); im.filepath_raw=str(OUT/'textures'/f'{name}.png'); im.file_format='PNG'; im.save(); im.pack(); return im
# Seamless, directional short-fibre normal texture. A material, not strand geometry.
rng=np.random.default_rng(712); n=1024
h=rng.normal(size=(n,n)).astype(np.float32)
seed=h.copy(); h=sum(np.roll(np.roll(seed,i,axis=0),i//4,axis=1)*np.exp(-i/4) for i in range(13))
h=(h-h.min())/(h.max()-h.min())
dx=(np.roll(h,-1,1)-np.roll(h,1,1))*1.35; dy=(np.roll(h,-1,0)-np.roll(h,1,0))*1.35
norm=np.stack([-dx,-dy,np.ones_like(h)],axis=2); norm/=np.linalg.norm(norm,axis=2,keepdims=True)
normal=image('plush_normal',np.dstack([norm*.5+.5,np.ones_like(h)]),True)
# Blush texture has soft radial alpha; avoids a raised cheek-button silhouette.
yy,xx=np.mgrid[-1:1:128j,-1:1:128j]; alpha=np.clip(1-xx*xx-yy*yy,0,1)**1.6*.62
blush=image('cheek_blush',np.dstack([np.full_like(alpha,244/255),np.full_like(alpha,183/255),np.full_like(alpha,167/255),alpha]))

def material(name,color,rough=.8,fur=False):
    m=bpy.data.materials.new(name); m.use_nodes=True; p=m.node_tree.nodes.get('Principled BSDF'); rgb=linear(color)
    p.inputs['Base Color'].default_value=(*rgb,1); p.inputs['Roughness'].default_value=rough
    m.diffuse_color=(*rgb,1)
    if fur:
        tint=np.array([int(color[i:i+2],16)/255 for i in (0,2,4)],dtype=np.float32)[None,None,:]*(.97+.06*h[...,None])
        texcolor=image(name.split('_')[1].lower()+'_albedo',np.dstack([tint,np.ones_like(h)]))
        color_node=m.node_tree.nodes.new('ShaderNodeTexImage');color_node.image=texcolor
        m.node_tree.links.new(color_node.outputs['Color'],p.inputs['Base Color'])
        p.inputs['Sheen Weight'].default_value=.20; p.inputs['Sheen Roughness'].default_value=.85
        tex=m.node_tree.nodes.new('ShaderNodeTexImage'); tex.image=normal
        nm=m.node_tree.nodes.new('ShaderNodeNormalMap'); nm.inputs['Strength'].default_value=.42
        m.node_tree.links.new(tex.outputs['Color'],nm.inputs['Color']); m.node_tree.links.new(nm.outputs['Normal'],p.inputs['Normal'])
    return m
mats=[material('Fur_Body_D9A772','D9A772',.89,True),material('Fur_Muzzle_Paws_7B5A3C','7B5A3C',.88,True),material('Ear_Inner','70492F',.9,True),material('Eyes_111111','111111',.19),material('Nose_And_Smile','302014',.70),material('Mouth_Interior','3E251E',.95),material('Tongue','D99083',.85)]
cheekmat=material('Cheeks_F4B7A7','F4B7A7',.9)
p=cheekmat.node_tree.nodes.get('Principled BSDF'); t=cheekmat.node_tree.nodes.new('ShaderNodeTexImage'); t.image=blush
cheekmat.node_tree.links.new(t.outputs['Color'],p.inputs['Base Color']); cheekmat.node_tree.links.new(t.outputs['Alpha'],p.inputs['Alpha']); cheekmat.surface_render_method='DITHERED'; mats.append(cheekmat)

# Each component is closed, with rings concentrated around deforming joints.
# All vertices have explicit normalized smooth skinning weights.
class Mesh:
    def __init__(self,name): self.name=name; self.v=[]; self.f=[]; self.uv=[]; self.mi=[]; self.w=[]; self.tags=[]
    def vert(self,p,uv,w,tag=None): self.v.append(tuple(p));self.uv.append(uv);self.w.append(w);self.tags.append(tag);return len(self.v)-1
    def face(self,ids,mat): self.f.append(ids);self.mi.append(mat)
    def ellipsoid(self,c,r,mat,w,seg=40,rings=24,tag=None,shape=None):
        start=len(self.v)
        # Duplicated seam UV vertices are merged only at poles; seam normals remain analytically aligned.
        for j in range(rings+1):
            t=pi*j/rings
            for i in range(seg+1):
                a=2*pi*i/seg; q=Vector((sin(t)*cos(a),sin(t)*sin(a),cos(t)))
                p=Vector((c[0]+r[0]*q.x,c[1]+r[1]*q.y,c[2]+r[2]*q.z))
                if shape:p=shape(p,q)
                weights=w(p) if callable(w) else w
                self.vert(p,(i/seg,j/rings),weights,(tag,tuple(p),tuple(c),tuple(q)))
        for j in range(rings):
            for i in range(seg):
                a=start+j*(seg+1)+i;b=a+seg+1
                if j==0:self.face((a,b,b+1),mat)
                elif j==rings-1:self.face((a,b,a+1),mat)
                else:self.face((a,b,b+1,a+1),mat)
    def tube(self,points,r,mat,w,tag=None,sides=8):
        start=len(self.v)
        for i,p in enumerate(points):
            p=Vector(p); tangent=Vector(points[min(i+1,len(points)-1)])-Vector(points[max(i-1,0)])
            tangent.normalize(); n=tangent.cross(Vector((0,1,0))).normalized(); b=tangent.cross(n).normalized()
            for j in range(sides):
                q=p+r*(cos(2*pi*j/sides)*n+sin(2*pi*j/sides)*b)
                self.vert(q,(j/sides,i/(len(points)-1)),w,(tag,tuple(q),tuple(p),(i/(len(points)-1),j/sides,0)))
        for i in range(len(points)-1):
            for j in range(sides):
                a=start+i*sides+j;b=start+i*sides+(j+1)%sides
                self.face((a,b,b+sides,a+sides),mat)
        for j in range(1,sides-1):
            self.face((start,start+j+1,start+j),mat)
            end=start+(len(points)-1)*sides
            self.face((end,end+j,end+j+1),mat)
    def finish(self):
        me=bpy.data.meshes.new(self.name);me.from_pydata(self.v,[],self.f);me.update();o=bpy.data.objects.new(self.name,me);S.collection.objects.link(o)
        for m in mats:me.materials.append(m)
        uv=me.uv_layers.new(name='UVMap')
        for poly,idx in zip(me.polygons,self.mi):
            poly.material_index=idx;poly.use_smooth=True
            for li in poly.loop_indices:uv.data[li].uv=self.uv[me.loops[li].vertex_index]
        names=set(k for w in self.w for k in w)
        for name in names:
            vg=o.vertex_groups.new(name=name)
            for i,w in enumerate(self.w):
                if w.get(name,0)>0:vg.add([i],w[name],'REPLACE')
        return o

def smooth(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)
def blend(a,b,t):return {a:1-t,b:t}
def torso_w(p):
    z=p.z
    if z<.38:return blend('pelvis','spine',smooth(.24,.42,z))
    return blend('spine','chest',smooth(.40,.60,z))
body=Mesh('Capybara_Body')
def pear(p,q):
    # Full haunches and a forward belly, tapering into the chest.
    f=1-.18*q.z
    p.x*=f;p.y=p.y*f-.027*(1-q.z*q.z)+.017*max(0,q.y)*math.exp(-((p.z-.32)/.11)**2);return p
body.ellipsoid((0,.022,.415),(.205,.170,.240),0,torso_w,48,32,shape=pear)
body.ellipsoid((0,-.012,.795),(.210,.190,.168),0,{'head':1},48,28,shape=lambda p,q:Vector((p.x*(1-.09*q.z),p.y-.018*(1-q.z*q.z)-.055*max(0,-q.y)**2*(1-.8*max(0,q.z)),p.z)))
for s,side in [(-1,'R'),(1,'L')]:
    # Ears seated in the skull, gently canted outward.
    c=(s*.140,.012,.955)
    body.ellipsoid(c,(.034,.028,.045),0,{f'ear.{side}':1},28,18)
    body.ellipsoid((s*.141,-.011,.957),(.021,.010,.028),2,{f'ear.{side}':1},24,16)
    # Arms are authored in T-pose. More rings than a primitive along the elbow span.
    def arm_w(p,s=s,side=side):
        x=abs(p.x)
        if x<.18:return blend('chest',f'upper_arm.{side}',smooth(.115,.19,x))
        if x<.285:return blend(f'upper_arm.{side}',f'lower_arm.{side}',smooth(.225,.28,x))
        return blend(f'lower_arm.{side}',f'hand.{side}',smooth(.305,.335,x))
    body.ellipsoid((s*.225,-.002,.606),(.158,.051,.052),0,arm_w,32,20)
    body.ellipsoid((s*.365,-.002,.606),(.037,.045,.040),1,{f'hand.{side}':1},28,18)
    def leg_w(p,side=side):
        if p.z>.245:return blend(f'upper_leg.{side}','pelvis',smooth(.25,.355,p.z))
        if p.z>.095:return blend(f'lower_leg.{side}',f'upper_leg.{side}',smooth(.13,.225,p.z))
        return blend(f'foot.{side}',f'lower_leg.{side}',smooth(.06,.13,p.z))
    body.ellipsoid((s*.112,.018,.185),(.077,.089,.160),0,leg_w,36,26)
    # Flatten the sole at canonical z=0 without a spherical tip touching the floor.
    body.ellipsoid((s*.112,-.018,.040),(.067,.091,.049),1,{f'foot.{side}':1},36,20,shape=lambda p,q:Vector((p.x,p.y,max(0,p.z))))
    # Two shallow toe seams on each paw, following the paw curvature.
    for d in [-.021,.021]:
        pts=[(s*.112+d,-.018-.090*sqrt(max(0,1-(d/.067)**2-((z-.04)/.049)**2))-.001,z) for z in np.linspace(.015,.061,12)]
        body.tube(pts,.0012,2,{f'foot.{side}':1},sides=6)
body.ellipsoid((0,.166,.256),(.046,.038,.049),0,{'tail':1},28,18)
body_details=body.finish();body_details.name='Capybara_Paws_And_Ears'
# Union the golden surfaces and generate a continuous, quad-dominant deformation cage.
# This removes intersecting primitive seams at the hips, shoulders, and neck.
body_obj=body_details.copy();body_obj.data=body_details.data.copy();S.collection.objects.link(body_obj);body_obj.name='Capybara_Body'
for ob,keep in [(body_obj,True),(body_details,False)]:
    bm=bmesh.new();bm.from_mesh(ob.data)
    bmesh.ops.delete(bm,geom=[f for f in bm.faces if (f.material_index==0)!=keep],context='FACES')
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001)
    bm.to_mesh(ob.data);bm.free();ob.data.update()
bpy.ops.object.select_all(action='DESELECT');body_obj.select_set(True);bpy.context.view_layer.objects.active=body_obj
body_obj.data.remesh_voxel_size=.0035;bpy.ops.object.voxel_remesh()
sm=body_obj.modifiers.new('Blend organic junctions','SMOOTH');sm.factor=.7;sm.iterations=6;bpy.ops.object.modifier_apply(modifier=sm.name)
bpy.ops.object.quadriflow_remesh(use_mesh_symmetry=True,use_preserve_sharp=False,target_faces=6200,seed=17)
for p in body_obj.data.polygons:p.use_smooth=True;p.material_index=0
# Transfer the explicit anatomical weights onto the remeshed surface; normalize to 4 influences.
kd=kdtree.KDTree(len(body.v))
for i,p in enumerate(body.v):kd.insert(p,i)
kd.balance();body_obj.vertex_groups.clear()
vg={n:body_obj.vertex_groups.new(name=n) for n in set(k for w in body.w for k in w)}
for v in body_obj.data.vertices:
    weights={}
    for co,i,dist in kd.find_n(v.co,8):
        for name,w in body.w[i].items():weights[name]=weights.get(name,0)+w/max(dist,.0001)**2
    top=sorted(weights.items(),key=lambda kv:-kv[1])[:4];total=sum(w for _,w in top)
    for name,w in top:vg[name].add([v.index],w/total,'REPLACE')
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(angle_limit=1.1519,island_margin=.02);bpy.ops.object.mode_set(mode='OBJECT')

face=Mesh('Capybara_Face')
face.ellipsoid((0,-.232,.765),(.091,.061,.085),1,{'head':1},40,24,tag='muzzle')
for s,side in [(-1,'R'),(1,'L')]:
    face.ellipsoid((s*.151,-.171,.837),(.015,.014,.023),3,{'head':1},24,16,tag='eye_'+side)
    # Small nostrils on the upper muzzle; independent of the mouth opening.
    face.ellipsoid((s*.017,-.286,.795),(.011,.004,.005),4,{'head':1},20,12,tag='nose')
    # Cheek as a surface patch conforming to the actual head surface, UV radial falloff.
    start=len(face.v);steps=16
    for j in range(steps+1):
        v=j/steps
        for i in range(steps+1):
            u=i/steps;x=s*(.151+(u-.5)*.062);z=.774+(v-.5)*.046
            qz=(z-.795)/.168;rx=.210*(1-.09*qz)
            y=-.012-.018*(1-qz*qz)-.190*sqrt(max(.001,1-(x/rx)**2-qz*qz))-.0010-.055*max(.001,1-(x/rx)**2-qz*qz)*(1-.8*max(0,qz))
            face.vert((x,y,z),(u,v),{'head':1},('cheek',(x,y,z),(s*.151,y,.774),(u,v,0)))
    for j in range(steps):
        for i in range(steps):
            a=start+j*(steps+1)+i;b=a+steps+1
            face.face((a,a+1,b+1,b) if s==1 else (a,b,b+1,a+1),7)

def surface_y(x,z):return -.232-.061*sqrt(max(.012,1-(x/.091)**2-((z-.765)/.085)**2))-.0022
# Wrap smile around the muzzle so the ends remain readable at profile.
for s in [-1,1]:
    pts=[]
    for t in np.linspace(0,1,32):
        x=s*.075*t;z=.736-.012*sin(pi*t)+.004*t
        pts.append((x,surface_y(x,z),z))
    face.tube(pts,.0021,4,{'head':1},tag='smile',sides=8)
face.tube([(0,surface_y(0,z),z) for z in np.linspace(.736,.773,14)],.0019,4,{'head':1},tag='philtrum')
# A flattened neutral opening grows into a curved dark mouth patch during speech.
face.ellipsoid((0,surface_y(0,.729)-.0005,.729),(.035,.0008,.0007),5,{'head':1},40,20,tag='opening',shape=lambda p,q:Vector((p.x,surface_y(p.x,p.z)-.0008+q.y*.0005,p.z)))
face.ellipsoid((0,surface_y(0,.728)-.0015,.728),(.017,.0005,.0004),6,{'head':1},28,14,tag='tongue',shape=lambda p,q:Vector((p.x,surface_y(p.x,p.z)-.0013+q.y*.0003,p.z)))
face_obj=face.finish();face_obj.shape_key_add(name='Basis',from_mix=False)
for name in MORPHS:
    key=face_obj.shape_key_add(name=name,from_mix=False);key.value=0
    for i,(p,taginfo) in enumerate(zip(face.v,face.tags)):
        if not taginfo:continue
        tag,base,c,q=taginfo;x,y,z=p;cx,cy,cz=c
        if tag and tag.startswith('eye_'):
            close=(name in ['blink_both','content'] or name=='blink_left' and tag=='eye_L' or name=='blink_right' and tag=='eye_R')
            if close:z=cz+(z-cz)*.085
            if name in ['smile','big_smile']:z=cz+(z-cz)*(.72 if name=='smile' else .5)
            if name=='sad':z+=.10*(abs(x)-abs(cx));z=cz+(z-cz)*.8
            if name=='angry':z=cz+(z-cz)*.60+.4*(abs(x)-abs(cx))
            if name=='surprised':z=cz+(z-cz)*1.12
        if tag=='smile':
            t=abs(cx)/.075
            if name in ['smile','big_smile','content']: z+=(.008 if name!='big_smile' else .014)*t
            if name=='sad':z+=.021*sin(pi*t)-.007*t
            if name in ['talk_open','surprised','talk_small','big_smile']:
                # Raise branches into the upper lip; a filled patch provides the opening below.
                z+=.007*sin(pi*t)
            y+=surface_y(x,z)-surface_y(x,p[2])
        if tag in ['opening','tongue']:
            amount={'big_smile':.019,'surprised':.026,'talk_open':.021,'talk_small':.009}.get(name,0)
            if amount:
                factor=.65 if tag=='tongue' else 1
                z=cz+q[2]*amount*factor-(amount*.5 if tag=='tongue' else amount*.18)
                x=cx+q[0]*(.019 if name=='surprised' else .035)*(.55 if tag=='tongue' else 1)
                y=surface_y(x,z)-(.0018 if tag=='tongue' else .0009)+q[1]*.00025
        key.data[i].co=(x,y,z)

# Deformation skeleton. All animation rotations are specified in world-axis deltas
# then converted to each bone's local rest basis. No generic human proportions.
arm=bpy.data.armatures.new('Capybara_Skeleton');rig=bpy.data.objects.new('Capybara_Rig',arm);S.collection.objects.link(rig);bpy.context.view_layer.objects.active=rig;rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
spec={}
def bone(name,head,tail,parent=None):
    b=arm.edit_bones.new(name);b.head=head;b.tail=tail
    if parent:b.parent=arm.edit_bones[parent]
    spec[name]={'head':head,'tail':tail,'parent':parent};return b
bone('root',(0,0,0),(0,0,.08));bone('pelvis',(0,.018,.31),(0,.018,.40),'root');bone('spine',(0,.018,.40),(0,.006,.52),'pelvis');bone('chest',(0,.006,.52),(0,0,.64),'spine');bone('neck',(0,0,.64),(0,0,.71),'chest');bone('head',(0,0,.71),(0,0,.89),'neck')
for s,side in [(-1,'R'),(1,'L')]:
    bone(f'shoulder.{side}',(0,0,.60),(s*.135,0,.606),'chest')
    bone(f'upper_arm.{side}',(s*.135,0,.606),(s*.255,0,.606),f'shoulder.{side}')
    bone(f'lower_arm.{side}',(s*.255,0,.606),(s*.329,0,.606),f'upper_arm.{side}')
    bone(f'hand.{side}',(s*.329,0,.606),(s*.393,0,.606),f'lower_arm.{side}')
    bone(f'upper_leg.{side}',(s*.112,.018,.31),(s*.112,.003,.172),'pelvis')
    bone(f'lower_leg.{side}',(s*.112,.003,.172),(s*.112,.006,.050),f'upper_leg.{side}')
    bone(f'foot.{side}',(s*.112,.006,.050),(s*.112,-.085,.028),f'lower_leg.{side}')
    bone(f'ear.{side}',(s*.140,.012,.923),(s*.141,.012,.993),'head')
bone('tail',(0,.145,.256),(0,.198,.259),'pelvis')
bpy.ops.object.mode_set(mode='OBJECT');rig.show_in_front=True;arm.display_type='OCTAHEDRAL'
for o in [body_obj,body_details,face_obj]:
    o.parent=rig;mod=o.modifiers.new('Soft skin','ARMATURE');mod.object=rig;mod.use_deform_preserve_volume=False
# Animation helpers: glTF linear blend skinning is the validation baseline.
def reset():
    for p in rig.pose.bones:p.rotation_mode='QUATERNION';p.rotation_quaternion=Quaternion();p.location=(0,0,0);p.scale=(1,1,1)
def rot(name,x=0,y=0,z=0):
    p=rig.pose.bones[name];q=Quaternion((1,0,0),x)@Quaternion((0,1,0),y)@Quaternion((0,0,1),z)
    basis=p.bone.matrix_local.to_quaternion();p.rotation_quaternion=basis.inverted()@q@basis

def loc(name,v):
    p=rig.pose.bones[name];p.location=p.bone.matrix_local.to_quaternion().inverted()@Vector(v)
def neutral():
    for s,side in [(-1,'R'),(1,'L')]:rot(f'upper_arm.{side}',y=s*1.20);rot(f'lower_arm.{side}',z=-s*.07)
def seated(a=1):
    loc('pelvis',(0,.015*a,-.09*a));rot('spine',x=.07*a)
    for s,side in [(-1,'R'),(1,'L')]:
        leg_ik(side,.006-.11*a,.050,-.09*a)
def forward_arms(a=1):
    for s,side in [(-1,'R'),(1,'L')]:
        rot(f'upper_arm.{side}',y=s*.35,z=-s*1.35*a);rot(f'lower_arm.{side}',z=-s*.65*a)

CLIPS=[('idle',4,True),('walk',1.2,True),('run',.8,True),('sit_down',1.4,False),('sit_idle',4,True),('stand_up',1.4,False),('wave',2.4,False),('point',2.4,False),('think',4,True),('talk',3,True),('type_at_computer',2,True),('read',4,True),('pick_up_object',2,False),('carry_object',1.2,True),('put_down_object',2,False),('jump',1.4,False),('celebrate',2.6,False),('sleep',5,True)]
# Ground-contact two-link IK, baked to FK quaternion tracks. Root stays stationary.
def leg_ik(side,y,z,pelvis_z=0):
    hip=Vector((0,.018,.31+pelvis_z));target=Vector((0,y,z));vec=target-hip
    l1=Vector((0,-.015,-.138)).length;l2=Vector((0,.003,-.122)).length;d=min(vec.length,l1+l2-.00001)
    alpha=math.acos(max(-1,min(1,(l1*l1+d*d-l2*l2)/(2*l1*d))))
    direction=math.atan2(vec.y,-vec.z);thigh=direction-alpha
    knee=pi-math.acos(max(-1,min(1,(l1*l1+l2*l2-d*d)/(2*l1*l2))))
    rest1=math.atan2(-.015,.138);rest2=math.atan2(.003,.122)
    # Rotation about X sends a downward vector toward +Y.
    rot(f'upper_leg.{side}',x=thigh-rest1)
    rot(f'lower_leg.{side}',x=knee-(rest2-rest1))
    rot(f'foot.{side}',x=-(thigh+knee-rest2))

def pose(name,t,d):
    reset();neutral();p=t/d;cy=2*pi*p
    breath=sin(cy)*.003
    rot('head',z=.015*sin(cy));rot('tail',x=.03*sin(cy))
    for s,side in [(-1,'R'),(1,'L')]:rot(f'ear.{side}',y=s*.025*sin(cy))
    if name in ['idle','talk','think','read']:rot('chest',x=.012*sin(cy))
    if name in ['walk','run','carry_object']:
        running=name=='run';stride=.12 if running else .070
        drop=-.022+(.012 if running else .003)*(1-cos(2*cy))
        loc('pelvis',(0,0,drop));rot('spine',z=.022*sin(cy));rot('chest',x=.07 if running else .015,z=-.02*sin(cy))
        for s,side,off in [(-1,'R',0),(1,'L',.5)]:
            ph=(p+off)%1
            # 60% stance, constant speed backwards; swing is eased with a toe lift.
            stance=.52 if running else .6
            if ph<stance:y=-stride+2*stride*ph/stance;lift=0
            else:
                u=(ph-stance)/(1-stance);e=u*u*(3-2*u);y=stride-2*stride*e;lift=(.074 if running else .038)*sin(pi*u)**2
            leg_ik(side,.006+y,.050+lift,drop)
            rot(f'upper_arm.{side}',x=-.30*sin(cy+off*2*pi),y=s*1.16)
        if name=='carry_object':forward_arms();rot('chest',x=-.015)
    elif name in ['sit_down','stand_up','sit_idle','type_at_computer']:
        a=smooth(0,1,p) if name=='sit_down' else 1-smooth(0,1,p) if name=='stand_up' else 1
        seated(a)
        if name=='type_at_computer':
            forward_arms();rot('head',x=.12)
            for s,side in [(-1,'R'),(1,'L')]:rot(f'hand.{side}',x=.055*sin(4*cy+s*.9));rot(f'lower_arm.{side}',z=-s*(.65+.025*sin(4*cy+s)))
    elif name=='wave':
        e=smooth(0,.22,p)*(1-smooth(.80,1,p));rot('upper_arm.R',y=-1.20+2.20*e,z=.05*e);rot('lower_arm.R',y=.50*e+.19*sin(3*cy)*e);rot('hand.R',y=.22*sin(3*cy)*e)
    elif name=='point':
        e=smooth(0,.22,p)*(1-smooth(.82,1,p));rot('upper_arm.L',y=1.2-.95*e,z=-.50*e);rot('head',z=-.13*e)
    elif name=='think':
        rot('upper_arm.R',y=-.4,z=1.30);rot('lower_arm.R',y=1.7,z=.15);rot('head',y=-.10,z=.08+.02*sin(cy))
    elif name=='read':forward_arms();rot('head',x=.15);rot('chest',x=.025)
    elif name=='talk':
        for s,side in [(-1,'R'),(1,'L')]:rot(f'upper_arm.{side}',y=s*(1.0+.10*sin(cy+s)),z=-s*(.15+.09*sin(cy)))
        rot('head',x=.035*sin(2*cy))
    elif name in ['pick_up_object','put_down_object']:
        # Starts/ends at carry pose; object contact occurs at the midpoint.
        q=p if name=='pick_up_object' else 1-p;bend=sin(pi*q)**2
        loc('pelvis',(0,.015*bend,-.045*bend));rot('spine',x=.36*bend);rot('head',x=.16*bend)
        for side in ['L','R']:leg_ik(side,.006,.05,-.045*bend)
        for s,side in [(-1,'R'),(1,'L')]:
            if q<.5:
                e=smooth(0,.5,q);ay=1.2-.35*e;az=.70*e;el=.07+.33*e
            else:
                e=smooth(.5,1,q);ay=.85-.50*e;az=.70+.65*e;el=.40+.25*e
            rot(f'upper_arm.{side}',y=s*ay,z=-s*az);rot(f'lower_arm.{side}',z=-s*el)
    elif name=='jump':
        # Anticipation, ballistic flight, landing compression, settle.
        if p<.25:z=-.035*sin(pi*p/.5);b=.25*sin(pi*p/.5)
        elif p<.72:u=(p-.25)/.47;z=.16*4*u*(1-u);b=-.08*sin(pi*u)
        else:u=(p-.72)/.28;z=-.024*sin(pi*u);b=.22*sin(pi*u)
        loc('pelvis',(0,0,z));
        for side in ['L','R']:
            if z<=0:leg_ik(side,.006,.05,z)
            else:rot(f'upper_leg.{side}',x=-b);rot(f'lower_leg.{side}',x=2*b);rot(f'foot.{side}',x=-b)
        for s,side in [(-1,'R'),(1,'L')]:rot(f'upper_arm.{side}',y=s*(1.2-.85*sin(pi*p)**2))
    elif name=='celebrate':
        e=smooth(0,.23,p)*(1-smooth(.80,1,p));rot('chest',z=.035*sin(2*cy)*e)
        for s,side in [(-1,'R'),(1,'L')]:rot(f'upper_arm.{side}',y=s*(1.2-1.9*e));rot(f'lower_arm.{side}',y=-s*.35*e);rot(f'hand.{side}',x=.1*sin(3*cy)*e)
    elif name=='sleep':
        # Side-lying rest loop, body mass supported by the cheek and haunch.
        rot('root',y=pi/2);loc('root',(-.49,0,.219));rot('head',x=.06)
        for s,side in [(-1,'R'),(1,'L')]:rot(f'upper_arm.{side}',y=s*1.38,z=-s*.10)
        rot('chest',x=.007*sin(cy))

rig.animation_data_create()
for name,d,loop in CLIPS:
    act=bpy.data.actions.new(name);act.use_fake_user=True;rig.animation_data.action=act
    act['loop']=loop;act['duration_seconds']=d;act['in_place']=True
    count=round(d*30)
    for i in range(count+1):
        pose(name,i/30,d)
        for pb in rig.pose.bones:
            pb.keyframe_insert('rotation_quaternion',frame=i+1,group=pb.name);pb.keyframe_insert('location',frame=i+1,group=pb.name)
    # NLA export preserves exact clip names and includes one action per track.
    track=rig.animation_data.nla_tracks.new();track.name=name;strip=track.strips.new(name,1,act);strip.action_frame_start=1;strip.action_frame_end=count+1;track.mute=True
rig.animation_data.action=None;reset()
rig['asset_version']='1.0';rig['height_m']=1.0;rig['forward_blender']='-Y';rig['runtime_states']=json.dumps({'IDLE':['idle'],'MOVING':['walk','run'],'WORKING':['sit_down','sit_idle','type_at_computer','read','stand_up'],'THINKING':['think'],'COMMUNICATING':['wave','point','talk'],'INTERACTING':['pick_up_object','carry_object','put_down_object'],'CELEBRATING':['jump','celebrate'],'RESTING':['sleep']})
# Export only canonical character, never test-scene props or lights.
bpy.ops.object.select_all(action='DESELECT')
for o in [rig,body_obj,body_details,face_obj]:o.select_set(True)
bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=str(OUT/'capybara.glb'),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_nla_strips=True,export_force_sampling=True,export_frame_range=False,export_morph=True,export_morph_normal=True,export_tangents=True,export_skins=True,export_yup=True,export_extras=True,export_optimize_animation_size=True,export_anim_slide_to_zero=True)
from finalize_glb import finalize
finalize(OUT/'capybara.glb',CLIPS)
metrics={'triangles':sum(len(p.vertices)-2 for o in [body_obj,body_details,face_obj] for p in o.data.polygons),'vertices':sum(len(o.data.vertices) for o in [body_obj,body_details,face_obj]),'bones':len(spec),'morphs':MORPHS,'clips':[{'name':n,'duration':d,'loop':l} for n,d,l in CLIPS],'skeleton':spec,'materials':[m.name for m in mats]}
(OUT/'manifest.json').write_text(json.dumps(metrics,indent=2)+'\n')
rig.animation_data.action=None
for tr in rig.animation_data.nla_tracks: tr.mute=True
reset()
for k in face_obj.data.shape_keys.key_blocks: k.value=0
bpy.context.view_layer.update()
# Ground and studio rig stay in the editable source for reproducible comparison renders.
floor_mat=material('Studio_Ivory','EEE9E1',.92)
fp=floor_mat.node_tree.nodes.get('Principled BSDF');fp.inputs['Emission Color'].default_value=(*linear('EEE9E1'),1);fp.inputs['Emission Strength'].default_value=.3
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.001));floor=bpy.context.object;floor.name='STUDIO_Ground';floor.data.materials.append(floor_mat)
def area(name,pos,power,size):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;o=bpy.data.objects.new(name,data);S.collection.objects.link(o);o.location=pos;o.rotation_euler=(Vector((0,0,.5))-o.location).to_track_quat('-Z','Y').to_euler()
area('STUDIO_Key',(-2,-3,4),110,3);area('STUDIO_Fill',(2,-1,2),50,2.5);area('STUDIO_Rim',(0,2,3),80,2)
S.world.use_nodes=True
S.world.node_tree.nodes.get('Background').inputs['Color'].default_value=(.72,.69,.65,1)
S.world.node_tree.nodes.get('Background').inputs['Strength'].default_value=.35
# A neutral camera backdrop independent of the illumination used to judge albedo.
wn=S.world.node_tree; bg=wn.nodes.get('Background'); out=wn.nodes.get('World Output')
cb=wn.nodes.new('ShaderNodeBackground');cb.inputs['Color'].default_value=(.86,.84,.80,1)
lp=wn.nodes.new('ShaderNodeLightPath');mix=wn.nodes.new('ShaderNodeMixShader')
wn.links.new(lp.outputs['Is Camera Ray'],mix.inputs[0]);wn.links.new(bg.outputs[0],mix.inputs[1]);wn.links.new(cb.outputs[0],mix.inputs[2]);wn.links.new(mix.outputs[0],out.inputs['Surface'])
cam_data=bpy.data.cameras.new('STUDIO_Camera');cam=bpy.data.objects.new('STUDIO_Camera',cam_data);S.collection.objects.link(cam);S.camera=cam;cam_data.type='ORTHO';cam_data.ortho_scale=1.20
S.render.engine='CYCLES';S.cycles.samples=32;S.cycles.use_denoising=True;S.render.resolution_x=700;S.render.resolution_y=700;S.render.resolution_percentage=100
S.view_settings.view_transform='Standard';S.render.image_settings.file_format='PNG';S.render.film_transparent=False
S.frame_set(1)
rig.animation_data.action=None
for tr in rig.animation_data.nla_tracks: tr.mute=True
reset()
for k in face_obj.data.shape_keys.key_blocks: k.value=0
bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'capybara.blend'))
if '--no-render' not in sys.argv:
    from render_turnaround import render_turnaround
    render_turnaround(S,OUT,'--preview' in sys.argv)
print('CAPYBARA_BUILD_COMPLETE',json.dumps({k:metrics[k] for k in ['triangles','vertices','bones']}))
