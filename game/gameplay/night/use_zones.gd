class_name UseZones
extends RefCounted
## Where each interactable of a map can be used from: its use zone, the floor a body stands on
## from which the server would offer it (`UseOffers` and `NightServer.use_target` ask the same
## tests: the reach on the flat, the floor, the line from the hand, the side it is used from).
## Two zones never share ground on a shipped map, with `MIN_GAP` between them (#908): holding use
## at a window bought the wall weapon beside it, because the window's reach and the weapon's
## overlapped and the press went to the weapon. `test_use_zone_spacing.gd` walks both maps.

## Metres of floor between two use zones on a map (the map review's rule): a step off one zone
## does not land in the next.
const MIN_GAP := 0.5

var _world: NightWorld
var _tuning: NightTuning
var _sight: UseSight
var _things: Array[Dictionary] = []


func _init(world: NightWorld, tuning: NightTuning, sight: UseSight = null) -> void:
	_world = world
	_tuning = tuning
	_sight = sight


## Every interactable that stands still: `{name, kind, id, floor, reach}` (`floor`: the ground the
## zone is measured on, `reach`: its radius on the flat). The shop spots (a wall weapon and its
## rounds are one spot), the doors, the breaches, the breaker posts and the fuel cans.
func things() -> Array[Dictionary]:
	if not _things.is_empty():
		return _things
	var out: Array[Dictionary] = []
	var index := 0
	for spot in _world.shop_spots():
		var at: Vector3 = spot["position"]
		var named := String(spot["shop_id"]) if spot["shop_id"] != &"" else String(spot["kind"])
		out.append(
			_thing(
				"%s (%.1f, %.1f, %.1f)" % [named, at.x, at.y, at.z],
				&"spot",
				StringName(str(index)),
				at,
				_tuning.spot_reach
			)
		)
		index += 1
	for door_id in _world.door_ids():
		var stands := _world.door_stands(door_id)
		var floor_at: Vector3 = (
			stands[0]
			if not stands.is_empty()
			else _world.door_points(door_id)[0] - Vector3(0.0, UseOffers.DOOR_MIDDLE, 0.0)
		)
		out.append(_thing("door %s" % door_id, &"door", door_id, floor_at, _tuning.use_reach))
	for id in _world.barricade_ids():
		var barricade := _world.barricade(id)
		out.append(_thing("breach %s" % id, &"breach", id, barricade.centre(), _tuning.use_reach))
	for circuit in _world.switches.circuit_ids():
		out.append(
			_thing(
				"post %s" % circuit,
				&"post",
				circuit,
				_world.switches.standing_point(circuit),
				_tuning.use_reach
			)
		)
	for spot in _world.fuel.ids():
		out.append(
			_thing(
				"fuel %s" % spot,
				&"fuel",
				spot,
				_world.fuel.standing_point(spot),
				_tuning.fuel_reach
			)
		)
	_things = out
	return out


func _thing(
	name: String, kind: StringName, id: StringName, floor_at: Vector3, reach: float
) -> Dictionary:
	return {"name": name, "kind": kind, "id": id, "floor": floor_at, "reach": reach}


## The things whose zone holds `here`, each reach grown by `grow` metres (half the gap, to keep
## `MIN_GAP` between two zones).
func zones_at(here: Vector3, grow: float = 0.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var spots := _world.shop_spots()
	for thing in things():
		if _holds(thing, spots, here, grow):
			out.append(thing)
	return out


func _holds(thing: Dictionary, spots: Array[Dictionary], here: Vector3, grow: float) -> bool:
	var id: StringName = thing["id"]
	match thing["kind"]:
		&"spot":
			return spot_reaches(
				_world, _tuning, _sight, spots[int(String(id))]["position"], here, grow
			)
		&"door":
			return door_reaches(_world, _tuning, _sight, id, here, grow)
		&"breach":
			return breach_reaches(_world, _tuning, _sight, _world.barricade(id), here, grow)
		&"post":
			return post_reaches(_tuning, _sight, _world.switches.post(id), here, grow)
		&"fuel":
			return fuel_reaches(_world, _tuning, _sight, id, here, grow)
	return false


# --- The tests the server asks (one source for the offers and for the sweep) ---------------------


## Whether a press at `here` reaches the shop spot standing at `at`.
static func spot_reaches(
	world: NightWorld,
	tuning: NightTuning,
	sight: UseSight,
	at: Vector3,
	here: Vector3,
	grow: float = 0.0
) -> bool:
	return (
		world.reach_distance(here, at) <= tuning.spot_reach + grow
		and (sight == null or sight.clear(here, at))
	)


## Whether a press at `here` reaches a slab of the door (from a side it is bought from).
static func door_reaches(
	world: NightWorld,
	tuning: NightTuning,
	sight: UseSight,
	door_id: StringName,
	here: Vector3,
	grow: float = 0.0
) -> bool:
	var stands := world.door_stands(door_id)
	for point in world.door_points(door_id):
		# The slab's middle is half a door above the floor it stands on.
		if (
			flat(here, point) <= tuning.use_reach + grow
			and world.on_level(here, point - Vector3(0.0, UseOffers.DOOR_MIDDLE, 0.0))
			and (sight == null or sight.clear_door(here, point, stands))
		):
			return true
	return false


## Whether a press at `here` reaches the breach to put boards back (from the field's side).
static func breach_reaches(
	world: NightWorld,
	tuning: NightTuning,
	sight: UseSight,
	barricade: Barricade,
	here: Vector3,
	grow: float = 0.0
) -> bool:
	return (
		barricade.depth_of(here) > 0.0
		and flat(here, barricade.centre()) <= tuning.use_reach + grow
		and world.on_level(here, barricade.centre())
		and (sight == null or sight.clear(here, barricade.centre(), UseSight.MOUNT_SKIN))
	)


## Whether a press at `here` reaches the breaker post (from the side its front faces).
static func post_reaches(
	tuning: NightTuning, sight: UseSight, post: CircuitSwitch, here: Vector3, grow: float = 0.0
) -> bool:
	return (
		flat(here, post.global_position) <= tuning.use_reach + grow
		and (sight == null or sight.clear_mounted(here, post.global_position, post.global_basis.z))
	)


## Whether a press at `here` reaches the fuel can stand `spot`.
static func fuel_reaches(
	world: NightWorld,
	tuning: NightTuning,
	sight: UseSight,
	spot: StringName,
	here: Vector3,
	grow: float = 0.0
) -> bool:
	var at := world.fuel.standing_point(spot)
	return flat(here, at) <= tuning.fuel_reach + grow and (sight == null or sight.clear(here, at))


static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
