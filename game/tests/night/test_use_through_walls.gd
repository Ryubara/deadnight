# No prompt and no press through a wall, a floor or a shut door (#831). Walks every interactable of
# both maps: the wall weapons, lockers, doors, the crane, the perk machines (the soda fountain's
# tonic among them), the re-cut bench, the grenade rack, the breaker posts, the fuel cans, the
# breaches' boards and a downed teammate. Around each, on a polar grid of the floor within its
# reach, the points a wall (or a shut door) stands between and the thing are found with a ray of
# the test's own; there the server must show no prompt for it and the press must change nothing.
# The point in front of it must show the prompt, and so must every clear point close by.
extends GdUnitTestSuite

const LOT := "res://world/drive_in_greybox.tscn"
const SMALL := "res://world/smallmap/smallmap_greybox.tscn"

## The rings of the grid (metres from the thing) and the turn between its spokes.
const RING_FIRST := 0.5
const RING_STEP := 0.5
const SPOKE_DEGREES := 12.0
## Metres inside the reach a point must be, so a rounding of the flat distance never decides.
const MARGIN := 0.05
## A point at most this far from the thing, with a clear line, must show a prompt.
const NEAR := 1.6
## The ground under a point may differ from the thing's floor by this much.
const FLOOR_SLACK := 0.2
## Metres above the ground a body needs clear, the room round it (a body's radius and a little more:
## a point closer to a wall would have the body pushed off it) and the hand's height of the lines.
const HEADROOM := 1.7
const ROOM := 0.5
const SPOKES := 8
const HAND := UseSight.HAND
## The press is checked at this many points of each thing, and for this many ticks.
const PRESS_POINTS := 2
const PRESS_TICKS := 4
## Metres of ground beside a downed player a reviver may stand on.
const REVIVE_SPOKE := 0.8

## Breaches with no floor in reach on their own side, so no clear point shows the prompt:
## `upper_b1` opens over the side stair's well (#824; #900 moves it onto the floor). Each comes off
## the list the moment a clear point shows it.
const NO_FLOOR_IN_REACH: Array[String] = ["breach upper_b1"]

## The map review's ray audit (#833): pairs of a shop spot's hand point and a place within reach
## behind a wall, the nearest two for each spot that has any. The grid above is coarse (half a
## metre); these are the exact places the audit found, the worst at 1.2 m.
const AUDIT_LOT: Array[Vector3] = [
	Vector3(-8.2, 0.0, -5.6),
	Vector3(-8.4, 0.0, -3.3),
	Vector3(-8.2, 0.0, -5.6),
	Vector3(-8.9, 0.0, -3.3),
	Vector3(11.4, 0.0, 3.0),
	Vector3(9.2, 0.0, 2.8),
	Vector3(11.4, 0.0, 3.0),
	Vector3(9.2, 0.0, 2.3),
	Vector3(-4.0, 0.0, 20.4),
	Vector3(-4.2, 0.0, 22.7),
	Vector3(-4.0, 0.0, 20.4),
	Vector3(-4.7, 0.0, 22.7),
	Vector3(3.5, 0.0, 25.9),
	Vector3(5.3, 0.0, 27.7),
	Vector3(3.5, 0.0, 25.9),
	Vector3(1.3, 0.0, 27.7),
	Vector3(8.2, 0.0, 3.7),
	Vector3(6.5, 0.0, 5.0),
	Vector3(8.2, 0.0, 3.7),
	Vector3(6.0, 0.0, 5.0),
	Vector3(-14.0, 0.0, 11.0),
	Vector3(-15.2, 0.0, 9.8),
	Vector3(-14.0, 0.0, 11.0),
	Vector3(-15.2, 0.0, 9.3),
	Vector3(4.15, 0.0, 30.5),
	Vector3(5.45, 0.0, 29.3),
	Vector3(4.15, 0.0, 30.5),
	Vector3(5.45, 0.0, 28.8),
	Vector3(24.0, 0.0, 36.0),
	Vector3(22.8, 0.0, 37.3),
	Vector3(24.0, 0.0, 36.0),
	Vector3(22.8, 0.0, 37.8),
	Vector3(-20.0, 0.0, 36.0),
	Vector3(-21.2, 0.0, 37.3),
	Vector3(-20.0, 0.0, 36.0),
	Vector3(-21.2, 0.0, 37.8),
	Vector3(0.0, 0.0, 56.0),
	Vector3(-1.7, 0.0, 57.3),
	Vector3(0.0, 0.0, 56.0),
	Vector3(-2.2, 0.0, 57.3),
	Vector3(2.0, 0.0, -31.0),
	Vector3(3.8, 0.0, -28.7),
	Vector3(8.35, 0.0, -1.8),
	Vector3(10.15, 0.0, -2.0),
	Vector3(8.35, 0.0, -1.8),
	Vector3(10.15, 0.0, -2.5),
]
const AUDIT_SMALL: Array[Vector3] = [
	Vector3(1.35, 0.0, 11.0),
	Vector3(-0.85, 0.0, 10.8),
	Vector3(1.35, 0.0, 11.0),
	Vector3(-0.85, 0.0, 10.3),
	Vector3(14.65, 0.0, -6.0),
	Vector3(16.95, 0.0, -6.2),
	Vector3(14.65, 0.0, -6.0),
	Vector3(16.95, 0.0, -6.7),
	Vector3(1.3, 3.4, 2.3),
	Vector3(1.1, 3.4, 5.1),
	Vector3(1.3, 3.4, 2.3),
	Vector3(0.6, 3.4, 5.1),
	Vector3(5.0, 3.4, -6.5),
	Vector3(4.8, 3.4, -8.7),
	Vector3(5.0, 3.4, -6.5),
	Vector3(4.3, 3.4, -8.7),
	Vector3(-4.7, 3.4, -4.0),
	Vector3(-6.9, 3.4, -4.2),
	Vector3(-4.7, 3.4, -4.0),
	Vector3(-6.9, 3.4, -4.7),
	Vector3(10.5, 0.0, -5.9),
	Vector3(10.3, 0.0, -3.1),
	Vector3(10.5, 0.0, -5.9),
	Vector3(9.8, 0.0, -3.1),
	Vector3(8.0, 0.0, 13.15),
	Vector3(7.8, 0.0, 15.45),
	Vector3(8.0, 0.0, 13.15),
	Vector3(7.3, 0.0, 15.45),
	Vector3(5.0, 0.0, -1.65),
	Vector3(5.8, 0.0, 0.65),
	Vector3(5.0, 0.0, -1.65),
	Vector3(3.8, 0.53, 0.65),
	Vector3(6.0, 3.4, -1.6),
	Vector3(7.3, 2.87, 0.7),
	Vector3(6.0, 3.4, -1.6),
	Vector3(7.8, 3.2, 0.7),
	Vector3(12.0, 3.4, 3.15),
	Vector3(11.8, 3.4, 5.45),
	Vector3(12.0, 3.4, 3.15),
	Vector3(11.3, 3.4, 5.45),
	Vector3(1.7, 0.0, 8.5),
	Vector3(0.5, 0.0, 6.8),
	Vector3(1.7, 0.0, 8.5),
	Vector3(-1.0, 0.0, 8.3),
	Vector3(2.94, 0.0, -6.32),
	Vector3(1.74, 0.0, -6.51),
	Vector3(2.94, 0.0, -6.32),
	Vector3(1.74, 0.0, -7.01),
	Vector3(7.6, 0.0, -6.32),
	Vector3(7.4, 0.0, -3.52),
	Vector3(7.6, 0.0, -6.32),
	Vector3(6.9, 0.0, -3.52),
	Vector3(-0.3, 3.4, -3.75),
	Vector3(1.5, 3.4, -1.95),
	Vector3(-0.3, 3.4, -3.75),
	Vector3(-2.5, 3.4, -1.95),
	Vector3(8.6, 3.4, -1.74),
	Vector3(8.4, 3.4, 0.56),
	Vector3(8.6, 3.4, -1.74),
	Vector3(7.9, 3.27, 0.56),
	Vector3(12.6, 3.4, -6.36),
	Vector3(12.4, 3.4, -8.56),
	Vector3(12.6, 3.4, -6.36),
	Vector3(11.9, 3.4, -8.56),
	Vector3(15.41, 3.4, -6.36),
	Vector3(15.21, 3.4, -8.56),
	Vector3(15.41, 3.4, -6.36),
	Vector3(14.71, 3.4, -8.56),
]

var _space: PhysicsDirectSpaceState3D
var _probe: WorldProbe
var _night: SeatedNight
var _blocked_total := 0
var _walls := 0
var _walls_with_far_side := 0
var _clear_total := 0


func _tuning() -> RulesTuning:
	var tuning := RulesFixture.tuning()
	# The pistol only, so no wall weapon but the pistol's is one the player already carries.
	tuning.economy.start_weapons = [&"weapon_pistol"]
	tuning.rounds.first_spawn_delay = 600.0
	return tuning


func _start(scene_path: String) -> void:
	_night = await NightFixture.seat(self, 2, _tuning(), 7, false, load(scene_path) as PackedScene)
	_space = _night.world.get_world_3d().direct_space_state
	_probe = WorldProbe.new(_space)
	_night.start_round()
	_night.server.rules.apply(RulesAction.grant_points(1, 100000))
	_night.tick()
	_blocked_total = 0
	_clear_total = 0
	_walls = 0
	_walls_with_far_side = 0


func after_test() -> void:
	if _night != null:
		_night.dispose()
		_night = null


# --- The things to walk -------------------------------------------------------------------------


## `{name, sig, target, reach, skin, front, matches, setup, side}`: `target` is the floor under the
## thing's hand point; `sig` groups the things that give the same prompt (a point near two of one
## sig may be legitimately in reach of the other); `front` the points a player is offered it from.
func _thing(
	name: String,
	sig: String,
	target: Vector3,
	reach: float,
	front: Array[Vector3],
	matches: Callable
) -> Dictionary:
	return {
		"name": name,
		"sig": sig,
		"target": target,
		"reach": reach,
		"skin": UseSight.SKIN,
		"front": front,
		"matches": matches,
		"setup": Callable(),
		"side": Callable(),
		"needs_wall": false,
		"wall_weapon": false,
		"front_any": false,
	}


func _spot_things() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var index := 0
	for spot in _night.world.shop_spots():
		index += 1
		var kind: StringName = spot["kind"]
		var id: StringName = spot["shop_id"]
		var at: Vector3 = spot["position"]
		var thing := _thing(
			"%s %s #%d" % [kind, id, index],
			"%s:%s" % [kind, id if kind != &"ammo" else &""],
			at,
			_night.server.tuning.spot_reach,
			[at],
			_spot_matches(kind, id)
		)
		thing["setup"] = _spot_setup.bind(spot)
		thing["wall_weapon"] = kind == &"wall"
		out.append(thing)
	return out


## Whether `prompt` is of `kind` and names `id` (any id when empty).
func _is(prompt: Dictionary, kind: StringName, id: StringName) -> bool:
	return prompt.get("kind") == kind and (id == &"" or prompt.get("id") == id)


func _spot_matches(kind: StringName, id: StringName) -> Callable:
	return func(prompt: Dictionary) -> bool:
		match kind:
			&"wall":
				return (
					(prompt.get("kind") == &"weapon" and prompt.get("id") == id)
					or (prompt.get("kind") == &"ammo")
				)
			&"ammo":
				return prompt.get("kind") == &"ammo"
			&"crane":
				return String(prompt.get("kind", "")).begins_with("crane")
			&"rack":
				return prompt.get("kind") == &"grenades"
			&"upgrade":
				return String(prompt.get("kind", "")).begins_with("recut")
			&"perk":
				return String(prompt.get("kind", "")).begins_with("tonic") and prompt["id"] == id
		return false


## Makes the spot offer something to player 1: room for rounds, the crane standing at this spot,
## room in the pack for grenades.
func _spot_setup(spot: Dictionary) -> void:
	var server := _night.server
	var pistol := server.combat.state_of(1, &"pistol")
	pistol.reserve = 0
	server.rules.players[1].grenades = 0
	if spot["kind"] == &"crane":
		server.rules.crane.spot = spot["crane_spot"]


func _post_things() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var reach := _night.server.tuning.use_reach
	for circuit in _night.world.switches.circuit_ids():
		var post := _night.world.switches.post(circuit)
		var stand := _night.world.switches.standing_point(circuit)
		var thing := _thing(
			"post %s" % circuit,
			"circuit:%s" % circuit,
			post.global_position,
			reach,
			[stand],
			_is.bind(&"circuit", circuit)
		)
		thing["skin"] = UseSight.MOUNT_SKIN
		# A post is used from the side its front faces.
		thing["side"] = func(point: Vector3) -> bool:
			return (
				(post.global_basis.z * Vector3(1.0, 0.0, 1.0)).dot(point - post.global_position)
				>= 0.0
			)
		out.append(thing)
	var fuel_reach := _night.server.tuning.fuel_reach
	for spot in _night.world.fuel.ids():
		out.append(
			_thing(
				"fuel %s" % spot,
				"fuel:%s" % spot,
				_night.world.fuel.standing_point(spot),
				fuel_reach,
				[_night.world.fuel.standing_point(spot)],
				_is.bind(&"fuel", spot)
			)
		)
	return out


func _breach_things() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var reach := _night.server.tuning.use_reach
	for id in _night.world.barricade_ids():
		var barricade := _night.world.barricade(id)
		var thing := _thing(
			"breach %s" % id,
			"repair:%s" % id,
			barricade.centre(),
			reach,
			[],
			_is.bind(&"repair", id)
		)
		thing["skin"] = UseSight.MOUNT_SKIN
		thing["front_any"] = true
		# The boards are put back from the field's side only.
		thing["side"] = func(point: Vector3) -> bool: return barricade.depth_of(point) > 0.0
		thing["setup"] = func() -> void: _night.server.rules.barricades.tear(id)
		out.append(thing)
	return out


## Whether the door at `slab` has a stand on each side (it is bought from both).
static func _both_sides(slab: Vector3, stands: Array[Vector3]) -> bool:
	var sides := {}
	for stand in stands:
		if Vector2(stand.x - slab.x, stand.z - slab.z).length() <= UseSight.STAND_NEAR:
			var out := Vector2(stand.x - slab.x, stand.z - slab.z)
			sides[Vector2i(signi(roundi(out.x)), signi(roundi(out.y)))] = true
	return sides.size() >= 2


func _door_thing(door_id: StringName, slab: Vector3, stands: Array[Vector3]) -> Dictionary:
	var floor_point := slab - Vector3(0.0, UseOffers.DOOR_MIDDLE, 0.0)
	var thing := _thing(
		"door %s" % door_id,
		"door:%s" % door_id,
		floor_point,
		_night.server.tuning.use_reach,
		stands,
		_is.bind(&"door", door_id)
	)
	thing["skin"] = UseSight.MOUNT_SKIN
	# A door bought from both sides has no back; with a 2.5 m reach (#908) no wall may be near it.
	thing["needs_wall"] = not _both_sides(slab, stands)
	# The slab is the thing and the line ends in its middle: the hand's height is the slab's.
	thing["lift"] = slab.y - floor_point.y
	# A door is bought from the open ground in front of it only.
	thing["side"] = func(point: Vector3) -> bool:
		return stands.any(
			func(stand: Vector3) -> bool:
				var front := Vector2(stand.x - slab.x, stand.z - slab.z)
				return (
					front.length() <= UseSight.STAND_NEAR
					and front.dot(Vector2(point.x - slab.x, point.z - slab.z)) >= 0.0
				)
		)
	return thing


# --- Rays and ground of the test's own ----------------------------------------------------------


## The distance to the first wall, prop or shut door on the way (layer 1 only: a body is none), or
## -1.0 when clear.
func _wall(from: Vector3, to: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.WORLD)
	var hit := _space.intersect_ray(query)
	return -1.0 if hit.is_empty() else from.distance_to(hit["position"])


## Whether the hand at feet `point` is walled off from `thing`.
func _walled(point: Vector3, thing: Dictionary) -> bool:
	var to: Vector3 = thing["target"] + Vector3(0.0, float(thing.get("lift", HAND)), 0.0)
	var from := point + Vector3(0.0, HAND, 0.0)
	var along := from.distance_to(to)
	var hit := _wall(from, to)
	return hit >= 0.0 and hit < along - float(thing["skin"])


## The standing ground at `x, z` near height `y` (the highest within `slack` of it with a body's
## headroom above), or `Vector3.INF`.
func _ground(x: float, z: float, y: float, slack: float) -> Vector3:
	var top := Vector3(x, y + slack + 0.6, z)
	var query := PhysicsRayQueryParameters3D.create(top, top - Vector3(0.0, 2.0 * slack + 1.2, 0.0))
	query.collision_mask = PhysicsLayers.WORLD
	var hit := _space.intersect_ray(query)
	if hit.is_empty() or absf(hit["position"].y - y) > slack or hit["normal"].y < 0.7:
		return Vector3.INF
	var ground: Vector3 = hit["position"]
	if _wall(ground + Vector3(0.0, 0.1, 0.0), ground + Vector3(0.0, HEADROOM, 0.0)) >= 0.0:
		return Vector3.INF
	for i in SPOKES:
		var turn := TAU * float(i) / float(SPOKES)
		var middle := ground + Vector3(0.0, 0.6, 0.0)
		var out := middle + Vector3(sin(turn), 0.0, cos(turn)) * ROOM
		# Both ways: a ray that starts inside a wall does not see it, so a point in a wall's
		# thickness looked clear from inside while ground stood behind it (the yard behind the side
		# room's north wall, #917; a bank there had hidden it).
		if _wall(middle, out) >= 0.0 or _wall(out, middle) >= 0.0:
			return Vector3.INF
	return ground


## Every standing point of the grid around `thing` within its reach, as `{at, flat}`.
func _grid(thing: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var target: Vector3 = thing["target"]
	var radius := RING_FIRST
	while radius <= float(thing["reach"]) - MARGIN:
		var degrees := 0.0
		while degrees < 360.0:
			var turn := deg_to_rad(degrees)
			var ground := _ground(
				target.x + sin(turn) * radius, target.z + cos(turn) * radius, target.y, FLOOR_SLACK
			)
			if ground.is_finite():
				out.append({"at": ground, "flat": radius})
			degrees += SPOKE_DEGREES
		radius += RING_STEP
	return out


func _side_ok(thing: Dictionary, point: Vector3) -> bool:
	var side: Callable = thing["side"]
	return not side.is_valid() or bool(side.call(point))


func _legit_elsewhere(point: Vector3, thing: Dictionary, all: Array[Dictionary]) -> bool:
	for other in all:
		if other["name"] == thing["name"] or other["sig"] != thing["sig"]:
			continue
		var apart := Vector2(point.x - other["target"].x, point.z - other["target"].z).length()
		if apart <= float(other["reach"]) and _side_ok(other, point) and not _walled(point, other):
			return true
	return false


## The server's own sight, made again (the server keeps its own private).
func _server_sight() -> UseSight:
	return UseSight.new(_probe.static_callable())


## Whether another thing of the same sort is in reach of `point` on the floor `point` is on.
func _on_floor_elsewhere(point: Vector3, thing: Dictionary, all: Array[Dictionary]) -> bool:
	for other in all:
		if other["name"] == thing["name"] or other["sig"] != thing["sig"]:
			continue
		if _night.world.reach_distance(point, other["target"]) <= float(other["reach"]):
			return true
	return false


# --- Asking the server --------------------------------------------------------------------------


func _stand(point: Vector3, id: int = 1) -> void:
	_night.server.body_of(id).teleport(point + Vector3(0.0, 0.05, 0.0))


func _prompt() -> Dictionary:
	return _night.server.use_target(1)


func _fingerprint() -> int:
	var rules := _night.server.rules
	var state := rules.players[1]
	return hash(
		var_to_bytes(
			[
				state.points,
				state.weapons,
				state.tonics,
				state.upgraded,
				state.grenades,
				rules.doors_open,
				rules.generator.circuits,
				rules.barricades.to_dict(),
				rules.crane.stage,
				rules.crane.plays,
				rules.players[2].downed,
			]
		)
	)


## Presses use at `point` (held too, for a revive) and steps a few ticks. False when the body did
## not stay where it was put (the press then says nothing about this point).
func _press(point: Vector3) -> bool:
	_stand(point)
	var stayed := true
	for _i in PRESS_TICKS:
		var command := NightCommand.new()
		command.player_id = 1
		command.use = _i == 0
		command.use_held = true
		_night.server.apply(command.to_dict(), 1)
		_night.tick()
		stayed = stayed and _night.server.body_of(1).global_position.distance_to(point) < 0.15
		_stand(point)
	return stayed


## Walks one thing; returns the problems found (empty for none).
func _walk(thing: Dictionary, all: Array[Dictionary]) -> Array[String]:
	var problems: Array[String] = []
	var setup: Callable = thing["setup"]
	if setup.is_valid():
		setup.call()
	var name: String = thing["name"]
	var matches: Callable = thing["matches"]
	# In front of it: offered.
	for point: Vector3 in thing["front"]:
		_stand(point)
		var prompt := _prompt()
		if not matches.call(prompt):
			problems.append("%s: no prompt in front at %s, got %s" % [name, point, prompt])
	var blocked: Array[Vector3] = []
	var offered_in_front := false
	for cell in _grid(thing):
		var point: Vector3 = cell["at"]
		_stand(point)
		var prompt := _prompt()
		if thing["front_any"] and _side_ok(thing, point) and not _walled(point, thing):
			# A breach's prompt comes after the spots', which hide it where they offer something:
			# ask the breaches alone.
			var own := UseOffers.post(
				_night.world, _night.server.rules, _night.server.tuning, point, _server_sight()
			)
			offered_in_front = offered_in_front or bool(matches.call(own))
		if not _side_ok(thing, point) or _walled(point, thing):
			if _legit_elsewhere(point, thing, all):
				continue
			blocked.append(point)
			if matches.call(prompt):
				problems.append("%s: prompt through a wall at %s: %s" % [name, point, prompt])
		else:
			_clear_total += 1
			if cell["flat"] <= NEAR and prompt.is_empty():
				problems.append("%s: no prompt at the clear point %s" % [name, point])
	if thing["front_any"] and not offered_in_front and not NO_FLOOR_IN_REACH.has(thing["name"]):
		problems.append("%s: no clear point of its reach shows the prompt" % name)
	_blocked_total += blocked.size()
	_walls_with_far_side += 1 if thing["wall_weapon"] and not blocked.is_empty() else 0
	_walls += 1 if thing["wall_weapon"] else 0
	if thing["front_any"] and offered_in_front and NO_FLOOR_IN_REACH.has(thing["name"]):
		problems.append("%s: offered now, take it off NO_FLOOR_IN_REACH" % name)
	if blocked.is_empty() and thing["needs_wall"]:
		problems.append("%s: no point of its reach is behind a wall (nothing to test)" % name)
	# The press at the far side changes nothing.
	for i in mini(PRESS_POINTS, blocked.size()):
		var point := blocked[i * blocked.size() / PRESS_POINTS]
		_stand(point)
		var shown := _prompt()
		if not shown.is_empty() and not matches.call(shown):
			continue
		var before := _fingerprint()
		if not _press(point):
			continue
		if _fingerprint() != before:
			problems.append("%s: a press changed the night at %s" % [name, point])
	return problems


func _report(problems: Array[String]) -> void:
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


# --- The tests ----------------------------------------------------------------------------------


func _walk_all(scene_path: String) -> void:
	await _start(scene_path)
	var things: Array[Dictionary] = []
	things.append_array(_spot_things())
	things.append_array(_post_things())
	things.append_array(_breach_things())
	var problems: Array[String] = []
	for thing in things:
		problems.append_array(_walk(thing, things))
	# The doors, each bought after it is walked, one that the door before it unlocks last.
	var doors: Array[ShopItem] = []
	for item in _night.server.rules.tuning.economy.items:
		if item.kind == ShopItem.Kind.DOOR:
			doors.append(item)
	while not doors.is_empty():
		var next := 0
		for i in doors.size():
			if doors[i].requires == &"" or _night.server.rules.is_door_open(doors[i].requires):
				next = i
				break
		var item: ShopItem = doors.pop_at(next)
		var slabs := _night.world.door_points(item.id)
		var stands := _night.world.door_stands(item.id)
		var all: Array[Dictionary] = []
		for slab in slabs:
			all.append(_door_thing(item.id, slab, stands))
		for i in all.size():
			all[i]["name"] = "%s slab %d" % [item.id, i]
			problems.append_array(_walk(all[i], all))
		_night.open_door(item.id)
		await _night.settle(60)
	_report(problems)
	assert_int(_blocked_total).is_greater(0)
	assert_int(_clear_total).is_greater(0)
	# A spot's reach is 1.5 m from its marker since #908, and the marker 1 to 1.35 m out from its
	# wall: a wall weapon's reach now ends about at its wall, so the far side of a wall is tested on
	# the breaches, doors and posts, and on the map review's exact places (`AUDIT_LOT`).
	print("wall weapons with ground in reach behind: %d of %d" % [_walls_with_far_side, _walls])


func test_the_lot_gives_no_prompt_and_takes_no_press_through_a_wall() -> void:
	await _walk_all(LOT)


func test_the_small_map_gives_no_prompt_and_takes_no_press_through_a_wall() -> void:
	await _walk_all(SMALL)


## Stands at each place the ray audit found behind a wall and asks for the spot it is behind.
func _walk_audit(scene_path: String, audit: Array[Vector3]) -> void:
	await _start(scene_path)
	var things := _spot_things()
	var problems: Array[String] = []
	var checked := 0
	for i in range(0, audit.size(), 2):
		var hand := audit[i]
		var point := audit[i + 1]
		for thing in things:
			var at: Vector3 = thing["target"]
			if Vector2(at.x - hand.x, at.z - hand.z).length() > 0.1 or absf(at.y - hand.y) > 0.5:
				continue
			# The audit's line ends inside the machine's own block, which can hit it: only the
			# places a wall (or a prop) stands at in the test's own line, as the hand's, count.
			if not _walled(point, thing):
				continue
			checked += 1
			var setup: Callable = thing["setup"]
			if setup.is_valid():
				setup.call()
			_stand(point)
			var prompt := _prompt()
			var matches: Callable = thing["matches"]
			if _on_floor_elsewhere(point, thing, things):
				continue
			if matches.call(prompt):
				problems.append(
					"%s: prompt through a wall at %s: %s" % [thing["name"], point, prompt]
				)
				continue
			if not prompt.is_empty():
				continue
			var before := _fingerprint()
			if _press(point) and _fingerprint() != before:
				problems.append("%s: a press changed the night at %s" % [thing["name"], point])
	_report(problems)
	# Two in five of the pairs (a fifth of the entries) have a spot with a wall in the way: the
	# walk ran. The second map's list lost the crowbar's and the bat's pairs with their spots (#910).
	assert_int(checked).is_greater(audit.size() / 5)


func test_the_lot_gives_nothing_at_the_places_the_ray_audit_found_behind_a_wall() -> void:
	await _walk_audit(LOT, AUDIT_LOT)


func test_the_small_map_gives_nothing_at_the_places_the_ray_audit_found_behind_a_wall() -> void:
	await _walk_audit(SMALL, AUDIT_SMALL)


## The standing point within 1.5 m of `at` that is nearest a wall (with a body's room): a teammate
## downed there has the wall's far side within a revive's reach.
func _beside_a_wall(at: Vector3) -> Vector3:
	var best := at
	var best_apart := INF
	var probe := _thing("probe", "probe", at, 1.5 + MARGIN, [], Callable())
	for cell in _grid(probe):
		var point: Vector3 = cell["at"]
		for i in SPOKES * 2:
			var turn := TAU * float(i) / float(SPOKES * 2)
			var middle := point + Vector3(0.0, 0.6, 0.0)
			var apart := _wall(middle, middle + Vector3(sin(turn), 0.0, cos(turn)) * 1.5)
			if apart >= 0.0 and apart < best_apart:
				best_apart = apart
				best = point
	return best


func _revive_things() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var reach := _night.server.tuning.revive_reach
	var index := 0
	for spot in _night.world.shop_spots():
		index += 1
		var at := _beside_a_wall(spot["position"])
		var thing := _thing(
			"downed teammate at %s #%d" % [spot["kind"], index],
			"revive",
			at,
			reach,
			[],
			_is.bind(&"revive", &"")
		)
		thing["setup"] = func() -> void: _stand(at, 2)
		out.append(thing)
	return out


func _walk_revives(scene_path: String) -> void:
	await _start(scene_path)
	_night.server.rules.apply(RulesAction.blow(2, 5000.0))
	var problems: Array[String] = []
	for thing in _revive_things():
		# In front: the nearest clear point of the grid.
		var front: Array[Vector3] = []
		for cell in _grid(thing):
			if not _walled(cell["at"], thing) and cell["flat"] <= REVIVE_SPOKE + RING_STEP:
				front.append(cell["at"])
				break
		thing["front"] = front
		problems.append_array(_walk(thing, []))
		# And the channel itself: held beside the wall, it never begins.
		var held := _night.server.revive().is_reviving(1)
		if held:
			problems.append("%s: a revive began through a wall" % thing["name"])
	_report(problems)
	assert_int(_blocked_total).is_greater(0)


func test_the_lot_does_not_raise_a_teammate_through_a_wall() -> void:
	await _walk_revives(LOT)


func test_the_small_map_does_not_raise_a_teammate_through_a_wall() -> void:
	await _walk_revives(SMALL)


## A player on the other floor, straight above or below a thing, is out of its reach (the second
## map has two storeys).
func test_a_thing_is_not_in_reach_from_the_floor_above_or_below() -> void:
	await _start(SMALL)
	var storey := _night.world.storey()
	assert_float(storey).is_greater(0.0)
	var problems: Array[String] = []
	var checked := 0
	var things := _spot_things()
	for thing in things:
		var matches: Callable = thing["matches"]
		var setup: Callable = thing["setup"]
		setup.call()
		var target: Vector3 = thing["target"]
		for sign in [-1.0, 1.0]:
			var ground := _ground(target.x, target.z, target.y + sign * storey, FLOOR_SLACK)
			if not ground.is_finite():
				continue
			checked += 1
			_stand(ground)
			if matches.call(_prompt()) and not _on_floor_elsewhere(ground, thing, things):
				problems.append("%s: a prompt from the other floor at %s" % [thing["name"], ground])
	_report(problems)
	assert_int(checked).is_greater(0)


## The prompt a client draws is the server's: the frame carries what `use_target` answers, at a
## spot in front of a thing and at a point behind its wall.
func test_the_frame_carries_the_prompt_the_server_decides() -> void:
	await _start(SMALL)
	var shown := 0
	for thing in _spot_things():
		var setup: Callable = thing["setup"]
		setup.call()
		for point: Vector3 in thing["front"]:
			_stand(point)
			_night.tick()
			_stand(point)
			var frame_prompt: Dictionary = _night.frame["players"][1]["prompt"]
			assert_dict(frame_prompt).is_equal(_prompt())
			shown += 1 if not frame_prompt.is_empty() else 0
	assert_int(shown).is_greater(0)
