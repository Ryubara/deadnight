extends GdUnitTestSuite
## The grenades' sounds from the server's events: the throw, a cook's ticks that quicken with the
## fuse, the bounces (harder is louder) and the blast. The clock is stepped by hand.

const OWN := 1

var _heard: Array[Dictionary] = []
var _sounds: GrenadeSounds
var _state: ClientState


func before_test() -> void:
	_heard = []
	_state = ClientState.new()
	_state.player_id = OWN
	_sounds = auto_free(GrenadeSounds.new())
	_sounds.play = func(id: StringName, at: Variant, db: float) -> void:
		_heard.append({"id": id, "at": at, "db": db, "t": _sounds.schedule.now()})
	add_child(_sounds)
	_sounds.setup(_state)
	_state.apply_events(
		[{"type": &"frame", "players": {OWN: {"pos": Vector3(1, 0, 2)}}, "zombies": []}]
	)


func _tell(event: Dictionary) -> void:
	_state.apply_events([event])


func _times(id: StringName) -> Array[float]:
	var times: Array[float] = []
	for h in _heard:
		if h["id"] == id:
			times.append(h["t"])
	return times


func test_a_cook_ticks_faster_as_the_fuse_runs_down() -> void:
	_tell({"type": &"cook_started", "player_id": OWN, "seq": 1, "fuse": 3.0})
	_sounds.schedule.advance(3.0)
	var ticks := _times(&"grenade_tick")
	assert_int(ticks.size()).is_greater(8)
	var first_gap := ticks[1] - ticks[0]
	var last_gap := ticks[-1] - ticks[-2]
	assert_float(first_gap).is_equal_approx(NightSoundTuning.current().tick_gap_start, 0.06)
	assert_float(last_gap).is_less(first_gap * 0.5)
	# The gaps only ever shrink.
	for i in range(1, ticks.size() - 1):
		assert_float(ticks[i + 1] - ticks[i]).is_less_equal(ticks[i] - ticks[i - 1] + 0.001)


func test_the_throw_ends_the_ticking_and_sounds_where_the_grenade_left_the_hand() -> void:
	_tell({"type": &"cook_started", "player_id": OWN, "seq": 1, "fuse": 3.0})
	_sounds.schedule.advance(1.0)
	_tell(
		{
			"type": &"grenade_thrown",
			"grenade_id": 1,
			"thrower_id": OWN,
			"seq": 2,
			"position": Vector3(2, 1, 2),
			"velocity": Vector3.ZERO,
			"fuse_left": 2.0,
			"underarm": false,
			"cooked": true,
		}
	)
	var ticks := _times(&"grenade_tick").size()
	_sounds.schedule.advance(3.0)
	assert_int(_times(&"grenade_tick").size()).is_equal(ticks)
	var throws := _heard.filter(func(h: Dictionary) -> bool: return h["id"] == &"grenade_throw")
	assert_array(throws).has_size(1)
	assert_vector(throws[0]["at"]).is_equal(Vector3(2, 1, 2))


func test_a_harder_bounce_is_louder() -> void:
	_tell(
		{
			"type": &"grenade_bounced",
			"grenade_id": 1,
			"point": Vector3.ZERO,
			"speed": 2.0,
			"wall": false
		}
	)
	_tell(
		{
			"type": &"grenade_bounced",
			"grenade_id": 1,
			"point": Vector3.ZERO,
			"speed": 11.0,
			"wall": false
		}
	)
	assert_float(_heard[1]["db"]).is_greater(_heard[0]["db"] + 3.0)


func test_the_blast_sounds_where_it_goes_off() -> void:
	_tell(
		{
			"type": &"grenade_exploded",
			"grenade_id": 1,
			"thrower_id": OWN,
			"point": Vector3(8, 0, 8),
			"core_radius": 2.0,
			"radius": 6.0,
			"in_hand": false,
		}
	)
	assert_array(_heard).has_size(1)
	assert_str(_heard[0]["id"]).is_equal("grenade_blast")
	assert_vector(_heard[0]["at"]).is_equal(Vector3(8, 0, 8))


func test_the_tick_gap_runs_from_slow_to_fast() -> void:
	assert_float(GrenadeSounds.tick_gap(3.0, 3.0)).is_equal(
		NightSoundTuning.current().tick_gap_start
	)
	assert_float(GrenadeSounds.tick_gap(0.0, 3.0)).is_equal(NightSoundTuning.current().tick_gap_end)
