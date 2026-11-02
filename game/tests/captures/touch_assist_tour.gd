extends Node
## The touch aim assist at work, for captures (#286): a zombie stands 7 m off, a little to the left
## of the crosshair, and a thumb drags the view toward it and stops short, then holds Aim. Without
## the assist the crosshair stays beside the zombie; with it the view is pulled onto the chest and,
## with auto-fire on, the gun fires by itself. Not part of the game. Run with Movie Maker:
##
## `godot --path game res://tests/captures/touch_assist_tour.tscn --resolution 2340x1080
## --fixed-fps 10 --write-movie out.png --quit-after 70 -- [--strength=0.5] [--auto=1]`
##
## `--strength` is the assist (0 is off, the "before"), `--auto` the auto-fire choice (0 off, 1
## while aiming, 2 always). The marks it prints say which frames are the poses.

## The most drag events one swipe takes, one per frame.
const MAX_DRAG_STEPS := 40
const HOLD_FRAMES := 15
const LOOK_FINGER := 3
const AIM_FINGER := 4
const LOOK_FROM := Vector2(1700.0, 300.0)

var _night: Night
var _controls: TouchControls
var _rig: AssistRig


func _ready() -> void:
	var args := _args()
	TouchMode.device_is_touch = true
	UIInputMode.touch = true
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	_controls = TouchControls.new()
	_controls.state = hud.state
	_controls.persist_hints = false
	_controls.safe_insets_changed.connect(_fit_hud.bind(hud))
	layer.add_child(_controls)
	add_child(layer)
	for id in TouchHints.ORDER:
		_controls.hints.mark_used(id)
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	await _night.start(Night.Mode.HUMAN)
	_night.touch_active = _controls.is_active
	_controls.look_gain = func() -> float: return _night.assist.friction()
	_night.assist.strength = float(args.get("strength", "0.5"))
	_night.assist.auto_fire = int(args.get("auto", "0"))
	var player := _night.player()
	player.capture_mouse = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rig = AssistRig.new(_night)
	if not await _rig.start(get_tree()):
		push_error("no zombie came out")
		get_tree().quit(1)
		return
	await _hold(HOLD_FRAMES)
	print("start frame ", Engine.get_frames_drawn())
	await _drag_toward_the_zombie()
	await _hold(HOLD_FRAMES)
	print("dragged frame ", Engine.get_frames_drawn())
	_touch(AIM_FINGER, _controls.button_circle(TouchLayout.AIM)[&"centre"])
	await _hold(HOLD_FRAMES)
	print("aiming frame ", Engine.get_frames_drawn())
	await _hold(HOLD_FRAMES * 2)
	print(
		(
			"end frame %d: shots %d, crosshair %.2f m from the chest, friction %.2f"
			% [
				Engine.get_frames_drawn(),
				_night.state.shots,
				_rig.lateral(),
				_night.assist.friction(),
			]
		)
	)
	get_tree().quit()


## The thumb swipes toward the zombie and stops as soon as the crosshair is near it, beside it.
func _drag_toward_the_zombie() -> void:
	_touch(LOOK_FINGER, LOOK_FROM)
	var at := LOOK_FROM
	for _i in MAX_DRAG_STEPS:
		if _rig.lateral() < AssistRig.STOP_METRES:
			break
		var step := _rig.thumb_step(1080.0)
		at += step
		_drag(LOOK_FINGER, at, step)
		await get_tree().process_frame
	_touch(LOOK_FINGER, at, false)


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


func _args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var parts := arg.substr(2).split("=", true, 1)
			parsed[parts[0]] = parts[1]
	return parsed
