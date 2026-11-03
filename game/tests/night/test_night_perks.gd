# The six perks in the real night (docs/design/perks.md): the machines offer and sell them through
# the same `use` as every shop prompt, and each effect is seen in what the server and the frame
# say: faster fire, a faster reload, three weapons, a faster revive and the shock a reload gives.
# Driven like a client, a tick of 1/60 s, nothing waits on the clock.
extends GdUnitTestSuite

const TICKS_PER_SECOND := 60

var _events: Array[Dictionary] = []


func _start(tuning: RulesTuning = null) -> Night:
	_events = []
	var night := await NightFixture.start(self, Night.Mode.MANUAL, tuning)
	night.state.event_received.connect(func(event: Dictionary) -> void: _events.append(event))
	NightFixture.run(night, 5)
	night.server.rules.apply(RulesAction.grant_points(1, 30000))
	NightFixture.run(night, 2)
	return night


func _count(type: StringName) -> int:
	return _events.filter(func(event: Dictionary) -> bool: return event["type"] == type).size()


func _first(type: StringName) -> Dictionary:
	for event in _events:
		if event["type"] == type:
			return event
	return {}


func _spot(night: Night, item: StringName) -> Vector3:
	for spot in night.world.shop_spots():
		if spot["shop_id"] == item:
			return spot["position"]
	return Vector3.INF


func _stand_at(night: Night, at: Vector3) -> Dictionary:
	night.player().teleport(at + Vector3(0.0, 0.1, 0.0))
	NightFixture.run(night, 3)
	return night.state.me()["prompt"]


func _press_use(night: Night) -> void:
	var command := NightCommand.new()
	command.use = true
	NightFixture.run(night, 1, command)
	NightFixture.run(night, 3)


## A press of reload, and the ticks it takes to reach the server and answer.
func _reload(night: Night) -> void:
	var command := NightCommand.new()
	command.reload = true
	NightFixture.run(night, 1, command)
	NightFixture.run(night, 3)


func _buy(night: Night, item: StringName) -> void:
	night.server.buy(1, item)
	NightFixture.run(night, 2)


func test_every_machine_offers_its_perk_with_name_price_and_effect_and_a_press_buys_it() -> void:
	var night := await _start()
	var rules := night.server.rules
	for item: ShopItem in rules.tuning.economy.items:
		if item.kind != ShopItem.Kind.TONIC:
			continue
		var prompt := _stand_at(night, _spot(night, item.id))
		(
			assert_str(String(prompt.get("kind", &"")))
			. override_failure_message(String(item.id))
			. is_equal("tonic")
		)
		assert_str(String(prompt["name"])).is_equal(item.display_name)
		assert_int(prompt["price"]).is_equal(rules.price_of(item.id, 1))
		assert_int(prompt["effect"]).is_equal(item.effect)
		var before := night.state.points()
		_press_use(night)
		assert_int(night.state.points()).is_equal(before - prompt["price"])
		assert_bool(rules.players[1].tonics.has(item.id)).is_true()
		# The next prompt there says it was had.
		assert_str(String(night.state.me()["prompt"]["kind"])).is_equal("tonic_owned")
		# And the frame carries it for the HUD and the bots.
		(
			assert_bool(
				PerkEffects.mask_has(rules.tuning.economy, night.state.me()["perks"], item.id)
			)
			. is_true()
		)
		# Make room for the next machine: the limit is the rules'.
		rules.players[1].tonics.erase(item.id)
		NightFixture.run(night, 2)
	night.queue_free()


func test_a_player_at_the_limit_is_told_so_and_charged_nothing() -> void:
	var night := await _start()
	var rules := night.server.rules
	var ids := PerkEffects.tonic_ids(rules.tuning.economy)
	for i in rules.tuning.economy.max_tonics:
		_buy(night, ids[i])
	var extra := ids[rules.tuning.economy.max_tonics]
	var prompt := _stand_at(night, _spot(night, extra))
	assert_str(String(prompt["kind"])).is_equal("tonic_full")
	var before := night.state.points()
	_press_use(night)
	assert_int(night.state.points()).is_equal(before)
	night.queue_free()


func test_faster_fire_shoots_more_often_through_the_real_trigger() -> void:
	var night := await _start()
	var target := night.state.position() + Vector3(0.0, 0.0, -20.0)
	var shots := {}
	for round in 2:
		if round == 1:
			_buy(night, &"tonic_double_shot")
		var weapon := night.server.combat.weapon_of(1)
		weapon.ammo = 999
		_events.clear()
		NightFixture.run(night, 2 * TICKS_PER_SECOND, NightFixture.shoot_at(night, target))
		shots[round] = _count(&"shot_fired")
	assert_int(shots[0]).is_greater(2)
	# The server shoots on whole ticks, so the 1.33 of the tuning shows as a little under it.
	assert_float(float(shots[1]) / float(shots[0])).is_greater(1.2)
	night.queue_free()


func test_faster_reload_finishes_in_half_the_time() -> void:
	var night := await _start()
	_buy(night, &"tonic_quick_load")
	var weapon := night.server.combat.weapon_of(1)
	weapon.ammo = 1
	_events.clear()
	_reload(night)
	var started := _first(&"reload_started")
	assert_float(started["seconds"]).is_equal_approx(
		weapon.def.reload_time * night.server.rules.tuning.perks.reload_time_scale, 0.001
	)
	NightFixture.run(night, int(started["seconds"] * TICKS_PER_SECOND) + 4)
	assert_int(_count(&"reload_finished")).is_equal(1)
	night.queue_free()


func test_a_third_weapon_is_kept_with_the_perk_and_lost_with_a_down() -> void:
	var night := await _start()
	_buy(night, &"tonic_third_holster")
	_buy(night, &"weapon_shotgun")
	_buy(night, &"weapon_rifle")
	assert_array(night.server.combat.carried(1)).has_size(3)
	assert_int(night.state.me()["arms"].size()).is_equal(3)
	night.server.rules.apply(RulesAction.skip_break())
	night.state.apply_events(night.server.rules.apply(RulesAction.blow(1, 9999.0)))
	NightFixture.run(night, 3)
	assert_array(night.server.combat.carried(1)).has_size(2)
	assert_int(night.state.me()["arms"].size()).is_equal(2)
	assert_int(night.state.me()["perks"]).is_equal(0)
	night.queue_free()


func test_a_reviver_with_the_perk_raises_a_teammate_in_half_the_time() -> void:
	var tuning := RulesFixture.tuning()
	tuning.rounds.first_spawn_delay = 600.0
	var night := await _start(tuning)
	night.server.apply({"type": NightServer.JOIN, "player_id": 2, "local": false})
	night.server.rules.apply(RulesAction.skip_break())
	_buy(night, &"tonic_swift_rescue")
	var here := night.state.position()
	night.server.body_of(2).teleport(here + Vector3(1.0, 0.0, 0.0))
	NightFixture.run(night, 2)
	night.state.apply_events(night.server.rules.apply(RulesAction.blow(2, 500.0)))
	NightFixture.run(night, 2)
	var seconds := night.server.rules.tuning.health.revive_seconds
	var hold := NightCommand.new()
	hold.use_held = true
	# With the perk half the plain time is enough: 40% is not yet, 65% is.
	NightFixture.run(night, int(seconds * 0.4 * TICKS_PER_SECOND), hold)
	assert_bool(night.server.rules.players[2].downed).is_true()
	NightFixture.run(night, int(seconds * 0.25 * TICKS_PER_SECOND), hold)
	assert_bool(night.server.rules.players[2].downed).is_false()
	night.queue_free()


func test_the_shock_hurts_and_holds_the_dead_in_reach_when_the_holder_reloads() -> void:
	var night := await _start()
	_buy(night, &"tonic_reload_shock")
	NightFixture.first_zombie(night)
	for _i in 1500:
		if night.server.sim.zombies.size() >= 2:
			break
		night.tick()
	assert_int(night.server.sim.zombies.size()).is_greater_equal(2)
	var ids: Array = night.server.sim.zombies.keys()
	var near: ZombieBody = night.server.sim.zombies[ids[0]]
	var far: ZombieBody = night.server.sim.zombies[ids[1]]
	var spec := night.server.rules.tuning.perks
	var here := night.state.position()
	near.position = here + Vector3(spec.shock_radius * 0.5, 0.0, 0.0)
	far.position = here + Vector3(spec.shock_radius * 2.0, 0.0, 0.0)
	var near_before := night.server.rules.zombie_health(ids[0])
	var far_before := night.server.rules.zombie_health(ids[1])
	night.server.combat.weapon_of(1).ammo = 1
	_events.clear()
	_reload(night)
	assert_int(_count(&"shock_burst")).is_equal(1)
	var burst := _first(&"shock_burst")
	assert_array(burst["hits"]).contains([ids[0]])
	assert_bool(burst["hits"].has(ids[1])).is_false()
	var hurt := (
		not night.server.rules.has_zombie(ids[0])
		or (night.server.rules.zombie_health(ids[0]) < near_before)
	)
	assert_bool(hurt).is_true()
	assert_float(night.server.rules.zombie_health(ids[1])).is_equal_approx(far_before, 3.0)
	night.queue_free()


func test_a_reload_cancelled_and_started_again_is_no_second_shock() -> void:
	var night := await _start()
	_buy(night, &"tonic_reload_shock")
	var weapon := night.server.combat.weapon_of(1)
	weapon.ammo = 1
	_events.clear()
	_reload(night)
	weapon.cancel_reload()
	_reload(night)
	assert_int(_count(&"shock_burst")).is_equal(1)
	# After the wait it shocks again.
	weapon.cancel_reload()
	var wait := night.server.rules.tuning.perks.shock_cooldown + 0.2
	NightFixture.run(night, int(wait * TICKS_PER_SECOND))
	weapon.ammo = 1
	_reload(night)
	assert_int(_count(&"shock_burst")).is_equal(2)
	night.queue_free()


func test_a_player_without_the_perk_gives_off_no_shock() -> void:
	var night := await _start()
	night.server.combat.weapon_of(1).ammo = 1
	_reload(night)
	assert_int(_count(&"shock_burst")).is_equal(0)
	night.queue_free()
