"""Shared headless render helpers for rig verification images."""
import bpy, os, math
from mathutils import Vector


def setup_scene(res=(480, 640)):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.film_transparent = False
    w = bpy.data.worlds.get("verify_world") or bpy.data.worlds.new("verify_world")
    scene.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.32, 0.34, 0.38, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    cam = bpy.data.objects.get("verify_cam")
    if not cam:
        cam = bpy.data.objects.new("verify_cam", bpy.data.cameras.new("verify_cam"))
        scene.collection.objects.link(cam)
        sun = bpy.data.objects.new("verify_sun", bpy.data.lights.new("verify_sun", "SUN"))
        scene.collection.objects.link(sun)
        sun.rotation_euler = (0.7, 0.15, 0.4)
        sun.data.energy = 3.0
    scene.camera = cam
    return cam


VIEWS = {
    "front": (Vector((0, -6, 1.0)), 2.3),
    "side": (Vector((6, 0, 1.0)), 2.3),
    "back": (Vector((0, 6, 1.0)), 2.3),
    "left": (Vector((-6, 0, 1.0)), 2.3),
    # elevated kitchen camera similar to an Overcooked-style 3/4 overhead view
    "production": (Vector((2.6, -4.2, 4.6)), 2.6),
}


def shot(path, view="front", target=Vector((0, 0, 0.95)), ortho=None):
    scene = bpy.context.scene
    cam = scene.camera
    loc, scale = VIEWS[view]
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = ortho or scale
    cam.location = target + (loc - Vector((0, 0, 1.0)))
    d = target - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
