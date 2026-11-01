# The ammo card and the equipment slot come from the weapons' own events (#133): a real
# `CombatServer` is fired, reloaded and switched, and its events are all the HUD hears.
extends GdUnitTestSuite

const STEP := WeaponsFixture.STEP
const FROM := Vector3(0.0, 1.1, 8.0)
const TO := Vector3(0.0, 1.1, -8.0)

var _host: Control
var _fixture: HudFixture
var _server: CombatServer
var _seq := 0


func before_test() -> void:
	UIMotion.reduced = false
	_host = auto_free(Control.new())
	_host.size = Vector2(1920, 1080)
	add_child(_host)
	_fixture = HudFixture.make(_host)
	_fixture.into_round_one()
	_server = WeaponsFixture.make_server(_fixture.rules)
	for def in WeaponCatalog.all():
		_fixture.hud.state.weapon_names[def.id] = def.display_name
		if def.is_melee():
			_fixture.hud.state.ammo_free.append(def.id)


func after_test() -> void:
	_server.detach()


## Sends one combat action; the HUD hears the events the weapons' feed lets through.
func _do(action: Dictionary) -> Array[Dictionary]:
	var events := _server.apply(action)
	for event in events:
		if HudLoadout.EVENTS.has(event["type"]):
			_fixture.hud.state.apply_event(event)
	return events


func _give(weapon_id: StringName) -> void:
	_do(CombatAction.give_weapon(1, weapon_id))


func _fire() -> void:
	_seq += 1
	_do(WeaponsFixture.fire_at(1, _seq, FROM, TO))
	_do(CombatAction.tick(0.5))


func _ammo() -> HudAmmo:
	return _fixture.hud.ammo


func test_a_weapon_in_hand_names_itself_and_its_rounds_on_the_card() -> void:
	_give(&"pistol")
	var def := WeaponCatalog.get_def(&"pistol")
	var state := _fixture.hud.state
	assert_str(state.weapon_name).is_equal(def.display_name)
	assert_int(state.ammo_magazine).is_equal(def.magazine_size)
	assert_int(state.ammo_reserve).is_equal(def.reserve_start)
	assert_str(_ammo().magazine_text).is_equal(str(def.magazine_size))
	assert_str(_ammo().reserve_text).is_equal("/ %d" % def.reserve_start)


func test_each_shot_takes_a_round_off_the_magazine() -> void:
	_give(&"pistol")
	var full := _fixture.hud.state.ammo_magazine
	_fire()
	assert_int(_fixture.hud.state.ammo_magazine).is_equal(full - 1)
	assert_str(_ammo().magazine_text).is_equal(str(full - 1))
	_fire()
	_fire()
	assert_int(_fixture.hud.state.ammo_magazine).is_equal(full - 3)
	assert_int(_fixture.hud.state.ammo_magazine).is_equal(_server.weapon_of(1).ammo)


func test_a_dry_magazine_asks_for_a_reload_and_the_reload_shows_while_it_runs() -> void:
	_give(&"pistol")
	var def := WeaponCatalog.get_def(&"pistol")
	for _i in def.magazine_size:
		_fire()
	var state := _fixture.hud.state
	assert_int(state.ammo_magazine).is_equal(0)
	assert_str(_ammo().hint_text).is_equal("RELOAD")
	_do(CombatAction.reload_weapon(1))
	assert_bool(state.ammo_reloading).is_true()
	assert_str(_ammo().hint_text).is_equal("RELOADING")
	# The reload takes its time; the card is as it was until it finishes.
	_do(CombatAction.tick(def.reload_time * 0.5))
	assert_int(state.ammo_magazine).is_equal(0)
	_do(CombatAction.tick(def.reload_time))
	assert_bool(state.ammo_reloading).is_false()
	assert_int(state.ammo_magazine).is_equal(def.magazine_size)
	assert_int(state.ammo_reserve).is_equal(def.reserve_start - def.magazine_size)
	assert_str(_ammo().hint_text).is_equal("")


func test_switching_weapons_changes_the_card_and_puts_the_old_one_in_the_equipment_slot() -> void:
	var pistol := WeaponCatalog.get_def(&"pistol")
	var shotgun := WeaponCatalog.get_def(&"shotgun")
	_give(&"pistol")
	var state := _fixture.hud.state
	assert_str(state.equipment_name).is_equal("")
	_fire()
	_give(&"shotgun")
	assert_str(state.weapon_name).is_equal(shotgun.display_name)
	assert_int(state.ammo_magazine).is_equal(shotgun.magazine_size)
	var pistol_rounds := pistol.magazine_size - 1 + pistol.reserve_start
	# The slot names the weapon put away; its rounds stay in the state, off the card (the ammo card
	# says the rounds of the weapon in hand).
	assert_str(_fixture.hud.health.equipment_text).is_equal(pistol.display_name.to_upper())
	assert_int(state.equipment_count).is_equal(pistol_rounds)
	# Back to the first: the slot now holds the shotgun, and the pistol's rounds are as left.
	_do(CombatAction.equip(1, &"pistol"))
	assert_str(state.weapon_name).is_equal(pistol.display_name)
	assert_int(state.ammo_magazine).is_equal(pistol.magazine_size - 1)
	assert_str(state.equipment_name).is_equal(shotgun.display_name)
	assert_int(state.equipment_count).is_equal(shotgun.magazine_size + shotgun.reserve_start)


func test_a_weapon_put_away_mid_reload_does_not_stay_reloading() -> void:
	_give(&"pistol")
	_fire()
	_do(CombatAction.reload_weapon(1))
	assert_bool(_fixture.hud.state.ammo_reloading).is_true()
	_give(&"shotgun")
	assert_bool(_fixture.hud.state.ammo_reloading).is_false()
	assert_str(_ammo().hint_text).is_equal("")


func test_a_weapon_that_uses_no_ammunition_shows_no_numbers_and_no_count() -> void:
	_give(&"pistol")
	_give(&"crowbar")
	var state := _fixture.hud.state
	assert_bool(state.ammo_used).is_false()
	assert_str(_ammo().magazine_text).is_equal(HudAmmo.NO_AMMO_MARK)
	assert_str(_ammo().hint_text).is_equal("")
	assert_bool(_ammo().is_low).is_false()
	# Put the other way: the crowbar in the slot is named with no count.
	_do(CombatAction.equip(1, &"pistol"))
	assert_bool(state.ammo_used).is_true()
	assert_str(_fixture.hud.health.equipment_text).is_equal("CROWBAR")


func test_another_players_weapons_leave_my_card_alone() -> void:
	_give(&"pistol")
	var state := _fixture.hud.state
	state.apply_event(
		{"type": &"weapon_equipped", "player_id": 2, "weapon_id": &"rifle", "ammo": 3, "reserve": 4}
	)
	state.apply_event(
		{"type": &"shot_fired", "shooter_id": 2, "weapon_id": &"pistol", "ammo": 1, "reserve": 1}
	)
	assert_str(state.weapon_name).is_equal(WeaponCatalog.get_def(&"pistol").display_name)
	assert_int(state.ammo_magazine).is_equal(WeaponCatalog.get_def(&"pistol").magazine_size)


func test_the_card_reads_whatever_rounds_the_events_carry() -> void:
	# A reserve the shop can grow or run out: the HUD takes the events' numbers as they come.
	_give(&"pistol")
	var state := _fixture.hud.state
	state.apply_event(
		{
			"type": &"reload_finished",
			"shooter_id": 1,
			"weapon_id": &"pistol",
			"ammo": 7,
			"reserve": 0
		}
	)
	assert_int(state.ammo_magazine).is_equal(7)
	assert_int(state.ammo_reserve).is_equal(0)
	assert_str(_ammo().reserve_text).is_equal("/ 0")
	state.apply_event(
		{"type": &"shot_fired", "shooter_id": 1, "weapon_id": &"pistol", "ammo": 0, "reserve": 0}
	)
	assert_str(_ammo().hint_text).is_equal("NO AMMO")


func test_the_equipment_slot_names_the_weapon_and_shows_no_rounds() -> void:
	# The rounds of the weapon put away are the ammo card's business (the maintainer's call,
	# #218); the slot is the weapon's name, cut with an ellipsis only when it is too long.
	_give(&"pistol")
	_give(&"rifle")
	await get_tree().process_frame
	await get_tree().process_frame
	var label: Label = _fixture.hud.health._equipment
	assert_str(label.text).is_equal("REVOLVER")
	assert_str(label.text).not_contains(" x")
	var font := label.get_theme_font(&"font")
	assert_float(HudStyle.text_width(font, label.text, HudStyle.SMALL)).is_less_equal(label.size.x)
