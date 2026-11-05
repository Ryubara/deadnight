extends GdUnitTestSuite
## The progression cheers (#1063): a level up, a tier up, an unlock, a challenge done, a poster set,
## a card, an emblem or frame and the first game of the day, in both voices. Each has three takes
## or more per voice, none repeats back to back, they rank above the chatter and below the urgent
## lines (hurt and downed cut one, a boss or a teammate down cuts one, a cheer never cuts those)
## and a teammate's cheer is heard where they stand.

const OWN := 1
const MATE := 2
const AT_MATE := Vector3(6.0, 0.0, 2.0)
const LINE := 2.0
const CHATTER: Array[StringName] = [
	&"kill", &"reload", &"idle", &"door", &"buy_weapon", &"buy_big", &"low_ammo", &"round_clear"
]
const URGENT: Array[StringName] = [
	&"downed", &"hurt", &"boss_arrive", &"boss_dead", &"close_call", &"teammate_down", &"revived"
]

var _director: VoiceDirector


func before_test() -> void:
	_director = VoiceDirector.new()
	_director.seed_random(11)


func _priority(event: StringName) -> int:
	return int(SoldierVoiceCatalog.moments()[event]["priority"])


## Asks until the moment is voiced (each ask is a new roll) and commits a line of `LINE` seconds.
func _say(event: StringName, speaker := OWN) -> int:
	for attempt in 30:
		var take := _director.choose(event, speaker)
		if take != 0:
			_director.commit(event, speaker, take, LINE)
			return take
	return 0


func test_there_are_eight_progression_moments_each_with_three_takes_per_voice() -> void:
	assert_int(SoldierVoiceCatalog.PROGRESS.size()).is_equal(8)
	for event in SoldierVoiceCatalog.PROGRESS:
		(
			assert_bool(SoldierVoiceCatalog.moments().has(event))
			. override_failure_message(String(event))
			. is_true()
		)
		(
			assert_int(SoldierVoiceCatalog.takes_of(event))
			. override_failure_message(String(event))
			. is_greater_equal(3)
		)
		for voice in SoldierVoiceCatalog.voices():
			for n in range(1, SoldierVoiceCatalog.takes_of(event) + 1):
				var id := SoldierVoiceCatalog.take_id(event, n, voice)
				(
					assert_object(SoundCatalog.get_def(id))
					. override_failure_message(String(id))
					. is_not_null()
				)
				(
					assert_bool(
						FileAccess.file_exists(SoldierVoiceCatalog.path_of(event, n, voice))
					)
					. is_true()
				)


func test_a_progression_moment_never_repeats_a_take_back_to_back() -> void:
	for event in SoldierVoiceCatalog.PROGRESS:
		var last := 0
		var seen := {}
		for i in 12:
			_director.advance(60.0)
			var take := _say(event)
			assert_int(take).override_failure_message(String(event)).is_not_equal(0)
			assert_int(take).override_failure_message("%s repeated" % event).is_not_equal(last)
			last = take
			seen[take] = true
		assert_int(seen.size()).override_failure_message(String(event)).is_equal(3)


func test_the_cheers_rank_above_the_chatter_and_below_the_urgent_lines() -> void:
	var tuning := NightSoundTuning.current()
	for event in SoldierVoiceCatalog.PROGRESS:
		var rank := _priority(event)
		for other in CHATTER:
			assert_int(rank).override_failure_message("%s over %s" % [event, other]).is_greater(
				_priority(other)
			)
		assert_int(rank).override_failure_message(String(event)).is_greater(_priority(&"streak"))
		for other in URGENT:
			assert_int(rank).override_failure_message("%s under %s" % [event, other]).is_less(
				_priority(other)
			)
		assert_int(rank).is_less(tuning.interrupt_priority)
		assert_int(rank).is_less(tuning.urgent_priority + 1)


func test_hurt_and_downed_cut_a_cheer_and_so_do_a_boss_and_a_teammate_down() -> void:
	for event in SoldierVoiceCatalog.PROGRESS:
		for urgent in URGENT:
			_director = VoiceDirector.new()
			_director.seed_random(3)
			assert_int(_say(event)).is_not_equal(0)
			_director.advance(0.5)
			(
				assert_bool(_director.would_interrupt(_priority(urgent)))
				. override_failure_message("%s should cut %s" % [urgent, event])
				. is_true()
			)


func test_a_cheer_never_cuts_an_urgent_line() -> void:
	for urgent in URGENT:
		for event in SoldierVoiceCatalog.PROGRESS:
			_director = VoiceDirector.new()
			_director.seed_random(4)
			assert_int(_say(urgent)).is_not_equal(0)
			_director.advance(0.5)
			(
				assert_bool(_director.would_interrupt(_priority(event)))
				. override_failure_message("%s must not cut %s" % [event, urgent])
				. is_false()
			)
			(
				assert_int(_say(event))
				. override_failure_message("%s was said over %s" % [event, urgent])
				. is_equal(0)
			)


func test_a_cheer_cuts_kill_chatter_but_not_a_streak() -> void:
	assert_int(_say(&"kill")).is_not_equal(0)
	_director.advance(0.5)
	assert_int(_say(&"level_up")).is_not_equal(0)
	assert_str(_director.history.back()["event"]).is_equal("level_up")
	_director.advance(100.0)
	assert_int(_say(&"streak")).is_not_equal(0)
	_director.advance(0.5)
	assert_int(_say(&"card")).is_equal(0)


func test_a_cheer_is_said_at_most_once_in_its_cooldown_per_speaker() -> void:
	assert_int(_say(&"level_up")).is_not_equal(0)
	_director.advance(LINE + 0.6)
	assert_int(_say(&"level_up")).is_equal(0)
	assert_int(_say(&"level_up", MATE)).is_not_equal(0)
