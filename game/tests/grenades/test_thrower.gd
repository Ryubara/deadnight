extends GdUnitTestSuite
## The throw input: buttons in a PlayerCommand become actions, the same way every time.

const HAND := Vector3(0, 1.5, 0)
const AIM := Vector3(0, 0, -1)

var _thrower: GrenadeThrower


func before_test() -> void:
	_thrower = GrenadeThrower.new(1, GrenadesFixture.def())


func _tick(over: bool, under: bool = false, hand: Vector3 = HAND) -> Array[Dictionary]:
	var command := PlayerCommand.new()
	command.throw_over = over
	command.throw_under = under
	return _thrower.step(command, hand, AIM, Vector3.ZERO)


func test_nothing_held_does_nothing() -> void:
	assert_array(_tick(false)).is_empty()
	assert_bool(_thrower.is_cooking()).is_false()


func test_pressing_cooks_holding_waits_and_releasing_throws() -> void:
	var press := _tick(true)
	assert_array(press).has_size(1)
	assert_str(press[0]["type"]).is_equal("cook")
	assert_bool(_thrower.is_cooking()).is_true()
	for _i in 30:
		assert_array(_tick(true)).is_empty()
	assert_float(_thrower.cooked_for(1.0 / 60.0)).is_equal_approx(0.5, 0.001)
	var release := _tick(false)
	assert_array(release).has_size(1)
	assert_str(release[0]["type"]).is_equal("throw")
	assert_bool(release[0]["underarm"]).is_false()
	assert_bool(_thrower.is_cooking()).is_false()


func test_the_second_input_tosses_underarm() -> void:
	_tick(false, true)
	var release := _tick(false, false)
	assert_bool(release[0]["underarm"]).is_true()


func test_each_throw_has_its_own_sequence_number() -> void:
	var first := _tick(true)
	_tick(false)
	var second := _tick(true)
	assert_int(second[0]["seq"]).is_equal(first[0]["seq"] + 1)


func test_a_moving_hand_is_told_to_the_server() -> void:
	_tick(true)
	assert_array(_tick(true, false, HAND + Vector3(0.2, 0, 0))).is_empty()
	var moved := _tick(true, false, HAND + Vector3(0.8, 0, 0))
	assert_array(moved).has_size(1)
	assert_str(moved[0]["type"]).is_equal("cook")


func test_after_a_grenade_goes_off_in_the_hand_the_held_button_does_nothing() -> void:
	_tick(true)
	_thrower.abandon()
	assert_array(_tick(true)).is_empty()
	assert_bool(_thrower.is_cooking()).is_false()
	_tick(false)
	assert_array(_tick(true)).has_size(1)


func test_the_same_commands_give_the_same_actions_and_a_restored_state_too() -> void:
	var script := []
	for i in 90:
		script.append([i >= 5 and i < 70, false, HAND + Vector3(i * 0.02, 0, 0)])
	var run_a := _run(GrenadeThrower.new(1, GrenadesFixture.def()), script)
	var run_b := _run(GrenadeThrower.new(1, GrenadesFixture.def()), script)
	assert_str(str(run_a)).is_equal(str(run_b))
	# Stop halfway, save, restore into a fresh one, and finish: the same actions.
	var half := GrenadeThrower.new(1, GrenadesFixture.def())
	var first := _run(half, script.slice(0, 40))
	var resumed := GrenadeThrower.new(1, GrenadesFixture.def())
	resumed.restore(half.snapshot())
	var rest := _run(resumed, script.slice(40))
	assert_str(str(first + rest)).is_equal(str(run_a))


func _run(thrower: GrenadeThrower, script: Array) -> Array:
	var actions := []
	for entry in script:
		var command := PlayerCommand.new()
		command.throw_over = entry[0]
		command.throw_under = entry[1]
		actions.append_array(thrower.step(command, entry[2], AIM, Vector3.ZERO))
	return actions


func test_a_cooked_throw_replays_to_the_same_grenade_on_the_server() -> void:
	# The client predicts with its own server copy; the replay of the same commands on another
	# gives the same landing.
	var landings: Array[Vector3] = []
	for _run_index in 2:
		var night := GrenadesFixture.night(1, GrenadesFixture.world_cast())
		var thrower := GrenadeThrower.new(1, GrenadesFixture.def())
		for i in 100:
			var command := PlayerCommand.new()
			command.throw_over = i >= 3 and i < 60
			for action in thrower.step(command, HAND, Vector3(0.3, 0.2, -1.0), Vector3(0, 0, -3)):
				night.server.apply(action)
			night.server.apply(GrenadeAction.tick(GrenadesFixture.STEP))
		var grenade := night.server.grenade(1)
		landings.append(grenade.position)
	assert_vector(landings[0]).is_equal(landings[1])


func test_the_command_carries_the_grenade_buttons_through_bytes() -> void:
	var command := PlayerCommand.new()
	command.throw_over = true
	command.throw_under = true
	var back := PlayerCommand.from_bytes(command.to_bytes())
	assert_bool(back.throw_over).is_true()
	assert_bool(back.throw_under).is_true()
	assert_bool(PlayerCommand.from_dict({}).throw_over).is_false()


func test_both_grenade_buttons_have_a_key_and_a_gamepad_button() -> void:
	for action in [&"throw_grenade", &"toss_grenade"]:
		assert_bool(InputMap.has_action(action)).is_true()
		var events := InputMap.action_get_events(action)
		assert_bool(events.any(func(e: InputEvent) -> bool: return e is InputEventKey)).is_true()
		(
			assert_bool(events.any(func(e: InputEvent) -> bool: return e is InputEventJoypadButton))
			. is_true()
		)


func test_the_player_samples_the_grenade_buttons_into_the_command() -> void:
	var player := auto_free(preload("res://gameplay/player/player.tscn").instantiate()) as Player
	player.capture_mouse = false
	add_child(player)
	Input.action_press(&"throw_grenade")
	var held := player.sample_command()
	Input.action_release(&"throw_grenade")
	assert_bool(held.throw_over).is_true()
	assert_bool(held.throw_under).is_false()
	assert_bool(player.sample_command().throw_over).is_false()
