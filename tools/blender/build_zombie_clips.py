"""Clips the zombie kit lacks, authored on the shared zombie rig into a file of their own (Deadnight #221).

Run with the pinned Blender, headless:

    blender -b --factory-startup -P tools/blender/build_zombie_clips.py -- \
        --zombie <workspace>/refs/polypizza/VlXjG0N8Eg/model.glb \
        --out game/assets/characters/zombies/clips

Writes `zombie_clips.glb` (the kit zombie's 50-bone skeleton, the kit mesh for previews, and only the clips built
here) and `clips.json` beside it (frames, events). The game adds these clips to the zombies' shared AnimationLibrary
(`ZombieRig`): same rig and track paths as every variant, so the variant files are not rebuilt.

The poses start from the kit's own: `Idle` frame 0 with the Walk's arms-forward stance filled in (build_zombies'
clean-up). Offsets are local Euler rotations in degrees per bone; the arm axes are the boss's measured ones
(build_boss.py `arms`): UpperArm X raises the hand up and in, Z spreads it (mirrored on the right), LowerArm X bends
the elbow. On the spine X pitches forward, Y yaws (the chest turns), Z rolls.
"""

import argparse
import json
import sys
from pathlib import Path

import bpy
from mathutils import Euler, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_zombies as bz
import soldier_clips as sc

# Tear_Boards: one board's work, looped while the zombie stands at the boards. The rules tear a board when a zombie's
# work reaches `seconds_per_board` (1.2 s for a walker, less by `barrier_speed`); the game plays the clip faster or
# slower so that `yank` lands on that moment (docs/design/zombies.md, "Tearing boards").
TEAR = "Tear_Boards"
TEAR_EVENTS = {"reach": 0, "grab": 9, "yank": 22, "end": 29}


def filled(arm, pose):
    out = {b.name: {"rot": Euler((0, 0, 0)).to_quaternion(), "loc": Vector()} for b in arm.pose.bones}
    for b, v in pose.items():
        out[b] = {"rot": v["rot"].copy(), "loc": v["loc"].copy()}
    return out


def arms(raise_=0, spread=0, elbow=0, right=None):
    """Both arms (the boss's measured axes); `right` overrides the right arm as (raise, spread, elbow)."""
    r = right or (raise_, spread, elbow)
    return {"UpperArm_L": (raise_, 0, spread), "UpperArm_R": (r[0], 0, -r[1]),
            "LowerArm_L": (elbow, 0, 0), "LowerArm_R": (r[2], 0, 0)}  # fmt: skip


def build(arm, probe=False):
    sc.CLIPS.clear()
    acts = {a.name: a for a in bpy.data.actions}
    every = [b.name for b in arm.pose.bones]
    idle = filled(arm, sc.sample(acts["Idle"], 0))

    # Reach: lean in, both hands up and forward to a board at chest height. Grab: the hands close on it, elbows give.
    # Pull: lean back against it, elbows bent, straining (a small shake). Yank: the chest throws back and turns, the
    # hands come back past the shoulders (the board leaves here). Follow-through: the arms fling out and down, then
    # back to the stance the next reach starts from.
    reach = sc.offset(idle, Abdomen=(20, 0, 0), Torso=(18, 0, 0), Neck=(-14, 0, 0), Head=(-10, 0, 0),
                      **arms(14, 8, -15))  # fmt: skip
    grab = sc.offset(idle, Abdomen=(16, 0, 0), Torso=(12, 0, 0), Neck=(-10, 0, 0), Head=(-6, 0, 0),
                     **arms(10, -4, 12))  # fmt: skip
    strain = sc.offset(idle, Abdomen=(-4, 0, 0), Torso=(-8, -4, 0), Neck=(4, 0, 0), Head=(4, 0, 0),
                       **arms(-4, -6, 40))  # fmt: skip
    strain2 = sc.offset(strain, Torso=(-3, 6, 0), Head=(0, 0, 4))
    yank = sc.offset(idle, Abdomen=(-12, 14, 0), Torso=(-18, 22, 0), Neck=(8, -8, 0), Head=(6, -6, 0),
                     **arms(-20, 14, 85, right=(-35, 30, 70)))  # fmt: skip
    fling = sc.offset(idle, Abdomen=(-6, 20, 0), Torso=(-8, 26, 0), Neck=(4, -10, 0),
                      **arms(-45, 35, 30, right=(-50, 45, 20)))  # fmt: skip
    settle = sc.offset(idle, Abdomen=(6, 6, 0), Torso=(4, 8, 0), **arms(-10, 10, 10))
    f = TEAR_EVENTS
    keys = [(f["reach"], idle), (6, reach), (f["grab"], grab), (14, strain), (17, strain2), (20, strain),
            (f["yank"], yank), (25, fling), (27, settle), (f["end"], idle)]  # fmt: skip
    sc.write(arm, TEAR, keys, every, "full", True, events=dict(f))

    if probe:  # the spine and arm axes, one bone turned per frame, for reading off a sheet
        keys, n = [(0, idle)], 1
        for bone in ("Abdomen", "Torso", "UpperArm_R", "LowerArm_R"):
            for ax in range(3):
                deg = [0, 0, 0]
                deg[ax] = 40
                keys.append((n, sc.offset(idle, **{bone: tuple(deg)})))
                n += 1
        sc.write(arm, "Probe", keys, every, "full", False)
        sc.CLIPS.pop("Probe")
    return [TEAR, *(["Probe"] if probe else [])]


def add_tracks(arm, names):
    ad = arm.animation_data
    ad.action = None
    for t in list(ad.nla_tracks):
        ad.nla_tracks.remove(t)
    for name in names:
        a = bpy.data.actions[name]
        track = ad.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, 0, a)
        if hasattr(strip, "action_slot") and a.slots:
            strip.action_slot = a.slots[0]
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.scale = (1, 1, 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zombie", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--probe", action="store_true", help="add a Probe clip (one bone turned per frame)")
    args = ap.parse_args(sys.argv[sys.argv.index("--") + 1 :])
    args.out.mkdir(parents=True, exist_ok=True)
    arm, body, _kit = bz.clean(args.zombie)
    names = build(arm, args.probe)
    add_tracks(arm, names)
    body.name = body.data.name = "Zombie_Mesh"
    bz.export(args.out / "zombie_clips.glb", arm, [body], True)
    spec = {
        "fps": sc.FPS,
        "bones": len(arm.data.bones),
        "clips": {n: {k: c[k] for k in ("loop", "frames", "seconds", "events")} for n, c in sc.CLIPS.items()},
    }
    (args.out / "clips.json").write_text(json.dumps(spec, indent=1) + "\n", newline="\n")
    print("ZOMBIE_CLIPS", spec)


main()
