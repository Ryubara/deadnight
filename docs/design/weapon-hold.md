# Weapons in the hands

How a weapon is sized and held by the Soldier: one size rule for every weapon, the grip on the right hand, the support
hand on the fore-end, the stock at the shoulder and the barrel along the camera's aim. The numbers are data, one
`WeaponHold` file per weapon class in `game/gameplay/player/holds/`; the arms are posed by `WeaponHandsIK`; the tests
are `game/tests/player/test_weapon_hold.gd`. The kit's grip and the clips are in [Animation](animation.md#weapons-in-the-hand).

## The size rule

**A weapon is its real length, at the Soldier's size, and a tenth more so that it reads.**

`length in the game = real length x 1.4 m / 1.75 m x 1.1`

The Soldier is 1.4 m tall in the game (the rig at the player's 0.8 scale), a person 1.75 m, so everything is 0.8 times
real; the extra 1.1 is the chunk the kit's props have (a chibi head and fists make a true-to-scale gun look thin). The
rule is `WeaponHold.rule_length()`; the test checks every weapon's length in the game against it within 5 %. Before
this rule the lever rifle was 1.32 m in the game (the Soldier's whole height) and the shotgun 1.21 m.

The glb models are drawn at the weapon's real length (the rifle 1.65 m with its fattened cross-section), so each hold
carries `model_scale`, the factor from the model to the rule.

| Weapon | Real length | Rule | Model (glb) | `model_scale` | In the game | Before |
| --- | --- | --- | --- | --- | --- | --- |
| Lever rifle (Rifle) | 1.07 m | 0.94 m | 1.65 m | 0.71 | 0.94 m | 1.32 m |
| Double shotgun (Shotgun) | 1.12 m | 0.99 m | 1.51 m | 0.82 | 0.99 m | 1.21 m |
| Baseball bat (Melee) | 0.86 m | 0.76 m | 1.11 m | 0.86 | 0.76 m | 0.89 m |
| Claw hammer (the repair's tool) | 0.33 m | 0.29 m | 0.73 m | 0.85 | 0.50 m | new |

**The hammer is the one exception, and a tool, not a weapon.** At the rule's 0.29 m the Soldier's chibi fist (about
0.15 m across) hides all of the handle and half the head, and the repair clip is seen for a second at a time, so its
hold file (`holds/hammer.tres`, class `Repair`) sizes it at 0.50 m, 1.7 times the rule, as the kit draws its own small
things large. It is not in `HOLD_CLASSES`: the rule's test covers the weapons the player swaps between.

## How a gun is held

The weapon rides the right hand (`Index1.R`) on the kit's grip, as before, so the clips that move the arm (Reload,
Equip, Unequip, Swing, the repair) still carry it. While the clip leaves the hands to the pose (standing, walking,
running, aiming, firing) `WeaponHandsIK` takes the arms over, blended by `influence` at 14 per second, and is
switched off (`active`) once the blend reaches 0, since at influence 0 it still overrode the arms in the drawn pose:

1. The weapon's world pose comes from the aim: the grip sits `grip_offset` from the right shoulder joint (right,
   up, forward is negative), the muzzle along the aim, up stays up. The stock's butt, `butt`, lands against the shoulder.
2. The kit's grip turns that pose into the right hand's pose, and a two-bone IK (law of cosines, the elbow out and
   down) reaches it.
3. The left arm reaches `support`, the fore-end, the same way. Both are pure geometry on the clip's pose: no clock, no
   randomness.
4. Firing kicks the weapon back 5 cm and up 4 degrees, dying away at 16 per second.

**The aim.** At the hip the barrel is along the body (the body faces the movement; the camera's pitch still lifts
it). While aiming it follows the camera's yaw and pitch and turns in a little (at most 5 degrees) to cross the
crosshair's ray 12 m ahead of the camera: the camera is over the shoulder, the muzzle is not. The shot itself is
the `AimResolver`'s, from the muzzle to what the camera ray is on.

## Per weapon

| Weapon | Grip from the shoulder joint (m) | Support (model units) | Notes |
| --- | --- | --- | --- |
| Lever rifle | right 0.05, down 0.09, forward 0.32 | -0.45, -0.05 (the fore-end) | stock at the shoulder, left hand under the barrel |
| Double shotgun | right 0.05, down 0.09, forward 0.36 | -0.45, -0.03 | the same, the stock a little longer |
| Baseball bat | the kit's grip, `shouldered = false` | none | one hand, as the Swing clip moves it; two hands on the grip is open work |

`muzzle` and `butt` (the ends of the model, origin the grip) are in every hold so the tests, and later the muzzle flash
and the aim correction, read the same points.

## The `Muzzle` node

**Every firearm model carries a node named `Muzzle` at the tip of its barrel, `-Z` pointing out of the barrel** (a
Blender empty exported into the glb, so it is a `Node3D` in Godot). It is where everything that leaves the gun starts:
the muzzle flash today ([Shot feedback](shot-feedback.md)), a tracer or smoke later. Never a fixed offset from the body
(`NightTuning.muzzle_offset` only places the shot's ray for the server, not what is drawn).

- `PlayerAnimation.muzzle_point()` finds the `Muzzle` in the weapon in the hand, through the weapon mount. A model
  that has none yet gets one made at the hold's `muzzle` point (the model's units, turned so `-Z` is the barrel), so a
  model without the node needs no code change and nothing is logged. A class with no model at all (the pistol, the flare
  gun) has no point: its flash is at the server's muzzle, 0.6 m along the barrel, where the fist is.
- Every view reads it the same way: the local player, remote players and the bots (`NightView` maps the shooter's id to
  the body that draws it).
- `test_shot_feedback.gd` checks, for every firearm in the catalogue, that the flash's global position equals the held
  weapon's `Muzzle`, that a model's own `Muzzle` is preferred over the made one, and that another player's shot flashes
  on their weapon.

## Which weapon is which

The class of each weapon id is one table, `WeaponHoldMap` (`game/gameplay/player/weapon_hold_map.gd`): lever rifle is
Rifle, double shotgun Shotgun, every melee weapon (crowbar, bat, fire axe) Melee. `WeaponEquipSync`
(`game/gameplay/night/weapon_equip_sync.gd`) reads the `weapon` of every player in each frame the server sends and, when
it changes, calls `PlayerAnimation.equip` on that player's body: the local player and the others take the same line,
and a player who joins late shows the weapon of his first frame. The test is `game/tests/night/test_weapon_equip.gd`
(each id taken in hand through the real combat action, for the local player and a second one, and by a swap).

## What has no model yet

The catalogue has six weapons (pistol, SMG, shotgun, rifle, flare gun, crowbar) and three models. Three have none and are
listed in `WeaponHoldMap.NO_MODEL`, each held as the nearest class until its own model and hold file land (see the open
issue for the pistol, SMG and flare gun):

| Weapon | Held as | Shows |
| --- | --- | --- |
| SMG | Rifle | the lever rifle model, two-handed |
| Pistol | Pistol (the one-handed clips) | the arm out toward the aim, the hand empty |
| Flare gun | Pistol | the same |

The fire axe has a model but no id in the catalogue yet; it is Melee as soon as it has a melee `WeaponDef`. Adding a
weapon's model is a glb with its origin on the grip and a `.tres` here; then take its id off `NO_MODEL` and out of the
table above.

## Proof

`test_weapon_hold.gd`: per gun in the aim pose, the grip within 3 cm of the pose's target, the left hand within 12 cm of
the fore-end, the stock within 16 cm of the shoulder, the barrel within 5 degrees of the camera ray and within 1 degree
of the crosshair's point 12 m ahead; at the hip and running, along the body within 3 degrees; pitched with the camera;
hands back to the clip during Reload; the bat in the hand at the rule's size. The capture sheet
(`game/tests/captures/weapon_hold_sheet.tscn`: side, the shoulder camera, from behind, from above, in idle, run, aim
and fire) is in the pull request.
