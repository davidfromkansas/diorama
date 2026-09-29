#!/usr/bin/env python3
"""Convert approved Herman Miller AutoCAD 3D DXFs to metre, Y-up OBJ assets.
Requires ezdxf. Input DXFs come from LibreDWG dwg2dxf; no mesh dimensions are altered.
Usage: python convert-office-furniture.py INPUT_DIRECTORY OUTPUT_DIRECTORY
"""
import sys, json, hashlib
from pathlib import Path
from collections import defaultdict
import ezdxf
src, out = map(Path, sys.argv[1:3]); out.mkdir(parents=True, exist_ok=True)
manifest = {'units':'metres','up':'Y','sources':{}}
for source, name in [('aeron','AeronESD'), ('nevi','NeviC')]:
    document = ezdxf.readfile(src / (source+'.dxf'))
    assert document.header.get('$INSUNITS') == 1, 'Expected explicitly authored inch units'
    groups = defaultdict(list)
    def visit(entities):
        for e in entities:
            if e.dxftype() == 'INSERT': visit(e.virtual_entities())
            elif e.dxftype() == '3DFACE':
                face=[]
                for v in e.wcs_vertices():
                    x,y,z=(float(c)*.0254 for c in v)
                    # Chair faces +CAD X; table depth lies on -CAD Y.
                    p=(y,z,x) if source=='aeron' else (x-.760635,z,-y-.0254)
                    if p not in face: face.append(p)
                if len(face)>=3: groups[e.dxf.layer].append(face)
    visit(document.modelspace())
    lines=['# Herman Miller official CAD model, inches converted uniformly to metres.', 'mtllib '+name+'.mtl']
    materials=[]; index=1; all_points=[]; triangles=0
    for layer,faces in groups.items():
        lines+=['o '+layer, 'usemtl '+layer]
        color=(.13,.15,.15) if source=='aeron' else ((.94,.94,.94) if 'TOP' in layer else (.62,.62,.62))
        if 'FABRIC' in layer: color=(.20,.23,.22)
        if 'CASTER' in layer: color=(.08,.09,.09)
        if 'GLIDES' in layer: color=(.12,.12,.12)
        materials += ['newmtl '+layer, 'Kd '+' '.join(map(str,color)), 'Ks 0.1 0.1 0.1', 'Ns 30','']
        # Share repeated vertices within each authored material group.
        lookup={}
        for face in faces:
            ids=[]
            for point in face:
                key=tuple(round(v,7) for v in point)
                if key not in lookup:
                    lookup[key]=index; index+=1; all_points.append(key)
                    lines.append('v '+' '.join(f'{v:.7f}' for v in key))
                ids.append(lookup[key])
            for i in range(1,len(ids)-1):
                lines.append(f'f {ids[0]} {ids[i]} {ids[i+1]}');triangles+=1
    (out/(name+'.obj')).write_text('\n'.join(lines)+'\n')
    (out/(name+'.mtl')).write_text('\n'.join(materials)+'\n')
    manifest['sources'][name]={'dwgSHA256':hashlib.sha256((src/(source+'.dwg')).read_bytes()).hexdigest(), 'vertices':len(all_points),'triangles':triangles,'minimum':[min(p[i] for p in all_points) for i in range(3)],'maximum':[max(p[i] for p in all_points) for i in range(3)]}
(out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest,indent=2))
