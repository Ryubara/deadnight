extends GdUnitTestSuite
## The dual pistols (#789): two pistols, one in each hand. The shots alternate hands, right first,
## on the one fire button; the two guns share one magazine and one reserve, and a reload fills the
## magazine of both; the server numbers the hand of every shot so each client flashes the right
## muzzle.

var _server: CombatServer


func before_test() -> void:
	_server = WeaponsFixture.make_server()
	_server.apply(CombatAction.give_weapon(1, &"dual_pistols"))
	_server.apply(CombatAction.equip(1, &"dual_pistols"))


func _pull(seq: int) -> Array[Dictionary]:
	return _server.apply(WeaponsFixture.fire_at(1, seq, WeaponsFixture.SHOOTER, Vector3(0, 1.1, 0)))


func _wait(seconds: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for _i in int(ceil(seconds / WeaponsFixture.STEP)):
		events.append_array(_server.apply(CombatAction.tick(WeaponsFixture.STEP)))
	return events


## `count` shots, each as soon as the weapon allows, and the hand each one was for.
func _hands(count: int) -> Array[int]:
	var def := WeaponsFixture.def(&"dual_pistols")
	var hands: Array[int] = []
	for seq in count:
		var shot := WeaponsFixture.of(_pull(seq + 1), &"shot_fired")
		assert_array(shot).has_size(1)
		hands.append(shot[0]["hand"])
		_wait(def.fire_interval + 0.02)
	return hands


func test_the_pair_is_a_dual_firearm_with_one_shared_magazine() -> void:
	var def := WeaponsFixture.def(&"dual_pistols")
	assert_bool(def.dual).is_true()
	assert_bool(def.is_hitscan()).is_true()
	assert_bool(def.automatic).is_true()
	assert_int(_server.state_of(1, &"dual_pistols").ammo).is_equal(def.magazine_size)
	# One count for both guns: an even magazine, so each gun fires half of it.
	assert_int(def.magazine_size % 2).is_equal(0)
	for id in WeaponCatalog.IDS:
		if id != &"dual_pistols":
			assert_bool(WeaponsFixture.def(id).dual).override_failure_message(str(id)).is_false()


func test_the_shots_alternate_hands_right_first() -> void:
	assert_array(_hands(6)).is_equal([0, 1, 0, 1, 0, 1])


func test_a_weapon_in_one_hand_always_shoots_from_the_right() -> void:
	_server.apply(CombatAction.give_weapon(1, &"pistol"))
	_server.apply(CombatAction.equip(1, &"pistol"))
	var def := WeaponsFixture.def(&"pistol")
	for seq in 4:
		var shot := WeaponsFixture.of(_pull(seq + 1), &"shot_fired")
		assert_int(shot[0]["hand"]).is_equal(0)
		_wait(def.fire_interval + 0.02)


func test_every_shot_spends_one_round_of_the_shared_magazine() -> void:
	var state := _server.state_of(1, &"dual_pistols")
	var before := state.ammo
	var shot := WeaponsFixture.of(_pull(1), &"shot_fired")[0]
	assert_int(shot["ammo"]).is_equal(before - 1)
	_wait(0.2)
	assert_int(WeaponsFixture.of(_pull(2), &"shot_fired")[0]["ammo"]).is_equal(before - 2)


func test_a_reload_fills_the_magazine_of_both_guns() -> void:
	var def := WeaponsFixture.def(&"dual_pistols")
	var state := _server.state_of(1, &"dual_pistols")
	var reserve := state.reserve
	state.ammo = 0
	_server.apply(CombatAction.reload_weapon(1))
	assert_bool(state.is_reloading()).is_true()
	assert_int(state.ammo).is_equal(0)
	var done := WeaponsFixture.of(_wait(def.reload_time + 0.05), &"reload_finished")
	assert_array(done).has_size(1)
	# Both guns' rounds come back at once: the whole magazine, from the one reserve.
	assert_int(state.ammo).is_equal(def.magazine_size)
	assert_int(state.reserve).is_equal(reserve - def.magazine_size)
	assert_int(done[0]["ammo"]).is_equal(def.magazine_size)


func test_a_reload_does_not_hand_the_turn_back_to_the_right() -> void:
	# Whose turn it is belongs to the trigger, not the magazine: after a reload the next shot is
	# the other hand's.
	assert_array(_hands(1)).is_equal([0])
	var state := _server.state_of(1, &"dual_pistols")
	state.ammo = 0
	_server.apply(CombatAction.reload_weapon(1))
	_wait(WeaponsFixture.def(&"dual_pistols").reload_time + 0.05)
	assert_array(_hands(2)).is_equal([1, 0])


func test_the_pair_reloads_with_the_steps_the_sounds_play() -> void:
	var motion := ReloadMotion.for_weapon(&"dual_pistols")
	assert_object(motion).is_not_null()
	for step: StringName in WeaponSounds.RELOAD[&"dual_pistols"]:
		assert_array(motion.event_shares(step)).override_failure_message(str(step)).is_not_empty()
	assert_bool(WeaponSounds.FIRE.has(&"dual_pistols")).is_true()


func test_the_re_cut_pair_keeps_both_hands() -> void:
	var def := WeaponsFixture.def(&"dual_pistols").upgraded(UpgradeTuning.new())
	assert_bool(def.dual).is_true()
