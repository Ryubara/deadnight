extends GdUnitTestSuite
## The loudest a close sound gets leaves room for a gun shot (#753). The engine boosts a 3D sound
## as it comes close and stops it at the player's `max_db`, so right beside the listener a sound's
## level is its trim and cap (`volume_db + near_cap_db`, or the engine's +3 dB with no cap),
## whatever the distance. The player's own gun peaks no closer to full scale than the guns' table
## says (`test_gun_audio_rules.gd`), so the sound may peak at most what is left under -1 dBFS when
## the two peaks land together (amplitudes add). No bus limiter does this: the web build ignores
## bus effects (`docs/research/gun-audio.md`). The peaks are measured, not computed: how much of a
## file's peak survives the distance filter and the pan depends on the sound (a voice keeps all of
## it, a 70 ms click loses 10 dB), so `tools/audio/close_levels.py` reads a recording of
## `tests/captures/audio_headroom.tscn --own=none --cells=zombie,world --all-variants --close` and
## writes `close_sound_levels.json`; this test fails when a cap or a trim is changed without
## measuring again, and when a measured peak leaves no room.

const HEADROOM := preload("res://tests/captures/audio_headroom.gd")
const GUN_TABLE := "res://tests/night/gun_levels.json"
const TABLE := "res://tests/core/close_sound_levels.json"
const CEILING_DBFS := -1.0
## A recording cannot show a sound louder than its file at its ceiling; this much over (the pitch
## draw resamples a file, which can lift a peak between its samples) is allowed before a row is
## called invented.
const RESAMPLING_DB := 1.0
## The decode rate; the highest sample of a file does not depend on it to within a fraction of a dB.
const RATE := 48000
const SLOW_GUNS: Array[String] = ["flare_gun"]

var _table: Dictionary
var _close_ids: Array[StringName] = []


func before_test() -> void:
	_table = JSON.parse_string(FileAccess.get_file_as_string(TABLE))["sounds"]
	_close_ids.clear()
	_close_ids.append_array(HEADROOM.ZOMBIE_SOUNDS)
	_close_ids.append_array(HEADROOM.WORLD_SOUNDS)


## The most a close sound may peak at, dBFS: what is left under the ceiling beside the loudest gun
## that fires without a break, at its own peak.
func _room_dbfs() -> float:
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GUN_TABLE))
	var loudest := -INF
	for weapon: String in table["guns"]:
		if weapon not in SLOW_GUNS:
			loudest = maxf(loudest, float(table["guns"][weapon]["peak_dbfs"]))
	return linear_to_db(db_to_linear(CEILING_DBFS) - db_to_linear(loudest))


## The level a sound is held to close up, dB over its file: what `AudioService.cap_near_level` sets.
func _ceiling_db(def: SoundDef) -> float:
	if def.near_cap_db < INF:
		return def.volume_db + def.near_cap_db
	return AudioService.ENGINE_MAX_DB


## The highest sample of a decoded file, dBFS.
func _file_peak_dbfs(path: String) -> float:
	var ogg := load(path) as AudioStream
	var playback := ogg.instantiate_playback()
	playback.start(0.0)
	var frames: PackedVector2Array = playback.mix_audio(
		1.0, ceili(ogg.get_length() * RATE) + RATE / 20
	)
	var peak := 0.0
	for frame in frames:
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	return linear_to_db(peak)


func test_the_room_is_what_the_loudest_gun_at_its_peak_leaves() -> void:
	# A gun at -4.9 dBFS is 0.57 of full scale; the sum may reach 0.89 (-1 dBFS), which leaves 0.32.
	var room := _room_dbfs()
	assert_float(room).is_between(-10.5, -8.5)
	assert_float(db_to_linear(room) + db_to_linear(-4.9)).is_less_equal(db_to_linear(-0.9))


func test_every_close_sound_of_the_capture_has_a_measured_row() -> void:
	assert_array(_close_ids).is_not_empty()
	for id in _close_ids:
		assert_object(SoundCatalog.get_def(id)).override_failure_message(String(id)).is_not_null()
		(
			assert_bool(_table.has(String(id)))
			. override_failure_message("%s has no row in %s: measure it" % [id, TABLE])
			. is_true()
		)


func test_the_measured_ceilings_are_of_the_caps_the_catalog_has() -> void:
	for id in _close_ids:
		var def := SoundCatalog.get_def(id)
		var row: Dictionary = _table[String(id)]
		(
			assert_float(_ceiling_db(def))
			. override_failure_message(
				(
					"%s is held to %.1f dB now, measured at %.1f: measure again"
					% [id, _ceiling_db(def), row["max_db"]]
				)
			)
			. is_equal_approx(float(row["max_db"]), 0.05)
		)


func test_every_close_sound_leaves_room_for_a_gun_shot() -> void:
	var room := _room_dbfs()
	for id in _close_ids:
		var row: Dictionary = _table[String(id)]
		(
			assert_float(float(row["close_peak_dbfs"]))
			. override_failure_message(
				(
					"%s peaks at %.1f dBFS close up, over the %.1f that leaves room: lower near_cap_db"
					% [id, row["close_peak_dbfs"], room]
				)
			)
			. is_less_equal(room + 0.05)
		)


func test_a_measured_peak_is_no_louder_than_the_loudest_file_at_its_ceiling() -> void:
	for id in _close_ids:
		var def := SoundCatalog.get_def(id)
		var loudest := -INF
		for variant in range(1, def.variants + 1):
			loudest = maxf(loudest, _file_peak_dbfs(def.path_for(variant)))
		var possible := loudest + _ceiling_db(def) + RESAMPLING_DB
		(
			assert_float(float(_table[String(id)]["close_peak_dbfs"]))
			. override_failure_message(
				(
					"%s measured at %.1f dBFS, yet its loudest file at its ceiling gives %.1f"
					% [id, _table[String(id)]["close_peak_dbfs"], possible]
				)
			)
			. is_less_equal(possible)
		)
