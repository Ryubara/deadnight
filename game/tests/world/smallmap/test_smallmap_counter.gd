# The hall's counter on the second map is not a roost (#847). Its middle is out of every zombie's
# reach (a zombie's centre stays 0.5 m off the counter and swings from 1.4 m, the middle of the top
# is 1.75 m from an edge), so a player who could stand on it shot down at the dead with nothing able
# to answer. The counter was 1.2 m high ("a little over a jump"), and the real body climbs 1.25 m
# from a standing start, not the jump's 1.1 m (docs/research/map-review.md): a sprint-jump from the
# west landed on it. It is built above the reach now; this runs the real player body at it.
extends GdUnitTestSuite

const SCENE := "res://world/smallmap/smallmap_greybox.tscn"
const PLAYER_SCENE := "res://gameplay/player/player.tscn"
## The most the body is measured to climb from level ground (`tests/player/test_jump_reach.gd`).
const BODY_REACH := CameraProbe.BODY_REACH
## What the counter must stand above that, so a small change to the jump or the step does not
## bring the roost back.
const MARGIN := 0.15
## Headings round the counter, and how far from its edge the body starts (metres).
const HEADINGS := 16
const START_GAPS := [1.0, 2.0, 3.0, 4.0]
const JUMP_TICKS := [0, 10, 20]
const RUN_TICKS := 80
## A body this high over the hall's floor, inside the counter's footprint, stands on the counter.
const ON_TOP_FROM := 1.0
const HALL := Rect2(1.0, 1.0, 14.0, 12.5)

var _hall: Node3D
var _body: Player


func before_test() -> void:
	_hall = auto_free((load(SCENE) as PackedScene).instantiate()) as Node3D
	add_child(_hall)
	_body = auto_free((load(PLAYER_SCENE) as PackedScene).instantiate()) as Player
	_body.local_input = false
	_body.capture_mouse = false
	_body.strip_model()
	add_child(_body)
	_body.set_physics_process(false)
	for _i in 4:
		await get_tree().physics_frame


## The counter's pieces, as one box in the scene's frame.
func _counter() -> AABB:
	var found := AABB()
	var first := true
	for piece in _hall.get_node("Start").get_children():
		if not String(piece.name).begins_with("DispatchCounter"):
			continue
		var box := piece as CSGBox3D
		var bounds := AABB(box.global_position - box.size / 2.0, box.size)
		found = bounds if first else found.merge(bounds)
		first = false
	assert_bool(first).override_failure_message("the hall has no counter").is_false()
	return found


func test_the_counter_stands_above_what_the_body_climbs() -> void:
	var top := _counter().end.y
	(
		assert_float(top)
		. override_failure_message(
			(
				"the counter is %.2f m high; the body climbs %.2f m, so it needs %.2f m"
				% [top, BODY_REACH, BODY_REACH + MARGIN]
			)
		)
		. is_greater_equal(BODY_REACH + MARGIN)
	)


func test_a_player_running_and_jumping_at_the_counter_never_stands_on_it() -> void:
	var counter := _counter()
	var centre := counter.get_center()
	var landed: Array[String] = []
	var runs := 0
	for heading in HEADINGS:
		var angle := TAU * heading / HEADINGS
		var toward := Vector3(cos(angle), 0.0, sin(angle))
		# From the centre out to the edge along this heading, then each gap past it.
		var edge := _edge_distance(counter, -toward)
		for gap: float in START_GAPS:
			var start := centre - toward * (edge + gap)
			start.y = 0.0
			if not _hall_floor_is_clear(start):
				continue
			for sprint in [true, false]:
				for jump_tick: int in JUMP_TICKS:
					runs += 1
					if await _stands_on_top(start, toward, sprint, jump_tick, counter):
						landed.append(
							(
								"from %s toward %s sprint %s jump at %d"
								% [start, toward, sprint, jump_tick]
							)
						)
	assert_int(runs).override_failure_message("too few runs: %d" % runs).is_greater(150)
	(
		assert_array(landed)
		. override_failure_message("a player stood on the counter: %s" % [landed.slice(0, 3)])
		. is_empty()
	)


## How far a ray from the box's centre along `direction` (flat) travels before it leaves the box.
func _edge_distance(box: AABB, direction: Vector3) -> float:
	var half := box.size / 2.0
	var along := INF
	if absf(direction.x) > 0.0001:
		along = minf(along, half.x / absf(direction.x))
	if absf(direction.z) > 0.0001:
		along = minf(along, half.z / absf(direction.z))
	return along


## Whether a body fits at `start` on the hall's floor (not inside a wall, a pillar, a stair or a
## machine): a run from inside a solid says nothing.
func _hall_floor_is_clear(start: Vector3) -> bool:
	if not HALL.has_point(Vector2(start.x, start.z)):
		return false
	var tuning := CameraProbe.tuning()
	var capsule := CapsuleShape3D.new()
	capsule.radius = tuning.radius
	capsule.height = tuning.height - 0.3
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.BOARDS
	query.transform = Transform3D(
		Basis.IDENTITY, start + Vector3(0.0, tuning.height * 0.5 + 0.2, 0.0)
	)
	return _hall.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## One run: the body at `start` on the floor, facing `toward`, running (or walking) at it with the
## jump pressed three ticks from `jump_tick`. True when it is on the counter at any tick.
func _stands_on_top(
	start: Vector3, toward: Vector3, sprint: bool, jump_tick: int, counter: AABB
) -> bool:
	_body.teleport(start + Vector3(0.0, 0.02, 0.0))
	var footprint := (
		Rect2(counter.position.x, counter.position.z, counter.size.x, counter.size.z).grow(0.1)
	)
	for tick in RUN_TICKS:
		var command := PlayerCommand.new()
		command.yaw = atan2(-toward.x, -toward.z)
		command.move = Vector2(0.0, -1.0)
		command.sprint = sprint
		command.jump = tick >= jump_tick and tick < jump_tick + 3
		_body.tick(command)
		var at := _body.global_position
		if at.y > ON_TOP_FROM and footprint.has_point(Vector2(at.x, at.z)):
			return true
		if tick % 40 == 0:
			await get_tree().physics_frame
	return false
