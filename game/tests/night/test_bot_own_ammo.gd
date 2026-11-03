# A bot that runs low on rounds fetches its own, as its standing order lets it (#692), in the real
# lot with the real server: the table of needs against orders (`BotNeeds`) played out under
# Roam, Follow and Hold, and a person's ammunition ping (#670) above all three. Ticks are run
# by hand.
#
# The home locker is 23 m from where the people stand in these scenarios, beyond the follow leash;
# the concession's (a door's walk away) is the nearer one for a bot that roams.
extends GdUnitTestSuite

const TICKS_PER_SECOND := 60
const SEED := 67
const LONG_BREAK := 3000.0
const SETTLE_FRAMES := 60
const DOOR := &"door_concession"
const PERSON := 1
const BOT := 2
const POINTS := 300
## The lockers: at home, and in the concession.
const HOME_LOCKER := Vector3(2.0, 0.0, -31.0)
const CONCESSION_LOCKER := Vector3(8.35, 0.0, -1.8)
## A place east of the concession's fence, nearer to its locker by the straight line and to the
## home locker by the walk.
const FENCED_OFF := Vector3(30.0, 0.0, -20.0)
## Where the people stand outside the concession, 23 m from the home locker.
const OUTSIDE := Vector3(0.0, 0.0, -8.0)
## Reserves of the pistol (magazine 10): under three magazines, under one.
const LOW_RESERVE := 25
const SHORT_RESERVE := 6
## Metres from a locker within which a purchase counts as made there (a hand reaches 3.2 m).
const AT_LOCKER := 3.5
## Metres the order promises: the follow band's far edge with slack, and a held spot.
const FOLLOW_NEAR := 12.0
const HOLD_RADIUS := 3.0
## Seconds that are long enough for a bot to have gone and bought, and to show it will not.
const TRIP := 120.0
const PATIENCE := 45.0
const BREAKER_SECONDS := 30.0

var _catcher := ErrorCatcher.new()
var _bought: Array[Vector3] = []
var _said: Array[StringName] = []


func after_test() -> void:
	_catcher.stop()


## A night with a person at seat 1 and one bot at seat 2 holding `POINTS`, a long break so nobody is
## in a hurry, the concession open when `open`.
func _night(open: bool, profile: BotProfile = null) -> SeatedNight:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = LONG_BREAK
	tuning.rounds.break_seconds = LONG_BREAK
	var night := await NightFixture.seat(self, 2, tuning, SEED, true)
	night.human(PERSON)
	night.seat(BOT, profile if profile != null else BotProfile.regular(), SEED + BOT)
	await night.settle(12)
	if open:
		night.open_door(DOOR)
		await night.settle(SETTLE_FRAMES)
	night.server.rules.players[BOT].points = POINTS
	_place(night, PERSON, OUTSIDE)
	_place(night, BOT, OUTSIDE + Vector3(3.0, 0.0, -2.0))
	_bought.clear()
	_said.clear()
	night.on_event = func(event: Dictionary) -> void:
		if event["type"] == &"purchase_made" and event["item_id"] == &"ammo_pistol":
			_bought.append(_where(night, BOT))
		elif event["type"] == &"bot_say" and event["player_id"] == BOT:
			_said.append(event["line"])
	_catcher.start()
	return night


func _place(night: SeatedNight, id: int, at: Vector3) -> void:
	night.server.body_of(id).teleport(at + Vector3(0.0, 0.1, 0.0))


func _where(night: SeatedNight, id: int) -> Vector3:
	return night.server.body_of(id).global_position


func _pistol(night: SeatedNight) -> Object:
	return night.server.combat.state_of(BOT, &"pistol")


func _short(night: SeatedNight, reserve: int, magazine := 10) -> void:
	_pistol(night).reserve = reserve
	_pistol(night).ammo = magazine


## Runs until the bot has bought rounds or `seconds` are over; true when it did.
func _until_bought(night: SeatedNight, seconds: float) -> bool:
	for _tick in int(seconds * TICKS_PER_SECOND):
		night.tick()
		if not _bought.is_empty():
			return true
	return false


## Runs `seconds` and returns the farthest the bot went from `from`.
func _farthest_from(night: SeatedNight, from: Vector3, seconds: float) -> float:
	var farthest := 0.0
	for _tick in int(seconds * TICKS_PER_SECOND):
		night.tick()
		farthest = maxf(farthest, _flat(_where(night, BOT), from))
	return farthest


## Runs `seconds` more and says whether the bot was within `radius` of `at` at the end.
func _settle_near(night: SeatedNight, at: Vector3, radius: float, seconds: float) -> bool:
	night.run(int(seconds * TICKS_PER_SECOND))
	return _flat(_where(night, BOT), at) <= radius


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- Roam: goes freely ---


func test_a_roaming_bot_low_on_rounds_walks_to_the_nearest_locker_by_the_walk_and_buys() -> void:
	var night := await _night(true)
	_short(night, LOW_RESERVE)
	assert_str(String(BotOrders.current(night.frame, BOT)["order"])).is_equal("roam")
	assert_bool(_until_bought(night, TRIP)).is_true()
	# The concession's locker is a few metres of walk through the door; the home one is a long walk.
	assert_float(_flat(_bought[0], CONCESSION_LOCKER)).is_less(AT_LOCKER)
	assert_int(_pistol(night).reserve).is_greater(LOW_RESERVE)
	assert_array(_catcher.lines).is_empty()
	night.dispose()


func test_a_roaming_bot_picks_the_locker_that_is_the_shorter_walk_not_the_nearer_one() -> void:
	var night := await _night(true)
	# East of the concession's fence: its locker is 28 m away through the wall, the home locker 30 m
	# in the open, and the walk to the concession goes round by the door, 42 m.
	# The breaker of the concession's lamps is the first errand a bot has once the door is open: let
	# it be done, so the only errand left is the rounds.
	night.run(int(BREAKER_SECONDS * TICKS_PER_SECOND))
	_place(night, BOT, FENCED_OFF)
	assert_float(_flat(FENCED_OFF, CONCESSION_LOCKER)).is_less(_flat(FENCED_OFF, HOME_LOCKER))
	_short(night, LOW_RESERVE)
	assert_bool(_until_bought(night, TRIP)).is_true()
	assert_float(_flat(_bought[0], HOME_LOCKER)).is_less(AT_LOCKER)
	night.dispose()


func test_a_roaming_bot_with_rounds_to_spare_does_not_go_for_more_than_it_wants() -> void:
	var night := await _night(true)
	_pistol(night).reserve = 60
	night.run(int(PATIENCE * TICKS_PER_SECOND))
	assert_array(_bought).is_empty()
	night.dispose()


# --- Follow: goes when the source is near the leader, or when the gun is empty ---


func test_a_following_bot_low_on_rounds_with_no_locker_near_stays_and_says_so() -> void:
	var night := await _night(false)
	night.give_order(BotOrders.FOLLOW, PERSON, OUTSIDE)
	_short(night, LOW_RESERVE)
	var farthest := _farthest_from(night, _where(night, PERSON), PATIENCE)
	assert_array(_bought).is_empty()
	assert_float(farthest).is_less(FOLLOW_NEAR)
	assert_array(_said).contains([&"need_ammo"])
	night.dispose()


func test_a_following_bot_goes_when_the_leader_comes_near_a_locker_and_comes_back() -> void:
	var night := await _night(false)
	night.give_order(BotOrders.FOLLOW, PERSON, OUTSIDE)
	_short(night, LOW_RESERVE)
	night.run(int(10.0 * TICKS_PER_SECOND))
	assert_array(_bought).is_empty()
	# The person walks to the home locker's side; the bot, still at its leader's side, goes too.
	var walker: HumanWalker = night.walkers[0]
	walker.goto(HOME_LOCKER + Vector3(-3.0, 0.0, 6.0))
	assert_bool(_until_bought(night, TRIP)).is_true()
	assert_float(_flat(_bought[0], HOME_LOCKER)).is_less(AT_LOCKER)
	assert_bool(_settle_near(night, _where(night, PERSON), FOLLOW_NEAR, 40.0)).is_true()
	night.dispose()


func test_a_following_bot_with_an_empty_gun_goes_anyway_and_comes_back_to_the_leader() -> void:
	var night := await _night(false)
	night.give_order(BotOrders.FOLLOW, PERSON, OUTSIDE)
	_short(night, 0, 0)
	assert_bool(_until_bought(night, TRIP)).is_true()
	assert_float(_flat(_bought[0], HOME_LOCKER)).is_less(AT_LOCKER)
	assert_int(_pistol(night).reserve + _pistol(night).ammo).is_greater(0)
	assert_bool(_settle_near(night, _where(night, PERSON), FOLLOW_NEAR, 60.0)).is_true()
	assert_array(_catcher.lines).is_empty()
	night.dispose()


# --- Hold: keeps the spot until the reserve is under a magazine ---


func test_a_holding_bot_low_on_rounds_keeps_its_spot() -> void:
	var night := await _night(false)
	night.give_order(BotOrders.HOLD, PERSON, OUTSIDE)
	night.run(int(15.0 * TICKS_PER_SECOND))
	var spot: Vector3 = BotOrders.current(night.frame, BOT)["at"]
	_short(night, LOW_RESERVE)
	var farthest := _farthest_from(night, spot, PATIENCE)
	assert_array(_bought).is_empty()
	assert_float(farthest).is_less(HOLD_RADIUS)
	night.dispose()


func test_a_holding_bot_under_a_magazine_goes_buys_and_returns_to_the_spot() -> void:
	var night := await _night(false)
	night.give_order(BotOrders.HOLD, PERSON, OUTSIDE)
	night.run(int(15.0 * TICKS_PER_SECOND))
	var spot: Vector3 = BotOrders.current(night.frame, BOT)["at"]
	_short(night, SHORT_RESERVE)
	assert_bool(_until_bought(night, TRIP)).is_true()
	assert_float(_flat(_bought[0], HOME_LOCKER)).is_less(AT_LOCKER)
	assert_bool(_settle_near(night, spot, HOLD_RADIUS, 60.0)).is_true()
	assert_array(_catcher.lines).is_empty()
	night.dispose()


# --- A person's ping names the place and sits above every order ---


func test_a_holding_bot_low_on_rounds_goes_to_the_locker_a_person_marked() -> void:
	var night := await _night(true)
	night.give_order(BotOrders.HOLD, PERSON, OUTSIDE)
	night.run(int(15.0 * TICKS_PER_SECOND))
	var spot: Vector3 = BotOrders.current(night.frame, BOT)["at"]
	_short(night, LOW_RESERVE)
	# Under the hold alone this reserve stays put (the test above); the mark names the far locker.
	var answer := night.server.ping(
		PERSON, {"kind": PingBoard.AMMO, "pos": HOME_LOCKER, "subject": 0}
	)
	assert_str(answer).is_equal("")
	assert_bool(_until_bought(night, TRIP)).is_true()
	assert_float(_flat(_bought[0], HOME_LOCKER)).is_less(AT_LOCKER)
	assert_bool(_settle_near(night, spot, HOLD_RADIUS, 60.0)).is_true()
	night.dispose()
