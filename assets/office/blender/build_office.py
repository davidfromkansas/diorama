"""Builds one piece of the startup office and exports it for the app.

    Blender -b --factory-startup -P build_office.py -- <piece> <out.glb> [review_dir]

Pieces (see ../README.md for each contract):
  order, prep, cooking, stove, tasting, bell, serving, pantry   station fixtures -> Resources/OfficeStations
  lobby                                                          the client lobby and skyline -> Resources/OfficeLobby
  box_sky … box_coral, binder, toolbox, device, plan_board       props -> Resources/OfficeProps

Stations are modelled in their own frame: centred on the footprint, standing on the floor,
x along the station, Blender -y toward the room (SceneKit +z), the worktop at TOP. Wall stations
are turned by the app. Parts the app animates stay separate objects, named
(`desk screen#i`, `desk logo#i`, `rack lights#i`, `rack screen#i`, `desk bell`).
"""
import bpy, math, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from office_kit import *

args = sys.argv[sys.argv.index("--") + 1:]
PIECE, OUT = args[0], args[1]
REVIEW = args[2] if len(args) > 2 else None
rng = random.Random(hash(PIECE) & 0xFFFF)
INK = [mat("ink_blue", "2e5cb3", 0.5), mat("ink_red", "cc4540", 0.5), mat("ink_green", "338c59", 0.5), mat("ink_black", "26262e", 0.5)]
SCREEN_OFF = glow("screen_off", "29334a", 0.4)
RACK_SCREEN = glow("terminal", "142921", 0.6)
LED = glow("status_led", "66f29e", 1.2)
LED_AMBER = glow("status_amber", "f5d98c", 1.2)


def credenza(width, depth, accent, fronts=True):
    """A low white credenza: oak top, black plinth, pastel drawer fronts toward the room (-y)."""
    box((width - 0.08, depth - 0.12, TOP - 0.05), (0, 0, (TOP - 0.05) / 2), WHITE, 0.02)
    box((width, depth, 0.05), (0, 0, TOP - 0.025), OAK, 0.012, 3)
    box((width - 0.3, depth - 0.3, 0.08), (0, 0, 0.04), BLACK, 0.01)
    if not fronts: return
    count = max(2, int(width / 1.1)); bay = (width - 0.16) / count
    for i in range(count):
        x = -width / 2 + 0.08 + bay * (i + 0.5)
        box((bay - 0.05, 0.025, TOP - 0.24), (x, -depth / 2 + 0.05, (TOP - 0.05) / 2 + 0.04), accent if i % 2 == 0 else WHITE, 0.012, 3)
        box((0.22, 0.04, 0.025), (x, -depth / 2 + 0.025, TOP - 0.16), BLACK, 0.008, 2)


def order():
    w, d = 4.8, 1.2
    credenza(w, d, BUTTER)
    wall = d / 2 - 0.05
    box((w - 0.3, 0.05, 1.36), (0, wall, TOP + 1.05), OAK_EDGE, 0.02, 3)
    box((w - 0.42, 0.04, 1.24), (0, wall - 0.02, TOP + 1.05), CORK, 0.005)
    notes = [BUTTER, PEACH, MINT, SKY, LILAC, CORAL]
    cols = max(3, int((w - 0.7) / 0.34))
    pin = mat("pin_red", "d94040", 0.4)
    for row in range(3):
        for col in range(cols):
            if (row * 7 + col * 3) % 5 == 0: continue
            x = -w / 2 + 0.5 + col * (w - 1.0) / (cols - 1); z = TOP + 0.6 + row * 0.36
            n = box((0.24, 0.01, 0.24), (x, wall - 0.05, z), notes[(row * 5 + col) % len(notes)], 0.003, 1)
            n.rotation_euler = (0, rng.uniform(-0.08, 0.08), 0)
            sphere(0.018, (x, wall - 0.065, z + 0.09), pin, 8)
    box((0.6, 0.4, 0.06), (w / 2 - 0.7, 0.1, TOP + 0.03), BLACK, 0.015)
    for i in range(3): box((0.42, 0.3, 0.012), (w / 2 - 0.7, 0.1, TOP + 0.07 + i * 0.015), PAPER, 0.003, 1)
    cyl(0.06, 0.12, (-w / 2 + 0.6, -0.1, TOP + 0.06), PEACH, 24, bevel=0.006)
    plant(-w / 2 + 0.35, 0.15, TOP, 0.7, seed=2)


def prep():
    w, d = 9.2, 1.2
    credenza(w, d, SAGE)
    wall = d / 2 - 0.05
    boards = 3; bw = (w - 0.6) / boards - 0.2
    board = mat("whiteboard", "fafafa", 0.15)
    notes = [BUTTER, PEACH, MINT]
    for b in range(boards):
        x = -w / 2 + 0.3 + (bw + 0.2) * (b + 0.5) + 0.1; z = TOP + 1.0
        box((bw + 0.08, 0.04, 1.22), (x, wall, z), ALUMINIUM, 0.012, 3)
        box((bw, 0.03, 1.14), (x, wall - 0.015, z), board, 0.004)
        for i in range(4):
            bx = x - bw / 2 + 0.35 + i * (bw - 0.7) / 3
            bz = z + (0.25 if i % 2 == 0 else -0.05) - (b % 2) * 0.1
            ink = INK[(i + b) % len(INK)]
            for (sw, sh, dx, dz) in [(0.36, 0.02, 0, 0.12), (0.36, 0.02, 0, -0.12), (0.02, 0.24, -0.17, 0), (0.02, 0.24, 0.17, 0)]:
                box((sw, 0.004, sh), (bx + dx, wall - 0.032, bz + dz), ink, 0)
            box((0.15, 0.006, 0.15), (bx + 0.08, wall - 0.034, bz - 0.36), notes[(i + b) % 3], 0)
        for line in range(3):
            box((bw * 0.5 - line * 0.15, 0.004, 0.012), (x - bw * 0.12, wall - 0.032, z - 0.4 - line * 0.06), INK[3], 0)
        box((bw * 0.6, 0.08, 0.03), (x, wall - 0.06, z - 0.6), ALUMINIUM, 0.008)
        for m in range(3):
            cyl(0.015, 0.13, (x - 0.15 + m * 0.12, wall - 0.06, z - 0.57), INK[m], 10, rot=(0, math.pi / 2, 0))
    plant(w / 2 - 0.35, 0.1, TOP, 0.8, seed=1)
    box((0.18, 0.18, 0.04), (-w / 2 + 0.5, -0.1, TOP + 0.02), BUTTER, 0.006)


def laptop(x, y, index, live=True):
    """A laptop: base under the chef's hands (+y side), lid leaning back toward the room."""
    box((0.52, 0.36, 0.025), (x, y, TOP + 0.013), GRAPHITE, 0.01, 3)
    box((0.44, 0.16, 0.004), (x, y + 0.04, TOP + 0.027), BLACK, 0)
    hinge = (x, y - 0.18, TOP + 0.025)
    shell = box((0.52, 0.018, 0.34), (x, hinge[1], hinge[2] + 0.17), GRAPHITE, 0.01, 3)
    screen = box((0.47, 0.002, 0.29), (x, hinge[1] + 0.0105, hinge[2] + 0.17), SCREEN_OFF, 0)
    logo = cyl(0.035, 0.004, (x, hinge[1] - 0.0105, hinge[2] + 0.19), glow("logo", "d9d9d9", 0.2), 20, rot=(math.pi / 2, 0, 0))
    for o in (shell, screen, logo):
        # Lean back 0.22 rad about the hinge (away from the chef, toward the room).
        o.location = Vector(hinge) + Matrix_rot_x(-0.22) @ (o.location - Vector(hinge))
        o.rotation_euler = (o.rotation_euler[0] - 0.22, o.rotation_euler[1], o.rotation_euler[2])
    if live:
        keep(screen, f"desk screen#{index}", pivot=screen.location)
        keep(logo, f"desk logo#{index}", pivot=logo.location)


def Matrix_rot_x(angle):
    from mathutils import Matrix
    return Matrix.Rotation(angle, 3, "X")


def cooking():
    w, d, spots = 9.0, 1.2, 6
    box((w, d, 0.05), (0, 0, TOP - 0.025), OAK, 0.012, 3)
    box((w - 0.4, 0.08, 0.06), (0, 0, TOP - 0.12), BLACK, 0.01)
    legs = max(2, int(w / 2.2) + 1)
    for i in range(legs):
        x = -w / 2 + 0.15 + i * (w - 0.3) / (legs - 1)
        for y in (-d / 2 + 0.12, d / 2 - 0.12): box((0.05, 0.05, TOP - 0.05), (x, y, (TOP - 0.05) / 2), BLACK, 0.008)
        box((0.06, d - 0.15, 0.03), (x, 0, 0.015), BLACK, 0.008)
    box((w - 0.6, 0.22, 0.05), (0, -d / 2 + 0.2, TOP - 0.2), SKY, 0.01)
    lamp = BUTTER
    for i in range(spots):
        x = -w / 2 + (i + 0.5) * w / spots
        laptop(x, d / 2 - 0.36, i)
        if i % 3 == 0: cyl(0.055, 0.11, (x + 0.42, -0.1, TOP + 0.055), [PEACH, MINT, BUTTER][i % 3], 24, bevel=0.006)
        elif i % 3 == 1: plant(x + 0.45, -0.2, TOP, 0.5, seed=i)
        else:
            cyl(0.08, 0.02, (x + 0.45, -0.15, TOP + 0.01), BLACK, 24)
            rod((x + 0.45, -0.15, TOP + 0.02), (x + 0.45, -0.05, TOP + 0.42), 0.012, BLACK)
            cyl(0.11, 0.12, (x + 0.45, -0.05, TOP + 0.45), lamp, 24, r2=0.05, rot=(0.3, 0, 0))


def stove():
    w, d, spots = 9.0, 1.2, 6
    box((w - 0.06, d - 0.08, TOP - 0.04), (0, 0, (TOP - 0.04) / 2), GRAPHITE, 0.015)
    box((w, d, 0.04), (0, 0, TOP - 0.02), BLACK, 0.01)
    bay = w / spots
    vent = mat("vent", "33363d", 0.6)
    for i in range(spots):
        x = -w / 2 + (i + 0.5) * bay
        box((bay - 0.06, 0.02, TOP - 0.16), (x, -d / 2 + 0.03, (TOP - 0.04) / 2), BLACK, 0.006)
        for row in range(5): box((bay - 0.3, 0.01, 0.012), (x, -d / 2 + 0.018, 0.15 + row * 0.06), vent, 0)
        leds = [box((0.05, 0.012, 0.03), (x - 0.2 + l * 0.08, -d / 2 + 0.012, TOP - 0.14), LED_AMBER if l % 3 == 2 else LED, 0) for l in range(6)]
        keep(join(leds, f"rack lights#{i}"), f"rack lights#{i}")
        box((0.44, 0.15, 0.02), (x, d / 2 - 0.32, TOP + 0.01), WHITE, 0.006)
        box((0.04, 0.04, 0.26), (x, d / 2 - 0.66, TOP + 0.13), ALUMINIUM, 0.008)
        box((0.2, 0.14, 0.012), (x, d / 2 - 0.66, TOP + 0.006), ALUMINIUM, 0.004)
        box((0.6, 0.03, 0.36), (x, d / 2 - 0.64, TOP + 0.38), BLACK, 0.012, 3)
        screen = box((0.55, 0.002, 0.31), (x, d / 2 - 0.624, TOP + 0.38), RACK_SCREEN, 0)
        keep(screen, f"rack screen#{i}", pivot=screen.location)
    for i in range(spots - 1):
        cyl(0.02, bay * 0.7, (-w / 2 + bay * (i + 1), -d / 2 + 0.25, TOP + 0.02), [SKY, CORAL, BUTTER][i % 3], 10, rot=(0, math.pi / 2, 0))


def tasting():
    w, d = 4.8, 1.2
    credenza(w, d, LILAC)
    wall = d / 2 - 0.05
    screens = [glow(f"device_{i}", c, 0.55) for i, c in enumerate(["9ec4e8", "99d6cc", "f2b899", "bdadde", "f5d98c"])]
    devices = max(3, int((w - 0.8) / 0.55))
    for i in range(devices):
        x = -w / 2 + 0.5 + i * (w - 1.0) / (devices - 1)
        tablet = i % 3 == 1
        dw, dh = (0.34, 0.25) if tablet else (0.15, 0.3)
        box((dw * 0.8, 0.12, 0.02), (x, 0.13, TOP + 0.01), ALUMINIUM, 0.006)
        body = box((dw, 0.015, dh), (x, 0.15, TOP + dh / 2 + 0.02), BLACK, 0.008, 3)
        face = box((dw - 0.02, 0.002, dh - 0.03), (x, 0.141, TOP + dh / 2 + 0.02), screens[i % len(screens)], 0)
        for o in (body, face): o.rotation_euler = (0.25, 0, 0)
    z = TOP + 0.95
    box((1.1, 0.04, 0.66), (0, wall, z), BLACK, 0.012, 3)
    box((1.02, 0.01, 0.58), (0, wall - 0.025, z), glow("test_screen", "1a2924", 0.5), 0)
    check = glow("check", "66f28c", 1.0)
    box((0.2, 0.01, 0.06), (-0.1, wall - 0.032, z - 0.05), check, 0).rotation_euler = (0, 0.8, 0)
    box((0.42, 0.01, 0.06), (0.08, wall - 0.032, z + 0.04), check, 0).rotation_euler = (0, -0.85, 0)
    for i, c in enumerate([MINT, BUTTER]): box((0.5, 0.01, 0.05), (0, wall - 0.032, z - 0.22 + i * 0.08), glow(f"test_bar_{i}", ["99d6cc", "f5d98c"][i], 0.6), 0)
    box((0.26, 0.34, 0.015), (w / 2 - 0.45, -0.2, TOP + 0.008), OAK_EDGE, 0.006)
    box((0.22, 0.28, 0.004), (w / 2 - 0.45, -0.2, TOP + 0.017), PAPER, 0)
    plant(-w / 2 + 0.3, -0.2, TOP, 0.6, seed=3)


def bell():
    cyl(0.28, TOP - 0.03, (0, 0, (TOP - 0.03) / 2), OAK, 40, bevel=0.01)
    cyl(0.32, 0.04, (0, 0, TOP - 0.02), WHITE, 40, bevel=0.01)
    cyl(0.3, 0.05, (0, 0, 0.025), BLACK, 40, bevel=0.01)
    parts = [cyl(0.2, 0.04, (0, 0, TOP + 0.02), BLACK, 40, bevel=0.008),
             sphere(0.17, (0, 0, TOP + 0.05), BRASS, 32, scale=(1, 1, 0.62)),
             cyl(0.018, 0.07, (0, 0, TOP + 0.18), BRASS, 12),
             sphere(0.035, (0, 0, TOP + 0.225), BRASS, 14)]
    keep(join(parts, "desk bell"), "desk bell", pivot=(0, 0, TOP))


def serving():
    w, d = 7.4, 1.2
    box((w, d, 0.05), (0, 0, TOP - 0.025), WHITE, 0.02, 3)
    box((w - 0.3, 0.36, 0.006), (0, -0.1, TOP + 0.003), MINT, 0)
    for x in (-w / 2 + 0.25, w / 2 - 0.25):
        for y in (-d / 2 + 0.15, d / 2 - 0.15): box((0.05, 0.05, TOP - 0.05), (x, y, (TOP - 0.05) / 2), ALUMINIUM, 0.008)
    box((w - 0.5, 0.05, 0.05), (0, 0, TOP - 0.1), ALUMINIUM, 0.008)
    x = w / 2 - 0.45
    box((0.05, 0.05, 0.6), (x, d / 2 - 0.15, TOP + 0.3), BLACK, 0.008)
    box((0.86, 0.04, 0.5), (x, d / 2 - 0.15, TOP + 0.75), BLACK, 0.012, 3)
    box((0.8, 0.01, 0.44), (x, d / 2 - 0.175, TOP + 0.75), glow("slide", "f7f2e6", 0.6), 0)
    for i, c in enumerate(["ed948c", "9ec4e8", "99d6cc"]):
        h = 0.1 + i * 0.07
        box((0.1, 0.01, h), (x - 0.2 + i * 0.15, d / 2 - 0.182, TOP + 0.6 + h / 2), glow(f"slide_bar_{i}", c, 0.7), 0)
    box((0.5, 0.01, 0.04), (x, d / 2 - 0.182, TOP + 0.9), glow("slide_title", "4d4d4d", 0.5), 0)
    plant(-w / 2 + 0.4, 0.25, TOP, 0.55, seed=5)


def pantry():
    w, d = 6.7, 1.2
    credenza(w, d, BUTTER)
    back = d / 2 - 0.1
    box((w - 0.1, 0.05, 1.5), (0, back + 0.02, TOP + 0.8), WHITE, 0.01)
    for i in range(5): box((0.06, 0.42, 1.5), (-w / 2 + 0.08 + i * (w - 0.16) / 4, back - 0.18, TOP + 0.8), OAK_EDGE, 0.01)
    shelves = [TOP + 0.6, TOP + 1.15]
    for z in shelves: box((w - 0.1, 0.42, 0.04), (0, back - 0.2, z), OAK, 0.008, 2)
    binders = int((w - 0.4) / 0.11)
    for i in range(binders):
        if i % 9 == 8: continue
        x = -w / 2 + 0.25 + i * 0.11
        b = box((0.08, 0.28, 0.34), (x, back - 0.2, shelves[1] + 0.19), PASTELS[(i // 4) % len(PASTELS)], 0.008, 2)
        if i % 9 == 7: b.rotation_euler = (0, 0.2, 0)
        box((0.05, 0.004, 0.1), (x, back - 0.342, shelves[1] + 0.22), PAPER, 0)
    cardboard = mat("cardboard", "c79e6b", 0.95)
    x = -w / 2 + 0.5; i = 0
    while x <= w / 2 - 0.5:
        if i % 3 == 2: box((0.5, 0.36, 0.32), (x, back - 0.2, shelves[0] + 0.18), cardboard, 0.01)
        else:
            box((0.56, 0.3, 0.24), (x, back - 0.2, shelves[0] + 0.14), CORAL if i % 2 == 0 else SKY, 0.03, 3)
            box((0.3, 0.04, 0.04), (x, back - 0.2, shelves[0] + 0.3), BLACK, 0.01)
        x += 0.9; i += 1
    for i, x in enumerate((-w * 0.32, 0, w * 0.32)):
        box((0.46, 0.32, 0.12), (x, back - 0.42, TOP + 0.06), LILAC if i == 1 else WHITE, 0.03, 3)
        for side in (-1, 1):
            a = cyl(0.012, 0.26, (x + side * 0.18, back - 0.3, TOP + 0.24), BLACK, 8)
            a.rotation_euler = (0, side * 0.25, 0)
        sphere(0.025, (x + 0.15, back - 0.585, TOP + 0.09), LED, 8)
    box((0.3, 0.24, 0.14), (w / 2 - 0.45, back - 0.5, TOP + 0.07), GRAPHITE, 0.02)


def lobby():
    """The lobby around the office floor (x -12…12, z -8…8 in SceneKit, not part of the model):
    polished concrete, café tables for clients on both sides with `seat_NN`/`dish_NN` anchors at
    the restaurant's spots, a reception desk and sofas out front, and the city beyond the windows."""
    g = 0.02
    concrete = mat("concrete", "d6d1c7", 0.4)
    box((44, 34, 0.04), (0, -2, 0), concrete, 0)
    seats = []
    chairs = [SKY, PEACH, MINT, LILAC, BUTTER, CORAL]
    for t, (x, z) in enumerate([(13.6, -4.5), (13.6, -0.8), (13.6, 2.9), (-13.6, -4.5), (-13.6, -0.8), (-13.6, 2.9)]):
        y = -z  # SceneKit z -> Blender -y
        cyl(0.32, 0.05, (x, y, g + 0.025), BLACK, 32, bevel=0.01)
        cyl(0.05, 0.9, (x, y, g + 0.48), BLACK, 16)
        cyl(0.62, 0.05, (x, y, g + 0.955), WHITE, 48, bevel=0.012)
        for side in (-1, 1):
            cy = y - side * 0.98; chair = chairs[(t * 2 + (1 if side > 0 else 0)) % len(chairs)]
            box((0.52, 0.5, 0.07), (x, cy, g + 0.605), chair, 0.03, 3)
            box((0.48, 0.06, 0.5), (x, cy - side * 0.24, g + 0.9), chair, 0.03, 3)
            for dx in (-0.21, 0.21):
                for dy in (-0.19, 0.19): box((0.04, 0.04, 0.57), (x + dx, cy + dy, g + 0.285), BLACK, 0.005)
            seats.append(((x, y - side * 0.87, g), (x, y - side * 0.3, g + 0.98)))
        plant(x + (1.1 if x > 0 else -1.1), y - 1.8, g, 1.3, TERRACOTTA if t % 2 else WHITE, seed=t)
    box((3.4, 0.9, 1.0), (-6.5, -11.2, g + 0.5), WHITE, 0.06, 3)
    box((3.5, 1.0, 0.05), (-6.5, -11.2, g + 1.02), OAK, 0.02, 3)
    box((3.42, 0.02, 0.16), (-6.5, -11.66, g + 0.62), SAGE, 0)
    for x in (6.2, 9.2):
        box((2.2, 0.9, 0.42), (x, -11.4, g + 0.21), SKY, 0.12, 4)
        box((2.2, 0.25, 0.5), (x, -11.75, g + 0.62), SKY, 0.1, 4)
    plant(-9, -10.6, g, 1.6, TERRACOTTA, seed=4)
    plant(11.4, -10.6, g, 1.6, seed=5)
    skyline()
    seats.sort(key=lambda s: (s[0][0] - 6.9) ** 2 + (-s[0][1] - 7.0) ** 2)
    anchors = []
    for i, (seat, dish) in enumerate(seats):
        anchors += [anchor(f"seat_{i + 1:02d}", seat), anchor(f"dish_{i + 1:02d}", dish)]
    return anchors


def skyline():
    """Towers beyond the window wall at golden hour, their windows lit amber."""
    import numpy as np
    r = np.random.default_rng(0xC17)
    tones = ["ccad9e", "a89ebd", "8f99b3", "e0c2a3"]
    facades = []
    for k, tone in enumerate(tones):
        base = np.array([int(tone[i:i + 2], 16) / 255 for i in (0, 2, 4)], np.float32)
        h, w = 256, 128
        img = np.tile(base, (h, w, 1))
        dark = base * 0.65 + np.array([0.25, 0.27, 0.36], np.float32) * 0.35
        for row in range(16):
            for col in range(6):
                lit = r.random() < 0.35
                y0, x0 = 6 + row * 16, 8 + col * 20
                img[y0:y0 + 9, x0:x0 + 13] = np.array([1, 0.84, 0.55], np.float32) if lit else dark
        image = bpy.data.images.new(f"facade_{k}", w, h, alpha=False)
        image.pixels.foreach_set(np.concatenate([img, np.ones((h, w, 1), np.float32)], axis=2).ravel())
        image.file_format = "JPEG"; image.pack()
        m = bpy.data.materials.new(f"facade_{k}"); m.use_nodes = True
        nt = m.node_tree; b = nt.nodes["Principled BSDF"]
        tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = image
        nt.links.new(tex.outputs["Color"], b.inputs["Base Color"])
        b.inputs["Roughness"].default_value = 0.8
        facades.append(m)
    for row in range(3):
        y = 19.0 + row * 9  # SceneKit z -19… -> Blender +y
        x = -40.0 + r.uniform(0, 3)
        while x < 40:
            w, d = r.uniform(3, 6), r.uniform(3, 5)
            h = r.uniform(3, 7) + row * 5 + (r.uniform(0, 5) if abs(x) < 10 else 0)
            m = facades[int(r.integers(0, len(facades)))]
            o = box((w, d, h), (x + w / 2, y + d / 2, h / 2), m, 0)
            uv_box(o, w, d, h)
            x += w + r.uniform(0.4, 1.6)


def uv_box(o, w, d, h):
    """Facade UVs in metres (a window bay every 1.5 m)."""
    me = o.data
    uv = me.uv_layers[0] if me.uv_layers else me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        n = poly.normal
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            u = (co.x if abs(n.y) > 0.5 else co.y) / 4.0
            uv.data[li].uv = (u, co.z / 8.0)


# ---------------------------------------------------------------- props

def gift(paper, ribbon):
    w, h, d = 0.8, 0.46, 0.62
    box((w, d, h), (0, 0, h / 2), paper, 0.02, 3)
    box((w + 0.04, d + 0.04, 0.08), (0, 0, h - 0.02), paper, 0.02, 3)
    box((w + 0.05, 0.08, h + 0.06), (0, 0, h / 2 + 0.01), ribbon, 0.005)
    box((0.08, d + 0.05, h + 0.06), (0, 0, h / 2 + 0.01), ribbon, 0.005)
    for side in (-1, 1): torus(0.09, 0.03, (side * 0.09, 0, h + 0.1), ribbon, rot=(math.pi / 2, side * 0.5, 0), seg=24, ring=8)


def binder():
    box((0.3, 0.75, 0.9), (0, 0, 0.45), SKY, 0.03, 3)
    box((0.24, 0.72, 0.84), (0.04, 0, 0.45), PAPER, 0.01)
    box((0.02, 0.4, 0.3), (-0.16, 0, 0.5), PAPER, 0)


def toolbox():
    box((1.0, 0.5, 0.45), (0, 0, 0.225), CORAL, 0.06, 4)
    box((1.02, 0.52, 0.08), (0, 0, 0.47), mat("coral_dark", "c7756e", 0.55), 0.03, 3)
    box((0.5, 0.08, 0.06), (0, 0, 0.62), BLACK, 0.02, 3)
    for x in (-0.25, 0.25): box((0.06, 0.08, 0.12), (x, 0, 0.55), BLACK, 0.01)


def device():
    box((1.0, 0.7, 0.26), (0, 0, 0.13), WHITE, 0.06, 4)
    sphere(0.05, (0.3, -0.36, 0.2), LED, 10)
    for x in (-0.38, 0.38): cyl(0.025, 0.6, (x, 0.3, 0.55), BLACK, 10)


def plan_board():
    box((0.8, 1.0, 0.04), (0, 0, 0.02), OAK_EDGE, 0.02, 3)
    box((0.7, 0.85, 0.01), (0, 0.03, 0.045), PAPER, 0)
    box((0.3, 0.1, 0.06), (0, 0.47, 0.06), ALUMINIUM, 0.01)
    for i in range(4): box((0.5 - (i % 2) * 0.15, 0.03, 0.004), (-0.05, 0.25 - i * 0.15, 0.052), SKY, 0)


STATIONS = {"order": order, "prep": prep, "cooking": cooking, "stove": stove, "tasting": tasting, "bell": bell, "serving": serving, "pantry": pantry}
WRAPS = {"box_sky": (SKY, CORAL), "box_mint": (MINT, LILAC), "box_peach": (PEACH, SKY), "box_lilac": (LILAC, BUTTER), "box_butter": (BUTTER, CORAL), "box_coral": (CORAL, MINT)}
PROPS = {"binder": binder, "toolbox": toolbox, "device": device, "plan_board": plan_board}

if PIECE in STATIONS:
    STATIONS[PIECE](); anchors = []
elif PIECE == "lobby":
    anchors = lobby()
elif PIECE in WRAPS:
    gift(*WRAPS[PIECE]); anchors = []
elif PIECE in PROPS:
    PROPS[PIECE](); anchors = []
else:
    raise SystemExit(f"unknown piece {PIECE}")

root, meshes, stats = assemble(PIECE, anchors)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
export(OUT, root, meshes)
print(f"OFFICE {PIECE} {stats}")
if REVIEW:
    extent = 30 if PIECE == "lobby" else (6 if PIECE in STATIONS else 1.6)
    review(REVIEW, [(PIECE, (extent * 0.6, -extent * 0.9, extent * 0.7), (0, 0, TOP / 2 if PIECE in STATIONS else 0.2), (900, 600))])
