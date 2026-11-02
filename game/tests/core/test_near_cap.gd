extends GdUnitTestSuite
## The engine boosts a 3D sound by unit_size / distance as it comes close and stops only at the
## player's max_db (+3 dB over the file), so every close sound ends up equally hot whatever its
## trim. A sound with a `near_cap_db` keeps its own level instead: the trim is what you hear up
## close.

var _audio: AudioService
var _listener: Node3D


func before_test() -> void:
	_listener = auto_free(Node3D.new())
	add_child(_listener)
	_audio = AudioService.new()
	_audio.listener = _listener
	_audio.seed_random(3)
	add_child(_audio)


func after_test() -> void:
	_audio.free()
	Audio.install_ui_hook()


func test_a_gun_close_up_is_held_to_its_own_level() -> void:
	var def := SoundCatalog.get_def(&"shot_rifle")
	assert_float(def.near_cap_db).is_equal(0.0)
	var player := _audio.play(&"shot_rifle", Vector3(0.0, 0.0, -1.7)) as AudioStreamPlayer3D
	assert_object(player).is_not_null()
	# Ceiling: the trim plus the play's own small level wobble, never the engine's +3 dB.
	assert_float(player.max_db).is_equal_approx(player.volume_db, 0.001)
	assert_float(player.max_db).is_less(3.0)


func test_a_sound_without_a_cap_keeps_the_engines_ceiling() -> void:
	var def := SoundCatalog.get_def(&"step_asphalt")
	assert_float(def.near_cap_db).is_equal(INF)
	var player := _audio.play(&"step_asphalt", Vector3(0.0, 0.0, -2.0)) as AudioStreamPlayer3D
	assert_object(player).is_not_null()
	assert_float(player.max_db).is_equal(3.0)


func test_every_arms_sound_carries_a_cap() -> void:
	for id in SoundCatalog.ids():
		var text := String(id)
		if (
			text.begins_with("shot_")
			or text.begins_with("tail_")
			or text.begins_with("reload_")
			or text.begins_with("impact_")
			or text.begins_with("buy_")
			or text.begins_with("crane")
			or text.begins_with("breaker_")
		):
			(
				assert_float(SoundCatalog.get_def(id).near_cap_db)
				. override_failure_message(text)
				. is_equal(0.0)
			)
