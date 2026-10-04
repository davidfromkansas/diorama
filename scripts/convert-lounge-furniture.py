#!/usr/bin/env python3
"""Convert requested Eames/Luva official DXFs to centred metre Y-up OBJ.
Usage: python convert-lounge-furniture.py INPUT_DIR OUTPUT_DIR
Input DWGs are converted with LibreDWG dwg2dxf; ezdxf reads explicit inch units.
"""
import sys,json,hashlib
from pathlib import Path
from collections import defaultdict
import ezdxf
src,out=map(Path,sys.argv[1:]); out.mkdir(parents=True,exist_ok=True)
manifest={}
for source,name in [('eames','EamesLounge'),('luva','LuvaCorner')]:
 d=ezdxf.readfile(src/(source+'.dxf')); assert d.header.get('$INSUNITS')==1
 groups=defaultdict(list)
 for e in d.modelspace():
  if e.dxftype()!='3DFACE':continue
  # The official Classic download includes a separate ottoman at CAD X > 23 in.
  # The chair ends below X = 14 in; exclude only that disconnected ottoman.
  if source=='eames' and all(v.x > 20 for v in e.wcs_vertices()):continue
  face=[]
  for v in e.wcs_vertices():
   x,y,z=[float(c)*.0254 for c in v]
   p=(y,z,x) if source=='eames' else (x,z,-y)
   if p not in face:face.append(p)
  if len(face)>=3:groups[e.dxf.layer].append(face)
 points=[p for faces in groups.values() for face in faces for p in face]
 lo=[min(p[i] for p in points) for i in range(3)]; hi=[max(p[i] for p in points) for i in range(3)]
 center=[(lo[0]+hi[0])/2,lo[1],(lo[2]+hi[2])/2]
 lines=['# Official CAD, metres, Y up.',f'mtllib {name}.mtl']; mats=[]; index=1; triangles=0
 for layer,faces in groups.items():
  lines += ['o '+layer,'usemtl '+layer]; lookup={}
  color=(.86,.82,.74) if source=='luva' and 'FABRIC' in layer else ((.28,.14,.065) if 'SHELL' in layer else (.08,.075,.07))
  mats += ['newmtl '+layer,'Kd '+' '.join(map(str,color)),'Ks 0.05 0.05 0.05','Ns 20','']
  for face in faces:
   ids=[]
   for p in face:
    key=tuple(round(p[i]-center[i],7) for i in range(3))
    if key not in lookup:
     lookup[key]=index; index+=1; lines.append('v '+' '.join(map(str,key)))
    ids.append(lookup[key])
   for i in range(1,len(ids)-1):lines.append(f'f {ids[0]} {ids[i]} {ids[i+1]}'); triangles+=1
 (out/(name+'.obj')).write_text('\n'.join(lines)+'\n'); (out/(name+'.mtl')).write_text('\n'.join(mats))
 manifest[name]={'source':source+'.dwg','sha256':hashlib.sha256((src/(source+'.dwg')).read_bytes()).hexdigest(),'dimensions':[hi[i]-lo[i] for i in range(3)],'triangles':triangles}
(out/'LoungeCAD.json').write_text(json.dumps(manifest,indent=2)+'\n');print(json.dumps(manifest,indent=2))
