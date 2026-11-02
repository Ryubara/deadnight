# What a bot buys at the spots of the lot (bots plan, phase 4): the wall shotgun, the hearty tonic,
# a crane play, and rounds at a locker (a short reserve, a dry gun). The scenarios of the errands
# themselves are in `test_bot_errands.gd`. Ticks are run by hand.
extends GdUnitTestSuite

const TICKS_PER_SECOND := 60
const SEED := 41
const LONG_BREAK := 3000.0
const SETTLE_FRAMES := 60
const DOOR := &"door_concession"

var _catcher := ErrorCatcher.new()


func after_test() -> void:
	_catcher.stop()


func _night(bots: int, profile: BotProfile = null) -> SeatedNight:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = LONG_BREAK
	tuning.rounds.break_seconds = LONG_BREAK
	var night := await NightFixture.seat(self, bots, tuning, SEED, true)
	for id in range(1, bots + 1):
		night.seat(id, profile if profile != null else BotProfile.regular(), SEED + id)
	await night.settle(12)
	_catcher.start()
	return night


func _give(night: SeatedNight, id: int, points: int) -> void:
	night.server.rules.players[id].points = points


func _seconds(night: SeatedNight, seconds: float) -> void:
	night.run(int(seconds * TICKS_PER_SECOND))


func _until(night: SeatedNight, seconds: float, done: Callable) -> float:
	for tick in int(seconds * TICKS_PER_SECOND):
		night.tick()
		if done.call():
			return float(tick) / TICKS_PER_SECOND
	return -1.0


func _open(night: SeatedNight, doors: Array[StringName]) -> void:
	for door_id in doors:
		night.open_door(door_id)
	await night.settle(SETTLE_FRAMES)


## A night with one bot whose list is `list`, the concession open, holding `points`.
func _shopper(list: Array[StringName], points: int) -> SeatedNight:
	var profile := BotProfile.regular()
	profile.shopping.assign(list)
	profile.saves_for.clear()
	var night := await _night(1, profile)
	await _open(night, [DOOR])
	_give(night, 1, points)
	return night


func test_a_bot_buys_the_wall_shotgun_and_carries_it() -> void:
	var night := await _shopper([&"weapon_shotgun"], 1000)
	night.run(2)
	var before: Dictionary = night.frame["players"][1]["arms"]
	var weakest := BotEconomy.weakest_of(before)
	var took := _until(
		night, 120.0, func() -> bool: return night.frame["players"][1]["arms"].has(&"shotgun")
	)
	assert_float(took).is_greater(0.0)
	var after: Dictionary = night.frame["players"][1]["arms"]
	# With the hands full the weapon worth least goes, whichever is in hand; with a free hand none.
	assert_bool(after.has(weakest)).is_equal(before.size() < WeaponCatalog.CARRY_LIMIT)
	assert_int(night.server.rules.points_of(1)).is_less(200)
	assert_array(_catcher.lines).is_empty()
	night.dispose()


func test_a_bot_buys_the_hearty_tonic_once() -> void:
	var night := await _shopper([&"tonic_hearty"], 1100)
	var bought := _purchases(night, &"tonic_hearty")
	_seconds(night, 90.0)
	assert_int(bought.size()).is_equal(1)
	assert_float(night.server.rules.max_health_of(1)).is_greater(100.0)
	night.dispose()


func test_a_bot_with_no_grenades_walks_to_the_rack_and_buys_some() -> void:
	# Enough for every door on the list first: grenades are what is left over.
	var night := await _shopper([], 10000)
	var rules := night.server.rules
	rules._set_grenades(rules.players[1], 0, &"test")
	# A direct call is no part of a server step: tell the bot as the next step would.
	night.host.hear([{"type": &"grenade_count_changed", "player_id": 1, "count": 0}])
	var bought := _purchases(night, &"grenades")
	_seconds(night, 240.0)
	assert_int(bought.size()).is_greater_equal(1)
	assert_int(rules.grenades_of(1)).is_greater(0)
	assert_array(_catcher.lines).is_empty()
	night.dispose()


func test_a_bot_plays_the_crane_and_takes_the_prize_it_wants() -> void:
	var night := await _shopper([&"crane_play"], 700)
	var bought := _purchases(night, &"crane_play")
	_seconds(night, 120.0)
	assert_int(bought.size()).is_greater_equal(1)
	assert_array(_catcher.lines).is_empty()
	night.dispose()


func test_a_bot_with_a_short_reserve_walks_to_a_locker_and_buys_rounds() -> void:
	var night := await _night(1)
	_give(night, 1, 200)
	night.server.combat.state_of(1, &"pistol").reserve = 4
	var bought := _purchases(night, &"ammo_pistol")
	_seconds(night, 90.0)
	assert_int(bought.size()).is_greater_equal(1)
	assert_int(night.server.combat.state_of(1, &"pistol").reserve).is_greater(4)
	night.dispose()


func test_a_bot_with_a_dry_gun_walks_to_a_locker_and_buys_rounds() -> void:
	var night := await _night(1)
	_give(night, 1, 200)
	var pistol = night.server.combat.state_of(1, &"pistol")
	pistol.ammo = 0
	pistol.reserve = 0
	var bought := _purchases(night, &"ammo_pistol")
	_seconds(night, 120.0)
	assert_int(bought.size()).is_greater_equal(1)
	assert_int(pistol.reserve + pistol.ammo).is_greater(0)
	night.dispose()


## The purchases of `item_id`, collected from now on.
func _purchases(night: SeatedNight, item_id: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	night.on_event = func(event: Dictionary) -> void:
		if event["type"] == &"purchase_made" and event["item_id"] == item_id:
			found.append(event)
	return found
