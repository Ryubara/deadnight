extends GdUnitTestSuite
## The drive-in's wind (#782): a quiet base layer and gusts that differ in length, level and gap
## from a seeded draw, that start and stop with the night like the other beds, and that are played
## sounds (so the browser, which ignores bus effects, has them too).

const BASE := &"bed_wind"
const DT := 1.0 / 30.0

var _ears: Node3D
var _heard: Array[Dictionary] = []


func before_test() -> void:
	Audio.stop_all()
	Audio.seed_random(21)
	_heard = []
	Audio.played.connect(_on_played)
	_ears = auto_free(Node3D.new())
	add_child(_ears)
	Audio.listener = _ears


func after_test() -> void:
	Audio.played.disconnect(_on_played)
	Audio.listener = null
	Audio.stop_all()


func _on_played(id: StringName, position: Variant) -> void:
	_heard.append({"id": id, "at": position})


func _wind(seed_value: int) -> WindSounds:
	var wind: WindSounds = auto_free(WindSounds.new())
	add_child(wind)
	wind.set_process(false)
	wind.setup(seed_value)
	wind.start()
	return wind


## Runs the wind and the audio service on `seconds` of game time.
func _run(wind: WindSounds, seconds: float) -> void:
	for _i in int(seconds / DT):
		Audio.advance(DT)
		wind.advance(DT)


func _gusts(plan: WindPlan, count: int) -> Array[Dictionary]:
	var gusts: Array[Dictionary] = []
	for _i in count:
		gusts.append(plan.next_gust())
	return gusts


func _spread(values: Array) -> float:
	return (values.max() as float) - (values.min() as float)


func test_a_seed_draws_the_same_night_every_time() -> void:
	var a := _gusts(WindPlan.new(7), 40)
	var b := _gusts(WindPlan.new(7), 40)
	var other := _gusts(WindPlan.new(8), 40)
	assert_array(a).is_equal(b)
	assert_array(a).is_not_equal(other)


func test_gusts_differ_in_level_gap_side_and_drift() -> void:
	var gusts := _gusts(WindPlan.new(11), 80)
	var lulls: Array = gusts.map(func(g: Dictionary) -> float: return g["lull"])
	var levels: Array = gusts.map(func(g: Dictionary) -> float: return g["db"])
	var bearings: Array = gusts.map(func(g: Dictionary) -> float: return g["bearing"])
	var drifts: Array = gusts.map(func(g: Dictionary) -> float: return g["drift"])
	assert_float(_spread(lulls)).is_greater(25.0)
	assert_float(_spread(levels)).is_greater(3.0)
	assert_float(_spread(bearings)).is_greater(4.0)
	assert_float(_spread(drifts)).is_greater(0.15)
	# Never two the same: every draw of a field differs from the one before it.
	for i in range(1, gusts.size()):
		assert_float(gusts[i]["lull"]).is_not_equal(gusts[i - 1]["lull"])
		assert_float(gusts[i]["db"]).is_not_equal(gusts[i - 1]["db"])


func test_a_gust_never_comes_before_the_lull_or_after_the_long_lull() -> void:
	var plan := WindPlan.new(3)
	for gust in _gusts(plan, 200):
		assert_float(gust["lull"]).is_greater_equal(WindPlan.LULL_S.x * plan.calm)
		assert_float(gust["lull"]).is_less_equal(WindPlan.LONG_LULL_S.y * plan.calm)
		assert_float(gust["db"]).is_between(
			WindPlan.GUST_DB.x + plan.breeze_db, WindPlan.GUST_DB.y + plan.breeze_db
		)
		assert_float(gust["metres"]).is_between(WindPlan.GUST_M.x, WindPlan.GUST_M.y)


func test_most_lulls_are_short_and_now_and_then_one_is_long() -> void:
	var plan := WindPlan.new(5)
	var lulls: Array = _gusts(plan, 400).map(func(g: Dictionary) -> float: return g["lull"])
	var long := lulls.filter(func(l: float) -> bool: return l >= WindPlan.LONG_LULL_S.x * plan.calm)
	assert_int(long.size()).is_between(20, 80)
	var short := lulls.filter(func(l: float) -> bool: return l <= 12.0 * plan.calm)
	assert_int(short.size()).is_greater(lulls.size() / 3)


func test_each_night_has_its_own_character() -> void:
	var calms := []
	var breezes := []
	for night_seed in 30:
		var plan := WindPlan.new(night_seed)
		calms.append(plan.calm)
		breezes.append(plan.breeze_db)
	assert_float(_spread(calms)).is_greater(0.4)
	assert_float(_spread(breezes)).is_greater(2.0)
	assert_float(calms.min()).is_greater_equal(WindPlan.CALM.x)
	assert_float(calms.max()).is_less_equal(WindPlan.CALM.y)


func test_details_are_rare_and_ride_on_the_stronger_gusts() -> void:
	var plan := WindPlan.new(9)
	var gusts := _gusts(plan, 400)
	var details := gusts.filter(func(g: Dictionary) -> bool: return g["detail"] != &"")
	assert_int(details.size()).is_between(25, 80)
	var kinds := {}
	for gust in details:
		kinds[gust["detail"]] = true
		assert_float(gust["db"]).is_greater_equal(WindPlan.DETAIL_MIN_DB + plan.breeze_db)
		assert_array(WindPlan.DETAILS).contains([gust["detail"]])
	assert_int(kinds.size()).is_equal(WindPlan.DETAILS.size())


func test_the_base_layer_wanders_within_its_range() -> void:
	var plan := WindPlan.new(2)
	var seen := []
	for _i in 600:
		seen.append(plan.walk_base())
	assert_float(seen.min()).is_greater_equal(WindPlan.WALK_DB.x)
	assert_float(seen.max()).is_less_equal(WindPlan.WALK_DB.y)
	assert_float(_spread(seen)).is_greater(1.0)


func test_the_gust_files_differ_in_length() -> void:
	var def := SoundCatalog.get_def(WindSounds.GUST)
	assert_int(def.variants).is_equal(8)
	var lengths := []
	for i in def.variants:
		lengths.append((load(def.path_for(i + 1)) as AudioStream).get_length())
	assert_float(_spread(lengths)).is_greater(6.0)
	assert_float(lengths.min()).is_less(4.0)
	assert_float(lengths.max()).is_greater(10.0)


func test_the_wind_runs_as_sounds_and_a_bed_not_as_a_bus_effect() -> void:
	var wind := _wind(4)
	_run(wind, 60.0)
	assert_bool(Audio.is_bed_running(BASE)).is_true()
	assert_str(SoundCatalog.get_def(BASE).bus).is_equal("Ambience")
	assert_str(SoundCatalog.get_def(WindSounds.GUST).bus).is_equal("Ambience")
	(
		assert_bool(_heard.any(func(h: Dictionary) -> bool: return h["id"] == WindSounds.GUST))
		. is_true()
	)
	var effects := AudioServer.get_bus_effect_count(AudioServer.get_bus_index("Ambience"))
	assert_int(effects).is_equal(0)


func test_two_minutes_of_wind_play_gusts_that_never_overlap_and_never_repeat() -> void:
	var wind := _wind(6)
	_run(wind, 240.0)
	var gusts := wind.played
	assert_int(gusts.size()).is_between(5, 40)
	var lengths := gusts.map(func(g: Dictionary) -> float: return g["length"])
	assert_float(_spread(lengths)).is_greater(3.0)
	for i in range(1, gusts.size()):
		var gap: float = gusts[i]["at"] - (gusts[i - 1]["at"] + gusts[i - 1]["length"])
		assert_float(gap).is_greater_equal(WindPlan.LULL_S.x * wind.plan.calm - 2.0 * DT)
		assert_str(gusts[i]["file"]).is_not_empty()
	var files := {}
	for gust in gusts:
		files[gust["file"]] = true
	assert_int(files.size()).is_greater(2)


func test_the_same_seed_replays_the_same_gusts_and_another_does_not() -> void:
	var first := _wind(12)
	Audio.seed_random(21)
	_run(first, 120.0)
	var times := first.played.map(func(g: Dictionary) -> float: return g["at"])
	first.stop()
	var again := _wind(12)
	Audio.seed_random(21)
	_run(again, 120.0)
	assert_array(again.played.map(func(g: Dictionary) -> float: return g["at"])).is_equal(times)
	var other := _wind(13)
	Audio.seed_random(21)
	_run(other, 120.0)
	assert_array(other.played.map(func(g: Dictionary) -> float: return g["at"])).is_not_equal(times)


func test_a_gust_blows_round_the_listener_and_follows_it() -> void:
	var wind := _wind(6)
	_ears.global_position = Vector3(40.0, 0.0, 0.0)
	var guard := 0
	while not wind.is_blowing() and guard < 20000:
		Audio.advance(DT)
		wind.advance(DT)
		guard += 1
	assert_bool(wind.is_blowing()).is_true()
	_ears.global_position = Vector3(-60.0, 0.0, 25.0)
	wind.advance(DT)
	var player := wind._gust["player"] as AudioStreamPlayer3D
	var away := player.global_position.distance_to(_ears.global_position)
	assert_float(away).is_between(WindPlan.GUST_M.x - 1.0, WindPlan.GUST_M.y + 3.0)


func test_the_base_layer_swells_with_a_gust() -> void:
	var wind := _wind(6)
	var calm_level := -99.0
	var swelled := -99.0
	for _i in 6000:
		Audio.advance(DT)
		wind.advance(DT)
		if not wind.is_blowing():
			calm_level = maxf(calm_level, Audio.bed_fade_db(BASE)) if _i > 150 else calm_level
		else:
			swelled = maxf(swelled, Audio.bed_fade_db(BASE))
	assert_float(swelled).is_greater(calm_level + 0.5)
	assert_float(swelled).is_less_equal(0.0)


func test_stopping_the_wind_ends_its_gusts_and_fades_the_base() -> void:
	var wind := _wind(6)
	_run(wind, 30.0)
	var count := wind.played.size()
	wind.stop()
	_run(wind, 120.0)
	assert_int(wind.played.size()).is_equal(count)
	assert_bool(Audio.is_bed_running(BASE)).is_false()
	assert_bool(wind.is_blowing()).is_false()


func test_the_night_starts_the_wind_and_the_end_of_the_night_stops_it() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 5)
	var wind := night.view.sounds.wind
	assert_object(wind).is_not_null()
	assert_bool(wind.is_running()).is_true()
	assert_bool(Audio.is_bed_running(BASE)).is_true()
	night.state.apply_events([{"type": &"game_over", "reason": &"all_down", "round_reached": 3}])
	Audio.advance(3.0)
	assert_bool(wind.is_running()).is_false()
	assert_bool(Audio.is_bed_running(BASE)).is_false()


func test_leaving_the_night_leaves_no_wind_playing() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 5)
	Audio.advance(4.0)
	assert_bool(Audio.is_bed_running(BASE)).is_true()
	night.free()
	Audio.advance(3.0)
	assert_bool(Audio.is_bed_running(BASE)).is_false()


func test_wind_is_a_bed_among_the_beds_and_a_group_with_a_limit() -> void:
	assert_bool(SoundCatalog.get_def(BASE).loop).is_true()
	assert_str(SoundCatalog.get_def(BASE).group).is_equal("bed")
	assert_int(SoundCatalog.group_limits()[&"wind"]).is_greater(1)
	for id: StringName in [WindSounds.GUST, &"wind_creak", &"wind_rattle", &"wind_flap"]:
		assert_str(SoundCatalog.get_def(id).group).is_equal("wind")
		assert_bool(SoundCatalog.get_def(id).loop).is_false()
