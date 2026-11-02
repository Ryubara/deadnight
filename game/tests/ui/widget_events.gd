class_name WidgetEvents
extends RefCounted
## Real input events for widget tests: a key, a d-pad or face button, and a mouse click, sent the
## way the engine would deliver them. Each waits a frame after every event, so a control's own
## handling (and its springs) has run before the test looks.
##
## Keys and joypad buttons go through `Input.parse_input_event`, which works in the headless
## runner. A mouse event goes straight to the viewport in its own coordinates: the headless window
## is 64 x 64 pixels, so a window position would be scaled by the stretch before it arrived.


static func key(tree: SceneTree, keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await tree.process_frame


static func button(tree: SceneTree, index: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = index
		event.pressed = pressed
		Input.parse_input_event(event)
		await tree.process_frame


## A left click at `point` (in the control's own coordinates) on `control`.
static func click(tree: SceneTree, control: Control, point: Vector2) -> void:
	var at := control.get_global_transform_with_canvas() * point
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		control.get_viewport().push_input(event, true)
		await tree.process_frame


## A click at `share` of the control's width, halfway down.
static func click_at_share(tree: SceneTree, control: Control, share: float) -> void:
	await click(tree, control, Vector2(control.size.x * share, control.size.y * 0.5))
