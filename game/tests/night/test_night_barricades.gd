# The boards across the fence's breaches, in a night: the lot has the breaches the rules list, the
# dead come to them from outside and tear them off a swing at a time and only then come in, the
# boards are solid for a player and nothing else, and a player (or the bot) puts them back for
# points. Driven like a client: events, frames and commands only.
extends GdUnitTestSuite

const BREACH := &"nw"
## Ticks to let the night settle, and the most a wait for the dead may take (60 ticks a second).
const SETTLE := 30
const GIVE_UP_TICKS := 3600
## A player in the field, metres in from the boards of the north-west breach, and the yaw that
## walks them out of the fence (forward is -Z turned by the yaw).
const FACING_OUT := PI / 2.0
## The height of the third board's middle: a ray through the boards, not between two.
const BOARD_HEIGHT := 1.5

var _events: Array[Dictionary] = []


func _start(tuning: RulesTuning = null, mode := Night.Mode.MANUAL) -> Night:
	_events = []
	var night := await NightFixture.start(self, mode, tuning)
	night.state.event_received.connect(func(event: Dictionary) -> void: _events.append(event))
	NightFixture.run(night, SETTLE)
	return night


func _count(type: StringName) -> int:
	return _events.filter(func(event: Dictionary) -> bool: return event["type"] == type).size()


func _boards_in_the_lot(night: Night, id: StringName) -> int:
	var up := 0
	for board in night.world.barricade(id).get_children():
		if (board as Node3D).visible:
			up += 1
	return up


func test_the_lot_has_the_breaches_the_rules_list_with_boards_across_each() -> void:
	var night := await _start()
	var tuning: BarricadeTuning = night.server.rules.tuning.barricades
	var ids := night.world.barricade_ids()
	ids.sort()
	var listed := tuning.ids.duplicate()
	listed.sort()
	assert_array(ids).is_equal(listed)
	for id in ids:
		var barricade := night.world.barricade(id)
		assert_int(barricade.capacity()).is_equal(tuning.boards)
		assert_int(barricade.boards()).is_equal(tuning.boards)
		assert_int(_boards_in_the_lot(night, id)).is_equal(tuning.boards)
	night.queue_free()


func test_every_field_spawn_stands_outside_its_own_breach() -> void:
	var night := await _start()
	var gates := night.world.spawn_gates()
	assert_int(gates.size()).is_equal(night.world.barricade_ids().size())
	for point: Vector3 in gates:
		var barricade := night.world.barricade(gates[point])
		assert_float(barricade.depth_of(point)).is_less(-2.0)
		assert_float(point.distance_to(barricade.centre())).is_less(6.0)
	night.queue_free()


func test_the_lot_follows_the_rules_board_by_board() -> void:
	var night := await _start()
	var zombie := NightFixture.first_zombie(night)
	var rules := night.server.rules
	night.state.apply_events(rules.apply(RulesAction.tear_board(BREACH, zombie)))
	night.state.apply_events(rules.apply(RulesAction.tear_board(BREACH, zombie)))
	assert_int(night.world.barricade(BREACH).boards()).is_equal(3)
	assert_int(_boards_in_the_lot(night, BREACH)).is_equal(3)
	assert_int(_boards_in_the_lot(night, &"ne")).is_equal(5)
	night.state.apply_events(rules.apply(RulesAction.repair(1, BREACH)))
	assert_int(_boards_in_the_lot(night, BREACH)).is_equal(4)
	night.queue_free()


func test_boards_stop_a_player_and_not_a_shot() -> void:
	var night := await _start()
	var barricade := night.world.barricade(BREACH)
	var outside := barricade.centre() + Vector3(0.0, BOARD_HEIGHT, 0.0) - barricade.inward() * 3.0
	var inside := barricade.centre() + Vector3(0.0, BOARD_HEIGHT, 0.0) + barricade.inward() * 3.0
	var shot := WorldProbe.new(night.get_world_3d().direct_space_state)
	assert_float(shot.distance(outside, inside)).is_equal(-1.0)
	var boards := WorldProbe.new(night.get_world_3d().direct_space_state, Barricade.BOARD_LAYER)
	assert_float(boards.distance(outside, inside)).is_greater(0.0)
	night.queue_free()


func test_a_player_walks_into_whole_boards_and_out_through_torn_ones() -> void:
	var night := await _start()
	var barricade := night.world.barricade(BREACH)
	var walk := NightCommand.new()
	walk.motion.yaw = FACING_OUT
	walk.motion.move = Vector2(0.0, -1.0)
	night.player().teleport(night.world.repair_spot(BREACH))
	NightFixture.run(night, 240, walk)
	assert_float(barricade.depth_of(night.player().global_position)).is_greater(0.0)
	var zombie := NightFixture.first_zombie(night)
	for _i in night.server.rules.tuning.barricades.boards:
		night.state.apply_events(night.server.rules.apply(RulesAction.tear_board(BREACH, zombie)))
	NightFixture.run(night, 240, walk)
	assert_float(barricade.depth_of(night.player().global_position)).is_less(-1.0)
	night.queue_free()


func test_the_dead_tear_the_boards_off_before_they_come_in() -> void:
	var night := await _start()
	night.server.rules.apply(RulesAction.skip_break())
	var sim := night.server.sim
	var whole: int = night.server.rules.tuning.barricades.boards
	var came_for: Dictionary[int, StringName] = {}
	var torn_when_in := -1
	for _i in GIVE_UP_TICKS:
		night.tick()
		for zombie: ZombieBody in sim.zombies.values():
			if zombie.gate_id != &"":
				came_for[zombie.id] = zombie.gate_id
				# Outside the fence for as long as boards stand across the way.
				var gate := night.world.barricade(zombie.gate_id)
				if gate.boards() > 0:
					assert_float(gate.depth_of(zombie.position)).is_less(0.0)
			elif came_for.has(zombie.id) and torn_when_in < 0:
				var gate_id := came_for[zombie.id]
				torn_when_in = (
					_events
					. filter(
						func(e: Dictionary) -> bool:
							return e["type"] == &"board_torn" and e["barricade_id"] == gate_id
					)
					. size()
				)
		if torn_when_in >= 0:
			break
	# The first one in had to have every board of its breach off first.
	assert_int(torn_when_in).is_greater_equal(whole)
	for event in _events:
		if event["type"] == &"board_torn":
			assert_int(event["zombie_id"]).is_greater(0)
			assert_int(event["boards"]).is_between(0, whole - 1)
	night.queue_free()


func test_a_player_puts_the_boards_back_for_points_from_inside_only() -> void:
	var night := await _start()
	var zombie := NightFixture.first_zombie(night)
	var rules := night.server.rules
	for _i in 3:
		night.state.apply_events(rules.apply(RulesAction.tear_board(BREACH, zombie)))
	var barricade := night.world.barricade(BREACH)
	var use := NightCommand.new()
	use.use = true
	# Outside the fence there is nothing to put back from.
	night.player().teleport(barricade.centre() - barricade.inward() * 1.2)
	NightFixture.run(night, 2)
	assert_dict(night.state.me()["prompt"]).is_empty()
	night.player().teleport(night.world.repair_spot(BREACH))
	NightFixture.run(night, 2)
	var prompt: Dictionary = night.state.me()["prompt"]
	assert_str(prompt["kind"]).is_equal("repair")
	assert_str(prompt["id"]).is_equal(BREACH)
	assert_int(prompt["boards"]).is_equal(2)
	var before := night.state.points()
	NightFixture.run(night, 1, use)
	NightFixture.run(night, 2)
	assert_int(barricade.boards()).is_equal(3)
	assert_int(night.state.points()).is_equal(before + rules.tuning.economy.repair)
	# One board a second at most: holding the key does not rebuild it all at once.
	NightFixture.run(night, 30, use)
	assert_int(barricade.boards()).is_equal(3)
	NightFixture.run(night, 60, use)
	assert_int(barricade.boards()).is_equal(4)
	NightFixture.run(night, 60, use)
	assert_int(barricade.boards()).is_equal(5)
	assert_int(_count(&"board_repaired")).is_equal(3)
	NightFixture.run(night, 2)
	assert_dict(night.state.me()["prompt"]).is_empty()
	night.queue_free()


func test_the_bot_goes_to_the_broken_fence_in_the_break_and_mends_it() -> void:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = 60.0
	var night := await _start(tuning, Night.Mode.AUTOPILOT)
	var rules := night.server.rules
	var north := &"n"
	for _i in 3:
		rules.barricades.tear(north)
	night.world.barricade(north).set_boards(rules.barricades.boards_of(north))
	var ticks := 0
	while rules.barricades.boards_of(north) < tuning.barricades.boards and ticks < GIVE_UP_TICKS:
		night.tick()
		ticks += 1
	assert_int(rules.barricades.boards_of(north)).is_equal(tuning.barricades.boards)
	NightFixture.run(night, 3)
	assert_int(_count(&"board_repaired")).is_equal(3)
	assert_int(night.state.points_earned).is_greater_equal(3 * tuning.economy.repair)
	night.queue_free()
