# The special round sting: in the catalog like the other stings, a real file of the right length,
# played when the rules announce a special round, ducking the effects under it.
extends GdUnitTestSuite

var _audio: AudioService


func before_test() -> void:
	_audio = AudioService.new()
	_audio.seed_random(7)
	add_child(_audio)


func after_test() -> void:
	_audio.free()
	Audio.install_ui_hook()


func test_the_sting_is_a_sting_of_the_music_bus_with_a_file() -> void:
	var def := SoundCatalog.get_def(&"special_round")
	assert_object(def).is_not_null()
	assert_str(String(def.group)).is_equal("sting")
	assert_str(String(def.bus)).is_equal(String(SoundCatalog.BUS_MUSIC))
	assert_bool(ResourceLoader.exists(def.path_for(1))).is_true()
	assert_float(def.duck_db).is_less(0.0)


func test_the_sting_is_long_enough_to_be_a_cue_and_short_enough_to_be_a_sting() -> void:
	var stream := load(SoundCatalog.get_def(&"special_round").path_for(1)) as AudioStreamOggVorbis
	assert_object(stream).is_not_null()
	# Bulbs ticking on, a reel whirring up, two stabs and a gong: about three and a half seconds.
	assert_float(stream.get_length()).is_between(2.5, 5.0)


func test_the_announcement_plays_it_once() -> void:
	var rules := RulesFixture.make_rules(1, 3, RulesFixture.tuning())
	_audio.connect_rules(rules)
	rules.apply(RulesAction.start())
	assert_int(_audio.active_voices()).is_equal(0)
	# A break before round 5 is the announcement; the rules emit it once.
	var announced := RulesFixture.record(rules)
	rules.event_emitted.emit({"type": &"special_round_announced", "round": 5})
	assert_int(_audio.active_voices()).is_equal(1)
	assert_int(announced.of(&"special_round_announced").size()).is_equal(1)


func _sting_playing() -> StringName:
	var budget := _audio.budget_2d()
	for slot in budget.slot_count:
		if (
			budget.is_active(slot)
			and budget.sound_at(slot) in [&"round_start", &"round_end", &"special_round"]
		):
			return budget.sound_at(slot)
	return &""


func test_the_announcement_takes_over_from_the_round_end_sting_that_is_still_sounding() -> void:
	# The rules end the round and announce the next one in the same moment, so the round's own sting
	# is playing when the announcement arrives; only one sting sounds at a time.
	var rules := RulesFixture.make_rules(1, 3, RulesFixture.tuning())
	_audio.connect_rules(rules)
	rules.event_emitted.emit({"type": &"round_ended", "round": 4})
	assert_str(String(_sting_playing())).is_equal("round_end")
	rules.event_emitted.emit({"type": &"special_round_announced", "round": 5})
	assert_str(String(_sting_playing())).is_equal("special_round")
	assert_int(_audio.budget_2d().group_count(&"sting")).is_equal(1)


func test_a_round_start_sting_does_not_cut_the_announcement_off() -> void:
	var rules := RulesFixture.make_rules(1, 3, RulesFixture.tuning())
	_audio.connect_rules(rules)
	rules.event_emitted.emit({"type": &"special_round_announced", "round": 5})
	rules.event_emitted.emit({"type": &"round_started", "round": 5})
	assert_str(String(_sting_playing())).is_equal("special_round")


func test_the_announcement_takes_over_even_from_a_round_start_sting_of_a_very_short_round() -> void:
	# Same loudness as the announcement: only its priority lets it through.
	var rules := RulesFixture.make_rules(1, 3, RulesFixture.tuning())
	_audio.connect_rules(rules)
	rules.event_emitted.emit({"type": &"round_started", "round": 4})
	rules.event_emitted.emit({"type": &"round_ended", "round": 4})
	rules.event_emitted.emit({"type": &"special_round_announced", "round": 5})
	assert_str(String(_sting_playing())).is_equal("special_round")
