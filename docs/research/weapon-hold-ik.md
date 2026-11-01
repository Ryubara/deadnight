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
| Work in world space | The rig is Z-up under a rotated, scaled Model; reading each bone as `skeleton.global_transform * get_bone_global_pose(b)`, solving in the world and writing back `parent_basis.inverse() * wanted_basis` as the local rotation never needs the bones' own axes |
| Two-bone IK needs no IK node | Law of cosines for the elbow on the plane toward a pole (elbows out and down), then turn each bone's current direction onto the wanted one with `Quaternion(from, to)`; two passes settle the forearm |
| The right hand gets its orientation from the kit hold | `hand_basis = weapon_basis * kit_hold_basis.inverse()`: the weapon sits in the fist exactly as the kit's does, whatever the arm does |
| Toe in to the crosshair | The camera is over the shoulder; a parallel barrel misses the camera ray's point 12 m ahead by 3.7 degrees. Aiming the barrel at that point costs at most 5 degrees off the ray and ends the miss |

## Not done

- Pistol, SMG and flare gun have no model and no hold (issue #285); the Soldier shows the lever rifle for every gun.
- The bat and the fire axe are one-handed.
- Hip fire keeps the body's forward (the body faces the movement), so the barrel at the hip is not on the crosshair.
