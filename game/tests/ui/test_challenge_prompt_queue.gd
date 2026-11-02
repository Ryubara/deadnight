extends GdUnitTestSuite
## What the challenge prompt shows and when, stepped by hand: one at a time, the most important
## first, short, replaced rather than repeated, dropped when stale, held while the player is down.

const STEP := 0.05

var _queue: ChallengePromptQueue


func before_test() -> void:
	_queue = ChallengePromptQueue.new()


func _mark(id: StringName, checkpoint := 25, extra := {}) -> Dictionary:
	var advance := {
		"id": id,
		"family": 0,
		"text": String(id),
		"before": 0,
		"after": 1,
		"target": 8,
		"checkpoint": checkpoint,
		"completed": false,
		"rung": 0,
		"rungs": 0,
	}
	advance.merge(extra, true)
	return advance


func _run(seconds: float, blocked := false) -> void:
	for _i in roundi(seconds / STEP):
		_queue.advance(STEP, blocked)


## Seconds from the prompt appearing to it being gone (the queue otherwise idle).
func _life_of(advance: Dictionary) -> float:
	_queue = ChallengePromptQueue.new()
	_queue.push(advance)
	var began := 0.0
	var seconds := 0.0
	var seen := false
	while seconds < 30.0:
		_queue.advance(STEP)
		seconds += STEP
		if not _queue.current.is_empty() and not seen:
			seen = true
			began = seconds
		if seen and _queue.current.is_empty():
			return seconds - began
	return -1.0


func test_a_prompt_comes_in_holds_and_leaves() -> void:
	_queue.push(_mark(&"a"))
	_queue.advance(STEP)
	assert_int(_queue.phase).is_equal(ChallengePromptQueue.Phase.IN)
	assert_float(_queue.shown()).is_between(0.0, 0.5)
	_run(HudTuning.current().challenge_in)
	assert_int(_queue.phase).is_equal(ChallengePromptQueue.Phase.HOLD)
	assert_float(_queue.shown()).is_equal(1.0)
	_run(HudTuning.current().challenge_hold + STEP)
	assert_int(_queue.phase).is_equal(ChallengePromptQueue.Phase.OUT)
	_run(HudTuning.current().challenge_out + 2.0 * STEP)
	assert_bool(_queue.current.is_empty()).is_true()
	assert_float(_queue.shown()).is_equal(0.0)


func test_a_quarter_mark_is_short_and_a_finish_longer() -> void:
	var mark := _life_of(_mark(&"a"))
	assert_float(mark).is_between(2.5, 3.5)
	var done := _life_of(_mark(&"b", 100, {"completed": true}))
	assert_float(done).is_greater(mark)
	assert_float(done).is_less(4.5)


func test_the_most_important_waiting_prompt_shows_first() -> void:
	_queue.push(_mark(&"quarter", 25))
	_queue.push(_mark(&"three", 75))
	_queue.push(_mark(&"done", 100, {"completed": true}))
	_queue.push(_mark(&"step", 0, {"rung": 2, "rungs": 5}))
	# Four were pushed and three may wait: the quarter mark, the least, was dropped.
	assert_int(_queue.waiting_count()).is_equal(ChallengePromptQueue.MAX_WAITING)
	var order: Array[StringName] = []
	for _i in 600:
		_run(0.1)
		if (
			not _queue.current.is_empty()
			and (order.is_empty() or order.back() != _queue.current["id"])
		):
			order.append(_queue.current["id"])
	assert_array(order).is_equal([&"done", &"step", &"three"])


func test_a_second_advance_of_the_showing_challenge_updates_it_in_place() -> void:
	_queue.push(_mark(&"a", 25))
	_run(0.6)
	_queue.push(_mark(&"a", 50, {"after": 4}))
	_queue.advance(STEP)
	assert_int(_queue.current["checkpoint"]).is_equal(50)
	assert_int(_queue.waiting_count()).is_equal(0)
	# A weaker one of the same challenge never replaces a stronger one.
	_queue.push(_mark(&"a", 25))
	_queue.advance(STEP)
	assert_int(_queue.current["checkpoint"]).is_equal(50)
	assert_int(_queue.waiting_count()).is_equal(0)


func test_a_waiting_prompt_of_one_challenge_is_replaced_not_repeated() -> void:
	_queue.push(_mark(&"a", 25))
	_run(0.3)
	_queue.push(_mark(&"b", 25))
	_queue.push(_mark(&"b", 50))
	assert_int(_queue.waiting_count()).is_equal(1)
	_queue.push(_mark(&"b", 25))
	assert_int(_queue.waiting_count()).is_equal(1)


func test_at_most_three_wait_and_the_lowest_quarter_marks_go_first() -> void:
	_queue.push(_mark(&"shown", 25))
	_run(0.3)
	for id in [&"a", &"b", &"c"]:
		_queue.push(_mark(id, 25))
	_queue.push(_mark(&"d", 75))
	assert_int(_queue.waiting_count()).is_equal(ChallengePromptQueue.MAX_WAITING)
	var kept: Array[StringName] = []
	for i in 100:
		_run(0.2)
		if not _queue.current.is_empty() and not kept.has(_queue.current["id"]):
			kept.append(_queue.current["id"])
	assert_bool(kept.has(&"d")).is_true()
	assert_int(kept.size()).is_equal(1 + ChallengePromptQueue.MAX_WAITING)


func test_a_finish_is_never_dropped_for_a_flood_of_quarter_marks() -> void:
	_queue.push(_mark(&"shown", 25))
	_run(0.3)
	_queue.push(_mark(&"done", 100, {"completed": true}))
	for id in [&"a", &"b", &"c", &"d", &"e", &"f"]:
		_queue.push(_mark(id, 25))
	var seen: Array[StringName] = []
	for i in 80:
		_run(0.2)
		if not _queue.current.is_empty() and not seen.has(_queue.current["id"]):
			seen.append(_queue.current["id"])
	assert_bool(seen.has(&"done")).is_true()


func test_a_busy_queue_shortens_the_holds() -> void:
	for id in [&"a", &"b"]:
		_queue.push(_mark(id, 25))
	var began := -1.0
	var elapsed := 0.0
	var first_life := 0.0
	while elapsed < 20.0:
		_queue.advance(STEP)
		elapsed += STEP
		if began < 0.0 and not _queue.current.is_empty():
			began = elapsed
		if began >= 0.0 and _queue.current.is_empty():
			first_life = elapsed - began
			break
	var alone := _life_of(_mark(&"z", 25))
	assert_float(first_life).is_less(alone)


func test_a_prompt_that_waited_too_long_is_dropped() -> void:
	_queue.push(_mark(&"shown", 100, {"completed": true}))
	_run(0.3)
	_queue.push(_mark(&"late", 25))
	# Held while blocked, the late one waits past its time and is gone.
	_run(HudTuning.current().challenge_stale + 1.0, true)
	assert_int(_queue.waiting_count()).is_equal(0)


func test_nothing_starts_and_the_showing_one_holds_while_blocked() -> void:
	_queue.push(_mark(&"a"))
	_run(0.6)
	var showing: StringName = _queue.current["id"]
	_run(10.0, true)
	assert_str(_queue.current["id"]).is_equal(showing)
	assert_int(_queue.phase).is_equal(ChallengePromptQueue.Phase.HOLD)
	var fresh := ChallengePromptQueue.new()
	fresh.push(_mark(&"b"))
	for _i in 100:
		fresh.advance(STEP, true)
	assert_bool(fresh.current.is_empty()).is_true()


func test_there_is_a_quiet_gap_between_two_prompts() -> void:
	_queue.push(_mark(&"a"))
	_queue.push(_mark(&"b"))
	var gap := 0.0
	var seen_first := false
	for _i in 400:
		_queue.advance(STEP)
		if not _queue.current.is_empty():
			seen_first = true
			if gap > 0.0:
				break
		elif seen_first:
			gap += STEP
	assert_float(gap).is_greater_equal(HudTuning.current().challenge_gap - STEP)


func test_what_is_worth_a_prompt() -> void:
	assert_bool(ChallengePromptQueue.is_worth_showing(_mark(&"a", 0))).is_false()
	assert_bool(ChallengePromptQueue.is_worth_showing(_mark(&"a", 25))).is_true()
	assert_bool(ChallengePromptQueue.is_worth_showing(_mark(&"a", 0, {"rung": 1}))).is_true()
	(
		assert_bool(ChallengePromptQueue.is_worth_showing(_mark(&"a", 0, {"completed": true})))
		. is_true()
	)
	assert_bool(ChallengePromptQueue.is_milestone_or_completion(_mark(&"a", 75))).is_false()
	(
		assert_bool(ChallengePromptQueue.is_milestone_or_completion(_mark(&"a", 0, {"rung": 2})))
		. is_true()
	)
