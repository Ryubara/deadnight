extends GdUnitTestSuite
## The audio service as the dead use it: the nearest attacker takes a voice from a far groan, a
## voice from behind is darker, every look has real sounds in the catalog and its overrides take
## effect.

var _audio: AudioService
var _listener: Node3D


func before_test() -> void:
	_listener = auto_free(Node3D.new())
	add_child(_listener)  # at the origin, looking down -Z
	_audio = AudioService.new()
	_audio.listener = _listener
	_audio.seed_random(3)
	add_child(_audio)


func after_test() -> void:
	_audio.free()
	Audio.install_ui_hook()


func test_the_nearest_attacker_beats_a_far_groan_for_a_voice() -> void:
	var limit: int = SoundCatalog.group_limits()[&"zombie_voice"]
	for i in limit:
		_audio.play(&"zombie_groan", Vector3(30.0, 0, -i))
	var near := _audio.play(&"zombie_alert", Vector3(0, 0, -3.0))
	assert_object(near).is_not_null()
	assert_int(_audio.budget_3d().group_count(&"zombie_voice")).is_equal(limit)


func test_a_voice_from_behind_is_darker_than_one_in_front() -> void:
	var front := _audio.play(&"zombie_alert", Vector3(0, 0, -6.0)) as AudioStreamPlayer3D
	var behind := _audio.play(&"zombie_alert", Vector3(0, 0, 6.0)) as AudioStreamPlayer3D
	var beside := _audio.play(&"zombie_alert", Vector3(6.0, 0, 0)) as AudioStreamPlayer3D
	assert_float(front.attenuation_filter_cutoff_hz).is_equal(AudioService.OPEN_CUTOFF_HZ)
	assert_float(behind.attenuation_filter_cutoff_hz).is_equal_approx(
		AudioService.REAR_CUTOFF_HZ, 1.0
	)
	assert_float(beside.attenuation_filter_cutoff_hz).is_greater(
		behind.attenuation_filter_cutoff_hz
	)
	# A gunshot (no rear cue) is the same everywhere.
	var shot := _audio.play(&"shot_rifle", Vector3(0, 0, 6.0)) as AudioStreamPlayer3D
	assert_float(shot.attenuation_filter_cutoff_hz).is_equal(AudioService.OPEN_CUTOFF_HZ)


func test_the_voice_table_gives_every_look_real_sounds() -> void:
	for look in ZombieModels.VARIANTS:
		for role in ["alert", "swing", "hurt", "death", "step", "step_run"]:
			var sound: StringName = ZombieVoiceTable.get_role(look, role)
			if sound != &"":
				(
					assert_object(SoundCatalog.get_def(sound))
					. override_failure_message("%s %s" % [look, role])
					. is_not_null()
				)
		for sound: StringName in ZombieVoiceTable.get_role(look, "idle"):
			assert_object(SoundCatalog.get_def(sound)).is_not_null()
	# A step falls with the foot: the clip's length over the rate it is played at.
	var slow := ZombieRig.gait_rate(&"walker", 0.7)
	assert_float(ZombieVoiceTable.cycle_seconds(&"walker", 0.7)).is_equal_approx(
		ZombieVoiceTable.WALK_CYCLE / slow, 0.001
	)
	var fast := ZombieRig.gait_rate(&"walker", 6.0)
	assert_float(ZombieVoiceTable.cycle_seconds(&"walker", 6.0)).is_equal_approx(
		ZombieVoiceTable.RUN_CYCLE / fast, 0.001
	)
	# From the run to the sprint the cadence holds and the stride lengthens (#278); past the
	# sprint's own speed the steps come faster.
	assert_float(ZombieVoiceTable.cycle_seconds(&"walker", 6.0)).is_equal_approx(
		ZombieVoiceTable.cycle_seconds(&"walker", 4.4), 0.001
	)
	assert_float(ZombieVoiceTable.cycle_seconds(&"walker", 8.0)).is_less(
		ZombieVoiceTable.cycle_seconds(&"walker", 4.4)
	)
	assert_float(ZombieVoiceTable.cycle_seconds(&"crawler", 1.1)).is_equal_approx(
		ZombieVoiceTable.CRAWL_CYCLE, 0.001
	)


func test_the_catalogs_overrides_take_effect() -> void:
	# #135: `merged()` without `true` keeps the base value; these entries state their own.
	assert_int(SoundCatalog.get_def(&"zombie_groan").priority).is_equal(30)
	assert_float(SoundCatalog.get_def(&"zombie_groan").max_distance).is_equal(40.0)
	assert_int(SoundCatalog.get_def(&"zombie_attack").priority).is_equal(60)
	assert_int(SoundCatalog.get_def(&"zombie_alert").priority).is_greater(
		SoundCatalog.get_def(&"zombie_groan").priority
	)
	assert_int(SoundCatalog.get_def(&"zombie_roar").priority).is_greater(
		SoundCatalog.get_def(&"zombie_alert").priority
	)
	assert_int(SoundCatalog.get_def(&"zombie_step_shuffle").priority).is_less(
		SoundCatalog.get_def(&"step_asphalt").priority
	)
