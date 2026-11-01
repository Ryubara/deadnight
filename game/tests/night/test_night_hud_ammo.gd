# The HUD's ammo card and equipment slot follow the rounds the server holds, whatever changed them:
# a locker, a wall buy of a weapon already carried, a pickup that sends no event of its own, a
# reload. The bug (maintainer, 2026-11-01): the card was fed by equip, shot and reload events only,
# so rounds bought for the weapon in hand showed after the next weapon swap and not before.
extends GdUnitTestSuite

const LOW := 5


func _start() -> Dictionary:
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	add_child(hud)
	var night := await NightFixture.start(self, Night.Mode.MANUAL, null, 7, hud)
	NightFixture.run(night, 30)
	night.server.rules.apply(RulesAction.grant_points(1, 9000))
	NightFixture.run(night, 2)
	return {"night": night, "hud": hud}


func _finish(night: Night, hud: Hud) -> void:
	night.queue_free()
	hud.queue_free()


## A weapon the player has fired down to `left` rounds in reserve, as the HUD would have heard it:
## the server's number is set, and the weapon taken in hand again so its event carries the count.
func _run_low(night: Night, weapon: StringName, left: int = LOW) -> void:
	night.server.combat.state_of(1, weapon).reserve = left
	night.state.apply_events(night.server.combat.apply(CombatAction.equip(1, weapon)))
	NightFixture.run(night, 2)


func _stand_at(night: Night, shop_id: StringName, kind: StringName) -> void:
	for spot in night.world.shop_spots():
		if (shop_id == &"" or spot["shop_id"] == shop_id) and spot["kind"] == kind:
			night.player().teleport(spot["position"] + Vector3(0.0, 0.1, 0.0))
			break
	NightFixture.run(night, 3)


func _use(night: Night) -> void:
	var command := NightCommand.new()
	command.use = true
	NightFixture.run(night, 1, command)
	NightFixture.run(night, 2)


func test_ammo_bought_at_a_locker_shows_in_the_card_without_a_swap() -> void:
	var made := await _start()
	var night: Night = made["night"]
	var hud: Hud = made["hud"]
	_run_low(night, &"pistol")
	assert_int(hud.state.ammo_reserve).is_equal(LOW)
	_stand_at(night, &"", &"ammo")
	assert_str(String(hud.state.prompt["kind"])).is_equal("buy_ammo")
	_use(night)
	var reserve := night.server.combat.state_of(1, &"pistol").reserve
	assert_int(reserve).is_greater(LOW)
	assert_int(hud.state.ammo_reserve).is_equal(reserve)
	assert_str(hud.ammo.reserve_text).is_equal("/ %d" % reserve)
	_finish(night, hud)


func test_ammo_bought_at_the_wall_for_the_weapon_in_hand_shows_in_the_card() -> void:
	var made := await _start()
	var night: Night = made["night"]
	var hud: Hud = made["hud"]
	night.server.buy(1, &"weapon_shotgun")
	NightFixture.run(night, 3)
	_run_low(night, &"shotgun", 2)
	assert_int(hud.state.ammo_reserve).is_equal(2)
	_stand_at(night, &"weapon_shotgun", &"wall")
	assert_str(String(hud.state.prompt["kind"])).is_equal("buy_ammo")
	_use(night)
	var reserve := night.server.combat.state_of(1, &"shotgun").reserve
	assert_int(reserve).is_greater(2)
	assert_int(hud.state.ammo_reserve).is_equal(reserve)
	_finish(night, hud)


func test_ammo_for_the_weapon_put_away_reaches_the_equipment_slot() -> void:
	var made := await _start()
	var night: Night = made["night"]
	var hud: Hud = made["hud"]
	night.server.buy(1, &"weapon_shotgun")
	NightFixture.run(night, 3)
	night.server.buy(1, &"weapon_rifle")
	NightFixture.run(night, 3)
	_run_low(night, &"shotgun", 2)
	_run_low(night, &"rifle")
	var shotgun := night.server.combat.state_of(1, &"shotgun")
	assert_str(hud.state.weapon_name).is_equal(WeaponCatalog.get_def(&"rifle").display_name)
	assert_int(hud.state.equipment_count).is_equal(shotgun.ammo + 2)
	_stand_at(night, &"weapon_shotgun", &"wall")
	_use(night)
	assert_int(shotgun.reserve).is_greater(2)
	assert_int(hud.state.equipment_count).is_equal(shotgun.ammo + shotgun.reserve)
	# The card still shows the rifle in hand.
	assert_int(hud.state.ammo_reserve).is_equal(night.server.combat.state_of(1, &"rifle").reserve)
	_finish(night, hud)


func test_rounds_added_with_no_event_of_their_own_show_on_the_next_frame() -> void:
	var made := await _start()
	var night: Night = made["night"]
	var hud: Hud = made["hud"]
	_run_low(night, &"pistol")
	# A pickup or a power-up that changes the weapon and says nothing: the frame carries it.
	night.server.combat.state_of(1, &"pistol").add_reserve(20)
	# The server's next step builds the frame; the link delivers it on the tick after.
	NightFixture.run(night, 2)
	assert_int(hud.state.ammo_reserve).is_equal(LOW + 20)
	_finish(night, hud)


func test_an_ammo_added_event_moves_the_card_the_moment_it_is_heard() -> void:
	var made := await _start()
	var night: Night = made["night"]
	var hud: Hud = made["hud"]
	_run_low(night, &"pistol")
	# No frame in between: only the weapons' event.
	night.state.apply_events(night.server.combat.apply(CombatAction.add_ammo(1, &"pistol", 12)))
	assert_int(hud.state.ammo_reserve).is_equal(LOW + 12)
	_finish(night, hud)


func test_another_players_ammo_leaves_your_card_alone() -> void:
	var made := await _start()
	var night: Night = made["night"]
	var hud: Hud = made["hud"]
	_run_low(night, &"pistol")
	(
		night
		. state
		. apply_events(
			[
				{
					"type": &"ammo_added",
					"player_id": 2,
					"weapon_id": &"pistol",
					"added": 30,
					"ammo": 8,
					"reserve": 90,
				}
			]
		)
	)
	assert_int(hud.state.ammo_reserve).is_equal(LOW)
	_finish(night, hud)


func test_the_card_is_the_latest_frame_on_every_tick_of_shots_a_reload_and_a_buy() -> void:
	var made := await _start()
	var night: Night = made["night"]
	var hud: Hud = made["hud"]
	var target := night.state.position() + Vector3(0.0, 0.0, -8.0)
	var reload := NightCommand.new()
	reload.reload = true
	var held := night.server.combat.weapon_of(1)
	for step in 3:
		NightFixture.run(night, 1, NightFixture.shoot_at(night, target))
		NightFixture.run(night, 20)
		_assert_card_is_the_frame(night, hud)
	NightFixture.run(night, 1, reload)
	var seen_reloading := false
	for _i in 300:
		NightFixture.run(night, 1)
		_assert_card_is_the_frame(night, hud)
		seen_reloading = seen_reloading or hud.state.ammo_reloading
	assert_bool(seen_reloading).is_true()
	assert_bool(hud.state.ammo_reloading).is_false()
	night.server.buy(1, &"ammo_pistol")
	NightFixture.run(night, 2)
	_assert_card_is_the_frame(night, hud)
	assert_int(hud.state.ammo_reserve).is_equal(held.reserve)
	_finish(night, hud)


## The card shows the local player's entry of the latest frame: the rounds the server held then.
func _assert_card_is_the_frame(night: Night, hud: Hud) -> void:
	var me := night.state.me()
	assert_int(hud.state.ammo_magazine).is_equal(me["ammo"])
	assert_int(hud.state.ammo_reserve).is_equal(me["reserve"])
	assert_bool(hud.state.ammo_reloading).is_equal(me["reloading"])
