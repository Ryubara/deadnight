extends Node
## The night on a phone, for captures: the touch controls over the HUD at rest, at a door that can
## be opened (the interact button names it), and in use (stick pushed to sprint, thumb on Fire).
## Pass `-- --notch` to leave room for a notch. Not part of the game. Run with Movie Maker:
## `godot --path game res://tests/captures/touch_tour.tscn --resolution 2340x1080 --fixed-fps 10
## --write-movie out.png --quit-after 70`; frames 5, 20, 35, 50 and 65 are the five poses.

const DOOR := &"door_concession"
const AT_DOOR := Vector3(0.0, 0.1, -2.0)
const NOTCH := Vector4(96.0, 0.0, 96.0, 24.0)
const HOLD_FRAMES := 15

var _night: Night
var _controls: TouchControls


func _ready() -> void:
	TouchMode.device_is_touch = true
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	_controls = TouchControls.new()
	_controls.state = hud.state
	if "--notch" in OS.get_cmdline_user_args():
		_controls.insets_override = NOTCH
	_controls.safe_insets_changed.connect(_fit_hud.bind(hud))
	layer.add_child(_controls)
	var prompt_layer := CanvasLayer.new()
	prompt_layer.layer = TouchRotatePrompt.LAYER
	prompt_layer.add_child(TouchRotatePrompt.new())
	add_child(prompt_layer)
	add_child(layer)
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	await _night.start(Night.Mode.HUMAN)
	_night.state.apply_events(_night.server.rules.apply(RulesAction.skip_break()))
	await _hold(HOLD_FRAMES)
	print("rest")
	_night.player().teleport(_night.world.door_points(DOOR)[0] + AT_DOOR)
	_night.state.apply_events(_night.server.rules.apply(RulesAction.grant_points(1, 900)))
	await _hold(HOLD_FRAMES)
	print("door")
	_touch(0, Vector2(330.0, 760.0))
	_drag(0, Vector2(330.0, 600.0), Vector2(0.0, -160.0))
	_touch(1, _controls.button_circle(TouchLayout.FIRE)[&"centre"])
	await _hold(HOLD_FRAMES)
	print("sprint and fire")
	_touch(1, _controls.button_circle(TouchLayout.FIRE)[&"centre"], false)
	_touch(0, Vector2.ZERO, false)
	_touch(2, _controls.button_circle(TouchLayout.INTERACT)[&"centre"])
	await _hold(HOLD_FRAMES)
	print("use")
	get_tree().quit()


func _fit_hud(insets: Vector4, hud: Hud) -> void:
	hud.offset_left = insets.x
	hud.offset_top = insets.y
	hud.offset_right = -insets.z
	hud.offset_bottom = -insets.w


func _touch(index: int, point: Vector2, pressed := true) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = get_viewport().get_final_transform() * point
	event.pressed = pressed
	Input.parse_input_event(event)


func _drag(index: int, point: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = get_viewport().get_final_transform() * point
	event.relative = get_viewport().get_final_transform().basis_xform(relative)
	Input.parse_input_event(event)


func _hold(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
