extends GdUnitTestSuite
## The re-cut layer in the real night (#791): the night has a `RecutLayer`, and when the player
## fires a weapon the server re-cut (`upgrade_weapon`, the bench's own action) the layer plays over
## the shot; the same weapon before the bench plays none.


func _start() -> Night:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 5)
	return night


func _fire(night: Night, weapon_id: StringName) -> int:
	var layer := night.get_node("RecutLayer") as RecutLayer
	var heard: Array[StringName] = []
	layer.play = func(id: StringName, _at: Variant, _db: float) -> void: heard.append(id)
	night.server.combat.apply(CombatAction.give_weapon(1, weapon_id))
	night.server.combat.apply(CombatAction.equip(1, weapon_id))
	NightFixture.run(night, 3)
	var command := NightFixture.shoot_at(night, night.state.position() + Vector3(0.0, 0.0, -12.0))
	NightFixture.run(night, 2, command)
	return heard.size()


func test_the_night_plays_the_layer_over_the_shot_of_every_re_cut_weapon() -> void:
	var night := await _start()
	for weapon_id in UpgradeTuning.new().weapons:
		var before := await _fire(night, weapon_id)
		(
			assert_int(before)
			. override_failure_message("%s: a layer before the bench" % weapon_id)
			. is_equal(0)
		)
		night.server.combat.apply(CombatAction.upgrade_weapon(1, weapon_id))
		NightFixture.run(night, 120)
		var after := await _fire(night, weapon_id)
		(
			assert_int(after)
			. override_failure_message("%s: no layer after the bench" % weapon_id)
			. is_greater(0)
		)
	night.queue_free()
