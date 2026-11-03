# A re-cut weapon wears its skin in every view for as long as it is held (Deadnight #787): the
# night's
# frames carry each weapon's tier, `WeaponEquipSync` dresses the body that holds it (the local
# player's and the
# others'), and a weapon that is swapped away, lost or bought again plain does not keep it.
extends GdUnitTestSuite

const OTHER_ID := 2


func _start() -> Night:
	var night := await NightFixture.start(self, Night.Mode.MANUAL, RulesFixture.full_hands())
	NightFixture.run(night, 3)
	return night


func _animation(body: Player) -> PlayerAnimation:
	return body.get_node("AnimationTree") as PlayerAnimation


func _recut(night: Night, player_id: int, weapon_id: StringName) -> void:
	night.server.combat.apply(CombatAction.upgrade_weapon(player_id, weapon_id))
	NightFixture.run(night, 3)


func _equip(night: Night, player_id: int, weapon_id: StringName) -> void:
	night.server.combat.apply(CombatAction.give_weapon(player_id, weapon_id))
	night.server.combat.apply(CombatAction.equip(player_id, weapon_id))
	NightFixture.run(night, 3)


func test_a_frame_entry_says_the_weapon_in_hand_is_re_cut_by_its_tier() -> void:
	var arms := {&"pistol": [10, 40, 1], &"rifle": [5, 20, 0]}
	assert_bool(WeaponEquipSync.is_recut({"weapon": &"pistol", "arms": arms})).is_true()
	assert_bool(WeaponEquipSync.is_recut({"weapon": &"rifle", "arms": arms})).is_false()
	# A weapon the entry does not list, and an entry with no arms, are plain.
	assert_bool(WeaponEquipSync.is_recut({"weapon": &"smg", "arms": arms})).is_false()
	assert_bool(WeaponEquipSync.is_recut({"weapon": &"pistol"})).is_false()
	assert_bool(WeaponEquipSync.is_recut({"weapon": &"", "arms": arms})).is_false()


func test_the_weapon_in_the_players_hand_is_plain_until_it_is_re_cut_then_skinned() -> void:
	var night := await _start()
	var animation := _animation(night.player())
	assert_bool(animation.is_recut()).is_false()
	await _recut(night, 1, &"pistol")
	assert_bool(animation.is_recut()).is_true()
	# On the revolver's real surfaces, not an overlay.
	var skin := RecutSkin.worn_by(animation.weapon())
	assert_object(skin).is_not_null()
	assert_int(skin.surface_count()).is_greater(0)
	night.queue_free()


func test_the_skin_sweeps_on_in_the_hand_when_the_re_cut_is_bought() -> void:
	var night := await _start()
	var animation := _animation(night.player())
	await _recut(night, 1, &"pistol")
	var skin := RecutSkin.worn_by(animation.weapon())
	# It started at nothing and is going over the weapon: not shown finished in the frame of the buy.
	assert_float(skin.reveal).is_less(1.0)
	for _i in 90:
		await get_tree().process_frame
	assert_float(skin.reveal).is_equal(1.0)
	night.queue_free()


func test_a_swap_away_and_back_shows_a_re_cut_weapon_finished_and_the_other_plain() -> void:
	var night := await _start()
	await _recut(night, 1, &"pistol")
	night.server.combat.apply(CombatAction.swap(1))
	NightFixture.run(night, 3)
	assert_str(String(night.state.me()["weapon"])).is_equal("crowbar")
	assert_bool(_animation(night.player()).is_recut()).is_false()
	night.server.combat.apply(CombatAction.swap(1))
	NightFixture.run(night, 3)
	var animation := _animation(night.player())
	assert_str(String(night.state.me()["weapon"])).is_equal("pistol")
	assert_bool(animation.is_recut()).is_true()
	# Put in the hand re-cut, it is shown finished: nothing sweeps on.
	assert_float(RecutSkin.worn_by(animation.weapon()).reveal).is_equal(1.0)
	night.queue_free()


func test_every_weapon_that_can_be_re_cut_wears_it_in_the_hand() -> void:
	var night := await _start()
	for id in UpgradeTuning.new().weapons:
		await _equip(night, 1, id)
		var animation := _animation(night.player())
		assert_bool(animation.is_recut()).override_failure_message("%s plain" % id).is_false()
		await _recut(night, 1, id)
		assert_bool(animation.is_recut()).override_failure_message("%s re-cut" % id).is_true()
	night.queue_free()


func test_another_players_re_cut_weapon_is_skinned_on_his_body_and_mine_is_not() -> void:
	var night := await _start()
	night.link.send({"type": NightServer.JOIN, "player_id": OTHER_ID, "local": false})
	NightFixture.run(night, 3)
	var other := night.server.body_of(OTHER_ID)
	await _equip(night, OTHER_ID, &"shotgun")
	assert_bool(_animation(other).is_recut()).is_false()
	await _recut(night, OTHER_ID, &"shotgun")
	assert_bool(_animation(other).is_recut()).is_true()
	assert_bool(_animation(night.player()).is_recut()).is_false()
	night.queue_free()


func test_a_weapon_lost_and_taken_again_comes_back_plain() -> void:
	var night := await _start()
	await _recut(night, 1, &"pistol")
	assert_bool(_animation(night.player()).is_recut()).is_true()
	# The crane or the wall gives another weapon in place of the revolver: the one in hand is plain.
	night.server.combat.apply(CombatAction.give_weapon(1, &"rifle", &"pistol"))
	night.server.combat.apply(CombatAction.equip(1, &"rifle"))
	NightFixture.run(night, 3)
	assert_bool(_animation(night.player()).is_recut()).is_false()
	night.server.combat.apply(CombatAction.give_weapon(1, &"pistol", &"rifle"))
	night.server.combat.apply(CombatAction.equip(1, &"pistol"))
	NightFixture.run(night, 3)
	assert_str(String(night.state.me()["weapon"])).is_equal("pistol")
	assert_bool(_animation(night.player()).is_recut()).is_false()
	night.queue_free()
