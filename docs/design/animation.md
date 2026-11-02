# Animation

How the third-person Soldier moves and uses his weapons: the clip list, how clips are named, the upper/lower body
split the AnimationTree wires, the event frames gameplay listens to, and how weapons attach to the hand. The clips
come from one script, so this page and the file cannot drift:
`tools/blender/soldier_clips.py` (it also writes `clips.json` beside the `.glb` with the same data).

## The character file

| | |
| --- | --- |
| Source | the kit Soldier (Quaternius Toon Shooter Game Kit, CC0), cleaned with the kit's rig-sharing recipe |
| Output | `game/assets/characters/soldier/soldier.glb` and `clips.json` (built, see [Rebuilding](#rebuilding)) |
| Rig | `CharacterArmature`, 43 bones, at `CharacterArmature/Skeleton3D` in Godot; object scale 1 |
| Triangles | 5,828 (Body 4,388, Head 1,352, two shoulder pads 44 each): inside the 6k player budget of the [style bible](style.md#budgets-proposed-for-the-web) |
| Clips | 35: the kit's 14, plus 21 authored here |
| Frame rate | 24 fps; every frame number on this page is at 24 fps |
| Root motion | none: the controller moves the body, clips play in place |

## Naming

- **`<Action>_<Class>`** for anything a weapon changes: `Aim_Rifle`, `Fire_Shotgun`, `Reload_Pistol`,
  `Swing_Melee`, `Equip_Melee`. Classes: **Rifle, Shotgun, Pistol, Melee**.
- **Bare names** for whole-body clips: `Idle`, `Walk`, `Run`, `Downed`; a whole-body clip with a variant is
  `<State>_<Variant>`: `Downed_Idle`, `Downed_Crawl`, `Revive_Kneel` ([Downed and revive](#downed-and-revive)).
- **Kit names stay** for kit clips we use as they are: `HitReact` is the hit, `Death` is going down. Renaming them
  would break the other kit characters that share the library.

Which weapon is which class: lever rifle is Rifle, double shotgun is Shotgun, baseball bat and fire axe are Melee.
The revolver and the flare gun are Pistol, the Tommy gun Rifle, the crowbar Melee
([Weapons in the hands](weapon-hold.md#which-weapon-is-which)). The night plays `Swing` or `Fire` on every
`shot_fired` ([attacks](weapon-hold.md#attacks-on-the-soldier)).

## Clips

`upper` clips key the [upper-body bones](#upperlower-split) and hold the standing pose on the rest; `full` clips
move every bone. Events are frames of the clip.

| Clip | Layer | Plays | Frames | Events |
| --- | --- | --- | --- | --- |
| Idle | full | loop | 40 (1.67 s) | - |
| Walk | full | loop | 24 (1.0 s) | step_left 0, step_right 12 |
| Run | full | loop | 17 (0.71 s) | - |
| HitReact | full | once | 10 (0.42 s) | - |
| Death | full | once | 18 (0.75 s) | - |
| Downed | full | loop | 48 (2.0 s) | - (superseded by `Downed_Idle`, not played) |
| Aim_Rifle | upper | loop | 48 (2.0 s) | - |
| Fire_Rifle | upper | once | 8 (0.33 s) | muzzle 0, can_fire_again 8 |
| Reload_Rifle | upper | once | 62 (2.58 s) | round_in 20, 32, 44; lever 56; can_fire_again 62 |
| Aim_Shotgun | upper | loop | 48 (2.0 s) | - |
| Fire_Shotgun | upper | once | 14 (0.58 s) | muzzle 0, can_fire_again 14 |
| Reload_Shotgun | upper | once | 40 (1.67 s) | break_open 6, shells_in 26, snap_shut 34, can_fire_again 40 |
| Aim_Pistol | upper | loop | 48 (2.0 s) | - |
| Fire_Pistol | upper | once | 6 (0.25 s) | muzzle 0, can_fire_again 6 |
| Reload_Pistol | upper | once | 28 (1.17 s) | mag_out 6, mag_in 22, can_fire_again 28 |
| Aim_Melee | upper | loop | 48 (2.0 s) | - |
| Swing_Melee | upper | once | 22 (0.92 s) | whoosh 6, hit_start 9, hit_end 12, can_swing_again 22 |
| Equip_<Class> | upper | once | 10 (0.42 s) | weapon_visible 2, ready 10 |
| Unequip_<Class> | upper | once | 10 (0.42 s) | weapon_hidden 8 |

Also in the file, unused for now: `Idle_Shoot` and `Run_Gun` (the kit's gun clips, which the Rifle and Shotgun clips
and the [sprint carry](#sprint-carry) start from), `Punch`, `Wave`, `Yes`, `No`, `Duck`, `Jump`, `Jump_Idle`,
`Jump_Land`.

What each event is for:

| Event | Gameplay does |
| --- | --- |
| muzzle | flash, sound and the shot (fire is at frame 0: input to bang has no delay) |
| can_fire_again | the earliest the next shot or a reload may start; the rest of the clip is settle |
| round_in, shells_in, mag_in | the reload sound; ammo is added at the last one, so an interrupted reload keeps what went in |
| lever, break_open, snap_shut, mag_out | sounds |
| hit_start .. hit_end | the melee hit window: test the weapon's hit shape on these frames only |
| whoosh | the swing sound |
| weapon_visible, weapon_hidden | show or hide the weapon model (it appears in the hand on the way up and leaves on the way down) |
| ready | the weapon can fire or swing |
| step_left, step_right | footstep sounds |

The glTF format has no events, so the controller adds them: a method track per clip built from `clips.json` when the
library loads, or a frame check in the state code. The frames above are the contract.

## Upper/lower split

The legs run while the arms aim: an AnimationTree blends an upper-body layer over the locomotion with a bone filter.

- **Upper bones (32):** `Abdomen` and everything under it: `Torso`, `Neck`, `Head`, both `Shoulder`, `UpperArm`,
  `LowerArm` and every finger bone. The list is `upper_bones` in `clips.json`.
- **Lower bones (11):** `Root`, `Body`, `Hips`, `UpperLeg`, `LowerLeg`, `Foot` and `PoleTarget` of each side.

`Abdomen` is in the upper set so recoil and the swing bend the whole spine; the hips stay with the legs.

```text
locomotion (Idle / Walk / Run by speed) ──┐
                                          Blend2 "split", amount 1, filter = upper bones ── full-body OneShot ── output
upper (Aim_<Class> or Sprint_<Class>; OneShots Fire, Reload, Swing, Equip, Unequip) ──┘   (HitReact; Death then Downed)
```

- Standing still, the locomotion is `Idle`; the upper layer is the class's `Aim_<Class>` loop with its one-shots on
  top, so the Soldier never holds a weapon in the Idle arms. Sprinting on the ground it is the class's
  `Sprint_<Class>` carry instead ([Sprint carry](#sprint-carry)).
- `HitReact`, `Death` and `Downed` are full-body and override both layers (a OneShot or a state with no filter).
- Checked headless in Godot: with `Run` under `Aim_Rifle` through a filtered Blend2, the legs follow `Run` and the
  right arm matches `Aim_Rifle` to 0.00 degrees (`game/tests/art/check_soldier_clips.gd`).
- Aim pitch (looking up and down) is not in the clips: the controller turns `Abdomen` or `Torso` about its pitch axis
  (bone X, positive bends forward) after the tree, within about 40 degrees, or we author `Aim_<Class>_Up/_Down` later.

## Weapons in the hand

How they are sized, shouldered and aimed (the size rule, the per-weapon numbers, the arm IK) is in
[Weapons in the hands](weapon-hold.md); this section is the kit hold they ride on.

- **Attach** each weapon to the `Index1.R` bone (a `BoneAttachment3D`), the bone the kit Soldier carries his weapons
  on. A weapon's origin is its grip; its transform on the bone is the kit **Shotgun** hold for guns and the kit
  **Shovel** hold for melee (weapons follow `game/assets/weapons/`, the kit's [weapons page](https://github.com/Ryubara/gdstudio/blob/main/docs/blender/weapons.md)
  and its `render_hold.py`, which prints the hold in the bone's space). Measured in Godot on the built Soldier (the
  kit weapons left in the hand with `build_soldier.py --keep-held Shotgun,Shovel`, divided by the kit files' own
  node transforms), the weapon scene's transform under a `BoneAttachment3D` on `Index1.R` is:

```gdscript
const HOLD_GUN := Transform3D(
    Basis(Vector3(-0.062527, -0.997926, -0.015303), Vector3(0.118606, -0.022655, 0.992683),
          Vector3(-0.990971, 0.060254, 0.119776)),
    Vector3(-0.039563, 0.197228, -0.070351))
const HOLD_MELEE := Transform3D(
    Basis(Vector3(-0.438017, -0.897818, 0.045446), Vector3(-0.898861, 0.436628, -0.037496),
          Vector3(0.013822, -0.057274, -0.998263)),
    Vector3(-0.004282, 0.175673, -0.062554))
```

With these, the lever rifle, double shotgun and bat sit in the Soldier's hand in Godot through every clip (the
Godot capture in the pull request).

- **Each model's own grip replaces these holds** wherever it has one (every model now does): see [Grips](#grips).
  `HOLD_GUN` and `HOLD_MELEE` stay as the fallback for a model with no grip file, and as the turn about the handle a
  melee weapon keeps.
- **Left hand:** the clips are one-handed (in `Idle_Shoot` the left arm hangs). `WeaponHandsIK`
  ([Weapons in the hands](weapon-hold.md)) reaches both hands to the weapon with a two-bone IK: the left hand bone to
  the grip's `left_hand`, turned as the grip says (solved from the model's `Support` socket), with the weight below;
  the clips move the arms themselves where the weight is 0. The melee weapons stay one-handed for now.

| Class | LeftHand IK weight |
| --- | --- |
| Rifle, Shotgun | 1 in Aim and Fire, standing and running; 0 in Reload, Equip and Unequip (the clip moves the left hand) |
| Pistol | 0 (one-handed, as the kit holds it) |
| Melee | 0 (one-handed; the IK does not run for a weapon that is not shouldered) |

## Grips

How the hands close on what they hold (#460): every finger touches the weapon and none goes into it, the trigger
finger is on the trigger, and the left hand holds the fore-end. A grip is data, one file per model,
`game/gameplay/player/grips/<model>.tres` (`HandGrip`), **solved from the model's own hand sockets**, so a new weapon
gets its grip by placing three empties and running the solver, never by tuning numbers.

**The sockets** (Blender empties under the weapon, built by `build_weapons.py` from its `GRIPS`, `TRIGGERS` and
`SUPPORTS` tables, like the `Muzzle`):

| Socket | Where | Turn (Blender; Godot) |
| --- | --- | --- |
| `Grip` | the right hand's handle: its centre where the middle finger wraps | +Z (Godot +Y) up the handle toward the index finger; +Y (Godot -Z) the way the straight fingers point: along the barrel on a pistol grip |
| `Trigger` | guns: the middle of the trigger's front face, where the finger's pad presses | +Y the press (backward) |
| `Support` | two-handed guns: the left hand's handle (fore-end, vertical foregrip) | +Z toward the left index finger (the muzzle, on a fore-end); +Y the way its fingers point (to the gun's right on a fore-end held from below, forward on a vertical grip) |

**The solver** (`game/tests/art/solve_grips.gd`, with `GripSolver` and `HandContact`) works in the hand bone's space
(`Index1`), so its result holds in every pose:

1. The hand's handle line: across the knuckles (pinky to index) at the middle finger; the straight fingers' direction
   and the palm's normal square to it.
2. The model is turned so its socket's up runs along the line and its front the fingers' way (a melee weapon keeps its
   old hold's turn about the handle, so its blade or claw still leads the swing), and moved so the socket is on the
   line; a gun slides along it until its `Trigger` is level with the index finger's knuckle.
3. It is pushed along the palm's normal until the palm is 1 mm from it.
4. A gun is then turned up to 30 degrees about the handle and slid up to 2 cm along the fingers, to the place where the
   index finger reaches the trigger best: the kit's fingers are short and thick, so on a gun drawn at real proportions
   the trigger is out of reach with the grip square in the palm (a chibi hand turns the gun, as a small hand does).
5. Each finger bends at its knuckle and middle joint (the thumb at its root and tip; the trigger finger also
   sideways at its knuckle) within joint limits, to the bend that brings its tip 1 mm from the surface with no part of
   it more than 1.2 mm in. The trigger finger looks for the trigger's face first and lies along the frame when it
   cannot reach it; a finger that can touch nothing is only kept out.

It writes the model's place under the right hand (`hold`, before the hold's `model_scale`), the size it was solved
at, every finger rotation of both hands, the left hand bone's pose in the model's space, and which parts touch.

**In the game** `PlayerAnimation` puts the model under the hand by its grip and gives the same hold to the arms' IK,
and `HandGripPose` (a `SkeletonModifier3D` after `WeaponHandsIK`) closes the fingers: the right hand on the held
item's grip (the weapon, the repair hammer or the grenade shell) while it shows, eased at 20 per second; the left hand
on the weapon's while the IK holds it there. It also keeps the palm whole: the kit hand is four bones from the wrist
(`Index1`, `Middle1`, `Pinky1`, `Thumb1`) and the weapon rides `Index1`, so when the IK turned only that one the other
three stayed with the forearm and the palm tore (every gun's hand in the aim pose before #460).
The left hand goes to the grip's `left_hand` on the weapon where it is after the right arm, and a two-handed gun's
hold turns the chest 20-30 degrees, left shoulder forward ([How a gun is held](weapon-hold.md#how-a-gun-is-held)):
the Soldier's 0.66 m arm did not reach a fore-end 0.70-0.81 m from his shoulder, and the clamped hand ended inside the
stock.

**Proof.** `game/tests/player/test_hand_grips.gd` measures the skin as drawn (`HandContact`: the skinned mesh against
the weapon's triangles, inside counted per closed piece) in every pose the player uses (equipped, standing, running,
aiming, firing and two moments of the reload for the guns; standing, running and four moments of the swing for melee;
the repair and the cooked grenade): no part more than 2 mm into the weapon, every contact within 5 mm.
`tools/blender/render_grips.py` draws the close contact sheets from the probe's dumps
(`game/tests/art/probe_hands.gd`).

## Grenade

The grenade clips (#102, for the grenades of #99) are `upper` clips like the weapon clips: the legs keep running
under them through the same bone filter. They are named `Grenade_<Action>` (the grenade is thrown, never aimed, so it
has no `Aim_` loop) and built by `grenade()` in `tools/blender/soldier_clips.py` into their own file,
`game/assets/characters/soldier/grenade/soldier_grenade.glb` with its `clips.json`: same rig, same track paths, so the
controller adds them to the Soldier's library (`AnimationLibrary.add_animation` on the default library; checked on
the Soldier with the weapon clips, every track finds its bone).

| Clip | Layer | Plays | Frames | Events |
| --- | --- | --- | --- | --- |
| Grenade_Cook | upper | once, hold the last frame | 20 (0.83 s) | grenade_visible 0, pin_out 14, spoon_off 18, cooked 20 |
| Grenade_Throw | upper | once | 22 (0.92 s) | **release 9**, done 22 |
| Grenade_Toss | upper | once | 22 (0.92 s) | **release 10**, done 22 |

| Event | Gameplay does |
| --- | --- |
| grenade_visible | hide the weapon, show the grenade in the hand (Cook starts from the lowered arms, where `Unequip_<Class>` ends) |
| pin_out | hide the grenade's `Pin` node (the ring leaves with the left hand); the pin sound |
| spoon_off | hide the `Spoon` node (or throw a spoon prop off along the body's +X); the fuse may start here |
| cooked | the hold: play the throw from here; while the button is held, stay on this frame |
| release | spawn the projectile at the hand bone's global position, hide the grenade in the hand |
| done | the arms are down; `Equip_<Class>` of the weapon can start |

- **In the night (#351):** `PlayerAnimation` adds the three clips to the Soldier's library like the repair clip and
  plays them on the upper-body action layer (`play_clip`): `Grenade_Cook` on the server's `cook_started`,
  `Grenade_Throw` or `Grenade_Toss` on `throw_started`. `grenade_visible` puts the gun away and shows the grenade
  in the hand, `release` takes it out of the hand and `done` brings the gun back (the `gone` stage when the grenade
  went off in the hand). The server lets go of the grenade at the clip's release frame (`NightTuning.grenade_release_*`,
  0.375 s and 0.4167 s), and the cook clip holds its last frame while the button is down (a custom timeline on the
  action node): see [Grenades](../research/grenades.md#polish-357).
- **Hand bone:** `Index1.R`, the bone every weapon is held on. At `release` the projectile starts at that bone's
  global position (at kit scale the hand is about 0.35 m above the head bone's origin for the throw, 0.55 m below it for
  the toss); its velocity comes from the aim and the throw strength, not from the hand: the hand sweeps across the
  body (it moves about 5 m/s to the left, 3.4 m/s forward at the throw's release).
- **Hold:** the grenade's origin is the centre of its body (its grip), standing up along +Y in Godot with the spoon on
  +X and the ring on +Z. Under a `BoneAttachment3D` on `Index1.R` it is the gun hold turned 90 degrees about its X:

```gdscript
const HOLD_GRENADE := Transform3D(  # HOLD_GUN * Basis(Vector3.RIGHT, PI / 2)
    Basis(Vector3(-0.062527, -0.997926, -0.015303), Vector3(-0.990971, 0.060254, 0.119776),
          Vector3(-0.118606, 0.022655, -0.992683)),
    Vector3(-0.039563, 0.197228, -0.070351))
```

- **Left hand:** no IK in the grenade clips (weight 0): the left hand reaches for the ring in Cook and points ahead
  in the throw by itself.
- Checked headless (`game/tests/art/check_grenade.gd`): each clip plays, the hand moves, no leg bone turns, the hand
  moves forward at `release`, and with a stride under the throw through the filter the arm matches the clip to 0.00
  degrees. `game/tests/art/capture_grenade.gd` renders the clips in Godot with the grenade in the hand.

## Repair

`Repair_Board` (#221) is the Soldier putting a board back across a breach of the fence: an `upper` clip like the
weapon clips, so the legs keep their locomotion under it through the same bone filter. It is built by `repair()` in
`tools/blender/soldier_clips.py` into its own file, `game/assets/characters/soldier/repair/soldier_repair.glb` with its
`clips.json`, and `PlayerAnimation` adds it to the Soldier's library when the tree is built.

| Clip | Layer | Plays | Frames | Events |
| --- | --- | --- | --- | --- |
| Repair_Board | upper | loop, one loop a board | 24 (1.0 s) | hammer 3, 18; **board_set 18** |

- **Pose:** the left hand holds the board flat against the gap at chest height, 0.95 m in front at kit scale (no IK);
  the right fist taps it from chin height (frame 3), rises above the helmet (15) and drives it home (18). The weapon is
  hidden while the clip holds the arms and shown again when it lets go.
- **The hammer:** while the clip holds the arms, the claw hammer
  (`game/assets/weapons/hammer/hammer.glb`, [Weapons](../research/weapons.md#the-hammer)) is in the right fist in
  the weapon's place, on the same `WeaponMount` (`Index1.R`), sized by its hold file (`holds/hammer.tres`, 0.50 m:
  [the exception to the size rule](weapon-hold.md#the-size-rule)). Its grip, `HOLD_HAMMER`, is the melee one tipped 20
  degrees in the hammer's swing plane, chosen from the clip's own motion: over a loop the face drops from the raise
  over the helmet onto the board and meets it square, face first (tested: a drop of more than 0.5 m, the face within
  45 degrees of both the blow and the player's forward, the head at least 0.15 m out ahead of the fist; the face is
  the model's `Face` node). An `Equip`
  clip's `weapon_visible` frame does not bring the weapon back over it. While the clip holds the arms the hands' IK is
  switched off, not only blended to 0: at influence 0 it still drew the arms in the gun pose, hiding the swing.
- **Timing comes from the rules, not the clock.** The night repairs one board every `repair_interval` (night tuning,
  1.0 s) while `use` is held ([hold to repair](rounds.md#the-fences-boards), #297), and each repair is a
  `board_repaired` event naming the player. On each one, `PlayerAnimation.board_repaired(interval)` seeks the clip
  to `board_set` less the board's mend (`Barricade.MEND_SECONDS`, 0.28 s: the board slides in and knocks home that
  long after the event) and plays it at `1 s / interval`, so the fist comes down as the board knocks home (#245).
  The first board of a hold gets a lead-in this way (the fist rises from the tap and lands), where it was down
  already; the loop comes round to the same place just as the next board goes up (the seek is then a no-op, not a
  jump). With no event for 1.5 intervals the layer fades out (18 per second).
- `board_set` comes once per board: each `board_repaired` makes one due, and the loop emits it when it reaches the
  frame, with the blow's `hammer`. `hammer` (both blows) is for the board sounds (#88).
- **Facing the boards.** A repair is allowed by place (field side, within reach), not by facing, so for an interval
  after each board the server turns the body toward the breach at its turn speed (`NightServer._face_breach`);
  walking or aiming turns it the player's way as before.
- **Every player's repair.** The clip is started by the view from the event stream (`NightView.show_repair`), for
  whichever player the event names: the view finds the drawn body through `NightView.bodies`, which a single-process
  night fills with the server's bodies and a client on another machine with its drawn avatars.
- Checked headless (`game/tests/art/check_repair.gd`): every track finds its bone on `soldier.glb`, the loop is
  seamless, the fist is lowest at frame 19 (one past `board_set`) and 0.82 m below the raise, no leg bone turns,
  and over `Walk` through the filter the arm matches the clip to 0.04 degrees. `game/tests/player/test_player_repair.gd`
  steps the controller by hand: the lead and the blow on the knock, pace, a faster interval, letting go, the hammer shown
  and put away, the face leading the blow; `game/tests/night/test_night_repair_show.gd` checks the facing and that the
  clip reaches the named player's body; `game/tests/night/test_night_repair_hammer.gd` holds `interact` at a breach
  through the night and checks the hammer replaces the weapon and the weapon comes back on release, and
  `game/tests/ui/touch/test_touch_repair.gd` does the same from a finger on the touch Interact button.

## Downed and revive

A downed player lies in `Downed_Idle`, and a teammate holding the revive kneels in `Revive_Kneel` (#504, for the
revives of #486). `Downed_Crawl` is ready in case downed players may move ([#505](https://github.com/Ryubara/deadnight/issues/505)
decides). All three are `full` clips: they own the legs too. They are built by `revive()` in
`tools/blender/soldier_clips.py` into their own files: `Downed_Idle` and `Revive_Kneel` in
`game/assets/characters/soldier/revive/soldier_revive.glb`, `Downed_Crawl` alone in
`game/assets/characters/soldier/crawl/soldier_crawl.glb`, each with its `clips.json`. Delete the `crawl` folder and the
crawl is gone: the controller adds it only when its file is there.

| Clip | Layer | Plays | Frames | Ground speed | Events |
| --- | --- | --- | --- | --- | --- |
| Downed_Idle | full | loop | 48 (2.0 s) | - | - |
| Downed_Crawl | full | loop, at ground speed | 32 (1.33 s) | 0.45 m/s | pull_right 0, pull_left 16 |
| Revive_Kneel | full | loop while the hold lasts | 24 (1.0 s) | - | press 6, 18 |

- **Downed_Idle** reclines on the left elbow, the chest 30 degrees off the ground. The right hand holds the belly, the
  right knee is drawn up, and the head looks left on one breath and right on the next. It sits with the hips over the
  player's place, and the whole body is turned 20 degrees about the vertical (head to his left, feet to his right).
  That turn is what makes it read from the shoulder camera behind him: lying straight, the camera looks along the body
  and sees the helmet. Unlike the old `Downed` (Death's last frame: flat on the back, the head 1.3 m behind the
  player's place, a helmet and two boots from behind), it reads from the side and from above too. Nothing goes below
  the ground (the lowest skin is the shin, at -2 mm).
- **Downed_Crawl** is the same recline. The heels dig in ahead and pull him forward, one then the other: a planted heel
  sweeps back at 0.45 m/s in the game (measured off the clip, `ground_speed` in its `clips.json`), and the left elbow
  pushes with the left heel. The controller plays it at ground speed over 0.45 (0.5 to 1.6), fully in by 40 % of it.
- **Revive_Kneel** is down on the right knee, the toes curled under, the left foot flat ahead. The back is upright and
  the arms reach out and down: the hands press 0.53 m ahead of him and 0.29 m up, and 6 cm lower on each `press`.
  Upright on purpose: leaned over his hands, the Soldier's big head met the teammate's. He presses the belly (where the
  downed hand holds the wound), not the chest, for the same reason.
- **No finger is keyed.** The hands keep the skeleton's rest fist, and `HandGripPose` (#507) is free to close them on
  whatever they hold. Blender's glTF exporter samples every bone of every clip whatever its keys, so
  `build_soldier.py` takes the finger channels out of the file after the export (`strip_channels`, 66 per clip:
  22 bones, 3 channels each). `test_player_revive.gd` checks the imported clips carry no finger track.
- **Driven by eased weights.** `PlayerAnimation.set_downed(bool)` (the rules' `player_downed` / `player_revived`)
  and `set_reviving(bool)` (`revive_started` naming the player as the reviver / `revive_interrupted`,
  `player_revived`). Each eases a Blend2 over everything the standing body does, at 6 per second for the downed pose
  and 10 for the kneel. Going down drops a repair, a reload and a revive. Down or kneeling, the weapon is put away and
  the arm IK lets go. A downed player cannot kneel. The tree: `full` (HitReact, Death) over `downed` (Downed_Idle,
  or the `crawl` blend) over `kneel` (Revive_Kneel) over `split`.
- **Other players' bodies.** `DownedPose.add_clips(anim_player)` adds the clips to any model on the
  Soldier's rig, so a drawn avatar (RemoteAvatars) can play `Downed_Idle` in place of its `DOWNED_TILT`.
- **The camera does not frame a downed body yet.** The shoulder rig keeps its standing height and pitch, so the body
  lies at the bottom edge of the view, cut off. Framing it is the camera's job (lower the pivot and tilt down while
  down, as the crouch flag does): [#532](https://github.com/Ryubara/deadnight/issues/532).
- Checked headless (`game/tests/player/test_player_revive.gd`): the clips are in the library, loop, find every bone on
  the player's skeleton, key the legs and no finger. The tree has a node for each. Going down eases (one tick in, the
  weight is under 0.2), the head ends under 60 % of its standing height, and getting up brings it and the weapon back.
  The downed head turns more than 15 degrees over a loop. The kneel presses 4 times in 2 s. A downed player does not
  kneel. Moving at 0.45 m/s while down plays the crawl at rate 1.0 and the heels move. Captures:
  `game/tests/captures/revive_poses.tscn`, in the night, from the shoulder camera, the side and above.

## Reloading

A reload is a tilt, not a clip (maintainer, 2026-11-01, #383: "it can just be a slight tilt weapon downward and pull it
back up after it's done"). The `Reload_<Class>` clips above are not played in the night: the arms stay on the weapon
(`WeaponHandsIK`) and the server's `reload_started` (`seconds` is the weapon's `reload_time`) calls
`PlayerAnimation.reload(seconds)` on the shooter's Soldier, on every client, through `NightView`. Over those seconds the
weapon's pitch is lowered about the grip by `PlayerTuning.reload_tilt_degrees` (35): down over the first
`reload_dip_in` (0.2) of the time, held, and back up over the last `reload_dip_out` (0.25), each a smoothstep, so the
weapon is level again when the reload is done. A swap (`equip`) cancels it. The tilt is added to the pitch of the pose
the aim weight gives ([hip fire](../research/hip-fire.md)), so a reload while aiming dips from the aim and returns to
it, and it never touches the weight: `test_reload_tilt.gd` samples the barrel's pitch every tick for every gun (hip and
aim) and checks the dip, the return within the reload time, a bounded turn per tick and an unchanged aim weight;
`test_night_reload.gd` does it through the real night with the sounds counted ([audio](audio.md)).

## Moving while aiming

While aiming the Soldier keeps facing the camera and moves at `aim_speed` (2.6 m/s) in any direction, so the legs
need a clip per direction (#74). Four `full` clips, one gait turned four ways, built by `aim_moves()` in
`tools/blender/soldier_clips.py` into their own file, `game/assets/characters/soldier/aim_move/soldier_aim_move.glb`
with its `clips.json`; `PlayerAnimation` adds them to the Soldier's library when the tree is built.

| Clip | Direction | Plays | Frames | Ground speed | Events |
| --- | --- | --- | --- | --- | --- |
| Walk_Shoot | ahead | loop | 17 (0.71 s) | 2.6 m/s | step_right 1, step_left 11 |
| Walk_Back | back | loop | 17 (0.71 s) | 2.6 m/s | step_right 1, step_left 11 |
| Strafe_Left | his left | loop | 17 (0.71 s) | 2.6 m/s | step_right 1, step_left 11 |
| Strafe_Right | his right | loop | 17 (0.71 s) | 2.6 m/s | step_right 1, step_left 11 |

- **One gait, four ways.** Each foot follows the kit `Run`'s path turned toward the direction of travel: in contact
  it sweeps the ground at the aim speed over 0.85 of the Run's contact, and the Run's swing fills the rest of the
  cycle, 0.55 as high going ahead and an even 16 cm arc (kit scale) going sideways or back (the Run's high back-kick
  would lift the foot in front of a backpedal). On a strafe the feet's lanes move 16 cm ahead and behind so they
  pass instead of colliding, and the knees and toes turn a third of the way toward the step. The hips drop 5 cm and
  bob at 0.45 of the Run's; `Body` does not turn, so the aim stays level. The legs are solved to meet the feet
  (`tools/blender/gaitlib.py`). Above the hips each clip holds the gun hold (`Idle_Shoot` frame 0); in the game the
  bone filter puts `Aim_<Class>` there.
- **Blended by the direction of travel.** The body's `locomotion` has the Idle/Walk/Run blend and, over it by an
  aim weight that follows `aiming` (`blend_rate`), a `BlendSpace2D` with Idle in the middle and the four clips at
  ahead, back, left and right (`PlayerAnimation.aim_move_for`: the velocity in the facing's frame). The clips share
  their length and their step frames, so a diagonal is two of them in step. The gait is fully in by 40 % of the
  clips' speed and plays at ground speed over 2.6 (0.5 to 1.6) behind its own time scale.
- Checked headless (`game/tests/player/test_player_aim_move.gd`): the planted foot, read off the skeleton while the
  player moves at the aim speed, sweeps straight against the travel at 2.60 m/s in all four directions.

## Sprint carry

While the body sprints, the legs play `Run` and the arms carry the weapon with the stride (#459): before, the upper
layer kept looping `Aim_<Class>`, so the arms and the gun stayed frozen through a sprint. Weapons need no clips of
their own: each rides `Index1.R`, so it swings when the arms and the chest do. Four `upper` clips, built by
`sprint_carries()` in `tools/blender/soldier_clips.py` into their own file,
`game/assets/characters/soldier/sprint/soldier_sprint.glb` with its `clips.json`; `PlayerAnimation` adds them to the
Soldier's library when the tree is built.

| Clip | Layer | Plays | Frames | The carry |
| --- | --- | --- | --- | --- |
| Sprint_Rifle | upper | loop | 17 (0.71 s) | both hands on, low across the chest, muzzle up past his left shoulder |
| Sprint_Shotgun | upper | loop | 17 (0.71 s) | the same, a little lower and with more swing (the heavier gun) |
| Sprint_Pistol | upper | loop | 17 (0.71 s) | one hand at the side, the forearm pumping (the kit's `Run_Gun` arm) |
| Sprint_Melee | upper | loop | 17 (0.71 s) | a runner's arm out from the side, the weapon upright and leaning back |

- **On Run's own frames.** Each clip is the kit `Run`, frame for frame: its spine, shoulders and left arm (the chest
  twists 9 degrees each way and bobs with the stride), so the swing lands on Run's footfalls by construction (the
  right foot plants at frame 3.5, the left at 12.5; the Body is lowest at 4 and 13). Only the right arm and, for the
  two-handed guns, the left arm are posed for the class.
- **Rifle and Shotgun.** The upper arm hangs (chest frame, his right is -X, ahead -Y: `(-0.35, -0.05, -1)`), the
  muzzle points `(0.85, -0.5, 0.45)` (across to his left, ahead and up) and the gun's top faces `(-0.3, 0.2, 1)`;
  the grip follows from the kit hold (0.62 m out along the forearm, so a low grip and a steep gun cannot both be had).
  On top of the chest's twist the gun swings 6 degrees each way (7 for the shotgun) and the muzzle dips 4 degrees (5)
  a frame after each footfall. The left hand reaches the hold's `support` point (`holds/<class>.tres`, times its
  `model_scale`) by two-bone IK in Blender, 0.07 m short along the forearm like `WeaponHandsIK`: if the support point
  moves, rebuild the clips. The muzzle shows past the left of the helmet from the shoulder camera; a carry in front of
  the chest (tried first) is hidden by the body.
- **Pistol.** `Run_Gun`'s right arm (the forearm pumps 46 degrees a stride), the upper arm swinging a third of the left
  arm's swing half a stride later.
- **Melee.** The upper arm hangs out from the side (`(-0.5, 0.1, -1)`) and swings 24 degrees fore and aft against the
  left arm; the forearm points ahead and pumps 1.2 times the arm's swing; the forearm is turned about its axis so the
  shaft leans up, back and out (`(-0.25, 0.45, 1)`): it stays up and clears the head from the camera. Hanging, the
  weapon pointed at the legs (first try).
- **Only the spine, the shoulders and the arms move.** The fingers stay the static grip every weapon clip shares and
  the hand's hold on the weapon is the game's (`HOLD_GUN`, `HOLD_MELEE`): the grip sockets and finger poses are #460's.
  A test fails if a Sprint clip moves a finger or a leg bone.

### The blend

- **When.** The carry comes in while the body is `sprinting`, **on the floor**, at `sprint_carry_min_speed` (3 m/s)
  or more, with nothing else for the arms (no aim and no hip-fire hold, no action clip, no repair). It eases in over
  `sprint_carry_in` (0.2 s) and out over `sprint_carry_out` (0.15 s), linearly, through a smoothstep in the tree
  (`PlayerTuning`, group Sprint carry).
- **Out at once for the arms' work.** The aim, a shot (the hip-fire hold), a reload, a swing, an equip or a grenade
  start the blend-out on their first tick; the one-shot's own fade (0.05 s) covers the carry first. The shot itself is
  not delayed: `muzzle` is frame 0 of Fire and comes in the call that starts it, carry or not. The shouldered pose
  (`WeaponHandsIK`) gives way to the carry by its weight (`influence = shoulder x (1 - carry)`).
- **In the air it holds still.** Following the sprint sway's rule (the feet make the motion,
  [Camera shake](camera-shake.md#the-sprint-sway)): in the air the clip stops where it is (the Run is not played
  there either) and keeps its weight; it never starts in the air. After the landing the locomotion restarts the Run,
  and the carry catches up with it (12 per second, exponential) instead of jumping.
- **Locked to the Run.** The tree has a `carry` Blend2 between `aim` and the action OneShot, its clip behind a
  `TimeSeek`. Every frame `PlayerAnimation` reads the Run's place
  (`parameters/body/locomotion/move/run/current_position`, after the tree's last step) plus that step
  (`current_delta`) and seeks the carry there: both clips land on the same frame, at whatever pace the Run plays.
- **Where.** The weight and the clip's place are `SprintCarry` (`game/gameplay/player/sprint_carry.gd`, no tree in
  it); the Sprint file is added to the Soldier's library by `SoldierClipFile`, which loads the repair, grenade,
  aim-move and sprint files alike.
- **With the hand grips (#507).** The carry keys no finger, so `HandGripPose` closes the fingers over it. The rifle's
  and shotgun's carry reach the old hold's `support` point and the weapon sits at the old hold; #507 moves both
  (`HandGrip.hold` and `left_hand`), so after it merges the Sprint clips for the long guns are rebuilt against the
  new points (`soldier_clips.py`, `SPRINT_CARRY`): until then the gun hides behind the arm and head in a sprint.
- **Checked:** `game/tests/player/test_sprint_carry.gd` (the clips are on Run's cycle; the carry plays only sprinting
  on the ground, holds in the air and never starts there; its phase matches Run to 0.002 s; it catches up after a
  landing without jumping; aim, a hip shot, a reload and a swing take it out within 0.15 s; the first shot's `muzzle`
  comes in the same call; the hand swings more than 5 cm a stride in every class; no finger or leg moves) and
  `game/tests/night/test_night_sprint_carry.gd` (sprint commands through the real night carry the weapon, and the
  first shot after the sprint comes on the same tick as one from a standstill). Captures:
  `game/tests/captures/sprint_carry_tour.tscn`.

## How the clips are made

From the kit's own poses, never from a blank rig: `Idle_Shoot` frame 0 (the gun hold) is the base of every weapon
pose, `Idle` frame 0 the lowered arms that Equip and Unequip move from and to. Recoil, sway and reloads are local
rotations on top, mostly of the spine, so both arms and the weapon move together. `Walk` is the kit `Run` at 60 % of
its stride, stretched to one second; `Downed` is the last frame of `Death`, breathing. The downed and revive
clips are built in world space instead (bones turned about world axes, arms and legs solved onto world targets):
lying and kneeling move the bones too far from the standing axes the offsets were measured in. What we learned on the way:
[Character animation](../research/character-animation.md).

## Rebuilding

```sh
blender -b --factory-startup -P tools/blender/build_soldier.py -- \
    --soldier <bundle>/models/PpLF4rt4ah.glb --out game/assets/characters/soldier/soldier.glb
blender -b --factory-startup -P tools/blender/render_clips.py -- \
    --soldier <bundle>/models/PpLF4rt4ah.glb --out <scratch>/clips        # contact sheets, one per class
godot --headless --path game --import
godot --headless --path game -s res://tests/art/check_soldier_clips.gd   # CLIPS/POSE/SPLIT lines, exit 0
# The grenade clips, their own file; the grenade model; their contact sheets and checks:
blender -b --factory-startup -P tools/blender/build_soldier.py -- --soldier <bundle>/models/PpLF4rt4ah.glb     --clips Grenade_ --out game/assets/characters/soldier/grenade/soldier_grenade.glb
blender -b --factory-startup -P tools/blender/build_weapons.py -- --only grenade
blender -b --factory-startup -P tools/blender/render_clips.py -- --soldier <bundle>/models/PpLF4rt4ah.glb     --only Grenade,GrenadeSplit --weapon Grenade=game/assets/weapons/grenade/grenade.glb=Shotgun --out <scratch>/clips
godot --headless --path game -s res://tests/art/check_grenade.gd          # MODEL/CLIP/RELEASE/SPLIT lines, exit 0
godot --path game -s res://tests/art/capture_grenade.gd -- --out <scratch>/godot-grenade.png
# The repair clip, its own file; its contact sheets (front, and from behind as the game's camera sees it); its check:
blender -b --factory-startup -P tools/blender/build_soldier.py -- --soldier <bundle>/models/PpLF4rt4ah.glb     --clips Repair_ --out game/assets/characters/soldier/repair/soldier_repair.glb
blender -b --factory-startup -P tools/blender/render_clips.py -- --soldier <bundle>/models/PpLF4rt4ah.glb     --only Repair,RepairSplit --view back --out <scratch>/repair
godot --headless --path game -s res://tests/art/check_repair.gd           # LIBRARY/CLIP/LOOP/BLOW/SPLIT lines, exit 0
# The aim-move clips, their own file (prints AIM_MOVES: ground speed and how far a foot was pulled into reach); their
# sheet, the kit Run above them (front, side, or from above and behind to see the feet on a strafe):
blender -b --factory-startup -P tools/blender/build_soldier.py -- --soldier <bundle>/models/PpLF4rt4ah.glb     --clips Walk_,Strafe_ --out game/assets/characters/soldier/aim_move/soldier_aim_move.glb
blender -b --factory-startup -P tools/blender/render_clips.py -- --soldier <bundle>/models/PpLF4rt4ah.glb     --only AimMove --view top --out <scratch>/aim
# The downed and revive clips, and the optional crawl in a file of its own (prints the finger channels taken out);
# their sheet, the old Downed above them (front, side, back or top); the check; the captures in the night:
blender -b --factory-startup -P tools/blender/build_soldier.py -- --soldier <bundle>/models/PpLF4rt4ah.glb     --clips Downed_Idle,Revive_ --out game/assets/characters/soldier/revive/soldier_revive.glb
blender -b --factory-startup -P tools/blender/build_soldier.py -- --soldier <bundle>/models/PpLF4rt4ah.glb     --clips Downed_Crawl --out game/assets/characters/soldier/crawl/soldier_crawl.glb
blender -b --factory-startup -P tools/blender/render_clips.py -- --soldier <bundle>/models/PpLF4rt4ah.glb     --only Revive --view side --out <scratch>/revive
godot --headless --path game -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/player/test_player_revive.gd
gds godot -- --path game res://tests/captures/revive_poses.tscn --quit-after 3600 -- --out <scratch>/revive
# The sprint carry clips, their own file (prints SPRINT: each clip's frames and how far the left hand missed the
# fore-end); one stride of each over Run with the game's weapons (Sprint; SprintBefore is Aim_<Class> over Run):
blender -b --factory-startup -P tools/blender/build_soldier.py -- --soldier <bundle>/models/PpLF4rt4ah.glb     --clips Sprint_ --out game/assets/characters/soldier/sprint/soldier_sprint.glb
blender -b --factory-startup -P tools/blender/render_clips.py -- --soldier <bundle>/models/PpLF4rt4ah.glb     --only Sprint,SprintBefore --view back --out <scratch>/sprint     --weapon Rifle=game/assets/weapons/lever_rifle/lever_rifle.glb=Shotgun=0.71     --weapon Shotgun=game/assets/weapons/double_shotgun/double_shotgun.glb=Shotgun=0.82     --weapon Pistol=game/assets/weapons/revolver/revolver.glb=Pistol=1.76     --weapon Melee=game/assets/weapons/baseball_bat/baseball_bat.glb=Shovel=0.86=-90,0,0
```

`<bundle>` is the Toon Shooter kit's folder in `refs/`. The `.glb` is third-party-derived (CC0); it is committed with
its licence entry (`game/assets/characters/soldier/LICENSE.md`, approved by the maintainer in issue #90).

The player controller (`game/gameplay/player/player_animation.gd`) plays the clips by these bare names and attaches
the lever rifle to `Index1.R` with `HOLD_GUN`; the file itself carries no weapon.
