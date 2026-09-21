import json, math, struct
import numpy as np
from pathlib import Path
from PIL import Image, ImageDraw

OUT = Path(__file__).parent
materials = [('Limestone', (0.68,0.64,0.54)), ('Setback trim',(0.82,0.78,0.67)), ('Windows',(0.18,0.25,0.28)), ('Aluminum spire',(0.67,0.72,0.73)), ('Entrance',(0.28,0.32,0.31))]
meshes = [[] for _ in materials]
def quad(points, mat):
    a,b,c,d = points
    u=[b[i]-a[i] for i in range(3)]; v=[c[i]-a[i] for i in range(3)]
    n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
    length=math.sqrt(sum(x*x for x in n)); n=[x/length for x in n]
    meshes[mat].extend([(p,n) for p in (a,b,c,a,c,d)])
def box(w,d,y,h,mat=0,x=0,z=0):
    l,r=x-w/2,x+w/2; f,b=z+d/2,z-d/2; t=y+h
    for face in [[(l,y,f),(r,y,f),(r,t,f),(l,t,f)],[(r,y,b),(l,y,b),(l,t,b),(r,t,b)],[(r,y,f),(r,y,b),(r,t,b),(r,t,f)],[(l,y,b),(l,y,f),(l,t,f),(l,t,b)],[(l,t,f),(r,t,f),(r,t,b),(l,t,b)],[(l,y,b),(r,y,b),(r,y,f),(l,y,f)]]: quad(face,mat)
def tier(w,d,y,h):
    box(w,d,y,h)
    box(w+.12,d+.12,y+h-.14,.14,1)
    for axis,span in [('x',w),('z',d)]:
        count=max(2,round(span/.6))
        for col in range(count):
            center=-span/2+(col+.5)*span/count
            for row in range(max(0,int((h-.35)/.65))):
                bottom=y+.23+row*.65; top=bottom+.36; a=center-.11; b=center+.11
                for sign in [-1,1]:
                    if axis=='x':
                        fixed=sign*(d/2+.006); pts=[(a,bottom,fixed),(b,bottom,fixed),(b,top,fixed),(a,top,fixed)]
                    else:
                        fixed=sign*(w/2+.006); pts=[(fixed,bottom,b),(fixed,bottom,a),(fixed,top,a),(fixed,top,b)]
                    quad(pts if sign==1 else pts[::-1],2)
def taper(radius,upper,y,h,sides=8,mat=3):
    for i in range(sides):
        a=2*math.pi*i/sides; b=2*math.pi*(i+1)/sides
        quad([(radius*math.cos(b),y,radius*math.sin(b)),(radius*math.cos(a),y,radius*math.sin(a)),(upper*math.cos(a),y+h,upper*math.sin(a)),(upper*math.cos(b),y+h,upper*math.sin(b))],mat)
    # Flat caps preserve a watertight solid.
    for level,r,reverse in [(y,radius,False),(y+h,upper,True)]:
        for i in range(1,sides-1):
            p=[(r*math.cos(2*math.pi*j/sides),level,r*math.sin(2*math.pi*j/sides)) for j in [0,i,i+1]]
            if reverse: p.reverse()
            n=(0,1 if reverse else -1,0)
            meshes[mat].extend((v,n) for v in p)

box(10,7.4,0,.25,1)
tier(9.5,6.9,.25,3.6)
tier(8.3,6.0,3.85,2.2)
tier(7.0,5.3,6.05,2.3)
tier(5.8,4.7,8.35,3.1)
tier(4.8,4.1,11.45,18.5)
tier(4.3,3.7,29.95,1.8)
box(4.6,4.0,31.75,.22,1)
tier(3.3,2.9,31.97,1.35)
tier(2.55,2.3,33.32,1.3)
tier(1.9,1.75,34.62,1.3)
box(1.6,1.5,35.92,.25,1)
taper(.72,.5,36.17,1.8)
taper(.5,.27,37.97,1.2)
taper(.22,.14,39.17,2.4)
taper(.14,.035,41.57,2.73)
box(1.25,.08,.25,1.45,4,z=3.495)
box(1.5,.32,1.7,.15,1,z=3.52)

# Portable glTF binary, Y up, meters (a stylized 1:10 miniature).
blob=bytearray(); views=[]; accessors=[]; primitives=[]
def accessor(values,kind):
    offset=len(blob)
    for v in values: blob.extend(struct.pack('<'+'f'*len(v),*v))
    views.append({'buffer':0,'byteOffset':offset,'byteLength':len(blob)-offset,'target':34962})
    entry={'bufferView':len(views)-1,'componentType':5126,'count':len(values),'type':kind}
    if kind=='VEC3': entry.update(min=[min(v[i] for v in values) for i in range(3)],max=[max(v[i] for v in values) for i in range(3)])
    accessors.append(entry); return len(accessors)-1
for material, vertices in enumerate(meshes):
    primitives.append({'attributes':{'POSITION':accessor([v[0] for v in vertices],'VEC3'),'NORMAL':accessor([v[1] for v in vertices],'VEC3')},'material':material})
doc={'asset':{'version':'2.0','generator':'Low-poly Empire State Building'},'scene':0,'scenes':[{'nodes':[0]}],'nodes':[{'mesh':0,'name':'Empire State Building'}],'meshes':[{'primitives':primitives}],'materials':[{'name':name,'pbrMetallicRoughness':{'baseColorFactor':[*color,1],'metallicFactor':.35 if i==3 else 0,'roughnessFactor':.72}} for i,(name,color) in enumerate(materials)],'buffers':[{'byteLength':len(blob)}],'bufferViews':views,'accessors':accessors}
js=json.dumps(doc,separators=(',',':')).encode(); js+=b' '*((-len(js))%4)
glb=struct.pack('<III',0x46546c67,2,28+len(js)+len(blob))+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(blob),0x004e4942)+blob
(OUT/'empire-state-building.glb').write_bytes(glb)
obj=['mtllib empire-state-building.mtl','o Empire_State_Building']; index=1
for material,vertices in enumerate(meshes):
    obj.append('usemtl '+materials[material][0].replace(' ','_'))
    for p,n in vertices: obj.append('v '+' '.join(f'{v:.5f}' for v in p))
    for i in range(0,len(vertices),3): obj.append(f'f {index+i} {index+i+1} {index+i+2}')
    index+=len(vertices)
(OUT/'empire-state-building.obj').write_text('\n'.join(obj)+'\n')
(OUT/'empire-state-building.mtl').write_text('\n'.join(f'newmtl {name.replace(" ","_")}\nKd {r} {g} {b}\n' for name,(r,g,b) in materials))

# Painter-rendered orthographic preview from the same triangles.
im=Image.new('RGB',(1200,1200),'#e9e7df'); draw=ImageDraw.Draw(im)
yaw=.65; pitch=.22; scale=23
def project(p):
    x,y,z=p; a=x*math.cos(yaw)+z*math.sin(yaw); depth=-x*math.sin(yaw)+z*math.cos(yaw)
    return (600+a*scale,1110-(y*math.cos(pitch)-depth*math.sin(pitch))*scale),y*math.sin(pitch)+depth*math.cos(pitch)
triangles=[]
for material,vertices in enumerate(meshes):
    for i in range(0,len(vertices),3):
        tri=vertices[i:i+3]; projected=[project(p) for p,n in tri]; n=tri[0][1]
        light=.70+.30*max(0,n[0]*.35+n[1]*.8+n[2]*.48)
        color=tuple(round(255*c*light) for c in materials[material][1])
        triangles.append((projected,color))
draw.ellipse((455,1070,775,1150),fill='#d4d2c9')
pixels=np.array(im); depths=np.full((1200,1200),-np.inf)
for projected,color in triangles:
    pts=np.array([p[0] for p in projected]); zs=np.array([p[1] for p in projected])
    lo=np.maximum(np.floor(pts.min(axis=0)).astype(int),0); hi=np.minimum(np.ceil(pts.max(axis=0)).astype(int),1199)
    if np.any(hi<lo): continue
    xx,yy=np.meshgrid(np.arange(lo[0],hi[0]+1)+.5,np.arange(lo[1],hi[1]+1)+.5)
    (ax,ay),(bx,by),(cx,cy)=pts
    den=(by-cy)*(ax-cx)+(cx-bx)*(ay-cy)
    if abs(den)<1e-10: continue
    wa=((by-cy)*(xx-cx)+(cx-bx)*(yy-cy))/den
    wb=((cy-ay)*(xx-cx)+(ax-cx)*(yy-cy))/den; wc=1-wa-wb
    zz=wa*zs[0]+wb*zs[1]+wc*zs[2]
    region=depths[lo[1]:hi[1]+1,lo[0]:hi[0]+1]
    mask=(wa>=0)&(wb>=0)&(wc>=0)&(zz>region)
    region[mask]=zz[mask]; pixels[lo[1]:hi[1]+1,lo[0]:hi[0]+1][mask]=color
im=Image.fromarray(pixels)
im.save(OUT/'preview.png')
data=[]
for material,vertices in enumerate(meshes):
    for p,n in vertices: data.extend([*p,*n,*materials[material][1]])
template=(OUT/'viewer-template.html').read_text()
(OUT/'preview.html').write_text(template.replace('MODEL_DATA',json.dumps(data,separators=(',',':'))).replace('TRIANGLE_COUNT',str(sum(len(m) for m in meshes)//3)))
print(json.dumps({'triangles':sum(len(m) for m in meshes)//3,'glb_bytes':len(glb),'height':44.3}))
