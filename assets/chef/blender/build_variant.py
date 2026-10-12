"""Fit another Meshy chef character to the tiny chef's skeleton, so it plays the chef's clips.

  Blender -b --factory-startup -P assets/chef/blender/build_variant.py -- <source.glb> <out_dir> <id>

The character keeps its own look; only where it stands and how its arms hang change:
  1. decimate to the chef's triangle budget;
  2. stand it where the chef stands (ankles on the chef's ankle point, soles on the floor);
  3. swing (and slightly stretch) each arm from the shoulder until the hand sits where the
     chef's hand does, so props held at the chef's hand sockets land in this character's hands;
  4. skin it to the chef armature with the chef's positional weights, except that a tail
     follows the hips (the chef has none) and nothing above the shoulders follows the arms.
Outputs <out_dir>/chef-<id>.glb (mesh + skin + the chef's 28 runtime nodes, no animations; the
app plays the chef's clips on it) and <out_dir>/chef-<id>.json (landmarks, counts, source hash).
"""
import bpy, bmesh, sys, os, json, math, hashlib
from mathutils import Vector, Matrix, Quaternion

sys.path.insert(0, os.path.dirname(__file__))
import chef_rig as R

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT, ID = argv[0], argv[1], argv[2]
OVERRIDES = json.loads(argv[3]) if len(argv) > 3 and argv[3] else {}
os.makedirs(OUT, exist_ok=True)

# Default budget for a chef character; a list (variants.json, guests.json) can set its own.
# Chosen from side-by-side renders (docs/restaurant/guests/downsample-comparison.png).
BUDGET = {"triangles": 15000, "base": 1024, "normal": 512, "metal_roughness": 256}
SMOOTHING = 12                          # waist-to-knee weight smoothing passes
ARMPIT = 0.78                           # below this height arm membership is all or nothing
SLACK = 0.14                            # surface-distance allowance around the arm (see arm_members)
CHEF_ANKLE = Vector((0.0, -0.07, 0.0))  # chef ankle-band centre in floor space (x, y), soles at z 0
CHEF_HAND = {1: Vector((0.6099, -0.0327, 0.5184)), -1: Vector((-0.6123, -0.0380, 0.5183))}
SHOULDER = {s: Vector((0.25 * s, 0.01, 0.86)) for s in (1, -1)}   # upperarm.L/R heads


def floor_space(ob):
    """Bake the import transform, then move the mesh so it stands where the chef stands."""
    me = ob.data
    me.transform(ob.matrix_world)
    ob.matrix_world = Matrix.Identity(4)
    vs = [v.co for v in me.vertices]
    zmin = min(v.z for v in vs)
    ank = [v for v in vs if 0.08 < v.z - zmin < 0.16]
    cx = (min(v.x for v in ank) + max(v.x for v in ank)) / 2
    cy = (min(v.y for v in ank) + max(v.y for v in ank)) / 2
    shift = Vector((CHEF_ANKLE.x - cx, CHEF_ANKLE.y - cy, -zmin))
    me.transform(Matrix.Translation(shift))
    me.update()
    return shift


def decimate(ob):
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    target = {**BUDGET, **OVERRIDES.get("budget", {})}["triangles"]
    if tris <= target:
        return tris
    # Meshy splits vertices at every texture seam. Welded first, the seams stay closed and their
    # UVs line up through the collapse; left split, each side collapses on its own and the
    # surface cracks open along them.
    bm = bmesh.new(); bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(ob.data); bm.free()
    mod = ob.modifiers.new("decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = target / tris
    mod.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def hand_centre(vs, s):
    """Centre of the hand: the vertices near the arm's outermost point at hand height."""
    band = [v for v in vs if 0.38 < v.z < 0.95 and v.x * s > 0.2]
    tip = max(band, key=lambda v: abs(v.x))
    near = [v for v in band if (v - tip).length < 0.10]
    return sum(near, Vector()) / len(near), tip


def surface_graph(me):
    """Vertex adjacency with UV-seam duplicates (same position) joined, so a walk over the
    surface doesn't stop at texture seams."""
    key = [(round(v.co.x, 5), round(v.co.y, 5), round(v.co.z, 5)) for v in me.vertices]
    group, groups = {}, []
    for i, k in enumerate(key):
        if k not in group:
            group[k] = len(groups); groups.append([])
        groups[group[k]].append(i)
    of = [group[k] for k in key]
    nbrs = [set() for _ in groups]
    for e in me.edges:
        a, b = of[e.vertices[0]], of[e.vertices[1]]
        if a != b:
            nbrs[a].add(b); nbrs[b].add(a)
    return of, groups, nbrs


def torso_half_width(z):
    """The chef's torso half-width at a height (its arm test in chef_rig.compute_weights):
    the characters share the chef's template, so below the armpit, nearer the middle than
    this is body even where an arm rests on it."""
    zs = z - R.FLOOR_SHIFT.z
    return 0.30 + max(0.0, -0.30 - zs) * 0.16 + 0.01


def arm_members(me, s, hand, graph):
    """The arm's vertices, sleeve included: those close to the hand over the surface. Going
    along the arm from the hand to a point at distance t from the shoulder takes about
    (length - t); reaching the torso means going up over the shoulder and back down, about
    (length + t). So surface distance separates an arm resting against the body from the body.
    Returns {vertex index: membership 0..1} (1 along the arm, fading in at the shoulder)."""
    import heapq
    of, groups, nbrs = graph
    sh = SHOULDER[s]
    axis = (hand - sh).normalized(); length = (hand - sh).length
    pos = [me.vertices[g[0]].co for g in groups]
    def tube(p):
        d = p - sh; t = d.dot(axis)
        return t, (d - axis * max(0.0, min(t, length + 0.08))).length
    inside = {}
    for gi, p in enumerate(pos):
        if p.x * s < 0.10 or p.z > 1.0 or p.z < 0.28:
            continue
        t, r = tube(p)
        if t >= -0.03 and r < 0.15:
            inside[gi] = t
    dist = {gi: (pos[gi] - hand).length for gi in inside if (pos[gi] - hand).length < 0.08}
    heap = [(d, gi) for gi, d in dist.items()]
    heapq.heapify(heap)
    while heap:
        d, g = heapq.heappop(heap)
        if d > dist.get(g, 1e9) or d > length + 0.4:
            continue
        for n in nbrs[g]:
            if n in inside:
                nd = d + (pos[n] - pos[g]).length
                if nd < dist.get(n, 1e9):
                    dist[n] = nd; heapq.heappush(heap, (nd, n))
    out = {}
    for gi, d in dist.items():
        t = inside[gi]
        if d > max(length - t, 0.0) + SLACK:
            continue                              # reached over the shoulder: torso, not arm
        p = pos[gi]
        if p.z < 0.58 and abs(p.x) < torso_half_width(p.z):
            continue                              # body the arm was resting against
        w = R.smoothstep(-0.04, 0.20, t)
        if w > 0:
            for i in groups[gi]:
                out[i] = w
    return out


def heat_members(ob, vs):
    """Arm membership by Blender's bone heat (automatic weights): temporary bones along the
    character's own arms, as they hang, on a copy with UV-seam duplicates merged. Heat follows
    the surface the way a limb does, so a hand resting on the apron keeps the apron on the body.
    Returns ({vertex index: 0..1}, {side: hand centre}), or None if Blender can't solve it."""
    from mathutils.kdtree import KDTree
    cp = ob.copy(); cp.data = ob.data.copy(); bpy.context.scene.collection.objects.link(cp)
    bm = bmesh.new(); bm.from_mesh(cp.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    # Thin loose pieces (whiskers) can stop bone heat solving; they take the nearest surface's.
    seen, small = set(), []
    for v in bm.verts:
        if v in seen:
            continue
        piece, stack = [], [v]; seen.add(v)
        while stack:
            x = stack.pop(); piece.append(x)
            for e in x.link_edges:
                o = e.other_vert(x)
                if o not in seen:
                    seen.add(o); stack.append(o)
        if len(piece) < 200:
            small += piece
    bmesh.ops.delete(bm, geom=small, context="VERTS")
    bm.to_mesh(cp.data); bm.free()
    data = bpy.data.armatures.new("heat"); rig = bpy.data.objects.new("heat", data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    def bone(name, head, tail, parent=None):
        b = data.edit_bones.new(name); b.head = Vector(head); b.tail = Vector(tail)
        if parent: b.parent = data.edit_bones[parent]
    bone("hips", (0, 0, 0.45), (0, 0, 0.70)); bone("chest", (0, 0, 0.70), (0, 0, 0.98), "hips")
    bone("head", (0, 0, 0.98), (0, 0, 1.6), "chest")
    hands = {}
    for s, sfx in ((1, "L"), (-1, "R")):
        hand, _ = hand_centre(vs, s); hands[s] = hand
        sh = SHOULDER[s]; elbow = sh.lerp(hand, 0.5) + Vector((0.02 * s, 0.02, 0))
        bone(f"clavicle.{sfx}", (0.06 * s, 0, 0.88), sh, "chest")
        bone(f"arm.{sfx}", sh, elbow, f"clavicle.{sfx}"); bone(f"forearm.{sfx}", elbow, hand, f"arm.{sfx}")
        bone(f"thigh.{sfx}", (0.15 * s, 0, 0.5), (0.165 * s, -0.015, 0.27), "hips")
        bone(f"shin.{sfx}", (0.165 * s, -0.015, 0.27), (0.17 * s, 0, 0.05), f"thigh.{sfx}")
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    cp.select_set(True); rig.select_set(True); bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    names = {g.index: g.name for g in cp.vertex_groups}
    arm_groups = {i for i, n in names.items() if n.split(".")[0] in ("arm", "forearm")}
    weight = [sum(g.weight for g in v.groups if g.group in arm_groups) for v in cp.data.vertices]
    solved = len(cp.vertex_groups) > 0 and sum(1 for w in weight if w > 0.5) > 200
    kd = KDTree(len(cp.data.vertices))
    for i, v in enumerate(cp.data.vertices):
        kd.insert(v.co, i)
    kd.balance()
    out = {}
    if solved:
        for v in ob.data.vertices:
            _, i, _ = kd.find(v.co)
            # Like the chef: below the armpit a vertex is arm or body, never between (a partial
            # weight drags shirt and apron after a raised arm); only the shoulder cap blends.
            w = R.smoothstep(0.15, 0.85, weight[i]) if v.co.z > ARMPIT else (1.0 if weight[i] >= 0.5 else 0.0)
            if w > 0:
                out[v.index] = w
    bpy.data.objects.remove(cp); bpy.data.objects.remove(rig)
    return (out, hands) if solved else None


def fit_arms(ob):
    """Swing each arm about the shoulder (and stretch it along its length) so its hand centre
    lands on the chef's hand centre. Returns what moved, and each vertex's arm membership."""
    me = ob.data
    vs = [v.co.copy() for v in me.vertices]
    graph = surface_graph(me)
    report, members = {}, {}
    heat = heat_members(ob, vs)
    report["membership"] = "bone heat" if heat else "surface distance"
    for s in (1, -1):
        hand, tip = hand_centre(vs, s)
        member = {i: w for i, w in heat[0].items() if me.vertices[i].co.x * s > 0} if heat else arm_members(me, s, hand, graph)
        target = CHEF_HAND[s]
        a, b = hand - SHOULDER[s], target - SHOULDER[s]
        swing = a.rotation_difference(b)
        k = b.length / a.length
        for i, w in member.items():
            # A share of the swing (an angle, not a blend of positions, so the sleeve near the
            # shoulder turns rather than shears) and a share of the stretch along the arm.
            q = Quaternion().slerp(swing, w)
            axis = q @ a.normalized()
            d = q @ (vs[i] - SHOULDER[s])
            along = d.dot(axis)
            me.vertices[i].co = SHOULDER[s] + axis * (along * (1 + (k - 1) * w)) + (d - axis * along)
            members[i] = max(members.get(i, 0.0), w)
        report["L" if s > 0 else "R"] = {
            "hand": [round(c, 4) for c in hand], "tip": [round(c, 4) for c in tip],
            "swing_deg": round(math.degrees(a.angle(b)), 2), "stretch": round(k, 4),
            "arm_vertices": sum(1 for w in member.values() if w > 0.5),
        }
    me.update()
    report["bridges_removed"] = remove_bridges(me, vs, members)
    return report, members


def remove_bridges(me, before, members):
    """Where a resting arm touched the body Meshy fused the two surfaces. Swinging the arm out
    stretches those bridging triangles into sheets; remove every face the fit stretched to
    more than 3x its original size (they sat where arm met body, so nothing visible is lost)."""
    bm = bmesh.new(); bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    def size(face, pts):
        a, b, c = (pts[v.index] for v in face.verts[:3])
        return max((a - b).length, (b - c).length, (c - a).length)
    now = [v.co.copy() for v in bm.verts]
    def joins_arm_to_body(face):
        # Wholly arm on one corner, wholly body on another: a fused contact patch away from
        # the shoulder (near the shoulder membership fades in, so the real joint never matches).
        m = [members.get(v.index, 0.0) for v in face.verts]
        # Only where a hand or forearm rested on the body; the armpit seam above stays whole.
        return max(m) > 0.95 and min(m) < 0.05 and max(v.co.z for v in face.verts) < 0.66
    bad = [f for f in bm.faces
           if (size(f, now) > 3 * max(size(f, before), 1e-4) and size(f, now) > 0.02) or joins_arm_to_body(f)]
    bmesh.ops.delete(bm, geom=bad, context="FACES_ONLY")   # vertices stay, so indices do too
    bm.to_mesh(me); bm.free(); me.update()
    return len(bad)


def is_tail(p, tail):
    """Behind the body below the waist: a tail, which follows the hips."""
    if not tail:
        return False
    return p.y > tail["behind"] and tail["low"] < p.z < tail["high"]


def apron_vertices(ob):
    """Every vertex the colour of the apron. The characters all wear a coloured apron over dark
    trousers; the chef's rules only find its apron by position, so on these it is found by
    colour: sampled at the front middle of the apron, then matched over the base colour texture."""
    import numpy as np
    me = ob.data
    image = None
    for m in me.materials:
        bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None) if m and m.node_tree else None
        link = bsdf and bsdf.inputs["Base Color"].links
        if link and link[0].from_node.type == "TEX_IMAGE":
            image = link[0].from_node.image
    uv = me.uv_layers.active
    if image is None or uv is None:
        return set()
    w, h = image.size
    px = np.array(image.pixels[:], dtype=np.float32).reshape(h, w, image.channels)[:, :, :3]
    colour = {}
    for loop in me.loops:
        if loop.vertex_index not in colour:
            u, v = uv.data[loop.index].uv
            colour[loop.vertex_index] = px[min(h - 1, max(0, int((v % 1) * h))), min(w - 1, max(0, int((u % 1) * w)))]
    band = [vt for vt in me.vertices if 0.38 < vt.co.z < 0.50 and abs(vt.co.x) < 0.08 and vt.index in colour]
    if not band:
        return set()
    front = min(vt.co.y for vt in band)
    ref = np.median(np.array([colour[vt.index] for vt in band if vt.co.y < front + 0.03]), axis=0)
    # Dark (trousers) or near-white (shirt) references mean the front isn't an apron here.
    if ref.max() < 0.15 or ref.min() > 0.75:
        return set()
    return {i for i, c in colour.items() if np.linalg.norm(c - ref) < 0.16 and 0.12 < me.vertices[i].co.z < 0.75}


def skin(mesh_ob, arm_ob, tail, members):
    """The chef's weights, a tail on the hips, then the waist-to-knee weights smoothed over the
    surface: the chef's apron rules expect its apron exactly where it is, and on a character
    whose apron sits a little differently a hard hips/thigh boundary tears when it sits down;
    smoothed, it bends."""
    me = mesh_ob.data
    for vg in list(mesh_ob.vertex_groups):
        mesh_ob.vertex_groups.remove(vg)
    groups = {b.name: mesh_ob.vertex_groups.new(name=b.name) for b in arm_ob.data.bones if b.use_deform}
    of, nodes, nbrs = surface_graph(me)
    apron = apron_vertices(mesh_ob)
    print("APRON vertices", len(apron))
    weights, tails, locked, arms = [], 0, [], []
    for g in nodes:
        v = me.vertices[g[0]]
        p = v.co.copy()
        m = max(members.get(i, 0.0) for i in g)
        if is_tail(p, tail):
            w = {"hips": 1.0}; tails += len(g)
        else:
            w = dict(R.compute_weights(p, arm_member=1.0 if m > 0.5 else m * 2))
            if m == 0 and any(i in apron for i in g) and p.y < 0.12:
                # The apron front drapes like a skirt: its top on the hips, its lower part on the
                # thighs by height (so it lies across the lap when sitting), split smoothly
                # between the left and right thigh across the middle.
                thighs = 0.85 * R.smoothstep(0.60, 0.34, p.z)
                left = R.smoothstep(-0.07, 0.07, p.x)
                w = {"hips": 1 - thighs, "thigh.L": thighs * left, "thigh.R": thighs * (1 - left)}
        draped = m == 0 and any(i in apron for i in g) and p.y < 0.12
        weights.append(w)
        arms.append(m > 0)
        locked.append(m > 0 or draped or is_tail(p, tail) or not (0.12 < p.z < 0.66))
    for _ in range(SMOOTHING):
        new = []
        for gi, w in enumerate(weights):
            if locked[gi] or not nbrs[gi]:
                new.append(w); continue
            # Never from the arms: body next to an arm must not start following it.
            around = [n for n in nbrs[gi] if not arms[n]]
            if not around:
                new.append(w); continue
            acc = dict((k, v * 0.5) for k, v in w.items())
            share = 0.5 / len(around)
            for n in around:
                for k, v in weights[n].items():
                    acc[k] = acc.get(k, 0.0) + v * share
            new.append(acc)
        weights = new
    for gi, w in enumerate(weights):
        top = sorted(((k, v) for k, v in w.items() if v > 1e-4), key=lambda kv: -kv[1])[:4]
        total = sum(v for _, v in top)
        for i in nodes[gi]:
            for name, wt in top:
                groups[name].add([i], wt / total, "REPLACE")
    mod = mesh_ob.modifiers.new("chef_skin", "ARMATURE")
    mod.object = arm_ob
    mesh_ob.parent = arm_ob
    return tails


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    ob = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    ob.name = R.MESH_NAME
    source_tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    shift = floor_space(ob)
    # Keep the full model to bake its detail onto the simplified one.
    high = ob.copy(); high.data = ob.data.copy(); bpy.context.scene.collection.objects.link(high)
    tris = decimate(ob)
    budget = {**BUDGET, **OVERRIDES.get("budget", {})}
    if budget.get("bake"):
        bm = bmesh.new(); bm.from_mesh(high.data)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
        bm.to_mesh(high.data); bm.free()
        import bake_detail
        bake_detail.bake(high, ob, color_size=budget["base"], normal_size=budget["normal"])
    bpy.data.objects.remove(high)
    arms, members = fit_arms(ob)
    arm = R.build_armature()
    tail = OVERRIDES.get("tail")
    tails = skin(ob, arm, tail, members)
    # Runtime skeleton only: the same bones, in the same order, as chef-animated.glb.
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for b in R.CONTROL_BONES:
        arm.data.edit_bones.remove(arm.data.edit_bones[b])
    bpy.ops.object.mode_set(mode="OBJECT")
    # Chefs are a couple of hundred pixels tall on screen: 1024 px textures keep each character
    # to about 12 MB of texture memory instead of 48.
    import texture_budget
    budget = {**BUDGET, **OVERRIDES.get("budget", {})}
    texture_budget.apply(ob, base=budget["base"], normal=budget["normal"], metal_roughness=budget["metal_roughness"])
    texture_budget.pad(ob)
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True); ob.select_set(True)
    prefix = OVERRIDES.get("prefix", "chef")
    glb = os.path.join(OUT, f"{prefix}-{ID}.glb")
    bpy.ops.export_scene.gltf(filepath=glb, use_selection=True, export_animations=False,
                              export_def_bones=False, export_skins=True, export_influence_nb=4,
                              export_yup=True, export_image_format="JPEG", export_image_quality=82,
                              export_rest_position_armature=True, export_leaf_bone=False)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, f"{prefix}-{ID}.blend"), compress=True)
    me = ob.data
    info = {
        "id": ID, "asset": f"{prefix}-{ID}.glb",
        "source": {"file": os.path.basename(SRC), "sha256": hashlib.sha256(open(SRC, "rb").read()).hexdigest()},
        "source_triangles": source_tris, "triangles": tris, "vertices": len(me.vertices),
        "floor_shift_blender": [round(c, 5) for c in shift],
        "arms": arms, "tail": tail, "tail_vertices": tails,
    }
    with open(os.path.join(OUT, f"{prefix}-{ID}.json"), "w") as fh:
        json.dump(info, fh, indent=2)
    print("VARIANT", json.dumps(info))


main()
