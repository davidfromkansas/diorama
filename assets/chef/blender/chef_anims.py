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
# chopping progress (see docs/chef-rig-report.md). The kitchen is seen from above, so the stroke is
# big enough to read from there: the knife rises well above the head line, holds a beat at the top
# with the blade up, then comes down hard; two impacts per 0.8 s loop, a whole-body bounce on each.
CHOP_DOWN = (-0.11, -0.40, 0.707)      # wrist target at impact (fitted so the edge meets the board)
CHOP_HOLD = (0.15, -0.455, BOARD_TOP + 0.045)
CHOP_AIM_DOWN = (0.25, -0.85, -0.50)     # steady fist: blade forward, slightly inward, edge down
CHOP_AIM_UP = (-0.15, -0.25, 0.95)       # raised: the blade points up, so the knife reads from above
CHOP_RAISE = (-0.14, 0.12, 0.50)         # wrist at the top: about 50 cm up and out to the side, clear of the hat from above
CHOP_PERIOD = 0.8
CHOP_IMPACTS = (6 / 30, 18 / 30)         # impacts on baked frames 6 and 18; each wind-up starts 6 frames before (frame 0 opens the loop)


def clip_chop():
    base = merge(P(**LEAN_WORK), rot__head=(14, 0, 0), hand_L=CHOP_HOLD, rot__hand_L=(10, 0, 0))
    keys = []
    for k, t_hit in enumerate(CHOP_IMPACTS):
        dx = 0.014 * k  # second chop lands a little further along the carrot
        hit = add(CHOP_DOWN, (dx, 0, 0))
        top = add(hit, CHOP_RAISE)
        keys += [
            # Up to the top, a beat there, then down hard; after the hit it lifts toward the next.
            (t_hit - 6 / 30, merge(base, hand_R=top, aimdir_R=CHOP_AIM_UP, rot__chest=(-2, 0, 0), rot__head=(10, 0, 0))),
            (t_hit - 4 / 30, merge(base, hand_R=add(top, (0, 0, 0.015)), aimdir_R=CHOP_AIM_UP, rot__chest=(-3, 0, 0), rot__head=(10, 0, 0))),
            (t_hit, merge(base, hand_R=hit, aimdir_R=CHOP_AIM_DOWN, loc__hips=(0, 0.025, -0.022),
                          rot__chest=(5, 0, 0), rot__head=(15.5, 0, 0), rot__hat=(1.2, 0, 0),
                          hand_L=add(CHOP_HOLD, (0, 0, -0.005)))),
            (t_hit + 1 / 30, merge(base, hand_R=add(hit, (0, 0.005, 0.012)), aimdir_R=CHOP_AIM_DOWN,
                                   loc__hips=(0, 0.025, -0.017), rot__chest=(4.5, 0, 0), rot__head=(15, 0, 0))),
            (t_hit + 3 / 30, merge(base, hand_R=add(hit, (0, 0.02, 0.12)), aimdir_R=CHOP_AIM_DOWN, rot__chest=(2, 0, 0))),
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
    """Out of the elevator: both hands up waving at you, jumping up and down twice, then a few
    more waves standing before heading to the order rail."""
    raised_L = (-RAISED[0], RAISED[1], RAISED[2])
    wave = P(hand_R=RAISED, hand_L=raised_L, rot__clavicle_R=(0, 12, 0), rot__clavicle_L=(0, -12, 0),
             rot__chest=(-4, 0, 0), rot__head=(-10, 0, 0), pole_R=(-0.70, 0.30, 0.60), pole_L=(0.70, 0.30, 0.60))
    def tilt(deg):  # both hands wave outward together
        return dict(rot__hand_R=(-10, 0, deg), rot__hand_L=(-10, 0, -deg))
    crouch = dict(loc__hips=(0, 0, -0.07), rot__spine=(6, 0, 0))
    air = dict(loc__hips=(0, 0, 0.17), foot_L=(0, 0, 0.15), foot_R=(0, 0, 0.15), rot__hat=(-4, 0, 0))
    land = dict(loc__hips=(0, 0, -0.06), rot__hat=(4, 0, 0))
    return dict(duration=2.4, loop=False, keys=[
        (0.0, P()),
        (0.14, merge(wave, **crouch, **tilt(20))),
        (0.32, merge(wave, **air, **tilt(-20))),        # first jump
        (0.5, merge(wave, **land, **tilt(22))),
        (0.68, merge(wave, **air, **tilt(-22))),        # second jump
        (0.86, merge(wave, **land, **tilt(20))),
        (1.04, merge(wave, loc__hips=(0, 0, 0.0), **tilt(-20))),
        (1.24, merge(wave, **tilt(22))),
        (1.44, merge(wave, **tilt(-20))),
        (1.64, merge(wave, **tilt(20))),
        (1.84, merge(wave, **tilt(-10))),
        (2.4, P(rot__head=(2, 0, 0))),
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


# Restaurant guests, seated at a table (top about 0.71 chef units high, their plate about 0.41
# ahead of the root). Their table partner sits straight across, so talking faces forward.
TABLE_TOP = 0.714
PLATE = (-0.06, -0.41, TABLE_TOP)
LEAN_TABLE = dict(rot__hips=(-4, 0, 0), rot__spine=(6, 0, 0), rot__chest=(4, 0, 0),
                  rot__clavicle_L=(0, 0, -14), rot__clavicle_R=(0, 0, 14))


def clip_sit_talk():
    """Telling a story across the table: hands take turns at chest height, nods and a little
    torso turn with each point."""
    base = merge(SIT, **LEAN_TABLE, rot__head=(6, 0, 0), hand_L=(0.30, -0.26, 0.76), hand_R=(-0.30, -0.26, 0.76))
    return dict(duration=3.2, loop=True, keys=[
        (0.0, base),
        (0.4, merge(base, hand_R=(-0.24, -0.34, 0.86), rot__hand_R=(-35, 0, 25), rot__chest=(4, 0, -6), rot__head=(2, 0, -4))),
        (0.8, merge(base, hand_R=(-0.30, -0.30, 0.82), rot__hand_R=(-20, 0, -15), rot__head=(10, 0, -2))),
        (1.3, merge(base, rot__head=(4, 0, 2))),
        (1.7, merge(base, hand_L=(0.24, -0.34, 0.86), rot__hand_L=(-35, 0, -25), rot__chest=(4, 0, 6), rot__head=(2, 0, 5))),
        (2.1, merge(base, hand_L=(0.30, -0.30, 0.82), rot__hand_L=(-20, 0, 15), rot__head=(11, 0, 3))),
        (2.6, merge(base, rot__head=(5, 0, 0))),
    ])


def clip_sit_laugh():
    """A big laugh: thrown back, shoulders shaking, a hand on the belly, the other patting the table."""
    back = merge(SIT, rot__hips=(-20, 0, 0), rot__chest=(-4, 0, 0), rot__head=(-4, 0, 0),
                 hand_L=(0.16, -0.30, 0.68), rot__hand_L=(0, 0, -30), hand_R=(-0.26, -0.33, TABLE_TOP + 0.03),
                 rot__clavicle_L=(0, 6, -8), rot__clavicle_R=(0, -6, 8))
    up = lambda m: merge(m, loc__hips=add(SIT_HIPS, (0, 0, 0.014)), rot__clavicle_L=(0, 12, -8), rot__clavicle_R=(0, -12, 8))
    return dict(duration=2.4, loop=True, keys=[
        (0.0, back),
        (0.2, up(merge(back, hand_R=(-0.26, -0.33, TABLE_TOP + 0.09)))),
        (0.4, back),
        (0.6, up(merge(back, rot__head=(-8, 0, 4)))),
        (0.8, merge(back, hand_R=(-0.26, -0.33, TABLE_TOP + 0.09))),
        (1.0, up(merge(back, rot__head=(-6, 0, -3)))),
        (1.3, merge(back, rot__hips=(-16, 0, 0), rot__head=(0, 0, 0))),
        (1.8, merge(back, rot__hips=(-12, 0, 0), rot__head=(2, 0, 6), hand_R=(-0.30, -0.30, TABLE_TOP + 0.03))),
    ])


def clip_sit_gesture():
    """Expressive: hands thrown wide ("can you believe it"), a point across the table, a shrug."""
    base = merge(SIT, **LEAN_TABLE, rot__head=(6, 0, 0), hand_L=(0.30, -0.26, 0.76), hand_R=(-0.30, -0.26, 0.76))
    wide = merge(base, hand_L=(0.44, -0.22, 0.94), hand_R=(-0.44, -0.22, 0.94), rot__hand_L=(-40, 0, -40), rot__hand_R=(-40, 0, 40),
                 rot__chest=(-4, 0, 0), rot__head=(-6, 0, 0), pole_L=BACK_POLE["L"], pole_R=BACK_POLE["R"])
    point = merge(base, hand_R=(-0.12, -0.42, 0.88), rot__hand_R=(-60, 0, 0), rot__chest=(6, 0, -8), rot__head=(4, 0, -4))
    shrug = merge(base, hand_L=(0.38, -0.18, 0.84), hand_R=(-0.38, -0.18, 0.84), rot__hand_L=(-50, 0, -30), rot__hand_R=(-50, 0, 30),
                  rot__clavicle_L=(0, 14, -6), rot__clavicle_R=(0, -14, 6), rot__head=(4, 14, 0))
    return dict(duration=3.6, loop=True, keys=[
        (0.0, base),
        (0.45, wide),
        (1.0, wide),
        (1.4, point),
        (1.6, merge(point, hand_R=(-0.12, -0.44, 0.86))),
        (1.8, point),
        (2.3, shrug),
        (2.8, shrug),
    ])


def clip_sit_eat():
    """Eating from the plate in front: lean in, scoop with the spoon, bring it up, chew."""
    lean = merge(SIT, rot__hips=(-2, 0, 0), rot__spine=(10, 0, 0), rot__chest=(8, 0, 0), rot__head=(18, 0, 0),
                 loc__hips=add(SIT_HIPS, (0, -0.02, 0)), rot__clavicle_L=(0, 0, -16), rot__clavicle_R=(0, 0, 22),
                 hand_L=(0.24, -0.30, TABLE_TOP + 0.03), rot__hand_L=(0, 0, -20),
                 pole_R=DOWN_POLE["R"])
    scoop = merge(lean, hand_R=(-0.08, -0.36, TABLE_TOP + 0.05), rot__hand_R=(20, 0, 10))
    lift = merge(lean, rot__spine=(4, 0, 0), rot__chest=(2, 0, 0), rot__head=(4, 0, 0),
                 hand_R=(-0.09, -0.33, 0.98), rot__hand_R=(-30, 0, 10), rot__clavicle_R=(0, 0, 26))
    chew = lambda nod: merge(lean, rot__spine=(6, 0, 0), rot__head=(10 + nod, 0, 0), hand_R=(-0.20, -0.32, TABLE_TOP + 0.08), rot__hand_R=(0, 0, 10))
    return dict(duration=3.0, loop=True, markers={"bite": 1.0}, keys=[
        (0.0, chew(0)),
        (0.45, scoop),
        (0.65, merge(scoop, hand_R=(-0.04, -0.37, TABLE_TOP + 0.05))),
        (1.0, lift),
        (1.25, lift),
        (1.6, chew(6)),
        (1.9, chew(0)),
        (2.2, chew(6)),
        (2.5, chew(0)),
    ])


def clip_sit_cheer():
    """Their dish arrives: both hands up, a happy bounce, then settle back."""
    up = merge(SIT, rot__hips=(-12, 0, 0), rot__head=(-8, 0, 0), hand_L=(0.30, -0.12, 1.12), hand_R=(-0.30, -0.12, 1.12),
               rot__hand_L=(-60, 0, 0), rot__hand_R=(-60, 0, 0), rot__clavicle_L=(0, 16, -6), rot__clavicle_R=(0, -16, 6),
               pole_L=BACK_POLE["L"], pole_R=BACK_POLE["R"])
    hop = merge(up, loc__hips=add(SIT_HIPS, (0, 0, 0.02)))
    return dict(duration=1.6, loop=False, keys=[
        (0.0, SIT),
        (0.3, up),
        (0.5, hop),
        (0.7, up),
        (0.9, hop),
        (1.1, up),
        (1.6, SIT),
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


# ----------------------------------------------------------------- pull requests
def clip_merge_ready():
    """Checks passed: a fist pump with a little hop before waiting at the pass."""
    pump = P(hand_R=(-0.46, -0.10, 1.16), rot__hand_R=(-30, 0, 0), rot__clavicle_R=(0, 12, 0),
             pole_R=(-0.70, 0.30, 0.6), rot__chest=(-6, 0, -4), rot__head=(-10, 0, -6),
             hand_L=(0.42, -0.06, 0.62))
    return dict(duration=1.2, loop=False, keys=[
        (0.0, P()),
        (0.16, P(loc__hips=(0, 0, -0.04), rot__spine=(5, 0, 0), hand_R=(-0.40, -0.10, 0.60))),
        (0.36, merge(pump, loc__hips=(0, 0, 0.045), foot_L=(0, 0, 0.035), foot_R=(0, 0, 0.035), rot__hat=(-3, 0, 0))),
        (0.52, merge(pump, loc__hips=(0, 0, -0.02), hand_R=(-0.46, -0.10, 1.04), rot__hat=(2, 0, 0))),
        (0.68, merge(pump, hand_R=(-0.46, -0.10, 1.18))),
        (0.86, merge(pump, hand_R=(-0.46, -0.10, 1.02))),
        (1.2, P(rot__chest=(-4, 0, 0), rot__head=(-3, 0, 0), hand_L=(0.34, 0.02, 0.62), hand_R=(-0.34, 0.02, 0.62),
                rot__hand_L=(0, 40, 0), rot__hand_R=(0, -40, 0))),
    ])


def clip_merge_ready_wait():
    """Ready to merge: hands on hips, rocking on its toes, nodding at you now and then."""
    hips = P(rot__chest=(-5, 0, 0), rot__head=(-4, 0, 0), hand_L=(0.34, 0.02, 0.62), hand_R=(-0.34, 0.02, 0.62),
             rot__hand_L=(0, 40, 0), rot__hand_R=(0, -40, 0), rot__clavicle_L=(0, 4, 0), rot__clavicle_R=(0, -4, 0))
    return dict(duration=2.4, loop=True, keys=[
        (0.0, hips),
        (0.4, merge(hips, loc__hips=(0, 0, 0.018), foot_L=(0, 0, 0.012), foot_R=(0, 0, 0.012))),
        (0.8, merge(hips, loc__hips=(0, 0, 0))),
        (1.2, merge(hips, rot__head=(8, 0, 6))),
        (1.45, merge(hips, rot__head=(-6, 0, 6))),
        (1.7, merge(hips, rot__head=(6, 0, 4))),
        (2.0, merge(hips, rot__head=(-4, 0, 0), loc__hips=(0, 0, 0.012))),
    ])


def clip_fix_react():
    """Needs a fix: a facepalm, then a sigh."""
    palm = P(hand_R=(-0.10, -0.27, 1.06), rot__hand_R=(-85, 0, 20), rot__clavicle_R=(0, 10, 14),
             pole_R=DOWN_POLE["R"], rot__head=(16, 0, -4), rot__neck=(6, 0, 0), rot__chest=(6, 0, 0),
             hand_L=(0.45, -0.02, 0.56))
    return dict(duration=1.3, loop=False, keys=[
        (0.0, P()),
        (0.2, P(rot__head=(-6, 0, 0), rot__chest=(-3, 0, 0))),
        (0.45, palm),
        (0.75, merge(palm, rot__head=(20, 0, 4), loc__hips=(0, 0, -0.01))),
        (0.95, merge(palm, rot__head=(18, 0, -6))),
        (1.3, merge(SUBDUED, rot__head=(8, 0, 10))),
    ])


def clip_fix_wait():
    """Needs a fix: scratches its head under the hat, then taps its chin, thinking it over."""
    scratch = P(hand_R=(-0.34, -0.06, 1.06), rot__hand_R=(-40, 0, 30), rot__clavicle_R=(0, 12, 0),
                pole_R=(-0.70, 0.30, 0.6), rot__head=(6, 0, 14), rot__chest=(3, 0, 4),
                hand_L=(0.45, -0.02, 0.56))
    chin = P(hand_R=(-0.10, -0.32, 0.88), rot__hand_R=(-60, 0, 10), rot__clavicle_R=(0, 6, 12),
             pole_R=DOWN_POLE["R"], rot__head=(-4, 0, -8), rot__chest=(2, 0, 0),
             hand_L=(0.20, -0.30, 0.74), rot__clavicle_L=(0, 0, -14), pole_L=DOWN_POLE["L"])
    return dict(duration=4.0, loop=True, keys=[
        (0.0, merge(SUBDUED, rot__head=(8, 0, 10))),
        (0.5, scratch),
        (0.7, merge(scratch, hand_R=(-0.31, -0.08, 1.09))),
        (0.9, scratch),
        (1.1, merge(scratch, hand_R=(-0.31, -0.08, 1.09))),
        (1.3, scratch),
        (1.9, chin),
        (2.3, merge(chin, hand_R=(-0.10, -0.33, 0.86), rot__head=(-6, 0, -12))),
        (2.7, merge(chin, rot__head=(-2, 0, -4))),
        (3.1, merge(chin, hand_R=(-0.10, -0.33, 0.86))),
        (3.6, merge(SUBDUED, rot__head=(6, 0, 8))),
    ])


# ----------------------------------------------------------------- the gong and the manager
# A chef that needs you strikes the gong with a felt mallet (prop_gong_mallet, right hand), then
# waits; the manager (the head chef) comes over and they talk until you answer.
GONG_STRIKE = (-0.12, -0.43, 0.92)        # wrist at impact: the mallet head lands 0.45 ahead of it


def clip_strike_gong():
    """A big wind-up over the right shoulder, the whole body turning into the swing, a little
    recoil as the mallet bounces off the gong, then standing proud while it rings."""
    wind = P(hand_R=(-0.40, 0.08, 1.04), rot__hand_R=(-70, 0, 10), rot__clavicle_R=(0, 14, 0),
             pole_R=(-0.70, 0.30, 0.60), rot__chest=(-6, 0, -18), rot__hips=(0, 0, -8),
             loc__hips=(0, 0.02, 0), hand_L=(0.40, -0.22, 0.72), rot__head=(-6, 0, -4))
    hit = P(hand_R=GONG_STRIKE, rot__hand_R=(-10, 0, 0), rot__clavicle_R=(0, 0, 18), pole_R=DOWN_POLE["R"],
            rot__chest=(6, 0, 12), rot__hips=(8, 0, 8), loc__hips=(0, -0.03, -0.012), rot__spine=(4, 0, 0),
            hand_L=(0.42, -0.08, 0.64), rot__head=(4, 0, 6))
    return dict(duration=1.8, loop=False, markers={"impact": 0.75}, keys=[
        (0.0, P()),
        (0.38, wind),
        (0.62, merge(hit, hand_R=(-0.30, -0.24, 1.0), rot__hand_R=(-40, 0, 5), rot__chest=(0, 0, 0))),
        (0.75, hit),
        (0.9, merge(hit, hand_R=(-0.22, -0.34, 0.98), rot__hand_R=(-25, 0, 0))),
        (1.3, P(hand_R=(-0.42, -0.10, 0.78), rot__hand_R=(-20, 0, 0), rot__chest=(-5, 0, 0), rot__head=(-8, 0, 0),
                hand_L=(0.36, 0.0, 0.62), rot__hand_L=(0, 40, 0))),
        (1.8, P()),
    ])


def clip_talk_reply():
    """Waiting chef talking with the manager: listens and nods, explains with a hand, shrugs."""
    base = P(rot__chest=(-3, 0, 0), rot__head=(2, 0, 0), hand_L=(0.40, -0.12, 0.62), hand_R=(-0.40, -0.12, 0.62))
    explain = merge(base, hand_R=(-0.28, -0.32, 0.88), rot__hand_R=(-35, 0, 25), rot__chest=(4, 0, -6), rot__head=(0, 0, -4))
    shrug = merge(base, hand_L=(0.38, -0.18, 0.84), hand_R=(-0.38, -0.18, 0.84), rot__hand_L=(-50, 0, -30), rot__hand_R=(-50, 0, 30),
                  rot__clavicle_L=(0, 14, -6), rot__clavicle_R=(0, -14, 6), rot__head=(4, 14, 0))
    return dict(duration=4.8, loop=True, keys=[
        (0.0, base),
        (0.4, merge(base, rot__head=(12, 0, 0))),             # nod
        (0.7, merge(base, rot__head=(-2, 0, 0))),
        (1.0, merge(base, rot__head=(11, 0, 0))),
        (1.4, base),
        (1.8, explain),
        (2.2, merge(explain, hand_R=(-0.30, -0.28, 0.82), rot__hand_R=(-20, 0, -15))),
        (2.6, explain),
        (3.1, shrug),
        (3.6, merge(shrug, rot__head=(6, 10, 0))),
        (4.2, merge(base, rot__head=(8, 0, 0))),
        (4.8, base),
    ])


def clip_manager_talk():
    """The head chef talking a chef through it: points with the wooden spoon, wags it, a hand on
    the hip, nods and a reassuring open hand."""
    hip = dict(hand_L=(0.34, 0.02, 0.62), rot__hand_L=(0, 40, 0), rot__clavicle_L=(0, 4, 0))
    base = P(rot__chest=(-4, 0, 0), rot__head=(-2, 0, 0), hand_R=(-0.38, -0.20, 0.80), rot__hand_R=(-20, 0, 0), **hip)
    point = merge(base, hand_R=(-0.14, -0.42, 0.92), rot__hand_R=(-55, 0, 0), rot__chest=(6, 0, -8), rot__head=(4, 0, -4))
    open_hand = merge(base, hand_L=(0.30, -0.32, 0.84), rot__hand_L=(-40, 0, -30), rot__chest=(2, 0, 6), rot__head=(6, 0, 4))
    return dict(duration=5.2, loop=True, keys=[
        (0.0, base),
        (0.5, point),
        (0.75, merge(point, rot__hand_R=(-55, 0, 18))),       # wag the spoon
        (1.0, merge(point, rot__hand_R=(-55, 0, -16))),
        (1.25, merge(point, rot__hand_R=(-55, 0, 14))),
        (1.6, base),
        (2.0, merge(base, rot__head=(10, 0, 0))),             # nod while listening
        (2.4, merge(base, rot__head=(-1, 0, 0))),
        (2.8, merge(base, rot__head=(9, 0, 2))),
        (3.3, open_hand),
        (3.8, merge(open_hand, hand_L=(0.32, -0.30, 0.80), rot__head=(8, 0, 6))),
        (4.4, merge(base, rot__head=(4, -8, 0))),
        (5.2, base),
    ])


# ----------------------------------------------------------------- the break room
# Machines are scaled to the chef (BreakRoom.swift): the arcade's control panel at 0.75 chef units,
# just past the reach of a counter (0.43 ahead); the vending machine's buttons at 0.82; the espresso
# machine on a worktop-height bar, its buttons at 0.72 and its group head at 0.66.
ARCADE_STICK = (0.13, -0.45, 0.76)
ARCADE_BUTTONS = (-0.15, -0.45, 0.77)


def clip_play_arcade():
    """Gaming: left hand wiggling the joystick, right hand mashing buttons, bobbing along, leaning
    in for the hard part, and a fist pump when it wins."""
    base = merge(P(**LEAN_WORK), rot__hips=(6, 0, 0), rot__head=(-6, 0, 0), hand_L=ARCADE_STICK, hand_R=ARCADE_BUTTONS,
                 rot__hand_L=(-10, 0, 0), rot__hand_R=(-10, 0, 0))
    def at(t, dl=(0, 0, 0), dr=(0, 0, 0), **kw):
        return (t, merge(base, hand_L=add(ARCADE_STICK, dl), hand_R=add(ARCADE_BUTTONS, dr), **kw))
    tap = (0, 0, -0.03)
    win = P(hand_R=(-0.46, -0.10, 1.16), rot__hand_R=(-30, 0, 0), rot__clavicle_R=(0, 12, 0), pole_R=(-0.70, 0.30, 0.6),
            rot__chest=(-6, 0, -4), rot__head=(-10, 0, -6), hand_L=(0.40, -0.12, 0.66), loc__hips=(0, 0, 0.03))
    return dict(duration=6.0, loop=True, markers={"win": 4.6}, keys=[
        at(0.0),
        at(0.3, dl=(0.04, 0, 0), dr=tap),
        at(0.55, dl=(-0.03, 0.02, 0)),
        at(0.8, dl=(0.0, -0.03, 0), dr=tap, loc__hips=(0, 0, -0.01)),
        at(1.05, dl=(-0.04, 0, 0)),
        at(1.3, dl=(0.03, 0.02, 0), dr=tap),
        at(1.6, rot__hips=(10, 0, 0), rot__spine=(6, 0, 0), rot__head=(4, 0, 0)),          # leaning in
        at(1.8, dl=(0.04, 0, 0), dr=tap, rot__hips=(10, 0, 0), rot__spine=(6, 0, 0), rot__head=(4, 0, 0)),
        at(2.0, dl=(-0.04, 0, 0), dr=tap, rot__hips=(10, 0, 0), rot__spine=(6, 0, 0), rot__head=(4, 0, 0)),
        at(2.2, dl=(0.04, 0, 0), dr=tap, rot__hips=(10, 0, 0), rot__spine=(6, 0, 0), rot__head=(4, 0, 0)),
        at(2.4, dl=(-0.04, 0, 0), dr=tap, rot__hips=(10, 0, 0), rot__spine=(6, 0, 0), rot__head=(4, 0, 0)),
        at(2.8, dl=(0, -0.02, 0), loc__hips=(0, 0, -0.012)),
        at(3.2, dl=(0.03, 0, 0), dr=tap),
        at(3.5, dl=(-0.03, 0.02, 0), loc__hips=(0, 0, -0.012)),
        at(3.8, dr=tap),
        at(4.1, dl=(0.04, 0, 0), dr=tap),
        (4.6, win),
        (4.9, merge(win, hand_R=(-0.46, -0.10, 1.04), loc__hips=(0, 0, -0.01))),
        (5.15, merge(win, loc__hips=(0, 0, 0.03))),
        at(5.6),
    ])


VEND_BUTTONS = (-0.30, -0.46, 0.82)


def clip_use_vending():
    """Picks a soda: presses a few buttons, waits for the clunk, crouches to the tray, comes up with it."""
    look = P(rot__head=(-10, 0, -6), rot__chest=(-2, 0, -4), hand_L=(0.40, -0.10, 0.62))
    press = merge(look, hand_R=VEND_BUTTONS, rot__hand_R=(-50, 0, 0), rot__clavicle_R=(0, 0, 14))
    crouch = P(loc__hips=(0, -0.01, -0.06), rot__hips=(24, 0, 0), rot__spine=(12, 0, 0), rot__head=(12, 0, 0),
               hand_R=(-0.18, -0.46, 0.48), rot__hand_R=(-20, 0, 0),
               hand_L=(0.34, -0.20, 0.50), pole_R=DOWN_POLE["R"], pole_L=DOWN_POLE["L"])
    return dict(duration=3.4, loop=False, markers={"grab": 2.3}, keys=[
        (0.0, P()),
        (0.35, press),
        (0.5, merge(press, hand_R=add(VEND_BUTTONS, (0, -0.03, 0)))),
        (0.7, press),
        (0.85, merge(press, hand_R=add(VEND_BUTTONS, (0, -0.03, -0.06)))),
        (1.05, merge(press, hand_R=add(VEND_BUTTONS, (0, 0, -0.06)))),
        (1.5, merge(look, hand_R=(-0.42, -0.10, 0.62), rot__head=(4, 0, 0))),   # the clunk
        (2.0, crouch),
        (2.3, merge(crouch, hand_R=(-0.18, -0.48, 0.44))),
        (2.8, P(hand_R=(-0.30, -0.20, 0.64), rot__head=(-4, 0, 0))),
        (3.4, P(hand_R=(-0.30, -0.20, 0.64))),
    ])


def clip_brew_espresso():
    """Pulls a shot: presses the button, waits with a hand on the hip, takes the cup from under
    the group head."""
    press = P(hand_R=(-0.10, -0.50, 0.72), rot__hand_R=(-55, 0, 0), rot__clavicle_R=(0, 0, 16), rot__head=(6, 0, 0),
              rot__hips=(6, 0, 0), hand_L=(0.40, -0.10, 0.62))
    wait = P(hand_R=(-0.34, 0.02, 0.62), rot__hand_R=(0, -40, 0), hand_L=(0.34, 0.02, 0.62), rot__hand_L=(0, 40, 0),
             rot__head=(8, 0, 6), rot__chest=(-3, 0, 0))
    take = P(hand_R=(-0.06, -0.50, 0.64), rot__hand_R=(0, 0, 0), rot__clavicle_R=(0, 0, 18), rot__hips=(8, 0, 0),
             rot__spine=(4, 0, 0), rot__head=(10, 0, 0), hand_L=(0.40, -0.10, 0.62), pole_R=DOWN_POLE["R"])
    return dict(duration=3.6, loop=False, markers={"grab": 2.6}, keys=[
        (0.0, P()),
        (0.4, press),
        (0.55, merge(press, hand_R=(-0.10, -0.52, 0.70))),
        (0.8, press),
        (1.3, wait),
        (1.8, merge(wait, rot__head=(10, 0, -4))),
        (2.3, merge(wait, rot__head=(6, 0, 4))),
        (2.6, take),
        (3.1, P(hand_R=MUG_REST, rot__hand_R=(0, 0, 0), rot__clavicle_R=(0, 0, 12))),
        (3.6, P(hand_R=MUG_REST, rot__hand_R=(0, 0, 0), rot__clavicle_R=(0, 0, 12))),
    ])


def clip_stand_sip():
    """Standing about with a coffee or a can: sips, looks around, a little weight shift."""
    hold = P(hand_R=MUG_REST, rot__hand_R=(0, 0, 0), rot__clavicle_R=(0, 0, 12), hand_L=(0.42, -0.06, 0.60))
    sip = merge(hold, hand_R=MUG_LIP, rot__hand_R=(-25, 0, 0), rot__head=(-6, 0, 0), rot__clavicle_R=(0, 0, 24))
    return dict(duration=4.2, loop=True, markers={"sip": 1.3}, keys=[
        (0.0, hold),
        (0.8, merge(hold, rot__head=(4, 0, 10), loc__hips=(0.01, 0, 0))),
        (1.3, sip),
        (1.9, sip),
        (2.4, hold),
        (3.2, merge(hold, rot__head=(2, 0, -12), loc__hips=(-0.01, 0, 0))),
    ])


def clip_stand_listen():
    """Listening in a circle: nods along, tilts the head, hands loosely clasped, shifts its weight."""
    base = P(hand_L=(0.20, -0.30, 0.60), hand_R=(-0.20, -0.30, 0.60), rot__hand_L=(0, 0, -30), rot__hand_R=(0, 0, 30),
             rot__chest=(-2, 0, 0), rot__head=(4, 0, 0))
    return dict(duration=4.2, loop=True, keys=[
        (0.0, base),
        (0.5, merge(base, rot__head=(13, 0, 0))),
        (0.8, merge(base, rot__head=(2, 0, 0))),
        (1.1, merge(base, rot__head=(12, 0, 0))),
        (1.6, merge(base, rot__head=(4, 10, 6), loc__hips=(0.012, 0, 0))),
        (2.6, merge(base, rot__head=(6, 10, 6), loc__hips=(0.012, 0, 0))),
        (3.1, merge(base, rot__head=(12, 0, 0))),
        (3.6, merge(base, rot__head=(3, -6, -4), loc__hips=(-0.006, 0, 0))),
    ])


def clip_stand_laugh():
    """A big standing laugh: thrown back, a hand on the belly, shoulders shaking, a knee slap."""
    back = P(rot__hips=(-8, 0, 0), rot__chest=(-6, 0, 0), rot__head=(-12, 0, 0), hand_L=(0.16, -0.36, 0.62),
             rot__hand_L=(0, 0, -30), hand_R=(-0.42, -0.10, 0.62), rot__clavicle_L=(0, 6, -8), rot__clavicle_R=(0, -6, 8))
    up = lambda m: merge(m, loc__hips=(0, 0, 0.018), rot__clavicle_L=(0, 12, -8), rot__clavicle_R=(0, -12, 8))
    slap = merge(back, rot__hips=(14, 0, 0), rot__spine=(8, 0, 0), rot__head=(6, 0, 0), hand_R=(-0.26, -0.40, 0.36),
                 pole_R=DOWN_POLE["R"], loc__hips=(0, 0, -0.03))
    return dict(duration=2.6, loop=True, keys=[
        (0.0, back),
        (0.2, up(back)),
        (0.4, back),
        (0.6, up(merge(back, rot__head=(-14, 0, 4)))),
        (0.8, back),
        (1.1, slap),
        (1.35, merge(slap, hand_R=(-0.26, -0.40, 0.44))),
        (1.6, slap),
        (2.0, up(back)),
        (2.3, merge(back, rot__head=(-8, 0, -4))),
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
    "sit_talk": clip_sit_talk,
    "sit_laugh": clip_sit_laugh,
    "sit_gesture": clip_sit_gesture,
    "sit_eat": clip_sit_eat,
    "sit_cheer": clip_sit_cheer,
    "cover_dish": clip_cover_dish,
    "merge_ready": clip_merge_ready,
    "merge_ready_wait": clip_merge_ready_wait,
    "fix_react": clip_fix_react,
    "fix_wait": clip_fix_wait,
    "strike_gong": clip_strike_gong,
    "talk_reply": clip_talk_reply,
    "manager_talk": clip_manager_talk,
    "play_arcade": clip_play_arcade,
    "use_vending": clip_use_vending,
    "brew_espresso": clip_brew_espresso,
    "stand_sip": clip_stand_sip,
    "stand_listen": clip_stand_listen,
    "stand_laugh": clip_stand_laugh,
}
