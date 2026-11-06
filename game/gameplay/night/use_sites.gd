class_name UseSites
extends RefCounted
## Whether a body stands near anything the use button could offer: a shop spot, a door slab, a
## breach, a breaker post or a fuel can. `NightServer.use_target` is asked for every body on every
## tick (the card each one shows, and the guard that times a press), and almost every answer is
## `{}`: the body is in the open. This is the flat test that settles those without walking every
## door, breach and spot (their points, a dictionary and a node read each).
##
## It is a bound, never a verdict: a body that is near a site may still be offered nothing (a wall
## between, another floor, a door already open), so the offers decide. A body that is not near any
## cannot be offered anything, because every offer needs the flat distance to one of these points
## to be within its reach (`UseZones`). The points are read once, when first asked (the night has
## begun by then and the map is built); the reaches are the tuning's, given on each ask.

## Says every body is near (a test's oracle: the offers alone, as before this test existed).
var always_near := false

var _world: NightWorld
## The places a body must be within `NightTuning.spot_reach`, `use_reach` and `fuel_reach` of.
var _spots := PackedVector2Array()
var _hands := PackedVector2Array()
var _fuel := PackedVector2Array()
var _built := false


func _init(world: NightWorld) -> void:
	_world = world


## Whether any site is within its reach of `here` on the flat (the floor is not looked at: the
## offers do that).
func near(here: Vector3, tuning: NightTuning) -> bool:
	if always_near:
		return true
	if not _built:
		_build()
	var at := Vector2(here.x, here.z)
	return (
		_within(_spots, at, tuning.spot_reach)
		or _within(_hands, at, tuning.use_reach)
		or _within(_fuel, at, tuning.fuel_reach)
	)


static func _within(points: PackedVector2Array, at: Vector2, reach: float) -> bool:
	var limit := reach * reach
	for point in points:
		if point.distance_squared_to(at) <= limit:
			return true
	return false


func _build() -> void:
	_built = true
	for spot in _world.shop_spots():
		_spots.append(_flat(spot["position"]))
	for door_id in _world.door_ids():
		for point in _world.door_points(door_id):
			_hands.append(_flat(point))
	for id in _world.barricade_ids():
		_hands.append(_flat(_world.barricade(id).centre()))
	for circuit in _world.switches.circuit_ids():
		_hands.append(_flat(_world.switches.post(circuit).global_position))
	for spot in _world.fuel.ids():
		_fuel.append(_flat(_world.fuel.standing_point(spot)))


static func _flat(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)
