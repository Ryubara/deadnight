extends GdUnitTestSuite
## What the audio service does to the mix: occlusion, ducking, the UI hook, the rules' stings and
## loops.

var _audio: AudioService
var _listener: Node3D


func before_test() -> void:
	_listener = auto_free(Node3D.new())
	add_child(_listener)
	_audio = AudioService.new()
	_audio.listener = _listener
	_audio.seed_random(7)
	add_child(_audio)


func after_test() -> void:
	_audio.free()
	# The game's own service gives the UI hook back to itself.
	Audio.install_ui_hook()


func test_occlusion_makes_a_sound_quieter_and_duller() -> void:
	var open := _audio.play(&"shot_rifle", Vector3(0, 0, 10)) as AudioStreamPlayer3D
	var open_db := open.volume_db
	var open_cutoff := open.attenuation_filter_cutoff_hz
	_audio.stop_all()
	_audio.occlusion_probe = func(_from: Vector3, _to: Vector3) -> float: return 1.0
	var blocked := _audio.play(&"shot_rifle", Vector3(0, 0, 10)) as AudioStreamPlayer3D
	assert_float(blocked.volume_db).is_equal_approx(open_db + AudioService.OCCLUSION_DB, 0.001)
	assert_float(blocked.attenuation_filter_cutoff_hz).is_less(open_cutoff)
	assert_float(blocked.attenuation_filter_cutoff_hz).is_equal_approx(
		AudioService.OCCLUDED_CUTOFF_HZ, 0.01
	)


func test_the_probe_is_asked_from_the_listener_to_the_source() -> void:
	_listener.global_position = Vector3(5, 0, 0)
	var seen := []
	_audio.occlusion_probe = func(from: Vector3, to: Vector3) -> float:
		seen.append([from, to])
		return 0.0
	_audio.play(&"shot_pistol", Vector3(5, 0, 9))
	assert_int(seen.size()).is_equal(1)
	assert_vector(seen[0][0]).is_equal(Vector3(5, 0, 0))
	assert_vector(seen[0][1]).is_equal(Vector3(5, 0, 9))


func _duck_bus_db() -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(AudioService.DUCK_BUS))


func test_a_sting_ducks_the_effects_bus_then_lets_it_back() -> void:
	var bus := AudioServer.get_bus_index(&"Effects")
	var before := AudioServer.get_bus_volume_db(bus)
	assert_float(_audio.duck_db).is_equal(0.0)
	_audio.play(&"round_start")
	_audio.advance(0.2)
	assert_float(_audio.duck_db).is_less(-8.0)
	# The duck is the volume of the bus the ducked buses send to; the player's setting is untouched.
	assert_float(_duck_bus_db()).is_equal_approx(_audio.duck_db, 0.001)
	assert_float(AudioServer.get_bus_volume_db(bus)).is_equal(before)
	var held := SoundCatalog.get_def(&"round_start").duck_hold
	_audio.advance(held)
	_audio.advance(1.0)
	_audio.advance(1.0)
	assert_float(_audio.duck_db).is_equal(0.0)
	assert_float(_duck_bus_db()).is_equal(0.0)


func test_the_duck_falls_at_its_attack_holds_and_lets_go_at_its_release() -> void:
	var def := SoundCatalog.get_def(&"round_start")
	_audio.play(&"round_start")
	_audio.advance(0.05)
	assert_float(_duck_bus_db()).is_equal_approx(-AudioService.DUCK_ATTACK_DB_PER_S * 0.05, 0.01)
	_audio.advance(0.2)
	assert_float(_duck_bus_db()).is_equal_approx(def.duck_db, 0.001)
	# Small steps, so the hold ends where it should (1.6 s after the sting started).
	for _i in roundi((def.duck_hold - 0.25) / 0.01) - 5:
		_audio.advance(0.01)
	assert_float(_duck_bus_db()).is_equal_approx(def.duck_db, 0.001)
	for _i in 36:
		_audio.advance(0.01)
	# 0.05 s of hold were left, then 0.31 s of release.
	var released := def.duck_db + AudioService.DUCK_RELEASE_DB_PER_S * 0.31
	assert_float(_duck_bus_db()).is_greater(def.duck_db)
	assert_float(_duck_bus_db()).is_less(0.0)
	assert_float(_duck_bus_db()).is_equal_approx(released, 0.4)


func test_a_slider_moved_during_a_duck_is_kept_when_the_duck_lets_go() -> void:
	var bus := AudioServer.get_bus_index(&"Effects")
	var before := AudioServer.get_bus_volume_db(bus)
	_audio.play(&"round_start")
	_audio.advance(0.3)
	AudioServer.set_bus_volume_db(bus, before - 6.0)
	_audio.advance(10.0)
	assert_float(_duck_bus_db()).is_equal(0.0)
	assert_float(AudioServer.get_bus_volume_db(bus)).is_equal(before - 6.0)
	AudioServer.set_bus_volume_db(bus, before)


func _has_effect(bus_name: StringName) -> bool:
	var bus := AudioServer.get_bus_index(bus_name)
	return AudioServer.get_bus_effect_count(bus) > 0


func test_the_sting_ducks_the_ambience_with_the_effects_and_leaves_the_rest() -> void:
	var duck := AudioService.DUCK_BUS
	for bus_name: StringName in AudioService.DUCK_BUSES:
		var bus := AudioServer.get_bus_index(bus_name)
		assert_str(AudioServer.get_bus_send(bus)).override_failure_message(bus_name).is_equal(duck)
		var before := AudioServer.get_bus_volume_db(bus)
		_audio.play(&"round_start")
		_audio.advance(0.2)
		# The player's own volume setting is untouched; the duck lives on the bus they send to.
		assert_float(AudioServer.get_bus_volume_db(bus)).is_equal(before)
		_audio.stop_all()
		_audio.advance(5.0)
	for untouched: StringName in [&"Music", &"Voice", &"UI"]:
		var bus := AudioServer.get_bus_index(untouched)
		assert_str(AudioServer.get_bus_send(bus)).override_failure_message(untouched).is_equal(
			"Master"
		)
	assert_str(AudioServer.get_bus_send(AudioServer.get_bus_index(duck))).is_equal("Master")


func test_no_bus_effect_does_the_duck() -> void:
	# Effects do not play in the web build's samples, so the duck must not depend on one.
	for bus_name: StringName in [&"Master", &"Music", &"Effects", &"Voice", &"Ambience", &"UI"]:
		assert_bool(_has_effect(bus_name)).override_failure_message(bus_name).is_false()
	assert_bool(_has_effect(AudioService.DUCK_BUS)).is_false()


func test_every_catalog_sound_is_on_a_bus_of_its_kind() -> void:
	var expected := {
		&"bed_crickets": &"Ambience",
		&"bed_highway": &"Ambience",
		&"bed_projector": &"Ambience",
		&"bed_score": &"Music",
		&"board_tear": &"Effects",
		&"round_start": &"Music",
		&"ui_press": &"UI",
	}
	for id: StringName in expected:
		assert_str(SoundCatalog.get_def(id).bus).override_failure_message(id).is_equal(expected[id])


func test_the_layout_has_a_bus_for_every_kind_of_sound_and_each_has_a_volume_setting() -> void:
	for bus_name: StringName in [&"Master", &"Music", &"Effects", &"Voice", &"Ambience", &"UI"]:
		(
			assert_int(AudioServer.get_bus_index(bus_name))
			. override_failure_message(bus_name)
			. is_greater_equal(0)
		)
		(
			assert_bool(SettingsService.BUSES.values().has(bus_name))
			. override_failure_message(bus_name)
			. is_true()
		)


func test_a_sting_does_not_duck_the_ui() -> void:
	var bus := AudioServer.get_bus_index(&"UI")
	var before := AudioServer.get_bus_volume_db(bus)
	_audio.play(&"round_start")
	_audio.advance(0.3)
	assert_float(AudioServer.get_bus_volume_db(bus)).is_equal(before)


func test_leaving_the_tree_lets_the_duck_go() -> void:
	var extra := AudioService.new()
	add_child(extra)
	extra.play(&"round_start")
	extra.advance(0.3)
	assert_float(_duck_bus_db()).is_less(-8.0)
	extra.free()
	assert_float(_duck_bus_db()).is_equal(0.0)


func test_a_wall_and_the_rear_are_told_by_volume_where_the_filter_is_not_heard() -> void:
	_audio.filters_apply = false
	var front := Vector3(0, 0, -10)
	var behind := Vector3(0, 0, 10)
	var open := _audio.play(&"zombie_groan", front) as AudioStreamPlayer3D
	var open_db := open.volume_db
	_audio.stop_all()
	var back := _audio.play(&"zombie_groan", behind) as AudioStreamPlayer3D
	assert_float(back.volume_db).is_equal_approx(open_db + AudioService.NO_FILTER_REAR_DB, 0.001)
	_audio.stop_all()
	_audio.occlusion_probe = func(_from: Vector3, _to: Vector3) -> float: return 1.0
	var blocked := _audio.play(&"zombie_groan", front) as AudioStreamPlayer3D
	var wall := AudioService.OCCLUSION_DB + AudioService.NO_FILTER_OCCLUSION_DB
	assert_float(blocked.volume_db).is_equal_approx(open_db + wall, 0.001)


func test_where_the_filter_is_heard_volume_is_left_to_the_usual_drop() -> void:
	_audio.filters_apply = true
	var front := Vector3(0, 0, -10)
	var open := _audio.play(&"zombie_groan", front) as AudioStreamPlayer3D
	var open_db := open.volume_db
	_audio.stop_all()
	var back := _audio.play(&"zombie_groan", Vector3(0, 0, 10)) as AudioStreamPlayer3D
	assert_float(back.volume_db).is_equal_approx(open_db, 0.001)
	_audio.stop_all()
	_audio.occlusion_probe = func(_from: Vector3, _to: Vector3) -> float: return 1.0
	var blocked := _audio.play(&"zombie_groan", front) as AudioStreamPlayer3D
	assert_float(blocked.volume_db).is_equal_approx(open_db + AudioService.OCCLUSION_DB, 0.001)


func test_a_desktop_and_a_stream_build_hear_the_filter_and_a_sample_build_does_not() -> void:
	assert_bool(AudioService.players_apply_filters()).is_equal(not OS.has_feature("web"))


func test_the_ui_hook_plays_the_cue_s_sound() -> void:
	assert_bool(UIAudio.handler.is_valid()).is_true()
	UIAudio.play(&"press")
	assert_int(_audio.budget_2d().active_count()).is_equal(1)
	assert_str(_audio.budget_2d().sound_at(0)).is_equal("ui_press")
	UIAudio.play(&"nonsense")
	assert_int(_audio.budget_2d().active_count()).is_equal(1)


func test_hover_and_focus_in_the_same_moment_make_one_sound() -> void:
	var ticket: Button = auto_free(Button.new())
	add_child(ticket)
	UiSounds.tag(ticket, &"ticket")
	UIInputMode.pointer = true
	UIAudio.play(&"hover", ticket)
	UIAudio.play(&"focus", ticket)
	assert_int(_audio.budget_2d().active_count()).is_equal(1)
	# A press and the screen change that follows it both sound.
	UIAudio.play(&"press", ticket)
	UIAudio.play(&"push")
	assert_int(_audio.budget_2d().active_count()).is_equal(3)


func test_the_rules_start_and_end_a_round_with_a_sting() -> void:
	var rules := RulesFixture.make_rules(1)
	_audio.connect_rules(rules)
	rules.event_emitted.emit({"type": &"round_started", "round": 1})
	assert_str(_audio.budget_2d().sound_at(0)).is_equal("round_start")
	_audio.advance(10.0)
	rules.event_emitted.emit({"type": &"round_ended", "round": 1})
	assert_str(_audio.budget_2d().sound_at(0)).is_equal("round_end")
	_audio.connect_rules(null)


func test_a_loop_lives_on_its_parent_and_loops() -> void:
	var generator: Node3D = auto_free(Node3D.new())
	add_child(generator)
	var hum := _audio.start_loop(&"generator_hum", generator)
	assert_object(hum).is_not_null()
	assert_object(hum.get_parent()).is_same(generator)
	assert_bool((hum.stream as AudioStreamOggVorbis).loop).is_true()
	assert_bool(hum.playing).is_true()
