# The numbered weapon slots in the real night (#682): the keys 1 and 2 take the first and the second
# weapon carried in hand, the slot in hand and an empty slot change nothing, a bought weapon takes
# the place of the one it replaces, and the pick travels the wire and survives a newer command. The
# keys themselves, on every device, are rows of `test_input_matrix.gd`.
extends GdUnitTestSuite

var _night: Night
var _heard: Array[Dictionary] = []


func before_test() -> void:
	_heard = []
	_night = await NightFixture.start(
		self, Night.Mode.MANUAL, RulesFixture.full_hands(RulesFixture.steady_crane_tuning()), 7
	)
	_night.state.event_received.connect(func(event: Dictionary) -> void: _heard.append(event))
	NightFixture.run(_night, 5)
	_night.server.rules.apply(RulesAction.grant_points(1, 50000))
	NightFixture.run(_night, 2)


func after_test() -> void:
	for action in WeaponSlots.ACTIONS:
		Input.action_release(action)
	_night.queue_free()


func _press_slot(slot: int) -> void:
	var command := NightCommand.new()
	command.slot = slot
	NightFixture.run(_night, 1, command)
	NightFixture.run(_night, 3)


func _held() -> String:
	return String(_night.state.me()["weapon"])


func _carried() -> Array:
	return _night.server.combat.carried(1)


func _equips() -> int:
	return _heard.filter(func(e: Dictionary) -> bool: return e["type"] == &"weapon_equipped").size()


func _stand_at(shop_id: StringName) -> void:
	for spot in _night.world.shop_spots():
		if spot["shop_id"] == shop_id:
			_night.player().teleport(spot["position"] + Vector3(0.0, 0.1, 0.0))
			break
	NightFixture.run(_night, 3)


func test_a_player_starts_with_the_crowbar_in_slot_one_and_the_pistol_in_two() -> void:
	assert_array(_carried()).is_equal([&"crowbar", &"pistol"])
	assert_str(_held()).is_equal("pistol")


func test_slot_one_takes_the_first_weapon_and_slot_two_the_second() -> void:
	_press_slot(1)
	assert_str(_held()).is_equal("crowbar")
	_press_slot(2)
	assert_str(_held()).is_equal("pistol")
	_press_slot(1)
	assert_str(_held()).is_equal("crowbar")


func test_the_slot_in_hand_does_nothing() -> void:
	var before := _equips()
	_press_slot(2)
	assert_str(_held()).is_equal("pistol")
	assert_int(_equips()).is_equal(before)


func test_the_slot_in_hand_does_not_cancel_a_reload() -> void:
	# A reload runs on the pistol, and the key of the pistol's own slot is pressed: still reloading.
	var pistol := _night.server.combat.weapon_of(1)
	pistol.ammo = 1
	var command := NightCommand.new()
	command.reload = true
	NightFixture.run(_night, 1, command)
	NightFixture.run(_night, 2)
	assert_bool(pistol.is_reloading()).is_true()
	_press_slot(2)
	assert_bool(pistol.is_reloading()).is_true()


func test_an_empty_slot_does_nothing() -> void:
	var before := _equips()
	_press_slot(3)
	assert_str(_held()).is_equal("pistol")
	_press_slot(WeaponSlots.MAX + 5)
	assert_str(_held()).is_equal("pistol")
	assert_int(_equips()).is_equal(before)


func test_a_slot_put_away_mid_reload_cancels_that_reload_like_a_swap() -> void:
	var pistol := _night.server.combat.weapon_of(1)
	pistol.ammo = 1
	var command := NightCommand.new()
	command.reload = true
	NightFixture.run(_night, 1, command)
	NightFixture.run(_night, 2)
	assert_bool(pistol.is_reloading()).is_true()
	_press_slot(1)
	assert_str(_held()).is_equal("crowbar")
	assert_bool(pistol.is_reloading()).is_false()


func test_the_swap_button_still_goes_to_the_next_weapon() -> void:
	var command := NightCommand.new()
	command.swap = true
	NightFixture.run(_night, 1, command)
	NightFixture.run(_night, 3)
	assert_str(_held()).is_equal("crowbar")


func test_a_bought_weapon_takes_the_slot_of_the_one_it_replaces() -> void:
	# The pistol (slot 2) is in hand: the shotgun takes its place, the crowbar stays slot 1.
	_stand_at(&"weapon_shotgun")
	NightFixture.run(_night, 1, _use())
	NightFixture.run(_night, 3)
	assert_array(_carried()).is_equal([&"crowbar", &"shotgun"])
	assert_str(_held()).is_equal("shotgun")
	# The crowbar (slot 1) in hand: the rifle takes slot 1 and the shotgun stays slot 2.
	_press_slot(1)
	_stand_at(&"weapon_rifle")
	NightFixture.run(_night, 1, _use())
	NightFixture.run(_night, 3)
	assert_array(_carried()).is_equal([&"rifle", &"shotgun"])
	assert_str(_held()).is_equal("rifle")
	_press_slot(2)
	assert_str(_held()).is_equal("shotgun")


func _use() -> NightCommand:
	var command := NightCommand.new()
	command.use = true
	return command


func test_the_key_reads_into_the_command_once_per_press() -> void:
	var controller := HumanController.new()
	Input.action_press(&"weapon_slot_1")
	assert_int(controller.command(_night.player(), 1).slot).is_equal(1)
	# Held: no new press, so no new pick.
	assert_int(controller.command(_night.player(), 1).slot).is_equal(WeaponSlots.NONE)
	Input.action_release(&"weapon_slot_1")
	Input.action_press(&"weapon_slot_2")
	assert_int(controller.command(_night.player(), 1).slot).is_equal(2)


func test_the_command_carries_the_slot_as_data_and_on_the_wire() -> void:
	for slot in range(0, WeaponSlots.MAX + 1):
		var command := NightCommand.new()
		command.slot = slot
		command.swap = slot == 2
		assert_int(NightCommand.from_dict(command.to_dict()).slot).is_equal(slot)
		var read := NetWire.read_command(NetWire.command(command))
		assert_int(read.slot).is_equal(slot)
		# The bits beside the slot are the same flags as before.
		assert_bool(read.swap).is_equal(slot == 2)
		assert_bool(read.fire).is_false()
		assert_bool(read.motion.melee).is_false()


func test_a_pick_waits_for_a_step_even_when_a_newer_command_arrives() -> void:
	var first := NightCommand.new()
	first.slot = 1
	_night.server.submit(1, first)
	_night.server.submit(1, NightCommand.new())
	NightFixture.run(_night, 3)
	assert_str(_held()).is_equal("crowbar")
