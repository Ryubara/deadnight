# The zombies of a frame as the difference against the ones a client has (#57): it must give the
# same zombies back, in far fewer bytes, and never let a bad packet through.
extends GdUnitTestSuite

const TICKS := 300


## `count` zombies walking on the lot at 3 m/s, turning now and then, as bodies of the codec.
func _walkers(count: int, seed_value: int) -> Dictionary[int, ZombieBody]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var zombies: Dictionary[int, ZombieBody] = {}
	for i in count:
		var zombie := ZombieBody.new()
		zombie.id = i + 1
		zombie.position = Vector3(rng.randf_range(-40, 40), 0.0, rng.randf_range(-40, 40))
		zombie.yaw = rng.randf_range(0.0, TAU)
		zombie.mode = ZombieBody.Mode.CHASE
		zombie.move_speed = 3.0
		zombies[zombie.id] = zombie
	return zombies


func _step(zombies: Dictionary[int, ZombieBody], rng: RandomNumberGenerator) -> void:
	for zombie: ZombieBody in zombies.values():
		if rng.randf() < 0.03:
			zombie.yaw += rng.randf_range(-0.6, 0.6)
		zombie.position += Vector3(-sin(zombie.yaw), 0.0, -cos(zombie.yaw)) * 3.0 * (1.0 / 30.0)


func test_the_deltas_give_the_same_zombies_in_far_fewer_bytes_for_100_zombies() -> void:
	var zombies := _walkers(100, 5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	var base: Dictionary[int, PackedByteArray] = {}
	var whole_bytes := 0
	var delta_bytes := 0
	for tick in TICKS:
		_step(zombies, rng)
		var next := ZombieDelta.entries_of(ZombieCodec.encode(zombies))
		var delta := ZombieDelta.diff(base, next, tick)
		var applied := ZombieDelta.apply(base, delta)
		assert_bool(applied["ok"]).is_true()
		base = applied["entries"]
		assert_array(ZombieDelta.whole(base)).is_equal(ZombieDelta.whole(next))
		if tick > 0:
			whole_bytes += ZombieCodec.encode(zombies).size()
			delta_bytes += delta.size()
	var per_tick_whole := whole_bytes / float(TICKS - 1)
	var per_tick_delta := delta_bytes / float(TICKS - 1)
	print(
		"100 walking zombies, bytes a tick (30 a second): whole ",
		snappedf(per_tick_whole, 1.0),
		", delta ",
		snappedf(per_tick_delta, 1.0)
	)
	# The first tick is the whole lot; after it a walker costs the flags and three steps.
	assert_float(per_tick_delta).is_less(per_tick_whole * 0.55)


func test_a_player_far_from_most_zombies_is_told_of_the_near_ones_only() -> void:
	var zombies := _walkers(100, 5)
	var all := ZombieDelta.entries_of(ZombieCodec.encode(zombies))
	var near: Dictionary[int, PackedByteArray] = {}
	for id: int in all:
		var at := Vector2(all[id].decode_s16(2), all[id].decode_s16(6)) / 100.0
		if at.length() <= 25.0:
			near[id] = all[id]
	var first := ZombieDelta.diff({}, near, 0)
	var everyone := ZombieDelta.diff({}, all, 0)
	print(
		"first delta, 100 zombies on an 80 m lot: everyone ",
		everyone.size(),
		" bytes, the ones within 25 m (",
		near.size(),
		") ",
		first.size()
	)
	assert_int(first.size()).is_less(everyone.size())
	# One walks away: it is a `gone`, two bytes.
	var left := near.duplicate()
	left.erase(near.keys()[0])
	assert_int(ZombieDelta.diff(near, left, 1).size()).is_equal(ZombieDelta.HEADER + 2)


func _entry(
	id: int, x := 0, y := 0, z := 0, yaw := 0, mode := 1, episode := 0, speed := 60, look := 0
) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(ZombieCodec.ENTRY_BYTES)
	bytes.encode_u16(0, id)
	bytes.encode_s16(2, x)
	bytes.encode_s16(4, y)
	bytes.encode_s16(6, z)
	bytes[8] = yaw
	bytes[9] = mode
	bytes[10] = episode
	bytes[11] = speed
	bytes[12] = look
	return bytes


func test_each_kind_of_change_costs_what_it_changed() -> void:
	var base: Dictionary[int, PackedByteArray] = {1: _entry(1, 100, 0, 100, 10, 1, 0, 60, 2)}
	var cases := {
		"moved a little": [_entry(1, 110, 0, 95, 10, 1, 0, 60, 2), 5 + 3 + 3],
		"moved far": [_entry(1, 900, 0, 100, 10, 1, 0, 60, 2), 5 + 3 + 6],
		"turned": [_entry(1, 100, 0, 100, 40, 1, 0, 60, 2), 5 + 3 + 1],
		"sped up": [_entry(1, 100, 0, 100, 10, 1, 0, 90, 2), 5 + 3 + 1],
		"began a swing": [_entry(1, 100, 0, 100, 10, 2, 1, 60, 2), 5 + 3 + 2],
		"lost a leg": [_entry(1, 100, 0, 100, 10, 1, 0, 60, 3), 5 + 3 + 1],
		"stood still": [_entry(1, 100, 0, 100, 10, 1, 0, 60, 2), 5],
	}
	for name: String in cases:
		var next: Dictionary[int, PackedByteArray] = {1: cases[name][0]}
		var delta := ZombieDelta.diff(base, next, 0)
		assert_int(delta.size()).override_failure_message(name).is_equal(cases[name][1])
		var applied := ZombieDelta.apply(base, delta)
		assert_array(applied["entries"][1]).override_failure_message(name).is_equal(cases[name][0])


func test_a_new_zombie_comes_whole_and_a_gone_one_leaves() -> void:
	var base: Dictionary[int, PackedByteArray] = {1: _entry(1), 2: _entry(2, 50, 0, 50)}
	var next: Dictionary[int, PackedByteArray] = {
		2: _entry(2, 50, 0, 50), 3: _entry(3, -300, 5, 700, 9, 2, 1, 80, 4)
	}
	var applied := ZombieDelta.apply(base, ZombieDelta.diff(base, next, 7))
	assert_bool(applied["ok"]).is_true()
	assert_array(applied["entries"].keys()).contains_exactly_in_any_order([2, 3])
	assert_array(applied["entries"][3]).is_equal(next[3])


func test_two_deltas_that_say_the_same_are_not_the_same_bytes() -> void:
	# `FrameDelta` leaves out a field that repeats: a delta that repeated would be lost.
	var base: Dictionary[int, PackedByteArray] = {1: _entry(1)}
	var next: Dictionary[int, PackedByteArray] = {1: _entry(1, 5)}
	assert_array(ZombieDelta.diff(base, next, 4)).is_not_equal(ZombieDelta.diff(base, next, 5))
	assert_int(ZombieDelta.diff(base, next, 260)[0]).is_equal(4)


func test_a_bad_delta_changes_nothing() -> void:
	var base: Dictionary[int, PackedByteArray] = {1: _entry(1, 10, 0, 10)}
	var good := ZombieDelta.diff(base, {1: _entry(1, 30, 0, 10)}, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for bad in [
		PackedByteArray(),
		good.slice(0, good.size() - 1),
		good + PackedByteArray([1]),
		# Says 999 changes and has none.
		PackedByteArray([0, 0xE7, 0x03, 0, 0]),
		# A step of an id the client does not have, without NEW.
		PackedByteArray([0, 1, 0, 0, 0, 77, 0, ZombieDelta.POSITION, 1, 1, 1]),
	]:
		var applied := ZombieDelta.apply(base, bad)
		assert_bool(applied["ok"]).is_false()
		assert_array(applied["entries"].keys()).is_equal([1])
		assert_array(applied["entries"][1]).is_equal(base[1])
	# Random bytes never crash it nor invent a zombie from nothing.
	for i in 200:
		var noise := PackedByteArray()
		noise.resize(rng.randi_range(0, 40))
		for at in noise.size():
			noise[at] = rng.randi() & 0xFF
		var applied := ZombieDelta.apply({}, noise)
		if not applied["ok"]:
			assert_int(applied["entries"].size()).is_equal(0)


func _frame(tick: int, zombies: PackedByteArray) -> Dictionary:
	var players := {}
	for id in [1, 2, 3, 4]:
		players[id] = {
			"pos": Vector3(id * 3.0 + tick * 0.05, 0.0, -10.0 + tick * 0.02),
			"facing": 0.1 * tick,
			"health": 100.0,
			"downed": false,
			"weapon": &"pistol",
			"ammo": 8,
			"reserve": 40,
			"reloading": false,
			"arms": {&"pistol": [8, 40], &"crowbar": [0, 0]},
			"points": 500,
			"prompt": {},
			"ack": tick,
		}
	return {
		"type": &"frame",
		"tick": tick,
		"phase": 1,
		"round": 5,
		"remaining": 60,
		"fuel": 80.0,
		"circuits": {&"main": true},
		"doors": [&"a", &"b"],
		"crane": {},
		"barricades": {&"north": 3, &"south": 5},
		"zombies": zombies,
		"players": players,
	}


func test_what_a_tick_to_one_of_four_players_costs_with_100_zombies() -> void:
	var zombies := _walkers(100, 5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	var base: Dictionary[int, PackedByteArray] = {}
	var before_whole := {}
	var before_delta := {}
	var whole_total := 0
	var delta_total := 0
	var sequence := 0
	for tick in 120:
		_step(zombies, rng)
		var codec := ZombieCodec.encode(zombies)
		var next := ZombieDelta.entries_of(codec)
		var delta_frame := _frame(tick, ZombieDelta.diff(base, next, sequence))
		sequence += 1
		base = next
		var whole_frame := _frame(tick, codec)
		var whole_tick := NetWire.tick(tick, [FrameDelta.diff(before_whole, whole_frame)])
		var delta_tick := NetWire.tick(tick, [FrameDelta.diff(before_delta, delta_frame)])
		before_whole = whole_frame
		before_delta = delta_frame
		if tick >= 20:
			whole_total += whole_tick.size()
			delta_total += delta_tick.size()
	var seconds := 100.0 / 30.0
	print(
		"a TICK to one client, 4 players and 100 walking zombies: whole ",
		snappedf(whole_total / 100.0, 1.0),
		" bytes (",
		snappedf(whole_total / seconds / 1000.0, 0.1),
		" KB/s), deltas ",
		snappedf(delta_total / 100.0, 1.0),
		" bytes (",
		snappedf(delta_total / seconds / 1000.0, 0.1),
		" KB/s)"
	)
	assert_int(delta_total).is_less(whole_total)
