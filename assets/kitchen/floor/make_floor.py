"""Textures for the kitchen's French stone floor: cream limestone octagons set with blue-grey
clover cabochons, framed by a blue-grey border with an interlaced rope motif.

    python3 assets/kitchen/floor/make_floor.py <out_dir>

Writes (all seamless along their repeat):
  floor_field.jpg / floor_field_normal.jpg   4 x 4 tiles (each tile different), repeats every 4 tiles
  floor_border.jpg / floor_border_normal.jpg one repeat of the border band, repeats along its length
Sizes are in pixels; the app maps the field at TILE metres per tile (see KitchenFloor.swift).
"""
import sys, os
import numpy as np
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
rng = np.random.default_rng(1868)
TILE_PX = 384                      # per limestone tile
N = 4                              # tiles per repeat
SIZE = TILE_PX * N

LIMESTONE = np.array([236, 226, 205]) / 255
LIMESTONE_WARM = np.array([229, 212, 182]) / 255
SLATE = np.array([96, 118, 142]) / 255         # blue-grey cabochon
SLATE_DARK = np.array([72, 90, 112]) / 255
GROUT = np.array([170, 158, 138]) / 255

def value_noise(h, w, cells, octaves=5, seed=0, wrap=True):
    """Tileable fractal value noise in 0..1."""
    r = np.random.default_rng(seed)
    out = np.zeros((h, w)); amp = 1.0; norm = 0.0
    for o in range(octaves):
        c = cells * 2 ** o
        grid = r.random((c, c))
        ys = np.linspace(0, c, h, endpoint=False); xs = np.linspace(0, c, w, endpoint=False)
        y0 = np.floor(ys).astype(int); x0 = np.floor(xs).astype(int)
        fy = ys - y0; fx = xs - x0
        fy = fy * fy * (3 - 2 * fy); fx = fx * fx * (3 - 2 * fx)
        y1 = (y0 + 1) % c; x1 = (x0 + 1) % c
        a = grid[y0][:, x0]; b = grid[y0][:, x1]; cc = grid[y1][:, x0]; d = grid[y1][:, x1]
        v = (a * (1 - fx) + b * fx) * (1 - fy)[:, None] + (cc * (1 - fx) + d * fx) * fy[:, None]
        out += amp * v; norm += amp; amp *= 0.5
    return out / norm

def smooth(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)

def field():
    ys, xs = np.mgrid[0:SIZE, 0:SIZE].astype(np.float64)
    tx, ty = (xs // TILE_PX).astype(int), (ys // TILE_PX).astype(int)
    u = (xs % TILE_PX) / TILE_PX - 0.5; v = (ys % TILE_PX) / TILE_PX - 0.5   # -0.5..0.5 within a tile
    # Distance to the nearest tile corner, in tile units: the cabochon sits there.
    cu = 0.5 - np.abs(u); cv = 0.5 - np.abs(v)
    # Clover (quatrefoil): four discs around the corner, plus a centre disc.
    R, off = 0.085, 0.07
    clover = np.full_like(u, 9.0)
    for dx, dy in ((off, 0), (-off, 0), (0, off), (0, -off)):
        # the corner is at (cu, cv) = (0, 0); lobes reach into the 4 tiles meeting there
        px = np.where(u > 0, 1, -1) * (cu) ; py = np.where(v > 0, 1, -1) * (cv)
        clover = np.minimum(clover, np.hypot(px - dx, py - dy) - R)
    clover = np.minimum(clover, np.hypot(cu, cv) - R * 0.9)
    # Octagon: the tile with its corners cut where the cabochon sits.
    octagon = np.minimum(np.minimum(cu, cv), (cu + cv) / np.sqrt(2) - 0.105)
    grout_w = 0.008
    stone = smooth(-0.002, 0.004, octagon - grout_w)            # 1 inside a limestone tile
    cab = smooth(0.004, -0.002, clover)                         # 1 inside the cabochon
    # Limestone: each tile its own tone, soft cloudy mottling, fossil specks, worn edges.
    tone = rng.uniform(0, 1, (N, N))[ty, tx]
    cloud = value_noise(SIZE, SIZE, 6, 6, seed=3)
    fine = value_noise(SIZE, SIZE, 48, 3, seed=4)
    base = LIMESTONE * (1 - tone[..., None] * 0.55) + LIMESTONE_WARM * (tone[..., None] * 0.55)
    base = base * (0.93 + 0.1 * cloud[..., None]) * (0.97 + 0.04 * fine[..., None])
    specks = (value_noise(SIZE, SIZE, 160, 1, seed=5) > 0.93) * 0.18
    base = base * (1 - specks[..., None] * 0.6)
    wear = smooth(0.0, 0.03, octagon)                           # slightly darker toward the joint
    base = base * (0.9 + 0.1 * wear[..., None])
    # Slate cabochon: cool, with faint veining.
    vein = np.abs(np.sin((xs * 0.03 + ys * 0.017 + value_noise(SIZE, SIZE, 8, 4, seed=7) * 9)))
    slate = SLATE * (1 - vein[..., None] * 0.0) * (0.9 + 0.15 * value_noise(SIZE, SIZE, 24, 3, seed=8)[..., None])
    slate = slate * (1 - smooth(0.6, 1.0, 1 - vein)[..., None] * 0.08)      # faint, soft veining
    col = GROUT * (1 - stone[..., None]) + base * stone[..., None]
    col = col * (1 - cab[..., None]) + slate * cab[..., None]
    # Height for the normal map: stones raised, joints sunk, a gentle dish in each stone.
    height = stone * 1.0 + cab * 1.0 - (1 - np.maximum(stone, cab)) * 0.6 + cloud * 0.08
    return col, height

def border(length_px=768, width_px=384):
    """One repeat of the border band (length along x): a slate field between thin cream and
    slate fillets, an interlaced cream rope running down the middle, small cream lozenges."""
    ys, xs = np.mgrid[0:width_px, 0:length_px].astype(np.float64)
    v = ys / width_px; u = xs / length_px
    col = np.zeros((width_px, length_px, 3)) + SLATE
    # Fillets: cream outer lines, then slate, then a cream inner line.
    for a, b, c in ((0.0, 0.06, LIMESTONE), (0.94, 1.0, LIMESTONE), (0.1, 0.12, LIMESTONE), (0.88, 0.9, LIMESTONE)):
        m = (v >= a) & (v < b); col[m] = c
    # Interlaced rope: two sine strands crossing, cream with a dark edge.
    k = 2 * np.pi * 2                                            # two crossings per repeat
    centre = 0.5
    rope = np.zeros_like(v)
    for phase in (0, np.pi):
        y = centre + 0.2 * np.sin(k * u + phase)
        d = np.abs(v - y) * width_px
        rope = np.maximum(rope, smooth(7, 4, d))
        edge = smooth(10, 7, d) * (1 - smooth(7, 4, d))
        col = col * (1 - edge[..., None] * 0.35)
    col = col * (1 - rope[..., None]) + LIMESTONE * rope[..., None]
    # Lozenges in the loops.
    for cx in (0.125, 0.375, 0.625, 0.875):
        d = np.abs((u - cx) * length_px) / 22 + np.abs((v - 0.5) * width_px) / 22
        m = smooth(1.0, 0.85, d)
        col = col * (1 - m[..., None]) + LIMESTONE_WARM * m[..., None]
    col *= (0.94 + 0.08 * value_noise(width_px, length_px, 8, 4, seed=11))[..., None]
    height = 0.5 + rope * 0.3 + (np.isclose(col, LIMESTONE).all(-1)) * 0.1
    # Joints every half repeat (two stones per repeat) and along the edges.
    joint = (np.abs(((u * 2) % 1) - 0.0) * length_px / 2 < 2) | (ys < 2) | (ys > width_px - 3)
    col[joint] = GROUT; height = np.where(joint, -0.5, height)
    return col, height

def normal_map(height, strength):
    """Tangent-space normal map from a height field (wraps at the edges, so it tiles)."""
    dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * strength
    dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * strength
    n = np.dstack([-dx, dy, np.ones_like(height)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5

def save(rgb, name, q=88):
    Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, name), quality=q)

os.makedirs(OUT, exist_ok=True)
col, h = field()
save(col, "floor_field.jpg"); save(normal_map(np.clip(h, -1, 1.2), 2.2), "floor_field_normal.jpg", 90)
col, h = border()
save(col, "floor_border.jpg"); save(normal_map(h, 1.5), "floor_border_normal.jpg", 90)
for f in sorted(os.listdir(OUT)):
    if f.startswith("floor_"): print(f, os.path.getsize(os.path.join(OUT, f)) // 1024, "KB")
