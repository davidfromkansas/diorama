"""Textures for the break room's floor, a salon rather than a kitchen: French oak parquet laid
point de Hongrie (chevron), and a deep-green wool rug with an ivory border under the lounge chairs.

    python3 assets/kitchen/floor/make_lounge.py <out_dir>

Writes:
  floor_parquet.jpg / floor_parquet_normal.jpg  two chevron columns, seamless both ways
                                               (PARQUET_W x PARQUET_H metres, see KitchenFloor.swift)
  floor_rug.jpg / floor_rug_normal.jpg          the whole rug, RUG_W x RUG_H metres
"""
import sys, os, math
import numpy as np
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
PX = 800                               # pixels per metre
PLANK = 0.11                           # plank width
P = PLANK * math.sqrt(2)               # a plank's vertical stride in its column (45 degrees)
COLUMN = 4 * P                         # a chevron column's width (planks 0.88 long)
PARQUET_W, PARQUET_H = 2 * COLUMN, 4 * P
OAKS = np.array([[176, 128, 82], [190, 142, 92], [164, 116, 72], [184, 136, 88], [170, 124, 78], [196, 150, 100]]) / 255
JOINT = np.array([92, 62, 38]) / 255

def save(rgb, height, name, strength):
    Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, name + ".jpg"), quality=86)
    gy, gx = np.gradient(height)
    n = np.dstack([-gx * strength, gy * strength, np.ones_like(height)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8)).save(os.path.join(OUT, name + "_normal.jpg"), quality=90)

def parquet():
    w, h = round(PARQUET_W * PX), round(PARQUET_H * PX)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float64)
    x, y = xs / PX, ys / PX
    column = np.floor(x / COLUMN).astype(int)
    lx = x - column * COLUMN
    s = np.where(column % 2 == 0, 1.0, -1.0)
    # Planks run at 45 degrees, mirrored column to column, so their ends meet in a V.
    across = y - s * lx + (column % 2) * COLUMN                 # constant along a plank
    k = np.floor(across / P).astype(int)
    f = across / P - k                                         # 0..1 across the plank
    along = (lx + s * y) / math.sqrt(2)                        # along the plank
    rng = np.random.default_rng(1789)
    tone = rng.integers(0, len(OAKS), size=(2, 4))
    phase = rng.uniform(0, 2 * math.pi, size=(2, 4, 3))
    c, kk = column % 2, k % 4
    base = OAKS[tone[c, kk]]
    # Grain: fine lines along the plank, gently waving, plus a few darker figure streaks.
    ph = phase[c, kk]
    grain = (np.sin((f * 38 + np.sin(along * 3.1 + ph[..., 0]) * 0.8) * math.pi) * 0.5 + 0.5) ** 3
    figure = np.sin(f * 7 + np.sin(along * 1.3 + ph[..., 1]) * 1.6 + ph[..., 2]) * 0.5 + 0.5
    shade = 1 - 0.09 * grain - 0.07 * figure
    rgb = base * shade[..., None]
    # Joints: between planks, and down the column seams where the chevrons meet.
    edge = np.minimum(f, 1 - f) * P
    seam = np.minimum(lx, COLUMN - lx) * math.sqrt(2)
    joint = np.minimum(edge, seam)
    line = np.clip(1 - joint / 0.0035, 0, 1)
    rgb = rgb * (1 - line[..., None]) + JOINT * line[..., None]
    height = 1 - line * 0.8 - grain * 0.06
    save(rgb, height, "floor_parquet", 6)

RUG_W, RUG_H = 6.8, 3.3
GREEN = np.array([38, 70, 60]) / 255
GREEN_DARK = np.array([28, 54, 46]) / 255
IVORY = np.array([232, 222, 198]) / 255
BRASS = np.array([182, 146, 78]) / 255

def rug():
    w, h = round(RUG_W * 256), round(RUG_H * 256)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float64)
    x, y = xs / 256, ys / 256
    d = np.minimum(np.minimum(x, RUG_W - x), np.minimum(y, RUG_H - y))   # distance to the edge
    rgb = np.broadcast_to(GREEN, (h, w, 3)).copy()
    # Field: a small ivory lozenge diaper with a darker ground between.
    u = ((x - RUG_W / 2) / 0.36) % 1 - 0.5
    v = ((y - RUG_H / 2) / 0.36) % 1 - 0.5
    diamond = np.abs(u) + np.abs(v)
    rgb = np.where((diamond < 0.08)[..., None], IVORY * 0.9, rgb)
    rgb = np.where(((diamond > 0.44) & (diamond < 0.5))[..., None], GREEN_DARK, rgb)
    # Border: ivory band with a brass line inside it and a dark green edge.
    rgb = np.where(((d > 0.04) & (d < 0.24))[..., None], IVORY, rgb)
    rgb = np.where(((d > 0.29) & (d < 0.31))[..., None], BRASS, rgb)
    rgb = np.where((d <= 0.04)[..., None], GREEN_DARK, rgb)
    # Wool: a soft pile speckle.
    pile = np.random.default_rng(7).random((h, w))
    rgb = rgb * (0.94 + 0.08 * pile)[..., None]
    height = pile * 0.3 + np.clip(d / 0.04, 0, 1)
    save(rgb, height, "floor_rug", 2)

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    parquet(); rug()
    print("parquet tile %.3f x %.3f m" % (PARQUET_W, PARQUET_H))
