extends Node
## The bot command wheel in the game's own night screen, for captures and for a browser run (#642).
## The orders go to a recorder (`BotOrders` is #641's); the input is real: a window sends it
## itself, a browser run sends it from outside and reads `window.__wheel`.
##
##     gds godot -- --path game res://tests/captures/bot_wheel_bench.tscn --resolution 1920x1080
##         -- --mode=desktop|pad|touch --out=<abs>/wheel.png [--pick=hold]
##
## `--mode` says which device opens the wheel: `desktop` holds Q and moves the mouse, `pad` holds
## the d-pad left on a pad that is not device 0 and pushes the right stick, `touch` shows the touch
## layer and holds the BOTS button with a drag. The picture is the window's, taken with the wheel
## open over the entry `--pick` (follow, roam or hold).
## In a browser the page's query is `?touch=1`, and nothing is sent: the page is driven from
## outside.

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"
const PAD := 3
const OPEN_SECONDS := 0.6
const SETTLE_SECONDS := 0.8

var heard: Array[Dictionary] = []

var _screen: NightScreen
var _controls: TouchControls
var _since := 0.0
var _ready_to_drive := false
var _published := false


func _ready() -> void:
	_run.call_deferred()


func _process(delta: float) -> void:
	_since += delta
	if _screen != null and _since >= 0.05:
		_since = 0.0
		_publish()


func _run() -> void:
	var args := NetArgs.new()
	var query := _query()
	var touch: bool = args.get_string("mode") == "touch" or query.get("touch", "0") == "1"
	TouchMode.device_is_touch = touch
	await get_tree().process_frame
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	_screen = UIRouter.top() as NightScreen
	await _screen.night.ready_to_play
	var player := _screen.night.player()
	# No real mouse here: a window on a private desktop, or a phone.
	player.capture_mouse = false
	player.grip.want(false)
	get_tree().root.get_node("Settings").set_value(
		SettingsService.LEFT_HANDED, query.get("left", "0") == "1"
	)
	_controls = _screen.find_children("*", "TouchControls", true, false)[0] as TouchControls
	_controls.refresh()
	_screen.wheel.link = BotOrderLink.new()
	_screen.wheel.link.issuer = _record
	for _i in 60:
		await get_tree().process_frame
	_ready_to_drive = true
	if args.get_string("mode") != "":
		await _drive(args)
		get_tree().quit()


func _record(order: StringName, issuer_id: int, at: Vector3) -> Dictionary:
	heard.append({"order": order, "issuer": issuer_id})
	return {&"type": &"order", &"order": order, &"at": at}


## Opens the wheel the way the mode's device does and takes the picture.
func _drive(args: NetArgs) -> void:
	var out := args.get_string("out")
	var pick := StringName(args.get_string("pick", "hold"))
	var toward := BotWheel.direction_of(pick)
	match args.get_string("mode"):
		"desktop":
			_key(true)
			await _wait(OPEN_SECONDS)
			var motion := InputEventMouseMotion.new()
			motion.relative = toward * BotWheel.MOUSE_REACH
			motion.position = Vector2(960.0, 540.0)
			get_viewport().push_input(motion, true)
		"pad":
			_pad_button(true)
			await _wait(OPEN_SECONDS)
			_stick(toward)
		"touch":
			var start := _button_at_window()
			_touch(start, true)
			await _wait(OPEN_SECONDS)
			var drag := InputEventScreenDrag.new()
			var window := get_viewport().get_final_transform()
			drag.position = start + window.basis_xform(toward * BotWheel.TOUCH_REACH)
			drag.relative = window.basis_xform(toward * BotWheel.TOUCH_REACH)
			Input.parse_input_event(drag)
	await _wait(SETTLE_SECONDS)
	if out != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out)
		print("SAVED ", out)
	print("HOVERED ", _screen.wheel.model.hovered())
	match args.get_string("mode"):
		"desktop":
			_key(false)
		"pad":
			_pad_button(false)
			_stick(Vector2.ZERO)
		"touch":
			_touch(_button_at_window(), false)
	await _wait(SETTLE_SECONDS)
	print("HEARD ", heard)


## Real seconds: the wheel opens by the time held, not by frames, and a window's frame rate varies.
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _bound(action: StringName, pad: bool) -> InputEvent:
	for event in InputMap.action_get_events(action):
		var is_pad := event is InputEventJoypadButton
		if is_pad == pad and (is_pad or event is InputEventKey):
			var copy := event.duplicate() as InputEvent
			if pad:
				copy.device = PAD
			return copy
	return null


func _key(pressed: bool) -> void:
	var event := _bound(&"bot_wheel", false) as InputEventKey
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _pad_button(pressed: bool) -> void:
	var event := _bound(&"bot_wheel", true) as InputEventJoypadButton
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _stick(push: Vector2) -> void:
	for axis in [[JOY_AXIS_RIGHT_X, push.x], [JOY_AXIS_RIGHT_Y, push.y]]:
		var motion := InputEventJoypadMotion.new()
		motion.device = PAD
		motion.axis = axis[0]
		motion.axis_value = axis[1]
		Input.parse_input_event(motion)
	Input.flush_buffered_events()


func _touch(at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = at
	event.pressed = pressed
	Input.parse_input_event(event)


func _button_at_window() -> Vector2:
	var centre: Vector2 = _controls.button_circle(TouchLayout.BOT_WHEEL)[&"centre"]
	return get_viewport().get_final_transform() * centre


## What a browser run reads: where the buttons are in page pixels, whether the wheel is open and
## over what, and the orders the recorder heard.
func _publish() -> void:
	if not OS.has_feature("web") or _controls == null:
		return
	var ratio := maxf(float(JavaScriptBridge.eval("window.devicePixelRatio", true)), 1.0)
	var window := get_viewport().get_final_transform()
	var buttons := {}
	var zoom := window.get_scale().x / ratio
	for id: StringName in TouchLayout.buttons(_controls.safe_rect(), _controls.touch_scale):
		var circle := _controls.button_circle(id)
		var at := window * (circle[&"centre"] as Vector2)
		buttons[id] = [at.x / ratio, at.y / ratio, float(circle[&"radius"]) * zoom]
	var model := _screen.wheel.model
	var data := {
		"ready": _ready_to_drive,
		"buttons": buttons,
		"holding": model.is_holding(),
		"open": model.is_open(),
		"hovered": String(model.hovered()),
		"current": String(model.current),
		"heard": heard,
		"paused": _screen.night.is_paused(),
		"yaw": _screen.night.player().camera_rig.yaw,
		"pings": _screen.night.state.frame.get("pings", {}).size(),
		"mirrored": _controls.is_mirrored(),
		"canvas": [_controls.size.x, _controls.size.y],
	}
	JavaScriptBridge.eval("window.__wheel = %s;" % JSON.stringify(data))
	if not _published:
		_published = true
		print("WHEEL first ", JSON.stringify(data))


func _query() -> Dictionary:
	var parsed := {}
	if not OS.has_feature("web"):
		return parsed
	var search: Variant = JavaScriptBridge.eval("window.location.search", true)
	for pair in String(search).trim_prefix("?").split("&"):
		var parts := pair.split("=", true, 1)
		if parts.size() == 2:
			parsed[parts[0]] = parts[1]
	return parsed
