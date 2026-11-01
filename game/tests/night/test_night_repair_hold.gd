# Holding use at a broken breach (#297): the first board goes up at the press, then one every
# `repair_interval` for as long as the button stays down, until the breach is whole, the player
# lets go, walks off, is hit, fires, reloads, swaps or goes down. Driven like a client: commands
# through the link (`use` the press, `use_held` the level), the rules' events back. Nothing waits
# on the clock; a tick is 1/60 s.
extends GdUnitTestSuite

const BREACH := &"nw"
const TICKS_PER_SECOND := 60
## Ticks to let the night settle before the first command.
const SETTLE := 30
const TEAR_ALL := 5

var _events: Array[Dictionary] = []


## A night that waits 60 s before round one (or, `active`, in its first round with no zombie yet),
## with `torn` boards of the breach off and the player standing at it.
func _start(torn: int, night_tuning: NightTuning = null, active := false) -> Night:
	_events = []
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = 60.0
	# A round that is on but whose first zombie is minutes away: blows come from the test.
	tuning.rounds.first_spawn_delay = 600.0
	var night := await NightFixture.start(self, Night.Mode.MANUAL, tuning)
	if night_tuning != null:
		night.server.tuning = night_tuning
	night.state.event_received.connect(func(event: Dictionary) -> void: _events.append(event))
	NightFixture.run(night, SETTLE)
	if active:
		night.server.rules.apply(RulesAction.skip_break())
	for _i in torn:
		night.server.rules.barricades.tear(BREACH)
	night.world.barricade(BREACH).set_boards(night.server.rules.barricades.boards_of(BREACH))
	night.player().teleport(night.world.repair_spot(BREACH))
	NightFixture.run(night, 2)
	_events.clear()
	return night


## `ticks` ticks with the button down; the first one is the press itself when `press` is true.
func _hold(night: Night, ticks: int, press := true) -> void:
	for i in ticks:
		var command := NightCommand.new()
		command.use = press and i == 0
		command.use_held = true
		NightFixture.run(night, 1, command)


func _release(night: Night, ticks: int) -> void:
	NightFixture.run(night, ticks, NightCommand.new())


func _seconds(seconds: float) -> int:
	return roundi(seconds * TICKS_PER_SECOND)


func _boards(night: Night) -> int:
	return night.server.rules.barricades.boards_of(BREACH)


func _count(type: StringName) -> int:
	return _events.filter(func(event: Dictionary) -> bool: return event["type"] == type).size()


func test_holding_use_puts_a_board_back_every_interval() -> void:
	var night := await _start(TEAR_ALL)
	var interval := night.server.tuning.repair_interval
	var before := night.state.points()
	_hold(night, 1)
	assert_int(_boards(night)).is_equal(1)
	_hold(night, _seconds(interval) - 5, false)
	assert_int(_boards(night)).is_equal(1)
	_hold(night, 10, false)
	assert_int(_boards(night)).is_equal(2)
	_hold(night, _seconds(interval), false)
	assert_int(_boards(night)).is_equal(3)
	_hold(night, _seconds(interval), false)
	assert_int(_boards(night)).is_equal(4)
	_hold(night, _seconds(interval), false)
	assert_int(_boards(night)).is_equal(5)
	assert_int(_count(&"board_repaired")).is_equal(TEAR_ALL)
	var pay := night.server.rules.tuning.economy.repair
	assert_int(night.state.points()).is_equal(before + TEAR_ALL * pay)
	night.queue_free()


func test_each_board_is_a_whole_interval_apart() -> void:
	var night := await _start(TEAR_ALL)
	var interval := night.server.tuning.repair_interval
	var tick_of: Array[int] = []
	for i in _seconds(interval * 4.5):
		var command := NightCommand.new()
		command.use = i == 0
		command.use_held = true
		var before := _count(&"board_repaired")
		NightFixture.run(night, 1, command)
		if _count(&"board_repaired") > before:
			tick_of.append(i)
	assert_int(tick_of.size()).is_equal(5)
	assert_int(tick_of[0]).is_less_equal(1)  # the events reach the client a tick behind
	for i in range(1, tick_of.size()):
		var apart := tick_of[i] - tick_of[i - 1]
		assert_int(apart).is_between(_seconds(interval), _seconds(interval) + 1)
	night.queue_free()


func test_letting_go_stops_and_a_new_press_goes_on() -> void:
	var night := await _start(TEAR_ALL)
	_hold(night, _seconds(1.5))
	assert_int(_boards(night)).is_equal(2)
	_release(night, _seconds(3.0))
	assert_int(_boards(night)).is_equal(2)
	assert_bool(night.server.is_repairing(1)).is_false()
	_hold(night, 1)
	assert_int(_boards(night)).is_equal(3)
	night.queue_free()


func test_a_tap_is_still_one_board() -> void:
	var night := await _start(TEAR_ALL)
	var tap := NightCommand.new()
	tap.use = true
	tap.use_held = true
	NightFixture.run(night, 1, tap)
	_release(night, _seconds(3.0))
	assert_int(_boards(night)).is_equal(1)
	night.queue_free()


func test_a_whole_breach_stops_the_hold_without_a_refusal() -> void:
	var night := await _start(2)
	_hold(night, _seconds(5.0))
	assert_int(_boards(night)).is_equal(night.server.rules.tuning.barricades.boards)
	assert_int(_count(&"board_repaired")).is_equal(2)
	assert_int(_count(&"action_rejected")).is_equal(0)
	assert_bool(night.server.is_repairing(1)).is_false()
	assert_dict(night.state.me()["prompt"]).is_empty()
	night.queue_free()


func test_walking_out_of_reach_stops_it_and_coming_back_needs_a_press() -> void:
	var night := await _start(TEAR_ALL)
	_hold(night, _seconds(1.5))
	assert_int(_boards(night)).is_equal(2)
	var barricade := night.world.barricade(BREACH)
	night.player().teleport(barricade.centre() + barricade.inward() * 8.0)
	_hold(night, _seconds(3.0), false)
	assert_int(_boards(night)).is_equal(2)
	night.player().teleport(night.world.repair_spot(BREACH))
	_hold(night, _seconds(3.0), false)
	assert_int(_boards(night)).is_equal(2)
	_hold(night, 1)
	assert_int(_boards(night)).is_equal(3)
	night.queue_free()


func test_a_blow_stops_it() -> void:
	var night := await _start(TEAR_ALL, null, true)
	_hold(night, _seconds(1.5))
	assert_int(_boards(night)).is_equal(2)
	night.server.rules.apply(RulesAction.blow(1, 5.0))
	_hold(night, _seconds(3.0), false)
	assert_int(_boards(night)).is_equal(2)
	_hold(night, 1)
	assert_int(_boards(night)).is_equal(3)
	night.queue_free()


func test_firing_reloading_and_swapping_stop_it() -> void:
	for interrupt in [&"fire", &"reload", &"swap"]:
		var night := await _start(TEAR_ALL)
		_hold(night, _seconds(1.5))
		assert_int(_boards(night)).is_equal(2)
		var command := NightCommand.new()
		command.use_held = true
		command.fire = interrupt == &"fire"
		command.reload = interrupt == &"reload"
		command.swap = interrupt == &"swap"
		NightFixture.run(night, 1, command)
		_hold(night, _seconds(3.0), false)
		assert_int(_boards(night)).is_equal(2)
		night.queue_free()


func test_going_down_stops_it_and_getting_up_needs_a_press() -> void:
	var night := await _start(TEAR_ALL)
	_hold(night, _seconds(1.5))
	night.server.rules.apply(RulesAction.set_downed(1, true))
	_hold(night, _seconds(2.0), false)
	night.server.rules.apply(RulesAction.set_downed(1, false))
	_hold(night, _seconds(3.0), false)
	assert_int(_boards(night)).is_equal(2)
	night.queue_free()


func test_without_the_hold_setting_a_press_is_a_board() -> void:
	var tuning := NightTuning.new()
	tuning.repair_hold = false
	var night := await _start(TEAR_ALL, tuning)
	_hold(night, _seconds(3.0))
	assert_int(_boards(night)).is_equal(1)
	night.queue_free()


func test_a_longer_interval_slows_the_boards() -> void:
	var tuning := NightTuning.new()
	tuning.repair_interval = 2.0
	var night := await _start(TEAR_ALL, tuning)
	_hold(night, _seconds(4.5))
	assert_int(_boards(night)).is_equal(3)
	night.queue_free()


func test_the_command_carries_the_held_state() -> void:
	var command := NightCommand.new()
	command.use_held = true
	assert_bool(NightCommand.from_dict(command.to_dict()).use_held).is_true()
	assert_bool(NightCommand.from_dict({}).use_held).is_false()
