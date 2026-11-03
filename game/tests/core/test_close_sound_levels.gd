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
## The night's beds in LUFS (`docs/research/gun-audio.md`), what a loudest 400 ms is read against.
const BEDS_LUFS := -35.3
## The sounds whose files are limited in their recipe (`tools/audio/limiter.py`, #762): a crack
## 20 dB over its body left them 5 to 10 LU over the beds once held under the room (-9.8 dBFS).
const SHARP_SOUNDS: Array[StringName] = [
	&"board_tear", &"board_last", &"board_repair", &"door_open", &"debris_clear"
]
## At least this many LU over the beds in the loudest 400 ms, 1.2 m from the listener (5 to 10
## before the limiter, 10.4 to 13.7 now; the dead's voices are 13 to 20).
const SHARP_MIN_LU_OVER_BEDS := 10.0
## The most a sharp file's highest sample may be over its loudest 400 ms (RMS), dB: the files were
## 15 to 23 before the limiter, and are 12.6 to 16.6 now.
const SHARP_MAX_CREST_DB := 17.5
## A loudness window, seconds (the momentary loudness of EBU R128).
const LOUD_WINDOW := 0.4

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


## A file decoded to frames at `RATE`.
func _decode(path: String) -> PackedVector2Array:
	var ogg := load(path) as AudioStream
	var playback := ogg.instantiate_playback()
	playback.start(0.0)
	return playback.mix_audio(1.0, ceili(ogg.get_length() * RATE) + RATE / 20)


## The highest sample of a decoded file, dBFS.
func _file_peak_dbfs(path: String) -> float:
	var peak := 0.0
	for frame in _decode(path):
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	return linear_to_db(peak)


## How far a file's highest sample is over its loudest 400 ms (RMS), dB.
func _file_crest_db(path: String) -> float:
	var frames := _decode(path)
	var window := mini(frames.size(), int(LOUD_WINDOW * RATE))
	var sums := PackedFloat64Array()
	sums.resize(frames.size() + 1)
	var peak := 0.0
	for i in frames.size():
		var f := frames[i]
		peak = maxf(peak, maxf(absf(f.x), absf(f.y)))
		sums[i + 1] = sums[i] + 0.5 * (f.x * f.x + f.y * f.y)
	var loudest := 0.0
	for i in range(window, frames.size() + 1):
		loudest = maxf(loudest, sums[i] - sums[i - window])
	return linear_to_db(peak) - 10.0 * log(loudest / window) / log(10.0)


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


func test_the_sharp_sounds_have_a_limited_crack_in_their_files() -> void:
	for id in SHARP_SOUNDS:
		var def := SoundCatalog.get_def(id)
		for variant in range(1, def.variants + 1):
			var crest := _file_crest_db(def.path_for(variant))
			(
				assert_float(crest)
				. override_failure_message(
					(
						"%s file %d has its highest sample %.1f dB over its loudest 400 ms: limit it in its recipe"
						% [id, variant, crest]
					)
				)
				. is_less_equal(SHARP_MAX_CREST_DB)
			)


func test_the_sharp_sounds_stay_over_the_beds_close_up() -> void:
	for id in SHARP_SOUNDS:
		var over: float = float(_table[String(id)]["close_lufs"]) - BEDS_LUFS
		(
			assert_float(over)
			. override_failure_message(
				(
					"%s is %.1f LU over the beds in its loudest 400 ms close up, under %.1f"
					% [id, over, SHARP_MIN_LU_OVER_BEDS]
				)
			)
			. is_greater_equal(SHARP_MIN_LU_OVER_BEDS)
		)


func test_a_board_torn_is_the_loudest_of_the_boards_close_up() -> void:
	# As it was when #753 took the peaks down: the torn board over the last one over the hammered one.
	var tear: float = _table["board_tear"]["close_lufs"]
	assert_float(tear).is_greater(float(_table["board_last"]["close_lufs"]))
	assert_float(tear).is_greater(float(_table["board_repair"]["close_lufs"]))
