# Player bodies walk the second map's greybox with every link open (`SmallMapWalkers`): every leg
# the zombies' mesh offers is walked to its end by the real body (the stairs, the door, the opening
# upstairs, round the counter and the racks), nobody is stuck, and nobody leaves the building. A
# short run; `res://tests/captures/smallmap_move_soak.tscn` is the long one.
extends GdUnitTestSuite

const SECONDS := 90
const BODIES := 3


func test_bodies_walk_every_leg_and_stay_inside() -> void:
	var walkers := auto_free(SmallMapWalkers.new()) as SmallMapWalkers
	add_child(walkers)
	await walkers.setup(BODIES, 7)
	for i in SECONDS * 60:
		walkers.step()
		if i % 30 == 0:
			await get_tree().physics_frame
	var report := walkers.report()
	var all: Dictionary = report["all"]
	var message := str(report)
	assert_int(all["failed"]).override_failure_message(message).is_equal(0)
	assert_int(all["outside"]).override_failure_message(message).is_equal(0)
	assert_float(all["longest_stuck_seconds"]).override_failure_message(message).is_less(2.0)
	assert_int(all["reached"]).override_failure_message(message).is_greater(BODIES * 6)


func test_no_window_lets_a_player_out() -> void:
	# A body runs and jumps at every window and the breach from inside for four seconds: the sill
	# is under a jump, so only the players-only blocker keeps it in.
	var lot := auto_free((load(SmallMapMeasure.SCENE) as PackedScene).instantiate()) as Node3D
	add_child(lot)
	for _i in 4:
		await get_tree().physics_frame
	var body := auto_free(load("res://gameplay/player/player.tscn").instantiate()) as Player
	body.local_input = false
	body.capture_mouse = false
	body.strip_model()
	add_child(body)
	body.set_physics_process(false)
	for socket: Node3D in lot.get_node("Windows").get_children():
		var inward := socket.global_basis.z
		body.teleport(socket.global_position + inward * 1.5 + Vector3.UP * 0.1)
		for i in 240:
			var command := PlayerCommand.new()
			command.yaw = atan2(inward.x, inward.z)
			command.move = Vector2(0.0, -1.0)
			command.jump = i % 30 == 0
			body.tick(command)
			if i % 30 == 0:
				await get_tree().physics_frame
		var depth := (body.global_position - socket.global_position).dot(inward)
		(
			assert_float(depth)
			. override_failure_message(
				"%s: the body got %.2f m into the wall" % [socket.name, -depth]
			)
			. is_greater(0.0)
		)
