# The perk drink in the real night (#912, docs/design/perks.md, "The drink"): a press of `use` at a
# machine buys the perk and the buyer's body drinks it (the clip, the bottle in the perk's colour);
# fire, reload, swap, the quick blow and `use` do nothing until it is down; the perk is had at the
# end; a blow meanwhile does not stop it and a down spills it; a bot's purchase shows its drink too.
# Driven like a client, a tick of 1/60 s, nothing waits on the clock.
extends GdUnitTestSuite

const TICKS_PER_SECOND := 60
const DRINK := 2.5

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


func _spot(night: Night, item: StringName) -> Vector3:
	for spot in night.world.shop_spots():
		if spot["shop_id"] == item:
			return spot["position"]
	return Vector3.INF


## Stands at the machine and presses `use` (a real press through the night's command).
func _buy_at_machine(night: Night, item: StringName) -> void:
	night.player().teleport(_spot(night, item) + Vector3(0.0, 0.1, 0.0))
	NightFixture.run(night, 3)
	var command := NightCommand.new()
	command.use = true
	NightFixture.run(night, 1, command)
	NightFixture.run(night, 3)


## Runs `ticks` ticks and steps the player's animation by each (a night driven by hand does not
## draw: the animation is stepped here as the frames would step it).
func _run(night: Night, ticks: int) -> void:
	for _i in ticks:
		NightFixture.run(night, 1)
		_animation(night)._process(1.0 / TICKS_PER_SECOND)


func _animation(night: Night) -> PlayerAnimation:
	return night.player().get_node("AnimationTree") as PlayerAnimation


## Holds the buttons `edit` sets for `ticks` ticks, each tick a fresh press.
func _hold(night: Night, ticks: int, edit: Callable) -> void:
	for _i in ticks:
		var command := NightCommand.new()
		command.aim_along(-night.player().global_basis.z)
		edit.call(command)
		NightFixture.run(night, 1, command)


func test_a_press_at_a_machine_starts_the_drink_and_the_perk_comes_at_its_end() -> void:
	var night := await _start()
	_buy_at_machine(night, &"tonic_double_shot")
	assert_int(_count(&"drink_started")).is_equal(1)
	assert_bool(night.server.is_drinking(1)).is_true()
	var animation := _animation(night)
	assert_bool(animation.is_drinking()).is_true()
	_run(night, 20)
	assert_bool(animation.bottle().visible).is_true()
	assert_object(animation.bottle().drink_colour()).is_equal(
		PerkBottle.colours_of(&"tonic_double_shot")["drink"]
	)
	assert_bool(PerkEffects.has(night.server.rules, 1, ShopItem.Effect.FIRE_RATE)).is_false()
	_run(night, int(DRINK * TICKS_PER_SECOND))
	assert_int(_count(&"drink_finished")).is_equal(1)
	assert_bool(night.server.is_drinking(1)).is_false()
	assert_bool(PerkEffects.has(night.server.rules, 1, ShopItem.Effect.FIRE_RATE)).is_true()
	assert_bool(animation.is_drinking()).is_false()
	assert_bool(animation.weapon().visible).is_true()
	night.queue_free()


func test_no_shot_reload_swap_or_blow_leaves_while_drinking() -> void:
	var night := await _start()
	_buy_at_machine(night, &"tonic_quick_load")
	var shots := _count(&"shot_fired")
	var reloads := _count(&"reload_started")
	var blows := _count(&"quick_melee")
	var equips := _count(&"weapon_equipped")
	_hold(
		night,
		int((DRINK - 0.3) * TICKS_PER_SECOND),
		func(command: NightCommand) -> void:
			command.fire = true
			command.reload = true
			command.swap = true
			command.motion.melee = true
	)
	assert_bool(night.server.is_drinking(1)).is_true()
	assert_int(_count(&"shot_fired")).is_equal(shots)
	assert_int(_count(&"reload_started")).is_equal(reloads)
	assert_int(_count(&"quick_melee")).is_equal(blows)
	assert_int(_count(&"weapon_equipped")).is_equal(equips)
	# Once it is down the trigger works again.
	NightFixture.run(night, 30)
	_hold(night, 20, func(command: NightCommand) -> void: command.fire = true)
	assert_int(_count(&"shot_fired")).is_greater(shots)
	night.queue_free()


func test_a_blow_does_not_stop_the_drink_and_a_down_spills_it() -> void:
	var night := await _start()
	var rules := night.server.rules
	rules.apply(RulesAction.skip_break())  # a blow lands in a round only
	NightFixture.run(night, 2)
	_buy_at_machine(night, &"tonic_reload_shock")
	NightFixture.run(night, 30)
	# A blow from outside the server's step reaches the client the way the step's own would.
	night.link.broadcast(rules.apply(RulesAction.blow(1, 20.0)))
	NightFixture.run(night, 2)
	assert_bool(night.server.is_drinking(1)).is_true()
	assert_bool(_animation(night).is_drinking()).is_true()
	night.link.broadcast(rules.apply(RulesAction.blow(1, 9999.0)))
	_run(night, 3)
	assert_int(_count(&"drink_spilled")).is_equal(1)
	assert_bool(_animation(night).is_drinking()).is_false()
	assert_bool(_animation(night).bottle().visible).is_false()
	NightFixture.run(night, int(DRINK * TICKS_PER_SECOND))
	assert_int(_count(&"drink_finished")).is_equal(0)
	assert_bool(rules.players[1].tonics.has(&"tonic_reload_shock")).is_false()
	night.queue_free()


func test_another_players_drink_shows_on_their_body() -> void:
	# A bot (or a teammate) buys: its drawn body drinks, from the same event every client hears.
	var night := await _start()
	var other := night.world.add_body(night.world.player_spawn(1), false)
	var drawn: Dictionary[int, Node3D] = {1: night.player(), 2: other}
	night.view.bodies = func(player_id: int) -> Node3D: return drawn.get(player_id)
	night.view.draw_event(
		{
			"type": &"drink_started",
			"player_id": 2,
			"item_id": &"tonic_swift_rescue",
			"seconds": DRINK
		}
	)
	var theirs := other.get_node("AnimationTree") as PlayerAnimation
	assert_bool(theirs.is_drinking()).is_true()
	assert_bool(_animation(night).is_drinking()).is_false()
	night.view.draw_event(
		{"type": &"drink_spilled", "player_id": 2, "item_id": &"tonic_swift_rescue"}
	)
	assert_bool(theirs.is_drinking()).is_false()
	night.queue_free()


func test_a_bots_purchase_is_drunk_on_its_body_in_the_night() -> void:
	var night := Night.new()
	night.match_settings = MatchSettings.new()
	night.match_settings.bots = 1
	add_child(night)
	await night.start(Night.Mode.MANUAL, 7)
	NightFixture.run(night, 5)
	var bot_id := -1
	for id: int in night.server.rules.players:
		if (night.server.rules.players[id] as PlayerState).bot:
			bot_id = id
	assert_int(bot_id).is_greater(1)
	night.server.rules.apply(RulesAction.grant_points(bot_id, 30000))
	# What the server answers a bot goes to the client as a bot's answer does (`Night._bots_answered`).
	night.link.broadcast(night.server.buy(bot_id, &"tonic_third_holster"))
	NightFixture.run(night, 3)
	assert_bool(night.server.is_drinking(bot_id)).is_true()
	var body: Node3D = night.view.bodies.call(bot_id)
	assert_object(body).override_failure_message("the bot has no drawn body").is_not_null()
	var animation := body.get_node("AnimationTree") as PlayerAnimation
	assert_bool(animation.is_drinking()).is_true()
	night.queue_free()
