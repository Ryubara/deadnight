# The standing orders of the bots in the real lot with the real server (#641): a person gives an
# order the way the command wheel does (a `BotOrders` whose sender is the connection of seat 1, so
# the action is bytes and back and the server decides), and hosted bots read it from the frame.
# - Roam spreads the bots over the map and away from the person, and no bot stands idle;
# - Follow keeps them within the follow band;
# - Hold keeps them within 3 m of the spot;
# - a downed person pulls a bot in every order, and it goes back to its order afterwards.
# Ticks are run by hand; only the physics frames the navigation server needs are awaited.
extends GdUnitTestSuite

const STEP := Night.STEP
const TICKS_PER_SECOND := 60
const SEED := 53
## A round that never begins its spawning.
const QUIET := 6000.0
## The person's seat.
const PERSON := 1
## Metres: the follow band's far edge plus the catching-up slack (the soak's "with them").
const FOLLOW_NEAR := 12.0
## Metres from the held spot that the order promises, and the share of the time it is kept (a person
## who walks through the group is given way, which moves a bot off its place for a moment).
const HOLD_RADIUS := 3.0
const HOLD_SHARE := 0.95
## The longest a bot may stand still with nothing to do (seconds): a look about lasts at most five.
const IDLE_LIMIT := 8.0
## Metres: a bot this near the speed of nothing is standing.
const STANDING := 0.05

var _catcher := ErrorCatcher.new()
var _gave: Array[Dictionary] = []


func after_test() -> void:
	_catcher.stop()


func _quiet() -> RulesTuning:
	var tuning := RulesFixture.tuning()
	tuning.rounds.first_spawn_delay = QUIET
	return tuning


## A night with a person at seat 1 (a stand-in) and `bots` bots after them, the round on and the
## doors in `doors` sold.
func _night(bots: int, doors: Array[StringName] = []) -> SeatedNight:
	var night := await NightFixture.seat(self, 1 + bots, _quiet(), SEED)
	night.human(PERSON)
	for id in range(2, 2 + bots):
		night.seat(id, BotProfile.regular(), SEED + id)
	for door in doors:
		night.open_door(door)
	await night.settle(12)
	night.start_round()
	_catcher.start()
	return night


func _place(night: SeatedNight, id: int, at: Vector3) -> void:
	night.server.body_of(id).teleport(at + Vector3(0.0, 0.1, 0.0))


func _where(night: SeatedNight, id: int) -> Vector3:
	return night.server.body_of(id).global_position


func _bot(night: SeatedNight, id: int) -> BotClient:
	for candidate in night.host.bots:
		if candidate.state.player_id == id:
			return candidate
	return null


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## The person's word, as the wheel gives it: through `BotOrders.issue`, over a sender that puts the
## action on the connection of seat 1 (bytes and back, as a link does).
func _give(night: SeatedNight, order: StringName, at: Vector3, bot_id := 0) -> Dictionary:
	var orders := BotOrders.new()
	orders.sender = Callable(self, &"_to_server").bind(night)
	var action := orders.issue(order, PERSON, at, bot_id)
	night.run(2)
	return action


func _to_server(action: Dictionary, night: SeatedNight) -> void:
	_gave.append(action)
	night.server.apply(bytes_to_var(var_to_bytes(action)), PERSON)


## Takes player `id` to the ground, as a blow outside a step does, and lets the bots hear it.
func _down(night: SeatedNight, id: int) -> void:
	night.host.hear(night.server.rules.apply(RulesAction.blow(id, 500.0)))


func _speed_of(night: SeatedNight, id: int) -> float:
	return night.server.body_of(id).velocity.length()


## Runs `seconds` and returns, for every bot, `{idle (longest seconds standing with nothing to do),
## far (share of the ticks farther than FOLLOW_NEAR from the person), cells (10 m cells walked
## through), spot (the farthest the bot was from `spot`, when given)}`.
func _watch(night: SeatedNight, seconds: float, ids: Array[int], spot := Vector3.INF) -> Dictionary:
	var out := {}
	var still := {}
	for id in ids:
		out[id] = {"idle": 0.0, "far": 0, "ticks": 0, "cells": {}, "spot": 0.0, "held": 0}
		still[id] = 0
	for _t in int(seconds * TICKS_PER_SECOND):
		night.tick()
		for id in ids:
			var here := _where(night, id)
			var note: String = _bot(night, id).intent.note
			# Standing with nothing to do: a bot that says it roams (or holds, or nothing) and does not
			# move. A look about, a fight, a held place and an errand are something.
			var idle_note := note == "" or note == "hold" or note == "roam"
			still[id] = still[id] + 1 if _speed_of(night, id) < STANDING and idle_note else 0
			var seen: Dictionary = out[id]
			seen["idle"] = maxf(seen["idle"], float(still[id]) / TICKS_PER_SECOND)
			seen["ticks"] += 1
			if _flat(here, _where(night, PERSON)) > FOLLOW_NEAR:
				seen["far"] += 1
			seen["cells"][Vector2i(floori(here.x / 10.0), floori(here.z / 10.0))] = true
			if spot != Vector3.INF:
				seen["spot"] = maxf(seen["spot"], _flat(here, spot))
				if _flat(here, spot) <= HOLD_RADIUS:
					seen["held"] += 1
	return out


# --- Roam: the default ---


func test_with_no_order_given_the_bots_roam_away_from_the_person_and_none_stands_idle() -> void:
	var night := await _night(3)
	var home := Autopilot.HOME
	_place(night, PERSON, home)
	for id in [2, 3, 4]:
		_place(night, id, home + Vector3(float(id - 3) * 2.0, 0.0, 3.0))
	assert_str(str(BotOrders.current(night.frame, 2)["order"])).is_equal("roam")
	night.run(60 * 20)
	var seen := _watch(night, 60.0, [2, 3, 4])
	var apart := 0.0
	for id in [2, 3, 4]:
		var report: Dictionary = seen[id]
		var far := float(report["far"]) / float(report["ticks"])
		(
			assert_float(report["idle"])
			. override_failure_message(
				"bot %d stood idle %.1f s: %s" % [id, report["idle"], report]
			)
			. is_less(IDLE_LIMIT)
		)
		(
			assert_int((report["cells"] as Dictionary).size())
			. override_failure_message("bot %d walked through few places: %s" % [id, report])
			. is_greater(2)
		)
		apart += far
	# Spread over the map and away from the person: most of the time well beyond the follow band.
	(
		assert_float(apart / 3.0)
		. override_failure_message(
			"share of the time beyond %d m: %.2f" % [FOLLOW_NEAR, apart / 3.0]
		)
		. is_greater(0.5)
	)
	for id in [2, 3, 4]:
		assert_float(_bot(night, id).legs.stuck.longest()).is_less(6.0)
	night.dispose()


func test_roaming_bots_take_different_places_from_each_other() -> void:
	var night := await _night(3)
	_place(night, PERSON, Autopilot.HOME)
	night.run(60 * 25)
	var places: Array[Vector3] = []
	for id in [2, 3, 4]:
		places.append(_where(night, id))
	var closest := INF
	for i in places.size():
		for j in range(i + 1, places.size()):
			closest = minf(closest, _flat(places[i], places[j]))
	(
		assert_float(closest)
		. override_failure_message("two bots stood %.1f m apart" % closest)
		. is_greater(5.0)
	)
	night.dispose()


# --- Follow ---


func test_under_follow_the_bots_stay_with_the_person_who_gave_the_order() -> void:
	var night := await _night(3)
	var walker := night.walkers[0]
	var home := Autopilot.HOME
	_place(night, PERSON, home)
	for id in [2, 3, 4]:
		_place(night, id, home + Vector3(float(id - 3) * 2.0, 0.0, 4.0))
	# Roaming first, so they have gone their own way before the order is given.
	night.run(60 * 25)
	_give(night, BotOrders.FOLLOW, _where(night, PERSON))
	assert_str(str(BotOrders.current(night.frame, 3)["order"])).is_equal("follow")
	# The person walks a loop of the field and the bots come with them.
	var route: Array[Vector3] = [
		home + Vector3(8.0, 0.0, -6.0),
		home + Vector3(-8.0, 0.0, -10.0),
		home + Vector3(0.0, 0.0, 4.0)
	]
	walker.goto(route[0])
	var near := 0
	var total := 0
	for t in 60 * 70:
		night.tick()
		if walker.arrived():
			walker.goto(route[(t / 600) % route.size()])
		if t < 60 * 15:
			continue
		for id in [2, 3, 4]:
			total += 1
			if _flat(_where(night, id), _where(night, PERSON)) <= FOLLOW_NEAR:
				near += 1
	var share := float(near) / float(total)
	(
		assert_float(share)
		. override_failure_message("within %d m: %.2f" % [FOLLOW_NEAR, share])
		. is_greater(0.9)
	)
	night.dispose()


func test_a_follow_whose_person_has_gone_is_a_roam() -> void:
	var night := await _night(2)
	_place(night, PERSON, Autopilot.HOME)
	_give(night, BotOrders.FOLLOW, Autopilot.HOME)
	night.run(60 * 10)
	night.walkers.clear()
	night.host.hear(night.server.apply({"type": NightServer.LEAVE, "player_id": PERSON}))
	night.run(60 * 40)
	for id in [2, 3]:
		assert_str(str(BotOrders.current(night.frame, id)["order"])).is_equal("follow")
		assert_str(_bot(night, id).intent.note).is_not_equal("follow")
	night.dispose()


# --- Hold ---


func test_under_hold_the_bots_stand_within_three_metres_of_the_spot_even_when_the_person_leaves(
) -> void:
	var night := await _night(3)
	var walker := night.walkers[0]
	var home := Autopilot.HOME
	var spot := home + Vector3(0.0, 0.0, 2.0)
	_place(night, PERSON, spot)
	for id in [2, 3, 4]:
		_place(night, id, home + Vector3(float(id - 3) * 6.0, 0.0, 14.0))
	_give(night, BotOrders.HOLD, spot)
	var held: Vector3 = BotOrders.current(night.frame, 2)["at"]
	assert_float(_flat(held, spot)).is_less(1.0)
	# They walk to it...
	night.run(60 * 25)
	# ...and then, with the person walking away, they stay.
	walker.goto(home + Vector3(-12.0, 0.0, -14.0))
	var seen := _watch(night, 40.0, [2, 3, 4], held)
	assert_float(_flat(_where(night, PERSON), held)).is_greater(10.0)
	for id in [2, 3, 4]:
		var report: Dictionary = seen[id]
		var kept := float(report["held"]) / float(report["ticks"])
		(
			assert_float(kept)
			. override_failure_message(
				(
					"bot %d within %d m of the spot %.3f of the time, at most %.1f away"
					% [id, HOLD_RADIUS, kept, report["spot"]]
				)
			)
			. is_greater(HOLD_SHARE)
		)
	night.dispose()


# --- A downed person pulls a bot in every order, and it goes back ---


func _revive_pull(order: StringName) -> void:
	var night := await _night(2)
	var walker := night.walkers[0]
	var home := Autopilot.HOME
	var spot := home + Vector3(0.0, 0.0, 6.0)
	_place(night, PERSON, spot)
	_place(night, 2, spot + Vector3(2.0, 0.0, 2.0))
	_place(night, 3, spot + Vector3(-2.0, 0.0, 2.0))
	_give(night, order, spot)
	night.run(60 * 15)
	# The person walks off and is struck down there.
	var body := home + Vector3(0.0, 0.0, -16.0)
	walker.goto(body)
	for _i in 60 * 20:
		night.tick()
		if walker.arrived():
			break
	_down(night, PERSON)
	walker.stop()
	var raised := -1.0
	for t in 60 * 40:
		night.tick()
		if not night.server.rules.players[PERSON].downed:
			raised = float(t) / TICKS_PER_SECOND
			break
	(
		assert_float(raised)
		. override_failure_message("%s: nobody raised the person" % order)
		. is_greater(0.0)
	)
	# Afterwards a bot is back at its order.
	night.run(60 * 40)
	var back := 0
	for id in [2, 3]:
		var here := _where(night, id)
		match order:
			BotOrders.HOLD:
				back += 1 if _flat(here, spot) < HOLD_RADIUS else 0
			BotOrders.FOLLOW:
				back += 1 if _flat(here, _where(night, PERSON)) <= FOLLOW_NEAR else 0
			_:
				back += 1 if _flat(here, _where(night, PERSON)) > 6.0 else 0
	(
		assert_int(back)
		. override_failure_message("%s: only %d bots went back" % [order, back])
		. is_greater(0)
	)
	night.dispose()


func test_a_downed_person_pulls_a_roaming_bot_and_it_goes_about_its_own_business_after() -> void:
	await _revive_pull(BotOrders.ROAM)


func test_a_downed_person_pulls_a_following_bot_and_it_follows_again() -> void:
	await _revive_pull(BotOrders.FOLLOW)


func test_a_downed_person_pulls_a_holding_bot_and_it_goes_back_to_the_spot() -> void:
	await _revive_pull(BotOrders.HOLD)


# --- A ping pulls a bot in every order, and it goes back ---


## A break that does not end, so a bot walks and shops with no zombie about.
func _long_break() -> RulesTuning:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = QUIET
	tuning.rounds.break_seconds = QUIET
	return tuning


## The person pings a shut door that only an order would have the bot buy (it holds the price and
## saves for the re-cut): the bot goes and buys it, and then takes up its order again.
func _ping_pull(order: StringName) -> void:
	var night := await NightFixture.seat(self, 2, _long_break(), SEED, true)
	night.human(PERSON)
	night.seat(2, BotProfile.regular(), SEED + 2)
	for door in [&"door_concession", &"door_booth", &"door_back_lot"]:
		night.open_door(door)
	await night.settle(60)
	_catcher.start()
	night.server.rules.players[PERSON].points = 100
	night.server.rules.players[2].points = 520
	var home := Autopilot.HOME
	var spot := home + Vector3(0.0, 0.0, 2.0)
	_place(night, PERSON, spot)
	_place(night, 2, spot + Vector3(1.0, 0.0, 1.0))
	_give(night, order, spot)
	night.run(60 * 10)
	var door := &"door_yard"
	assert_bool(night.server.rules.is_door_open(door)).is_false()
	var index := night.world.door_ids().find(door)
	var at: Vector3 = night.level.shop.door_stands[door][0]
	(
		assert_str(
			String(night.server.ping(PERSON, {"kind": &"door", "pos": at, "subject": index}))
		)
		. is_equal("")
	)
	var bought := -1.0
	for t in 60 * 90:
		night.tick()
		if night.server.rules.is_door_open(door):
			bought = float(t) / TICKS_PER_SECOND
			break
	(
		assert_float(bought)
		. override_failure_message("%s: the pinged door was not bought" % order)
		. is_greater(0.0)
	)
	night.run(60 * 40)
	var here := _where(night, 2)
	match order:
		BotOrders.HOLD:
			(
				assert_float(_flat(here, spot))
				. override_failure_message("hold: %.1f m from the spot" % _flat(here, spot))
				. is_less(HOLD_RADIUS)
			)
		BotOrders.FOLLOW:
			(
				assert_float(_flat(here, _where(night, PERSON)))
				. override_failure_message(
					"follow: %.1f m from the person" % _flat(here, _where(night, PERSON))
				)
				. is_less(FOLLOW_NEAR)
			)
		_:
			(
				assert_float(_flat(here, at))
				. override_failure_message("roam: still %.1f m from the door" % _flat(here, at))
				. is_greater(3.0)
			)
	assert_array(_catcher.lines).is_empty()
	night.dispose()


func test_a_ping_pulls_a_roaming_bot_to_the_door_and_it_goes_on_roaming() -> void:
	await _ping_pull(BotOrders.ROAM)


func test_a_ping_pulls_a_following_bot_to_the_door_and_it_follows_again() -> void:
	await _ping_pull(BotOrders.FOLLOW)


func test_a_ping_pulls_a_holding_bot_to_the_door_and_it_goes_back_to_the_spot() -> void:
	await _ping_pull(BotOrders.HOLD)


# --- The fight goes on under every order ---


## A night with one zombie to a round and one bot, the person at seat 1; the zombie is dropped
## `ahead` metres in front of the bot, in the bot's view (it faces -z), and walks at it.
func _fight_night(order: StringName) -> Dictionary:
	var night := await NightFixture.seat(self, 2, SeatedNight.one_a_round(), SEED)
	night.human(PERSON)
	night.seat(2, BotProfile.regular(), SEED + 2)
	await night.settle(12)
	_catcher.start()
	var spot := Autopilot.HOME + Vector3(0.0, 0.0, 2.0)
	_place(night, PERSON, spot + Vector3(0.0, 0.0, 6.0))
	_place(night, 2, spot)
	_give(night, order, spot)
	night.run(60 * 8)
	night.start_round()
	var zombie := night.drop_zombie(spot + Vector3(0.0, 0.0, -14.0), 1.0)
	var farthest := 0.0
	var died := false
	for _t in 60 * 40:
		night.tick()
		farthest = maxf(farthest, _flat(_where(night, 2), spot))
		if night.server.sim.zombies.is_empty() or zombie.mode == ZombieBody.Mode.DYING:
			died = true
			break
	return {"night": night, "died": died, "farthest": farthest, "spot": spot}


func test_a_holding_bot_shoots_what_comes_and_stays_at_the_spot() -> void:
	var fought := await _fight_night(BotOrders.HOLD)
	assert_bool(fought["died"]).override_failure_message("the zombie was not shot").is_true()
	(
		assert_float(fought["farthest"])
		. override_failure_message("went %.1f m from the spot" % fought["farthest"])
		. is_less(HOLD_RADIUS)
	)
	(fought["night"] as SeatedNight).dispose()


func test_a_roaming_bot_shoots_what_comes_and_goes_on_roaming() -> void:
	var fought := await _fight_night(BotOrders.ROAM)
	assert_bool(fought["died"]).override_failure_message("the zombie was not shot").is_true()
	var night: SeatedNight = fought["night"]
	night.run(60 * 40)
	(
		assert_float(_flat(_where(night, 2), fought["spot"]))
		. override_failure_message("the bot is still at the place of the fight")
		. is_greater(6.0)
	)
	night.dispose()


# --- A "hold here" ping pulls a bot in every order, and it goes back (#229's reply) ---


func _here_ping(order: StringName) -> void:
	var night := await _night(2)
	var spot := Autopilot.HOME + Vector3(0.0, 0.0, 2.0)
	var marked := Autopilot.HOME + Vector3(-14.0, 0.0, -12.0)
	_place(night, PERSON, spot)
	_place(night, 2, spot + Vector3(1.5, 0.0, 0.0))
	_place(night, 3, spot + Vector3(-1.5, 0.0, 0.0))
	_give(night, order, spot)
	night.run(60 * 15)
	var answer := night.server.ping(PERSON, {"kind": &"here", "pos": marked, "subject": 0})
	assert_str(String(answer)).is_equal("")
	var near := -1.0
	for t in 60 * 30:
		night.tick()
		for id in [2, 3]:
			if _flat(_where(night, id), marked) < 3.5:
				near = float(t) / TICKS_PER_SECOND
		if near >= 0.0:
			break
	assert_float(near).override_failure_message("%s: no bot went to the ping" % order).is_greater(
		0.0
	)
	# The mark runs out and the bot takes up its order again.
	night.run(60 * 45)
	var back := 0
	for id in [2, 3]:
		var here := _where(night, id)
		match order:
			BotOrders.HOLD:
				back += 1 if _flat(here, spot) < HOLD_RADIUS else 0
			BotOrders.FOLLOW:
				back += 1 if _flat(here, _where(night, PERSON)) <= FOLLOW_NEAR else 0
			_:
				back += 1 if _flat(here, marked) > 3.5 else 0
	assert_int(back).override_failure_message("%s: only %d went back" % [order, back]).is_greater(0)
	night.dispose()


func test_a_here_ping_pulls_a_roaming_bot_and_it_roams_on() -> void:
	await _here_ping(BotOrders.ROAM)


func test_a_here_ping_pulls_a_following_bot_and_it_follows_again() -> void:
	await _here_ping(BotOrders.FOLLOW)


func test_a_here_ping_pulls_a_holding_bot_and_it_goes_back_to_the_spot() -> void:
	await _here_ping(BotOrders.HOLD)
