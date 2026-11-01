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
	&"pause",
	&"throw_grenade",
	&"toss_grenade",
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
