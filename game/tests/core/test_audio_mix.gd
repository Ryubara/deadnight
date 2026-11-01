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


func test_a_sting_ducks_the_effects_bus_then_lets_it_back() -> void:
	var bus := AudioServer.get_bus_index(&"Effects")
	assert_float(_audio.duck_db).is_equal(0.0)
	_audio.play(&"round_start")
	_audio.advance(0.2)
	assert_float(_audio.duck_db).is_less(-8.0)
	# The bus carries it in an effect of its own; the player's volume setting is untouched.
	var amplify: AudioEffectAmplify
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectAmplify:
			amplify = AudioServer.get_bus_effect(bus, i)
	assert_object(amplify).is_not_null()
	assert_float(amplify.volume_db).is_equal_approx(_audio.duck_db, 0.001)
	var held := SoundCatalog.get_def(&"round_start").duck_hold
	_audio.advance(held)
	_audio.advance(1.0)
	_audio.advance(1.0)
	assert_float(_audio.duck_db).is_equal(0.0)


func test_a_sting_does_not_duck_the_ui() -> void:
	var bus := AudioServer.get_bus_index(&"UI")
	var before := AudioServer.get_bus_volume_db(bus)
	_audio.play(&"round_start")
	_audio.advance(0.3)
	assert_float(AudioServer.get_bus_volume_db(bus)).is_equal(before)


func test_leaving_the_tree_takes_the_duck_effect_off_the_bus() -> void:
	var bus := AudioServer.get_bus_index(&"Effects")
	var count := AudioServer.get_bus_effect_count(bus)
	var extra := AudioService.new()
	add_child(extra)
	assert_int(AudioServer.get_bus_effect_count(bus)).is_equal(count + 1)
	extra.free()
	assert_int(AudioServer.get_bus_effect_count(bus)).is_equal(count)


func test_the_ui_hook_plays_the_cue_s_sound() -> void:
	assert_bool(UIAudio.handler.is_valid()).is_true()
	UIAudio.play(&"press")
	assert_int(_audio.budget_2d().active_count()).is_equal(1)
	assert_str(_audio.budget_2d().sound_at(0)).is_equal("ui_press")
	UIAudio.play(&"nonsense")
	assert_int(_audio.budget_2d().active_count()).is_equal(1)


func test_hover_and_focus_in_the_same_moment_make_one_sound() -> void:
	UIAudio.play(&"hover")
	UIAudio.play(&"focus")
	assert_int(_audio.budget_2d().active_count()).is_equal(1)
	# A press and the screen change that follows it both sound.
	UIAudio.play(&"press")
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
