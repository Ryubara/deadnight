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


func _stand_at(night: Night, shop_id: StringName, kind: StringName = &"") -> void:
	for spot in night.world.shop_spots():
		if (shop_id == &"" or spot["shop_id"] == shop_id) and (kind == &"" or spot["kind"] == kind):
			night.player().teleport(spot["position"] + Vector3(0.0, 0.1, 0.0))
	NightFixture.run(night, 3)


func test_the_wall_weapon_the_crane_and_a_locker_each_have_a_card() -> void:
	var made := await _start()
	var night: Night = made["night"]
	var hud: Hud = made["hud"]
	_stand_at(night, &"weapon_shotgun")
	assert_str(String(hud.state.prompt["kind"])).is_equal("buy_weapon")
	assert_str(hud.prompt.title_text).contains("SHOTGUN")
	_stand_at(night, &"crane_play")
	assert_str(String(hud.state.prompt["kind"])).is_equal("buy_crane")
	assert_str(hud.prompt.title_text).is_equal("PRIZE CRANE")
	night.server.combat.state_of(1, &"pistol").reserve = 0
	_stand_at(night, &"", &"ammo")
	assert_str(String(hud.state.prompt["kind"])).is_equal("buy_ammo")
	assert_str(hud.prompt.title_text).contains("ROUNDS")
	assert_str(hud.prompt.detail_text).contains("ROUNDS FOR YOUR RESERVE")
	_finish(night, hud)
