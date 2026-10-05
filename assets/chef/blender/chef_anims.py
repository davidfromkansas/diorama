"""Clip authoring data for the tiny chef.

Each clip is a list of (time_seconds, pose) keys. A pose is a dict merged over STAND:
  "rot:<bone>":  (rx, ry, rz) degrees about armature axes (see chef_rig.arm_space_rot)
  "loc:hips":    (dx, dy, dz) offset in armature space
  "hand.L"/"hand.R": absolute wrist IK target (armature space, floor = 0, chef faces -Y)
  "foot.L"/"foot.R": ankle IK offset from rest
  "pole.L"/"pole.R": absolute elbow pole position
Right-side rotations are written explicitly (mirror = (rx, -ry, -rz)).

The chef's arms are very short (shoulder-to-wrist reach 0.377 units) and the belly protrudes
0.41 units in front of the hip line, so every hand target below was fitted to that reach,
usually with clavicle protraction plus a hip/spine lean.
"""
import math

FPS = 30

REST_WRIST = {"L": (0.545, -0.02, 0.63), "R": (-0.545, -0.02, 0.63)}
RELAX_HAND = {"L": (0.47, -0.05, 0.58), "R": (-0.47, -0.05, 0.58)}
BACK_POLE = {"L": (0.62, 0.45, 0.70), "R": (-0.62, 0.45, 0.70)}
DOWN_POLE = {"L": (0.75, 0.05, 0.25), "R": (-0.75, 0.05, 0.25)}

# Station geometry the clips are authored against (mirrored in the runtime station config).
COUNTER_TOP = 0.585         # work surface height (floor = 0)
COUNTER_FRONT_Y = -0.43     # front edge of the counter relative to the chef root
BOARD_TOP = COUNTER_TOP + 0.02

STAND = {
    "hand.L": RELAX_HAND["L"], "hand.R": RELAX_HAND["R"],
    "pole.L": BACK_POLE["L"], "pole.R": BACK_POLE["R"],
    "loc:hips": (0, 0, 0),
    "foot.L": (0, 0, 0), "foot.R": (0, 0, 0),
}
ROT_BONES = ["hips", "spine", "chest", "neck", "head", "hat",
             "clavicle.L", "clavicle.R", "hand.L", "hand.R", "toe.L", "toe.R",
             "foot_ik.L", "foot_ik.R"]


def _key(k):
    k = k.replace("__", ":")
    if k.endswith("_L") or k.endswith("_R"):
        k = k[:-2] + "." + k[-1]
    return k


def P(**kw):
    """Build a pose; keyword names use '__' for ':' and '_L'/'_R' for '.L'/'.R'."""
    d = dict(STAND)
    for k, v in kw.items():
        k = k.replace("__", ":")
        if k.endswith("_L") or k.endswith("_R"):
            k = k[:-2] + "." + k[-1]
        d[k] = v
    return d


def merge(base, **kw):
    d = dict(base)
    for k, v in kw.items():
        k = k.replace("__", ":")
        if k.endswith("_L") or k.endswith("_R"):
            k = k[:-2] + "." + k[-1]
        d[k] = v
    return d


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


# ----------------------------------------------------------------- shared poses
LEAN_WORK = dict(rot__hips=(10, 0, 0), rot__spine=(5, 0, 0), rot__chest=(3, 0, 0),
                 loc__hips=(0, 0.025, -0.012),
                 rot__clavicle_L=(0, 0, -18), rot__clavicle_R=(0, 0, 18),
                 pole_L=DOWN_POLE["L"], pole_R=DOWN_POLE["R"])

CARRY_HANDS = {"L": (0.15, -0.36, 0.775), "R": (-0.15, -0.36, 0.775)}
CARRY = P(rot__clavicle_L=(0, 0, -20), rot__clavicle_R=(0, 0, 20), rot__spine=(-2, 0, 0),
          rot__hand_L=(0, 0, 0), rot__hand_R=(0, 0, 0),
          hand_L=CARRY_HANDS["L"], hand_R=CARRY_HANDS["R"],
          pole_L=DOWN_POLE["L"], pole_R=DOWN_POLE["R"])

PLACE_HANDS = {"L": (0.15, -0.47, BOARD_TOP + 0.05), "R": (-0.15, -0.47, BOARD_TOP + 0.05)}
PLACE = merge(P(**LEAN_WORK), rot__hips=(14, 0, 0), rot__spine=(6, 0, 0),
              hand_L=PLACE_HANDS["L"], hand_R=PLACE_HANDS["R"])

SUBDUED = P(rot__chest=(6, 0, 0), rot__spine=(3, 0, 0), rot__head=(10, 0, 0),
            rot__clavicle_L=(0, 6, 0), rot__clavicle_R=(0, -6, 0),
            hand_L=(0.45, -0.02, 0.555), hand_R=(-0.45, -0.02, 0.555), loc__hips=(0, 0, -0.008))


def clip_idle():
    return dict(duration=4.0, loop=True, keys=[
        (0.0, P()),
        (1.0, P(loc__hips=(0.012, 0, -0.004), rot__hips=(0, -1.5, 0), rot__chest=(-2, 1.5, 0),
                rot__head=(0, 0, 0), hand_L=add(RELAX_HAND["L"], (0, 0, 0.008)))),
        (2.0, P(rot__chest=(-1, 0, 0), rot__head=(-2, 0, 14), rot__neck=(0, 0, 4))),
        (2.6, P(rot__chest=(-1, 0, 0), rot__head=(-2, 2, 16), rot__neck=(0, 0, 4))),
        (3.2, P(loc__hips=(-0.008, 0, -0.003), rot__hips=(0, 1, 0), rot__chest=(-2, -1, 0))),
    ])


def clip_planning():
    """Recipe clipboard held low and out to the chef's left; the torso twists toward it so the
    right mitten can tap down its near edge without the forearms crossing."""
    card_hand = (0.35, -0.36, 0.73)
    base = merge(P(**LEAN_WORK), rot__hips=(5, 0, 5), rot__spine=(3, 0, 10), rot__chest=(2, 0, 15),
                 loc__hips=(0, 0.01, -0.004), hand_L=card_hand, rot__hand_L=(-10, 0, -10),
                 rot__head=(14, 0, 6), rot__neck=(2, 0, 2),
                 rot__clavicle_L=(0, 0, -10), rot__clavicle_R=(0, 0, 24))
    up = lambda x: (x - 0.02, -0.40, 0.79)
    down = lambda x: (x, -0.42, 0.745)
    return dict(duration=2.4, loop=True, markers={"tap": 0.125}, keys=[
        (0.0, merge(base, hand_R=up(-0.03), rot__head=(13, 3, 8))),
        (0.3, merge(base, hand_R=down(-0.03), rot__hand_R=(15, 0, 0), rot__head=(15, 5, 8))),
        (0.55, merge(base, hand_R=up(-0.01), rot__head=(15, 6, 9))),
        (0.85, merge(base, hand_R=down(-0.01), rot__hand_R=(15, 0, 0), rot__head=(15, 8, 10))),
        (1.1, merge(base, hand_R=up(0.01), rot__head=(15, 8, 10))),
        (1.4, merge(base, hand_R=down(0.01), rot__hand_R=(15, 0, 0), rot__head=(15, 9, 11))),
        (1.9, merge(base, hand_R=(-0.08, -0.36, 0.80), rot__head=(11, 4, 5), rot__chest=(2, 0, 12))),
    ])


def clip_research():
    lh, rh = (0.17, -0.34, 0.77), (-0.17, -0.34, 0.77)
    base = merge(P(**LEAN_WORK), rot__hips=(4, 0, 0), rot__spine=(3, 0, 0), loc__hips=(0, 0.01, -0.004),
                 hand_L=lh, hand_R=rh, rot__hand_L=(-15, 0, -10), rot__hand_R=(-15, 0, 10),
                 rot__head=(16, 0, 0))
    return dict(duration=2.8, loop=True, keys=[
        (0.0, merge(base, rot__head=(16, 0, 6))),
        (0.7, merge(base, rot__head=(18, 2, -6))),
        (1.2, merge(base, hand_R=(-0.06, -0.37, 0.84), rot__hand_R=(-40, 0, 30), rot__head=(15, 0, 0))),
        (1.5, merge(base, hand_R=(0.02, -0.37, 0.82), rot__hand_R=(-40, 0, 40), rot__head=(15, 0, 4))),
        (1.9, merge(base, rot__head=(17, 0, 6))),
        (2.4, merge(base, rot__head=(18, -2, 2))),
    ])


# Overcooked 2 reference: the game's "Chop" animation fires an "Impact" event that advances
# chopping progress, at ~0.2 s per impact (see docs/chef-rig-report.md). So: a fast, short-stroke
# 5 Hz chop, two impacts per 0.4 s loop, with a small whole-body bounce on every hit.
CHOP_DOWN = (-0.11, -0.40, 0.707)      # wrist target at impact (fitted so the edge meets the board)
CHOP_HOLD = (0.15, -0.455, BOARD_TOP + 0.045)
CHOP_AIM_DOWN = (0.25, -0.85, -0.50)     # steady fist: blade forward, slightly inward, edge down
CHOP_AIM_UP = (0.25, -0.85, -0.30)       # wrist cocks back a little on the up-stroke
CHOP_PERIOD = 0.4
CHOP_IMPACTS = (2 / 30, 8 / 30)          # impacts land exactly on baked frames 2 and 8


def clip_chop():
    base = merge(P(**LEAN_WORK), rot__head=(14, 0, 0), hand_L=CHOP_HOLD, rot__hand_L=(10, 0, 0))
    keys = []
    for k, t_hit in enumerate(CHOP_IMPACTS):
        dx = 0.014 * k  # second chop lands a little further along the carrot
        hit = add(CHOP_DOWN, (dx, 0, 0))
        top = add(hit, (0, 0.02, 0.085))
        t0 = t_hit - 2 / 30
        keys += [
            (t0, merge(base, hand_R=top, aimdir_R=CHOP_AIM_UP, rot__chest=(3, 0, 0))),
            (t_hit, merge(base, hand_R=hit, aimdir_R=CHOP_AIM_DOWN, loc__hips=(0, 0.025, -0.022),
                          rot__chest=(5, 0, 0), rot__head=(15.5, 0, 0), rot__hat=(1.2, 0, 0),
                          hand_L=add(CHOP_HOLD, (0, 0, -0.005)))),
            (t_hit + 1 / 30, merge(base, hand_R=add(hit, (0, 0.005, 0.012)), aimdir_R=CHOP_AIM_DOWN,
                                   loc__hips=(0, 0.025, -0.017), rot__chest=(4.5, 0, 0), rot__head=(15, 0, 0))),
        ]
    return dict(duration=CHOP_PERIOD, loop=True,
                markers={"impact": CHOP_IMPACTS[0], "impact_2": CHOP_IMPACTS[1]}, keys=keys)


def clip_waiting_tool():
    watch = P(rot__head=(12, 0, -6), rot__chest=(2, 0, -3), hand_L=(0.40, -0.02, 0.60),
              hand_R=(-0.44, -0.04, 0.57), loc__hips=(0, 0, -0.004))
    check = merge(P(**LEAN_WORK), rot__hips=(8, 0, -6), rot__head=(18, 0, -4),
                  hand_R=(-0.20, -0.47, 0.70), rot__hand_R=(-20, 0, 0),
                  hand_L=(0.42, -0.06, 0.60), pole_L=BACK_POLE["L"])
    return dict(duration=3.6, loop=True, keys=[
        (0.0, watch),
        (1.2, merge(watch, rot__head=(12, -3, -10), loc__hips=(0.006, 0, -0.006))),
        (1.8, check),
        (2.3, merge(check, rot__head=(20, 4, 0))),
        (2.9, merge(watch, rot__head=(11, 0, -4))),
    ])


def clip_testing():
    dip = (-0.13, -0.46, BOARD_TOP + 0.075)
    mouth = (-0.14, -0.325, 0.96)
    base = merge(P(**LEAN_WORK), rot__hips=(6, 0, 0), rot__spine=(3, 0, 0), rot__head=(12, 0, 0),
                 hand_L=(0.42, -0.08, 0.60), pole_L=BACK_POLE["L"])
    think = merge(base, rot__hips=(2, 0, 0), rot__spine=(0, 0, 0), hand_R=(-0.34, -0.22, 0.74),
                  rot__hand_R=(-20, 0, 0), rot__head=(-6, 9, 8), rot__neck=(0, 3, 0),
                  hand_L=(0.13, -0.34, 0.92), rot__hand_L=(-30, 0, 0), pole_L=DOWN_POLE["L"])
    return dict(duration=2.6, loop=True, markers={"taste": 0.75}, keys=[
        (0.0, merge(base, hand_R=dip, rot__hand_R=(10, 0, 0))),
        (0.35, merge(base, hand_R=add(dip, (0, 0.02, 0.12)), rot__hand_R=(-10, 0, 0), rot__head=(4, 0, 0))),
        (0.75, merge(base, rot__hips=(4, 0, 0), hand_R=mouth, rot__hand_R=(-35, 0, 0), rot__head=(8, 0, 0))),
        (1.0, merge(base, rot__hips=(4, 0, 0), hand_R=mouth, rot__hand_R=(-35, 0, 0), rot__head=(7, 0, 0))),
        (1.5, think),
        (2.0, merge(think, rot__head=(-4, 6, 10))),
    ])


RAISED = (-0.42, -0.06, 1.18)


def clip_request_input():
    up = P(hand_R=RAISED, rot__hand_R=(-10, 0, 0), rot__clavicle_R=(0, 12, 0), rot__chest=(-3, -3, 0),
           rot__head=(-6, 0, 0), pole_R=(-0.70, 0.30, 0.60))
    return dict(duration=1.0, loop=False, keys=[
        (0.0, P()),
        (0.15, P(loc__hips=(0, 0, -0.02), hand_R=(-0.45, 0.0, 0.56), rot__head=(4, 0, 0))),
        (0.42, merge(up, loc__hips=(0, 0, 0.008))),
        (0.58, merge(up, rot__hand_R=(-10, 0, 18))),
        (0.74, merge(up, rot__hand_R=(-10, 0, -14))),
        (1.0, merge(up, hand_R=(-0.38, -0.12, 1.10), rot__hand_R=(-10, 0, 0))),
    ])


def clip_wait_input():
    att = P(rot__chest=(-3, 0, 0), rot__head=(-7, 0, 0), hand_R=(-0.40, -0.10, 0.66),
            rot__hand_R=(-10, 0, 0), hand_L=(0.45, -0.05, 0.58))
    return dict(duration=2.4, loop=True, keys=[
        (0.0, att),
        (0.8, merge(att, loc__hips=(0, 0, 0.006), rot__head=(-8, 3, 4))),
        (1.6, merge(att, loc__hips=(0, 0, -0.002), rot__head=(-6, -2, -3))),
    ])


def clip_blocked_react():
    shrug = P(rot__clavicle_L=(0, -14, 0), rot__clavicle_R=(0, 14, 0), rot__head=(4, -6, 24),
              rot__chest=(-2, 0, 6), hand_L=(0.46, -0.24, 0.68), hand_R=(-0.46, -0.24, 0.68),
              rot__hand_L=(-40, 25, 0), rot__hand_R=(-40, -25, 0),
              pole_L=DOWN_POLE["L"], pole_R=DOWN_POLE["R"])
    return dict(duration=1.0, loop=False, keys=[
        (0.0, P()),
        (0.18, P(rot__head=(2, 0, 26), rot__chest=(0, 0, 8), loc__hips=(0, 0.01, 0))),
        (0.5, shrug),
        (0.65, merge(shrug, rot__clavicle_L=(0, -10, 0), rot__clavicle_R=(0, 10, 0))),
        (1.0, merge(SUBDUED, rot__head=(10, 0, 14))),
    ])


def clip_blocked_wait():
    return dict(duration=3.2, loop=True, keys=[
        (0.0, merge(SUBDUED, rot__head=(10, 0, 14))),
        (1.0, merge(SUBDUED, rot__chest=(8, 0, 0), rot__head=(12, 0, 6), loc__hips=(0, 0, -0.012))),
        (1.8, merge(SUBDUED, rot__head=(6, -2, 22), rot__chest=(5, 0, 4))),
        (2.6, merge(SUBDUED, rot__head=(9, 0, 16))),
    ])


def clip_error_react():
    return dict(duration=0.8, loop=False, keys=[
        (0.0, P()),
        (0.12, P(loc__hips=(0, 0.035, 0.01), rot__chest=(-12, 0, 0), rot__spine=(-4, 0, 0), rot__head=(-10, 0, 0),
                 hand_L=(0.40, -0.22, 0.86), hand_R=(-0.40, -0.22, 0.86), rot__hand_L=(-50, 0, 0),
                 rot__hand_R=(-50, 0, 0), rot__clavicle_L=(0, -10, 0), rot__clavicle_R=(0, 10, 0),
                 pole_L=DOWN_POLE["L"], pole_R=DOWN_POLE["R"], rot__hat=(-3, 0, 0))),
        (0.3, P(loc__hips=(0, 0.02, 0.0), rot__chest=(-6, 0, 0), rot__head=(-4, 0, 0),
                hand_L=(0.42, -0.15, 0.74), hand_R=(-0.42, -0.15, 0.74), rot__hat=(2, 0, 0))),
        (0.5, merge(SUBDUED, rot__chest=(10, 0, 0), rot__head=(18, 0, 0),
                    rot__clavicle_L=(0, 10, 0), rot__clavicle_R=(0, -10, 0), loc__hips=(0, 0, -0.014))),
        (0.8, merge(SUBDUED, rot__head=(14, 0, 4))),
    ])


def clip_present_review():
    gesture = P(rot__chest=(-2, 0, -6), rot__head=(4, -4, -10), hand_R=(-0.34, -0.31, 0.70),
                rot__hand_R=(-20, -50, 0), rot__clavicle_R=(0, 0, 18), pole_R=DOWN_POLE["R"],
                hand_L=(0.42, -0.05, 0.60))
    return dict(duration=1.4, loop=False, markers={"release": 0.5}, keys=[
        (0.0, CARRY),
        (0.38, PLACE),
        (0.55, merge(PLACE, hand_L=add(PLACE_HANDS["L"], (0.03, 0.02, 0.02)), hand_R=add(PLACE_HANDS["R"], (-0.03, 0.02, 0.02)))),
        (0.85, gesture),
        (1.1, merge(gesture, rot__head=(-4, 0, 0))),
        (1.4, merge(gesture, rot__head=(-2, 0, -4), hand_R=(-0.36, -0.28, 0.68))),
    ])


def clip_wait_review():
    proud = P(rot__chest=(-4, 0, 0), rot__head=(-3, 0, 0), hand_L=(0.36, -0.02, 0.64), hand_R=(-0.36, -0.02, 0.64),
              rot__hand_L=(0, 30, 0), rot__hand_R=(0, -30, 0))
    return dict(duration=2.6, loop=True, keys=[
        (0.0, merge(proud, rot__head=(-2, 0, -4))),
        (0.9, merge(proud, rot__head=(8, 0, -12), loc__hips=(0, 0, -0.004))),
        (1.6, merge(proud, rot__head=(-5, 3, 0), loc__hips=(0, 0, 0.004))),
    ])


def clip_celebrate():
    up = P(hand_L=(0.46, -0.08, 1.12), hand_R=(-0.46, -0.08, 1.12), rot__hand_L=(-20, 0, 0),
           rot__hand_R=(-20, 0, 0), rot__clavicle_L=(0, -12, 0), rot__clavicle_R=(0, 12, 0),
           rot__head=(-10, 0, 0), pole_L=(0.70, 0.30, 0.6), pole_R=(-0.70, 0.30, 0.6))
    return dict(duration=1.0, loop=False, keys=[
        (0.0, P()),
        (0.14, P(loc__hips=(0, 0, -0.06), rot__spine=(6, 0, 0), hand_L=(0.42, -0.05, 0.50), hand_R=(-0.42, -0.05, 0.50))),
        (0.32, merge(up, loc__hips=(0, 0, 0.06), foot_L=(0, 0, 0.05), foot_R=(0, 0, 0.05), rot__hat=(-3, 0, 0))),
        (0.48, merge(up, loc__hips=(0, 0, -0.035), rot__hat=(3, 0, 0))),
        (0.68, P(rot__head=(16, 0, 0), rot__chest=(3, 0, 0), loc__hips=(0, 0, -0.01))),
        (0.84, P(rot__head=(-2, 0, 0))),
        (1.0, P()),
    ])


def clip_unknown():
    return dict(duration=4.0, loop=True, keys=[
        (0.0, P(rot__head=(2, 0, 0))),
        (0.8, P(rot__head=(0, 3, 22), rot__neck=(0, 0, 4))),
        (1.5, P(rot__head=(0, 3, 22), rot__neck=(0, 0, 4))),
        (2.2, P(rot__head=(4, -7, 0))),
        (2.8, P(rot__head=(0, -3, -20), rot__neck=(0, 0, -4))),
        (3.4, P(rot__head=(0, -3, -20), rot__neck=(0, 0, -4))),
    ])


def clip_cancel():
    return dict(duration=0.6, loop=False, markers={"release": 0.28}, keys=[
        (0.0, CARRY),
        (0.28, PLACE),
        (0.6, P()),
    ])


def clip_pickup():
    return dict(duration=0.5, loop=False, markers={"attach": 0.24}, keys=[
        (0.0, P()),
        (0.24, PLACE),
        (0.5, CARRY),
    ])


def clip_putdown():
    return dict(duration=0.5, loop=False, markers={"release": 0.26}, keys=[
        (0.0, CARRY),
        (0.26, PLACE),
        (0.5, P()),
    ])


def clip_carry_idle():
    return dict(duration=2.0, loop=True, keys=[
        (0.0, CARRY),
        (1.0, merge(CARRY, loc__hips=(0, 0, -0.006), rot__chest=(-1, 0, 0),
                    hand_L=add(CARRY_HANDS["L"], (0, 0, -0.005)), hand_R=add(CARRY_HANDS["R"], (0, 0, -0.005)),
                    rot__head=(2, 0, 4))),
    ])


def _gait(period, stride, lift, bob, lean, arm_swing, carry=False, run=False):
    """In-place gait sampled at 8 phases. The planted foot slides back at constant speed,
    so nominal ground speed = stride / (stance_fraction * period)."""
    stance = 0.55
    keys = []
    n = 8
    for i in range(n):
        ph = i / n
        pose = merge(CARRY if carry else P(), rot__hips=(lean, 0, 0), rot__spine=(lean * 0.5, 0, 0))
        hips_z = 0.0
        for sfx, off in (("L", 0.0), ("R", 0.5)):
            p = (ph + off) % 1.0
            if p < stance:
                y = -stride / 2 + stride * (p / stance)
                z = 0.0
                rx = 0.0
            else:
                q = (p - stance) / (1 - stance)
                y = stride / 2 - stride * (0.5 - 0.5 * math.cos(math.pi * q))
                z = lift * math.sin(math.pi * q)
                rx = -12 * math.sin(math.pi * q) if run else -8 * math.sin(math.pi * q)
            s = 1 if sfx == "L" else -1
            pose["foot." + sfx] = (0.0, y, z)
            pose["rot:foot_ik." + sfx] = (rx, 0, 0)
            if not carry:
                swing = -arm_swing * (y / (stride / 2))  # opposite arm to leg
                other = "R" if sfx == "L" else "L"
                hb = (0.44 * (1 if other == "L" else -1), -0.06, 0.60) if not run else \
                    (0.40 * (1 if other == "L" else -1), -0.12, 0.70)
                pose["hand." + other] = (hb[0], hb[1] - swing, hb[2] + abs(swing) * 0.25)
                if run:
                    pose["pole." + other] = (0.6 * (1 if other == "L" else -1), 0.5, 0.6)
        # body: lowest at contacts (phase 0, .5), highest mid-stance
        hips_z = -bob * math.cos(4 * math.pi * ph) * 0.5 - bob * 0.5
        yaw = 5 * math.sin(2 * math.pi * ph)
        pose["loc:hips"] = (0.012 * math.sin(2 * math.pi * ph), 0, hips_z)
        pose["rot:hips"] = (lean, 0, yaw)
        pose["rot:chest"] = (0, 0, -yaw * 1.2)
        pose["rot:head"] = (-lean * 0.6, 0, -yaw * 0.4)
        pose["rot:hat"] = (1.5 * math.sin(4 * math.pi * ph - 1.2), 0, 0)
        if carry:
            for sfx in ("L", "R"):
                pose["hand." + sfx] = add(CARRY_HANDS[sfx], (0, -0.01, hips_z))
        keys.append((ph * period, pose))
    return dict(duration=period, loop=True, keys=keys,
                nominal_speed=round(stride / (stance * period), 4))


def clip_walk():
    return _gait(period=16 / FPS, stride=0.22, lift=0.055, bob=0.022, lean=6, arm_swing=0.07)


def clip_run():
    return _gait(period=12 / FPS, stride=0.30, lift=0.08, bob=0.035, lean=12, arm_swing=0.09, run=True)


def clip_carry_walk():
    return _gait(period=16 / FPS, stride=0.20, lift=0.05, bob=0.016, lean=2, arm_swing=0.0, carry=True)


# ----------------------------------------------------------------- lifecycle clips (phase 2)
# Arrival: the chef steps out of the elevator toward the camera and waves.
def clip_arrive_wave():
    wave = P(hand_R=RAISED, rot__hand_R=(-10, 0, 0), rot__clavicle_R=(0, 12, 0), rot__chest=(-3, -4, 0),
             rot__head=(-8, 0, -6), pole_R=(-0.70, 0.30, 0.60))
    return dict(duration=1.8, loop=False, keys=[
        (0.0, P()),
        (0.15, P(loc__hips=(0, 0, -0.03), rot__spine=(4, 0, 0))),
        (0.32, P(loc__hips=(0, -0.02, 0.03), foot_L=(0, -0.04, 0.04), foot_R=(0, -0.04, 0.04), rot__hat=(-2, 0, 0))),
        (0.48, P(loc__hips=(0, 0, -0.01), rot__hat=(2, 0, 0))),
        (0.7, wave),
        (0.88, merge(wave, rot__hand_R=(-10, 0, 22))),
        (1.06, merge(wave, rot__hand_R=(-10, 0, -18))),
        (1.24, merge(wave, rot__hand_R=(-10, 0, 22))),
        (1.42, merge(wave, rot__hand_R=(-10, 0, -10))),
        (1.8, P(rot__head=(2, 0, 0))),
    ])


# Reading the order: a small ticket held up close in the left mitten, right hand steadying it.
def clip_read_ticket():
    tl = (0.17, -0.35, 0.82)
    base = P(rot__head=(16, 0, 4), rot__chest=(2, 0, 4), hand_L=tl, rot__hand_L=(-35, 0, -15),
             hand_R=(-0.17, -0.35, 0.78), rot__hand_R=(-30, 0, 15),
             rot__clavicle_L=(0, 0, -16), rot__clavicle_R=(0, 0, 16), pole_L=DOWN_POLE["L"], pole_R=DOWN_POLE["R"])
    return dict(duration=2.6, loop=True, keys=[
        (0.0, base),
        (0.7, merge(base, rot__head=(18, 0, -4))),
        (1.3, merge(base, rot__head=(14, 0, 6), loc__hips=(0, 0, 0.004))),
        (1.7, merge(base, rot__head=(20, 0, 2))),  # nod: got it
        (2.0, merge(base, rot__head=(12, 0, 2))),
    ])


# Break room: the chef perches in an Eames lounge chair, hips back on the cushion, short legs out.
SIT_HIPS = (0, 0.08, 0.04)
SIT = P(loc__hips=SIT_HIPS, rot__hips=(-16, 0, 0), rot__spine=(-4, 0, 0), rot__chest=(-2, 0, 0), rot__head=(14, 0, 0),
        foot_L=(0, -0.17, 0.19), foot_R=(0, -0.17, 0.19), rot__foot_ik_L=(-35, 0, 0), rot__foot_ik_R=(-35, 0, 0),
        hand_L=(0.42, -0.04, 0.58), hand_R=(-0.42, -0.04, 0.58), rot__hand_L=(0, 0, -10), rot__hand_R=(0, 0, 10),
        pole_L=DOWN_POLE["L"], pole_R=DOWN_POLE["R"])
MUG_REST = (-0.30, -0.20, 0.64)
MUG_LIP = (-0.10, -0.36, 0.98)


def clip_sit_down():
    return dict(duration=0.9, loop=False, keys=[
        (0.0, P()),
        (0.25, P(loc__hips=(0, 0.03, -0.05), rot__hips=(8, 0, 0), hand_L=(0.45, 0.02, 0.52), hand_R=(-0.45, 0.02, 0.52))),
        (0.55, merge(SIT, loc__hips=(0, 0.07, 0.06), foot_L=(0, -0.12, 0.12), foot_R=(0, -0.12, 0.12))),
        (0.9, SIT),
    ])


def clip_stand_up():
    return dict(duration=0.7, loop=False, keys=[
        (0.0, SIT),
        (0.3, P(loc__hips=(0, 0.02, -0.04), rot__hips=(14, 0, 0), rot__spine=(6, 0, 0),
                hand_L=(0.44, -0.10, 0.52), hand_R=(-0.44, -0.10, 0.52))),
        (0.7, P()),
    ])


def clip_sit_idle():
    return dict(duration=4.0, loop=True, keys=[
        (0.0, SIT),
        (1.2, merge(SIT, loc__hips=add(SIT_HIPS, (0, 0, -0.006)), rot__chest=(-4, 0, 0), rot__head=(10, 0, 12))),
        (2.4, merge(SIT, rot__head=(12, 0, -10), rot__chest=(-3, 0, 2))),
        (3.2, merge(SIT, foot_L=(0, -0.19, 0.21), rot__head=(15, 0, 0))),
    ])


def clip_sit_sip():
    hold = merge(SIT, hand_R=MUG_REST, rot__hand_R=(0, 0, 0), rot__clavicle_R=(0, 0, 12))
    sip = merge(hold, hand_R=MUG_LIP, rot__hand_R=(-25, 0, 0), rot__head=(-4, 0, 0), rot__clavicle_R=(0, 0, 24))
    return dict(duration=3.6, loop=True, markers={"sip": 1.3}, keys=[
        (0.0, hold),
        (0.9, merge(hold, rot__head=(12, 0, 6))),
        (1.3, sip),
        (1.9, sip),
        (2.4, hold),
        (3.0, merge(hold, rot__head=(14, 0, -6))),
    ])


def clip_sit_chat():
    talk = merge(SIT, rot__head=(8, 0, 22), rot__neck=(0, 0, 6), rot__chest=(-3, 0, 8))
    return dict(duration=3.0, loop=True, keys=[
        (0.0, talk),
        (0.5, merge(talk, hand_R=(-0.36, -0.24, 0.74), rot__hand_R=(-30, 0, 20), rot__head=(6, 0, 24))),
        (0.9, merge(talk, hand_R=(-0.32, -0.26, 0.78), rot__hand_R=(-30, 0, -10), rot__head=(4, 2, 20))),
        (1.4, merge(talk, rot__head=(10, 0, 18))),
        (2.0, merge(talk, rot__head=(4, -3, 24), loc__hips=add(SIT_HIPS, (0, 0, 0.012)))),  # laugh
        (2.3, merge(talk, rot__head=(10, 0, 22), loc__hips=SIT_HIPS)),
    ])


# Shipping (used by the serving-window flow): lower a cloche over the presented plate.
def clip_cover_dish():
    # Short arms and a round belly: lean in like PLACE and keep the hand low over the plate.
    over = (-0.12, -0.43, BOARD_TOP + 0.19)
    down = (-0.12, -0.45, BOARD_TOP + 0.115)
    base = merge(P(**LEAN_WORK), rot__hips=(14, 0, 0), rot__spine=(6, 0, 0), hand_L=(0.42, -0.05, 0.60),
                 pole_L=BACK_POLE["L"], rot__head=(16, 0, 0))
    return dict(duration=1.2, loop=False, markers={"release": 0.75}, keys=[
        (0.0, merge(base, hand_R=(-0.42, -0.10, 0.70))),
        (0.35, merge(base, hand_R=over, rot__hand_R=(-10, 0, 0))),
        (0.75, merge(base, hand_R=down, rot__hand_R=(-5, 0, 0), loc__hips=(0, 0.02, -0.01))),
        (1.2, P(rot__chest=(-3, 0, 0), rot__head=(-2, 0, 0))),
    ])


CLIPS = {
    "idle_available": clip_idle,
    "planning_recipe": clip_planning,
    "researching_book": clip_research,
    "working_chop": clip_chop,
    "waiting_tool": clip_waiting_tool,
    "testing_dish": clip_testing,
    "walk": clip_walk,
    "run": clip_run,
    "carry_idle": clip_carry_idle,
    "carry_walk": clip_carry_walk,
    "request_input": clip_request_input,
    "wait_input": clip_wait_input,
    "blocked_react": clip_blocked_react,
    "blocked_wait": clip_blocked_wait,
    "error_react": clip_error_react,
    "present_review": clip_present_review,
    "wait_review": clip_wait_review,
    "celebrate_done": clip_celebrate,
    "unknown_wait": clip_unknown,
    "cancel_cleanup": clip_cancel,
    "pickup": clip_pickup,
    "putdown": clip_putdown,
    "arrive_wave": clip_arrive_wave,
    "read_ticket": clip_read_ticket,
    "sit_down": clip_sit_down,
    "stand_up": clip_stand_up,
    "sit_idle": clip_sit_idle,
    "sit_sip": clip_sit_sip,
    "sit_chat": clip_sit_chat,
    "cover_dish": clip_cover_dish,
}
