extends Node
## The first run on a phone, for captures: the hints over the controls (drag to move, drag to look),
## the interact hint and the tap mark on the prompt card at a door, and the same after the controls
## were used (the hints gone, the card still a tap mark). Not part of the game.
##
## `godot --path game res://tests/captures/touch_hints_tour.tscn -- --out=<folder>
## [--window=844x390] [--scale=2] [--notch]` saves `first-run.png`, `door.png`,
## `used-stick-look.png` and `used.png`. The window is sized like a phone held sideways (the
## project's canvas, 1920 x 1080 or more, stretched to it), `--scale` times its pixels so the type
## can be read, and the touches are real events sent to it. A Movie Maker frame is always
## 1920 x 1080, hence stills.

const DOOR := &"door_concession"
const AT_DOOR := Vector3(0.0, 0.1, -2.0)
const NOTCH := Vector4(96.0, 0.0, 96.0, 24.0)
const HOLD_FRAMES := 40
const SETTLE_FRAMES := 4

var _night: Night
var _controls: TouchControls


func _ready() -> void:
	var args := _args()
	var window := _pair(str(args.get("window", "844x390")))
	get_window().size = Vector2i(window * float(args.get("scale", "2")))
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	TouchMode.device_is_touch = true
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	_controls = TouchControls.new()
	_controls.state = hud.state
	# A first run every time: nothing is remembered in the player's settings.
	_controls.persist_hints = false
	if args.has("notch"):
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
	await _snap(args, "first-run")
	_night.player().teleport(_night.world.door_points(DOOR)[0] + AT_DOOR)
	_night.state.apply_events(_night.server.rules.apply(RulesAction.grant_points(1, 900)))
	await _hold(HOLD_FRAMES)
	await _snap(args, "door")
	var rest := (
		_controls.safe_rect().position + Vector2(330.0, _controls.safe_rect().size.y - 330.0)
	)
	_touch(0, rest)
	_drag(0, rest + Vector2(0.0, -60.0), Vector2(0.0, -60.0))
	_touch(1, Vector2(1700.0, 330.0))
	_drag(1, Vector2(1760.0, 330.0), Vector2(60.0, 0.0))
	await _hold(HOLD_FRAMES)
	await _snap(args, "used-stick-look")
	_touch(0, Vector2.ZERO, false)
	_touch(1, Vector2.ZERO, false)
	_touch(2, _controls.button_circle(TouchLayout.INTERACT)[&"centre"])
	await _hold(HOLD_FRAMES)
	await _snap(args, "used")
	get_tree().quit()


func _snap(args: Dictionary, pose: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var out := "%s/%s.png" % [str(args.get("out", "user://")), pose]
	image.save_png(out)
	print("saved ", out, " ", image.get_size(), " canvas ", get_viewport().get_visible_rect().size)


func _args() -> Dictionary:
	var found := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		found[parts[0]] = parts[1] if parts.size() > 1 else true
	return found


func _pair(text: String) -> Vector2:
	var parts := text.split("x")
	return Vector2(float(parts[0]), float(parts[1]))


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
