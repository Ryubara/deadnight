# The autopilot seated as a person in a suite or the soak (`SeatedNight.seat` with `legacy`) shops
# like the one in a night does (#998): it was made bare, with no shop spots and no prices, so its
# pistol read 0/0 for rounds on end while it had points to spend. Ticks are run by hand.
extends GdUnitTestSuite

const TICKS_PER_SECOND := 60
const SEED := 998
const LONG_BREAK := 3000.0
const SETTLE_FRAMES := 60
const PERSON := 1
## Where it stands to start: the field in front of the screen, a walk from the lockers.
const START := Vector3(0.0, 0.0, -20.0)
## Points that pay for a purchase of rounds and nothing else it wants.
const ROUNDS_POINTS := 300
## Points that pay for the first wall weapon with some to spare.
const GUN_POINTS := 5000
const TRIP := 120.0
## Ticks between the physics frames the engine is given.
const FRAME_EVERY := 30

var _catcher := ErrorCatcher.new()
var _bought: Array[StringName] = []


func after_test() -> void:
	_catcher.stop()


func _night() -> SeatedNight:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = LONG_BREAK
	tuning.rounds.break_seconds = LONG_BREAK
	var night := await NightFixture.seat(self, 1, tuning, SEED, true)
	night.seat(PERSON, BotProfile.autopilot(), SEED + PERSON, true)
	await night.settle(SETTLE_FRAMES)
	night.server.body_of(PERSON).teleport(START + Vector3(0.0, 0.1, 0.0))
	_bought.clear()
	night.on_event = func(event: Dictionary) -> void:
		if event["type"] == &"purchase_made" and event["player_id"] == PERSON:
			_bought.append(event["item_id"])
	_catcher.start()
	return night


func _pilot(night: SeatedNight) -> Autopilot:
	return night.host.bots[0].legacy


func _pistol(night: SeatedNight) -> Object:
	return night.server.combat.state_of(PERSON, &"pistol")


## Runs until `done` says so or `seconds` are over, giving the engine a physics frame every
## `FRAME_EVERY` ticks (a bought door's navigation mesh needs one); true when `done` was reached.
func _until(night: SeatedNight, done: Callable, seconds: float) -> bool:
	for tick in int(seconds * TICKS_PER_SECOND):
		night.tick()
		if done.call():
			return true
		if tick % FRAME_EVERY == 0:
			await night.settle(1)
	return false


func test_a_seated_autopilot_knows_the_shop_a_night_gives_it() -> void:
	var night := await _night()
	var pilot := _pilot(night)
	assert_bool(pilot.spots.is_empty()).is_false()
	assert_bool(pilot.ammo_prices.has(&"pistol")).is_true()
	assert_bool(pilot.wanted.is_empty()).is_false()
	assert_bool(pilot.order.is_empty()).is_false()
	assert_bool(pilot.repair_goals.is_empty()).is_false()
	assert_int(pilot.recut_price).is_greater(0)
	night.dispose()


func test_a_seated_autopilot_with_an_empty_pistol_walks_to_a_locker_and_buys_rounds() -> void:
	var night := await _night()
	_pistol(night).ammo = 0
	_pistol(night).reserve = 0
	night.server.rules.players[PERSON].points = ROUNDS_POINTS
	var bought := func() -> bool: return _bought.has(&"ammo_pistol")
	assert_bool(await _until(night, bought, TRIP)).is_true()
	assert_int(_pistol(night).reserve + _pistol(night).ammo).is_greater(0)
	night.dispose()


func test_a_seated_autopilot_with_points_to_spare_buys_a_wall_weapon() -> void:
	var night := await _night()
	night.server.rules.players[PERSON].points = GUN_POINTS
	var armed := func() -> bool: return night.frame["players"][PERSON].get("arms", {}).size() > 1
	assert_bool(await _until(night, armed, TRIP)).is_true()
	night.dispose()
