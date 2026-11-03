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
	var def := SoundCatalog.get_def(&"grenade_bounce")
	assert_float(def.near_cap_db).is_equal(INF)
	var player := _audio.play(&"grenade_bounce", Vector3(0.0, 0.0, -2.0)) as AudioStreamPlayer3D
	assert_object(player).is_not_null()
	assert_float(player.max_db).is_equal(3.0)


func test_a_loud_sound_is_held_under_its_trim_close_up() -> void:
	# A negative cap puts the near level under the trim (#753): the last board has a +4 dB trim and
	# is held more than 9 dB under it, so a shot landing on it leaves room under full scale.
	var def := SoundCatalog.get_def(&"board_last")
	assert_float(def.near_cap_db).is_less(0.0)
	var player := _audio.play(&"board_last", Vector3(0.0, 0.0, -2.0)) as AudioStreamPlayer3D
	assert_object(player).is_not_null()
	assert_float(player.max_db).is_equal_approx(player.volume_db + def.near_cap_db, 0.001)
	assert_float(player.max_db).is_less(player.volume_db)


func test_a_sound_without_a_cap_after_a_capped_one_on_one_slot_keeps_the_engines_ceiling() -> void:
	var capped := _audio.play(&"shot_rifle", Vector3(0.0, 0.0, -2.0)) as AudioStreamPlayer3D
	assert_object(capped).is_not_null()
	assert_float(capped.max_db).is_less(3.0)
	# Everything stopped, so the next sound takes the same slot (the lowest free one).
	_audio.stop_all()
	var uncapped := _audio.play(&"grenade_bounce", Vector3(0.0, 0.0, -2.0)) as AudioStreamPlayer3D
	assert_object(uncapped).is_same(capped)
	assert_float(uncapped.max_db).is_equal(AudioService.ENGINE_MAX_DB)


func test_no_sounds_level_depends_on_what_the_slot_played_before() -> void:
	var at := Vector3(0.0, 0.0, -2.0)
	var played := 0
	for id in SoundCatalog.ids():
		# A loud capped sound has used the slot, then every sound in the catalog takes it in turn.
		_audio.stop_all()
		assert_object(_audio.play(&"shot_rifle", at)).is_not_null()
		_audio.stop_all()
		var player := _audio.play(id, at) as AudioStreamPlayer3D
		if player == null:
			continue
		played += 1
		var def := SoundCatalog.get_def(id)
		var expected := AudioService.ENGINE_MAX_DB
		if def.near_cap_db < INF:
			expected = player.volume_db + def.near_cap_db
		(
			assert_float(player.max_db)
			. override_failure_message(
				"%s: max_db %.2f, expected %.2f" % [id, player.max_db, expected]
			)
			. is_equal_approx(expected, 0.001)
		)
		assert_float(player.unit_size).is_equal(def.unit_size)
		assert_float(player.max_distance).is_equal(def.max_distance)
	assert_int(played).is_greater(20)


func test_a_flat_sound_after_another_on_one_slot_is_set_from_its_own_definition() -> void:
	var first := _audio.play(&"zombie_attack", null, 6.0) as AudioStreamPlayer
	assert_object(first).is_not_null()
	_audio.stop_all()
	var second := _audio.play(&"ui_press") as AudioStreamPlayer
	assert_object(second).is_same(first)
	var def := SoundCatalog.get_def(&"ui_press")
	assert_str(String(second.bus)).is_equal(String(def.bus))
	assert_float(second.volume_db).is_equal_approx(def.volume_db, 0.001)


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
