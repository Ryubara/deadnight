extends GdUnitTestSuite
## The menu's sounds sit where the table says (#894): every sound of `UiSoundTable` has a target in
## `menu_sound_levels.json`, and the level a player hears it at (the file's own peak, decoded, plus
## the bank's trim, the row's trim and the UI bus at its default) is within a dB or two of it, in
## every variant file. The weights are a ladder (each rung's median at least `LADDER_STEP_DB`
## over the one below), nothing clips and no menu sound peaks over -10 dBFS (a pistol shot in
## the night is -8.6). The recording of the real service (`tools/audio/menu_levels.py levels`,
## from `tests/captures/audio_menu_levels.tscn`) reads the same file, and agreed with this
## prediction within a tenth of a dB when the numbers were set. Also what the menu's sounds
## cost to load: the bank is deferred (the night's loading bar only queues it) and small.

const TARGETS := "res://tests/core/menu_sound_levels.json"
const RATE := 48000
## The Ogg's decode and the random pitch can lift a file's peak a little.
const VARIANT_TOLERANCE_DB := 2.5
const MEAN_TOLERANCE_DB := 1.5
const LADDER_STEP_DB := 3.0
const LOUDEST_DBFS := -10.0
## What the menu's sounds may weigh: seconds of sound decoded, and bytes of files.
const MAX_SECONDS := 8.0
const MAX_BYTES := 230 * 1024
const BANK := "res://core/audio/banks/ui_menu.tres"


func _targets() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(TARGETS))


## The peak of a file as the service plays it (decoded to samples), in dBFS.
func _file_peak_db(path: String) -> float:
	var wav := PcmStream.decode(load(path) as AudioStream, RATE)
	var peak := 0
	for i in range(0, wav.data.size() - 1, 2):
		peak = maxi(peak, absi(wav.data.decode_s16(i)))
	return linear_to_db(float(peak) / PcmStream.PEAK)


## The table's distinct (sound, trim) rows: "ui_press|-2.0" to the sound and the trim.
func _rows() -> Dictionary:
	var rows := {}
	for role: StringName in UiSoundTable.ROLES:
		for cue: StringName in UiSoundTable.ROLES[role]:
			var row: Dictionary = UiSoundTable.ROLES[role][cue]
			if not UiSoundTable.is_silent(row):
				var trim := float(row.get("db", 0.0))
				rows["%s|%s" % [row["sound"], trim]] = [row["sound"], trim]
	return rows


## What a play of this row peaks at in the Master mix at the default settings, per variant file.
func _predicted(sound: StringName, trim: float) -> Array[float]:
	var def := SoundCatalog.get_def(sound)
	var percent := float(SettingsService.DEFAULTS[SettingsService.VOLUME_UI])
	var bus_db := linear_to_db(percent / 100.0)
	var out: Array[float] = []
	for variant in range(1, def.variants + 1):
		out.append(_file_peak_db(def.path_for(variant)) + def.volume_db + trim + bus_db)
	return out


func test_every_sound_of_the_table_has_a_target_and_sits_on_it() -> void:
	var targets := _targets()
	var rows := _rows()
	var lines := PackedStringArray()
	for key: String in rows:
		if not targets.has(key):
			lines.append("%s has no target" % key)
			continue
		var row: Array = rows[key]
		var target := float(targets[key]["target_dbfs"])
		var peaks := _predicted(row[0], row[1])
		var mean := 0.0
		for peak in peaks:
			mean += peak / peaks.size()
			if absf(peak - target) > VARIANT_TOLERANCE_DB:
				lines.append("%s: a variant peaks at %.1f, target %.1f" % [key, peak, target])
		if absf(mean - target) > MEAN_TOLERANCE_DB:
			lines.append("%s: mean %.1f dBFS, target %.1f" % [key, mean, target])
	for key: String in targets:
		if not rows.has(key):
			lines.append("%s is a target no row of the table plays" % key)
	assert_array(Array(lines)).is_empty()


func test_the_weights_are_a_ladder_and_the_menu_stays_under_the_night() -> void:
	var targets := _targets()
	var rows := _rows()
	var by_rung := {}
	var loudest := -200.0
	for key: String in rows:
		var row: Array = rows[key]
		var rung := int(targets[key]["rung"])
		var peaks := _predicted(row[0], row[1])
		var mean := 0.0
		for peak in peaks:
			mean += peak / peaks.size()
			loudest = maxf(loudest, peak)
		if not by_rung.has(rung):
			by_rung[rung] = []
		by_rung[rung].append(mean)
	var medians := {}
	for rung: int in by_rung:
		var values: Array = by_rung[rung]
		values.sort()
		medians[rung] = values[values.size() / 2]
	for rung in [2, 3, 4]:
		(
			assert_float(float(medians[rung]) - float(medians[rung - 1]))
			. override_failure_message(
				"rung %d is not %.0f dB over rung %d" % [rung, LADDER_STEP_DB, rung - 1]
			)
			. is_greater_equal(LADDER_STEP_DB)
		)
	assert_float(loudest).is_less(LOUDEST_DBFS)


func test_a_hint_is_a_lighter_weight_than_the_press_of_the_same_role() -> void:
	for role: StringName in UiSoundTable.ROLES:
		var rows: Dictionary = UiSoundTable.ROLES[role]
		if not rows.has(&"press") or UiSoundTable.is_silent(rows[&"press"]):
			continue
		for cue: StringName in [&"hover", &"focus"]:
			if rows.has(cue) and not UiSoundTable.is_silent(rows[cue]):
				assert_int(int(rows[cue]["weight"])).override_failure_message(role).is_less(
					int(rows[&"press"]["weight"])
				)


func test_the_menus_sounds_are_a_deferred_bank_and_small() -> void:
	var bank := load(BANK) as SoundBank
	assert_bool(bank.deferred).is_true()
	var seconds := 0.0
	var bytes := 0
	for def in bank.sounds:
		for variant in range(1, def.variants + 1):
			var path := def.path_for(variant)
			seconds += (load(path) as AudioStream).get_length()
			bytes += FileAccess.get_file_as_bytes(path).size()
	(
		assert_float(seconds)
		. override_failure_message("%.1f s of sound (cap %.0f)" % [seconds, MAX_SECONDS])
		. is_less_equal(MAX_SECONDS)
	)
	(
		assert_int(bytes)
		. override_failure_message("%d KiB (cap %d)" % [bytes / 1024, MAX_BYTES / 1024])
		. is_less_equal(MAX_BYTES)
	)


func test_every_sound_is_on_the_ui_bus_in_a_group_with_a_limit() -> void:
	var limits := SoundCatalog.group_limits()
	for def in (load(BANK) as SoundBank).sounds:
		assert_str(def.bus).override_failure_message(def.id).is_equal("UI")
		assert_bool(limits.has(def.group)).override_failure_message(def.id).is_true()
