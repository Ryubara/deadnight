# The weapon in the Soldier's hand follows the weapon the server says he holds (docs/design/
# weapon-hold.md, "Which weapon is which"): every id of the catalogue, equipped through the real
# combat action, shows its class, its hold and its model on the player view, for the local
# player and for another one.
extends GdUnitTestSuite

const OTHER_ID := 2
## Frames the Equip clip is given to bring the weapon up.
const EQUIP_FRAMES := 120
## Per weapon: the class it is held as and the model its own hold file names. A model that is not
## in `assets/weapons/` yet leaves the hand empty (`WAITING`): never another weapon's model.
const EXPECTED := {
	&"rifle": [&"Rifle", "res://assets/weapons/lever_rifle/lever_rifle.glb"],
	&"shotgun": [&"Shotgun", "res://assets/weapons/double_shotgun/double_shotgun.glb"],
	&"crowbar": [&"Melee", "res://assets/weapons/crowbar/crowbar.glb"],
	&"smg": [&"Rifle", "res://assets/weapons/tommy_gun/tommy_gun.glb"],
	&"pistol": [&"Pistol", "res://assets/weapons/revolver/revolver.glb"],
	&"flare_gun": [&"Pistol", "res://assets/weapons/flare_gun/flare_gun.glb"],
	&"baseball_bat": [&"Melee", "res://assets/weapons/baseball_bat/baseball_bat.glb"],
	&"fire_axe": [&"Melee", "res://assets/weapons/fire_axe/fire_axe.glb"],
	&"dual_pistols": [&"Dual", "res://assets/weapons/service_pistol/service_pistol.glb"],
}
## A weapon drawn with another's model until its own lands: it may share that model, and is taken
## off this list with its own glb. None now (the pair has the service pistol, #797).
const STAND_INS := {}


func _start() -> Night:
	var night := await NightFixture.start(self, Night.Mode.MANUAL, RulesFixture.full_hands())
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


## The weapon shows on the Equip clip's `weapon_visible` frame: frames, not ticks, carry it.
func _check(body: Player, weapon_id: StringName) -> void:
	var animation := _animation(body)
	for _i in EQUIP_FRAMES:
		if animation.weapon() == null or animation.weapon().visible:
			break
		await get_tree().process_frame
	var expected: Array = EXPECTED[weapon_id]
	(
		assert_str(String(animation.weapon_class))
		. override_failure_message("%s: class" % weapon_id)
		. is_equal(String(expected[0]))
	)
	var model: String = expected[1]
	if not ResourceLoader.exists(model):
		(
			assert_object(animation.weapon())
			. override_failure_message("%s: no model yet, an empty hand" % weapon_id)
			. is_null()
		)
		assert_object(animation.weapon_hold()).is_null()
		return
	var weapon := animation.weapon()
	(
		assert_object(weapon)
		. override_failure_message("%s: its model is not in the hand" % weapon_id)
		. is_not_null()
	)
	assert_bool(weapon.visible).override_failure_message("%s: hidden" % weapon_id).is_true()
	assert_bool(weapon.is_inside_tree()).is_true()
	assert_str(weapon.scene_file_path).is_equal(model)
	assert_str(animation.weapon_hold().scene).is_equal(model)
	assert_str(String(animation.weapon_hold().weapon_class)).is_equal(String(expected[0]))


func test_the_table_covers_the_whole_catalogue() -> void:
	assert_array(EXPECTED.keys()).contains_exactly_in_any_order(WeaponCatalog.IDS)
	for id in WeaponCatalog.IDS:
		var weapon_class := WeaponHoldMap.class_of(id)
		assert_bool(weapon_class in PlayerAnimation.CLASSES).is_true()
		assert_str(String(weapon_class)).is_equal(String(EXPECTED[id][0]))


func test_no_two_weapons_share_a_model() -> void:
	var seen := {}
	for id in WeaponCatalog.IDS:
		var model: String = EXPECTED[id][1]
		if STAND_INS.has(id):
			# Its model is the stand-in's, until its own lands.
			assert_str(model).is_equal(EXPECTED[STAND_INS[id]][1])
			continue
		(
			assert_bool(seen.has(model))
			. override_failure_message("%s shares %s" % [id, model])
			. is_false()
		)
		seen[model] = id
	# The bat and the axe are not the crowbar, the lever rifle is not the Tommy gun.
	assert_str(EXPECTED[&"crowbar"][1]).is_not_equal(
		"res://assets/weapons/baseball_bat/baseball_bat.glb"
	)


func test_every_weapon_has_a_hold_file_of_its_own() -> void:
	for id in WeaponCatalog.IDS:
		var path := "%s%s.tres" % [PlayerAnimation.HOLDS_DIR, id]
		assert_bool(ResourceLoader.exists(path)).override_failure_message(path).is_true()
		var hold := load(path) as WeaponHold
		assert_str(hold.scene).is_equal(EXPECTED[id][1])
		assert_str(String(hold.weapon_class)).is_equal(String(WeaponHoldMap.class_of(id)))
	# What has no glb yet is the list the docs name.
	for id in WeaponHoldMap.no_model():
		assert_bool(ResourceLoader.exists(EXPECTED[id][1])).is_false()


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
		await _check(night.player(), id)
	night.queue_free()


func test_the_weapon_of_another_player_shows_on_his_body() -> void:
	var night := await _start()
	night.link.send({"type": NightServer.JOIN, "player_id": OTHER_ID, "local": false})
	NightFixture.run(night, 3)
	var other := night.server.body_of(OTHER_ID)
	assert_object(other).is_not_null()
	for id: StringName in [&"shotgun", &"crowbar", &"rifle"]:
		await _equip(night, OTHER_ID, id)
		await _check(other, id)
		# The local player's hand is his own.
		assert_str(String(_animation(night.player()).weapon_class)).is_equal("Pistol")
	night.queue_free()


func test_a_swap_to_the_next_carried_weapon_changes_the_view() -> void:
	var night := await _start()
	assert_str(String(_animation(night.player()).weapon_class)).is_equal("Pistol")
	night.server.combat.apply(CombatAction.swap(1))
	NightFixture.run(night, 3)
	assert_str(String(night.state.me()["weapon"])).is_equal("crowbar")
	await _check(night.player(), &"crowbar")
	night.queue_free()


func test_an_attack_straight_after_equipping_does_not_leave_the_hand_empty() -> void:
	var night := await _start()
	await _equip(night, 1, &"rifle")
	var animation := _animation(night.player())
	# Taken in hand and fired within the same frame: the Equip clip never reaches its frame.
	animation.equip(&"shotgun")
	assert_bool(animation.weapon().visible).is_false()
	animation.play_action(&"Fire")
	assert_bool(animation.weapon().visible).is_true()
	night.queue_free()
