"""Rebuild with Blender --background --python assets/library/export_library.py.
Original Diorama artwork. Model units are metres, Z up; USD exports Y up.
"""
import bpy, math, os, random, json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'Sources/DioramaApp/Resources/Library'
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
random.seed(23)
bpy.context.preferences.filepaths.save_version = 0
def mat(name, hex):
    srgb = [int(hex[i:i+2],16)/255 for i in (0,2,4)]
    rgb = [v/12.92 if v <= .04045 else ((v+.055)/1.055)**2.4 for v in srgb]
    m=bpy.data.materials.new(name); m.diffuse_color=(*rgb,1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*rgb,1); p.inputs['Roughness'].default_value=.78
    return m
wood=mat('Honey oak','BD8050'); edge=mat('Honey edges','DFA967'); cream=mat('Warm cream','F4E4C5'); dark=mat('Shelf recess','865535'); brass=mat('Brass','D5AC59'); peach=mat('Peach','DE9A87'); sage=mat('Sage','9DB79D'); blue=mat('Dusty blue','8FAFC6'); mauve=mat('Mauve','B79DB9'); ink=mat('Ink','474C59')
colors=[sage,blue,peach,mauve,cream]
def box(name, loc, dims, material, bevel=.05):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc); o=bpy.context.object; o.name=name; o.dimensions=dims
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        mod=o.modifiers.new('Soft toy edges','BEVEL'); mod.width=bevel; mod.segments=3
        bpy.context.view_layer.objects.active=o; bpy.ops.object.modifier_apply(modifier=mod.name)
    o.data.materials.append(material)
    return o
def sphere(name,loc,scale,material):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=10,location=loc); o=bpy.context.object; o.name=name; o.scale=scale; o.data.materials.append(material)
    for p in o.data.polygons:p.use_smooth=True
    return o
def book(name,x,y,z,w,h,c):
    box(name+'_pages',(x,y,z+h/2),(w-.055,.37,h-.07),cream,.018)
    for dx in [-w/2,w/2]:box(name+'_cover',(x+dx,y,z+h/2),(.045,.44,h),c,.015)
    box(name+'_spine',(x,y-.23,z+h/2),(w+.04,.06,h),c,.028)
    for dz in [.16,h-.15]:box(name+'_band',(x,y-.265,z+dz),(w+.045,.015,.032),brass,.007)
    sphere(name+'_emblem',(x,y-.28,z+h*.55),(.04,.013,.05),cream)
# Floor rug, two low cabinets, with explicit shadows/recesses baked into material choices.
box('rug_border',(0,-.45,.045),(5.8,3.65,.09),cream,.22)
box('rug_sage',(0,-.45,.10),(5.45,3.3,.065),sage,.2)
for x in [-1.37,1.37]:
    box('shelf_back',(x,.67,1.47),(2.42,.18,2.78),dark,.10)
    for sx in [-1.16,1.16]:box('shelf_upright',(x+sx,.31,1.47),(.19,.88,2.85),edge,.08)
    for z in [.18,1.43,2.85]:box('shelf_plank',(x,.28,z),(2.53,1.03,.18),edge,.07)
    for row,z in enumerate([.29,1.54]):
        bx=x-.92
        for i in range(6):
            w=random.uniform(.22,.3); h=random.uniform(.67,.96)
            book('shelf_book_%s_%s_%s'%(x,row,i),bx,.18,z,w,h,colors[(i+row+int(x>0)*2)%5]);bx+=.34
    # Tiny arched-like crown, friendly owl bookend.
    sphere('shelf_crown',(x,.34,2.96),(.30,.12,.15),cream)
# table in front, exposed centre for selected book
for x in [-.64,.64]:
    for y in [-1.45,-.72]:box('table_leg',(x,y,.41),(.15,.15,.72),wood,.055)
box('reading_table',(0,-1.10,.85),(1.78,1.10,.18),edge,.16)
# stool
for x in [1.1,1.55]:box('stool_leg',(x,-1.72,.26),(.12,.12,.42),wood,.04)
box('stool_cushion',(1.32,-1.72,.5),(.72,.60,.22),peach,.12)
# mushroom lamp
box('lamp_foot',(-.61,-1.04,.99),(.28,.29,.08),brass,.05)
sphere('lamp_stem',(-.61,-1.04,1.2),(.095,.095,.25),cream)
sphere('mushroom_cap',(-.61,-1.04,1.43),(.30,.29,.16),peach)
for dx,dy in [(-.1,-.14),(.13,-.06),(-.04,.11)]:sphere('lamp_spot',(-.61+dx,-1.04+dy,1.555),(.05,.045,.015),cream)
# ladder at left, front of shelf
for x in [-2.30,-1.77]:
    o=box('ladder_rail',(x,-.65,.99),(.10,.12,1.93),wood,.04);o.rotation_euler.x=-.14
for z in [.3,.7,1.1,1.5]:box('ladder_rung',(-2.035,-.65,z),(.64,.13,.10),cream,.035)
# chunky bookends atop cabinets
for x in [-2.1,2.1]:
    sphere('bookend_owl',(x,.18,3.12),(.22,.18,.25),sage)
    for dx in [-.075,.075]:
        sphere('owl_eye',(x+dx,.005,3.17),(.052,.025,.064),cream)
        sphere('owl_pupil',(x+dx,-.02,3.17),(.019,.01,.026),ink)
# Save reusable library before book exports.
# Avoid requiring exporter-specific orientation options: set through inspected RNA.
def usd(name):
    props=bpy.ops.wm.usd_export.get_rna_type().properties.keys()
    kwargs=dict(filepath=str(OUT/name),export_animation=False,export_materials=True)
    if 'convert_orientation' in props:kwargs.update(convert_orientation=True,export_global_forward_selection='NEGATIVE_Z',export_global_up_selection='Y')
    bpy.ops.wm.usd_export(**kwargs)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'assets/library/chibi-library.blend'))
tri=sum(len(p.vertices)-2 for o in bpy.context.scene.objects if o.type=='MESH' for p in o.data.polygons)
assert tri<50000,tri
usd('ChibiLibrary.usdz')
for o in list(bpy.data.objects):bpy.data.objects.remove(o,do_unlink=True)
book('display_book',0,0,0,.68,.95,blue)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'assets/library/closed-book.blend'));usd('ClosedBook.usdz')
for o in list(bpy.data.objects):bpy.data.objects.remove(o,do_unlink=True)
for x,angle in [(-.31,-.12),(.31,.12)]:
    o=box('open_cover',(x,0,.06),(.64,.90,.08),blue,.025);o.rotation_euler.y=angle
    o=box('open_pages',(x,0,.12),(.59,.84,.07),cream,.018);o.rotation_euler.y=angle
box('open_spine',(0,0,.05),(.07,.91,.08),blue,.02)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'assets/library/open-book.blend'));usd('OpenBook.usdz')
(ROOT/'assets/library/metrics.json').write_text(json.dumps({'alcove_triangles':tri,'textures':0},indent=2)+'\n')
print('LIBRARY_TRIANGLES',tri)
