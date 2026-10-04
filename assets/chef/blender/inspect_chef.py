import bpy, bmesh, sys, os, math
from mathutils import Vector
argv = sys.argv[sys.argv.index("--")+1:]
src, outdir = argv[0], argv[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
ob = [o for o in bpy.context.scene.objects if o.type=='MESH'][0]
print("OBJ", ob.name, ob.location, ob.rotation_euler, ob.scale)
me = ob.data
mw = ob.matrix_world
vs = [mw @ v.co for v in me.vertices]
for i,a in enumerate("XYZ"):
    print(a, min(v[i] for v in vs), max(v[i] for v in vs))
print("verts", len(me.vertices), "faces", len(me.polygons))
bm = bmesh.new(); bm.from_mesh(me)
bm.verts.ensure_lookup_table()
# islands
seen=set(); islands=[]
for v in bm.verts:
    if v.index in seen: continue
    stack=[v]; seen.add(v.index); isl=[]
    while stack:
        x=stack.pop(); isl.append(x.index)
        for e in x.link_edges:
            o=e.other_vert(x)
            if o.index not in seen: seen.add(o.index); stack.append(o)
    islands.append(isl)
islands.sort(key=len, reverse=True)
print("islands", len(islands))
for isl in islands[:30]:
    pts=[vs[i] for i in isl]
    mn=[min(p[k] for p in pts) for k in range(3)]; mx=[max(p[k] for p in pts) for k in range(3)]
    print(len(isl), [round(x,3) for x in mn], [round(x,3) for x in mx])
nm = sum(1 for e in bm.edges if not e.is_manifold)
print("non-manifold edges", nm, "boundary", sum(1 for e in bm.edges if e.is_boundary))
for m in me.materials:
    print("MAT", m.name)
    for n in m.node_tree.nodes:
        print("  ", n.type, n.name, getattr(getattr(n,'image',None),'name',None), getattr(getattr(getattr(n,'image',None),'colorspace_settings',None),'name',None))
    for l in m.node_tree.links:
        print("  LINK", l.from_node.name, l.from_socket.name, "->", l.to_node.name, l.to_socket.name)
# renders
scene=bpy.context.scene
scene.render.engine='BLENDER_EEVEE' if 'BLENDER_EEVEE' in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items] else 'BLENDER_EEVEE_NEXT'
scene.render.resolution_x=600; scene.render.resolution_y=800
w=bpy.data.worlds.new("W"); scene.world=w; w.use_nodes=True
w.node_tree.nodes['Background'].inputs[1].default_value=1.0
cam=bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); scene.collection.objects.link(cam); scene.camera=cam
cam.data.type='ORTHO'; cam.data.ortho_scale=2.2
sun=bpy.data.objects.new("sun", bpy.data.lights.new("sun",'SUN')); scene.collection.objects.link(sun); sun.rotation_euler=(0.6,0.2,0.5); sun.data.energy=3
def shot(name, loc):
    cam.location=Vector(loc)
    d=Vector((0,0,0))-cam.location
    cam.rotation_euler=d.to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=os.path.join(outdir,name+".png")
    bpy.ops.render.render(write_still=True)
for n,l in [("front_negY",(0,-5,0)),("back_posY",(0,5,0)),("side_posX",(5,0,0)),("side_negX",(-5,0,0)),("bottom",(0,0,-5)),("top",(0,0.01,5))]:
    shot(n,l)
