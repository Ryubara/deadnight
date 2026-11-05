# gdlint:disable=max-public-methods
extends GdUnitTestSuite
## The popup queue (`PopupQueue`): what shows, in which order and for how long, with a clock the
## test moves by hand. A level and five unlocks in one tick; three cards up at most, the oldest
## leaving first; the lowest cards merged past eight; a tier made of its level card; the timings of
## the design page (0.25 s drop, 0.15 s between cards, holds of 2.6, 2.0 and 3.6 s); a blocked
## queue (the arrival drop) that keeps its cards for the screen's return.

const STEP := 0.05

var _queue: PopupQueue
var _t := HudTuning.current()


func before_test() -> void:
	UIMotion.reduced = false
	_queue = PopupQueue.new()


func after_test() -> void:
	UIMotion.reduced = false


## Runs the clock `seconds` forward; returns the kinds of the cards that started, in order.
func _run(seconds: float, blocked := false) -> Array[int]:
	var kinds: Array[int] = []
	var left := seconds
	while left > 0.0001:
		for card in _queue.advance(minf(STEP, left), blocked):
			kinds.append(card.kind)
		left -= STEP
	return kinds


func _kinds(list: Array[PopupQueue.Card]) -> Array[int]:
	var out: Array[int] = []
	for card in list:
		out.append(card.kind)
	return out


func _stack_of_five() -> void:
	_queue.push(PopupQueue.Kind.LEVEL, {"level": 12})
	for item in ["boots", "teal", "goggles", "helmet", "tan"]:
		_queue.push(PopupQueue.Kind.UNLOCK, {"slot": &"top", "item": StringName(item), "level": 12})


func test_a_level_and_five_unlocks_in_one_tick_start_in_order_and_three_stand() -> void:
	_stack_of_five()
	var started := _run(0.0)
	assert_array(started).is_empty()
	started = _run(STEP)
	assert_array(started).is_equal([PopupQueue.Kind.LEVEL])
	assert_int(_queue.waiting.size()).is_equal(5)
	started = _run(0.4)
	assert_array(started).is_equal([PopupQueue.Kind.UNLOCK, PopupQueue.Kind.UNLOCK])
	assert_int(_queue.shown.size()).is_equal(PopupQueue.MAX_VISIBLE)
	assert_array(_kinds(_queue.shown)).is_equal(
		[PopupQueue.Kind.LEVEL, PopupQueue.Kind.UNLOCK, PopupQueue.Kind.UNLOCK]
	)


func test_cards_start_a_gap_apart() -> void:
	_stack_of_five()
	var starts: Array[float] = []
	var clock := 0.0
	for _i in 40:
		clock += 0.01
		if not _queue.advance(0.01).is_empty():
			starts.append(clock)
	assert_int(starts.size()).is_equal(3)
	assert_float(starts[1] - starts[0]).is_between(
		_t.popup_start_gap - 0.011, _t.popup_start_gap + 0.011
	)
	assert_float(starts[2] - starts[1]).is_between(
		_t.popup_start_gap - 0.011, _t.popup_start_gap + 0.011
	)


func test_never_more_than_three_are_up_and_the_oldest_leaves_first() -> void:
	_stack_of_five()
	var order: Array[String] = []
	var most := 0
	for _i in 600:
		for card in _queue.advance(0.02):
			order.append("%d" % int(card.data.get("level", 0)))
		most = maxi(most, _queue.shown.size())
		# Never more up than the limit, a leaving card included once it is nearly gone.
		var up := 0
		for card in _queue.shown:
			if card.phase != PopupQueue.Phase.OUT:
				up += 1
		assert_int(up).is_less_equal(PopupQueue.MAX_VISIBLE)
	assert_int(order.size()).is_equal(6)
	assert_bool(_queue.is_idle()).is_true()


func test_the_oldest_card_is_the_first_to_go() -> void:
	_stack_of_five()
	_run(0.5)
	var oldest := _queue.shown[0]
	var left_first: PopupQueue.Card = null
	for _i in 300:
		_queue.advance(0.02)
		for card in _queue.shown:
			if card.phase == PopupQueue.Phase.OUT and left_first == null:
				left_first = card
	assert_object(left_first).is_same(oldest)


func test_a_waiting_card_sends_the_oldest_away_after_the_minimum_show() -> void:
	_stack_of_five()
	_run(0.3)
	var oldest := _queue.shown[0]
	_run(_t.popup_in + _t.popup_min_show - 0.3 - 0.1)
	assert_int(oldest.phase).is_not_equal(PopupQueue.Phase.OUT)
	_run(0.3)
	assert_int(oldest.phase).is_equal(PopupQueue.Phase.OUT)


func test_a_card_alone_holds_for_its_kind() -> void:
	var holds := {
		PopupQueue.Kind.LEVEL: _t.popup_hold_level,
		PopupQueue.Kind.UNLOCK: _t.popup_hold_unlock,
		PopupQueue.Kind.TIER: _t.popup_hold_tier,
		PopupQueue.Kind.CHALLENGE: _t.popup_hold_challenge,
	}
	for kind: int in holds:
		var queue := PopupQueue.new()
		queue.push(kind, {})
		queue.advance(0.01)
		var total := 0.0
		while not queue.is_idle() and total < 20.0:
			queue.advance(0.01)
			total += 0.01
		var expected: float = _t.popup_in + float(holds[kind]) + _t.popup_out
		assert_float(total).is_between(expected - 0.03, expected + 0.03)


func test_the_design_page_numbers() -> void:
	assert_float(_t.popup_in).is_equal(0.25)
	assert_float(_t.popup_start_gap).is_equal(0.15)
	assert_float(_t.popup_hold_level).is_equal(2.6)
	assert_float(_t.popup_hold_unlock).is_equal(2.0)
	assert_float(_t.popup_hold_tier).is_equal(3.6)
	assert_int(PopupQueue.MAX_VISIBLE).is_equal(3)
	assert_int(PopupQueue.MAX_WAITING).is_equal(8)


func test_past_eight_waiting_the_lowest_are_merged_into_one_card() -> void:
	# Three up, then twelve unlocks arrive at once: eight wait, the rest are counted.
	for i in 3:
		_queue.push(PopupQueue.Kind.LEVEL, {"level": i + 1})
	_run(0.5)
	assert_int(_queue.shown.size()).is_equal(3)
	for i in 12:
		_queue.push(PopupQueue.Kind.UNLOCK, {"slot": &"top", "item": &"boots", "level": 9})
	assert_int(_queue.waiting.size()).is_equal(PopupQueue.MAX_WAITING)
	var last := _queue.waiting[_queue.waiting.size() - 1]
	assert_int(last.kind).is_equal(PopupQueue.Kind.MORE)
	# Seven unlock cards and the one that says the other five.
	assert_int(int(last.data["count"])).is_equal(5)
	assert_int(_queue.waiting.size() - 1 + int(last.data["count"])).is_equal(12)


func test_a_level_card_is_kept_over_unlocks_when_merging() -> void:
	for i in 3:
		_queue.push(PopupQueue.Kind.UNLOCK, {"slot": &"top", "item": &"boots", "level": 9})
	_run(0.5)
	for i in 8:
		_queue.push(PopupQueue.Kind.UNLOCK, {"slot": &"top", "item": &"boots", "level": 9})
	_queue.push(PopupQueue.Kind.LEVEL, {"level": 10})
	var kinds := _kinds(_queue.waiting)
	assert_bool(kinds.has(PopupQueue.Kind.LEVEL)).is_true()
	assert_int(kinds[kinds.size() - 1]).is_equal(PopupQueue.Kind.MORE)
	assert_int(_queue.waiting.size()).is_equal(PopupQueue.MAX_WAITING)


func test_a_new_card_stands_before_the_merged_one() -> void:
	for i in 3:
		_queue.push(PopupQueue.Kind.LEVEL, {"level": i + 1})
	_run(0.5)
	for i in 10:
		_queue.push(PopupQueue.Kind.UNLOCK, {"slot": &"top", "item": &"boots", "level": 9})
	_queue.push(PopupQueue.Kind.CHALLENGE, {"text": "x"})
	var kinds := _kinds(_queue.waiting)
	assert_int(kinds[kinds.size() - 1]).is_equal(PopupQueue.Kind.MORE)
	assert_bool(kinds.has(PopupQueue.Kind.CHALLENGE)).is_true()


func test_a_tier_is_its_level_card_made_longer() -> void:
	_queue.push(PopupQueue.Kind.LEVEL, {"level": 11})
	assert_bool(_queue.upgrade_to_tier(11, "Newsreel")).is_true()
	assert_int(_queue.waiting.size()).is_equal(1)
	assert_int(_queue.waiting[0].kind).is_equal(PopupQueue.Kind.TIER)
	assert_str(_queue.waiting[0].data["tier_name"]).is_equal("Newsreel")
	assert_bool(_queue.upgrade_to_tier(12, "Newsreel")).is_false()


func test_a_tier_that_arrives_while_the_level_card_is_up_holds_longer() -> void:
	_queue.push(PopupQueue.Kind.LEVEL, {"level": 11})
	_run(1.0)
	var card := _queue.shown[0]
	assert_float(card.hold).is_equal(_t.popup_hold_level)
	assert_bool(_queue.upgrade_to_tier(11, "Newsreel")).is_true()
	assert_int(card.kind).is_equal(PopupQueue.Kind.TIER)
	assert_float(card.hold).is_equal(_t.popup_hold_tier)


func test_a_blocked_queue_starts_nothing_and_ages_nothing_then_shows_what_waited() -> void:
	_queue.push(PopupQueue.Kind.LEVEL, {"level": 5})
	assert_array(_run(30.0, true)).is_empty()
	assert_int(_queue.waiting.size()).is_equal(1)
	assert_array(_run(0.2)).is_equal([PopupQueue.Kind.LEVEL])
	# A card showing holds still while blocked.
	var card := _queue.shown[0]
	var age := card.age
	_run(5.0, true)
	assert_float(card.age).is_equal(age)


func test_the_drop_overshoots_a_little_and_settles() -> void:
	_queue.push(PopupQueue.Kind.LEVEL, {"level": 5})
	_run(STEP)
	var card := _queue.shown[0]
	var lowest := -1.0e9
	var first := true
	for _i in 30:
		_queue.advance(0.01)
		var dy := float(_queue.look_of(card, false)["dy"])
		if first:
			assert_float(dy).is_less(-10.0)
			first = false
		lowest = maxf(lowest, dy)
	# Past its place by a little (under a seventh of the drop), and home when it is in.
	assert_float(lowest).is_between(0.5, _t.popup_drop / 7.0)
	assert_float(float(_queue.look_of(card, false)["dy"])).is_equal_approx(0.0, 0.01)


func test_reduced_motion_fades_without_moving() -> void:
	_queue.push(PopupQueue.Kind.LEVEL, {"level": 5})
	_run(STEP)
	var card := _queue.shown[0]
	for _i in 20:
		_queue.advance(0.01)
		var look := _queue.look_of(card, true)
		assert_float(float(look["dy"])).is_equal(0.0)
	assert_float(_queue.stamp_of(card, true)).is_equal(1.0)
	_run(_t.popup_in + _t.popup_hold_level + 0.01)
	var leaving := _queue.look_of(card, true)
	assert_float(float(leaving["dy"])).is_equal(0.0)
	assert_float(float(leaving["alpha"])).is_less(1.0)


func test_the_icon_stamps_small_then_big_then_home() -> void:
	_queue.push(PopupQueue.Kind.LEVEL, {"level": 5})
	_run(STEP)
	var card := _queue.shown[0]
	var seen: Array[float] = []
	for _i in 60:
		_queue.advance(0.01)
		seen.append(_queue.stamp_of(card, false))
	assert_float(seen[0]).is_equal(PopupQueue.STAMP_FROM)
	assert_float(seen.max()).is_between(1.09, 1.1001)
	assert_float(seen[seen.size() - 1]).is_equal_approx(1.0, 0.02)
	_run(1.0)
	assert_float(_queue.stamp_of(card, false)).is_equal(1.0)


func test_cards_slide_up_when_the_one_above_leaves() -> void:
	_queue.push(PopupQueue.Kind.LEVEL, {"level": 5})
	_queue.push(PopupQueue.Kind.UNLOCK, {"slot": &"top", "item": &"boots", "level": 5})
	_run(0.6)
	var second := _queue.shown[1]
	var home := PopupCard.size_of(PopupQueue.Kind.LEVEL).y + PopupQueue.GAP
	assert_float(second.y).is_equal_approx(home, 0.01)
	_run(_t.popup_in + _t.popup_hold_level)
	# The level card is leaving: the unlock has begun to slide to the top.
	var ys: Array[float] = []
	for _i in 30:
		_queue.advance(0.01)
		ys.append(second.y)
	assert_float(ys[0]).is_less_equal(home)
	assert_float(ys[ys.size() - 1]).is_less(home - 10.0)
	_run(0.5)
	assert_float(second.y).is_equal_approx(0.0, 0.01)


func test_clear_forgets_everything() -> void:
	_stack_of_five()
	_run(0.5)
	_queue.clear()
	assert_bool(_queue.is_idle()).is_true()


func test_a_card_waits_for_the_stack_to_settle_before_it_comes_out_over_it() -> void:
	_queue.push(PopupQueue.Kind.LEVEL, {"level": 5})
	_queue.push(PopupQueue.Kind.UNLOCK, {"slot": &"top", "item": &"boots", "level": 5})
	_queue.push(PopupQueue.Kind.UNLOCK, {"slot": &"top", "item": &"tan", "level": 5})
	_queue.push(PopupQueue.Kind.UNLOCK, {"slot": &"top", "item": &"teal", "level": 5})
	_run(0.6)
	# The level card leaves (the others wait behind it); while the rest slide up, no card starts.
	var guard := 0
	while _queue.shown[0].phase != PopupQueue.Phase.OUT and guard < 400:
		_queue.advance(0.02)
		guard += 1
	var sliding_when_started := 0
	for _i in 100:
		for card in _queue.advance(0.02):
			for other in _queue.shown:
				if (
					other != card
					and other.phase != PopupQueue.Phase.OUT
					and other.slide < PopupQueue.SETTLED
				):
					sliding_when_started += 1
	assert_int(sliding_when_started).is_equal(0)
