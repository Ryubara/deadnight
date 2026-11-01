# The HUD over a night driven by hand: what the player stands at, what a blow does and what a shot
# costs reach the HUD only through the events the client hears (`NightHudBinding`).
extends GdUnitTestSuite

const DOOR := &"door_concession"
const PRICE := 350


func _start() -> Dictionary:
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	add_child(hud)
	var night := await NightFixture.start(self, Night.Mode.MANUAL, null, 7, hud)
	NightFixture.run(night, 30)
	return {"night": night, "hud": hud}


## A rules action from outside the server's own tick, its events delivered as the link would.
func _act(night: Night, action: Dictionary) -> void:
	night.state.apply_events(night.server.rules.apply(action))


func _finish(night: Night, hud: Hud) -> void:
	night.queue_free()
	hud.queue_free()


func test_the_prompt_names_the_door_and_its_price_and_goes_when_the_player_leaves() -> void:
	var made := await _start()
	var night: Night = made["night"]
	var hud: Hud = made["hud"]
	assert_bool(hud.prompt.visible).is_false()
	night.player().teleport(night.world.door_points(DOOR)[0] + Vector3(0.0, 0.1, -2.0))
	_act(night, RulesAction.grant_points(1, 400))
	NightFixture.run(night, 3)
	assert_bool(hud.prompt.visible).is_true()
	assert_str(hud.prompt.title_text).is_equal("CONCESSION STAND")
	assert_str(hud.prompt.price_text).is_equal("%d POINTS" % PRICE)
	night.player().teleport(night.state.position() + Vector3(0.0, 0.0, 20.0))
	NightFixture.run(night, 3)
	assert_bool(hud.prompt.visible).is_false()
	_finish(night, hud)


func test_a_door_the_player_cannot_afford_shows_what_is_missing() -> void:
	var made := await _start()
	var night: Night = made["night"]
	var hud: Hud = made["hud"]
	night.player().teleport(night.world.door_points(DOOR)[0] + Vector3(0.0, 0.1, -2.0))
	NightFixture.run(night, 3)
	assert_str(hud.prompt.price_text).is_equal("NEED %d POINTS" % PRICE)
	_finish(night, hud)


func test_a_shot_and_a_reload_move_the_ammunition_card() -> void:
	var made := await _start()
	var night: Night = made["night"]
	var hud: Hud = made["hud"]
	var full: int = hud.state.ammo_magazine
	assert_int(full).is_greater(0)
	assert_str(hud.state.weapon_name).is_equal(WeaponCatalog.get_def(&"pistol").display_name)
	var target := night.state.position() + Vector3(0.0, 0.0, -8.0)
	NightFixture.run(night, 1, NightFixture.shoot_at(night, target))
	NightFixture.run(night, 2)
	assert_int(hud.state.ammo_magazine).is_equal(full - 1)
	var command := NightCommand.new()
	command.reload = true
	NightFixture.run(night, 1, command)
	NightFixture.run(night, 400)
	assert_int(hud.state.ammo_magazine).is_equal(full)
	_finish(night, hud)


func test_a_blow_lowers_health_and_the_arc_points_at_the_dead_one() -> void:
	var made := await _start()
	var night: Night = made["night"]
	var hud: Hud = made["hud"]
	var zombie_id := NightFixture.first_zombie(night)
	var body: ZombieBody = night.server.sim.zombies[zombie_id]
	for _i in 600:
		# On the player's right hand, facing the way the player faces (straight ahead is -z).
		body.position = night.state.position() + Vector3(0.8, 0.0, 0.0)
		night.tick()
		if not hud.damage.arcs.is_empty():
			break
	assert_float(hud.state.health).is_less(100.0)
	assert_float(hud.state.health).is_equal_approx(night.server.health_of(1), 0.01)
	assert_array(hud.damage.arcs).is_not_empty()
	assert_float(hud.damage.arcs[0]["angle"]).is_equal_approx(PI * 0.5, 0.3)
	_finish(night, hud)


func test_health_is_the_rules_and_reaches_the_hud_by_events_alone() -> void:
	var made := await _start()
	var night: Night = made["night"]
	var hud: Hud = made["hud"]
	NightFixture.first_zombie(night)
	# A blow from outside the server's tick: no frame is sent after it, only the rules' events.
	_act(night, RulesAction.blow(1, 30.0, 0.0))
	assert_float(night.server.rules.health_of(1)).is_equal(70.0)
	assert_float(hud.state.health).is_equal(70.0)
	assert_float(hud.state.max_health).is_equal(100.0)
	# The server mends it with the rules' clock, and the HUD follows each step.
	NightFixture.run(night, 60 * 8)
	assert_float(night.server.rules.health_of(1)).is_greater(70.0)
	assert_float(hud.state.health).is_equal_approx(night.server.health_of(1), 1.0)
	_finish(night, hud)


func test_going_down_shows_in_the_hud_and_getting_up_restores_the_bar() -> void:
	var made := await _start()
	var night: Night = made["night"]
	var hud: Hud = made["hud"]
	NightFixture.first_zombie(night)
	_act(night, RulesAction.blow(1, 500.0, 1.0))
	assert_bool(hud.state.is_local_downed()).is_true()
	assert_float(hud.state.health).is_equal(0.0)
	_act(night, RulesAction.set_downed(1, false))
	assert_bool(hud.state.is_local_downed()).is_false()
	assert_float(hud.state.health).is_equal(100.0)
	_finish(night, hud)


func test_the_round_and_the_party_come_from_the_rules_events() -> void:
	var made := await _start()
	var night: Night = made["night"]
	var hud: Hud = made["hud"]
	assert_int(hud.state.phase).is_equal(HudState.PHASE_BREAK)
	_act(night, RulesAction.skip_break())
	NightFixture.run(night, 2)
	assert_int(hud.state.round_number).is_equal(1)
	assert_str(hud.round_part.number_text).is_equal("01")
	assert_int(hud.state.zombies_left).is_greater(0)
	night.link.send({"type": NightServer.JOIN, "player_id": 2, "local": false})
	NightFixture.run(night, 2)
	assert_bool(hud.state.team.has(2)).is_true()
	assert_array(hud.team.shown).has_size(1)
	_finish(night, hud)
