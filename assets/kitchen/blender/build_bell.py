"""Builds the kitchen's service gong (the "bell" station, where chefs that need you call for
you): a hammered bronze gong hung on cords in a deep-green lacquered frame with brass caps and
ball finials, a "SERVICE" enamel plaque on the beam, on bronze feet. Exports bell.glb.

    Blender -b --factory-startup -P build_bell.py -- <out.glb> [review_dir]

Units, origin and axes as for the range (kitchen_kit.py): origin at the centre of the station's
footprint on the kitchen floor; Blender -y faces the camera (the gong's struck face).

Contract with the app (see README.md):
- footprint x -0.9..0.9, y -0.3..0.3, nothing outside it;
- the gong's face centre at GONG_Z above the floor (where a chef's mallet lands, see
  `KitchenLayout.gongStrike`), its face in the plane y = -GONG_T / 2;
- the gong (materials `gong_*`) swings about the empty `gong_pivot`: the app hangs it there and
  sets it shivering when struck.
"""
import bpy, math, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kitchen_kit import *
import french_back as F

GONG_R, GONG_T, GONG_Z = 0.55, 0.035, 1.18     # face centre 1.29 above world 0, where the mallet lands
POST_X, POST_TOP = 0.8, 2.5
BEAM_Z = POST_TOP + 0.05
PIVOT_Z = BEAM_Z - 0.06

BRONZE = mat("gong_bronze", "9a6a32", 0.38, 0.85)
RINGS = mat("gong_rings", "6f4a22", 0.5, 0.8)
BOSS = mat("gong_boss", "d4a24e", 0.22, 0.95)
CORD = mat("gong_cord", "6b1f1a", 0.9)
FELT = mat("mallet_felt", "c8a878", 0.95)
HANDLE = mat("mallet_handle", "3a2414", 0.6)

def gong():
    rot = (math.pi / 2, 0, 0)                      # disc faces -y
    cyl(GONG_R, GONG_T, (0, 0, GONG_Z), BRONZE, 64, rot=rot, bevel=0.006)
    torus(GONG_R, 0.022, (0, 0, GONG_Z), BRONZE, rot=rot, seg=64, ring=10)             # rolled rim
    for r in (0.42, 0.31, 0.21):                                                         # hammered rings
        torus(r, 0.006, (0, -GONG_T / 2, GONG_Z), RINGS, rot=rot, seg=48, ring=6)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.13, segments=32, ring_count=16, location=(0, -GONG_T / 2, GONG_Z))
    b = bpy.context.active_object; b.scale = (1, 0.4, 1); finish(b, BOSS, smooth=True)  # polished boss
    # Cords from the beam to two eyes on the rim.
    for x in (-0.2, 0.2):
        top = (x * 1.6, 0, PIVOT_Z)
        eye = (x, 0, GONG_Z + math.sqrt(GONG_R ** 2 - x ** 2) - 0.01)
        rod(top, eye, 0.008, CORD, 8)
        torus(0.018, 0.005, eye, BRONZE, rot=(0, math.pi / 2, 0), seg=12, ring=5)

def frame():
    for sx in (-1, 1):
        x = sx * POST_X
        box((0.2, 0.56, 0.07), (x, 0, 0.035), F.BRONZE, 0.012, 2)                      # foot
        box((0.14, 0.14, 0.06), (x, 0, 0.1), F.BRASS, 0.008, 2)                          # collar
        box((0.09, 0.09, POST_TOP - 0.13), (x, 0, 0.13 + (POST_TOP - 0.13) / 2), F.LACQUER, 0.01, 2)
        box((0.11, 0.11, 0.035), (x, 0, 0.95), F.BRASS, 0.005, 1)                        # brass band
        box((0.13, 0.13, 0.05), (x, 0, POST_TOP), F.BRASS, 0.006, 2)                     # cap
        cyl(0.045, 0.06, (sx * 0.86, 0, BEAM_Z + 0.075), F.BRASS, 16)                    # finial stem
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.05, segments=20, ring_count=10, location=(sx * 0.86, 0, BEAM_Z + 0.13))
        finish(bpy.context.active_object, F.BRASS_BRIGHT, smooth=True)
        # A curved brass knee brace in the corner under the beam.
        cx, cz = x - sx * 0.2, BEAM_Z - 0.25
        for k in range(6):
            a0, a1 = k / 6 * math.pi / 2, (k + 1) / 6 * math.pi / 2
            p = lambda a: (cx + sx * 0.2 * math.cos(a), -0.05, cz + 0.2 * math.sin(a))
            rod(p(a0), p(a1), 0.012, F.BRASS, 8)
    box((1.76, 0.12, 0.1), (0, 0, BEAM_Z), F.LACQUER, 0.012, 2)                        # beam
    box((1.8, 0.13, 0.02), (0, 0, BEAM_Z + 0.06), F.BRASS, 0.004, 1)
    F.plaque("SERVICE", (0, -0.07, BEAM_Z), 0.5, 0.08)
    # A spare mallet resting in brass hooks on the right post.
    hx, hy = POST_X, -0.085                       # on the post's front face
    for z in (0.78, 1.18):
        torus(0.022, 0.006, (hx, hy + 0.01, z), F.BRASS, rot=(math.pi / 2, 0, 0), seg=12, ring=5)
    rod((hx, hy, 0.62), (hx, hy, 1.24), 0.013, HANDLE, 10)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.06, segments=16, ring_count=10, location=(hx, hy, 0.6))
    finish(bpy.context.active_object, FELT, smooth=True)

def build():
    for o in list(bpy.context.scene.objects): bpy.data.objects.remove(o, do_unlink=True)
    gong(); frame()
    root, merged, stats = assemble("bell", [anchor("gong_pivot", (0, 0, PIVOT_Z))])
    print("BELL", stats)
    return root, merged

VIEWS = (("kitchen_view", (0, -4.5, 6.2), (0, 0, 1.0), (1200, 1000)),
         ("front", (1.3, -3.0, 1.6), (0, 0, 1.1), (1200, 1200)))

if __name__ == "__main__" and "--" in sys.argv:
    args = sys.argv[sys.argv.index("--") + 1:]
    root, meshes = build()
    export(args[0], root, meshes)
    print("BELL exported", args[0])
    if len(args) > 1: review(args[1], VIEWS)
