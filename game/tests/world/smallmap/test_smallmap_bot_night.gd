# Bots play the second map by themselves: they start in the hall, the dead come in through the
# windows, they buy the first link and the weapons, play the box and put boards back, and they hold
# for several rounds. A short night of each size (`tests/captures/smallmap_bot_night.tscn` plays
# the long ones to round 10 and prints the numbers for the design page).
extends GdUnitTestSuite

## Game seconds of the solo night, and of the night of four on the whole map. The solo bot buys the
## first link and then its first gun (the overlay saves for the shotgun, and a bot with only its
## start gun is offered nothing after a gun it can pay for), by 107 s on 12 of 14 seeds and by 225 s
## on all; before, the two stairs came first and the gun in the break of round 4, which a night lost
## on one seed of four (#910). A bot starts no errand with a dead within 12 m, so the
## night still runs past the breaks of rounds 5 and 6: the weapon is bought in one of several
## breaks.
const SOLO_SECONDS := 330.0
const FOUR_SECONDS := 150.0
## Game seconds in which four bots on the shut map have bought every link (round 4 at the latest).
const FOUR_LINKS_SECONDS := 210.0
const FRAME_EVERY := 30
## A night that has shown everything its test asks for runs on this many game seconds more (the
## cap on the dead alive is read to the end) and stops: the asked-for things are events, and an
## event that has happened stays happened. With the full 330 s the solo bot has shown them all by
## 130 s on the four seeds (round 4 at 123 to 128 s, the weapon at 75 to 127 s), and the three links
## of the team by 60 s.
const GRACE_SECONDS := 30.0

var _seated: SeatedNight
var _links: Array[StringName] = []
var _tears: Dictionary = {}
var _buys: Dictionary = {}
var _rounds_started := 0
var _most_alive := 0
## The round each link was bought in (#696).
var _link_rounds: Dictionary = {}


func after_test() -> void:
	if _seated != null:
		_seated.dispose()
		_seated = null


## Plays `seconds` of game time, or until `done` (when given) has been true for `grace` seconds.
func _play(
	bots: int, seconds: float, open_all: bool, seed_value := 3, done := Callable(), grace := 0.0
) -> void:
	_links.clear()
	_tears.clear()
	_buys.clear()
	_link_rounds.clear()
	_rounds_started = 0
	_most_alive = 0
	_seated = await SmallMapNight.seat(self, bots, null, seed_value)
	var profiles := [BotProfile.regular(), BotProfile.veteran(), BotProfile.rookie()]
	for i in bots:
		_seated.seat(i + 1, profiles[i % profiles.size()], 400 + i)
	if open_all:
		var points := _seated.server.rules.points_of(1)
		for item in _seated.server.rules.tuning.economy.items:
			if item.kind == ShopItem.Kind.DOOR:
				_seated.open_door(item.id)
		_seated.server.rules.players[1].points = points
		await _seated.settle(10)
	_seated.on_event = _on_event
	_seated.start_round()
	var ticks := int(seconds * 60.0)
	var done_at := -1
	for tick in ticks:
		_seated.tick()
		_most_alive = maxi(_most_alive, _seated.server.sim.standing_count())
		if done.is_valid():
			if done_at < 0 and done.call():
				done_at = tick
			if done_at >= 0 and tick - done_at >= int(grace * 60.0):
				break
		if tick % FRAME_EVERY == 0:
			await get_tree().physics_frame


func _on_event(event: Dictionary) -> void:
	match event["type"]:
		&"door_opened":
			_links.append(event["door_id"])
			_link_rounds[event["door_id"]] = _seated.server.rules.round_number
		&"board_torn":
			_tears[event["barricade_id"]] = int(_tears.get(event["barricade_id"], 0)) + 1
		&"purchase_made":
			_buys[event["item_id"]] = int(_buys.get(event["item_id"], 0)) + 1
		&"round_started":
			_rounds_started = maxi(_rounds_started, int(event["round"]))


## The seeds the solo night is held over: the one night that flaked (a bot that bought no weapon
## because it paced the stair landing between two sellers of the shotgun, #821) was a matter of the
## seed, so the test holds on every one of these and not on one picked to pass.
func test_a_bot_alone_buys_a_link_and_a_weapon_holds_the_windows_and_reaches_round_4(
	seed_value: int, test_parameters := [[1], [3], [4], [7]]
) -> void:
	assert_object(test_parameters).is_not_null()
	await _play(1, SOLO_SECONDS, false, seed_value, _solo_has_shown_it, GRACE_SECONDS)
	var rules := _seated.server.rules
	(
		assert_int(_rounds_started)
		. override_failure_message("round %d" % _rounds_started)
		. is_greater_equal(4)
	)
	assert_array(_links).contains([&"door_side"])
	assert_int(_tears.size()).is_greater_equal(4)
	var weapons := 0
	for id: StringName in _buys:
		var item := rules.tuning.economy.item(id)
		if item.kind == ShopItem.Kind.WEAPON or item.kind == ShopItem.Kind.CRANE:
			weapons += 1
	assert_int(weapons).override_failure_message("bought %s" % [_buys]).is_greater_equal(1)
	assert_int(_most_alive).is_less_equal(24)


## Whether the solo night has shown everything its test asks for: round 4 begun, the first link
## bought, four windows torn and a weapon bought.
func _solo_has_shown_it() -> bool:
	if _rounds_started < 4 or not _links.has(&"door_side") or _tears.size() < 4:
		return false
	for id: StringName in _buys:
		var kind := _seated.server.rules.tuning.economy.item(id).kind
		if kind == ShopItem.Kind.WEAPON or kind == ShopItem.Kind.CRANE:
			return true
	return false


func test_four_bots_on_the_whole_map_hold_it_for_several_rounds() -> void:
	await _play(4, FOUR_SECONDS, true)
	assert_int(_rounds_started).is_greater_equal(3)
	assert_int(_most_alive).is_less_equal(24)
	# With every link sold the windows of all three rooms are in the pool: the dead tore into at
	# least five of the twelve in three rounds.
	(
		assert_int(_tears.size())
		. override_failure_message("torn %s" % [_tears.keys()])
		. is_greater_equal(5)
	)


func test_four_bots_buy_all_three_links_together_in_the_first_rounds() -> void:
	# The team rule (`bot_team_links`): the door's rotation and the one-errand turn left the
	# second stair unbought for the whole night; now the nearest free bot buys each link in the
	# first lulls.
	await _play(4, FOUR_LINKS_SECONDS, false, 3, func() -> bool: return _link_rounds.size() == 3)
	assert_int(_link_rounds.size()).override_failure_message("links %s" % [_link_rounds]).is_equal(
		3
	)
	for link: StringName in _link_rounds:
		(
			assert_int(_link_rounds[link])
			. override_failure_message("%s" % [_link_rounds])
			. is_less_equal(4)
		)
