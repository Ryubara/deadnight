# The crowbar in a real night (#285): the attack button goes in as a real mouse event, the human
# controller turns it into the command, the server swings, a zombie in reach is hurt, the Soldier
# swings and no muzzle flash is drawn. Nothing here calls the combat or the animation directly.
extends GdUnitTestSuite

const SETTLE := 30
const REACH_AHEAD := 1.1

var _night: Night
var _controller: HumanController
var _heard: Array[Dictionary] = []


func before_test() -> void:
	_heard = []
	_controller = HumanController.new()
	_night = await NightFixture.start(self, Night.Mode.MANUAL)
	_night.state.event_received.connect(func(event: Dictionary) -> void: _heard.append(event))
	NightFixture.run(_night, SETTLE)
	# The shoulder camera settles on frames, not ticks.
	for _i in 90:
		await get_tree().process_frame


func after_test() -> void:
	_button(false)
	_night.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _count(type: StringName) -> int:
	return _heard.filter(func(event: Dictionary) -> bool: return event["type"] == type).size()


func _take_crowbar() -> void:
	# Not a start weapon any more (the quick melee took its place, #411): found, like the crane's.
	_night.server.combat.apply(CombatAction.give_weapon(1, &"crowbar"))
	NightFixture.run(_night, 3)
	assert_str(String(_night.state.me()["weapon"])).is_equal("crowbar")


## Puts a zombie `REACH_AHEAD` metres in front of the player along the view's ground direction.
func _zombie_in_reach() -> ZombieBody:
	var id := NightFixture.first_zombie(_night)
	assert_int(id).is_greater(0)
	var body: ZombieBody = _night.server.sim.zombies[id]
	var command := _controller.command(_night.player(), 1)
	var flat := Vector3(command.dir.x, 0.0, command.dir.z).normalized()
	body.position = _night.state.position() + flat * REACH_AHEAD
	body.velocity = Vector3.ZERO
	_night.server.sim.touch()
	return body


## The muzzle flashes made so far: one the first time a weapon fires, none for a blow.
func _lights() -> int:
	return _night.find_children(String(MuzzleFlash.NODE_NAME), "Node3D", true, false).size()


func test_the_attack_button_swings_the_crowbar_and_hurts_a_zombie_in_reach() -> void:
	_take_crowbar()
	var zombie := _zombie_in_reach()
	var spot := zombie.position
	var animation := _night.player().get_node("AnimationTree") as PlayerAnimation
	var swung := false
	_button(true)
	for _i in 12:
		zombie.position = spot
		zombie.velocity = Vector3.ZERO
		_night.server.sim.touch()
		NightFixture.run(_night, 1, _controller.command(_night.player(), 1))
		swung = swung or animation.action_clip == &"Swing_Melee"
	_button(false)
	assert_int(_count(&"shot_fired")).is_greater(0)
	(
		assert_int(_count(&"damage_dealt"))
		. override_failure_message("the blow did not hurt the zombie in reach")
		. is_greater(0)
	)
	assert_bool(_heard.any(func(e: Dictionary) -> bool: return e.get("melee", false))).is_true()
	assert_bool(swung).override_failure_message("no swing was played").is_true()
	# A blow has no muzzle: no flash light, no gun impact.
	assert_int(_lights()).override_failure_message("a muzzle flash was drawn").is_equal(0)


func test_a_zombie_out_of_reach_is_not_hurt() -> void:
	_take_crowbar()
	var zombie := _zombie_in_reach()
	var command := _controller.command(_night.player(), 1)
	var flat := Vector3(command.dir.x, 0.0, command.dir.z).normalized()
	var spot := _night.state.position() + flat * 4.0
	_button(true)
	for _i in 12:
		zombie.position = spot
		zombie.velocity = Vector3.ZERO
		_night.server.sim.touch()
		NightFixture.run(_night, 1, _controller.command(_night.player(), 1))
	_button(false)
	assert_int(_count(&"damage_dealt")).is_equal(0)


func test_a_gun_shot_still_draws_its_flash_and_plays_the_fire_clip() -> void:
	var animation := _night.player().get_node("AnimationTree") as PlayerAnimation
	var fired := false
	_button(true)
	for _i in 6:
		NightFixture.run(_night, 1, _controller.command(_night.player(), 1))
		fired = fired or animation.action_clip == &"Fire_Pistol"
	_button(false)
	assert_int(_count(&"shot_fired")).is_greater(0)
	assert_bool(fired).is_true()
	assert_int(_lights()).is_greater(0)


## The blows the real attack button lands on a walker of the round `round_number` (a fresh night
## each), with `weapon` in hand, until the walker is dead or `limit` ticks have passed: the damage
## of each blow and the health it left.
func _blows_on(weapon: StringName, round_number: int, limit: int = 150) -> Array[Dictionary]:
	_night.queue_free()
	await get_tree().physics_frame
	await before_test()
	_night.server.rules.round_number = round_number - 1
	_night.server.combat.apply(CombatAction.give_weapon(1, weapon))
	NightFixture.run(_night, 3)
	var zombie := _zombie_in_reach()
	var spot := zombie.position
	_button(true)
	for _i in limit:
		if _count(&"target_killed") > 0:
			break
		zombie.position = spot
		zombie.velocity = Vector3.ZERO
		NightFixture.run(_night, 1, _controller.command(_night.player(), 1))
	_button(false)
	return _heard.filter(func(e: Dictionary) -> bool: return e["type"] == &"damage_dealt")


func test_the_crowbar_bat_and_axe_do_their_flat_damage_through_the_real_button() -> void:
	# Through the real mouse button, the controller's camera ray, the sweep from the eye and the
	# rules' health (#924): the crowbar's and the bat's 55 leave 3 of round two's 58, the axe's
	# 132 kills round nine's 123 in one blow. Before, the head's x1.5 and x2.5 made them 68, 90
	# and 375 whatever the crosshair was on.
	var expected := {
		&"crowbar": [2, 2, 55.0],
		&"baseball_bat": [2, 2, 55.0],
		&"fire_axe": [9, 1, 132.0],
	}
	for weapon: StringName in expected:
		var plan: Array = expected[weapon]
		var blows := await _blows_on(weapon, plan[0])
		(
			assert_int(blows.size())
			. override_failure_message("%s: %d blows on round %d" % [weapon, blows.size(), plan[0]])
			. is_greater_equal(plan[1])
		)
		assert_float(blows[0]["damage"]).is_equal(plan[2])
		assert_int(_count(&"target_killed")).is_equal(1)
		assert_int(blows.size()).is_equal(plan[1])
