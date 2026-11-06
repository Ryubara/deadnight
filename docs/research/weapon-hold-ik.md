# Weapon hold and arm IK

What building `WeaponHandsIK` (the Soldier's arms on his weapon) taught us. The design is in
[Weapons in the hands](../design/weapon-hold.md).

## What was wrong, and why

Measured on main with `tests/captures/weapon_hold_sheet.tscn` (every weapon in idle, run, aim and fire from the side,
the shoulder camera, behind and above; it prints `HOLD` lines with the grip-to-hand distance and the barrel's direction):

| Symptom | Measured | Why it drifted |
| --- | --- | --- |
| Barrel angled up | the lever rifle's muzzle direction was (-0.02, 0.36, -0.93) in every pose: 21 degrees above the body's forward, never level | `HOLD_GUN` was measured from the kit Shotgun in `Idle_Shoot`, a one-handed pose with the arm out and the muzzle lifted; the transform was copied as if it were a rest pose, and nothing compared the barrel with the aim afterwards |
| Gun too long | lever rifle 1.65 m x the Soldier's 0.8 scale = 1.32 m, as tall as the Soldier (1.4 m); shotgun 1.21 m, bat 0.89 m | the models were drawn at real length and only their cross-sections fattened (weapons page); `player.tscn` then scales the Soldier to 0.8, a factor no weapon page mentions. The unit-scale check was against the kit's weapons, which are not at real length |
| Stock floats, left arm hangs | the right hand's grip is an arm's length (0.66 m) from the shoulder; butt about 0.25 m behind it, so the stock stayed 0.4 m in front of the shoulder; the left arm kept the clip's hanging pose | the clips are one-handed; #110 (left-hand IK) was designed but never built, and a transform on the hand bone cannot bend the arm |
| Every gun is the lever rifle | the shop's shotgun and the revolver showed the lever rifle | `PlayerAnimation.equip` is called by nothing outside tests; the class stays `Rifle` (issue #285) |

The method: put the numbers next to the picture. The `HOLD` line said 21 degrees where the eye only said "off"; the
size came from `model length x scale x 0.8` against the Soldier's bounds. Tests now assert both.

## Findings

| Finding | Detail |
| --- | --- |
| A `SkeletonModifier3D` child of the Skeleton3D runs after the clips | Set `influence` to blend it with the clip's arms (0 clip, 1 modifier); a `BoneAttachment3D` under the skeleton sees the modified pose |
| The modified pose is only readable at `skeleton_updated` | After the frame the skeleton gives back the clip's pose: `get_bone_global_pose` read later (a test after `await process_frame`, a script in `_process`) shows the unmodified arms. Tests connect to `skeleton_updated` and record the bones there |
| The modifier's `influence` does not blend the arms | With the modifier on, `Torso` and the hand bones blend linearly with `influence`, but `UpperArm` and `LowerArm` (both sides) are in the IK pose at any influence, 0 included; switching `active` off then snaps them to the clip's (a 27 to 66 degree turn in one tick, the weapon 29, a hand 0.7 m). `WeaponHandsIK.weight` blends every bone it turns itself (slerp from the clip's local rotation to the solved one), the modifier's `influence` stays 1 (#619) |
| Work in world space | The rig is Z-up under a rotated, scaled Model; reading each bone as `skeleton.global_transform * get_bone_global_pose(b)`, solving in the world and writing back `parent_basis.inverse() * wanted_basis` as the local rotation never needs the bones' own axes |
| Two-bone IK needs no IK node | Law of cosines for the elbow on the plane toward a pole (elbows out and down), then turn each bone's current direction onto the wanted one with `Quaternion(from, to)`; two passes settle the forearm |
| The right hand gets its orientation from the kit hold | `hand_basis = weapon_basis * kit_hold_basis.inverse()`: the weapon sits in the fist exactly as the kit's does, whatever the arm does |
| Toe in to the crosshair | The camera is over the shoulder; a parallel barrel misses the camera ray's point 12 m ahead by 3.7 degrees. Aiming the barrel at that point costs at most 5 degrees off the ray and ends the miss |

## The reload and the shouldered hold out of the body (#987)

Measured with `tests/captures/clip_arms_tour.tscn -- --measure --every=1` (the real player, every gun, the pose after
the IK, every tick of the reload; mm, kit scale, deepest vertex over the tolerance of 30; rolled sleeves / jacket):

| Beat, check | Before | After |
| --- | --- | --- |
| Reload, left arm | 94-125 / 95-120 | none |
| Reload, right arm | 33-96 / 33-101 | none |
| Fire, right arm (the long guns) | 30-53 / 30-45 | none |
| Menu holds, right arm (long sleeve) | 30-39 recorded | none |

- **The issue's "right hand into the trunk" was the other arm.** `ClipFit`'s arm checks join the body and the other
  arm. Split by target, no right hand went into the trunk: it went 33-101 mm into the left hand and forearm. Split a
  check by target before tuning a pose.
- **The left hand in the body had four causes:** the belt point inside the hips (half width 0.32 kit); a straight line
  from a gun at the right to the belt on the left, through the belly; the hold's pole (`side + down`) lying along the
  hanging arm, so the elbow flipped between ticks and turned in; the hand left bent as on the fore-end, the fingers in
  the thigh. Straightening alone took 94-125 down to 56-99; the elbow's own pole took the rest.
- **The two hands:** the fists are about 0.25 kit wide, so a left hand on a magazine's middle or a drum's centre is in
  the right fist. The hand takes the far end: the bottom of the magazine (M4, MP5, .50), the low front of the drum, not
  the hand further along the barrel (a search found that too, and it left the drum held by nothing). A push of the left
  hand off the right arm by the bones' lines changed nothing and went: the arm is at full stretch there, and what
  matters is which side of the gun the hand is on.
- **The hold:** the grip moved out 5 cm (the pump 8) cleared what a shot's kick did; elbows at 1.6 of the shoulder width
  instead of 1.0 only took 53 to 43 and left the pump at 50, so `ELBOW_OUT_TWO_HANDED` stayed.
- **The tour's reload started in a hop:** `teleport` put the player 5 cm up and the reload began in the landing (hips
  0.5 kit up, then 0.1 down). The tour now settles first.

## The poses #987 left over the tolerance (#1282)

Measured again on main after #987 with `clip_arms_tour.tscn -- --measure --every=1 --trace` (every weapon, every
tick, 3 cm; mm, rolled sleeves / jacket), then after the fixes: the same numbers #987's report gave. The table and
the changes are in [Arms and the body](../design/animation.md#arms-and-the-body).

- **The crawl was the arm's blend, not a pose.** Both clips are clean alone; blended bone by bone from the sit (the right
  forearm over the knee) to the crawl (the elbow on the ground, 8 cm wider) the arm crossed the belly and the thigh at
  weights 0.1 to 0.5 (31-65 mm in a probe that blended the clips directly, `ClipFit` on the result, 8 phases of the
  crawl). The belly-and-thigh fold is tight enough that even 10 % of the way toward the crawl faulted. Faster easing
  would only shorten it; a slower one would lengthen it. What fixed it is a waypoint, a still pose with the hand out and
  up, that the arm passes through first: sit to it, then on to the crawl. A blend that mixes the waypoint and the
  crawl at once (the arm = sit to crawl, then toward the waypoint) still had a band at weights 0.03-0.08, 31-38 mm: the
  crawl's own pull is in the arm while the waypoint's share is small; so the arm is blended sit to waypoint first
  (`crawl_lead`) and that result to the crawl (`crawl`). Choosing the waypoint by the sit-to-waypoint path alone (40
  steps, both looks, 3 candidates clean of 5) is the cheap part: the first try (0.62 out, 0.34 up) was clean on her and
  faulted 31-36 mm on his jacket.
- **A blend is a pose too.** The clip sampler reads clips and the tour reads the beats; the blend between two beats'
  clips was in neither until the crawl's blend-in. Probe a blend by evaluating the two clips' tracks at a weight and
  measuring (`ClipFit.measure` on the skeleton's own pose), not by waiting for the tree to pass through it.
- **The sprint, strike and cook faults were one vertex to a few at 30-37 mm**, each moved by a few degrees: the pistol
  carry's arm out 6, the pistol's wind-up out 38 (was 30 once; 27 mm at the 2 cm tolerance was too close), the grenade's
  elbow bent 30 (16 gave 30-31, 22 gave 32, 10 gave 40: the other way is not a fix).
- **The melee armband** is the seat's ring on the upper arm: the arm came down across the chest in the swing's
  follow-through (41 mm) and hung against it in the sprint (43-45): both went out from the side (8 and 16 degrees in the
  swing, the carry's `upper` from `(-0.5, 0.1, -1)` to `(-0.75, 0.1, -1)`, 20 mm at the 2 cm tolerance in the swing).
- **Where a clip lives:** the grenade's cook and the melee swing are in `soldier_parts.glb` (the library every dressed body
  has) as well as in their own files; the parts' copy is the one `SoldierClipFile.add` keeps, so a fix to the cook that
  rebuilt only the grenade file measured as no change at all until the parts file was rebuilt too.
  Glb files are in Git LFS: `git show HEAD:<file>.glb` prints a pointer, not the file.

## Not done

- The shoulder camera sees every gun end-on in the aim pose (a fist and a barrel tip); see [Weapons in the hands](../design/weapon-hold.md#which-weapon-is-which).
- The bat and the fire axe are one-handed.
- Hip fire keeps the body's forward (the body faces the movement), so the barrel at the hip is not on the crosshair.
