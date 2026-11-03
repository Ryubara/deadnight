# The input actions are defined once each, and no two gameplay actions share a gamepad button or
# stick direction (#162): a pad press must do one thing.
extends GdUnitTestSuite

## What a player does in the night; the `ui_*` actions belong to menus and may share buttons with
## them (A accepts in a menu and jumps in the night).
const GAMEPLAY: Array[StringName] = [
	&"move_forward",
	&"move_back",
	&"move_left",
	&"move_right",
	&"look_left",
	&"look_right",
	&"look_up",
	&"look_down",
	&"sprint",
	&"crouch",
	&"jump",
	&"aim",
	&"swap_shoulder",
	&"fire",
	&"reload",
	&"interact",
	&"swap_weapon",
	&"weapon_slot_1",
	&"weapon_slot_2",
	&"weapon_slot_3",
	&"pause",
	&"scoreboard",
	&"throw_grenade",
	&"toss_grenade",
	&"quick_melee",
	&"ping",
	&"bot_wheel",
]


func test_every_action_is_defined_once_in_the_project_file() -> void:
	var text := FileAccess.get_file_as_string("res://project.godot")
	var seen := {}
	var in_input := false
	for line in text.split("\n"):
		if line.begins_with("["):
			in_input = line.strip_edges() == "[input]"
		elif in_input and line.contains("={"):
			var action := line.get_slice("=", 0)
			(
				assert_bool(seen.has(action))
				. override_failure_message(
					"the action %s is defined twice; the later one wins" % action
				)
				. is_false()
			)
			seen[action] = true
	assert_bool(seen.has("interact")).is_true()


func test_no_two_gameplay_actions_share_a_pad_button_or_stick_direction() -> void:
	var owner_of := {}
	for action in GAMEPLAY:
		assert_bool(InputMap.has_action(action)).is_true()
		for event in InputMap.action_get_events(action):
			var key := _pad_key(event)
			if key == "":
				continue
			(
				assert_bool(owner_of.has(key))
				. override_failure_message(
					"%s and %s both use %s" % [owner_of.get(key), action, key]
				)
				. is_false()
			)
			owner_of[key] = action


func test_the_buttons_the_docs_name_are_the_ones_bound() -> void:
	assert_str(_pad_of(&"reload")).is_equal("button 2")
	assert_str(_pad_of(&"interact")).is_equal("button 3")
	assert_str(_pad_of(&"fire")).is_equal("axis 5+")
	assert_str(_pad_of(&"pause")).is_equal("button 6")
	# Back / Select, the small button on the left of the pad's middle.
	assert_str(_pad_of(&"scoreboard")).is_equal("button 4")


func test_the_wheel_the_ping_and_the_shoulder_are_on_the_keys_the_maintainer_asked_for() -> void:
	assert_array(_keys_of(&"bot_wheel")).contains_exactly([KEY_Q])
	assert_array(_keys_of(&"swap_shoulder")).contains_exactly([KEY_C])
	assert_array(_keys_of(&"crouch")).contains_exactly([KEY_CTRL])
	assert_array(_keys_of(&"ping")).contains_exactly([KEY_Z])
	assert_bool(_has_mouse_button(&"ping", MOUSE_BUTTON_MIDDLE)).is_true()
	assert_str(_pad_of(&"bot_wheel")).is_equal("button 13")
	assert_str(_pad_of(&"ping")).is_equal("button 14")
	# Every pad event answers every pad (device -1), so a reconnected or second pad plays too.
	for action in [&"bot_wheel", &"ping", &"swap_shoulder"]:
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton:
				assert_int(event.device).is_equal(-1)


func test_the_number_keys_take_the_weapon_slots_and_the_swap_stays_where_it_was() -> void:
	# 1 and 2 pick the first and second weapon (#682), 3 is the third slot's; none of them is on a pad
	# (the pad and the phone swap with one button) and none shares a key with another action.
	assert_array(_keys_of(&"weapon_slot_1")).contains_exactly([KEY_1])
	assert_array(_keys_of(&"weapon_slot_2")).contains_exactly([KEY_2])
	assert_array(_keys_of(&"weapon_slot_3")).contains_exactly([KEY_3])
	for action in WeaponSlots.ACTIONS:
		assert_str(_pad_of(action)).is_equal("")
	assert_array(_keys_of(&"swap_weapon")).contains_exactly([KEY_F])
	assert_str(_pad_of(&"swap_weapon")).is_equal("button 11")
	var seen := {}
	for action in GAMEPLAY:
		for key in _keys_of(action):
			(
				assert_bool(seen.has(key))
				. override_failure_message("%s and %s share a key" % [seen.get(key), action])
				. is_false()
			)
			seen[key] = action


func _keys_of(action: StringName) -> Array[int]:
	var keys: Array[int] = []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			keys.append((event as InputEventKey).physical_keycode)
	return keys


func _has_mouse_button(action: StringName, button: int) -> bool:
	for event in InputMap.action_get_events(action):
		if (
			event is InputEventMouseButton
			and (event as InputEventMouseButton).button_index == button
		):
			return true
	return false


func _pad_of(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		if _pad_key(event) != "":
			return _pad_key(event)
	return ""


func _pad_key(event: InputEvent) -> String:
	if event is InputEventJoypadButton:
		return "button %d" % (event as InputEventJoypadButton).button_index
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return "axis %d%s" % [motion.axis, "+" if motion.axis_value > 0.0 else "-"]
	return ""
