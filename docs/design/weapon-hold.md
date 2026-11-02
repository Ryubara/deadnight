# Weapons in the hands

How a weapon is sized and held by the Soldier: one size rule for every weapon, the grip on the right hand, the support
hand on the fore-end, the stock at the shoulder and the barrel along the camera's aim. The numbers are data, one
`WeaponHold` file per weapon class in `game/gameplay/player/holds/`; the arms are posed by `WeaponHandsIK`; the tests
are `game/tests/player/test_weapon_hold.gd`. The kit's grip and the clips are in [Animation](animation.md#weapons-in-the-hand).

## The size rule

**A weapon is its real length at the Soldier's size, a third more as the kit draws its guns, and a gun whose grip
would vanish in his fist is drawn larger until it fills it.**

`length in the game = real length x 1.4 m / 1.75 m x 1.3 x size_factor`

The Soldier is 1.4 m tall in the game (the rig at the player's 0.8 scale), a person 1.75 m, so everything is 0.8 times
real. His hands are not: his fist is 0.20 m from the index knuckle's top to the pinky's underside and his index finger
5.7 cm thick (a real hand: 8.5 cm and 1.8 cm), 2.3 to 3 times real against a body at 0.8. The kit draws its guns for
those hands: beside the same Soldier its AK is 1.33 times a real AK, its revolver 0.79 m. So the rule's extra is 1.3,
the kit's own (it was 1.1 until #460, and every gun read small in the hand: the maintainer, "the player's hands are too
big for some guns"). The rule is `WeaponHold.rule_length()`; the test checks every weapon's length in the game against
it, times its `size_factor`, within 5 %. Before any rule the lever rifle was 1.32 m in the game (the Soldier's whole
height).

**The grip decides the small guns.** A real pistol grip is about the three fingers under the trigger finger, and a
trigger guard takes the finger with room. Measured on the models (`WeaponFit`, `game/tests/art/weapon_fit.gd`): the
grip below the trigger's level over the Soldier's fingers below the index (0.167 m), the guard's opening in front of
the trigger over his index finger, and the length over his height. A gun short of 1.0 on the grip gets a
`size_factor` until it is about there (the revolver and the flare gun). The long guns are held at the wrist like a
stick, the knuckles along it, so their "grip" is the wrist's length; the rule alone sizes them. The Tommy gun stays at
the rule (0.78 of the fingers, the pinky partly off the butt): any larger and the Soldier's left arm cannot reach its
foregrip with the stock at his shoulder, so its guard was deepened instead.

| Weapon | `model_scale` | `size_factor` | In the game | Grip / fingers | Guard / finger | Length / height | Before (#460) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Revolver (Pistol) | 2.275 | 1.75 | 0.56 m | 1.22 | 0.87 | 0.40 | 0.44 m; grip 0.94, guard 0.67 |
| Flare gun | 2.21 | 1.7 | 0.46 m | 1.18 | 0.97 | 0.33 | 0.37 m; grip 0.94, guard 0.77 |
| Tommy gun (SMG) | 1.3 | 1 | 0.92 m | 0.78 | 0.95 (guard made 1.5 cm deeper) | 0.65 | 0.78 m; grip 0.66, guard 0.58 |
| Lever rifle (Rifle) | 0.84 | 1 | 1.11 m | 1.99 along the wrist | 0.93 | 0.79 | 0.94 m; guard 0.79 |
| Double shotgun (Shotgun) | 0.96 | 1 | 1.16 m | 1.97 along the wrist | 1.11 (guard made 2 cm deeper) | 0.83 | 0.99 m; guard 0.61 |
| Baseball bat (Melee) | 1.01 | 1 | 0.89 m | - | - | 0.64 | 0.76 m |
| Crowbar (Melee) | 1.3 | 1 | 0.78 m | - | - | 0.56 | 0.66 m |
| Fire axe (Melee) | 0.95 | 1 | 0.94 m | - | - | 0.67 | new |
| Claw hammer (the repair's tool) | 0.85 | - | 0.50 m | - | - | 0.36 | unchanged |

The kit beside the same Soldier, for scale: revolver 0.79 m, SMG 0.91 m, AK 1.14 m, shotgun 1.24 m.

The glb models are drawn at the weapon's real length (the rifle 1.65 m with its fattened cross-section), so each hold
carries `model_scale`, the factor from the model to the rule. A grip is solved at its hold's size
([Grips](animation.md#grips)), so a new `model_scale` means solving the grip again (the test checks they agree).

**The hammer is a tool, not a weapon.** At the rule's 0.34 m the Soldier's fist hides most of the handle and the repair
clip is seen for a second at a time, so its hold file (`holds/hammer.tres`, class `Repair`) sizes it at 0.50 m, about
1.5 times the rule, as the kit draws its own small things large. It is not in `HOLD_CLASSES`: the rule's test covers
the weapons the player swaps between.

## How a gun is held

The weapon rides the right hand (`Index1.R`) on the kit's grip, as before, so the clips that move the arm (Reload,
Equip, Unequip, Swing, the repair) still carry it. While the clip leaves the hands to the pose (standing, walking,
running, aiming, firing) `WeaponHandsIK` takes the arms over, blended by `influence` at 14 per second, and is
switched off (`active`) once the blend reaches 0, since at influence 0 it still overrode the arms in the drawn pose:

1. A two-handed gun's hold turns the chest (`stance_turn_deg`, 20-30 degrees) so the left shoulder comes forward, a
   shooter's stance: the Soldier's arm is 0.66 m, and without it the fore-end was 0.70-0.81 m from his left shoulder,
   so the left hand stopped short of it, inside the stock (#460).
2. The weapon's world pose comes from the aim: the grip sits `grip_offset` from the right shoulder joint (right,
   up, forward is negative), the muzzle along the aim, up stays up. The stock's butt, `butt`, lands against the shoulder.
3. The weapon's grip (`HandGrip.hold`, the kit's for a model with none) turns that pose into the right hand's
   pose, and a two-bone IK (law of cosines, the elbow out and down) reaches it.
4. The left arm reaches the weapon's grip (`HandGrip.left_hand`: the hand bone's place and turn on the fore-end,
   solved from the model's `Support` socket), taken from where the weapon is after the right arm, not from its target,
   so both hands hold the same weapon; a hold with no grip reaches `support`. All of it is pure geometry on the
   clip's pose: no clock, no randomness.
5. Firing kicks the weapon back 5 cm and up 4 degrees, dying away at 16 per second.

**The aim.** At the hip the barrel is along the body (the body faces the movement; the camera's pitch still lifts
it). While the aim is held (the button, or a shot within the hold: [hip fire](../research/hip-fire.md)) it follows the
camera's yaw and pitch and turns in a little (at most 5 degrees) to cross the crosshair's ray 12 m ahead of the camera:
the camera is over the shoulder, the muzzle is not. The pose never flips: the pose weight
(`PlayerAnimation.aim_weight()`, eased at the aim's speed) blends the yaw (the body's heading to the view) and the
turn toward the ray (`converge`, 0 to 1), so the weapon eases in and out as the aim does. The camera zooms for the
aim button only; a shot from the hip raises the weapon and does not zoom (#464). A hip shot also waits for
the body: it leaves when the body faces the view within 10 degrees, a press before that is kept for 0.6 s and a held
trigger waits as long as it takes ([turn first, then shoot](../research/hip-fire.md), #477). The shot itself is the
`AimResolver`'s, from the muzzle to what the camera ray is on.

## Per weapon

| Weapon | Grip from the shoulder joint (m) | Support (model units) | Notes |
| --- | --- | --- | --- |
| Lever rifle | right 0, down 0.09, forward 0.365 | -0.36, -0.03 (the fore-end's rear) | stock at the shoulder, left hand under the barrel; chest turned 20 degrees |
| Double shotgun | right 0, down 0.09, forward 0.41 | -0.36, -0.03 | the same, the stock a little longer; chest turned 30 degrees |
| Tommy gun | right 0, down 0.09, forward 0.39 | -0.37, -0.045 (the foregrip) | stock at the shoulder, left hand on the foregrip; chest turned 30 degrees |
| Revolver, flare gun | right 0.10, down 0.05, forward 0.42 | none | one hand: the right arm out toward the aim, the left stays with the clip |
| Baseball bat, crowbar, fire axe | the kit's grip, `shouldered = false` | none | one hand, as the Swing clip moves it; two hands on the grip is open work |

The grip moved forward with the bigger stocks of #460 (by the butt's growth), so the stock stays at the shoulder, and
in by 5 cm, toward the chest.
`support` is the model's `Support` socket (the left hand's grip on it is the weapon's `HandGrip.left_hand`, solved
from that socket: [Grips](animation.md#grips)); the support sits at the fore-end's rear, where the Soldier's short arm
reaches with the stock at his shoulder.

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

Each weapon id of the catalogue has **its own hold file**, `game/gameplay/player/holds/<id>.tres` (class, model, size,
grip), so no two weapons share a model: the crowbar is not the bat, the Tommy gun is not the lever rifle.
`WeaponHoldMap` (`game/gameplay/player/weapon_hold_map.gd`) gives the clip class of each id (rifle Rifle, shotgun
Shotgun, SMG Rifle, revolver and flare gun Pistol, every melee weapon Melee); `PlayerAnimation.equip(id)`
takes the class's clips and the id's own hold (`WeaponHoldMap.hold_for`). A hold whose `scene` is not in
`assets/weapons/` yet
(`WeaponHold.has_model`) leaves the hand empty, never another weapon's model: `WeaponHoldMap.no_model()` lists those
(none now). `holds/melee.tres` stays as the class-level hold for a weapon with no file of its own (the bat and the axe
have `holds/baseball_bat.tres` and `holds/fire_axe.tres` since they got ids, #461; the axe uses the melee class's grip
as the bat does, a bad grip is the hand-placement task's, #460). `WeaponEquipSync`
(`game/gameplay/night/weapon_equip_sync.gd`) reads the `weapon` of every player in each frame the server sends and
calls `equip` on that player's body when it changes: the local player and the others take the same line, and a player
who joins late shows the weapon of his first frame. The test is `game/tests/night/test_weapon_equip.gd` (each id taken
in hand through the real combat action, for the local player and a second one, by a swap, and no two ids sharing a
model).

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
