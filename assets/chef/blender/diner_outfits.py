"""Paints restaurant-diner outfits onto the chef's base colour texture.

The chef atlas is colour-coded: white jacket and hat, teal apron, neckerchief and hat band,
orange skin, dark hair and shoes, navy trousers. Each outfit recolours the white parts to a
shirt colour and the teal parts to an accent (vest or skirt), keeping the painted shading by
scaling each texel's brightness. Skin, hair and face are untouched. (The app also hides the hat
bone on diners.)

Run inside Blender (the Blender MCP runs it while iterating) or headless:
    Blender -b --factory-startup -P diner_outfits.py -- <chef-animated.glb> <out dir>
Writes diner_01.jpg ... diner_06.jpg at 1024 px (JPEG 85).
"""
import bpy, sys, os
import numpy as np

OUTFITS = [  # (shirt, accent) as sRGB hex
    ("f2cf45", "3b6fb6"),   # lemon shirt, blue vest
    ("f07a5a", "f4ead8"),   # coral shirt, cream skirt
    ("79b8e6", "2e5a8f"),   # sky shirt, navy vest
    ("9bb35a", "efe3c6"),   # olive shirt, linen skirt
    ("f4f1ea", "c8423a"),   # white shirt, red vest
    ("b79ad6", "4e7a3c"),   # lavender shirt, green skirt
]

def srgb(h):
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)], dtype=np.float32)

def chef_texture(glb):
    before = set(bpy.data.images.keys())
    bpy.ops.import_scene.gltf(filepath=glb)
    new = [bpy.data.images[k] for k in bpy.data.images.keys() if k not in before]
    return next(im for im in new if im.colorspace_settings.name == "sRGB" and "metallic" not in im.name)

def paint(image, out_dir, size=1024):
    w, h = image.size
    px = np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)
    rgb = px[..., :3]
    mx = rgb.max(-1); mn = rgb.min(-1)
    sat = np.where(mx > 1e-5, (mx - mn) / np.maximum(mx, 1e-5), 0)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    # Hue in degrees.
    d = np.maximum(mx - mn, 1e-5)
    hue = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    white = np.clip((0.22 - sat) / 0.1, 0, 1) * np.clip((mx - 0.5) / 0.2, 0, 1)
    teal = np.clip((sat - 0.3) / 0.15, 0, 1) * np.clip((mx - 0.12) / 0.1, 0, 1) * ((hue > 165) & (hue < 215))
    white_ref = np.percentile(mx[white > 0.9], 90) if (white > 0.9).any() else 1.0
    teal_ref = np.percentile(mx[teal > 0.9], 90) if (teal > 0.9).any() else 0.5
    os.makedirs(out_dir, exist_ok=True)
    written = []
    for i, (shirt, accent) in enumerate(OUTFITS):
        out = rgb.copy()
        shade_w = np.clip(mx / white_ref, 0, 1.1)[..., None]
        shade_t = np.clip(mx / teal_ref, 0, 1.3)[..., None]
        out = out * (1 - white[..., None]) + (srgb(shirt) * shade_w) * white[..., None]
        out = out * (1 - teal[..., None]) + (srgb(accent) * shade_t) * teal[..., None]
        image_out = bpy.data.images.new(f"diner_{i + 1:02d}", w, h, alpha=False)
        image_out.colorspace_settings.name = "sRGB"
        image_out.pixels[:] = np.concatenate([np.clip(out, 0, 1), np.ones((h, w, 1), np.float32)], -1).ravel()
        image_out.scale(size, size)
        path = os.path.join(out_dir, f"diner_{i + 1:02d}.jpg")
        bpy.context.scene.render.image_settings.quality = 85
        image_out.filepath_raw = path; image_out.file_format = "JPEG"; image_out.save()
        written.append(path)
    return {"white": float(white.mean()), "teal": float(teal.mean()), "written": written}

if __name__ == "__main__" and "--" in sys.argv:
    glb, out_dir = sys.argv[sys.argv.index("--") + 1:][:2]
    print("DINERS", paint(chef_texture(glb), out_dir))
