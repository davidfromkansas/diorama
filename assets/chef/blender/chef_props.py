"""Simple props sized for the tiny chef, plus the rules that fit their hand attachments.

Every prop's origin is its grip/attach point. Props are built in Blender world axes
(Z up, chef faces -Y) and exported as separate nodes in chef-props.glb.
"""
import bpy, bmesh, math
from mathutils import Vector, Matrix, Euler, Quaternion
import chef_anims as A

FITS = {}


def _mat(name, rgb, rough=0.6, metal=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m


def _obj(name, parts):
    """parts: list of (kind, size/params, location, material). Joined into one mesh."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    mats = []
    for kind, p, loc, mat in parts:
        if mat not in mats:
            mats.append(mat)
        mi = mats.index(mat)
        before = set(bm.faces)
        if kind == "box":
            r = bmesh.ops.create_cube(bm, size=1.0)
            bmesh.ops.scale(bm, vec=Vector(p), verts=r["verts"])
            bmesh.ops.translate(bm, vec=Vector(loc), verts=r["verts"])
        elif kind == "cyl":
            rad, depth, seg = p[:3]
            r = bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=rad, radius2=p[3] if len(p) > 3 else rad, depth=depth)
            if len(p) > 4:
                bmesh.ops.rotate(bm, cent=Vector(), matrix=Matrix.Rotation(p[4][1], 3, p[4][0]), verts=r["verts"])
            bmesh.ops.translate(bm, vec=Vector(loc), verts=r["verts"])
        elif kind == "sphere":
            r = bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=1.0)
            bmesh.ops.scale(bm, vec=Vector(p), verts=r["verts"])
            bmesh.ops.translate(bm, vec=Vector(loc), verts=r["verts"])
        for f in set(bm.faces) - before:
            f.material_index = mi
            f.smooth = kind != "box"
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def build_props():
    paper = _mat("prop_paper", (0.95, 0.92, 0.82), 0.8)
    ink = _mat("prop_ink", (0.25, 0.22, 0.35), 0.8)
    cover = _mat("prop_book_cover", (0.62, 0.16, 0.12), 0.7)
    steel = _mat("prop_steel", (0.86, 0.88, 0.9), 0.32, 0.3)  # low metalness: reads as steel without an env map
    wood = _mat("prop_wood", (0.55, 0.34, 0.17), 0.7)
    darkwood = _mat("prop_handle", (0.22, 0.13, 0.07), 0.6)
    carrot = _mat("prop_carrot", (0.95, 0.45, 0.08), 0.5)
    leaf = _mat("prop_leaf", (0.25, 0.6, 0.2), 0.6)
    plate = _mat("prop_plate", (0.97, 0.97, 0.95), 0.3)
    tomato = _mat("prop_tomato", (0.85, 0.15, 0.1), 0.4)
    bun = _mat("prop_bun", (0.85, 0.6, 0.28), 0.6)
    potm = _mat("prop_pot", (0.3, 0.32, 0.36), 0.4, 0.3)
    soup = _mat("prop_soup", (0.9, 0.55, 0.15), 0.3)
    out = {}
    # Recipe clipboard, gripped at its near right-hand corner (origin) and extending to -X / +Z.
    # Printed on both faces so it reads from the overhead camera whichever way it tilts.
    out["prop_recipe_card"] = _obj("prop_recipe_card", [
        ("box", (0.34, 0.012, 0.27), (-0.175, 0, 0.135), wood),
        ("box", (0.07, 0.03, 0.03), (-0.175, 0, 0.26), steel),
        *[part for side in (1, -1) for part in (
            ("box", (0.30, 0.004, 0.22), (-0.175, 0.008 * side, 0.125), paper),
            ("box", (0.24, 0.003, 0.04), (-0.175, 0.011 * side, 0.205), cover),
            *[("box", (0.24 - 0.06 * (i % 2), 0.003, 0.015), (-0.175, 0.011 * side, 0.15 - i * 0.035), ink) for i in range(4)],
        )],
    ])
    out["prop_cookbook"] = _obj("prop_cookbook", [
        ("box", (0.17, 0.24, 0.012), (-0.085, 0, -0.006), cover),
        ("box", (0.17, 0.24, 0.012), (-0.255, 0, -0.006), cover),
        ("box", (0.155, 0.22, 0.02), (-0.088, 0, 0.008), paper),
        ("box", (0.155, 0.22, 0.02), (-0.252, 0, 0.008), paper),
        *[("box", (0.10, 0.008, 0.002), (-0.09 - 0.165 * (i // 4), 0.07 - (i % 4) * 0.045, 0.019), ink) for i in range(8)],
    ])
    # Chunky cartoon chef's knife (Overcooked-style proportions): the handle runs back through
    # the fist and its butt pokes out behind the mitten; the blade leaves the thumb side.
    out["prop_knife"] = _obj("prop_knife", [
        ("box", (0.034, 0.12, 0.038), (0, 0.05, 0), darkwood),
        ("box", (0.038, 0.012, 0.042), (0, 0.112, 0), steel),
        *[("cyl", (0.007, 0.040, 8, 0.007, ("Y", math.pi / 2)), (0, y, 0), steel) for y in (0.02, 0.075)],
        ("box", (0.009, 0.20, 0.072), (0, -0.10, -0.014), steel),
        ("box", (0.012, 0.02, 0.052), (0, -0.004, -0.004), steel),
    ])
    out["prop_spoon"] = _obj("prop_spoon", [
        ("cyl", (0.013, 0.17, 8, 0.013, ("X", math.pi / 2)), (0, -0.045, 0), wood),
        ("sphere", (0.034, 0.044, 0.014), (0, -0.15, 0.004), wood),
    ])
    out["prop_ingredient"] = _obj("prop_ingredient", [
        ("cyl", (0.03, 0.17, 12, 0.008, ("Y", math.pi / 2)), (0.02, 0, 0.03), carrot),
        ("cyl", (0.012, 0.05, 6, 0.004, ("Y", math.pi / 2)), (0.13, 0, 0.03), leaf),
        *[("cyl", (0.028, 0.01, 12, 0.028, ("Y", math.pi / 2)), (-0.10 - 0.016 * i, 0, 0.028), carrot) for i in range(3)],
    ])
    out["prop_cutting_board"] = _obj("prop_cutting_board", [
        ("box", (0.40, 0.24, 0.02), (0, 0, 0.01), wood),
    ])
    out["prop_plate"] = _obj("prop_plate", [
        ("cyl", (0.12, 0.012, 24, 0.12), (0, 0, 0.006), plate),
        ("cyl", (0.135, 0.01, 24, 0.12), (0, 0, 0.016), plate),
        ("sphere", (0.06, 0.06, 0.022), (0, 0, 0.032), bun),
        ("cyl", (0.055, 0.012, 16, 0.055), (0, 0, 0.05), tomato),
        ("sphere", (0.06, 0.06, 0.03), (0, 0, 0.065), bun),
    ])
    out["prop_pot"] = _obj("prop_pot", [
        ("cyl", (0.13, 0.14, 24, 0.13), (0, 0, 0.07), potm),
        ("cyl", (0.12, 0.01, 24, 0.12), (0, 0, 0.125), soup),
        ("box", (0.07, 0.025, 0.02), (0.16, 0, 0.12), potm),
        ("box", (0.07, 0.025, 0.02), (-0.16, 0, 0.12), potm),
    ])
    # Order ticket: a small paper slip gripped at its bottom edge (origin).
    out["prop_ticket"] = _obj("prop_ticket", [
        ("box", (0.16, 0.004, 0.22), (0, 0, 0.11), paper),
        *[("box", (0.12 - 0.04 * (i % 2), 0.005, 0.012), (0, 0, 0.18 - i * 0.03), ink) for i in range(5)],
    ])
    # Coffee mug held around its body (origin at the grip), handle on the outside.
    mug = _mat("prop_mug", (0.93, 0.9, 0.84), 0.4)
    coffee = _mat("prop_coffee", (0.28, 0.16, 0.08), 0.3)
    out["prop_mug"] = _obj("prop_mug", [
        ("cyl", (0.05, 0.11, 16, 0.05), (0, 0, 0.02), mug),
        ("cyl", (0.044, 0.004, 16, 0.044), (0, 0, 0.074), coffee),
        ("box", (0.015, 0.02, 0.06), (-0.06, 0, 0.025), mug),
    ])
    # Cloche lifted by its knob (origin), dome hanging below.
    out["prop_cloche"] = _obj("prop_cloche", [
        ("sphere", (0.13, 0.13, 0.08), (0, 0, -0.07), steel),
        ("cyl", (0.022, 0.03, 10, 0.022), (0, 0, -0.005), steel),
    ])
    return out


def _at(pos, rot):
    return Matrix.Translation(pos) @ rot.to_matrix().to_4x4()


def _card(S):
    # nearly flat, far edge slightly raised toward the chef's eyes; visible from overhead
    return _at(S.translation + Vector((0.03, 0.0, -0.01)), Euler((math.radians(72), 0, math.radians(14))))


def _book(S):
    return _at(S.translation + Vector((0.02, -0.03, 0.01)), Euler((math.radians(-22), 0, 0)))


KNIFE_GRIP_FROM_BUTT = 0.11  # the fist closes on the last couple of cm of the handle


def _knife(S):
    """Fist closes on the butt end of the handle, so most of the handle and the whole blade sit in
    front of the mitten and stay visible. Blade forward and a little inward, edge down, tip 5
    degrees low so the edge meets the board at the impact frame."""
    rot = Euler((math.radians(5), 0, math.radians(10)))
    D = _at(S.translation, rot)
    D.translation = D @ Vector((0, -KNIFE_GRIP_FROM_BUTT, 0))
    return D


def knife_edge_low(D):
    return min((D @ Vector((0, y, -0.05))).z for y in (-0.005, -0.10, -0.195))


MOUTH = Vector((-0.02, -0.395, 1.085))


def _spoon(S):
    d = (MOUTH - S.translation).normalized()
    q = Vector((0, -1, 0)).rotation_difference(d)
    return _at(S.translation, q)


def _plate(S):
    return _at(S.translation + Vector((0, -0.02, -0.006)), Quaternion())


def _ticket(S):
    # upright slip tilted back toward the chef's eyes
    return _at(S.translation + Vector((-0.02, -0.02, 0.0)), Euler((math.radians(-60), 0, math.radians(-8))))


def _mug(S):
    return _at(S.translation + Vector((0.0, -0.04, -0.01)), Quaternion())


def _cloche(S):
    return _at(S.translation + Vector((0.0, -0.02, -0.02)), Quaternion())


# (prop, socket, clip, time_s, desired_world_matrix_fn)
ATTACH_FITS = [
    ("prop_recipe_card", "socket_hand.L", "planning_recipe", 1.0, _card),
    ("prop_cookbook", "socket_hand.L", "researching_book", 0.0, _book),
    ("prop_knife", "socket_hand.R", "working_chop", 2 / 30, _knife),
    ("prop_spoon", "socket_hand.R", "testing_dish", 0.75, _spoon),
    ("prop_plate", "socket_carry", "carry_idle", 0.0, _plate),
    ("prop_ticket", "socket_hand.L", "read_ticket", 0.0, _ticket),
    ("prop_mug", "socket_hand.R", "sit_sip", 0.0, _mug),
    ("prop_cloche", "socket_hand.R", "cover_dish", 0.35, _cloche),
]


def record_fit(prop, clip, socket, off):
    FITS[(prop, clip)] = (socket, off)
