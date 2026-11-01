# The weapon in the Soldier's hand follows the weapon the server says he holds (docs/design/
# weapon-hold.md, "Which weapon is which"): every id of the catalogue, equipped through the real
# combat action, shows its class, its hold and its model on the player view, for the local
# player and for another one.
extends GdUnitTestSuite

const OTHER_ID := 2
## Per weapon: the class it is held as and the model scene its hold names ("" = none yet).
const EXPECTED := {
	&"rifle": [&"Rifle", "res://assets/weapons/lever_rifle/lever_rifle.glb"],
	&"shotgun": [&"Shotgun", "res://assets/weapons/double_shotgun/double_shotgun.glb"],
	&"crowbar": [&"Melee", "res://assets/weapons/baseball_bat/baseball_bat.glb"],
	&"smg": [&"Rifle", "res://assets/weapons/lever_rifle/lever_rifle.glb"],
	&"pistol": [&"Pistol", ""],
	&"flare_gun": [&"Pistol", ""],
}


func _start() -> Night:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 3)
	return night


func _animation(body: Player) -> PlayerAnimation:
	return body.get_node("AnimationTree") as PlayerAnimation


## Takes a weapon in hand the way the game does (the combat server answers `weapon_equipped`),
## then lets the frames carry it to the view.
func _equip(night: Night, player_id: int, weapon_id: StringName) -> void:
	night.server.combat.apply(CombatAction.give_weapon(player_id, weapon_id))
	night.server.combat.apply(CombatAction.equip(player_id, weapon_id))
	NightFixture.run(night, 3)


func _check(body: Player, weapon_id: StringName) -> void:
	var animation := _animation(body)
	var expected: Array = EXPECTED[weapon_id]
	(
		assert_str(String(animation.weapon_class))
		. override_failure_message("%s: class" % weapon_id)
		. is_equal(String(expected[0]))
	)
	var model: String = expected[1]
	if model == "":
		(
			assert_object(animation.weapon())
			. override_failure_message("%s: no model yet" % weapon_id)
			. is_null()
		)
		assert_object(animation.weapon_hold()).is_null()
		return
	(
		assert_object(animation.weapon())
		. override_failure_message("%s: a model" % weapon_id)
		. is_not_null()
	)
	assert_str(animation.weapon().scene_file_path).is_equal(model)
	assert_str(animation.weapon_hold().scene).is_equal(model)
	assert_str(String(animation.weapon_hold().weapon_class)).is_equal(String(expected[0]))


func test_the_table_covers_the_whole_catalogue() -> void:
	assert_array(EXPECTED.keys()).contains_exactly_in_any_order(WeaponCatalog.IDS)
	for id in WeaponCatalog.IDS:
		var weapon_class := WeaponHoldMap.class_of(id)
		assert_bool(weapon_class in PlayerAnimation.CLASSES).is_true()
		assert_str(String(weapon_class)).is_equal(String(EXPECTED[id][0]))


func test_every_weapon_off_the_list_has_a_hold_of_its_own_class() -> void:
	for id in WeaponHoldMap.NO_MODEL:
		assert_bool(id in WeaponCatalog.IDS).is_true()
	for id in WeaponCatalog.IDS:
		if id not in WeaponHoldMap.NO_MODEL:
			assert_object(PlayerAnimation.hold_of(WeaponHoldMap.class_of(id))).is_not_null()


func test_a_melee_weapon_is_held_as_melee_whatever_its_id() -> void:
	assert_str(String(WeaponHoldMap.class_of(&"crowbar"))).is_equal("Melee")
	assert_str(String(WeaponHoldMap.class_of(&"nobody"))).is_equal(
		String(PlayerAnimation.DEFAULT_CLASS)
	)


func test_each_weapon_equipped_shows_its_class_and_model_on_the_local_player() -> void:
	var night := await _start()
	for id in WeaponCatalog.IDS:
		await _equip(night, 1, id)
		assert_str(String(night.state.me()["weapon"])).is_equal(String(id))
		_check(night.player(), id)
	night.queue_free()


func test_the_weapon_of_another_player_shows_on_his_body() -> void:
	var night := await _start()
	night.link.send({"type": NightServer.JOIN, "player_id": OTHER_ID, "local": false})
	NightFixture.run(night, 3)
	var other := night.server.body_of(OTHER_ID)
	assert_object(other).is_not_null()
	for id: StringName in [&"shotgun", &"crowbar", &"rifle"]:
		await _equip(night, OTHER_ID, id)
		_check(other, id)
		# The local player's hand is his own.
		assert_str(String(_animation(night.player()).weapon_class)).is_equal("Pistol")
	night.queue_free()


func test_a_swap_to_the_next_carried_weapon_changes_the_view() -> void:
	var night := await _start()
	assert_str(String(_animation(night.player()).weapon_class)).is_equal("Pistol")
	night.server.combat.apply(CombatAction.swap(1))
	NightFixture.run(night, 3)
	assert_str(String(night.state.me()["weapon"])).is_equal("crowbar")
	_check(night.player(), &"crowbar")
	night.queue_free()
