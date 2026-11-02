# Raising a downed teammate in the night (bots plan, phase 0): hold use beside them for the
# rules' `revive_seconds`, and they get up with half their health; let go, step away or go down and
# the time starts over. Driven like a client: commands through the link, the events and the frame
# back. A tick is 1/60 s and nothing waits on the clock.
extends GdUnitTestSuite

const TICKS_PER_SECOND := 60
const SETTLE := 30

var _events: Array[Dictionary] = []


## A night in its first round with no zombie for ten minutes, a second player standing a metre
## from the first, and `downed` taking the second to the ground.
func _start(downed := true) -> Night:
	_events = []
	var tuning := RulesFixture.tuning()
	tuning.rounds.first_spawn_delay = 600.0
	var night := await NightFixture.start(self, Night.Mode.MANUAL, tuning)
	night.state.event_received.connect(func(event: Dictionary) -> void: _events.append(event))
	NightFixture.run(night, SETTLE)
	night.server.apply({"type": NightServer.JOIN, "player_id": 2, "local": false})
	night.server.rules.apply(RulesAction.skip_break())
	var here := night.state.position()
	night.server.body_of(2).teleport(here + Vector3(1.0, 0.0, 0.0))
	NightFixture.run(night, 2)
	if downed:
		# A blow outside a step reaches no client by itself: hand the clients its events.
		night.state.apply_events(night.server.rules.apply(RulesAction.blow(2, 500.0)))
	NightFixture.run(night, 2)
	_events.clear()
	return night


func _hold(night: Night, seconds: float, held := true) -> void:
	var command := NightCommand.new()
	command.use_held = held
	NightFixture.run(night, roundi(seconds * TICKS_PER_SECOND), command)


func _count(type: StringName) -> int:
	return _events.filter(func(event: Dictionary) -> bool: return event["type"] == type).size()


func _seconds_needed(night: Night) -> float:
	return night.server.rules.tuning.health.revive_seconds


func test_holding_use_beside_a_downed_teammate_raises_them_after_the_channel() -> void:
	var night := await _start()
	var needed := _seconds_needed(night)
	_hold(night, needed * 0.95)
	assert_bool(night.server.rules.players[2].downed).is_true()
	assert_float(night.server.revive().progress(2)).is_between(0.9, 1.0)
	_hold(night, needed * 0.2)
	assert_bool(night.server.rules.players[2].downed).is_false()
	assert_float(night.server.rules.health_of(2)).is_equal(50.0)
	assert_int(_count(&"player_revived")).is_equal(1)
	var revived := _events.filter(
		func(e: Dictionary) -> bool: return e["type"] == &"player_revived"
	)
	assert_int(revived[0]["reviver_id"]).is_equal(1)
	assert_int(_count(&"revive_started")).is_equal(1)
	assert_int(_count(&"revive_stopped")).is_equal(1)
	assert_bool(night.server.revive().is_reviving(1)).is_false()
	night.queue_free()


func test_the_prompt_and_the_frame_say_who_is_being_raised_and_how_far_it_has_got() -> void:
	var night := await _start()
	assert_str(night.state.me()["prompt"]["kind"]).is_equal("revive")
	assert_int(night.state.me()["prompt"]["id"]).is_equal(2)
	_hold(night, _seconds_needed(night) / 3.0)
	var frame: Dictionary = night.state.frame["players"]
	assert_int(frame[1]["reviving"]).is_equal(2)
	assert_float(frame[2]["revive"]).is_between(0.3, 0.36)
	assert_float(frame[1]["prompt"]["progress"]).is_between(0.3, 0.36)
	assert_int(frame[2]["reviving"]).is_equal(0)
	night.queue_free()


func test_letting_go_starts_the_time_over() -> void:
	var night := await _start()
	_hold(night, _seconds_needed(night) - 1.0)
	_hold(night, 0.2, false)
	assert_float(night.server.revive().progress(2)).is_equal(0.0)
	(
		assert_str(
			_events.filter(func(e: Dictionary) -> bool: return e["type"] == &"revive_stopped")[0]["reason"]
		)
		. is_equal("released")
	)
	_hold(night, _seconds_needed(night) - 1.0)
	assert_bool(night.server.rules.players[2].downed).is_true()
	_hold(night, 1.5)
	assert_bool(night.server.rules.players[2].downed).is_false()
	night.queue_free()


func test_out_of_reach_nothing_happens() -> void:
	var night := await _start()
	night.server.body_of(2).teleport(night.state.position() + Vector3(6.0, 0.0, 0.0))
	NightFixture.run(night, 2)
	assert_str(str(night.state.me()["prompt"].get("kind", ""))).is_not_equal("revive")
	_hold(night, _seconds_needed(night) + 1.0)
	assert_bool(night.server.rules.players[2].downed).is_true()
	assert_int(_count(&"revive_started")).is_equal(0)
	night.queue_free()


func test_a_reviver_who_goes_down_stops_the_channel() -> void:
	var night := await _start()
	_hold(night, _seconds_needed(night) * 0.5)
	night.server.rules.apply(RulesAction.blow(1, 500.0))
	_hold(night, 1.0)
	assert_bool(night.server.revive().is_reviving(1)).is_false()
	assert_float(night.server.revive().progress(2)).is_equal(0.0)
	(
		assert_str(
			_events.filter(func(e: Dictionary) -> bool: return e["type"] == &"revive_stopped")[0]["reason"]
		)
		. is_equal("down")
	)
	night.queue_free()


func _pose_of(night: Night, player_id: int) -> PlayerAnimation:
	return night.server.body_of(player_id).get_node(^"AnimationTree") as PlayerAnimation


func test_the_bodies_lie_down_kneel_and_get_up_with_the_events() -> void:
	var night := await _start()
	var patient := _pose_of(night, 2)
	var reviver := _pose_of(night, 1)
	assert_bool(patient.is_downed()).is_true()
	assert_bool(reviver.is_downed()).is_false()
	_hold(night, 1.0)
	assert_bool(reviver.is_reviving()).is_true()
	_hold(night, 0.2, false)
	assert_bool(reviver.is_reviving()).is_false()
	_hold(night, _seconds_needed(night) + 0.5)
	assert_bool(patient.is_downed()).is_false()
	_hold(night, 0.5, false)
	assert_bool(reviver.is_reviving()).is_false()
	night.queue_free()


func test_a_standing_teammate_offers_no_revive() -> void:
	var night := await _start(false)
	_hold(night, 1.0)
	assert_int(_count(&"revive_started")).is_equal(0)
	assert_str(str(night.state.me()["prompt"].get("kind", ""))).is_not_equal("revive")
	night.queue_free()
