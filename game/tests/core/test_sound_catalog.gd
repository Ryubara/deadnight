extends GdUnitTestSuite
## The sound catalog's table: every override the catalog writes takes effect (issue #135: `merged`
## ignored them), the night's sounds are all listed, and the beds are loops that sit under the
## effects.

const CATALOG_SOURCE := "res://core/audio/sound_catalog.gd"
## Overrides that `merged(..., false)` used to drop: the base already had the key.
const OVERRIDES := {
	&"ui_tick": {"pitch_semitones": 1.0, "cooldown": 0.02},
	&"ui_press": {"pitch_semitones": 0.3},
	&"shot_smg": {"pitch_semitones": 0.8, "volume_db": -6.0},
	&"dry_fire": {"priority": 70, "max_distance": 20.0, "cooldown": 0.12},
	&"grenade_throw": {"priority": 70, "max_distance": 30.0},
	&"generator_hum": {"loop": true, "volume_db": -8.0},
	&"board_last": {"priority": 75, "max_distance": 90.0, "unit_size": 12.0},
	&"board_repair": {"max_distance": 40.0, "unit_size": 7.0},
	&"melee_hit": {"priority": 72, "max_distance": 35.0},
	&"player_downed": {"priority": 88},
	&"bed_score": {"bus": &"Music", "volume_db": -22.0},
}
const NIGHT_SOUNDS: Array[StringName] = [
	&"board_tear",
	&"board_last",
	&"board_repair",
	&"door_open",
	&"melee_swing",
	&"melee_hit",
	&"till_ring",
	&"player_hurt",
	&"player_downed",
	&"bed_crickets",
	&"bed_highway",
	&"bed_projector",
	&"bed_score",
]
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


func test_the_catalog_never_calls_merged_without_overwriting() -> void:
	var source := FileAccess.get_file_as_string(CATALOG_SOURCE)
	var calls := source.count(".merged(")
	# The one helper (`_with`), which passes true; every override goes through it.
	assert_int(calls).is_equal(1)
	assert_bool(source.contains("base.merged(overrides, true)")).is_true()


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


func test_a_board_torn_outranks_a_groan() -> void:
	var groan := SoundCatalog.get_def(&"zombie_groan")
	for id: StringName in [&"board_tear", &"board_last", &"board_repair"]:
		assert_int(SoundCatalog.get_def(id).priority).is_greater(groan.priority)


func test_the_last_board_is_the_loudest_of_the_boards() -> void:
	var tear := SoundCatalog.get_def(&"board_tear")
	var last := SoundCatalog.get_def(&"board_last")
	assert_float(last.volume_db).is_greater(tear.volume_db)
	assert_int(last.priority).is_greater(tear.priority)
