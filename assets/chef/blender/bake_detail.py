"""Bake a full-detail model onto its simplified copy: the full model's surface normals (shape and
its normal map) and colours, re-projected onto the simplified mesh's own UVs. The simplified
mesh then looks like the full one at a fraction of the triangles; re-projecting the colour also
undoes the texture stretching simplification causes (eyes and mouths smear without it)."""
import bpy


def _bake_into(mat, size, name, colorspace, **bake):
    img = bpy.data.images.new(name, size, size, alpha=False)
    img.colorspace_settings.name = colorspace
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = img
    for n in mat.node_tree.nodes:
        n.select = False
    node.select = True
    mat.node_tree.nodes.active = node
    bpy.ops.object.bake(**bake)
    img.pack()
    return node


def bake(high, low, color_size, normal_size):
    """`low` is a simplified copy of `high` in the same place. Rewires low's material to the
    baked colour and normal maps; leaves metal/roughness as it was."""
    scene = bpy.context.scene
    engine = scene.render.engine
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 4
    b = scene.render.bake
    b.use_selected_to_active = True
    b.cage_extrusion = 0.02          # simplified surface sits within ~2 cm of the full one
    b.max_ray_distance = 0.06
    b.margin = 8                     # padding around each UV island
    mat = low.data.materials[0].copy()
    low.data.materials[0] = mat
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    nmap = bsdf.inputs["Normal"].links[0].from_node
    bpy.ops.object.select_all(action="DESELECT")
    high.select_set(True); low.select_set(True)
    bpy.context.view_layer.objects.active = low
    normal = _bake_into(mat, normal_size, low.name + "_normal", "Non-Color", type="NORMAL", normal_space="TANGENT")
    b.use_pass_direct = False; b.use_pass_indirect = False; b.use_pass_color = True
    color = _bake_into(mat, color_size, low.name + "_color", "sRGB", type="DIFFUSE", pass_filter={"COLOR"})
    mat.node_tree.links.new(normal.outputs["Color"], nmap.inputs["Color"])
    mat.node_tree.links.new(color.outputs["Color"], bsdf.inputs["Base Color"])
    scene.render.engine = engine
