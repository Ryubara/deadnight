class_name WeaponClassTargets
extends Resource
## What one class of weapon is meant to do (#972), written as numbers a test holds every weapon of
## the class to. One file per class in `classes/<key>.tres`; the table with the reasons is in
## docs/design/weapons.md ("The audit"). A weapon that leaves its class's band is too strong (under
## the lowest) or too weak (over the highest) for the class: retune the weapon, or move it to the
## class it really is, never widen a band to fit it without the reason on the design page.
##
## Measured through the real damage path (`WeaponAudit`): a walker of the round on the lot, the
## weapon in the shooter's hands at the real eye height, the fitted zones, the rules' health. Rounds
## 1, 5 and 10 are the weapon as shipped; rounds 15 and 20 are the weapon re-cut once at the bench
## (the health curve outgrows a shipped weapon by design: the re-cut is what the late rounds ask
## for).

## The rounds every band is written for, and whether the weapon is re-cut at it.
const ROUNDS: Array[int] = [1, 5, 10, 15, 20]
const RECUT_FROM := 15
## "No upper limit" in a band: a class that is allowed to be as weak as it likes at a round.
const OPEN := 999

@export var weapon_class: WeaponClass.Id = WeaponClass.Id.PISTOL
## What the class is for, in a line: the reason for its numbers.
@export_multiline var job: String = ""

@export_group("Time to kill a walker")
## Trigger pulls that kill a walker with body hits at each round of `ROUNDS`, as (lowest, highest)
## pairs: 10 numbers. Under the lowest is too strong, over the highest too weak.
@export var body_pulls: PackedInt32Array = PackedInt32Array()
## Seconds from the first pull to the kill (reloads included), the same pairs: 10 numbers.
@export var body_seconds: PackedFloat32Array = PackedFloat32Array()

@export_group("Zones")
## The head's multiplier and the limb's, (lowest, highest).
@export var head_multiplier: Vector2 = Vector2(1.0, 3.0)
@export var limb_multiplier: Vector2 = Vector2(0.5, 1.0)

@export_group("Penetration")
## Extra bodies a shot passes (`WeaponDef.penetration`; a melee weapon: the targets of one blow less
## one), (lowest, highest).
@export var bodies: Vector2i = Vector2i(0, 0)
## The share of its damage a shot keeps at each body it passes (`penetration_falloff`),
## (lowest, highest); not read for a class that passes no body.
@export var kept: Vector2 = Vector2(0.5, 0.8)

@export_group("Rounds")
## The magazine's size (a melee weapon has none), (lowest, highest).
@export var magazine: Vector2i = Vector2i(0, 0)


## The targets of a class, or null when it has none.
static func of(class_id: WeaponClass.Id) -> WeaponClassTargets:
	var path := "res://gameplay/weapons/classes/%s.tres" % WeaponClass.key(class_id)
	return load(path) as WeaponClassTargets if ResourceLoader.exists(path) else null


## The targets of the class of `def`.
static func for_weapon(def: WeaponDef) -> WeaponClassTargets:
	return of(def.weapon_class)


## The (lowest, highest) pulls of the band at `round_number` (one of `ROUNDS`).
func pulls_band(round_number: int) -> Vector2i:
	var at := ROUNDS.find(round_number) * 2
	return Vector2i(body_pulls[at], body_pulls[at + 1])


## The (lowest, highest) seconds of the band at `round_number`.
func seconds_band(round_number: int) -> Vector2:
	var at := ROUNDS.find(round_number) * 2
	return Vector2(body_seconds[at], body_seconds[at + 1])


## Whether the bands are written whole: ten pairs of numbers, each pair in order.
func is_complete() -> bool:
	if body_pulls.size() != ROUNDS.size() * 2 or body_seconds.size() != ROUNDS.size() * 2:
		return false
	for i in ROUNDS.size():
		if (
			body_pulls[i * 2] > body_pulls[i * 2 + 1]
			or body_seconds[i * 2] > body_seconds[i * 2 + 1]
		):
			return false
	return true
