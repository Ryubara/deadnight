class_name GrenadeDef
extends Resource
## One kind of grenade as data: how it is thrown, how it flies and bounces, and what the blast does.
## Every number lives in a `.tres` of this script (`defs/`), none in code; the server and the client
## load the same file, so a prediction and the authoritative answer use the same numbers.

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Fuse")
## Seconds from the pin to the blast. Cooking spends it while the grenade is still in the hand;
## held to the end, it goes off in the hand.
@export_range(0.0, 100.0, 0.05, "or_greater", "suffix:s") var fuse: float = 3.0
## A throw released with less fuse than this left still flies, but never with less, so the
## grenade is never already spent in the hand that let it go.
@export_range(0.0, 2.0, 0.01, "or_greater", "suffix:s") var min_fuse_left: float = 0.05

@export_group("Throw")
## Overarm: the far throw. Speed in m/s along the aim, lifted by `over_lift_deg`.
@export_range(0.0, 60.0, 0.5, "or_greater", "suffix:m/s") var over_speed: float = 15.0
@export_range(0.0, 90.0, 0.5, "or_greater", "suffix:deg") var over_lift_deg: float = 8.0
## Underarm: the short toss on its own input; low, slow, and it rolls.
@export_range(0.0, 60.0, 0.5, "or_greater", "suffix:m/s") var under_speed: float = 7.0
@export_range(0.0, 90.0, 0.5, "or_greater", "suffix:deg") var under_lift_deg: float = 22.0
## How much of the thrower's own velocity the grenade keeps.
@export_range(0.0, 1.0) var inherit_velocity: float = 0.5

@export_group("Authority")
## The server decides where the grenade leaves from: the player's feet plus `hand_height`, and a
## hand the client reports is kept within `hand_reach` of that (an arm's length and the lag).
@export_range(0.0, 10.0, 0.05, "or_greater", "suffix:m") var hand_height: float = 1.45
@export_range(0.0, 10.0, 0.05, "or_greater", "suffix:m") var hand_reach: float = 1.0
## The most of the thrower's own speed the server believes, m/s: the sprint, with a little slack.
@export_range(0.0, 20.0, 0.1, "or_greater", "suffix:m/s") var max_carrier_speed: float = 7.5
## Where a grenade a downed player was holding starts, above the feet.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:m") var drop_height: float = 0.3

@export_group("Flight")
## Downward acceleration, m/s^2.
@export_range(0.0, 100.0, 0.5, "or_greater", "suffix:m/s^2") var gravity: float = 16.0
@export_range(0.0, 1.0, 0.01, "or_greater", "suffix:m") var radius: float = 0.09
## Speed kept along the surface normal after a bounce, off a floor and off a wall.
@export_range(0.0, 1.0) var floor_restitution: float = 0.42
@export_range(0.0, 1.0) var wall_restitution: float = 0.5
## Speed lost along the surface at each bounce.
@export_range(0.0, 1.0) var bounce_friction: float = 0.2
## A bounce slower than this (along the normal, m/s) on a floor lands the grenade: it rolls.
@export_range(0.0, 10.0, 0.1, "or_greater", "suffix:m/s") var rest_speed: float = 1.4
## Rolling: speed lost per second, and the speed under which it stops dead.
@export_range(0.0, 20.0, 0.1, "or_greater", "suffix:m/s^2") var roll_deceleration: float = 3.5
@export_range(0.0, 5.0, 0.05, "or_greater", "suffix:m/s") var stop_speed: float = 0.2
## How far below it the floor still counts as under it while rolling (a ledge ends the roll).
@export_range(0.0, 1.0, 0.01, "or_greater", "suffix:m") var ground_reach: float = 0.12

@export_group("Blast")
## Full damage inside the core radius, sliding to nothing at the radius.
@export_range(0.0, 30.0, 0.1, "or_greater", "suffix:m") var core_radius: float = 2.0
@export_range(0.0, 40.0, 0.1, "or_greater", "suffix:m") var blast_radius: float = 8.0
## Damage to a fully exposed zombie at the centre. Direct impact is not a kill by default: a
## round-5 zombie (132) dies inside about 2.7 m, a round-10 one (213) never to one grenade.
@export_range(0.0, 500.0, 1.0, "or_greater") var damage: float = 150.0
## How high above the grenade the blast "stands", so a grenade lying on the floor does not
## shadow itself with it.
@export_range(0.0, 5.0, 0.05, "or_greater", "suffix:m") var blast_lift: float = 0.25
## A part is shielded when something solid stands this much nearer than the part.
@export_range(0.0, 1.0, 0.01, "or_greater", "suffix:m") var cover_slack: float = 0.12
## Horizontal and upward speed a body at the centre is thrown with; falls off like the damage.
@export_range(0.0, 40.0, 0.5, "or_greater", "suffix:m/s") var knockback_speed: float = 7.0
@export_range(0.0, 20.0, 0.5, "or_greater", "suffix:m/s") var knockback_lift: float = 3.0
## Seconds a survivor at the centre is stunned; falls off like the damage.
@export_range(0.0, 10.0, 0.1, "or_greater", "suffix:s") var stun_seconds: float = 1.6

@export_group("Players")
## What a blast does to the player who threw it (reduced but real); others in co-op take nothing.
@export_range(0.0, 1.0) var self_damage_fraction: float = 0.4
## Where on a player the blast aims, above their feet.
@export_range(0.0, 10.0, 0.05, "or_greater", "suffix:m") var player_chest: float = 1.0


## The launch velocity of a throw along `aim` (any length), lifted for overarm or underarm and
## carrying part of the thrower's velocity. A pure function: the client's prediction and the
## server's throw give the same vector.
func launch_velocity(aim: Vector3, underarm: bool, carrier_velocity: Vector3) -> Vector3:
	var dir := aim.normalized()
	var axis := dir.cross(Vector3.UP)
	axis = axis.normalized() if axis.length_squared() > 1e-8 else Vector3.RIGHT
	var lift := deg_to_rad(under_lift_deg if underarm else over_lift_deg)
	var speed := under_speed if underarm else over_speed
	return dir.rotated(axis, lift) * speed + carrier_velocity * inherit_velocity


## 1.0 inside the core radius, sliding linearly to 0.0 at the blast radius, 0 beyond, and 0 for a
## distance that is not a finite number (a blast that is nowhere hurts nothing).
func falloff(distance: float) -> float:
	if not is_finite(distance):
		return 0.0
	if distance <= core_radius:
		return 1.0
	if distance >= blast_radius:
		return 0.0
	return 1.0 - (distance - core_radius) / maxf(blast_radius - core_radius, 0.001)
