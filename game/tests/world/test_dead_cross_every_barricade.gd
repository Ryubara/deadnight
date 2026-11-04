extends GdUnitTestSuite
## The dead climb in over the sill and never through the wall (#915: "zombies would just phase
## through the wall"). On both maps, at every barricade with its boards down, a zombie walks the
## real navigation mesh from outside to a player inside, and at every step its body (a capsule
## of the zombie's width, from its knees to its head) is asked whether it stands in anything solid.
## A dead that crossed a sill at the floor, or brushed a jamb, fails here with where it was.

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
## Metres outside the barricade the dead start, and inside which the player stands.
const START_OUT := 5.0
## An upstairs window opens onto a gallery or a terrace 2.5 m deep and no more: a dead put 5 m out
## stands in the air over the alley, and its walk starts from wherever the mesh is nearest it.
const START_OUT_UPSTAIRS := 1.2
## A window whose sill foot is higher than this is upstairs (m).
const UPSTAIRS_FROM := 1.0
const STAND_IN := 3.6
## It is across when it is this far inside.
const ACROSS := 1.6
const MAX_TICKS := 900
## Only the wall's own reach is asked (m): the apron's lamp posts and the rooms' furniture are
## other things a body may stand in, and not this one's.
const NEAR := 1.6
const WORLD_MASK := 1
## How far either side of the opening's middle the dead start (m): the way through is a funnel,
## and a zombie that starts off to one side takes the edge of it.
const SIDES: Array[float] = [-0.8, 0.0, 0.8]
## A dead walks at a stroll and at a sprint.
const SPEEDS: Array[float] = [1.0, 6.0]

var _seated: SeatedNight


func after_test() -> void:
	if _seated != null:
		_seated.dispose()
		_seated = null


func _walk_every_barricade(path: String) -> void:
	var tuning := RulesFixture.tuning()
	tuning.health.max_health = 1000000.0
	_seated = await SeatedNight.start(self, 1, tuning, 5, false, load(path) as PackedScene)
	for item in _seated.server.rules.tuning.economy.items:
		if item.kind == ShopItem.Kind.DOOR:
			_seated.open_door(item.id)
	await _seated.settle(30)
	var world := _seated.world
	var checked := 0
	for id in world.barricade_ids():
		for side in SIDES:
			for speed in SPEEDS:
				var report := await _cross(id, side, speed)
				assert_str(report).override_failure_message(report).is_empty()
				checked += 1
	assert_int(checked).is_greater(10)


## One zombie across one barricade: "" when it got in without touching a solid, else what went
## wrong.
func _cross(id: StringName, side: float, speed: float) -> String:
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
	var out := START_OUT_UPSTAIRS if floor_y > UPSTAIRS_FROM else START_OUT
	var start := barricade.centre() - barricade.inward() * out + across * side
	start.y = floor_y
	var zombie := sim.spawn(900, speed, start, 0.0, null, id)
	zombie.enter(ZombieBody.Mode.CHASE)
	var shape := CapsuleShape3D.new()
	shape.radius = BODY_RADIUS
	shape.height = BODY_TO - BODY_FROM
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = WORLD_MASK
	var space := world.get_world_3d().direct_space_state
	var label := "%s (start %+.1f m aside, %.0f m/s)" % [id, side, speed]
	var climbed := false
	for tick in MAX_TICKS:
		_seated.tick()
		if tick % 30 == 0:
			await get_tree().physics_frame
		if not sim.zombies.has(900):
			return "%s: the zombie was lost" % label
		zombie = sim.zombies[900]
		climbed = climbed or zombie.climbing
		shape.height = (BODY_TO_CLIMBING if zombie.climbing else BODY_TO) - BODY_FROM
		query.transform = Transform3D(
			Basis.IDENTITY, zombie.position + Vector3.UP * (BODY_FROM + shape.height * 0.5)
		)
		var hit := _wall_in_the_body(space, query, barricade)
		if hit != null and absf(barricade.depth_of(zombie.position)) < NEAR:
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
				return "%s: it came in without climbing" % label
			return ""
	if side != 0.0:
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
