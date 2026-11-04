extends GdUnitTestSuite
## The frame's zombie bytes are decoded once for the whole process (#930): the person's client, each
## bot's and the horde read the same bytes, and the bytes change only when the simulation steps
## (30 Hz, a frame comes at 60 Hz). The views and the voices loop over the crowd once per step.

var _sim: ZombieSim


func before_test() -> void:
	_sim = ZombieFixture.sim()


func _frame(bytes: PackedByteArray) -> Dictionary:
	return {"type": &"frame", "zombies": bytes, "players": {}}


func _crowd(count: int, shift := 0.0) -> PackedByteArray:
	_sim.zombies.clear()
	for id in count:
		ZombieFixture.standing(_sim, id + 1, Vector3(id + shift, 0, 3))
	return ZombieCodec.encode(_sim.zombies)


func test_the_same_bytes_are_decoded_once_and_the_entries_handed_out_again() -> void:
	var bytes := _crowd(20)
	var before := ZombieCodec.decode_count
	var first := ZombieCodec.decode_shared(bytes)
	var again := ZombieCodec.decode_shared(bytes.duplicate())
	assert_int(ZombieCodec.decode_count - before).is_equal(1)
	assert_int(first.size()).is_equal(20)
	assert_bool(is_same(first, again)).is_true()
	assert_array(first).is_equal(ZombieCodec.decode(bytes))


func test_other_bytes_are_decoded_and_not_mistaken_for_the_last() -> void:
	var first := ZombieCodec.decode_shared(_crowd(5))
	var moved := ZombieCodec.decode_shared(_crowd(5, 0.5))
	assert_bool(is_same(first, moved)).is_false()
	assert_float(moved[0]["position"].x).is_equal_approx(0.5, 0.001)
	assert_int(ZombieCodec.decode_shared(PackedByteArray()).size()).is_equal(0)
	assert_int(ZombieCodec.decode_shared(_crowd(0)).size()).is_equal(0)


func test_every_client_state_that_hears_a_frame_shares_one_decode() -> void:
	var event := _frame(_crowd(30))
	var states: Array[ClientState] = []
	for id in 4:
		var state := ClientState.new()
		state.player_id = id + 1
		states.append(state)
	var before := ZombieCodec.decode_count
	for state in states:
		state.apply_events([event])
	assert_int(ZombieCodec.decode_count - before).is_equal(1)
	for state in states:
		assert_int(state.zombies.size()).is_equal(30)
	# The next frame holds the same bytes (the simulation has not stepped): none at all.
	var held := _frame(ZombieCodec.encode(_sim.zombies))
	for state in states:
		state.apply_events([held])
	assert_int(ZombieCodec.decode_count - before).is_equal(1)
	# A step moved them: one more, for all four.
	var stepped := _frame(_crowd(30, 0.2))
	for state in states:
		state.apply_events([stepped])
	assert_int(ZombieCodec.decode_count - before).is_equal(2)
	assert_float(states[3].zombies[0]["position"].x).is_equal_approx(0.2, 0.001)


func _horde() -> ZombieHorde:
	var camera := auto_free(Camera3D.new()) as Camera3D
	add_child(camera)
	var horde := auto_free(ZombieHorde.new()) as ZombieHorde
	add_child(horde)
	horde.setup_client(camera, 0.7)
	return horde


func test_the_horde_leaves_its_views_alone_for_bytes_it_has_applied() -> void:
	var horde := _horde()
	var bytes := _crowd(8)
	assert_bool(horde.apply_snapshot(bytes, 1.0 / 60.0)).is_true()
	assert_int(horde.view_count()).is_equal(8)
	var view := horde.view_of(3)
	view.position = Vector3(99, 0, 99)
	var decodes := ZombieCodec.decode_count
	assert_bool(horde.apply_snapshot(bytes.duplicate(), 1.0 / 60.0)).is_false()
	assert_vector(view.position).is_equal(Vector3(99, 0, 99))
	assert_int(horde.last_snapshot_bytes).is_equal(bytes.size())
	assert_int(ZombieCodec.decode_count).is_equal(decodes)
	# A zombie that left, or one that moved, is a new snapshot and reaches the views.
	assert_bool(horde.apply_snapshot(_crowd(7), 1.0 / 60.0)).is_true()
	assert_int(horde.view_count()).is_equal(7)
	assert_vector(horde.view_of(3).position).is_equal_approx(Vector3(2, 0, 3), Vector3.ONE * 0.02)


func test_the_horde_still_moves_the_dead_evenly_when_fed_every_tick() -> void:
	var horde := _horde()
	ZombieFixture.standing(_sim, 1, Vector3.ZERO)
	var body: ZombieBody = _sim.zombies[1]
	var seen: Array[float] = []
	for tick in 40:
		await get_tree().physics_frame
		var view := horde.view_of(1)
		seen.append(view.position.x if view != null else 0.0)
		# The simulation steps on every second tick: the bytes in between are the last ones.
		if tick % 2 == 0:
			body.position.x += 0.1
		horde.apply_snapshot(ZombieCodec.encode(_sim.zombies), 1.0 / 60.0)
	var most := 0.0
	var least := 1.0
	for i in range(8, seen.size()):
		var gap := seen[i] - seen[i - 1]
		most = maxf(most, gap)
		least = minf(least, gap)
	assert_float(least).is_greater(0.045)
	assert_float(most).is_less(0.055)


func test_a_night_with_three_bots_decodes_the_crowd_at_most_once_a_tick() -> void:
	var night := Night.new()
	night.match_settings = MatchSettings.new()
	night.match_settings.bots = 3
	add_child(night)
	await night.start(Night.Mode.MANUAL, 7)
	night.server.rules.apply(RulesAction.skip_break())
	NightFixture.run(night, 300)
	assert_int(night.state.zombies.size()).is_greater(0)
	var ticks := 120
	var before := ZombieCodec.decode_count
	NightFixture.run(night, ticks)
	var decodes := ZombieCodec.decode_count - before
	# Five readers (the person, three bots, the horde) used to make five a tick. Now one for each
	# step of the simulation (half the ticks).
	assert_int(decodes).is_greater(0)
	assert_int(decodes).is_less_equal(ticks / 2 + 2)
	await NightFixture.settle_bake(night)
	night.queue_free()
