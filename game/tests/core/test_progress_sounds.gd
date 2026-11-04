extends GdUnitTestSuite
## The progression sounds (#1062): a record scratch for a challenge done, a snare roll into brass
## for a level up, the same bigger for a tier up, a ticket punch and a bell for an unlock
## (climbing a pentatonic scale when they come close together) and the same with a paper rustle
## for a card, an emblem or a frame. Every cue is checked from its files (length, peak with the
## trims, the share of its energy in the first 50 ms, K-weighted loudness of the loudest 400 ms)
## against what the recording of the real service measured (`progress_sound_levels.json`, written
## by `tools/audio/progress_levels.py --pin`), the rules (the stack, the moments, the night's
## trim, the bus at 0) and the recording's margins (a cue never hides a shot, a groan or a
## warning, is heard over a burst, does not clip, and eight unlocks in two seconds stay under a
## level up). The words are `docs/research/menu-sfx.md#the-progression-sounds-1062`.

const PIN := "res://tests/core/progress_sound_levels.json"
const RATE := 48000
## The cues of the issue and their sounds.
const CUES := {
	&"challenge_done": &"ui_challenge_done",
	&"level_up": &"ui_level_up",
	&"tier_up": &"ui_tier_up",
	&"unlock": &"ui_unlock",
	&"card_earned": &"ui_card_earned",
}
## How far the files may be from the recording's numbers (the Ogg decode and the engine's mix).
const PEAK_TOLERANCE_DB := 1.0
const LOUDNESS_TOLERANCE_DB := 1.5
const LENGTH_TOLERANCE := 0.15
## The share of a sound's energy in its first 50 ms moves with where the recording's first sample
## is (a bell that starts at 45 ms is half in and half out of the window): points of a hundred.
const FIRST_SHARE_TOLERANCE := 20.0
## BS.1770 K-weighting at 48 kHz (the pre-filter, the RLB high-pass).
const K_PRE_B: Array[float] = [1.53512485958697, -2.69169618940638, 1.19839281085285]
const K_PRE_A: Array[float] = [-1.69065929318241, 0.73248077421585]
const K_RLB_B: Array[float] = [1.0, -2.0, 1.0]
const K_RLB_A: Array[float] = [-1.99004745483398, 0.99007225036621]

var _audio: AudioService


func before_test() -> void:
	_audio = AudioService.new()
	_audio.seed_random(3)
	add_child(_audio)
	_audio.set_process(false)


func after_test() -> void:
	_audio.free()
	Audio.install_ui_hook()


func _pin() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PIN))


## A file as the service plays it: samples as floats.
func _samples(path: String) -> PackedFloat32Array:
	var wav := PcmStream.decode(load(path) as AudioStream, RATE)
	var out := PackedFloat32Array()
	out.resize(wav.data.size() / 2)
	for i in out.size():
		out[i] = wav.data.decode_s16(i * 2) / float(PcmStream.PEAK)
	return out


func _bus_db() -> float:
	return linear_to_db(float(SettingsService.DEFAULTS[SettingsService.VOLUME_UI]) / 100.0)


func _biquad(x: PackedFloat32Array, b: Array[float], a: Array[float]) -> PackedFloat32Array:
	var y := PackedFloat32Array()
	y.resize(x.size())
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in x.size():
		var out := b[0] * x[i] + b[1] * x1 + b[2] * x2 - a[0] * y1 - a[1] * y2
		x2 = x1
		x1 = x[i]
		y2 = y1
		y1 = out
		y[i] = out
	return y


## The loudest 400 ms in LUFS of a mono file played in both channels, `gain_db` louder than it is.
func _lufs_m(x: PackedFloat32Array, gain_db: float) -> float:
	var weighted := _biquad(_biquad(x, K_PRE_B, K_PRE_A), K_RLB_B, K_RLB_A)
	var window := int(0.4 * RATE)
	var sums := PackedFloat64Array()
	sums.resize(weighted.size() + 1)
	for i in weighted.size():
		sums[i + 1] = sums[i] + weighted[i] * weighted[i]
	var best := 0.0
	var span := maxi(weighted.size(), window)
	var start := 0
	while start + window <= span:
		var stop := mini(start + window, weighted.size())
		best = maxf(best, (sums[stop] - sums[mini(start, weighted.size())]) / window)
		start += int(0.1 * RATE)
	# Both channels carry the same signal, so the power is twice a channel's.
	return -0.691 + 10.0 * log(maxf(2.0 * best, 1e-18)) / log(10.0) + gain_db


func _first_share(x: PackedFloat32Array) -> float:
	var first := 0.0
	var all := 0.0
	var limit := int(0.05 * RATE)
	for i in x.size():
		all += x[i] * x[i]
		if i < limit:
			first += x[i] * x[i]
	return first / maxf(all, 1e-18)


func _peak_db(x: PackedFloat32Array) -> float:
	var peak := 0.0
	for sample in x:
		peak = maxf(peak, absf(sample))
	return linear_to_db(peak)


## The cue's row of the table.
func _row(cue: StringName) -> Dictionary:
	return UiSoundTable.row(&"any", cue)


func _gain_db(id: StringName) -> float:
	return SoundCatalog.get_def(id).volume_db + _bus_db()


# ---- the files ----


func test_every_cue_has_a_row_a_sound_and_files_as_long_as_the_row_says() -> void:
	for cue: StringName in CUES:
		var row := _row(cue)
		assert_bool(row.is_empty()).override_failure_message("no row for %s" % cue).is_false()
		assert_str(row["sound"]).is_equal(CUES[cue])
		var def := SoundCatalog.get_def(CUES[cue])
		assert_object(def).override_failure_message("no sound %s" % CUES[cue]).is_not_null()
		assert_str(def.bus).is_equal("UI")
		assert_bool(def.deferred).is_true()
		var pinned: float = _pin()["cues"][cue]["seconds"]
		for variant in range(1, def.variants + 1):
			var seconds := (load(def.path_for(variant)) as AudioStream).get_length()
			(
				assert_float(seconds)
				. override_failure_message(
					(
						"%s file %d is %.2f s, the recording says %.2f"
						% [cue, variant, seconds, pinned]
					)
				)
				. is_between(pinned * (1.0 - LENGTH_TOLERANCE), pinned * (1.0 + LENGTH_TOLERANCE))
			)
			if row.has("seconds"):
				(
					assert_float(seconds)
					. override_failure_message(
						(
							"%s file %d is %.2f s, the row says %s"
							% [cue, variant, seconds, row["seconds"]]
						)
					)
					. is_between(row["seconds"] * 0.85, row["seconds"] * 1.15)
				)


func test_the_files_peak_where_the_recording_measured_them_and_never_clip() -> void:
	var pin := _pin()
	for cue: StringName in CUES:
		var def := SoundCatalog.get_def(CUES[cue])
		var mean := 0.0
		for variant in range(1, def.variants + 1):
			var peak := _peak_db(_samples(def.path_for(variant))) + _gain_db(CUES[cue])
			mean += peak / def.variants
			(
				assert_float(peak)
				. override_failure_message("%s file %d peaks at %.1f dBFS" % [cue, variant, peak])
				. is_less(float(pin["gates"]["clip_db"]))
			)
		(
			assert_float(mean)
			. override_failure_message(
				"%s: files %.1f dBFS, recording %.1f" % [cue, mean, pin["cues"][cue]["peak"]]
			)
			. is_equal_approx(float(pin["cues"][cue]["peak"]), PEAK_TOLERANCE_DB)
		)


func test_the_files_are_as_loud_as_the_recording_measured_and_each_has_its_attack() -> void:
	var pin := _pin()
	for cue: StringName in CUES:
		var def := SoundCatalog.get_def(CUES[cue])
		var lufs := 0.0
		var share := 0.0
		for variant in range(1, def.variants + 1):
			var samples := _samples(def.path_for(variant))
			lufs += _lufs_m(samples, _gain_db(CUES[cue])) / def.variants
			share += _first_share(samples) * 100.0 / def.variants
		(
			assert_float(lufs)
			. override_failure_message(
				"%s: files %.1f LUFS-M, recording %.1f" % [cue, lufs, pin["cues"][cue]["lufs_m"]]
			)
			. is_equal_approx(float(pin["cues"][cue]["lufs_m"]), LOUDNESS_TOLERANCE_DB)
		)
		(
			assert_float(share)
			. override_failure_message(
				(
					"%s: %.1f percent in the first 50 ms, recording %.1f"
					% [cue, share, pin["cues"][cue]["first50_percent"]]
				)
			)
			. is_equal_approx(float(pin["cues"][cue]["first50_percent"]), FIRST_SHARE_TOLERANCE)
		)


func test_the_weights_are_the_ladders_commit_and_moment() -> void:
	for cue: StringName in [&"challenge_done", &"unlock", &"card_earned"]:
		assert_int(int(_row(cue)["weight"])).override_failure_message(cue).is_equal(
			UiSoundTable.COMMIT
		)
	for cue: StringName in [&"level_up", &"tier_up"]:
		assert_int(int(_row(cue)["weight"])).override_failure_message(cue).is_equal(
			UiSoundTable.MOMENT
		)
	var level := float(_pin()["cues"][&"level_up"]["peak"])
	var commit := float(_pin()["cues"][&"challenge_done"]["peak"])
	(
		assert_float(level - commit)
		. override_failure_message("a level up is not 1 to 3 dB over the commit")
		. is_between(1.0, 3.0)
	)
	assert_float(float(_pin()["cues"][&"tier_up"]["peak"])).is_greater_equal(level)


# ---- the recording's margins ----


func test_the_recording_says_no_cue_hides_a_shot_a_groan_or_a_warning_and_none_clips() -> void:
	var pin := _pin()
	assert_float(float(pin["fight_db"])).is_equal(UiSounds.FIGHT_DB)
	(
		assert_float(float(pin["worst_mask_margin_db"]))
		. override_failure_message(
			"the narrowest margin of a cue over a shot, a groan or a warning is under the gate"
		)
		. is_greater_equal(float(pin["gates"]["mask_gate_db"]))
	)
	(
		assert_float(float(pin["worst_burst_peak_db"]))
		. override_failure_message("a cue over a burst reaches the clip level")
		. is_less(float(pin["gates"]["clip_db"]))
	)
	for cue: StringName in CUES:
		(
			assert_float(float(pin["cues"][cue]["fight_under_pistol_lu"]))
			. override_failure_message("%s is louder than a pistol shot in a night" % cue)
			. is_greater_equal(0.0)
		)


func test_eight_unlocks_in_two_seconds_stay_under_a_level_up_and_moments_under_the_ceiling(
) -> void:
	var pin := _pin()
	var level := float(pin["cues"][&"level_up"]["peak"])
	for name: String in pin["stacks"]:
		assert_float(float(pin["stacks"][name]["peak"])).override_failure_message(name).is_less(
			level
		)
		assert_int(int(pin["stacks"][name]["count"])).is_equal(8)
	for case: String in pin["moments"]:
		(
			assert_float(float(pin["moments"][case]["peak"]))
			. override_failure_message(case)
			. is_less_equal(float(pin["gates"]["moments_ceiling_db"]))
		)


# ---- the rules ----


func test_unlocks_that_come_close_climb_the_pentatonic_scale_and_hold_at_the_top() -> void:
	var steps: Array[float] = []
	for _i in 6:
		assert_bool(_audio.ui.handle(&"unlock")).is_true()
		steps.append(_audio.ui.last_pitch)
		_audio.advance(0.2)
	assert_array(steps).is_equal([0.0, 2.0, 4.0, 7.0, 7.0, 7.0])
	_audio.advance(UiSounds.UNLOCK_WINDOW + 0.1)
	_audio.ui.handle(&"unlock")
	assert_float(_audio.ui.last_pitch).is_equal(0.0)


func test_a_card_and_an_unlock_share_one_stack_and_each_step_is_a_little_quieter() -> void:
	_audio.ui.handle(&"card_earned")
	_audio.advance(0.15)
	_audio.ui.handle(&"unlock")
	assert_float(_audio.ui.last_pitch).is_equal(2.0)
	assert_float(_audio.ui.last_extra_db).is_between(
		UiSounds.UNLOCK_STEP_DB - UiSounds.LEVEL_JITTER_DB,
		UiSounds.UNLOCK_STEP_DB + UiSounds.LEVEL_JITTER_DB
	)


func test_a_level_up_is_not_played_while_the_tier_up_that_includes_it_sounds() -> void:
	assert_bool(_audio.ui.handle(&"tier_up")).is_true()
	_audio.advance(0.3)
	assert_bool(_audio.ui.handle(&"level_up")).is_false()
	_audio.advance(2.0)
	assert_bool(_audio.ui.handle(&"level_up")).is_true()


func test_a_scratch_goes_under_a_fanfare_but_a_tier_takes_a_level_ups_place_at_its_own_level(
) -> void:
	_audio.ui.handle(&"level_up")
	_audio.advance(0.3)
	_audio.ui.handle(&"challenge_done")
	assert_float(_audio.ui.last_extra_db).is_between(
		UiSounds.MOMENT_UNDER_DB - UiSounds.LEVEL_JITTER_DB,
		UiSounds.MOMENT_UNDER_DB + UiSounds.LEVEL_JITTER_DB
	)
	_audio.advance(3.0)
	_audio.ui.handle(&"level_up")
	_audio.advance(0.3)
	_audio.ui.handle(&"tier_up")
	assert_float(absf(_audio.ui.last_extra_db)).is_less_equal(UiSounds.LEVEL_JITTER_DB)


func test_the_cues_are_quieter_in_a_night_and_a_menu_sound_is_not() -> void:
	_audio.ui.handle(&"level_up")
	assert_float(absf(_audio.ui.last_extra_db)).is_less_equal(UiSounds.LEVEL_JITTER_DB)
	_audio.advance(3.0)
	_audio.ui.in_night = true
	_audio.ui.handle(&"level_up")
	assert_float(_audio.ui.last_extra_db).is_between(
		UiSounds.FIGHT_DB - UiSounds.LEVEL_JITTER_DB, UiSounds.FIGHT_DB + UiSounds.LEVEL_JITTER_DB
	)
	_audio.advance(0.5)
	UIInputMode.reset()
	UIInputMode.pointer = true
	_audio.ui.handle(&"select")
	assert_float(absf(_audio.ui.last_extra_db)).is_less_equal(UiSounds.LEVEL_JITTER_DB)


func test_the_interface_slider_at_zero_is_mute_for_every_cue() -> void:
	var path := QuietSettings.test_path("progress_sounds_test")
	var settings := QuietSettings.make(self, path)
	settings.set_value(SettingsService.VOLUME_UI, 0)
	settings.apply_all()
	assert_bool(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"UI"))).is_true()
	for cue: StringName in CUES:
		assert_str(SoundCatalog.get_def(CUES[cue]).bus).is_equal("UI")
	settings.reset_defaults()
	settings.apply_all()
	settings.free()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_level_up_in_the_middle_of_a_burst_of_automatic_fire_is_still_started() -> void:
	var played: Array[StringName] = []
	_audio.played.connect(func(id: StringName, _position: Variant) -> void: played.append(id))
	var listener: Node3D = auto_free(Node3D.new())
	add_child(listener)
	_audio.listener = listener
	for shot in 60:
		_audio.play(&"shot_m4a1", Vector3(0.3, 1.45, -0.4))
		_audio.play(&"tail_m4a1", Vector3(0.3, 1.45, -0.45))
		_audio.advance(0.04)
		if shot == 30:
			assert_bool(_audio.ui.handle(&"level_up")).is_true()
	(
		assert_bool(played.has(&"ui_level_up"))
		. override_failure_message("the level up was dropped")
		. is_true()
	)
	_audio.stop_all()
