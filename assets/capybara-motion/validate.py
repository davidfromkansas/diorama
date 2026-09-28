"""Blender validation: inspect exported GLB, not the authoring scene."""
import bpy,json,math,struct,hashlib
from pathlib import Path
D=Path(__file__).resolve().parent
b=(D/'capybara-animated.glb').read_bytes();n=struct.unpack_from('<I',b,12)[0];j=json.loads(b[20:20+n]);binary=b[28+n:]
errors=[]
assert set(a['name'] for a in j['animations'])=={'idle','walk','run'}
assert len(j['skins'][0]['joints'])==25
assert len(j['materials'])==1 and len(j['textures'])==3
assert not j.get('extensionsRequired')
def values(i):
 a=j['accessors'][i];v=j['bufferViews'][a['bufferView']];formats={5126:'f',5123:'H',5125:'I',5121:'B'};f=formats[a['componentType']];size=struct.calcsize(f);width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']];offset=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',width*size)
 return [struct.unpack_from('<'+f*width,binary,offset+k*stride) for k in range(a['count'])]
loops={}
for a in j['animations']:
 maxdiff=0
 for sampler in a['samplers']:
  v=values(sampler['output']);assert all(math.isfinite(x) for row in v for x in row)
  maxdiff=max(maxdiff,max(abs(x-y) for x,y in zip(v[0],v[-1])))
 loops[a['name']]=maxdiff
 if maxdiff>.0001:errors.append(a['name']+' loop does not close')
weights=values(j['meshes'][0]['primitives'][0]['attributes']['WEIGHTS_0']);assert all(abs(sum(w)-1)<1e-5 for w in weights)
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(D/'capybara-animated.glb'))
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH');s=bpy.context.scene
for track in rig.animation_data.nla_tracks:track.mute=True
samples={}
for action in bpy.data.actions:
 rig.animation_data.action=action;start,end=action.frame_range;bounds=[]
 for i in range(21):
  frame=start+(end-start)*i/20;s.frame_set(int(frame),subframe=frame-int(frame));deps=bpy.context.evaluated_depsgraph_get();obj=mesh.evaluated_get(deps);m=obj.to_mesh();low=min((obj.matrix_world@v.co).z for v in m.vertices);bounds.append(low);obj.to_mesh_clear()
 samples[action.name]={'minFloor':min(bounds),'maxFloor':max(bounds),'samples':21}
 if min(bounds)<-.012:errors.append(action.name+' mesh penetrates ground over 12mm')
report={'errors':errors,'joints':25,'triangles':j['accessors'][j['meshes'][0]['primitives'][0]['indices']]['count']//3,'loopMaxDifference':loops,'normalizedWeights':True,'finiteAnimationSamples':True,'floorBounds':samples,'animatedSHA256':hashlib.sha256(b).hexdigest()}
(D/'validation.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2));assert not errors,errors
