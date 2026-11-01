extends GdUnitTestSuite
## The audio service with real players and real files: the catalog is complete, plays are pooled and
## limited, variants and pitch are seeded, distance and occlusion shape a sound, a sting ducks the
## Effects bus and the UI hook is wired.

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


func test_every_catalog_sound_has_all_its_variant_files() -> void:
	assert_int(SoundCatalog.ids().size()).is_greater(25)
	for id: StringName in SoundCatalog.ids():
		var def := SoundCatalog.get_def(id)
		(
			assert_bool(SoundCatalog.GROUP_LIMITS.has(def.group))
			. override_failure_message("%s: group %s has no limit" % [id, def.group])
			. is_true()
		)
		(
			assert_int(AudioServer.get_bus_index(def.bus))
			. override_failure_message("%s: no bus %s" % [id, def.bus])
			. is_greater_equal(0)
		)
		for variant in range(1, def.variants + 1):
			var path := def.path_for(variant)
			(
				assert_bool(ResourceLoader.exists(path))
				. override_failure_message("missing " + path)
				. is_true()
			)
			assert_object(load(path)).is_instanceof(AudioStreamOggVorbis)


func test_every_ui_cue_the_addon_can_send_has_a_sound() -> void:
	for cue: StringName in [&"hover", &"press", &"focus", &"back", &"push", &"pop", &"tick"]:
		var id: StringName = SoundCatalog.UI_CUES.get(cue, &"")
		assert_object(SoundCatalog.get_def(id)).override_failure_message("cue " + cue).is_not_null()


func test_a_flat_sound_plays_on_a_pooled_player() -> void:
	var children := _audio.get_child_count()
	var player := _audio.play(&"round_end") as AudioStreamPlayer
	assert_object(player).is_not_null()
	assert_bool(player.playing).is_true()
	assert_str(player.bus).is_equal("Music")
	assert_int(_audio.get_child_count()).is_equal(children)


func test_a_world_sound_plays_where_it_was_asked_for() -> void:
	var player := _audio.play(&"shot_pistol", Vector3(4, 1, -3)) as AudioStreamPlayer3D
	assert_object(player).is_not_null()
	assert_bool(player.playing).is_true()
	assert_vector(player.global_position).is_equal(Vector3(4, 1, -3))
	assert_str(player.bus).is_equal("Effects")


func test_an_unknown_sound_is_dropped_not_fatal() -> void:
	assert_object(_audio.play(&"no_such_sound")).is_null()
	assert_int(_audio.active_voices()).is_equal(0)


func test_a_variant_never_repeats_back_to_back() -> void:
	var last := ""
	for i in 40:
		_audio.advance(1.0)
		var player := _audio.play(&"zombie_groan", Vector3(0, 0, 3)) as AudioStreamPlayer3D
		assert_object(player).is_not_null()
		var path := player.stream.resource_path
		assert_str(path).is_not_equal(last)
		last = path


func test_the_same_seed_gives_the_same_variants_and_pitches() -> void:
	var first := _run_sequence(99)
	var second := _run_sequence(99)
	var other := _run_sequence(100)
	assert_array(first).is_equal(second)
	assert_array(first).is_not_equal(other)


func test_pitch_stays_within_the_sound_s_range() -> void:
	var def := SoundCatalog.get_def(&"step_gravel")
	var spread := pow(2.0, def.pitch_semitones / 12.0)
	var lowest := INF
	var highest := -INF
	for i in 60:
		_audio.advance(1.0)
		var player := _audio.play(&"step_gravel", Vector3(0, 0, 2)) as AudioStreamPlayer3D
		lowest = minf(lowest, player.pitch_scale)
		highest = maxf(highest, player.pitch_scale)
	assert_float(lowest).is_greater_equal(1.0 / spread - 0.0001)
	assert_float(highest).is_less_equal(spread + 0.0001)
	assert_float(highest - lowest).is_greater(0.05)


func test_a_sound_past_its_range_is_not_started() -> void:
	var def := SoundCatalog.get_def(&"step_asphalt")
	assert_object(_audio.play(&"step_asphalt", Vector3(0, 0, def.max_distance + 1.0))).is_null()
	assert_int(_audio.culled).is_equal(1)
	assert_int(_audio.active_voices()).is_equal(0)
	assert_object(_audio.play(&"step_asphalt", Vector3(0, 0, def.max_distance - 1.0))).is_not_null()


func test_gunfire_is_limited_to_its_group_and_makes_no_new_nodes() -> void:
	var children := _audio.get_child_count()
	var limit: int = SoundCatalog.GROUP_LIMITS[&"gun"]
	for i in 60:
		_audio.play(&"shot_rifle", Vector3(0, 0, 4.0 + i * 0.01))
	assert_int(_audio.budget_3d().group_count(&"gun")).is_less_equal(limit)
	assert_int(_audio.get_child_count()).is_equal(children)


func test_28_zombies_do_not_drown_the_night() -> void:
	var limit: int = SoundCatalog.GROUP_LIMITS[&"zombie_voice"]
	# Zombie i stands i + 2 metres away, the nearest first; all groan in the same instant.
	for i in 28:
		_audio.play(&"zombie_groan", Vector3(i + 2.0, 0, 0))
	assert_int(_audio.budget_3d().group_count(&"zombie_voice")).is_equal(limit)
	var playing: Array[float] = []
	for child in _audio.get_children():
		if child is AudioStreamPlayer3D and child.playing:
			playing.append(child.global_position.x)
	playing.sort()
	assert_int(playing.size()).is_equal(limit)
	# The six nearest were first in, and farther ones are not clearly louder, so none replaced them.
	assert_float(playing[0]).is_equal(2.0)
	assert_float(playing[limit - 1]).is_equal(2.0 + limit - 1)
	# The player's own shot still gets through.
	assert_object(_audio.play(&"shot_pistol", Vector3(0, 0, 1))).is_not_null()


func test_a_nearer_zombie_takes_over_from_a_farther_one() -> void:
	var limit: int = SoundCatalog.GROUP_LIMITS[&"zombie_voice"]
	for i in limit:
		_audio.play(&"zombie_groan", Vector3(30.0, 0, 0))
	var near := _audio.play(&"zombie_groan", Vector3(3.0, 0, 0)) as AudioStreamPlayer3D
	assert_object(near).is_not_null()
	assert_int(_audio.budget_3d().group_count(&"zombie_voice")).is_equal(limit)


func test_stop_all_frees_every_voice() -> void:
	_audio.play(&"shot_pistol", Vector3(0, 0, 3))
	_audio.play(&"round_end")
	assert_int(_audio.active_voices()).is_equal(2)
	_audio.stop_all()
	assert_int(_audio.active_voices()).is_equal(0)


func test_waiting_for_the_mixer_lets_the_audio_server_drop_a_stopped_voice() -> void:
	# A stopped voice's playback stays in the audio server, holding the stream, until its mixer
	# thread has taken a few steps; quitting before that is reported as a leak.
	var stream := load(SoundCatalog.get_def(&"round_end").path_for(1)) as AudioStream
	await _audio.wait_for_mixer()
	var held := stream.get_reference_count()
	var player := auto_free(AudioStreamPlayer.new()) as AudioStreamPlayer
	add_child(player)
	player.stream = stream
	player.play()
	player.stop()
	player.stream = null
	await _audio.wait_for_mixer()
	assert_int(stream.get_reference_count()).is_equal(held)


## Plays a fixed run of sounds with the given seed and returns each one's file and pitch.
func _run_sequence(seed_value: int) -> Array:
	_audio.stop_all()
	_audio.seed_random(seed_value)
	var out := []
	for i in 12:
		_audio.advance(1.0)
		var player := _audio.play(&"shot_smg", Vector3(0, 0, 5)) as AudioStreamPlayer3D
		out.append([player.stream.resource_path, snappedf(player.pitch_scale, 0.00001)])
	return out
