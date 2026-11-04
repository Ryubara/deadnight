class_name ExtractionChains
extends RefCounted
## The chains the extraction proposal measures (`docs/design/extraction.md`, #1056), as data for
## `extraction_probe.gd`. Nothing here is the game: no step exists in a shipped scene. A chain is a
## list of stages; the steps of a stage may be done in any order and at once, and a stage opens when
## the one before it is done and the kill tally has reached the stage's `tier` (a share of the
## quota). The last stage's step is the extraction itself.
##
## Step fields: `id`; `kind` (below); `at`, or `from` and `to` for a carry; `seconds` of work (a
## carry's `lift`, a stand's `seconds`); `door`, the shop door it stands behind; `surge`, the dead a
## step's noise calls, as a share of the round's own count (so it scales with the round, the players
## and the zombie count modifier), when the step starts; `circuit`, `need`, `windows`, `gate` by
## kind.

## Stand at `at` with the trigger up for `seconds`. The work stops while a dead is on the worker.
const WORK := &"work"
## Lift at `from`, walk to `to` at a run with both hands full (no shot, no sprint), set it down.
const CARRY := &"carry"
## The team holds the ground round `at` for `seconds`. The guns stay up.
const STAND := &"stand"
## Buy fuel cans from the stand at `at` until the tank holds `need` of its capacity.
const TANK := &"tank"
## Throw the breaker of `circuit` on after `seconds` of work at the post.
const BREAKER := &"breaker"
## Every generator circuit on and the tank never dry for `seconds`; a dry tank starts it over.
const LOAD := &"load"
## Every window of `windows` holds all its boards at once for `seconds`.
const SEAL := &"seal"

const LOT_FUEL_YARD := Vector3(34.3, 0.0, 15.9)
const LOT_GENERATOR := Vector3(42.6, 0.0, 18.0)
const LOT_PROJECTOR := Vector3(0.0, 3.8, 27.0)
const LOT_PLAZA_WRECK := Vector3(-9.0, 0.0, 52.0)
const LOT_BACK_SIGN := Vector3(-47.0, 0.0, 33.5)
const LOT_POST_STAND := Vector3(8.5, 0.0, -6.0)
const LOT_POST_BOOTH := Vector3(5.6, 0.0, 20.0)
const LOT_POST_BACK := Vector3(-46.0, 0.0, -6.0)
const LOT_LZ := Vector3(0.0, 0.0, -24.0)

const SMALL_ALL := [&"start_1", &"start_4", &"side_2", &"side_breach", &"upper_a1", &"upper_a2"]
const SMALL_RADIO := Vector3(11.5, 3.4, 0.5)
const SMALL_BATTERY := Vector3(8.0, 0.0, 9.5)
const SMALL_SET := Vector3(0.8, 0.0, -3.2)
const SMALL_AERIAL := Vector3(3.5, 3.4, -5.2)
const SMALL_AERIAL_E := Vector3(12.5, 3.4, -1.2)
const SMALL_WALL := Vector3(9.5, 3.4, 3.2)
const SMALL_TERRACE := Vector3(8.0, 3.4, 9.5)


static func stages(map: StringName, chain: StringName) -> Array:
	match "%s/%s" % [map, chain]:
		"drive_in/v1":
			return _lot_v1()
		"small_indoor/v1":
			return _small_v1()
		"drive_in/v2":
			return _lot_v2()
		"small_indoor/v2":
			return _small_v2()
		"drive_in/v3":
			return _lot_v2()
		"small_indoor/v3":
			return _small_v3()
		"drive_in/v4":
			return _with_hold_call(_lot_v2())
		"small_indoor/v4":
			return _with_hold_call(_small_v3())
		_:
			return []


## The lot with nothing added: what it has today, used as it stands.
static func _lot_v1() -> Array:
	return [
		_stage(&"fuel", 0.0, [_tank(&"tank_full", LOT_FUEL_YARD, 1.0, &"door_yard")]),
		_stage(
			&"breakers",
			0.0,
			[
				_breaker(&"post_stand", LOT_POST_STAND, &"concession", 1.0),
				_breaker(&"post_booth", LOT_POST_BOOTH, &"booth", 1.0, &"door_booth"),
				_breaker(&"post_back", LOT_POST_BACK, &"back_lot", 1.0, &"door_back_lot"),
			]
		),
		_stage(&"projector", 0.0, [_work(&"projector", LOT_PROJECTOR, 20.0, &"door_booth")]),
		_stage(&"extract", 1.0, [_stand(&"lz", LOT_LZ, 60.0, 12.0)]),
	]


## The back rooms with nothing added: what they have today, used as they stand.
static func _small_v1() -> Array:
	return [
		_stage(&"links", 0.0, [_seal(&"seal", SMALL_ALL, 1.0, &"door_stairs_side")]),
		_stage(&"radio", 0.0, [_work(&"radio", SMALL_RADIO, 20.0, &"door_stairs_start")]),
		_stage(&"extract", 1.0, [_stand(&"lz", Vector3(5.0, 0.0, -2.0), 60.0, 6.0)]),
	]


## Light the LZ: the lot's chain, built on its generator, circuits, booth and doors. Distance, fuel
## and light: every door bought, three breakers across the lot, two loads carried with hands full.
static func _lot_v2() -> Array:
	return [
		_stage(
			&"restart",
			0.0,
			[
				_work(&"generator", LOT_GENERATOR, 20.0, &"door_yard", 0.25),
				_tank(&"tank_full", LOT_FUEL_YARD, 1.0, &"door_yard"),
			]
		),
		_stage(
			&"power",
			0.15,
			[
				_breaker(&"box_stand", LOT_POST_STAND, &"concession", 10.0, &"", 0.15),
				_breaker(&"box_booth", LOT_POST_BOOTH, &"booth", 10.0, &"door_booth", 0.15),
				_breaker(&"box_back", LOT_POST_BACK, &"back_lot", 10.0, &"door_back_lot", 0.15),
			]
		),
		_stage(&"load", 0.3, [_load(&"load_test", 45.0, 0.25)]),
		_stage(
			&"projector",
			0.45,
			[
				_carry(&"lamp", LOT_PLAZA_WRECK, LOT_PROJECTOR, 5.0, &"door_road", 0.25),
				_carry(&"reel", LOT_BACK_SIGN, LOT_PROJECTOR, 5.0, &"door_back_lot", 0.25),
			]
		),
		_stage(&"roll", 0.6, [_work(&"roll", LOT_PROJECTOR, 75.0, &"door_booth", 0.5)]),
		_stage(
			&"flares",
			0.8,
			[
				_work(&"flare_nw", Vector3(-6.0, 0.0, -31.0), 5.0, &"", 0.25),
				_work(&"flare_ne", Vector3(6.0, 0.0, -31.0), 5.0),
				_work(&"flare_sw", Vector3(-6.0, 0.0, -11.0), 5.0),
				_work(&"flare_se", Vector3(6.0, 0.0, -11.0), 5.0),
			]
		),
		_stage(&"extract", 1.0, [_stand(&"lz", LOT_LZ, 90.0, 12.0, 1.0)]),
	]


## Raise the roof: the back rooms' chain, built on the windows, the floors and the ring. Contact,
## not distance: every leg passes a window, and it ends outside on the terrace.
static func _small_v2() -> Array:
	var links: Array = [&"door_side", &"door_stairs_start", &"door_stairs_side"]
	var seal := _seal(&"seal", SMALL_ALL, 5.0, &"", 0.0)
	seal["doors"] = links
	var battery := _carry(&"battery", SMALL_BATTERY, SMALL_RADIO, 5.0, &"door_stairs_start", 0.25)
	var radio_set := _carry(&"set", SMALL_SET, SMALL_RADIO, 5.0, &"door_stairs_start", 0.25)
	battery["doors"] = links
	radio_set["doors"] = links
	var wall := _work(&"charges", SMALL_WALL, 24.0, &"door_stairs_start", 0.5)
	var roof := _stand(&"roof", SMALL_TERRACE, 90.0, 7.0, 1.0)
	roof["gate"] = SMALL_WALL
	return [
		_stage(&"seal", 0.0, [seal]),
		_stage(&"parts", 0.15, [battery, radio_set]),
		_stage(
			&"aerial",
			0.35,
			[
				_work(&"aerial_w", SMALL_AERIAL, 12.0, &"door_stairs_side", 0.15),
				_work(&"aerial_e", SMALL_AERIAL_E, 12.0, &"door_stairs_start", 0.15),
			]
		),
		_stage(&"call", 0.6, [_work(&"call", SMALL_RADIO, 75.0, &"door_stairs_start", 0.5)]),
		_stage(&"wall", 0.8, [wall]),
		_stage(&"extract", 1.0, [roof]),
	]


## `v2` with a seal that can be held while the dead are at the boards (at count x5 six windows at
## five boards never stood at once) and longer clocks to keep the floor.
static func _small_v3() -> Array:
	var stages := _small_v2()
	stages[0]["steps"][0]["boards"] = 3
	stages[3]["steps"][0]["seconds"] = 90.0
	stages[4]["steps"][0]["seconds"] = 30.0
	return stages


## The final chains: the call at the hold brings half a round's dead (a whole round's ended every
## small team's hold), one number for every team and both maps.
static func _with_hold_call(stages: Array) -> Array:
	stages[-1]["steps"][0]["surge"] = 0.5
	return stages


static func _stage(id: StringName, tier: float, steps: Array) -> Dictionary:
	return {"id": id, "tier": tier, "steps": steps}


static func _work(
	id: StringName, at: Vector3, seconds: float, door := &"", surge := 0.0
) -> Dictionary:
	return {"id": id, "kind": WORK, "at": at, "seconds": seconds, "door": door, "surge": surge}


static func _carry(
	id: StringName, from: Vector3, to: Vector3, lift: float, door := &"", surge := 0.0
) -> Dictionary:
	return {
		"id": id,
		"kind": CARRY,
		"from": from,
		"to": to,
		"lift": lift,
		"seconds": lift,
		"door": door,
		"surge": surge,
	}


static func _stand(
	id: StringName, at: Vector3, seconds: float, radius: float, surge := 0.0, door := &""
) -> Dictionary:
	return {
		"id": id,
		"kind": STAND,
		"at": at,
		"seconds": seconds,
		"radius": radius,
		"door": door,
		"surge": surge,
	}


static func _tank(id: StringName, at: Vector3, need: float, door := &"") -> Dictionary:
	return {"id": id, "kind": TANK, "at": at, "need": need, "seconds": 0.0, "door": door}


static func _breaker(
	id: StringName, at: Vector3, circuit: StringName, seconds: float, door := &"", surge := 0.0
) -> Dictionary:
	return {
		"id": id,
		"kind": BREAKER,
		"at": at,
		"circuit": circuit,
		"seconds": seconds,
		"door": door,
		"surge": surge,
	}


static func _load(id: StringName, seconds: float, surge := 0.0) -> Dictionary:
	return {"id": id, "kind": LOAD, "seconds": seconds, "door": &"", "surge": surge}


static func _seal(
	id: StringName, windows: Array, seconds: float, door := &"", surge := 0.0
) -> Dictionary:
	return {
		"id": id,
		"kind": SEAL,
		"windows": windows,
		"seconds": seconds,
		"door": door,
		"surge": surge,
	}
