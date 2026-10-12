"""Review renders for a fitted character: the chef's rig, clips and props, wearing its body.

  Blender -b assets/chef/chef-rigged.blend -P assets/chef/blender/review_variant.py -- \
      <chef-<id>.blend> <chef-manifest.json> <out_dir> [clip,clip] [views]
"""
import bpy, sys, os, runpy

argv = sys.argv[sys.argv.index("--") + 1:]
variant, rest = argv[0], argv[1:]
chef = bpy.data.objects["chef_body"]
arm = bpy.data.objects["chef_rig"]
with bpy.data.libraries.load(variant) as (src, dst):
    dst.objects = ["chef_body"]
body = dst.objects[0]
bpy.context.scene.collection.objects.link(body)
chef.hide_render = True
body.name = "variant_body"
body.parent = arm
body.matrix_world = arm.matrix_world.copy()
for m in list(body.modifiers):
    body.modifiers.remove(m)
mod = body.modifiers.new("chef_skin", "ARMATURE")
mod.object = arm
sys.argv = [sys.argv[0], "--", *rest]
runpy.run_path(os.path.join(os.path.dirname(__file__), "render_clips.py"), run_name="__main__")
