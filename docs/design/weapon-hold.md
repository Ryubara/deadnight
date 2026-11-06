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
running, aiming, firing) `WeaponHandsIK` takes the arms over, blended by its `weight` at 14 per second (the blend
is done bone by bone inside the modifier: the engine's `influence` blended only the chest and the hands, and left
the arms in the gun pose at any value), and is switched off (`active`) once the weight reaches 0, where the arms are
the clip's and switching off moves nothing:

1. A two-handed gun's hold turns the chest (`stance_turn_deg`, 20-30 degrees) so the left shoulder comes forward, a
   shooter's stance: the Soldier's arm (upper arm and forearm) is 0.59 m since #978 (0.66 m with the kit's forearm,
   #460), and without the turn the fore-end was 0.70-0.81 m from his left shoulder, so the left hand stopped short of
   it, inside the stock. Its elbows bend out further than a one-handed gun's (`ELBOW_OUT_TWO_HANDED` 1.0 of the
   shoulder width against `ELBOW_OUT` 0.45): with the shorter forearm the shouldered hold folded the right forearm
   into the jacket. Ten degrees more stance reached the fore-ends too, but turned the seat's armband 2-3 cm deeper into
   the chest when firing the long guns, so the stances stayed and step 4's slide does the rest.
2. The weapon's world pose comes from the aim: the grip sits `grip_offset` from the right shoulder joint (right,
   up, forward is negative), the muzzle along the aim, up stays up. The stock's butt, `butt`, lands against the shoulder.
   A two-handed gun's grip sits 5 cm out to the right of the joint (the pump 8 cm, #987): straight ahead of the joint
   a shot's kick put the right forearm 30-53 mm into the chest, and further-out elbows alone (1.6 of the shoulder width)
   still left 43-50 mm.
3. The weapon's grip (`HandGrip.hold`, the kit's for a model with none) turns that pose into the right hand's
   pose, and a two-bone IK (law of cosines, the elbow out and down) reaches it.
4. The left arm reaches the weapon's grip (`HandGrip.left_hand`: the hand bone's place and turn on the fore-end,
   solved from the model's `Support` socket), taken from where the weapon is after the right arm, not from its target,
   so both hands hold the same weapon; a hold with no grip reaches `support`. All of it is pure geometry on the
   clip's pose: no clock, no randomness. Where the fore-end is still out of the left arm's reach (the view far down:
   the chest bends over and the gun drops away from the left shoulder), the weapon slides back along its barrel until
   the left hand reaches it (`WeaponHandsIK.PULL_*`, at most 12 cm, `pulled()`; `tests/art/measure_arms.tscn` prints
   it per weapon and view pitch). Before #978 the hand stopped short there instead, off the fore-end by up to 13 mm at
   40 degrees down.
5. Firing kicks the weapon back 5 cm and up 4 degrees, dying away at 16 per second.

**At the hip** the barrel is along the body (the body faces the movement; the camera's pitch still lifts it), turned
in to the crosshair's point (12 m ahead of the camera) the way the aim does, while the view is within 30 degrees of the
body's heading; the share fades out to nothing at 90 degrees (`WeaponHandsIK.hip_share()`, continuous, so a gun is
never swung round by a view behind the body: a person who runs one way and looks the other keeps the barrel forward).
Running pulls the camera back, so the turn-in is up to 8 degrees there. (Before #285 the hip barrel ran parallel to the
body and crossed the crosshair's ray nowhere; `game/tests/captures/hip_aim_targets.tscn` shows the barrel line
against a close and a far target.)

**The aim.** While the aim is held (the button, or a shot within the hold: [hip fire](../research/hip-fire.md)) it
follows the camera's yaw and pitch and turns in a little (at most 5 degrees) to cross the crosshair's ray 12 m ahead
of the camera: the camera is over the shoulder, the muzzle is not. The pose never flips: the pose weight
(`PlayerAnimation.aim_weight()`, eased at the aim's speed) blends the yaw (the body's heading to the view) and the
turn toward the ray (`converge`, 0 to 1), so the weapon eases in and out as the aim does. The camera zooms for the aim
button only; a shot from the hip raises the weapon and does not zoom (#464). A hip shot also waits for the body: it
leaves when the body faces the view within 10 degrees, a press before that is kept for 0.6 s and a held trigger waits
as long as it takes ([turn first, then shoot](../research/hip-fire.md), #477). The shot itself is the `AimResolver`'s,
from the muzzle to what the camera ray is on.

## The grenade in the hand

The cooked grenade is held like a weapon: `holds/grenade.tres` (`weapon_class` Grenade) names the model
(`assets/weapons/grenade/grenade.glb`), the size (2.2 times the rule's length: a real grenade vanishes in the chibi's
fist at the rule's size), the muzzle and butt points of the model, and `grips/grenade.tres` is the fist solved for it
(`tools/art/solve_grips.gd`, rerun after a size change). `PlayerAnimation` builds the node `Grenade` on the weapon mount
from them; it shows with the cook clip's `grenade_visible` event and goes with `release`. The capture
(`weapon_hold_sheet.tscn -- --only=grenade`) adds a close view of the hand and one from the front.

## The House Pistol

`house_pistol` (#898, the start weapon) is held one-handed in the `Pistol` class at the service pistol's size
(`holds/house_pistol.tres`: `model_scale` 1.95, `size_factor` 1.75; its model is the grip, trigger and magazine of the
dual pistols' with its own slide and frame, so the hand fits the same way). Its grip is solved in `grips/house_pistol.tres`
(`solve_grips.gd --only house_pistol`: trigger finger 1.0 mm, wrap 0.1 to 1.0 mm); `test_hand_grips.gd`,
`test_menu_grips.gd` and `test_weapon_hold.gd` hold it. Its reload (`reload/house_pistol.tres`, 1.5 s) is the magazine
kind: the left hand goes to the grip's foot, the magazine drops and goes to the belt, a new one is brought and seated, the
hand racks the slide's rear. The sprint carry is the class's (`Sprint_Pistol`).

## The dual pistols

`dual_pistols` is the first weapon held in both hands (#789): a pistol in each, the shots alternating. Its hold file
(`holds/dual_pistols.tres`, class `Dual`, `dual = true`) is the revolver's model twice, the left one **the right one
mirrored** (the model of #797 replaces the revolver when it lands). It is built the way the rest of the hold is, by the
hands' IK, plus six arm clips from Blender ([Animation](animation.md#dual-pistols)).

- **The rig is an exact mirror**: every left bone's rest rotation is its right one's with `y` and `z` negated (measured
  in Godot on the Soldier and in Blender: the left hand ended 0.0 m from the right's reflection). So nothing is solved
  for the left hand: `HeldWeapon` puts a second copy of the model on `Index1.L` at the right one's place with `x` turned
  about (`WeaponHandsIK.MIRROR`: a node whose basis turns the other way draws the model in a mirror), the left fingers
  are the grip's right-hand ones with `y` and `z` negated (`HandGrip.mirrored()`, `HandGripPose.left_mirrors`), and the
  left arm reaches the mirror of the right arm's pose (`WeaponHandsIK._reach_offhand`). One builder serves the night,
  other players' bodies and the menu's soldier, so all three show both guns.
- **Where the guns are**: `grip_offset` is the right gun's, from the right shoulder joint; the left gun's is its mirror
  from the left shoulder (0.28 m out, 0.05 down, 0.42 forward), so the pair is about 0.7 m apart. Each barrel turns in
  to meet the crosshair's point 12 m ahead from where it is, so both cross the ray there (the rule of one gun, per
  gun). The shoulder camera is over the right shoulder: the right gun shows beside the head and the left hand on the
  other side, with its gun hidden by the head (the head is as wide as the arms' span from behind); the left gun is plain
  from the side and the front and in other players' views.
- **Recoil is per gun**: the shot's `hand` (0 right, 1 left; the server numbers it, `WeaponState.hand`) kicks that gun
  back and up (`recoil`, `recoil_left`) and flashes that gun's muzzle (`PlayerAnimation.muzzle_point(hand)`), for every
  player alike.
- **Reload**: one reload for both (`reload/dual_pistols.tres`): both pistols come in toward the chest, turn up and both
  cylinders open (the part moves on the second model too, `ReloadView.offpart`), a pause, close, and back to the aim.
  No hand leaves a gun for the belt, so the reload's `left` stays 0 and the fingers stay closed.
- **Around the aim**: equip, unequip, the sprint and the quick melee are clips (`Aim_Dual`, `Fire_Dual`, `Equip_Dual`,
  `Unequip_Dual`, `Strike_Dual`, `Sprint_Dual`): the Pistol clips with the left arm the right's mirrored (the sprint's
  left arm is the right's half a stride on, so the pistols pump against each other). Down, a revive and the repair hide
  both guns with the weapon.
- **Tests**: `test_dual_pistols_hold.gd` (both grips on their targets within 3 cm, both hands within 1 cm of their grip,
  both barrels within 1.5 degrees of the crosshair's point, the pair level and apart, the left fingers the right's
  mirrored, no part of either hand more than 2 mm into its gun and every contact within 5 mm standing, aiming, firing
  from either hand, running and sprinting) and `test_dual_pistols_view.gd` (the flash on the gun that fired, the kick on
  that gun, another player's body).

## Per weapon

| Weapon | Grip from the shoulder joint (m) | Support (model units) | Notes |
| --- | --- | --- | --- |
| Lever rifle | right 0, down 0.09, forward 0.365 | -0.36, -0.03 (the fore-end's rear) | stock at the shoulder, left hand under the barrel; chest turned 20 degrees |
| Double shotgun | right 0, down 0.09, forward 0.41 | -0.36, -0.03 | the same, the stock a little longer; chest turned 30 degrees |
| Tommy gun | right 0, down 0.09, forward 0.39 | -0.37, -0.045 (the foregrip) | stock at the shoulder, left hand on the foregrip; chest turned 30 degrees |
| Revolver, flare gun | right 0.10, down 0.05, forward 0.42 | none | one hand: the right arm out toward the aim, the left stays with the clip |
| Dual pistols | right 0.28, down 0.05, forward 0.42 (the left gun mirrored, from the left shoulder) | none | a pistol in each hand ([above](#the-dual-pistols)) |
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
Shotgun, SMG Rifle, the PPSh, MP5, M4A1, M249 and .50 calibre Rifle, the 870 pump Shotgun, revolver and flare gun
Pistol, the dual pistols Dual, every melee weapon Melee); `PlayerAnimation.equip(id)`
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

**The six firearms of #793** have a hold each (`holds/{ppsh,mp5,m4a1,m249,fifty_cal,pump_870}.tres`), from the model batches'
numbers ([the holds of the nine](../research/weapon-models.md)): `model_scale` 1.3 (the .50's 1.21 with its size factor
0.93, the one exception of `test_weapon_hold.gd`), `real_length` the drawn length (the M249's stock is shorter than the
real one so its butt stays at the shoulder), the support just ahead of the magazine, the box or the pump so the left hand
clears it. The .50 is as long as the Soldier is tall (1.40 m in the game). A weapon whose model has not landed holds
another's (`STAND_INS` in `test_weapon_equip.gd` lists them, and only they may share a model).

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
of the crosshair's point 12 m ahead; pitched with the camera;
hands back to the clip during Reload; the bat in the hand at the rule's size; at the hip and running the barrel
within 1 degree of the crosshair's point and within 8 degrees of the body, and a view behind the body leaving it forward;
the grenade held by its hold file (model, size, in the hand while cooked). The capture sheet
(`game/tests/captures/weapon_hold_sheet.tscn`: side, the shoulder camera, from behind, from above, in idle, run, aim
and fire) is in the pull request.
