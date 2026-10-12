"""Scale a mesh's PBR textures to a budget (per role), for the app's runtime exports."""


def _image(socket):
    node = socket.links[0].from_node if socket.links else None
    while node is not None and node.type != "TEX_IMAGE":
        node = next((i.links[0].from_node for i in node.inputs if i.links), None)
    return node.image if node is not None else None


def apply(ob, base, normal, metal_roughness):
    """Each texture no larger than its role's size: base colour, normal map, packed metal/roughness."""
    done = {}
    for mat in ob.data.materials:
        if not mat or not mat.node_tree:
            continue
        bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None:
            continue
        for socket, size in (("Base Color", base), ("Normal", normal), ("Metallic", metal_roughness), ("Roughness", metal_roughness)):
            img = _image(bsdf.inputs[socket])
            if img is not None and img.size[0] > size:
                img.scale(size, size)
            if img is not None:
                done[img.name] = tuple(img.size)
    return done


def pad(ob, pixels=8):
    """Extend every UV island's edge colours outward into the empty texture around it, in all of
    the mesh's textures. Sampling at an island's edge (filtering, mipmaps, a decimated triangle's
    UV landing just outside) then reads the island's own colour instead of the atlas background,
    which on a normal map shows as bright cracks along the seams."""
    import numpy as np
    me = ob.data
    uv = me.uv_layers.active
    if uv is None:
        return
    images = set()
    for mat in me.materials:
        if mat and mat.node_tree:
            images |= {n.image for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image}
    tris = []
    me.calc_loop_triangles()
    co = np.array([uv.data[i].uv for lt in me.loop_triangles for i in lt.loops], dtype=np.float64).reshape(-1, 3, 2)
    for img in images:
        w, h = img.size
        if not w or not h:
            continue
        px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, img.channels)
        mask = np.zeros((h, w), dtype=bool)
        pts = co * np.array([w, h]) - 0.5
        for t in pts:
            x0, y0 = np.floor(t.min(axis=0)).astype(int); x1, y1 = np.ceil(t.max(axis=0)).astype(int)
            x0, y0 = max(x0 % w if x1 - x0 > w else x0, 0), max(y0, 0)
            x1, y1 = min(x1, w - 1), min(y1, h - 1)
            if x1 < x0 or y1 < y0:
                continue
            ys, xs = np.mgrid[y0:y1 + 1, x0:x1 + 1]
            (ax, ay), (bx, by), (cx, cy) = t
            d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(d) < 1e-12:
                continue
            l1 = ((by - cy) * (xs - cx) + (cx - bx) * (ys - cy)) / d
            l2 = ((cy - ay) * (xs - cx) + (ax - cx) * (ys - cy)) / d
            l3 = 1 - l1 - l2
            e = -1.0 / max(w, h) * 4   # a pixel's grace: covered if the triangle touches it
            mask[ys, xs] |= (l1 >= e) & (l2 >= e) & (l3 >= e)
        filled = mask.copy()
        for _ in range(pixels):
            acc = np.zeros_like(px); n = np.zeros((h, w), dtype=np.float32)
            for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                m = np.roll(filled, (dy, dx), axis=(0, 1))
                acc += np.roll(px, (dy, dx), axis=(0, 1)) * m[..., None]; n += m
            grow = (~filled) & (n > 0)
            px[grow] = acc[grow] / n[grow][:, None]
            filled |= grow
        img.pixels.foreach_set(px.ravel())
        img.update()
