extends GdUnitTestSuite
## The rules the energy weapons and the re-cut layer keep (#791, `docs/research/gun-audio.md`):
## the firearms' rules (a shot is over the night's beds, peaks no closer to full scale than the
## headroom allows, no bus effect is relied on) hold for the ray gun and the freeze gun, a re-cut
## weapon's shot with the layer on it still keeps them, the layer is heard (it rings in the tail
## and in the bright band) and the close sounds of the freeze and the burst leave room for a shot.
## The numbers are measured on a recording of the game (`tools/audio/energy_levels.py` writes
## `energy_levels.json` from `tools/bench/audio_energy_bench.tscn`); this test fails when a trim or
## a file changed without measuring again.

const TABLE := "res://tests/night/energy_levels.json"
const GUN_TABLE := "res://tests/night/gun_levels.json"
const FILES := "res://assets/audio/energy/"
## The firearms' rules (`test_gun_audio_rules.gd`).
const MIN_SHOT_ABOVE_BEDS_LU := 14.0
const MIN_BURST_ABOVE_BEDS_LU := 17.0
const MAX_PEAK_DBFS := -4.5
const CEILING_DBFS := -1.0
## The layer is heard when the 2 to 8 kHz band of the tail of a re-cut shot (0.08 to 0.5 s after
## the report) holds this much more energy than the plain shot's: the shared layer rings there. The
## wonder weapons' own shots fill that band, so their layer rings lower, and is heard when the 250
## to 500 Hz band is this much higher.
const MIN_BRIGHT_ADDED_DB := 8.0
const MIN_DEEP_ADDED_DB := 5.0
## The layer takes at most this much of the shot's headroom: its own peak adds to the report's.
const MAX_PEAK_ADDED_DB := 1.5
const WONDER: Array[String] = ["ray_gun", "freeze_gun"]
const ENERGY: Array[String] = ["ray_gun", "freeze_gun"]

var _table: Dictionary


func before_test() -> void:
	_table = JSON.parse_string(FileAccess.get_file_as_string(TABLE))


func _file_sha(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	var bytes := file.get_buffer(file.get_length())
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func test_the_energy_weapons_are_a_shot_over_the_beds() -> void:
	for weapon in ENERGY:
		var row: Dictionary = _table["slots"][weapon]
		var beds: float = _table["bed_lufs"]
		(
			assert_float(float(row["single_momentary_lufs"]) - beds)
			. override_failure_message(
				"%s: one shot is under %.0f LU over the beds" % [weapon, MIN_SHOT_ABOVE_BEDS_LU]
			)
			. is_greater_equal(MIN_SHOT_ABOVE_BEDS_LU)
		)
		(
			assert_float(float(row["burst_lufs"]) - beds)
			. override_failure_message(
				"%s: a burst is under %.0f LU over the beds" % [weapon, MIN_BURST_ABOVE_BEDS_LU]
			)
			. is_greater_equal(MIN_BURST_ABOVE_BEDS_LU)
		)


func test_every_slot_leaves_the_headroom_the_firearms_leave() -> void:
	for slot: String in _table["slots"]:
		(
			assert_float(float(_table["slots"][slot]["peak_dbfs"]))
			. override_failure_message("%s peaks too close to full scale" % slot)
			. is_less_equal(MAX_PEAK_DBFS)
		)


func test_the_layer_takes_next_to_none_of_the_headroom_and_is_heard() -> void:
	assert_array(_table["recut"].keys()).is_not_empty()
	for weapon: String in _table["recut"]:
		var row: Dictionary = _table["recut"][weapon]
		for key in ["single_peak_added_db", "burst_peak_added_db"]:
			(
				assert_float(float(row[key]))
				. override_failure_message("%s: the layer lifts the %s" % [weapon, key])
				. is_less_equal(MAX_PEAK_ADDED_DB)
			)
		var heard: float = float(
			row["deep_added_db"] if weapon in WONDER else row["bright_added_db"]
		)
		var needed := MIN_DEEP_ADDED_DB if weapon in WONDER else MIN_BRIGHT_ADDED_DB
		(
			assert_float(heard)
			. override_failure_message(
				"%s: the layer is not heard (%.1f dB, wants %.1f)" % [weapon, heard, needed]
			)
			. is_greater_equal(needed)
		)


func test_the_trims_and_files_are_the_ones_that_were_measured() -> void:
	for slot: String in _table["slots"]:
		var row: Dictionary = _table["slots"][slot]
		for id: String in row["trims_db"]:
			var def := SoundCatalog.get_def(StringName(id))
			assert_object(def).override_failure_message("no sound " + id).is_not_null()
			(
				assert_float(def.volume_db)
				. override_failure_message(
					"%s: trim %.2f, measured at %.2f" % [id, def.volume_db, row["trims_db"][id]]
				)
				. is_equal_approx(float(row["trims_db"][id]), 0.01)
			)
		for file: String in row["files_sha256"]:
			(
				assert_str(_file_sha(FILES + file))
				. override_failure_message("%s changed since it was measured" % file)
				. is_equal(row["files_sha256"][file])
			)


func _room_dbfs() -> float:
	var guns: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GUN_TABLE))["guns"]
	var loudest := -INF
	for weapon: String in guns:
		if weapon != "flare_gun":
			loudest = maxf(loudest, float(guns[weapon]["peak_dbfs"]))
	for weapon in ENERGY:
		loudest = maxf(loudest, float(_table["slots"][weapon]["peak_dbfs"]))
	return linear_to_db(db_to_linear(CEILING_DBFS) - db_to_linear(loudest))


func test_the_close_sounds_leave_room_for_a_shot() -> void:
	# The sound's highest sample beside the listener plus the loudest gun's peak stays under
	# -1 dBFS when the two land together (amplitudes add): the rule of the dead's voices.
	var room := _room_dbfs()
	assert_dict(_table["close"]).is_not_empty()
	for id: String in _table["close"]:
		var row: Dictionary = _table["close"][id]
		(
			assert_float(float(row["close_peak_dbfs"]))
			. override_failure_message(
				"%s peaks at %.1f dBFS close up, room is %.1f" % [id, row["close_peak_dbfs"], room]
			)
			. is_less_equal(room)
		)
		var def := SoundCatalog.get_def(StringName(id))
		var ceiling := (
			def.volume_db + def.near_cap_db if def.near_cap_db < INF else AudioService.ENGINE_MAX_DB
		)
		(
			assert_float(ceiling)
			. override_failure_message("%s: its cap moved since it was measured" % id)
			. is_equal_approx(float(row["max_db"]), 0.15)
		)


func test_the_close_sounds_are_a_rule_for_every_sound_of_the_freeze_and_the_burst() -> void:
	for id: StringName in [
		&"burst_ray", &"freeze_hit", &"freeze_creak", &"freeze_thaw", &"freeze_shatter"
	]:
		(
			assert_bool(_table["close"].has(String(id)))
			. override_failure_message("%s was not measured" % id)
			. is_true()
		)
