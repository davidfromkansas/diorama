"""Normalize exporter output without modifying geometry, weights, or animation samples."""
import json,struct

def finalize(path,clips):
    data=path.read_bytes();size=struct.unpack_from('<I',data,12)[0];doc=json.loads(data[20:20+size]);binary=data[28+size:]
    # Blender's armature container is identity. Make skinned meshes scene roots,
    # as required for portable parent-transform semantics in glTF runtimes.
    roots=doc['scenes'][doc.get('scene',0)]['nodes']
    for node in doc['nodes']:
        if node.get('name')=='Capybara_Rig':
            assert not any(k in node for k in ['matrix','translation','rotation','scale'])
            children=node.get('children',[]);skinned=[i for i in children if 'skin' in doc['nodes'][i]]
            node['children']=[i for i in children if i not in skinned];roots.extend(skinned)
    for mesh in doc['meshes']:
        for prim in mesh['primitives']:
            material=doc['materials'][prim['material']]
            textured=('normalTexture' in material or 'baseColorTexture' in material.get('pbrMetallicRoughness',{}))
            if not textured:prim['attributes'].pop('TEXCOORD_0',None)
            if 'normalTexture' not in material:prim['attributes'].pop('TANGENT',None)
    byname={n:(d,l) for n,d,l in clips}
    for anim in doc['animations']:
        duration,loop=byname[anim['name']]
        anim['extras']={'loop':loop,'duration_seconds':duration,'in_place':True}
        if anim['name'] in ['walk','carry_object']:anim['extras']['nominal_speed_mps']=.14/(.6*1.2)
        if anim['name']=='run':anim['extras']['nominal_speed_mps']=.24/(.52*.8)
        if anim['name'] in ['pick_up_object','put_down_object']:anim['extras']['events']=[{'time':1.0,'event':'attach_object' if anim['name']=='pick_up_object' else 'release_object'}]
    # Drop data made unreachable by removing unneeded UV/tangent attributes.
    used=set()
    for mesh in doc['meshes']:
        for p in mesh['primitives']:
            used.update(p['attributes'].values())
            if 'indices' in p:used.add(p['indices'])
            for target in p.get('targets',[]):used.update(target.values())
    for a in doc['animations']:
        for sampler in a['samplers']:used.update([sampler['input'],sampler['output']])
    for skin in doc['skins']:used.add(skin['inverseBindMatrices'])
    remap={old:new for new,old in enumerate(sorted(used))}
    doc['accessors']=[doc['accessors'][i] for i in sorted(used)]
    for mesh in doc['meshes']:
        for p in mesh['primitives']:
            p['attributes']={k:remap[v] for k,v in p['attributes'].items()}
            if 'indices' in p:p['indices']=remap[p['indices']]
            for target in p.get('targets',[]):
                for k in target:target[k]=remap[target[k]]
    for a in doc['animations']:
        for sampler in a['samplers']:
            for k in ['input','output']:sampler[k]=remap[sampler[k]]
    for skin in doc['skins']:skin['inverseBindMatrices']=remap[skin['inverseBindMatrices']]
    views=set();owners=[]
    for a in doc['accessors']:
        if 'bufferView' in a:owners.append(a)
        if 'sparse' in a:owners.extend([a['sparse']['indices'],a['sparse']['values']])
    owners.extend(i for i in doc.get('images',[]) if 'bufferView' in i)
    views={o['bufferView'] for o in owners};vm={old:new for new,old in enumerate(sorted(views))}
    newviews=[];payload=bytearray()
    for idx in sorted(views):
        view=doc['bufferViews'][idx].copy();offset=view.get('byteOffset',0);chunk=binary[offset:offset+view['byteLength']]
        payload.extend(b'\0'*((-len(payload))%4));view['byteOffset']=len(payload);payload.extend(chunk);newviews.append(view)
    for owner in owners:owner['bufferView']=vm[owner['bufferView']]
    doc['bufferViews']=newviews;doc['buffers'][0]['byteLength']=len(payload)
    payload.extend(b'\0'*((-len(payload))%4));binary=bytes(payload)
    blob=json.dumps(doc,separators=(',',':')).encode();blob+=b' '*((-len(blob))%4)
    path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(blob)+len(binary))+struct.pack('<II',len(blob),0x4e4f534a)+blob+struct.pack('<II',len(binary),0x004e4942)+binary)
