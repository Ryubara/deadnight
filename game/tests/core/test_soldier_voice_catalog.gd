extends GdUnitTestSuite
## The soldier's voice as data: every moment has its takes on disk and in the sound catalog, the
## manifest the recipe wrote agrees with both, the approved ElevenLabs settings are the ones used
## and the characters spent stay inside the budget.

const FOLDER := "res://assets/audio/voice/soldier/"
const MANIFEST := FOLDER + "manifest.json"
## What the maintainer listened to and approved (2026-11-01).
const APPROVED_MODEL := "eleven_v4"
const APPROVED_VOICE := "nPczCjzI2devNBz1zQrb"
const APPROVED_SETTINGS := {"stability": 0.0, "similarity_boost": 0.8, "style": 0.6}
## The free tier's characters this work may spend (tags count in the plan, not all in the bill).
const BUDGET := 6500
## A line longer than this is a speech, not a bark.
const LONGEST := 9.0
const MOMENTS: Array[StringName] = [
	&"round_start",
	&"round_clear",
	&"reload",
	&"low_ammo",
	&"dry",
	&"kill",
	&"streak",
	&"close_call",
	&"hurt",
	&"downed",
	&"revived",
	&"teammate_down",
	&"buy_weapon",
	&"buy_big",
	&"door",
	&"power_on",
	&"grenade",
	&"boss_arrive",
	&"boss_dead",
	&"idle",
]


func _manifest() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))


func test_every_moment_has_all_its_takes_on_disk_and_in_the_catalog() -> void:
	for event: StringName in SoldierVoiceCatalog.events():
		var takes := SoldierVoiceCatalog.takes_of(event)
		assert_int(takes).override_failure_message(String(event)).is_greater(2)
		for n in range(1, takes + 1):
			var path := SoldierVoiceCatalog.path_of(event, n)
			assert_bool(ResourceLoader.exists(path)).override_failure_message(path).is_true()
			var def := SoundCatalog.get_def(SoldierVoiceCatalog.take_id(event, n))
			(
				assert_object(def)
				. override_failure_message("no sound for %s %d" % [event, n])
				. is_not_null()
			)
			assert_str(def.path_for(1)).is_equal(path)


func test_no_file_in_the_folder_is_left_out_of_the_catalog() -> void:
	var files := 0
	for file in DirAccess.get_files_at(FOLDER):
		if not file.ends_with(".ogg"):
			continue
		files += 1
		var parts := file.trim_suffix(".ogg").rsplit("_", true, 1)
		var event := StringName(parts[0])
		(
			assert_bool(SoldierVoiceCatalog.moments().has(event))
			. override_failure_message(file)
			. is_true()
		)
		assert_int(int(parts[1])).override_failure_message(file).is_between(
			1, SoldierVoiceCatalog.takes_of(event)
		)
	var expected := 0
	for event: StringName in SoldierVoiceCatalog.events():
		expected += SoldierVoiceCatalog.takes_of(event)
	assert_int(files).is_equal(expected)


func test_the_takes_are_voice_bus_sounds_ranked_by_their_moment() -> void:
	for event: StringName in SoldierVoiceCatalog.events():
		var def := SoundCatalog.get_def(SoldierVoiceCatalog.take_id(event, 1))
		assert_str(def.bus).is_equal(SoldierVoiceCatalog.BUS)
		assert_str(def.group).is_equal(SoldierVoiceCatalog.GROUP)
		assert_int(def.priority).is_equal(SoldierVoiceCatalog.moments()[event]["priority"])
		assert_float(def.pitch_semitones).is_equal(0.0)
	assert_bool(SoundCatalog.group_limits().has(SoldierVoiceCatalog.GROUP)).is_true()


func test_the_bus_the_voices_play_on_exists_and_is_not_ducked() -> void:
	assert_int(AudioServer.get_bus_index(SoldierVoiceCatalog.BUS)).is_greater_equal(0)
	assert_bool(AudioService.DUCK_BUSES.has(SoldierVoiceCatalog.BUS)).is_false()


func test_the_manifest_lists_every_take_with_the_approved_settings() -> void:
	var manifest := _manifest()
	var takes := 0
	for event: StringName in SoldierVoiceCatalog.events():
		for n in range(1, SoldierVoiceCatalog.takes_of(event) + 1):
			takes += 1
			var file := "%s_%d.ogg" % [event, n]
			assert_bool(manifest.has(file)).override_failure_message(file).is_true()
			var entry: Dictionary = manifest[file]
			assert_str(entry["event"]).is_equal(String(event))
			assert_str(entry["model_id"]).is_equal(APPROVED_MODEL)
			assert_str(entry["voice_id"]).is_equal(APPROVED_VOICE)
			assert_dict(entry["voice_settings"]).is_equal(APPROVED_SETTINGS)
			assert_int(int(entry["characters"])).is_equal(String(entry["text"]).length())
	assert_int(manifest.size()).is_equal(takes)


func test_the_characters_requested_stay_inside_the_budget() -> void:
	var requested := 0
	for entry: Dictionary in _manifest().values():
		if entry["source"] == "text-to-speech":
			requested += int(entry["characters"])
	assert_int(requested).is_less_equal(BUDGET)


func test_a_line_is_written_as_speech_not_as_a_caption() -> void:
	var tag := RegEx.create_from_string("\\[[^\\]]*\\]")
	var manifest := _manifest()
	for file: String in manifest:
		var text: String = manifest[file]["text"]
		var spoken := tag.sub(text, "", true).strip_edges()
		assert_bool(spoken.length() > 0).override_failure_message(file).is_true()
		var marks := (
			spoken.contains("!")
			or spoken.contains("?")
			or spoken.contains("...")
			or spoken.contains(",")
			or spoken.contains("'")
			or spoken.split(" ", false).size() >= 4
		)
		(
			assert_bool(marks)
			. override_failure_message("%s reads like a caption: %s" % [file, text])
			. is_true()
		)


func test_no_take_is_a_speech_and_the_commonest_calls_are_short() -> void:
	var longest := 0.0
	for event: StringName in SoldierVoiceCatalog.events():
		for n in range(1, SoldierVoiceCatalog.takes_of(event) + 1):
			var seconds := SoldierVoiceCatalog.length(event, n)
			(
				assert_float(seconds)
				. override_failure_message("%s %d is silent" % [event, n])
				. is_greater(0.3)
			)
			longest = maxf(longest, seconds)
	assert_float(longest).is_less(LONGEST)
	for event: StringName in [&"reload", &"kill", &"grenade", &"hurt"]:
		var total := 0.0
		for n in range(1, SoldierVoiceCatalog.takes_of(event) + 1):
			total += SoldierVoiceCatalog.length(event, n)
		var mean := total / SoldierVoiceCatalog.takes_of(event)
		assert_float(mean).override_failure_message(String(event)).is_less(3.5)


func test_the_moments_the_issue_names_all_have_lines() -> void:
	for event in MOMENTS:
		(
			assert_bool(SoldierVoiceCatalog.moments().has(event))
			. override_failure_message(String(event))
			. is_true()
		)
