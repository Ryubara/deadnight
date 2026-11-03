extends GdUnitTestSuite
## The second map's located wind follows the gust that is blowing (#809): the wind under the roof
## and the yard's four wind loops swell with `WindSounds.swell()`, the way the drive-in's base layer
## does, through `SmallMapSoundTuning`; the rooms' levels at rest and the yard's reach do not move.

const GREYBOX := preload("res://world/smallmap/smallmap_greybox.tscn")
const BACKDROP := preload("res://world/smallmap/backdrop.tscn")
const SETTLE_FRAMES := 4
const DT := 1.0 / 30.0
## What the roof wind's trim was before the gusts drove it (the rooms' levels are read from it).
const ROOF_TRIM_BEFORE_DB := -19.0
const START_EAR := Vector3(4.0, 1.6, 10.0)
const UPPER_B := Vector3(-3.0, 5.0, -4.0)
const UPPER_A := Vector3(8.0, 5.0, 2.0)
const FAR_AWAY := Vector3(900.0, 1.6, 900.0)
## How far a bed's fade may lag the swell it follows, and the swell's own step between two looks.
const LAG_DB := 0.6

var _ears: Node3D
var _greybox: Node3D
var _backdrop: Node3D
var _sounds: SmallMapSounds
var _wind: WindSounds
var _t := SmallMapSoundTuning.current()


func before_test() -> void:
	Audio.stop_all()
	Audio.seed_random(23)
	_ears = auto_free(Node3D.new())
	add_child(_ears)
	_ears.global_position = START_EAR
	Audio.listener = _ears


func after_test() -> void:
	Audio.listener = null
	Audio.stop_all()


## The map built, the sounds set up, and the night's wind (seed 6) running beside them.
func _start(with_wind := true) -> void:
	_greybox = auto_free(GREYBOX.instantiate())
	add_child(_greybox)
	_backdrop = auto_free(BACKDROP.instantiate())
	add_child(_backdrop)
	for _i in SETTLE_FRAMES:
		await get_tree().physics_frame
	_sounds = auto_free(SmallMapSounds.new())
	_sounds.set_process(false)
	add_child(_sounds)
	_sounds.setup(ClientState.new(), _greybox, _backdrop)
	if with_wind:
		_wind = auto_free(WindSounds.new())
		add_child(_wind)
		_wind.set_process(false)
		_wind.setup(6)
		_wind.start()
		_sounds.wind = _wind
	_step(0.5)


func _step(seconds: float) -> void:
	for _i in int(seconds / DT):
		if _wind != null:
			_wind.advance(DT)
		_sounds.advance(DT)
		Audio.advance(DT)


## Runs on until a gust is blowing (a night's first gust comes within a minute).
func _until_a_gust() -> void:
	var guard := 0
	while not _wind.is_blowing() and guard < 3000:
		_step(DT)
		guard += 1
	assert_bool(_wind.is_blowing()).is_true()


## The roof wind as heard now: its trim and its fade, dB.
func _roof_db() -> float:
	return SoundCatalog.get_def(&"bed_roof_wind").volume_db + Audio.bed_fade_db(&"bed_roof_wind")


## The level a room's roof wind had before the gusts drove it, dB.
func _roof_rest(room: StringName) -> float:
	return ROOF_TRIM_BEFORE_DB + _t.roof_db[room]


func _winds() -> Array[SmallMapYard.Source]:
	return _sounds.yard.source_of(&"yard_wind")


func test_the_roof_wind_rests_where_it_did_with_the_gust_in_the_raised_trim() -> void:
	await _start(false)
	_ears.global_position = UPPER_B
	_step(4.0)
	assert_float(_roof_db()).is_equal_approx(_roof_rest(&"UpperB"), 0.01)
	_ears.global_position = UPPER_A
	_step(4.0)
	assert_float(_roof_db()).is_equal_approx(_roof_rest(&"UpperA"), 0.01)
	assert_float(_t.roof_gust_db).is_less_equal(SmallMapSoundTuning.ROOF_HEADROOM_DB)
	# A bed cannot be raised over its own level: the fade stays at 0 or under at the gust's peak.
	(
		assert_float(_t.roof_db[&"UpperB"] - SmallMapSoundTuning.ROOF_HEADROOM_DB + _t.roof_gust_db)
		. is_less_equal(0.0)
	)


func test_the_roof_wind_swells_with_the_gust_and_comes_back_to_where_it_rested() -> void:
	await _start()
	_ears.global_position = UPPER_B
	# The bed fades up from silence first (20 dB a second).
	_step(4.0)
	var rest := _roof_rest(&"UpperB")
	var peak := -99.0
	var looked := 0
	for _i in 1500:
		_step(0.1)
		var swell := _wind.swell()
		var expected := rest + _t.roof_gust_db * swell
		assert_float(_roof_db()).is_between(expected - LAG_DB, expected + LAG_DB)
		assert_float(_roof_db()).is_greater_equal(rest - 0.01)
		peak = maxf(peak, _roof_db())
		looked += 1 if swell > 0.5 else 0
	assert_int(looked).is_greater(10)
	assert_float(peak).is_greater(rest + _t.roof_gust_db * 0.9)
	assert_float(peak).is_less_equal(rest + _t.roof_gust_db + 0.01)


func test_the_roof_wind_stays_silent_in_a_room_with_none_whatever_the_gust() -> void:
	await _start()
	_ears.global_position = START_EAR
	for _i in 600:
		_step(0.1)
		assert_bool(Audio.is_bed_running(&"bed_roof_wind")).is_false()


func test_the_yards_wind_loops_swell_with_the_gust_by_the_same_amount_each() -> void:
	await _start()
	_until_a_gust()
	var peak := 0.0
	var checked := 0
	for _i in 600:
		_step(0.1)
		var swell := _wind.swell()
		peak = maxf(peak, swell)
		for source in _winds():
			if source.player != null and source.player.playing:
				# At the window it comes in at, the way's level is what it was: only the gust is new.
				var rests := source.def.volume_db + source.way.extra_db
				if not Audio.filters_apply and source.way.kind != &"outside":
					rests += _t.no_filter_db
				assert_float(source.db - rests).is_between(
					_t.yard_gust_db * swell - LAG_DB, _t.yard_gust_db * swell + LAG_DB
				)
				checked += 1
	assert_int(checked).is_greater(500)
	assert_float(peak).is_greater(0.9)


func test_only_the_yards_wind_swells_and_nothing_swells_with_no_wind() -> void:
	await _start()
	_until_a_gust()
	_step(1.0)
	var checked := 0
	for source in _sounds.yard.sources:
		if source.id == SmallMapYard.WIND or source.way == null:
			continue
		checked += 1
		var rests := source.def.volume_db + source.way.extra_db
		if not Audio.filters_apply and source.way.kind != &"outside":
			rests += _t.no_filter_db
		assert_float(source.db).override_failure_message(source.id).is_equal_approx(rests, 0.01)
	assert_int(checked).is_greater(0)
	_wind.stop()
	_step(1.0)
	assert_float(_sounds.gust_swell()).is_equal(0.0)


func test_a_night_with_no_wind_leaves_the_roof_and_the_yard_as_they_rest() -> void:
	await _start(false)
	_ears.global_position = UPPER_B
	_step(4.0)
	assert_float(_sounds.gust_swell()).is_equal(0.0)
	assert_float(_roof_db()).is_equal_approx(_roof_rest(&"UpperB"), 0.01)


func test_a_gust_does_not_make_the_yard_carry_further() -> void:
	await _start()
	_ears.global_position = FAR_AWAY
	_until_a_gust()
	_step(3.0)
	for source in _sounds.yard.sources:
		assert_bool(source.player.playing).is_false()
		assert_float(source.player.max_distance).is_equal(source.def.max_distance)
