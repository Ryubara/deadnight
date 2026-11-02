extends GdUnitTestSuite
## When the soldier may speak, on a clock the test moves by hand: one line at a time, downed over
## hurt over everything else, a cooldown per moment and speaker, and no take repeated back to back.

const LINE := 2.0

var _director: VoiceDirector


func before_test() -> void:
	_director = VoiceDirector.new()
	_director.seed_random(7)


## Chooses and, if something was chosen, commits a line of `LINE` seconds. Returns the take. A
## moment that is only voiced some of the time is asked again (each ask is a new roll, and one the
## gates refuse stays refused), so a test about the gates does not depend on the roll.
func _say(event: StringName, speaker := 1) -> int:
	for attempt in 30:
		var take := _try(event, speaker)
		if take != 0:
			return take
	return 0


## One ask, one roll.
func _try(event: StringName, speaker := 1) -> int:
	var take := _director.choose(event, speaker)
	if take != 0:
		_director.commit(event, speaker, take, LINE)
	return take


func test_every_moment_picks_a_take_that_exists() -> void:
	for event: StringName in SoldierVoiceCatalog.events():
		var take := VoiceDirector.new().choose(event, 1)
		var info: Dictionary = SoldierVoiceCatalog.EVENTS[event]
		if info["chance"] >= 1.0:
			assert_int(take).override_failure_message(String(event)).is_between(1, info["takes"])


func test_an_unknown_moment_says_nothing() -> void:
	assert_int(_director.choose(&"no_such_moment")).is_equal(0)


func test_two_lines_never_overlap() -> void:
	assert_int(_say(&"round_start")).is_not_equal(0)
	_director.advance(LINE - 0.1)
	assert_bool(_director.is_speaking()).is_true()
	assert_int(_say(&"round_clear")).is_equal(0)
	assert_int(_say(&"idle")).is_equal(0)


func test_a_gap_of_silence_follows_every_line() -> void:
	_say(&"round_start")
	_director.advance(LINE + VoiceDirector.GAP * 0.5)
	assert_bool(_director.is_speaking()).is_false()
	assert_float(_director.wait()).is_equal_approx(VoiceDirector.GAP * 0.5, 0.001)
	assert_int(_say(&"round_clear")).is_equal(0)
	_director.advance(VoiceDirector.GAP * 0.5 + 0.01)
	assert_int(_say(&"round_clear")).is_not_equal(0)


func test_a_dropped_request_is_not_queued() -> void:
	_say(&"round_start")
	assert_int(_say(&"door")).is_equal(0)
	_director.advance(LINE + VoiceDirector.GAP + 5.0)
	assert_int(_director.history.size()).is_equal(1)


func test_downed_cuts_a_line_and_hurt_cuts_an_ordinary_one() -> void:
	_say(&"round_start")
	_director.advance(0.5)
	(
		assert_bool(_director.would_interrupt(SoldierVoiceCatalog.EVENTS[&"hurt"]["priority"]))
		. is_true()
	)
	assert_int(_say(&"hurt")).is_not_equal(0)
	_director.advance(0.5)
	(
		assert_bool(_director.would_interrupt(SoldierVoiceCatalog.EVENTS[&"downed"]["priority"]))
		. is_true()
	)
	assert_int(_say(&"downed")).is_not_equal(0)
	assert_str(_director.history.back()["event"]).is_equal("downed")


func test_hurt_does_not_cut_downed_and_neither_cuts_an_equal() -> void:
	_say(&"downed")
	_director.advance(0.5)
	assert_int(_say(&"hurt")).is_equal(0)
	assert_int(_say(&"downed", 2)).is_equal(0)


func test_an_ordinary_line_cuts_only_one_far_below_it() -> void:
	_say(&"reload")
	_director.advance(0.5)
	assert_int(_say(&"low_ammo")).is_equal(0)
	assert_int(_say(&"round_start")).is_equal(0)
	assert_int(_say(&"close_call")).is_not_equal(0)
	_director.advance(100.0)
	_say(&"kill")
	_director.advance(0.2)
	assert_int(_say(&"streak")).is_not_equal(0)
	_director.advance(100.0)
	_say(&"idle")
	_director.advance(0.2)
	assert_int(_say(&"boss_arrive")).is_not_equal(0)


func test_a_line_does_not_cut_one_of_nearly_its_own_rank() -> void:
	_say(&"streak")
	_director.advance(0.5)
	for event: StringName in [&"dry", &"round_start", &"grenade", &"reload", &"power_low"]:
		assert_int(_say(event)).override_failure_message(String(event)).is_equal(0)


func test_the_priorities_rank_downed_over_hurt_over_the_rest() -> void:
	var downed: int = SoldierVoiceCatalog.EVENTS[&"downed"]["priority"]
	var hurt: int = SoldierVoiceCatalog.EVENTS[&"hurt"]["priority"]
	assert_int(downed).is_greater(hurt)
	for event: StringName in SoldierVoiceCatalog.events():
		if event != &"downed" and event != &"hurt":
			var priority: int = SoldierVoiceCatalog.EVENTS[event]["priority"]
			assert_int(hurt).override_failure_message(String(event)).is_greater(priority)
			assert_int(priority).override_failure_message(String(event)).is_less(
				VoiceDirector.INTERRUPT_PRIORITY
			)


func test_a_moment_has_a_cooldown_for_each_speaker() -> void:
	var cooldown: float = SoldierVoiceCatalog.EVENTS[&"power_low"]["cooldown"]
	assert_bool(cooldown > LINE + VoiceDirector.GAP).is_true()
	assert_int(_say(&"power_low", 1)).is_not_equal(0)
	_director.advance(LINE + VoiceDirector.GAP + 0.1)
	assert_int(_say(&"power_low", 1)).is_equal(0)
	# Another player has not said it, so the same moment is theirs to say.
	assert_int(_say(&"power_low", 2)).is_not_equal(0)
	_director.advance(LINE + VoiceDirector.GAP + cooldown)
	assert_int(_say(&"power_low", 1)).is_not_equal(0)


func test_no_take_repeats_among_the_last_few() -> void:
	var recent: Array[int] = []
	for i in 40:
		var take := _say(&"reload")
		_director.advance(LINE + VoiceDirector.GAP + 100.0)
		if take == 0:
			continue
		assert_array(recent).override_failure_message("take %d repeated" % take).not_contains(
			[take]
		)
		recent.append(take)
		if recent.size() > VoiceDirector.REMEMBER:
			recent.pop_front()


func test_a_moment_with_few_takes_still_varies() -> void:
	# Four takes: at most three are remembered, so the fourth is always free and none repeats.
	var last := 0
	for i in 30:
		var take := _say(&"boss_dead")
		_director.advance(100.0)
		assert_int(take).is_not_equal(0)
		assert_int(take).is_not_equal(last)
		last = take


func test_every_take_of_a_moment_gets_played_over_time() -> void:
	var seen := {}
	for i in 120:
		seen[_say(&"kill")] = true
		_director.advance(100.0)
	seen.erase(0)
	assert_int(seen.size()).is_equal(SoldierVoiceCatalog.takes_of(&"kill"))


func test_chance_leaves_some_of_the_commonest_moment_unvoiced() -> void:
	var said := 0
	for i in 200:
		if _try(&"kill") != 0:
			said += 1
		_director.advance(100.0)
	assert_int(said).is_between(60, 120)


func test_the_same_seed_chooses_the_same_takes() -> void:
	var a := VoiceDirector.new()
	var b := VoiceDirector.new()
	a.seed_random(99)
	b.seed_random(99)
	for i in 10:
		assert_int(a.choose(&"reload", 1)).is_equal(b.choose(&"reload", 1))
		a.commit(&"reload", 1, 1, 1.0)
		b.commit(&"reload", 1, 1, 1.0)
		a.advance(50.0)
		b.advance(50.0)


func test_quiet_time_counts_from_the_end_of_the_last_line() -> void:
	_director.advance(30.0)
	assert_float(_director.quiet_for()).is_equal_approx(30.0, 0.001)
	_say(&"round_start")
	_director.advance(LINE + 4.0)
	assert_float(_director.quiet_for()).is_equal_approx(4.0, 0.001)
