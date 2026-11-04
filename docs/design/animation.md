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
  `Swing_Melee`, `Equip_Melee`. Classes: **Rifle, Shotgun, Pistol, Melee**, and **Dual** (a pistol in each hand, [below](#dual-pistols)).
- **Bare names** for whole-body clips: `Idle`, `Walk`, `Run`, `Downed`; a whole-body clip with a variant is
  `<State>_<Variant>`: `Downed_Idle`, `Downed_Crawl`, `Revive_Kneel` ([Downed and revive](#downed-and-revive)).
- **Kit names stay** for kit clips we use as they are: `HitReact` is the hit, `Death` is going down. Renaming them
  would break the other kit characters that share the library.

Which weapon is which class: lever rifle is Rifle, double shotgun is Shotgun, baseball bat and fire axe are Melee.
The revolver and the flare gun are Pistol, the dual pistols Dual, the Tommy gun Rifle, the crowbar Melee
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
| Strike_<Class> | upper | once | 13 (0.54 s) | whoosh 3, hit 6, can_strike_again 13 (the [quick melee](#quick-melee), its own file) |
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
| hit, can_strike_again | the quick melee's blow lands; the earliest the next may start (the server's cooldown is the rule) |
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
`--fingers` keeps a model's written `hold` and left hand and solves the right hand's fingers only: the sprint carries
are built from the `hold`, so a finger fix that keeps it needs no new Sprint file (#716: the lever rifle's middle
finger).

**In the game** `HeldWeapon` (what `PlayerAnimation` and the menu's stage both call, #621) puts the model under the
hand by its grip and gives the same hold to the arms' IK, and `HandGripPose` (a `SkeletonModifier3D` after
`WeaponHandsIK`) closes the fingers: the right hand on the held item's grip (the weapon, the repair hammer or the
grenade shell) while it shows, eased at 20 per second; the left hand on the weapon's while the IK holds it there. It
also keeps the palm whole: the kit hand is four bones from the wrist (`Index1`, `Middle1`, `Pinky1`, `Thumb1`) and the
weapon rides `Index1`, so when the IK turned only that one the other three stayed with the forearm and the palm tore
(every gun's hand in the aim pose before #460).
The left hand goes to the grip's `left_hand` on the weapon where it is after the right arm, and a two-handed gun's
hold turns the chest 20-30 degrees, left shoulder forward ([How a gun is held](weapon-hold.md#how-a-gun-is-held)):
the Soldier's 0.66 m arm did not reach a fore-end 0.70-0.81 m from his shoulder, and the clamped hand ended inside the
stock.

**Proof.** `game/tests/player/test_hand_grips.gd` measures the skin as drawn (`HandContact`: the skinned mesh against
the weapon's triangles, inside counted per closed piece; the near meshes only, as the solver does: the far level of
detail is hidden by its visibility range, not by `visible`, and measured with it a fingertip 6.9 mm off the rifle
passed on the decimated hand's longer tip, #716) in every pose the player uses (equipped, standing, running,
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
  switched off at weight 0, which it ends on the clip's arms (`WeaponHandsIK.weight`, not the modifier's own
  `influence`: at influence 0 it still drew the arms in the gun pose, hiding the swing).
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

## Drink

`Drink_Perk` (#912) is the Soldier drinking a perk: an `upper` clip like the repair, so the legs keep walking under
it, built by `drink()` in `tools/blender/drink_clip.py` (called from `soldier_clips.build`) into its own file,
`game/assets/characters/soldier/drink/soldier_drink.glb` with its `clips.json`; `PlayerAnimation` adds it to the
library and plays it on a layer of its own over the repair (under a down), at the pace of the rules' drink.

| Clip | Layer | Plays | Frames | Events |
| --- | --- | --- | --- | --- |
| Drink_Perk | upper | once, stretched to the drink's seconds | 60 (2.5 s) | weapon_hidden 6, bottle_visible 6, cap_off 17, drink 24, gulp 30, 37, discard 46, weapon_visible 53, done 60 |

- **The motion:** the gun goes down (the aim pose to the lowered arms, as `Unequip`), the bottle comes up from the
  right hip to the chest, the left hand takes the cap and twists it off (`cap_off`), the bottle goes to the mouth from
  his right, its bottom 45 degrees round to the right and raised 100 to 126 degrees from upright over two gulps, the
  head tipped back a few degrees only (tipped back 20 degrees or more the kit's big head read in the game as pouring
  the bottle over the helmet), then the arm flings the empty bottle out to the right (`discard`) and the gun comes
  back up. Further round (58 degrees) and higher (135) the fist sank 60 mm into the head, and at the hip the fingers
  50 mm into the hip (`test_soldier_clip_fit.gd`, which samples `Drink_Perk` with the player's other clips): now 13 mm
  at most on both looks, every quarter frame, and the build's `ARMS` line is clear.
- **How it is made:** in world space, like the sprint carries. Each key sets the bottle's lip and axis, the lip on
  the mouth while drinking (`MOUTH`, kit metres in `Idle` frame 0, carried by the Head bone so it follows the head);
  the right hand is turned the least way from the gun hold so the bottle, through its solved grip, points along the
  axis, and the arm is solved onto the lip by two-bone IK; the left hand reaches the cap the same way. The build prints
  each key's miss (0 at every key) and the mouth in the Head bone's frame, which the test checks the lip against.
- **The bottle** (`PerkBottle`, `game/assets/weapons/perk_bottle/`, built by `tools/blender/weapon_specs/perk_bottle.py`):
  one model for every perk, coloured by the game (the glass in the drink colour of the perk's machine, the label band
  in the machine's body colour, the cap chrome; the soda fountain's for the health tonic), 0.22 m drawn and 0.39 m in
  the game (`holds/perk_bottle.tres`, 1.75 times the size rule, as the grenade is drawn large), its grip solved
  (`grips/perk_bottle.tres`, every finger within 1 mm). On the hand mount in the weapon's place; its nodes `Label` and
  `Cap`. The cap flicks off at `cap_off`; at `discard` a copy of the bottle is thrown to his right (1.6 m/s out, 2 up),
  bounces once, lies on its side 4 s and goes; a down drops it from the hand.
- **Sounds** (`perks` bank, deferred, #864; synthesised by `tools/audio/drink_recipes.py`): `drink_open` at `cap_off`
  (the cap snapped off, a fizz), `drink_gulp` at `drink` (three swallows and a breath), `drink_discard` at `discard`
  (a swish, the glass landing 0.45 s later, a bounce and a roll). Played at the bottle.
- **Every player's drink:** the view starts it from the rules' `drink_started` for the player it names
  (`NightView.show_drink`), so a teammate, a bot and another client see it; `drink_spilled` drops the bottle.
- **The arms:** while the drink holds them the hands' IK is at weight 0 and the sprint carry stays out; the weapon is
  hidden from `weapon_hidden` to `weapon_visible`, and nothing else shows it in between.
- Checked: `tests/player/test_player_drink.gd` (the clip in the library, its pace, the gun away and back, the bottle in
  each perk's colours, the cap, the lip within 5 cm of the mouth in the Head bone's frame as the game draws it, the
  throw landing beside him, a down dropping it, the fingers on the bottle's grip). Captures:
  `tests/captures/drink_tour.gd` (`--view player`, `teammate` or `side`).

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

- **Downed_Idle** reclines on the left elbow, the chest 30 degrees off the ground. The right knee is drawn up and falls
  out to his right, the right forearm rests over it, and the head looks left on one breath and right on the next. The
  right hand held the belly until #939: sitting up with the knees in, the belly is a fold between the trunk and the
  thighs, and the hand or forearm went into one of them wherever it pressed (49-102 mm over 18 places). It sits with the
  hips over the player's place, and the whole body is turned 20 degrees about the vertical (head to his left, feet to
  his right). That turn is what makes it read from the shoulder camera behind him: lying straight, the camera looks
  along the body and sees the helmet. Unlike the old `Downed` (Death's last frame: flat on the back, the head 1.3 m
  behind the player's place, a helmet and two boots from behind), it reads from the side and from above too. Nothing
  goes below the ground (the lowest skin is the shin, at -2 mm).
- **Downed_Crawl** is the same recline. The heels dig in ahead and pull him forward, one then the other: a planted heel
  sweeps back at 0.45 m/s in the game (measured off the clip, `ground_speed` in its `clips.json`), and each elbow
  pushes with its own heel, 8 cm wider than the downed left hand (a hand kept on the belly was in the way of the left
  knee, 130 mm into the shin). The controller plays it at ground speed over 0.45 (0.5 to 1.6), fully in by 40 % of it.
- **Revive_Kneel** is down on the right knee, the toes curled under, the left foot flat ahead. The back is upright and
  the arms reach out and down: the hands press 0.53 m ahead of him and 0.29 m up, 0.42 m apart (0.14 apart, the big
  hands went through each other, #939), and 6 cm lower on each `press`.
  Upright on purpose: leaned over his hands, the Soldier's big head met the teammate's. He presses the belly (where the
  downed hand holds the wound), not the chest, for the same reason.
- **No finger is keyed.** The hands keep the skeleton's rest fist, and `HandGripPose` (#507) is free to close them on
  whatever they hold. Blender's glTF exporter samples every bone of every clip whatever its keys, so
  `build_soldier.py` takes the finger channels out of the file after the export (`strip_channels`, 66 per clip:
  22 bones, 3 channels each). `test_player_revive.gd` checks the imported clips carry no finger track.
- **Driven by eased weights.** `PlayerAnimation.set_downed(bool)` (the rules' `player_downed` / `player_revived`)
  and `set_reviving(bool)` (`revive_started` naming the player as the reviver / `revive_stopped`,
  `player_revived`). `Night` calls them from the server's events for every body it draws, and `RemoteAvatars` from each
  frame's `downed`, so a player who joins late lies down too. Each eases a Blend2 over everything the standing body
  does, at 6 per second for the downed pose and 10 for the kneel. Going down drops a repair, a reload and a revive.
  Down or kneeling, the weapon is put away and the arm IK lets go. A downed player cannot kneel. The tree: `full`
  (HitReact, Death) over `downed` (Downed_Idle, or the `crawl` blend) over `kneel` (Revive_Kneel) over `split`.
- **Other players' bodies.** `DownedPose.add_clips(anim_player)` adds the clips to any model on the
  Soldier's rig, so a drawn avatar (RemoteAvatars) plays `Downed_Idle`; `DOWNED_TILT` is only for a body with no animation.
- **The camera follows the body down** (#532): the shoulder rig sinks its pivot and tips the view while the player is
  down, so the whole body is in the picture; the clips do not move the camera. See
  [shoulder camera](../research/shoulder-camera.md#the-downed-camera).
- Checked headless (`game/tests/player/test_player_revive.gd`): the clips are in the library, loop, find every bone on
  the player's skeleton, key the legs and no finger. The tree has a node for each. Going down eases (one tick in, the
  weight is under 0.2), the head ends under 60 % of its standing height, and getting up brings it and the weapon back.
  The downed head turns more than 15 degrees over a loop. The kneel presses 4 times in 2 s. A downed player does not
  kneel. Moving at 0.45 m/s while down plays the crawl at rate 1.0 and the heels move. Captures:
  `game/tests/captures/revive_poses.tscn`, in the night, from the shoulder camera, the side and above.
- Checked over a real socket (`game/tests/net/test_night_revive_online.gd`, the pose test): the downed player's own
  played body and the other client's drawn avatar of them reach the downed weight 1 from the server's events and
  frames, the reviver's kneel reaches 1 on both screens while the hold lasts, and a walk-away, a finished hold and a
  revive each ease their weights back to 0 on both. Captures of the same flow from the two screens:
  `game/tests/captures/revive_poses_online.tscn` (the window is the downed player's screen, a second viewport is the
  reviver's; the reviver is a bot that walks over and holds Use).

## Reloading

A reload is a motion per mechanism, played on the solved grips (#683, after #383's tilt). Players missed reloads
(maintainer, 2026-11-03: "Reload Animations that is more noticeable and Reload Sounds if not exists yet."), and the
reason was on the screen: from the shoulder camera (0.6 m right, 2.3 m behind) a weapon held at the hip is behind the
Soldier's head, and #383's 35 degree tilt took it further down behind him. Measured by drawing the frame again without
the weapon and counting the pixels that change (`tests/captures/reload_sheet.tscn --measure`, 1920 by 1080):

| Weapon | Before (#383 tilt), mid-reload | After, mid-reload | After, most |
| --- | --- | --- | --- |
| Tommy gun | 0 | 6,684 | 6,808 |
| Lever rifle | 284 | 8,676 | 9,352 |
| Double-barrel | 336 | 7,332 | 9,076 |
| Revolver | 740 | 3,688 | 4,280 |
| Flare gun | 888 | 2,680 | 5,124 |

(the median of the frames from 20 to 70 % of the reload, in pixels of the 2.07 million on screen.) So every reload
carries the weapon **out to the right of the head and up**, turns its working side to the camera, and turns the chest
the left shoulder forward so the short left arm still reaches it.

### How it is made

- **Data, one file per weapon:** `gameplay/player/reload/<weapon id>.tres` (`ReloadMotion`), a row of `ReloadKey`s at
  shares of the reload's time, so it stretches over the weapon's own `reload_time`. A key gives the weapon's move and
  turn from the hold (metres and degrees in the aim's frame, about the grip), the chest's lean and turn, the left hand's
  point (on the weapon in the model's units, optionally on its moving part, or at the belt pouch in the body's frame),
  how far the part is open, whether the part is on the weapon and whether the ammunition is in the left hand. Numbers
  ease between keys (smoothstep); the switches hold from their key. The first and last keys are the hold's own, so a
  reload starts and ends on the pose the aim weight gives (hip or aim) and never touches the weight.
- **The arms** (`WeaponHandsIK`): the move and turn are added to the hold's target, the right hand follows the weapon
  through its solved grip, and the left hand reaches the key's point, blended bone by bone from where the hold left it
  (the fore-end, or the clip's arm for a one-handed gun), so it leaves and comes back without a jump. Its fingers half
  open off the fore-end grip.
- **The part and the ammunition** (`ReloadView`, owned by `PlayerAnimation`): the weapon's moving part is a node of its
  model, made in Blender at its pivot (`tools/blender/build_weapons.py`, `NODES`), turned and slid by the key's
  `part`; the ammunition is its own small model beside the gun's (`<gun>_ammo.glb`), on a `BoneAttachment3D` on the left
  hand bone, standing out of the fingertips at 1.5 times the gun's size (the kit's hands are two to three times a
  person's, and a shell at the gun's size vanished in the fist). The tommy gun's drum is taken off the gun by the hand
  where it is and a full one put back.
- **Every client** draws every player's reload from the server's `reload_started` (`NightView.show_reload` calls
  `PlayerAnimation.reload(seconds)`), so a teammate's is the same motion; a swap, going down or kneeling at a revive
  cancels it (it eases out in a few frames), and the sprint carry waits while the arms are busy.
- The authored `Reload_<Class>` clips in `clips.json` are not played: their poses were keyed on the kit's hold, before
  the grips were solved.

### Every weapon

| Weapon | Mechanism | The motion | Part | Ammunition | Steps and their sounds |
| --- | --- | --- | --- | --- | --- |
| Revolver (`pistol`, 1.3 s) | revolver | up beside the shoulder; cylinder out; muzzle up to throw the empties; down to load | `Cylinder`, 85 degrees out to the left on its crane | speedloader | `cylinder_out` `reload_revolver_open`, `eject` `reload_revolver_eject`, `pouch` `reload_pouch`, `rounds_in` `reload_revolver_rounds`, `cylinder_in` `reload_revolver_close` |
| Tommy gun (`smg`, 1.9 s) | magazine | raised muzzle up, the drum toward the camera; drum off and stowed, a full one on; bolt pulled | `Drum`, slid down and out to the right | the drum | `mag_out` `reload_smg_mag_out`, `pouch` `reload_pouch`, `mag_in` `reload_smg_mag_in`, `bolt` `reload_smg_bolt` |
| Lever rifle (`rifle`, 2.2 s) | lever | rolled 60 degrees so the loading gate faces up; three rounds pushed in; lever thrown | `Lever`, 50 degrees down on its pin | one round | `pouch` `reload_pouch`, `round_in` (3) `reload_rifle_round`, `lever` `reload_rifle_lever` |
| Double-barrel (`shotgun`, 2.4 s) | break-open | out right, muzzle down; barrels broken open; two shells in; flicked shut | `Barrels` with the forend, 45 degrees on the hinge pin | two shells | `break_open` `reload_shotgun_open`, `eject` `reload_shotgun_eject`, `pouch` `reload_pouch`, `shells_in` `reload_shotgun_shells`, `snap_shut` `reload_shotgun_shut` |
| PPSh (`ppsh`, 2.8 s) | magazine | like the Tommy gun's: the drum taken off and a full one put on, the bolt pulled | `Drum` | the drum | `drum_out`, `pouch`, `drum_in`, `bolt` |
| MP5, M4A1 (`mp5` 1.9 s, `m4a1` 2.1 s) | magazine | muzzle up, the magazine toward the camera; out, a full one in, the bolt | `Magazine` | the magazine | `mag_out`, `pouch`, `mag_in`, `bolt` |
| M249 (`m249`, 5.0 s) | belt | the feed cover up, the belt laid in, the cover shut, the charging handle | `Cover` | a belt of rounds | `cover_open`, `pouch`, `belt_in`, `cover_shut`, `charge` |
| .50 calibre (`fifty_cal`, 3.4 s) | magazine | the box magazine out and in, the long bolt | `Magazine` | the magazine | `mag_out`, `pouch`, `mag_in`, `bolt` |
| Pump 870 (`pump_870`, 2.8 s from empty) | by the round | rolled so the loading port faces up; a shell from the belt into the port, six times; the pump racked | `Pump` | one shell | `pouch`, `shell_in` (once a round), `pump` |
| Flare gun (`flare_gun`, 2.0 s) | break-open | up beside the shoulder; barrel broken open, the case shaken out; a flare in; snapped shut | `Barrel`, 50 degrees on its hinge | one flare cartridge | `break_open` `reload_flare_open`, `eject` `reload_flare_eject`, `pouch` `reload_pouch`, `shells_in` `reload_flare_in`, `snap_shut` `reload_flare_shut` |

The melee weapons do not reload. The sounds and their levels under fire are on the [audio page](audio.md#reloads).

**A reload that loads one round at a time (#793, the pump).** The server's reload is a clock a round long
(`WeaponDef.reload_by_round`: `reload_time / magazine_size`), puts each round in the magazine as its time comes
(`reload_round`) and ends when a shot is fired with a round in (`reload_interrupted`) or the tube is full
(`reload_finished`). `reload_started` says how many rounds it will load (`rounds`) and its `seconds` are that many round
times. The motion is the pump's full reload from empty, with a lead-in, six identical cycles (one shell fetched from the
belt pouch and put in the port) and a lead-out (the pump racked): `ReloadMotion.loop_rounds`, `loop_from` and `loop_to`
say which stretch loops, and a reload of fewer rounds plays the lead-in, that many cycles and the lead-out
(`ReloadMotion.playhead` maps the time, `event_shares_for` the sounds, so a two-round top-up sounds two shells). An
interrupted reload lets the arms back to the hold in a few frames, as a swap does (`NightView.show_reload_stopped`).

### Proof

`tests/player/test_reload_motion.gd` steps every gun's reload tick by tick, hip and aimed: the weapon turns at least
30 degrees and moves at least 0.1 m, never more than 20 degrees a tick (the revolver's flick is 17.4), the left hand goes
more than 0.35 m from the grip (the belt) and within 0.3 m of the weapon, the part opens fully and is back on, the
ammunition shows and is gone, and the weapon is back on its hold by the end of the reload time with the aim weight
unchanged; a swap ends it, the sprint carry waits for it, and every motion's file starts and ends on the hold and names
a part its model has. `test_hand_grips.gd` measures the right hand on its grip twice through each reload,
`test_night_reload.gd` plays each one through the real night, and `test_remote_weapons.gd` checks that a second client
sees the reload and the revolver's cylinder open. Captures: `tests/captures/reload_sheet.tscn` (each gun's reload
from the shoulder camera and a teammate's from the player's screen, `--measure` for the numbers above).

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

## Quick melee

The `V` button (#411, [Quick melee](weapons.md#quick-melee)) strikes with whatever is in the hands, so one blow has to
look right with a revolver, a lever rifle, a double shotgun, a bat and an axe, without a clip per gun. It is one motion,
an overhead bash (the weapon is the club), authored once and keyed from each class's own aim pose: `Strike_Rifle`,
`Strike_Shotgun`, `Strike_Pistol` and `Strike_Melee`, built by `strikes()` in `tools/blender/soldier_clips.py` into
their own file, `game/assets/characters/soldier/strike/soldier_strike.glb` with its `clips.json`; `PlayerAnimation` adds
them to the library and `strike()` plays the class's (`play_action(&"Strike")`). A bat or an axe uses the melee class's.

- **The motion** (13 frames at 24 fps, 0.54 s, inside the 0.6 s cooldown): a wind-up at frame 3 (the right arm up and
  the chest turned back), the blow at frame 6 (the arm down and ahead, the chest forward), the follow-through at 8, home
  at 13. The same offsets for every class; `STRIKE` says how much of it the right arm does on its own, the rest being the
  spine, which carries both hands and the weapon: a gun in two hands is mostly spine (0.45), a pistol, a bat and an axe
  in one hand swing the whole arm (0.9, 1.0).
- **The shouldered pose is let go at once.** A gun's arms are the IK pose (`WeaponHandsIK`), which fades out over a
  fifth of a second when a clip takes the arms: the wind-up of a blow was flattened by it (the gun's hand moved 0.26 m
  instead of 0.5) and the arms popped when it reached zero. `strike()` drops the IK weight to 0 on the first frame.
- **Checked against each weapon in the hand** (`game/tests/player/test_quick_melee_strike.gd`): for the revolver, the
  rifle, the shotgun, the bat and the axe the weapon stays shown and in the hand, travels more than 0.35 m from the
  wind-up to the blow, lands ahead of the body, clears the head by 12 cm and is back where it began; `hit` comes once.
  The contact sheets are `render_clips.py --only Strike --view side` with each weapon (`--weapon`, as the sprint
  sheets do); the captures are the player's own camera, `game/tests/captures/quick_melee_tour.tscn`.

```sh
blender -b --factory-startup -P tools/blender/build_soldier.py -- --soldier <bundle>/models/PpLF4rt4ah.glb     --clips Strike_Rifle,Strike_Shotgun,Strike_Pistol,Strike_Melee --out game/assets/characters/soldier/strike/soldier_strike.glb
blender -b --factory-startup -P tools/blender/render_clips.py -- --soldier <bundle>/models/PpLF4rt4ah.glb     --only Strike --view side --out <scratch>/strike     --weapon Rifle=game/assets/weapons/lever_rifle/lever_rifle.glb=Shotgun=0.71     --weapon Shotgun=game/assets/weapons/double_shotgun/double_shotgun.glb=Shotgun=0.82     --weapon Pistol=game/assets/weapons/revolver/revolver.glb=Pistol=1.76     --weapon Melee=game/assets/weapons/baseball_bat/baseball_bat.glb=Shovel=0.86=-90,0,0
```

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
| Sprint_tommy_gun | upper | loop | 17 (0.71 s) | the rifle's carry through the Tommy gun's own grip (see below) |
| Sprint_Pistol | upper | loop | 17 (0.71 s) | one hand at the side, the forearm pumping (the kit's `Run_Gun` arm) |
| Sprint_Melee | upper | loop | 17 (0.71 s) | a runner's arm out from the side, the weapon upright and leaning back |

- **On Run's own frames.** Each clip is the kit `Run`, frame for frame: its spine, shoulders and left arm (the chest
  twists 9 degrees each way and bobs with the stride), so the swing lands on Run's footfalls by construction (the
  right foot plants at frame 3.5, the left at 12.5; the Body is lowest at 4 and 13). Only the right arm and, for the
  two-handed guns, the left arm are posed for the class.
- **Rifle and Shotgun: the weapon's pose, both hands on it (#527).** The carry says where the weapon is, in the
  world's axes at Run's frame 4 (his right is -X, ahead -Y), turned with the chest: its grip `(0.1, -0.33, 0)` m from
  the Torso bone's head (a little left of centre, ahead of the belly; the shotgun 3 cm lower), the muzzle pointing
  `(0.85, -0.5, 0.45)` (across to his left, ahead and up) and the top facing `(-0.3, 0.2, 1)`. On top of the chest's
  twist the gun swings 6 degrees each way (7 for the shotgun) and the muzzle dips 4 degrees (5) a frame after each
  footfall. Both arms reach it by two-bone IK in Blender, the way `WeaponHandsIK` does while aiming: the right hand
  bone turned so the weapon, through its solved grip (`grips/<model>.tres` `hold`, at the hold's `model_scale`),
  points that way with its grip on the point; the left hand bone on the grip's `left_hand` point of that weapon and
  turned to it. `soldier_clips.py` reads the hold and grip files itself (`game_grip`; Godot's bones have Blender's pose
  bone axes), so a re-solved grip needs only a rebuild. Both hands land within 0.001 m. The muzzle shows past the
  left of the helmet from the shoulder camera; a carry in front of the chest (tried first) is hidden by the body.
  Built the old way (the forearm fixed by the gun's direction through the kit weapon's hold, the left hand on a typed
  support point), the carry moved with every new grip: on #507's grips the gun hung by the right leg.
- **A model's own carry.** The Tommy gun's pistol grip turns it 90 degrees off the lever rifle's wrist in the hand,
  so through `Sprint_Rifle` it pointed at his legs. A model whose grip is that far from its class's gets
  `Sprint_<model>` (`SPRINT_CARRY` entries with a `class`), the same pose through its own grip;
  `SprintCarry.clip_for` picks it for that model and the class's carry for every other.
- **Pistol.** `Run_Gun`'s right arm (the forearm pumps 46 degrees a stride), the upper arm swinging a third of the left
  arm's swing half a stride later.
- **Melee.** The upper arm hangs out from the side (`(-0.5, 0.1, -1)`) and swings 24 degrees fore and aft against the
  left arm; the forearm points ahead and pumps 1.2 times the arm's swing; the forearm is turned about its axis so the
  shaft leans up, back and out (`(-0.25, 0.45, 1)`): it stays up and clears the head from the camera. Hanging, the
  weapon pointed at the legs (first try).
- **Only the spine, the shoulders, the arms and the hand bones move.** The fingers are the grip's: `HandGripPose`
  closes the right hand whenever a weapon shows and the left on a two-handed gun while the carry is in (its weight,
  as the shouldered pose's while aiming). The hand bones (`Index1`, the palm the weapon rides) turn as the IK turns
  them. A test fails if a Sprint clip moves a finger or a leg bone.

### The blend

- **When.** The carry comes in while the body is `sprinting`, **on the floor**, at `sprint_carry_min_speed` (3 m/s)
  or more, with nothing else for the arms (no aim and no hip-fire hold, no action clip, no repair). It eases in over
  `sprint_carry_in` (0.2 s) and out over `sprint_carry_out` (0.15 s), linearly, through a smoothstep in the tree
  (`PlayerTuning`, group Sprint carry).
- **Out at once for the arms' work.** The aim, a shot (the hip-fire hold), a reload, a swing, an equip or a grenade
  start the blend-out on their first tick; the one-shot's own fade (0.05 s) covers the carry first. The shot itself is
  not delayed: `muzzle` is frame 0 of Fire and comes in the call that starts it, carry or not. The shouldered pose
  (`WeaponHandsIK`) gives way to the carry by its weight (`weight = shoulder x (1 - smoothstep(carry))`, the curve
  the tree brings the carry clip in on, so the two cross over and neither leads, #619). The first build (#525)
  scaled the modifier's `influence` linearly and switched it off at 0: the engine blends the chest and the hands by
  `influence` but draws the upper and lower arms in the IK pose at any value while the modifier is on, so the arms
  snapped to the carry's (the weapon turned 29 degrees and the left arm 65 in one tick) and the start of the sprint
  popped. The blend is now done inside the modifier, bone by bone, and `test_sprint_start_blend.gd` draws the start
  from a stand, a run and the aim and fails on a jump.
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
- **On the hand grips (#527).** The carry keys no finger, so `HandGripPose` closes the fingers over it, and the
  long guns' clips are built through the grip files: when a grip is solved again (`solve_grips.gd`), rebuild the
  Sprint file (not needed after `--fingers`, which keeps the `hold`) and check the hands with `test_hand_grips.gd`,
  which measures both hands on every weapon's skin in the sprint too.
- **Checked:** `game/tests/player/test_sprint_carry.gd` (the clips are on Run's cycle; the carry plays only sprinting
  on the ground, holds in the air and never starts there; its phase matches Run to 0.002 s; it catches up after a
  landing without jumping; aim, a hip shot, a reload and a swing take it out within 0.15 s; the first shot's `muzzle`
  comes in the same call; the hand swings more than 5 cm a stride in every class; no finger or leg moves) and
  `game/tests/night/test_night_sprint_carry.gd` (sprint commands through the real night carry the weapon, and the
  first shot after the sprint comes on the same tick as one from a standstill). Captures:
  `game/tests/captures/sprint_carry_tour.tscn`.

## Dual pistols

The first weapon held in both hands (#789, the hold: [Weapons in the hands](weapon-hold.md#the-dual-pistols)). The aim,
the fire and the reload are the hands' IK and the reload motion, which pose both arms; six `upper` clips, class `Dual`,
cover what the arms do around them, in their own file (`game/assets/characters/soldier/dual/soldier_dual.glb` with its
`clips.json`, added to the Soldier's library by `PlayerAnimation` through `DualClips`):

| Clip | Plays | Frames | Events |
| --- | --- | --- | --- |
| Aim_Dual | loop | 48 | - |
| Fire_Dual | once | 6 | muzzle 0, can_fire_again 6 |
| Equip_Dual | once | 10 | weapon_visible 2, ready 10 |
| Unequip_Dual | once | 10 | weapon_hidden 8 |
| Strike_Dual | once | 13 | whoosh 3, hit 6, can_strike_again 13 (the [quick melee](#quick-melee): both pistols come down together) |
| Sprint_Dual | loop | 17 | - (Run's cycle, see [Sprint carry](#sprint-carry)) |

**Made by mirroring, from the IK's hold.** The kit rig is an exact mirror: each left bone's local rotation is the right
one's with `y` and `z` negated (the Blender build asserts the left hand ends within 2 mm of the right's reflection, and
prints 0.0). Every Dual clip starts from the Pistol pose with the right arm solved to where the night's hand IK holds
the right pistol (`DUAL_HAND`: x -0.62, y -0.42, z 1.23 at kit scale, read in Godot; the elbow out and down), the hand
turned as the Pistol pose turns it, and `Shoulder`, `UpperArm`, `LowerArm` and `Index1` of the left side set to the
right side's, flipped by that rule (`dual_arm`, `mirror_arm`, `dual` in `tools/blender/soldier_clips.py`); the chest,
which both arms hang from, keeps its own twist. The Pistol pose mirrored as it was (#789) put both hands on the body's
middle line, one through the other: the IK hid it while aiming, but the equip and the quick melee play the clip's own
arms (Strike_Dual 142 mm, Equip_Dual 108 mm, #939). The sprint's left arm is the right's, half a stride on (`shifted`),
so the two arms pump against each other as a runner's do. `Fire_Dual` is one kick on both arms for the clip's pose only:
which gun kicks is the IK's, per shot (`WeaponHandsIK.recoil` and `recoil_left`, from the shot's `hand`).

```sh
blender -b --factory-startup -P tools/blender/build_soldier.py -- --soldier <bundle>/models/PpLF4rt4ah.glb     --clips Aim_Dual,Fire_Dual,Equip_Dual,Unequip_Dual,Strike_Dual,Sprint_Dual     --out game/assets/characters/soldier/dual/soldier_dual.glb
gds godot -- --path game res://tests/captures/dual_pistols_tour.tscn --write-movie <abs>/f.png --fixed-fps 30     --quit-after 285 [-- --view=side|front|rear|top]     # hold, aim, fire, reload, sprint, sprint into the aim, the blow
```

The Strike and Sprint files are built with their clips by name: `--clips Strike_` or `Sprint_` would write
`Strike_Dual` or `Sprint_Dual` into them too.

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
    --soldier <bundle>/models/PpLF4rt4ah.glb --clips main --out game/assets/characters/soldier/soldier.glb
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
# The perk drink (#912), its own file (prints DRINK: each key's miss and the mouth in the Head bone's frame); the bottle
# and its grip; the sheet (front, or --view back) with the bottle through its grip; the captures in the game:
blender -b --factory-startup -P tools/blender/build_weapons.py -- --only perk_bottle
godot --headless --path game -s res://tests/art/solve_grips.gd -- --only perk_bottle
blender -b --factory-startup -P tools/blender/build_soldier.py -- --soldier <bundle>/models/PpLF4rt4ah.glb     --clips Drink_ --out game/assets/characters/soldier/drink/soldier_drink.glb
blender -b --factory-startup -P tools/blender/render_clips.py -- --soldier <bundle>/models/PpLF4rt4ah.glb     --only Drink --zoom 2 --grip Drink=game/assets/weapons/perk_bottle/perk_bottle.glb=perk_bottle --out <scratch>/drink
gds godot -- --path game -s res://tests/captures/drink_tour.gd -- --view player --out <scratch>
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
# The sprint carry clips, their own file (prints SPRINT: each clip's frames and how far each hand missed the weapon);
# one stride of each over Run with the game's weapons held through their grips (Sprint; SprintBefore is Aim_<Class>
# over Run); the tour from the shoulder camera, and with `-- --side` from his right:
blender -b --factory-startup -P tools/blender/build_soldier.py -- --soldier <bundle>/models/PpLF4rt4ah.glb     --clips Sprint_Rifle,Sprint_Shotgun,Sprint_Pistol,Sprint_Melee,Sprint_tommy_gun,Sprint_ppsh,Sprint_mp5,Sprint_m4a1,Sprint_m249,Sprint_fifty_cal,Sprint_pump_870 --out game/assets/characters/soldier/sprint/soldier_sprint.glb
blender -b --factory-startup -P tools/blender/render_clips.py -- --soldier <bundle>/models/PpLF4rt4ah.glb     --only Sprint,SprintBefore --view back --out <scratch>/sprint     --grip Rifle=game/assets/weapons/lever_rifle/lever_rifle.glb=rifle     --grip Shotgun=game/assets/weapons/double_shotgun/double_shotgun.glb=shotgun     --grip tommy_gun=game/assets/weapons/tommy_gun/tommy_gun.glb=smg     --weapon Pistol=game/assets/weapons/revolver/revolver.glb=Pistol=1.76     --weapon Melee=game/assets/weapons/baseball_bat/baseball_bat.glb=Shovel=0.86=-90,0,0
gds godot -- --path game res://tests/captures/sprint_carry_tour.tscn --write-movie <abs>/f.png --fixed-fps 30 --quit-after 700
gds godot -- --path game res://tests/captures/sprint_carry_tour.tscn --write-movie <abs>/f.png --fixed-fps 30 --quit-after 700 -- --side
```

`<bundle>` is the Toon Shooter kit's folder in `refs/`. The `.glb` is third-party-derived (CC0); it is committed with
its licence entry (`game/assets/characters/soldier/LICENSE.md`, approved by the maintainer in issue #90).

The player controller (`game/gameplay/player/player_animation.gd`) plays the clips by these bare names and attaches
the lever rifle to `Index1.R` with `HOLD_GUN`; the file itself carries no weapon.
