# The quick melee in a real night (#411): the key goes in as a real key event, the human controller
# turns it into the command, the body turns to the view, the server sweeps with whatever weapon is
# in hand, a zombie in reach is hurt, and the Soldier strikes with the clip of the weapon he holds.
# Nothing here calls the combat or the animation directly.
extends GdUnitTestSuite

const SETTLE := 30
const REACH_AHEAD := 1.1
## Each weapon kind and the clip its blow plays.
const HELD := {
	&"pistol": &"Strike_Pistol",
	&"rifle": &"Strike_Rifle",
	&"shotgun": &"Strike_Shotgun",
	&"baseball_bat": &"Strike_Melee",
	&"fire_axe": &"Strike_Melee",
}

var _night: Night
var _controller: HumanController
var _heard: Array[Dictionary] = []


func before_test() -> void:
	_heard = []
	_controller = HumanController.new()
	_night = await NightFixture.start(self, Night.Mode.MANUAL)
	_night.state.event_received.connect(func(event: Dictionary) -> void: _heard.append(event))
	NightFixture.run(_night, SETTLE)
	for _i in 60:
		await get_tree().process_frame


func after_test() -> void:
	_key(false)
	_night.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_V
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _count(type: StringName) -> int:
	return _heard.filter(func(event: Dictionary) -> bool: return event["type"] == type).size()


func _zombie_in_reach() -> ZombieBody:
	var id := NightFixture.first_zombie(_night)
	assert_int(id).is_greater(0)
	var body: ZombieBody = _night.server.sim.zombies[id]
	_place(body)
	return body


func _place(body: ZombieBody) -> void:
	# Not through the controller: reading it consumes the key's press.
	var dir := -_night.player().camera_rig.aim_transform().basis.z
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	body.position = _night.state.position() + flat * REACH_AHEAD
	body.velocity = Vector3.ZERO


## Holds the key for a few ticks (a tap), keeping the zombie where it is.
func _tap(body: ZombieBody, ticks: int = 12) -> void:
	_key(true)
	for _i in ticks:
		_place(body)
		NightFixture.run(_night, 1, _controller.command(_night.player(), 1))
		_key(false)


func test_v_strikes_with_each_weapon_and_plays_that_weapons_clip() -> void:
	for id in HELD:
		if id != HELD.keys()[0]:
			# A fresh night for each weapon: one zombie, whole.
			_night.queue_free()
			await get_tree().physics_frame
			await before_test()
		var animation := _night.player().get_node("AnimationTree") as PlayerAnimation
		_night.server.combat.apply(CombatAction.give_weapon(1, id, id))
		NightFixture.run(_night, 40)
		_heard = []
		var zombie := _zombie_in_reach()
		var seen: Array[StringName] = []
		_key(true)
		for _i in 14:
			_place(zombie)
			NightFixture.run(_night, 1, _controller.command(_night.player(), 1))
			_key(false)
			seen.append(animation.action_clip)
		(
			assert_int(_count(&"quick_melee"))
			. override_failure_message("V with the %s did not swing" % id)
			. is_equal(1)
		)
		(
			assert_int(_count(&"damage_dealt"))
			. override_failure_message("V with the %s did not hurt the zombie" % id)
			. is_equal(1)
		)
		(
			assert_array(seen)
			. override_failure_message("%s: the clip played was %s" % [id, seen])
			. contains([HELD[id]])
		)
		# No gun went off and the weapon in hand is the same one.
		assert_int(_count(&"shot_fired")).is_equal(0)
		assert_str(String(_night.state.me()["weapon"])).is_equal(String(id))


func test_a_round_two_walker_takes_two_blows_on_v_and_a_round_one_walker_one() -> void:
	# Through the real key, command, sweep from the eye and rules (#897): 50 health on round 1 falls
	# to the 50 of one blow, round 2's 58 does not.
	var round_one := _zombie_in_reach()
	_tap(round_one, 6)
	assert_int(_count(&"damage_dealt")).is_equal(1)
	assert_int(_count(&"target_killed")).is_equal(1)
	_night.queue_free()
	await get_tree().physics_frame
	await before_test()
	_night.server.rules.round_number = 1
	var walker := _zombie_in_reach()
	_tap(walker, 6)
	assert_int(_count(&"damage_dealt")).is_equal(1)
	var hurt := _heard.filter(func(e: Dictionary) -> bool: return e["type"] == &"damage_dealt")
	var left: float = hurt[0]["health"]
	assert_float(left).is_equal(RulesFixture.round_health(2) - 50.0)
	assert_int(_count(&"target_killed")).is_equal(0)
	NightFixture.run(_night, 40)
	_tap(walker, 6)
	assert_int(_count(&"damage_dealt")).is_equal(2)
	assert_int(_count(&"target_killed")).is_equal(1)


func test_a_press_while_the_body_faces_away_turns_it_and_the_blow_follows() -> void:
	var zombie := _zombie_in_reach()
	var player := _night.player()
	player.state.facing += PI * 0.9
	player.rotation.y = player.state.facing
	_tap(zombie, 40)
	assert_int(_count(&"quick_melee")).is_equal(1)
	assert_int(_count(&"damage_dealt")).is_equal(1)


func test_the_cooldown_refuses_a_second_blow_and_a_later_one_lands() -> void:
	var zombie := _zombie_in_reach()
	_tap(zombie, 6)
	_tap(zombie, 6)
	assert_int(_count(&"quick_melee")).is_equal(1)
	NightFixture.run(_night, 40)
	_tap(zombie, 6)
	assert_int(_count(&"quick_melee")).is_equal(2)


func test_the_blow_is_refused_while_a_grenade_is_cooking_in_the_hand() -> void:
	var zombie := _zombie_in_reach()
	var cook := _controller.command(_night.player(), 1)
	cook.motion.throw_over = true
	NightFixture.run(_night, 6, cook)
	assert_bool(_night.server.grenades.is_cooking(1)).is_true()
	var blow := _controller.command(_night.player(), 1)
	blow.motion.throw_over = true
	blow.motion.melee = true
	_place(zombie)
	NightFixture.run(_night, 1, blow)
	NightFixture.run(_night, 3, cook)
	assert_int(_count(&"quick_melee")).is_equal(0)


func test_a_downed_player_cannot_strike() -> void:
	_night.server.rules.apply(RulesAction.set_downed(1, true))
	NightFixture.run(_night, 4)
	var blow := NightCommand.new()
	blow.motion.melee = true
	NightFixture.run(_night, 20, blow)
	assert_int(_count(&"quick_melee")).is_equal(0)
