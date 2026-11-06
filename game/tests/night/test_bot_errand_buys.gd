# What a bot buys at the spots of the lot (bots plan, phase 4): the wall shotgun, the hearty tonic,
# a crane play, and rounds at a locker (a short reserve, a dry gun). The scenarios of the errands
# themselves are in `test_bot_errands.gd`. Ticks are run by hand.
extends GdUnitTestSuite

const TICKS_PER_SECOND := 60
const SEED := 41
const LONG_BREAK := 3000.0
const SETTLE_FRAMES := 60
const DOOR := &"door_concession"
## The locker in the concession, 30 m from home, and the one at home the bot would use alone.
const MARKED_LOCKER := Vector3(8.35, 0.0, -1.8)
const HOME_LOCKER := Vector3(2.0, 0.0, -31.0)
## Metres from a locker within which a purchase counts as made there (a hand reaches 3.2 m).
const AT_LOCKER := 3.5

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
	night.server.combat.state_of(1, &"house_pistol").reserve = 4
	var bought := _purchases(night, &"ammo_house_pistol")
	_seconds(night, 90.0)
	assert_int(bought.size()).is_greater_equal(1)
	assert_int(night.server.combat.state_of(1, &"house_pistol").reserve).is_greater(4)
	night.dispose()


func test_a_bot_with_a_dry_gun_walks_to_a_locker_and_buys_rounds() -> void:
	var night := await _night(1)
	_give(night, 1, 200)
	var pistol = night.server.combat.state_of(1, &"house_pistol")
	pistol.ammo = 0
	pistol.reserve = 0
	var bought := _purchases(night, &"ammo_house_pistol")
	_seconds(night, 120.0)
	assert_int(bought.size()).is_greater_equal(1)
	assert_int(pistol.reserve + pistol.ammo).is_greater(0)
	night.dispose()


func _dry_bot_with_a_dead_one_at(metres: float) -> SeatedNight:
	var night := await _night(1)
	var pistol = night.server.combat.state_of(1, &"house_pistol")
	pistol.ammo = 0
	pistol.reserve = 0
	var here := night.server.body_of(1).global_position
	# One of the dead that stands where it is: the lot is never quiet in a late round.
	var zombie := night.server.sim.spawn(2001, 0.0, here + Vector3(0.0, 0.0, -metres))
	zombie.speed = 0.0
	zombie.enter(ZombieBody.Mode.CHASE)
	night.hold_fire = true
	return night


func test_a_dry_bot_runs_for_rounds_with_a_dead_one_in_sight_but_not_in_reach() -> void:
	# The soak found bots dying with thousands of points and empty guns: they shopped only in a lull.
	var night := await _dry_bot_with_a_dead_one_at(8.0)
	_give(night, 1, 0)
	# The bot has made the dead one out before it holds the price.
	_seconds(night, 3.0)
	_give(night, 1, 200)
	var pistol = night.server.combat.state_of(1, &"house_pistol")
	var bought := _purchases(night, &"ammo_house_pistol")
	_seconds(night, 90.0)
	assert_int(bought.size()).is_greater_equal(1)
	assert_int(pistol.reserve + pistol.ammo).is_greater(0)
	night.dispose()


func test_a_dry_bot_holding_the_start_pistol_runs_for_rounds_for_the_freeze_gun_in_its_pack(
) -> void:
	# #1346: the freeze gun is the only gun worth rounds, no wall sells them, and the locker sold for
	# the weapon in hand (the empty start pistol): two nights of a hundred stood the boss round out
	# holding 1 780 points and two empty guns.
	var night := await _dry_bot_with_a_dead_one_at(8.0)
	night.server.combat.apply(CombatAction.give_weapon(1, &"freeze_gun"))
	var freeze = night.server.combat.state_of(1, &"freeze_gun")
	freeze.ammo = 0
	freeze.reserve = 0
	night.server.combat.apply(CombatAction.equip(1, &"house_pistol"))
	_give(night, 1, 0)
	_seconds(night, 3.0)
	_give(night, 1, 400)
	var bought := _purchases(night, &"ammo_freeze_gun")
	_seconds(night, 90.0)
	assert_int(bought.size()).is_greater_equal(1)
	assert_int(freeze.reserve + freeze.ammo).is_greater(0)
	night.dispose()


func test_a_dry_bot_that_cannot_pay_for_the_freeze_gun_s_rounds_buys_the_start_pistols() -> void:
	# The freeze gun's three rounds cost 150, the start pistol's thirty cost 40 (the nightly's
	# seed 55 held 105 points and a crowbar and fed nothing for eight minutes).
	var night := await _dry_bot_with_a_dead_one_at(8.0)
	night.server.combat.apply(CombatAction.give_weapon(1, &"freeze_gun"))
	var freeze = night.server.combat.state_of(1, &"freeze_gun")
	freeze.ammo = 0
	freeze.reserve = 0
	night.server.combat.apply(CombatAction.equip(1, &"house_pistol"))
	_give(night, 1, 0)
	_seconds(night, 3.0)
	_give(night, 1, 100)
	var pistol = night.server.combat.state_of(1, &"house_pistol")
	var bought := _purchases(night, &"ammo_house_pistol")
	_seconds(night, 90.0)
	assert_int(bought.size()).is_greater_equal(1)
	assert_int(pistol.reserve + pistol.ammo).is_greater(0)
	assert_int(freeze.reserve + freeze.ammo).is_equal(0)
	night.dispose()


# --- A person's ammunition ping ---


## A night with a bot at seat 1 (no following, no other shopping: it has nothing to buy but rounds)
## and a person at seat 2 near home, the concession open.
func _person_and_bot(points: int) -> SeatedNight:
	var profile := BotProfile.regular()
	profile.follows = false
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = LONG_BREAK
	tuning.rounds.break_seconds = LONG_BREAK
	var night := await NightFixture.seat(self, 2, tuning, SEED, true)
	night.seat(1, profile, SEED + 1)
	night.human(2)
	await night.settle(12)
	await _open(night, [DOOR])
	night.server.body_of(2).teleport(Autopilot.HOME + Vector3(-4.0, 0.1, 0.0))
	_give(night, 1, points)
	_catcher.start()
	return night


func _mark_ammo(night: SeatedNight, at: Vector3) -> void:
	var answer := night.server.ping(2, {"kind": PingBoard.AMMO, "pos": at, "subject": 0})
	assert_str(answer).is_equal("")


func test_a_bot_short_of_rounds_buys_at_the_locker_a_person_marked() -> void:
	var night := await _person_and_bot(200)
	night.server.combat.state_of(1, &"house_pistol").reserve = 4
	# Standing at the other locker, whose prompt sells the same rounds: the mark is an order for the
	# marked one, so the bot walks on.
	night.server.body_of(1).teleport(HOME_LOCKER + Vector3(-1.0, 0.1, 1.0))
	night.run(2)
	assert_str(String(night.frame["players"][1]["prompt"].get("kind", &""))).is_equal("ammo")
	_mark_ammo(night, MARKED_LOCKER)
	var at := _where_bought(night, &"ammo_house_pistol", 90.0)
	assert_bool(at.is_finite()).is_true()
	assert_float(_flat(at, MARKED_LOCKER)).is_less(AT_LOCKER)
	assert_int(night.server.combat.state_of(1, &"house_pistol").reserve).is_greater(4)
	assert_array(_catcher.lines).is_empty()
	night.dispose()


func test_without_the_mark_the_same_bot_uses_the_locker_at_home() -> void:
	var night := await _person_and_bot(200)
	night.server.combat.state_of(1, &"house_pistol").reserve = 4
	var at := _where_bought(night, &"ammo_house_pistol", 90.0)
	assert_bool(at.is_finite()).is_true()
	assert_float(_flat(at, HOME_LOCKER)).is_less(AT_LOCKER)
	night.dispose()


func test_a_bot_with_full_reserves_does_not_go_to_a_marked_locker() -> void:
	var night := await _person_and_bot(200)
	var bought := _purchases(night, &"ammo_house_pistol")
	var start := night.server.body_of(1).global_position
	_mark_ammo(night, MARKED_LOCKER)
	_seconds(night, 40.0)
	var here := night.server.body_of(1).global_position
	assert_float(_flat(here, start)).is_less(3.0)
	assert_float(_flat(here, MARKED_LOCKER)).is_greater(20.0)
	assert_int(bought.size()).is_equal(0)
	assert_array(_catcher.lines).is_empty()
	night.dispose()


## Where the bot at seat 1 stood when it first bought `item_id` within `seconds`, or `Vector3.INF`.
func _where_bought(night: SeatedNight, item_id: StringName, seconds: float) -> Vector3:
	var bought := _purchases(night, item_id)
	for _tick in int(seconds * TICKS_PER_SECOND):
		night.tick()
		if not bought.is_empty():
			return night.server.body_of(1).global_position
	return Vector3.INF


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## The purchases of `item_id`, collected from now on.
func _purchases(night: SeatedNight, item_id: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	night.on_event = func(event: Dictionary) -> void:
		if event["type"] == &"purchase_made" and event["item_id"] == item_id:
			found.append(event)
	return found
