extends GdUnitTestSuite
## What starting a sound costs, kept down: a short sound plays from samples decoded once (not from
## the Ogg file, whose headers the engine reads again at every play), and the night limits how many
## sounds start in one frame, the rest following in the next frames, highest priority first.

## A short sound with a few variants, one with a place, and one longer than the limit.
const SHORT := &"impact_flesh"
const LONG := &"bed_crickets"

var _audio: AudioService
var _listener: Node3D


func before_test() -> void:
	_listener = auto_free(Node3D.new())
	add_child(_listener)
	_audio = AudioService.new()
	_audio.listener = _listener
	_audio.seed_random(7)
	add_child(_audio)
	# The clock is moved by hand, so a waiting sound starts when the test says.
	_audio.set_process(false)


func after_test() -> void:
	_audio.free()
	Audio.install_ui_hook()


func _preload(id: StringName) -> void:
	_audio.preload_sound(id)


func test_a_short_sound_is_decoded_to_samples_of_its_own_length() -> void:
	var def := SoundCatalog.get_def(SHORT)
	var ogg := load(def.path_for(1)) as AudioStreamOggVorbis
	var wav := PcmStream.decode(ogg, int(AudioServer.get_mix_rate()))
	assert_float(wav.get_length()).is_equal_approx(ogg.get_length(), 0.06)
	assert_int(wav.format).is_equal(AudioStreamWAV.FORMAT_16_BITS)
	assert_int(wav.mix_rate).is_equal(int(AudioServer.get_mix_rate()))
	# It is the sound, not silence: some sample is well above zero.
	var peak := 0
	for i in range(0, wav.data.size() - 1, 2):
		peak = maxi(peak, absi(wav.data.decode_s16(i)))
	assert_int(peak).is_greater(1000)


func test_a_preloaded_short_sound_plays_from_samples_and_a_long_one_stays_ogg() -> void:
	_preload(SHORT)
	var short := _audio.play(SHORT) as AudioStreamPlayer
	assert_object(short).is_not_null()
	assert_object(short.stream).is_instanceof(AudioStreamWAV)
	var def := SoundCatalog.get_def(LONG)
	_preload(LONG)
	assert_object(_audio._pick_stream(def, true)).is_instanceof(AudioStreamOggVorbis)


func test_a_sound_that_is_not_preloaded_still_plays_from_its_file() -> void:
	var player := _audio.play(SHORT) as AudioStreamPlayer
	assert_object(player).is_not_null()
	assert_object(player.stream).is_instanceof(AudioStreamOggVorbis)


func test_no_more_sounds_start_in_a_frame_than_the_limit_and_the_rest_follow() -> void:
	_audio.starts_per_frame = 2
	var ids: Array[StringName] = [&"impact_flesh", &"zombie_death", &"points_tick", &"points_kill"]
	for id in ids:
		_audio.play(id)
	assert_int(_audio.started).is_equal(2)
	# The next frames start the others (the service's clock is moved by hand here).
	await get_tree().process_frame
	_audio.advance(0.016)
	assert_int(_audio.started).is_equal(4)


func test_a_waiting_sound_that_is_too_late_is_dropped() -> void:
	_audio.starts_per_frame = 1
	_audio.play(&"impact_flesh")
	_audio.play(&"zombie_death")
	assert_int(_audio.started).is_equal(1)
	await get_tree().process_frame
	_audio.advance(AudioService.DEFER_MAX_SECONDS + 0.05)
	assert_int(_audio.started).is_equal(1)


func test_the_loudest_priority_waits_least() -> void:
	_audio.starts_per_frame = 1
	var low := SoundCatalog.get_def(&"points_tick")
	var high := SoundCatalog.get_def(&"points_kill")
	assert_int(high.priority).is_greater(low.priority)
	var order: Array[StringName] = []
	_audio.played.connect(func(id: StringName, _at: Variant) -> void: order.append(id))
	_audio.play(&"impact_flesh")  # takes the frame's start
	_audio.play(&"points_tick")
	_audio.play(&"points_kill")
	await get_tree().process_frame
	_audio.advance(0.016)
	assert_array(order).is_equal([&"impact_flesh", &"points_kill"])


func test_a_kept_bed_is_paused_when_it_fades_out_and_comes_back_without_starting_again() -> void:
	_audio.start_bed(&"bed_score", true)
	assert_bool(_audio.is_bed_running(&"bed_score")).is_false()
	var player := _audio._beds[&"bed_score"]["player"] as AudioStreamPlayer
	assert_bool(player.stream_paused).is_true()
	assert_object(_audio.start_bed(&"bed_score")).is_same(player)
	assert_bool(player.stream_paused).is_false()
	assert_bool(player.playing).is_true()
	assert_bool(_audio.is_bed_running(&"bed_score")).is_true()
	_audio.advance(5.0)
	assert_float(_audio.bed_fade_db(&"bed_score")).is_equal(0.0)
	_audio.stop_bed(&"bed_score")
	_audio.advance(5.0)
	assert_bool(_audio.is_bed_running(&"bed_score")).is_false()
	assert_bool(player.stream_paused).is_true()
	assert_object(_audio.start_bed(&"bed_score")).is_same(player)
	_audio.stop_beds(true)
	assert_bool(player.playing).is_false()
