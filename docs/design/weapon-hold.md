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
| Crowbar (Melee) | 0.75 m | 0.66 m | 0.75 m | 1.1 | 0.66 m | new |
| Tommy gun (SMG) | 0.88 m | 0.78 m | 0.88 m | 1.1 | 0.78 m | new |
| Revolver (Pistol), exception | 0.31 m | 0.27 m | 0.31 m | 1.76 | 0.44 m (1.6 times) | new |
| Flare gun, exception | 0.26 m | 0.23 m | 0.26 m | 1.76 | 0.37 m (1.6 times) | new |
| Claw hammer (the repair's tool) | 0.33 m | 0.29 m | 0.73 m | 0.85 | 0.50 m | new |

**Three exceptions, drawn larger on purpose.** The revolver and the flare gun are 1.6 times the rule
(`WeaponHold.size_factor`, the test pins it): at the rule's size they hide in the Soldier's 0.15 m fist and only the
barrel shows, and a player who cannot see his revolver thinks it is not there (#285). The hammer, below, is the third.

**The hammer is a tool, not a weapon, and the first exception.** At the rule's 0.29 m the Soldier's chibi fist (about
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
| Tommy gun | right 0.05, down 0.09, forward 0.34 | -0.365, -0.04 (the foregrip) | stock at the shoulder, left hand on the foregrip |
| Revolver, flare gun | right 0.10, down 0.05, forward 0.42 | none | one hand: the right arm out toward the aim, the left stays with the clip |
| Baseball bat, crowbar | the kit's grip, `shouldered = false` | none | one hand, as the Swing clip moves it; two hands on the grip is open work |

`muzzle` and `butt` (the ends of the model, origin the grip) are in every hold so the tests, and later the muzzle flash
and the aim correction, read the same points.

## Which weapon is which

Each weapon id of the catalogue has **its own hold file**, `game/gameplay/player/holds/<id>.tres` (class, model, size,
grip), so no two weapons share a model: the crowbar is not the bat, the Tommy gun is not the lever rifle.
`WeaponHoldMap` (`game/gameplay/player/weapon_hold_map.gd`) gives the clip class of each id (rifle Rifle, shotgun
Shotgun, SMG Rifle, revolver and flare gun Pistol, every melee weapon Melee); `PlayerAnimation.equip(id)`
takes the class's clips and the id's own hold (`WeaponHoldMap.hold_for`). A hold whose `scene` is not in
`assets/weapons/` yet
(`WeaponHold.has_model`) leaves the hand empty, never another weapon's model: `WeaponHoldMap.no_model()` lists those
(none now). `holds/melee.tres` stays as the class-level hold for a weapon with no file of its own, the bat and the
axe when they get an id. `WeaponEquipSync` (`game/gameplay/night/weapon_equip_sync.gd`) reads the `weapon` of every
player in each frame the server sends and calls `equip` on that player's body when it changes: the local
player and the others take the same line, and a player who joins late shows the weapon of his first frame. The test
is `game/tests/night/test_weapon_equip.gd` (each id taken in hand through the real combat action, for the local
player and a second one, by a swap, and no two ids sharing a model).

**The shoulder camera sees a gun end-on.** From behind the shoulder, with the barrel converging on the crosshair, every
gun in the aim pose is a fist and the tip of a barrel; the revolver is no different from the rifle. The side, rear and
other players' views (the capture sheet) show the guns whole.

## Attacks on the Soldier

A weapon's attack is drawn from the server's `shot_fired` event, for every player alike (`NightView.show_attack`): a
melee weapon plays `Swing_Melee` (wind-up, whoosh at frame 6, the blow at 9 to 12, follow-through), a gun plays
`Fire_<Class>` and its recoil. A blow has no muzzle: `ShotEffects.shot` draws no flash and no impact for it, only a
spark where it hurt (`damage_dealt` with `melee`). The blow itself is swept from the Soldier's head, not from the
shoulder camera 2.3 m behind him: from the camera the crowbar's 1.9 m fell short of a zombie at the player's face,
and no blow ever hurt in a real night (#285; the bots send their eye, so their tests passed). The tests are
`game/tests/night/test_night_melee.gd` (the real attack button, a zombie in reach, the swing, no flash, a zombie out
of reach left alone, a gun still flashes) and the capture `game/tests/captures/melee_swing.tscn`.

## Proof

`test_weapon_hold.gd`: per gun in the aim pose, the grip within 3 cm of the pose's target, the left hand within 12 cm of
the fore-end, the stock within 16 cm of the shoulder, the barrel within 5 degrees of the camera ray and within 1 degree
of the crosshair's point 12 m ahead; at the hip and running, along the body within 3 degrees; pitched with the camera;
hands back to the clip during Reload; the bat in the hand at the rule's size. The capture sheet
(`game/tests/captures/weapon_hold_sheet.tscn`: side, the shoulder camera, from behind, from above, in idle, run, aim
and fire) is in the pull request.
