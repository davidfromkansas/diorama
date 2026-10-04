"""Skeleton, skin weights and authoring controls for the Meshy tiny chef.

All joint positions were measured from the supplied GLB (see docs/chef-rig-report.md).
Coordinates below are Blender world space AFTER the floor shift: Z up, the chef faces -Y,
the character's left side is +X. 1 Blender unit == 1 glTF unit; the chef is 1.90 units tall.
"""
import bpy
import bmesh
from mathutils import Vector, Matrix, Quaternion, Euler

# The source mesh is centred on its origin. Shift it so the soles sit on Z=0 and the
# point between the ankles sits on the origin. Recorded in the manifest.
FLOOR_SHIFT = Vector((0.0, 0.06, 0.950569))

ARMATURE_NAME = "chef_rig"
MESH_NAME = "chef_body"

def bone_table():
    """name -> (head, tail, parent, deform)"""
    t = {
        "root": ((0, 0, 0), (0, 0, 0.20), None, False),
        "hips": ((0, 0, 0.50), (0, 0, 0.68), "root", True),
        "spine": ((0, 0, 0.68), (0, -0.01, 0.82), "hips", True),
        "chest": ((0, -0.01, 0.82), (0, -0.02, 0.96), "spine", True),
        "neck": ((0, -0.02, 0.96), (0, -0.02, 1.02), "chest", True),
        "head": ((0, -0.02, 1.02), (0, -0.02, 1.46), "neck", True),
        "hat": ((0, 0.02, 1.46), (0, 0.04, 1.90), "head", True),
    }
    for sfx, s in (("L", 1.0), ("R", -1.0)):
        t[f"clavicle.{sfx}"] = ((0.06 * s, -0.01, 0.88), (0.245 * s, 0.0, 0.865), "chest", True)
        t[f"upperarm.{sfx}"] = ((0.25 * s, 0.01, 0.86), (0.44 * s, 0.01, 0.72), f"clavicle.{sfx}", True)
        t[f"forearm.{sfx}"] = ((0.44 * s, 0.01, 0.72), (0.545 * s, -0.02, 0.63), f"upperarm.{sfx}", True)
        t[f"hand.{sfx}"] = ((0.545 * s, -0.02, 0.63), (0.635 * s, -0.03, 0.53), f"forearm.{sfx}", True)
        t[f"thigh.{sfx}"] = ((0.15 * s, 0.0, 0.50), (0.165 * s, -0.015, 0.27), "hips", True)
        t[f"shin.{sfx}"] = ((0.165 * s, -0.015, 0.27), (0.17 * s, 0.0, 0.12), f"thigh.{sfx}", True)
        t[f"foot.{sfx}"] = ((0.17 * s, 0.0, 0.12), (0.19 * s, -0.20, 0.045), f"shin.{sfx}", True)
        t[f"toe.{sfx}"] = ((0.19 * s, -0.20, 0.045), (0.20 * s, -0.30, 0.045), f"foot.{sfx}", True)
        # Prop sockets: non-deforming, oriented to world axes (tail +Z, roll 0) so that in
        # glTF space their rest frame equals the model frame. Grip point = mitten centre.
        t[f"socket_hand.{sfx}"] = ((0.600 * s, -0.045, 0.575), (0.600 * s, -0.045, 0.625), f"hand.{sfx}", False)
        # Authoring controls (stripped from the runtime export).
        t[f"foot_ik.{sfx}"] = ((0.17 * s, 0.0, 0.12), (0.17 * s, -0.15, 0.12), "root", False)
        t[f"mch_foot.{sfx}"] = ((0.17 * s, 0.0, 0.12), (0.19 * s, -0.20, 0.045), f"foot_ik.{sfx}", False)
        t[f"knee_pole.{sfx}"] = ((0.165 * s, -0.60, 0.27), (0.165 * s, -0.65, 0.27), "root", False)
        t[f"hand_ik.{sfx}"] = ((0.545 * s, -0.02, 0.63), (0.545 * s, -0.07, 0.63), "root", False)
        t[f"elbow_pole.{sfx}"] = ((0.62 * s, 0.45, 0.70), (0.62 * s, 0.50, 0.70), "root", False)
        # World-space hand orientation control (blended in per clip, e.g. a steady knife grip)
        t[f"hand_aim.{sfx}"] = ((0.545 * s, -0.02, 0.63), (0.635 * s, -0.03, 0.53), "root", False)
    # Two-hand carry target; position refitted by fit_carry_socket() after the carry pose exists.
    # Two-hand carry target: constrained to the midpoint of the hand sockets with a level
    # orientation, then baked, so a plate held in both hands stays level and between them.
    t["socket_carry"] = ((0, -0.045, 0.575), (0, -0.045, 0.625), "root", False)
    return t

CONTROL_BONES = [n for n in bone_table() if n.startswith(("foot_ik", "mch_foot", "knee_pole", "hand_ik", "elbow_pole", "hand_aim"))]
SOCKET_BONES = ["socket_hand.L", "socket_hand.R", "socket_carry"]


def import_chef(src):
    bpy.ops.import_scene.gltf(filepath=src)
    mesh_ob = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    mesh_ob.name = MESH_NAME
    me = mesh_ob.data
    me.transform(Matrix.Translation(FLOOR_SHIFT))
    me.update()
    return mesh_ob


def build_armature():
    arm = bpy.data.armatures.new(ARMATURE_NAME)
    ob = bpy.data.objects.new(ARMATURE_NAME, arm)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    table = bone_table()
    for name, (h, t, parent, deform) in table.items():
        eb = arm.edit_bones.new(name)
        eb.head = Vector(h)
        eb.tail = Vector(t)
        eb.use_deform = deform
    for name, (h, t, parent, deform) in table.items():
        eb = arm.edit_bones[name]
        if parent:
            eb.parent = arm.edit_bones[parent]
            eb.use_connect = False
    # Deterministic rolls: Z axis of every bone points as close to world -Y (forward) /
    # up as possible so authored rotations are predictable.
    for eb in arm.edit_bones:
        if eb.name.startswith("socket") or eb.name.startswith("knee_pole"):
            eb.roll = 0.0
        else:
            eb.align_roll(Vector((0, -1, 0)) if abs(eb.vector.normalized().y) < 0.9 else Vector((0, 0, 1)))
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in ob.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return ob


def setup_leg_ik(ob):
    """IK legs so stationary clips keep feet planted while the hips move."""
    for sfx in ("L", "R"):
        shin = ob.pose.bones[f"shin.{sfx}"]
        c = shin.constraints.new("IK")
        c.name = "leg_ik"
        c.target = ob
        c.subtarget = f"foot_ik.{sfx}"
        c.pole_target = ob
        c.pole_subtarget = f"knee_pole.{sfx}"
        c.chain_count = 2
        c.use_tail = True
        foot = ob.pose.bones[f"foot.{sfx}"]
        c2 = foot.constraints.new("COPY_TRANSFORMS")
        c2.name = "foot_follow_ik"
        c2.target = ob
        c2.subtarget = f"mch_foot.{sfx}"
    for sfx in ("L", "R"):
        fa = ob.pose.bones[f"forearm.{sfx}"]
        c = fa.constraints.new("IK")
        c.name = "arm_ik"
        c.target = ob
        c.subtarget = f"hand_ik.{sfx}"
        c.pole_target = ob
        c.pole_subtarget = f"elbow_pole.{sfx}"
        c.chain_count = 2
        c.use_tail = True
    for sfx in ("L", "R"):
        c = ob.pose.bones[f"hand.{sfx}"].constraints.new("COPY_ROTATION")
        c.name = "hand_aim"
        c.target = ob
        c.subtarget = f"hand_aim.{sfx}"
        c.influence = 0.0
    sc = ob.pose.bones["socket_carry"]
    for i, sfx in enumerate(("L", "R")):
        c = sc.constraints.new("COPY_LOCATION")
        c.name = f"carry_mid_{sfx}"
        c.target = ob
        c.subtarget = f"socket_hand.{sfx}"
        c.influence = 1.0 if i == 0 else 0.5
    # Choose the pole angle that best preserves the rest pose (avoids twisted knees).
    best = None
    import math
    result = {}
    for bone, con, root in (("shin", "leg_ik", "thigh"), ("forearm", "arm_ik", "upperarm")):
        for sfx in ("L", "R"):
            best = None
            for ang in range(-180, 180, 5):
                ob.pose.bones[f"{bone}.{sfx}"].constraints[con].pole_angle = math.radians(ang)
                bpy.context.view_layer.update()
                pb = ob.pose.bones[f"{root}.{sfx}"]
                rest = ob.data.bones[f"{root}.{sfx}"].matrix_local
                err = pb.matrix.to_quaternion().rotation_difference(rest.to_quaternion()).angle
                if best is None or err < best[1]:
                    best = (ang, err)
            ob.pose.bones[f"{bone}.{sfx}"].constraints[con].pole_angle = math.radians(best[0])
            result[f"{bone}.{sfx}"] = best
    bpy.context.view_layer.update()
    return result


# --------------------------------------------------------------------------- weights

def smoothstep(e0, e1, x):
    if e0 == e1:
        return 1.0 if x >= e1 else 0.0
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def chain_weights(param, joints, names, widths):
    """Distribute 1.0 along a chain given a scalar parameter and joint positions."""
    w = {n: 0.0 for n in names}
    # names[i] covers joints[i-1]..joints[i]
    rem = 1.0
    out = {}
    prev = 1.0
    shares = []
    for i, j in enumerate(joints):
        shares.append(smoothstep(j - widths[i], j + widths[i], param))
    # shares[i] = fraction belonging to names[i+1] or beyond
    acc = []
    for i in range(len(names)):
        lo = shares[i - 1] if i > 0 else 1.0
        hi = shares[i] if i < len(shares) else 0.0
        out[names[i]] = max(0.0, lo - hi)
    return out


def _closest_param(p, pts):
    """Arc-length parameter of the closest point on a polyline (extends before start)."""
    best = None
    s0 = 0.0
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        ab = b - a
        L2 = ab.length_squared
        t = (p - a).dot(ab) / L2
        if i > 0:
            t = max(t, 0.0)
        if i < len(pts) - 2:
            t = min(t, 1.0)
        q = a + ab * t
        d = (p - q).length
        s = s0 + t * ab.length
        if best is None or d < best[0]:
            best = (d, s)
        s0 += ab.length
    return best[1]


def compute_weights(p_shifted):
    """Positional skin weights. Pure function of vertex position, so UV-seam duplicates
    (the mesh has 1,567 seam-split islands) receive identical weights and never crack."""
    p = p_shifted - FLOOR_SHIFT  # measurements were taken in source space
    x, y, z = p.x, p.y, p.z
    ax = abs(x)
    sfx = "L" if x >= 0 else "R"

    # --- torso chain by height (source-space z)
    torso = chain_weights(z, [-0.29, -0.15, -0.025, 0.055],
                          ["hips", "spine", "chest", "neck", "head"],
                          [0.05, 0.05, 0.035, 0.035])
    hat = smoothstep(0.60, 0.80, z)
    if hat > 0:
        torso["head"] *= (1 - hat)
        torso["hat"] = hat

    # --- arm membership
    width = 0.30 if z > -0.30 else 0.30 + (-0.30 - z) * 0.16
    low = smoothstep(width, width + 0.035, ax) if z > -0.50 else 0.0
    shoulder = smoothstep(0.17, 0.29, ax) * smoothstep(0.07, -0.05, z) * smoothstep(-0.28, -0.10, z)
    A = max(low, shoulder)
    if z > 0.05:
        A = 0.0

    # --- leg membership
    if z < -0.66:
        Lg = 1.0
    else:
        Lg = smoothstep(-0.40, -0.54, z)
        Lg *= smoothstep(0.0, 0.06, ax)
        Lg *= 1 - 0.7 * smoothstep(-0.22, -0.27, y)      # apron front: mostly hips
        Lg *= 1 - 0.7 * smoothstep(0.30, 0.33, ax)       # apron sides
        Lg *= 1 - 0.8 * smoothstep(0.10, 0.15, y)        # apron bow at the back
    Lg *= (1 - A)

    w = {}
    rest = max(0.0, 1 - A - Lg)
    for k, v in torso.items():
        w[k] = w.get(k, 0) + v * rest

    if A > 0:
        q = Vector((ax, y, z))
        pts = [Vector((0.25, -0.05, -0.09)), Vector((0.44, -0.05, -0.23)),
               Vector((0.545, -0.08, -0.32)), Vector((0.635, -0.09, -0.42))]
        s = _closest_param(q, pts)
        se = (pts[1] - pts[0]).length
        sw = se + (pts[2] - pts[1]).length
        arm = chain_weights(s, [0.0, se, sw],
                            [f"clavicle.{sfx}", f"upperarm.{sfx}", f"forearm.{sfx}", f"hand.{sfx}"],
                            [0.06, 0.04, 0.025])
        for k, v in arm.items():
            w[k] = w.get(k, 0) + v * A

    if Lg > 0:
        leg = chain_weights(-z, [0.685, 0.83],
                            [f"thigh.{sfx}", f"shin.{sfx}", f"foot.{sfx}"], [0.045, 0.03])
        toe = 0.75 * smoothstep(-0.20, -0.29, y) * smoothstep(-0.80, -0.86, z)
        if toe > 0:
            f = leg[f"foot.{sfx}"]
            leg[f"toe.{sfx}"] = f * toe
            leg[f"foot.{sfx}"] = f * (1 - toe)
        for k, v in leg.items():
            w[k] = w.get(k, 0) + v * Lg

    # keep 4 strongest, normalise
    items = sorted(((k, v) for k, v in w.items() if v > 1e-4), key=lambda kv: -kv[1])[:4]
    tot = sum(v for _, v in items)
    return [(k, v / tot) for k, v in items]


def skin_mesh(mesh_ob, arm_ob):
    for vg in list(mesh_ob.vertex_groups):
        mesh_ob.vertex_groups.remove(vg)
    groups = {b.name: mesh_ob.vertex_groups.new(name=b.name) for b in arm_ob.data.bones if b.use_deform}
    cache = {}
    for v in mesh_ob.data.vertices:
        key = (round(v.co.x, 5), round(v.co.y, 5), round(v.co.z, 5))
        ws = cache.get(key)
        if ws is None:
            ws = compute_weights(v.co.copy())
            cache[key] = ws
        for name, wt in ws:
            groups[name].add([v.index], wt, "REPLACE")
    mod = mesh_ob.modifiers.new("chef_skin", "ARMATURE")
    mod.object = arm_ob
    mesh_ob.parent = arm_ob
    return len(cache)


def bone_rest_quat(ob, name):
    return ob.data.bones[name].matrix_local.to_quaternion()


def arm_space_rot(ob, name, rx=0.0, ry=0.0, rz=0.0):
    """Local pose quaternion that rotates `name` by the given Euler angles (degrees) about
    armature axes (X: pitch, + = lean/nod forward for upright bones, swing a hanging limb
    backward; Y: frontal-plane roll; Z: yaw, + = turn to the chef's left)."""
    import math
    B = bone_rest_quat(ob, name)
    qa = Euler((math.radians(rx), math.radians(ry), math.radians(rz)), "XYZ").to_quaternion()
    return B.inverted() @ qa @ B
