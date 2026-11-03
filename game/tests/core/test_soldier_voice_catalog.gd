extends GdUnitTestSuite
## The soldiers' voices as data, for the male and the female one: every moment has its takes on
## disk and in the sound catalog, the manifest the recipe wrote agrees with both, the ElevenLabs
## settings are the ones approved and the characters spent stay inside the budget.

const ROOT := "res://assets/audio/"
## What the maintainer listened to and approved (2026-11-01, the male voice); the female voice is
## another premade voice on the same model and settings.
const APPROVED_MODEL := "eleven_v4"
const APPROVED_SETTINGS := {"stability": 0.0, "similarity_boost": 0.8, "style": 0.6}
## Per voice: the ElevenLabs voice, and the free tier's characters its work may spend (tags count
## in the plan, not all in the bill).
const SPEC := {
	&"male": {"voice_id": "nPczCjzI2devNBz1zQrb", "budget": 6500},
	&"female": {"voice_id": "EXAVITQu4vr4xnSDxMaL", "budget": 6000},
}
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


func _folder(voice: StringName) -> String:
	return ROOT + SoldierVoiceCatalog.VOICES[voice]["folder"]


func _manifest(voice: StringName) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(_folder(voice) + "manifest.json"))


func test_there_are_two_voices_and_each_is_known_to_the_spec() -> void:
	assert_array(SoldierVoiceCatalog.voices()).contains_exactly([&"male", &"female"])
	assert_array(SPEC.keys()).contains_exactly(SoldierVoiceCatalog.voices())


func test_every_moment_has_all_its_takes_on_disk_and_in_the_catalog_for_both_voices() -> void:
	for voice: StringName in SoldierVoiceCatalog.voices():
		for event: StringName in SoldierVoiceCatalog.events():
			var takes := SoldierVoiceCatalog.takes_of(event)
			assert_int(takes).override_failure_message(String(event)).is_greater(2)
			for n in range(1, takes + 1):
				var path := SoldierVoiceCatalog.path_of(event, n, voice)
				assert_bool(ResourceLoader.exists(path)).override_failure_message(path).is_true()
				var def := SoundCatalog.get_def(SoldierVoiceCatalog.take_id(event, n, voice))
				(
					assert_object(def)
					. override_failure_message("no %s sound for %s %d" % [voice, event, n])
					. is_not_null()
				)
				assert_str(def.path_for(1)).is_equal(path)


func test_the_voices_have_distinct_ids_and_are_told_apart_by_their_prefix() -> void:
	var seen := {}
	for voice: StringName in SoldierVoiceCatalog.voices():
		var id := SoldierVoiceCatalog.take_id(&"reload", 1, voice)
		assert_bool(SoldierVoiceCatalog.is_take(id)).is_true()
		assert_bool(seen.has(id)).is_false()
		seen[id] = true
	assert_bool(SoldierVoiceCatalog.is_take(&"shot_pistol")).is_false()
	assert_str(SoldierVoiceCatalog.voice_of({})).is_equal("male")
	assert_str(SoldierVoiceCatalog.voice_of({"voice": &"female"})).is_equal("female")
	assert_str(SoldierVoiceCatalog.voice_of({"voice": &"robot"})).is_equal("male")


func test_no_file_in_a_voices_folder_is_left_out_of_the_catalog() -> void:
	var expected := 0
	for event: StringName in SoldierVoiceCatalog.events():
		expected += SoldierVoiceCatalog.takes_of(event)
	for voice: StringName in SoldierVoiceCatalog.voices():
		var files := 0
		for file in DirAccess.get_files_at(_folder(voice)):
			if not file.ends_with(".ogg"):
				continue
			files += 1
			var parts := file.trim_suffix(".ogg").rsplit("_", true, 1)
			var event := StringName(parts[0])
			(
				assert_bool(SoldierVoiceCatalog.moments().has(event))
				. override_failure_message("%s %s" % [voice, file])
				. is_true()
			)
			assert_int(int(parts[1])).override_failure_message(file).is_between(
				1, SoldierVoiceCatalog.takes_of(event)
			)
		assert_int(files).override_failure_message(String(voice)).is_equal(expected)


func test_the_takes_are_voice_bus_sounds_ranked_by_their_moment() -> void:
	for voice: StringName in SoldierVoiceCatalog.voices():
		for event: StringName in SoldierVoiceCatalog.events():
			var def := SoundCatalog.get_def(SoldierVoiceCatalog.take_id(event, 1, voice))
			assert_str(def.bus).is_equal(SoldierVoiceCatalog.BUS)
			assert_str(def.group).is_equal(SoldierVoiceCatalog.GROUP)
			assert_int(def.priority).is_equal(SoldierVoiceCatalog.moments()[event]["priority"])
			assert_float(def.pitch_semitones).is_equal(0.0)
	assert_bool(SoundCatalog.group_limits().has(SoldierVoiceCatalog.GROUP)).is_true()


func test_the_bus_the_voices_play_on_exists_and_is_not_ducked() -> void:
	assert_int(AudioServer.get_bus_index(SoldierVoiceCatalog.BUS)).is_greater_equal(0)
	assert_bool(AudioService.DUCK_BUSES.has(SoldierVoiceCatalog.BUS)).is_false()


func test_the_manifest_lists_every_take_with_the_approved_settings() -> void:
	for voice: StringName in SoldierVoiceCatalog.voices():
		var manifest := _manifest(voice)
		var takes := 0
		for event: StringName in SoldierVoiceCatalog.events():
			for n in range(1, SoldierVoiceCatalog.takes_of(event) + 1):
				takes += 1
				var file := "%s_%d.ogg" % [event, n]
				assert_bool(manifest.has(file)).override_failure_message(file).is_true()
				var entry: Dictionary = manifest[file]
				assert_str(entry["event"]).is_equal(String(event))
				assert_str(entry["model_id"]).is_equal(APPROVED_MODEL)
				assert_str(entry["voice_id"]).is_equal(SPEC[voice]["voice_id"])
				assert_dict(entry["voice_settings"]).is_equal(APPROVED_SETTINGS)
				assert_int(int(entry["characters"])).is_equal(String(entry["text"]).length())
		assert_int(manifest.size()).override_failure_message(String(voice)).is_equal(takes)


func test_the_characters_requested_stay_inside_the_budget() -> void:
	for voice: StringName in SoldierVoiceCatalog.voices():
		var requested := 0
		for entry: Dictionary in _manifest(voice).values():
			if entry["source"] == "text-to-speech":
				requested += int(entry["characters"])
		assert_int(requested).override_failure_message(String(voice)).is_less_equal(
			SPEC[voice]["budget"]
		)


func test_the_female_voice_says_every_moment_in_her_own_voice() -> void:
	var male := _manifest(&"male")
	var female := _manifest(&"female")
	var same := 0
	for file: String in female:
		assert_bool(male.has(file)).override_failure_message(file).is_true()
		assert_str(female[file]["source"]).is_equal("text-to-speech")
		assert_str(female[file]["voice_id"]).is_not_equal(male[file]["voice_id"])
		same += int(female[file]["text"] == male[file]["text"])
		# The lines that name the speaker's sex are hers.
		for word in ["papa", " guy ", "big boy"]:
			(
				assert_bool(String(female[file]["text"]).contains(word))
				. override_failure_message("%s: %s" % [file, female[file]["text"]])
				. is_false()
			)
	# Most lines say the same words in her voice; the ones that read better another way are hers.
	assert_int(same).is_less(female.size())


func test_a_line_is_written_as_speech_not_as_a_caption() -> void:
	var tag := RegEx.create_from_string("\\[[^\\]]*\\]")
	for voice: StringName in SoldierVoiceCatalog.voices():
		var manifest := _manifest(voice)
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
				. override_failure_message("%s %s reads like a caption: %s" % [voice, file, text])
				. is_true()
			)


func test_no_take_is_a_speech_and_the_commonest_calls_are_short() -> void:
	for voice: StringName in SoldierVoiceCatalog.voices():
		var longest := 0.0
		for event: StringName in SoldierVoiceCatalog.events():
			for n in range(1, SoldierVoiceCatalog.takes_of(event) + 1):
				var seconds := SoldierVoiceCatalog.length(event, n, voice)
				(
					assert_float(seconds)
					. override_failure_message("%s %s %d is silent" % [voice, event, n])
					. is_greater(0.3)
				)
				longest = maxf(longest, seconds)
		assert_float(longest).override_failure_message(String(voice)).is_less(LONGEST)
		for event: StringName in [&"reload", &"kill", &"grenade", &"hurt"]:
			var total := 0.0
			for n in range(1, SoldierVoiceCatalog.takes_of(event) + 1):
				total += SoldierVoiceCatalog.length(event, n, voice)
			var mean := total / SoldierVoiceCatalog.takes_of(event)
			assert_float(mean).override_failure_message("%s %s" % [voice, event]).is_less(3.5)


func test_the_moments_the_issue_names_all_have_lines() -> void:
	for event in MOMENTS:
		(
			assert_bool(SoldierVoiceCatalog.moments().has(event))
			. override_failure_message(String(event))
			. is_true()
		)
