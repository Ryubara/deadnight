extends GdUnitTestSuite
## The sound catalog's table: every override takes effect (issue #135: `merged` ignored them; the
## banks now hold every value, and this pins the ones that were once overrides), the night's sounds
## are all listed, and the beds are loops that sit under the
## effects.

## Overrides that `merged(..., false)` used to drop: the base already had the key.
const OVERRIDES := {
	&"ui_tick": {"pitch_semitones": 1.0, "cooldown": 0.02},
	&"ui_press": {"pitch_semitones": 0.3},
	&"shot_smg": {"pitch_semitones": ArmsCatalog.FIREARM_PITCH_SEMITONES, "volume_db": -2.5},
	&"dry_fire": {"priority": 70, "max_distance": 20.0, "cooldown": 0.12},
	&"grenade_throw": {"priority": 70, "max_distance": 30.0},
	&"generator_hum": {"loop": true, "volume_db": -8.0},
	&"board_last": {"priority": 75, "max_distance": 90.0, "unit_size": 12.0},
	&"board_repair": {"max_distance": 40.0, "unit_size": 7.0},
	&"melee_hit": {"priority": 72, "max_distance": 35.0},
	&"bed_score": {"bus": &"Music", "volume_db": BED_SCORE_DB},
	&"bed_crickets": {"volume_db": BED_CRICKETS_DB},
}
const NIGHT_SOUNDS: Array[StringName] = [
	&"board_tear",
	&"board_last",
	&"board_repair",
	&"door_open",
	&"melee_swing",
	&"melee_hit",
	&"till_ring",
	&"bed_crickets",
	&"bed_highway",
	&"bed_projector",
	&"bed_score",
]
## The break's two beds as the maintainer tuned them (#382): the score 25% louder in amplitude
## (+1.9 dB from -22) and the crickets 25% quieter (-2.5 dB from -16).
const BED_SCORE_DB := -20.1
const BED_CRICKETS_DB := -18.5
const BEDS: Array[StringName] = [&"bed_crickets", &"bed_highway", &"bed_projector", &"bed_score"]


func test_every_override_takes_effect() -> void:
	for id: StringName in OVERRIDES:
		var def := SoundCatalog.get_def(id)
		assert_object(def).override_failure_message("no sound " + id).is_not_null()
		for property: String in OVERRIDES[id]:
			(
				assert_that(def.get(property))
				. override_failure_message("%s.%s ignored its override" % [id, property])
				. is_equal(OVERRIDES[id][property])
			)


func test_the_night_s_sounds_are_in_the_catalog() -> void:
	for id in NIGHT_SOUNDS:
		var def := SoundCatalog.get_def(id)
		assert_object(def).override_failure_message("no sound " + id).is_not_null()
		assert_int(def.variants).is_greater_equal(1)


func test_the_beds_loop_and_sit_under_the_effects() -> void:
	for id in BEDS:
		var def := SoundCatalog.get_def(id)
		assert_bool(def.loop).override_failure_message(id + " must loop").is_true()
		assert_float(def.volume_db).override_failure_message(id + " too loud").is_less_equal(-12.0)
		assert_str(def.group).is_equal("bed")
	assert_str(SoundCatalog.get_def(&"bed_score").bus).is_equal("Music")
	assert_str(SoundCatalog.get_def(&"bed_crickets").bus).is_equal("Ambience")


func test_the_break_score_is_louder_and_the_crickets_quieter() -> void:
	var score := SoundCatalog.get_def(&"bed_score").volume_db
	var crickets := SoundCatalog.get_def(&"bed_crickets").volume_db
	assert_float(score).is_equal_approx(BED_SCORE_DB, 0.001)
	assert_float(crickets).is_equal_approx(BED_CRICKETS_DB, 0.001)
	# 25% in amplitude, read in decibels: +1.94 and -2.5.
	assert_float(score - -22.0).is_equal_approx(20.0 * log(1.25) / log(10.0), 0.06)
	assert_float(crickets - -16.0).is_equal_approx(20.0 * log(0.75) / log(10.0), 0.06)
	# By trim the score was 6 dB under the crickets, and is 1.6 dB under them now.
	assert_float(score - crickets).is_equal_approx(-1.6, 0.001)


func test_a_board_torn_outranks_a_groan() -> void:
	var groan := SoundCatalog.get_def(&"zombie_groan")
	for id: StringName in [&"board_tear", &"board_last", &"board_repair"]:
		assert_int(SoundCatalog.get_def(id).priority).is_greater(groan.priority)


func test_the_last_board_is_the_loudest_of_the_boards() -> void:
	var tear := SoundCatalog.get_def(&"board_tear")
	var last := SoundCatalog.get_def(&"board_last")
	assert_float(last.volume_db).is_greater(tear.volume_db)
	assert_int(last.priority).is_greater(tear.priority)
