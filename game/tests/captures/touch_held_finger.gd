extends Node
## A thumb held on the stick's side through the helicopter drop (the touch layer is down), then the
## layer comes up and the thumb walks (#1329): the stick's ring and the walk it makes, on a phone's
## canvas (2337 x 1080 units for an 844 x 390 page). Before the fix the layer never read the finger,
## so there was no ring and no walk.
## Not part of the game. Run in a window with the kit's launcher:
## `gds godot -- --path game res://tests/captures/touch_held_finger.tscn -- --out=<folder>`
## It writes `held_down.png` (the thumb rests, the layer is down), `held_up.png` (the layer is up)
## and `held_walk.png` (the thumb pushed right), prints the walk, and quits.

const PAGE := Vector2i(2337, 1080)
const SETTLE_FRAMES := 12
const THUMB := Vector2(330.0, 760.0)
const PUSH := Vector2(110.0, -40.0)

var _viewport: SubViewport
var _controls: TouchControls
var _out := "."


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
	TouchMode.device_is_touch = true
	_viewport = SubViewport.new()
	_viewport.size = PAGE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var ground := ColorRect.new()
	ground.color = Color(0.18, 0.2, 0.26)
	ground.size = Vector2(PAGE)
	_viewport.add_child(ground)
	_controls = TouchControls.new()
	_controls.persist_hints = false
	_viewport.add_child(_controls)
	_controls.size = Vector2(PAGE)
	_controls.refresh()
	_controls.live = false
	_touch(THUMB, true)
	await _settle()
	await _save("held_down")
	_controls.live = true
	await _settle()
	await _save("held_up")
	_drag(THUMB + PUSH)
	await _settle()
	await _save("held_walk")
	print("walk ", Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back"))
	_touch(THUMB + PUSH, false)
	TouchMode.device_is_touch = null
	get_tree().quit()


func _touch(at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = at
	event.pressed = pressed
	_viewport.push_input(event)


func _drag(to: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = 0
	event.position = to
	event.relative = PUSH
	_viewport.push_input(event)


func _settle() -> void:
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	_viewport.get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("saved ", name)
