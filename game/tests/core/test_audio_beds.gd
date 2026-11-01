extends GdUnitTestSuite
## The service's beds: a looping flat sound that fades in and out on the service's own clock, in
## players of its own that the voice budget never counts.

var _audio: AudioService


func before_test() -> void:
	_audio = AudioService.new()
	_audio.seed_random(3)
	add_child(_audio)


func after_test() -> void:
	_audio.free()
	Audio.install_ui_hook()


func test_a_bed_loops_on_its_bus_and_starts_silent() -> void:
	var player := _audio.start_bed(&"bed_crickets")
	assert_object(player).is_not_null()
	assert_bool(player.playing).is_true()
	assert_str(player.bus).is_equal("Effects")
	assert_bool((player.stream as AudioStreamOggVorbis).loop).is_true()
	assert_float(_audio.bed_fade_db(&"bed_crickets")).is_equal(AudioService.BED_SILENT_DB)
	assert_float(player.volume_db).is_less(-70.0)


func test_a_bed_fades_in_over_three_seconds_to_its_own_level() -> void:
	var player := _audio.start_bed(&"bed_highway")
	var level := SoundCatalog.get_def(&"bed_highway").volume_db
	_audio.advance(1.0)
	assert_float(_audio.bed_fade_db(&"bed_highway")).is_equal_approx(-40.0, 0.01)
	_audio.advance(2.0)
	assert_float(_audio.bed_fade_db(&"bed_highway")).is_equal(0.0)
	assert_float(player.volume_db).is_equal_approx(level, 0.01)
	_audio.advance(5.0)
	assert_float(player.volume_db).is_equal_approx(level, 0.01)


func test_a_bed_fades_out_and_frees_its_player() -> void:
	var player := _audio.start_bed(&"bed_score")
	_audio.advance(4.0)
	_audio.stop_bed(&"bed_score")
	_audio.advance(1.0)
	assert_bool(_audio.is_bed_running(&"bed_score")).is_true()
	assert_float(_audio.bed_fade_db(&"bed_score")).is_equal_approx(-30.0, 0.01)
	_audio.advance(1.1)
	assert_bool(_audio.is_bed_running(&"bed_score")).is_false()
	assert_bool(player.playing).is_false()


func test_starting_a_running_bed_turns_it_back_up_on_the_same_player() -> void:
	var first := _audio.start_bed(&"bed_score")
	_audio.advance(4.0)
	_audio.stop_bed(&"bed_score")
	_audio.advance(0.5)
	var again := _audio.start_bed(&"bed_score")
	assert_object(again).is_same(first)
	_audio.advance(5.0)
	assert_float(_audio.bed_fade_db(&"bed_score")).is_equal(0.0)


func test_beds_have_players_of_their_own_and_cost_the_budget_nothing() -> void:
	var children := _audio.get_child_count()
	for id: StringName in [&"bed_crickets", &"bed_highway", &"bed_score"]:
		assert_object(_audio.start_bed(id)).is_not_null()
	assert_int(_audio.get_child_count()).is_equal(children)
	assert_int(_audio.active_voices()).is_equal(0)
	assert_object(_audio.play(&"shot_pistol", Vector3(0, 0, 3))).is_not_null()


func test_an_unknown_bed_is_dropped_and_the_pool_is_not_overrun() -> void:
	assert_object(_audio.start_bed(&"no_such_bed")).is_null()
	for i in AudioService.POOL_BEDS:
		# The same four ids cannot fill the pool: only distinct running beds take a player.
		_audio.start_bed(&"bed_crickets")
	assert_object(_audio.start_bed(&"bed_highway")).is_not_null()
	assert_object(_audio.start_bed(&"bed_score")).is_not_null()


func test_stop_all_silences_the_beds_at_once() -> void:
	_audio.start_bed(&"bed_crickets")
	_audio.start_bed(&"bed_highway")
	_audio.stop_all()
	assert_bool(_audio.is_bed_running(&"bed_crickets")).is_false()
	assert_bool(_audio.is_bed_running(&"bed_highway")).is_false()


func test_the_beds_files_are_whole_loops() -> void:
	for id: StringName in [&"bed_crickets", &"bed_highway", &"bed_projector", &"bed_score"]:
		var def := SoundCatalog.get_def(id)
		var stream := load(def.path_for(1)) as AudioStreamOggVorbis
		var seconds := stream.get_length()
		# Rendered as an exact number of seconds, so the loop point is the end of the file.
		assert_float(seconds).override_failure_message(id).is_equal_approx(roundf(seconds), 0.002)
