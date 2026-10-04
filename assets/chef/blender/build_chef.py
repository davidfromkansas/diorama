"""Repeatable rig + animation + export pipeline for the tiny chef.

  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      -P tools/blender/build_chef.py -- <source.glb> <out_dir>

Outputs in <out_dir>:
  chef-rigged.blend      editable source: mesh, deform skeleton, IK controls, ctrl_* authoring
                         actions and the baked runtime actions
  chef-animated.glb      runtime: skinned chef, sockets, one glTF animation per clip
  chef-props.glb         separate prop meshes (recipe card, cookbook, knife, ingredient, board,
                         plate, spoon, pot)
  chef-manifest.json     semantic clip table, markers, sockets, prop attach offsets, stations
Blender is only needed to rebuild assets; the application loads the GLBs.
"""
import bpy, sys, os, json, math, hashlib
from mathutils import Vector, Matrix, Quaternion, Euler

sys.path.insert(0, os.path.dirname(__file__))
import importlib
import chef_rig as R
import chef_anims as A
import chef_props as PR
importlib.reload(R); importlib.reload(A); importlib.reload(PR)

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
ONLY = argv[2].split(",") if len(argv) > 2 and argv[2] else None
os.makedirs(OUT, exist_ok=True)
FPS = A.FPS


def channelbag(action):
    for layer in action.layers:
        for strip in layer.strips:
            for slot in action.slots:
                cb = strip.channelbag(slot)
                if cb:
                    return cb
    return None


def fcurves(action):
    cb = channelbag(action)
    return list(cb.fcurves) if cb else []


def setup():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    mesh = R.import_chef(SRC)
    arm = R.build_armature()
    nverts = R.skin_mesh(mesh, arm)
    poles = R.setup_leg_ik(arm)
    return scene, mesh, arm, nverts, poles


def apply_pose(arm, pose, prev_quats):
    P = arm.pose.bones
    for pb in P:
        if pb.name in R.SOCKET_BONES:
            continue
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
    for b in A.ROT_BONES:
        rx, ry, rz = pose.get("rot:" + b, (0, 0, 0))
        q = R.arm_space_rot(arm, b, rx, ry, rz)
        if b in prev_quats and q.dot(prev_quats[b]) < 0:
            q = -q
        prev_quats[b] = q
        P[b].rotation_quaternion = q
    def set_loc(bone, world_offset):
        B = arm.data.bones[bone].matrix_local.to_3x3()
        P[bone].location = B.inverted() @ Vector(world_offset)
    for s in ("L", "R"):
        d = pose.get("aimdir." + s)
        con = P[f"hand.{s}"].constraints["hand_aim"]
        con.influence = 1.0 if d else 0.0
        if d:
            B = arm.data.bones[f"hand_aim.{s}"].matrix_local.to_quaternion()
            rest_dir = (arm.data.bones[f"hand_aim.{s}"].tail_local - arm.data.bones[f"hand_aim.{s}"].head_local).normalized()
            q = rest_dir.rotation_difference(Vector(d).normalized())
            roll = pose.get("aimroll." + s, 0.0)
            if roll:
                q = Quaternion(Vector(d).normalized(), math.radians(roll)) @ q
            ql = B.inverted() @ q @ B
            if f"hand_aim.{s}" in prev_quats and ql.dot(prev_quats[f"hand_aim.{s}"]) < 0:
                ql = -ql
            prev_quats[f"hand_aim.{s}"] = ql
            P[f"hand_aim.{s}"].rotation_quaternion = ql
    set_loc("hips", pose["loc:hips"])
    for s in ("L", "R"):
        set_loc(f"hand_ik.{s}", Vector(pose["hand." + s]) - Vector(A.REST_WRIST[s]))
        set_loc(f"foot_ik.{s}", pose["foot." + s])
        set_loc(f"elbow_pole.{s}", Vector(pose["pole." + s]) - arm.data.bones[f"elbow_pole.{s}"].head_local)


KEYED = None


def keyed_bones(arm):
    return [b for b in A.ROT_BONES] + ["hips"] + [f"{n}.{s}" for n in ("hand_ik", "foot_ik", "elbow_pole", "hand_aim") for s in "LR"]


def author_clip(arm, name, spec):
    act = bpy.data.actions.new("ctrl_" + name)
    act.use_fake_user = True
    arm.animation_data_create()
    arm.animation_data.action = act
    keys = list(spec["keys"])
    if spec["loop"]:
        keys.append((spec["duration"], keys[0][1]))
    prev = {}
    for t, pose in keys:
        f = round(t * FPS, 3)
        apply_pose(arm, pose, prev)
        for b in keyed_bones(arm):
            pb = arm.pose.bones[b]
            pb.keyframe_insert("rotation_quaternion", frame=f, group=b)
            pb.keyframe_insert("location", frame=f, group=b)
        for side in "LR":
            arm.pose.bones[f"hand.{side}"].constraints["hand_aim"].keyframe_insert("influence", frame=f)
    n = round(spec["duration"] * FPS)
    act.use_frame_range = True
    act.frame_start, act.frame_end = 0, n
    if spec["loop"]:
        act.use_cyclic = True
        for fc in fcurves(act):
            fc.modifiers.new("CYCLES")
            for kp in fc.keyframe_points:
                kp.handle_left_type = kp.handle_right_type = "AUTO_CLAMPED"
            fc.update()
    else:
        for fc in fcurves(act):
            for kp in fc.keyframe_points:
                kp.handle_left_type = kp.handle_right_type = "AUTO_CLAMPED"
            fc.update()
    for mname, mt in spec.get("markers", {}).items():
        m = act.pose_markers.new(mname)
        m.frame = round(mt * FPS)
    return act, n


def bake_clip(arm, name, ctrl, n):
    """Visual-key the constrained result onto deform + socket bones (FK only) so the
    runtime needs no IK. One key per frame."""
    scene = bpy.context.scene
    arm.animation_data.action = ctrl
    bones = [b.name for b in arm.data.bones if b.use_deform or b.name in R.SOCKET_BONES or b.name == "root"]
    frames = {}
    for f in range(0, n + 1):
        scene.frame_set(f)
        bpy.context.view_layer.update()
        frames[f] = {}
        for b in bones:
            pb = arm.pose.bones[b]
            m = arm.convert_space(pose_bone=pb, matrix=pb.matrix, from_space="POSE", to_space="LOCAL")
            frames[f][b] = m.copy()
    baked = bpy.data.actions.new(name)
    baked.use_fake_user = True
    arm.animation_data.action = baked
    prev = {}
    for f in range(0, n + 1):
        for b in bones:
            pb = arm.pose.bones[b]
            loc, rot, _ = frames[f][b].decompose()
            if b in prev and rot.dot(prev[b]) < 0:
                rot = -rot
            prev[b] = rot
            pb.location = loc
            pb.rotation_quaternion = rot
            pb.keyframe_insert("location", frame=f, group=b)
            pb.keyframe_insert("rotation_quaternion", frame=f, group=b)
    for fc in fcurves(baked):
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    baked.use_frame_range = True
    baked.frame_start, baked.frame_end = 0, n
    for m in ctrl.pose_markers:
        baked.pose_markers.new(m.name).frame = m.frame
    arm.animation_data.action = ctrl
    return baked, frames


def socket_matrix(arm, ctrl, frame, socket):
    arm.animation_data.action = ctrl
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()
    return arm.matrix_world @ arm.pose.bones[socket].matrix


C = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))  # Blender -> glTF axes


def to_gltf_offset(off_bl):
    """Prop offset in the socket's glTF node frame (socket bones are world-aligned at rest,
    so their glTF rest frame is the model frame). Verified after export by verify_export."""
    m = off_bl @ C.inverted()
    loc, rot, _ = m.decompose()
    return {"position": [round(v, 5) for v in loc],
            "quaternion": [round(rot.x, 5), round(rot.y, 5), round(rot.z, 5), round(rot.w, 5)]}


def main():
    scene, mesh, arm, nverts, poles = setup()
    print("unique weight positions", nverts, "poles", poles)
    names = ONLY or list(A.CLIPS.keys())
    clip_meta = {}
    ctrl_actions = {}
    for name in names:
        spec = A.CLIPS[name]()
        ctrl, n = author_clip(arm, name, spec)
        baked, frames = bake_clip(arm, name, ctrl, n)
        ctrl_actions[name] = (ctrl, n)
        clip_meta[name] = {
            "clip": name,
            "duration": round(n / FPS, 4),
            "frames": n + 1,
            "fps": FPS,
            "loop": spec["loop"],
            "markers": {k: round(v / spec["duration"], 4) for k, v in spec.get("markers", {}).items()},
        }
        if "nominal_speed" in spec:
            clip_meta[name]["nominal_speed"] = spec["nominal_speed"]
        print("clip", name, n + 1, "frames")

    # ---- props: build, then fit attach offsets against the actual baked poses
    props = PR.build_props()
    attach = {}
    for prop, socket, clip, t, desired in PR.ATTACH_FITS:
        if clip not in ctrl_actions:
            continue
        ctrl, n = ctrl_actions[clip]
        f = round(t * FPS)
        S = socket_matrix(arm, ctrl, f, socket)
        D = desired(S)
        off = S.inverted() @ D
        attach.setdefault(prop, {})[clip] = dict(socket=socket, **to_gltf_offset(off),
                                                 fit_frame=f, blender=[list(r) for r in off], grip_gap=round((D.translation - S.translation).length, 4))
        PR.record_fit(prop, clip, socket, off)
        if prop == "prop_knife":
            mid = D @ Vector((0, -0.10, -0.05))
            print(f"KNIFE edge z at impact {PR.knife_edge_low(D):.4f} (board top {A.BOARD_TOP:.4f}); blade mid x {mid.x:.3f} y {mid.y:.3f}")

    # Rest pose + editable action on the source file
    arm.animation_data.action = ctrl_actions[names[0]][0]
    scene.frame_set(0)
    for o in props.values():
        o.hide_render = True
    blend_path = os.path.join(OUT, "chef-rigged.blend")
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=blend_path, compress=True)

    # ---- props export
    bpy.ops.object.select_all(action="DESELECT")
    for o in props.values():
        o.hide_render = False
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "chef-props.glb"), use_selection=True,
                              export_animations=False, export_yup=True)

    # ---- runtime export: strip authoring controls, keep baked actions only
    for o in props.values():
        bpy.data.objects.remove(o)
    for ctrl, _ in ctrl_actions.values():
        bpy.data.actions.remove(ctrl)
    for pb in arm.pose.bones:
        for c in list(pb.constraints):
            pb.constraints.remove(c)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for b in R.CONTROL_BONES:
        arm.data.edit_bones.remove(arm.data.edit_bones[b])
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0)
    arm.animation_data.action = None
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True); mesh.select_set(True)
    glb = os.path.join(OUT, "chef-animated.glb")
    bpy.ops.export_scene.gltf(filepath=glb, use_selection=True, export_animations=True,
                              export_animation_mode="ACTIONS", export_force_sampling=True,
                              export_frame_step=1, export_def_bones=False, export_skins=True,
                              export_influence_nb=4, export_yup=True, export_image_format="AUTO",
                              export_optimize_animation_size=False, export_rest_position_armature=True,
                              export_anim_slide_to_zero=True, export_leaf_bone=False)

    src_hash = hashlib.sha256(open(SRC, "rb").read()).hexdigest()
    manifest = {
        "asset": "chef-animated.glb",
        "props": "chef-props.glb",
        "source": {"file": os.path.basename(SRC), "sha256": src_hash},
        "units": "1 glTF unit = 1 source unit; chef height 1.90 (soles to toque top)",
        "height": 1.90,
        "floor_shift_blender": list(R.FLOOR_SHIFT),
        "floor_shift_gltf": [R.FLOOR_SHIFT.x, R.FLOOR_SHIFT.z, -R.FLOOR_SHIFT.y],
        "facing": "+Z in glTF (-Y in Blender)",
        "root_motion": "none - all clips are in place; navigation moves the avatar root",
        "clips": clip_meta,
        "sockets": {
            "socket_hand.L": {"parent": "hand.L", "use": "left-hand props (recipe card, cookbook)"},
            "socket_hand.R": {"parent": "hand.R", "use": "right-hand props (knife, spoon)"},
            "socket_carry": {"parent": "root (baked to hands' midpoint, level)", "use": "two-hand plate"},
        },
        "attach": attach,
        "stations": {
            "counter_top": A.COUNTER_TOP,
            "board_top": A.BOARD_TOP,
            "counter_front_from_root": -A.COUNTER_FRONT_Y,
            "note": "Distances in chef units, measured forward (+Z glTF) from the avatar root.",
        },
        "bones": {
            "deform": [b.name for b in arm.data.bones if b.use_deform],
            "sockets": R.SOCKET_BONES,
            "root": "root",
        },
    }
    with open(os.path.join(OUT, "chef-manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=2)
    print("DONE", glb)


main()
