extends GdUnitTestSuite
## The grenades' sounds from the server's events: the throw, the fuse's beeps (from the hand, then
## from the grenade, quickening to the blast), the bounces (harder is louder) and the blast. The
## clock is stepped by hand.

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


func _thrown(
	id: int, fuse_left: float, at: Vector3 = Vector3(2, 1, 2), thrower: int = OWN
) -> Dictionary:
	return {
		"type": &"grenade_thrown",
		"grenade_id": id,
		"thrower_id": thrower,
		"seq": 2,
		"position": at,
		"velocity": Vector3.ZERO,
		"fuse_left": fuse_left,
		"underarm": false,
		"cooked": 3.0 - fuse_left,
	}


func _blast(id: int, at: Vector3 = Vector3(8, 0, 8)) -> Dictionary:
	return {
		"type": &"grenade_exploded",
		"grenade_id": id,
		"thrower_id": OWN,
		"point": at,
		"core_radius": 2.0,
		"radius": 6.0,
		"in_hand": false,
	}


func _gaps(beeps: Array[float]) -> Array[float]:
	var gaps: Array[float] = []
	for i in range(1, beeps.size()):
		gaps.append(beeps[i] - beeps[i - 1])
	return gaps


func test_a_cook_beeps_faster_as_the_fuse_runs_down() -> void:
	_tell({"type": &"cook_started", "player_id": OWN, "seq": 1, "fuse": 3.0})
	_sounds.schedule.advance(3.0)
	var beeps := _times(&"grenade_beep")
	assert_int(beeps.size()).is_greater(8)
	var gaps := _gaps(beeps)
	assert_float(gaps[0]).is_equal_approx(NightSoundTuning.current().beep_gap_start, 0.06)
	assert_float(gaps[-1]).is_less(gaps[0] * 0.5)
	# The gaps only ever shrink.
	for i in range(1, gaps.size()):
		assert_float(gaps[i]).is_less_equal(gaps[i - 1] + 0.001)


func test_the_beep_goes_on_from_the_grenade_after_the_throw_until_the_blast() -> void:
	_sounds.where_is = func(id: int) -> Variant: return Vector3(2 + id, 0.1, -5)
	_tell({"type": &"cook_started", "player_id": OWN, "seq": 1, "fuse": 3.0})
	_sounds.schedule.advance(1.0)
	var in_hand := _times(&"grenade_beep").size()
	_tell(_thrown(1, 2.0))
	_sounds.schedule.advance(1.99)
	_tell(_blast(1))
	var heard := _times(&"grenade_beep").size()
	_sounds.schedule.advance(3.0)
	assert_int(_times(&"grenade_beep").size()).is_equal(heard)
	assert_int(heard).is_greater(in_hand + 3)
	assert_int(_sounds.beeping()).is_equal(0)
	var beeps := _heard.filter(func(h: Dictionary) -> bool: return h["id"] == &"grenade_beep")
	assert_vector(beeps[-1]["at"]).is_equal(Vector3(3, 0.1, -5))
	assert_vector(beeps[in_hand - 1]["at"]).is_equal(Vector3(1, 1.4, 2))
	var throws := _heard.filter(func(h: Dictionary) -> bool: return h["id"] == &"grenade_throw")
	assert_array(throws).has_size(1)
	assert_vector(throws[0]["at"]).is_equal(Vector3(2, 1, 2))


func test_the_beat_does_not_stutter_at_the_throw() -> void:
	_tell({"type": &"cook_started", "player_id": OWN, "seq": 1, "fuse": 3.0})
	_sounds.schedule.advance(1.0)
	_tell(_thrown(1, 2.0))
	_sounds.schedule.advance(2.0)
	var beeps := _times(&"grenade_beep")
	var gaps := _gaps(beeps)
	for i in range(1, gaps.size()):
		assert_float(gaps[i]).is_less_equal(gaps[i - 1] + 0.001)
	assert_float(gaps[0]).is_greater(0.4)
	assert_float(gaps[-1]).is_less(0.15)


func test_a_whole_fuse_quickens_to_the_blast_and_swells() -> void:
	_tell({"type": &"cook_started", "player_id": OWN, "seq": 1, "fuse": 3.0})
	_sounds.schedule.advance(0.4)
	_tell(_thrown(1, 2.6))
	_sounds.schedule.advance(2.6)
	_tell(_blast(1))
	var beeps := _heard.filter(func(h: Dictionary) -> bool: return h["id"] == &"grenade_beep")
	var times: Array[float] = []
	for beep in beeps:
		times.append(beep["t"])
	var gaps := _gaps(times)
	var tuning := NightSoundTuning.current()
	assert_int(beeps.size()).is_between(12, 22)
	assert_float(gaps[0]).is_equal_approx(tuning.beep_gap_start, 0.03)
	assert_float(gaps[-1]).is_less_equal(tuning.beep_gap_end + 0.04)
	assert_float(beeps[-1]["db"]).is_greater(beeps[0]["db"] + 3.0)
	assert_float(times[-1]).is_less_equal(3.0)


func test_another_players_grenade_is_heard_from_the_grenade() -> void:
	var seen: Array[int] = []
	_sounds.where_is = func(id: int) -> Variant:
		seen.append(id)
		return Vector3(9, 0.1, 9)
	_tell(_thrown(4, 2.0, Vector3(5, 1, 5), 2))
	_sounds.schedule.advance(0.3)
	assert_array(seen).contains([4])
	var beeps := _heard.filter(func(h: Dictionary) -> bool: return h["id"] == &"grenade_beep")
	assert_array(beeps).is_not_empty()
	assert_vector(beeps[0]["at"]).is_equal(Vector3(9, 0.1, 9))


func test_two_grenades_in_the_air_beep_apart_and_one_blast_ends_only_its_own() -> void:
	_tell(_thrown(1, 2.0))
	_tell(_thrown(2, 2.0, Vector3(4, 1, 4), 2))
	_sounds.schedule.advance(0.1)
	assert_int(_sounds.beeping()).is_equal(2)
	_tell(_blast(1))
	assert_int(_sounds.beeping()).is_equal(1)


func test_a_refused_cook_is_silent() -> void:
	_tell({"type": &"cook_started", "player_id": OWN, "seq": 1, "fuse": 3.0})
	_tell({"type": &"cook_rejected", "player_id": OWN, "seq": 2, "reason": &"player_downed"})
	_sounds.schedule.advance(2.0)
	assert_int(_sounds.beeping()).is_equal(0)
	assert_int(_times(&"grenade_beep").size()).is_less_equal(1)


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


func test_the_beep_gap_runs_from_slow_to_fast() -> void:
	assert_float(GrenadeSounds.beep_gap(3.0, 3.0)).is_equal(
		NightSoundTuning.current().beep_gap_start
	)
	assert_float(GrenadeSounds.beep_gap(0.0, 3.0)).is_equal(NightSoundTuning.current().beep_gap_end)
