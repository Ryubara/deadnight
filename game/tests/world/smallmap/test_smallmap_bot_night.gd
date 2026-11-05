# Bots play the second map by themselves: they start in the hall, the dead come in through the
# windows, they buy the first link and the weapons, play the box and put boards back, and they hold
# for several rounds. A short night of each size (`tests/captures/smallmap_bot_night.tscn` plays
# the long ones to round 10 and prints the numbers for the design page).
extends GdUnitTestSuite

## Game seconds of the night of four on the whole map (the solo night's are in `SoloBotNight`).
const FOUR_SECONDS := 150.0
## Game seconds in which four bots on the shut map have bought every link (round 4 at the latest).
const FOUR_LINKS_SECONDS := 210.0
const FRAME_EVERY := 30
## The solo night is judged as a rate over these seeds (`SoloBotNight`), not on pinned seeds: the
## night is chaotic, so a change that moves one hit moves the nights after it on every seed, and a
## seed picked on the night it passed went red on changes that did nothing wrong (#821, #890, #910,
## #1038). Measured on main (`tests/captures/smallmap_solo_sweep.tscn`, seeds 1 to 100, 2026-11-04,
## at 40365bce): the solo bot failed on 5 of 100 (seeds 38, 40, 50, 64, 84: downed in round 3 or 4
## at 87 to 135 s, three of them without a gun), none of these 10 seeds.
const SOLO_SEEDS := 10
## Nights the solo bot may fail of those 10. At the 5% of main a change that only reshuffles the
## nights puts 4 or more of 10 down 0.1% of the time (binomial; 1.8% at the 11% that the 95% bound
## of main's 5 of 100 allows; the ten blocks of ten seeds of the sweep had 0 to 2), a bot that
## stops buying fails all 10, and one that fails half of the nights is caught 83% of the time. A
## tighter rate is the sweep's to measure (a night is 4.6 s: 100 seeds are two minutes on four
## processes), not a suite's: ten nights are already 46 s of this file.
const SOLO_FAILURES_ALLOWED := 3

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


## A bot alone buys the first link and a weapon, tears four windows' boards, holds the dead to 24
## at once and reaches round 4 on all but a few seeds of `SOLO_SEEDS`.
func test_a_bot_alone_buys_a_link_and_a_weapon_and_reaches_round_4_on_nearly_every_seed() -> void:
	var failed: Array[String] = []
	for seed_value in range(1, SOLO_SEEDS + 1):
		var night := SoloBotNight.new(seed_value)
		await night.play(self)
		if not night.failures().is_empty():
			failed.append("seed %d: %s" % [seed_value, ", ".join(night.failures())])
	(
		assert_int(failed.size())
		. override_failure_message(
			(
				"the solo bot failed %d of %d nights (at most %d): %s"
				% [failed.size(), SOLO_SEEDS, SOLO_FAILURES_ALLOWED, " | ".join(failed)]
			)
		)
		. is_less_equal(SOLO_FAILURES_ALLOWED)
	)


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
