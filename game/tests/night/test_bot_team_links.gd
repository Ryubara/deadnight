# The team's link rule (`BotShop.team_links`, a small map's overlay): a link the team can pay for is
# bought by the nearest bot that is free, even when the one-errand turn and the door's rotation say
# it is another bot's. Two bots in the real lot with the rule on, the turn-holder's brain stopped
# (a bot busy or far away): the other buys the door inside the grace a rotation would take, and
# with both free exactly one buys it. With the rule off (the lot's default) the same night waits
# for the rotation.
extends GdUnitTestSuite

const SEED := 43
const LONG_BREAK := 3000.0
const TICKS_PER_SECOND := 60
const DOOR := &"door_concession"

var _catcher := ErrorCatcher.new()


func after_test() -> void:
	_catcher.stop()


func _night(team_links: bool) -> SeatedNight:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = LONG_BREAK
	tuning.rounds.break_seconds = LONG_BREAK
	var night := await NightFixture.seat(self, 2, tuning, SEED, true)
	night.stand_still = true
	night.level.shop.team_links = team_links
	for id in [1, 2]:
		night.seat(id, BotProfile.regular(), SEED + id)
	await night.settle(12)
	_catcher.start()
	for id in [1, 2]:
		night.server.rules.players[id].points = 500
	return night


func _distance(night: SeatedNight, id: int) -> float:
	var here := night.server.body_of(id).global_position
	var at: Vector3 = night.level.shop.door_stands[DOOR][0]
	return Vector2(here.x - at.x, here.z - at.z).length()


func _bot(night: SeatedNight, id: int) -> BotClient:
	for candidate in night.host.bots:
		if candidate.state.player_id == id:
			return candidate
	return null


## Seconds until the door opens (-1 if it never does), the nearer bot's brain stopped when asked;
## `buyers` gets who bought.
func _door_time(night: SeatedNight, stop_nearer: bool, buyers: Array[int]) -> float:
	night.on_event = func(event: Dictionary) -> void:
		if event["type"] == &"purchase_made" and event["item_id"] == DOOR:
			buyers.append(event["player_id"])
	var nearer := 1 if _distance(night, 1) <= _distance(night, 2) else 2
	if stop_nearer:
		_bot(night, nearer).brain_enabled = false
	for tick in int(100.0 * TICKS_PER_SECOND):
		night.tick()
		if night.server.rules.is_door_open(DOOR):
			return float(tick) / TICKS_PER_SECOND
	return -1.0


func test_with_the_rule_on_the_free_bot_buys_when_the_nearer_one_is_busy() -> void:
	var night := await _night(true)
	var buyers: Array[int] = []
	var took := _door_time(night, true, buyers)
	assert_float(took).is_greater(0.0)
	assert_float(took).is_less(BotErrands.TURN_SECONDS)
	assert_int(buyers.size()).is_equal(1)
	assert_array(_catcher.lines).is_empty()
	night.dispose()


func test_with_the_rule_off_the_same_night_waits_for_the_rotation() -> void:
	var night := await _night(false)
	var buyers: Array[int] = []
	var took := _door_time(night, true, buyers)
	assert_float(took).is_greater(BotErrands.TURN_SECONDS - 1.0)
	night.dispose()


func test_with_both_free_one_bot_buys_the_link_once() -> void:
	var night := await _night(true)
	var buyers: Array[int] = []
	var took := _door_time(night, false, buyers)
	assert_float(took).is_greater(0.0)
	for _i in 600:
		night.tick()
	assert_int(buyers.size()).is_equal(1)
	assert_array(_catcher.lines).is_empty()
	night.dispose()
