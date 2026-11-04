extends GdUnitTestSuite
## The dead climb in over the sill and never through the wall (#915: "zombies would just phase
## through the wall"). On both maps, at every barricade with its boards down, a zombie walks the
## real navigation mesh from outside to a player inside, and at every step its body (a capsule
## of the zombie's width, from its knees to its head) is asked whether it stands in anything solid.
## A dead that crossed a sill at the floor, or brushed a jamb, fails here with where it was. Each
## also walks in from where the dead of that barricade rise, up the stairs and along the decks.

## How a dead comes to its barricade: straight from outside the middle of it, from outside one end
## of it (it may take the next window along, #810), or from where it rises (a walk that passes
## stairs and other walls, so its body is judged in this wall's thickness only, where the
## simulation keeps a body off the jambs: `ZombieGate.keep_in_opening`).
enum Walk { STRAIGHT, ASIDE, FROM_SPAWN }

const LOT := "res://world/drive_in_greybox.tscn"
const SMALL := "res://world/smallmap/smallmap_greybox.tscn"
## The zombie's body, as the capsule it is tested with: its width (half, m) and the part of it
## above the knees. The feet are left out: a foot on a sill is on it, not in it.
const BODY_RADIUS := 0.3
const BODY_FROM := 0.15
const BODY_TO := 1.55
## Over the sill it is drawn on its hands (the crawl clip and a lean, `ZombieView`): its body is
## about this tall then, so the head clears a lintel 1.3 m over the sill.
const BODY_TO_CLIMBING := 1.1
## Metres outside the barricade the dead start, and inside which the player stands. A deck is
## narrower than `START_OUT`: there the dead start as far out as it goes, `START_STEP` at a time,
## and never closer than `START_OUT_LEAST`, the sill's ramp.
const START_OUT := 5.0
const START_STEP := 0.25
const START_OUT_LEAST := 1.5
const STAND_IN := 3.6
## How far (m) the walking mesh's nearest point may lie beside a start, and above or below it: more
## and the start stands on nothing, and a dead put there walks to some other floor (#994).
const ON_THE_MESH := 0.05
const SAME_FLOOR := 1.0
## It is across when it is this far inside.
const ACROSS := 1.6
const MAX_TICKS := 900
## From where they rise: 26 s of a stroll, the 19 m to an upper window with its stair and deck.
const MAX_TICKS_FROM_THE_SPAWN := 1600
## Only the wall's own reach is asked (m): the apron's lamp posts and the rooms' furniture are
## other things a body may stand in, and not this one's.
const NEAR := 1.6
const WORLD_MASK := 1
## How far either side of the opening's middle the dead start (m): the way through is a funnel,
## and a zombie that starts off to one side takes the edge of it.
const SIDES: Array[float] = [-0.8, 0.0, 0.8]
## A dead walks at a stroll and at a sprint.
const SPEEDS: Array[float] = [1.0, 6.0]
## Metres from the wall's middle, and either side of the boards, in which a climb is over this
## barricade's own sill and not another's (a storey under it, the next window along).
const ITS_OWN_SILL := 1.6
const SILL_SLACK := 0.5

var _seated: SeatedNight


func after_test() -> void:
	if _seated != null:
		_seated.dispose()
		_seated = null


func _seat(path: String) -> void:
	var tuning := RulesFixture.tuning()
	tuning.health.max_health = 1000000.0
	_seated = await SeatedNight.start(self, 1, tuning, 5, false, load(path) as PackedScene)
	for item in _seated.server.rules.tuning.economy.items:
		if item.kind == ShopItem.Kind.DOOR:
			_seated.open_door(item.id)
	await _seated.settle(30)


func _walk_every_barricade(path: String) -> void:
	await _seat(path)
	var checked := 0
	for id in _seated.world.barricade_ids():
		for side in SIDES:
			for speed in SPEEDS:
				var start := _start_outside(id, side)
				var label := "%s (start %+.1f m aside, %.0f m/s)" % [id, side, speed]
				var walk := Walk.STRAIGHT if side == 0.0 else Walk.ASIDE
				var report := await _cross(id, start, speed, label, walk)
				assert_str(report).override_failure_message(report).is_empty()
				checked += 1
	assert_int(checked).is_greater(10)


## The dead of every spawn point walk from where they rise, not from a spot put outside the boards.
func _walk_from_every_spawn(path: String) -> void:
	await _seat(path)
	var checked := 0
	var gates := _seated.world.spawn_gates()
	for point: Vector3 in gates:
		var id: StringName = gates[point]
		for speed in SPEEDS:
			var label := "%s (from its spawn %s, %.0f m/s)" % [id, point, speed]
			var report := await _cross(id, point, speed, label, Walk.FROM_SPAWN)
			assert_str(report).override_failure_message(report).is_empty()
			checked += 1
	assert_int(checked).is_greater(10)


## Where a dead outside `id` starts: `START_OUT` from the boards or, off a deck, as far out as the
## walking mesh goes at the window's own height. A start in the air has no ground under it, and
## what the dead does there is the nearest mesh's: on the second map a shed's roof no dead can
## reach, or the room over the side room through its wall (#994).
func _start_outside(id: StringName, side: float) -> Vector3:
	var barricade := _seated.world.barricade(id)
	var map := _seated.world.map()
	var across := barricade.inward().cross(Vector3.UP)
	var out := START_OUT
	while out >= START_OUT_LEAST:
		var start := barricade.centre() - barricade.inward() * out + across * side
		start.y = barricade.global_position.y
		var ground := NavigationServer3D.map_get_closest_point(map, start)
		if (
			Vector2(ground.x - start.x, ground.z - start.z).length() <= ON_THE_MESH
			and absf(ground.y - start.y) <= SAME_FLOOR
		):
			return start
		out -= START_STEP
	assert_bool(false).override_failure_message("%s: no ground outside it" % id).is_true()
	return barricade.centre() - barricade.inward() * START_OUT


## Whether a dead at `point` is over `barricade`'s own sill.
func _at_its_own_sill(barricade: Barricade, point: Vector3, across: Vector3) -> bool:
	var along := absf((point - barricade.centre()).dot(across))
	return (
		absf(barricade.depth_of(point)) < ITS_OWN_SILL
		and along < barricade.board_half + SILL_SLACK
		and absf(point.y - barricade.global_position.y) < ITS_OWN_SILL
	)


## Whether a dead at `point` is in `barricade`'s wall, in front of the opening.
func _in_its_wall(barricade: Barricade, point: Vector3, across: Vector3) -> bool:
	return (
		_at_its_own_sill(barricade, point, across)
		and (
			absf(barricade.depth_of(point)) < barricade.thickness * 0.5 + ZombieGate.BODY_HALF_WIDTH
		)
	)


## One zombie across one barricade, from `start`: "" when it got in over the barricade's own sill
## without touching a solid, else what went wrong.
func _cross(id: StringName, start: Vector3, speed: float, label: String, walk: Walk) -> String:
	var world := _seated.world
	var barricade := world.barricade(id)
	var sim := _seated.server.sim
	_seated.server.rules.barricades.boards[id] = 0
	barricade.set_boards(0, false)
	sim.zombies.clear()
	var across := barricade.inward().cross(Vector3.UP)
	var floor_y := barricade.global_position.y
	var stand := barricade.centre() + barricade.inward() * STAND_IN
	_seated.server.body_of(1).teleport(Vector3(stand.x, floor_y + 0.1, stand.z))
	var zombie := sim.spawn(900, speed, start, 0.0, null, id)
	zombie.enter(ZombieBody.Mode.CHASE)
	var shape := CapsuleShape3D.new()
	shape.radius = BODY_RADIUS
	shape.height = BODY_TO - BODY_FROM
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = WORLD_MASK
	var space := world.get_world_3d().direct_space_state
	var climbed := false
	for tick in MAX_TICKS_FROM_THE_SPAWN if walk == Walk.FROM_SPAWN else MAX_TICKS:
		_seated.tick()
		if tick % 30 == 0:
			await get_tree().physics_frame
		if not sim.zombies.has(900):
			return "%s: the zombie was lost" % label
		zombie = sim.zombies[900]
		climbed = (
			climbed or (zombie.climbing and _at_its_own_sill(barricade, zombie.position, across))
		)
		shape.height = (BODY_TO_CLIMBING if zombie.climbing else BODY_TO) - BODY_FROM
		query.transform = Transform3D(
			Basis.IDENTITY, zombie.position + Vector3.UP * (BODY_FROM + shape.height * 0.5)
		)
		var hit := _wall_in_the_body(space, query, barricade)
		var judged := (
			_in_its_wall(barricade, zombie.position, across)
			if walk == Walk.FROM_SPAWN
			else absf(barricade.depth_of(zombie.position)) < NEAR
		)
		if hit != null and judged:
			var solid := hit
			return (
				"%s: its body is in %s at depth %.2f, along %.2f, height %.2f"
				% [
					label,
					solid.get_path() if solid != null else "a solid",
					barricade.depth_of(zombie.position),
					(zombie.position - barricade.centre()).dot(across),
					zombie.position.y - floor_y
				]
			)
		if barricade.depth_of(zombie.position) > ACROSS:
			if not climbed:
				return "%s: it came in without climbing its sill" % label
			return ""
	if walk == Walk.ASIDE:
		return ""  # off to one side it may come to the next window along (#810): its body is judged
	return (
		"%s: it did not get in (at %s, mode %d, gate %s, boards %d, depth %.2f)"
		% [
			label,
			zombie.position,
			zombie.mode,
			zombie.gate_id,
			_seated.server.rules.barricades.boards_of(id),
			barricade.depth_of(zombie.position)
		]
	)


## What of the wall (the map's CSG walls and this barricade's own frame, not a prop of the room)
## the body is in, or null.
func _wall_in_the_body(
	space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D, barricade: Barricade
) -> Node:
	for hit in space.intersect_shape(query, 8):
		var solid := hit["collider"] as Node
		if solid is CSGShape3D or _is_frame_of(solid, barricade):
			return solid
	return null


## Whether `solid` is a part of the window around `barricade`: a child of its window socket (the
## second map) or of a `Frame*` node standing where it does (the drive-in's).
func _is_frame_of(solid: Node, barricade: Barricade) -> bool:
	var parent := solid.get_parent()
	return (
		parent == barricade.get_parent()
		or (
			parent.name.begins_with("Frame")
			and (parent as Node3D).global_position.is_equal_approx(barricade.global_position)
		)
	)


func test_the_dead_climb_in_at_every_drive_in_breach_without_touching_the_wall() -> void:
	await _walk_every_barricade(LOT)


func test_the_dead_climb_in_at_every_second_map_window_without_touching_the_wall() -> void:
	await _walk_every_barricade(SMALL)


func test_the_dead_rise_and_climb_in_over_their_own_sill_at_every_drive_in_breach() -> void:
	await _walk_from_every_spawn(LOT)


func test_the_dead_rise_and_climb_in_over_their_own_sill_at_every_second_map_window() -> void:
	await _walk_from_every_spawn(SMALL)
