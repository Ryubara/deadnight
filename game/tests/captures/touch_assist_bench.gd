extends Node
## The touch aim assist in a browser (#286): the game's own night screen with the touch layer
## forced on, a zombie held beside the crosshair (`AssistRig`), and what a browser run needs to
## drive it with real touches: where the look area and the Aim button are, how far the thumb should
## drag next, and what happened (the crosshair's distance from the chest, shots, friction). Not
## part of the game: `tools/web_smoke/touch_assist.py` exports a copy of the project that starts on
## this scene and reads `window.__assist`. The page's query sets the assist:
## `?touch=1&assist=1&auto=1`.

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"
## Where the look finger lands, as shares of the touch layer's size.
const LOOK_AT := Vector2(0.7, 0.3)
## The view counts as settled when the lens has moved less than this (metres) for `SETTLED_FRAMES`
## frames in a row; the wait gives up after `SETTLE_LIMIT` frames.
const SETTLED_AT := 0.0005
const SETTLED_FRAMES := 20
const SETTLE_LIMIT := 900

var _night: Night
var _controls: TouchControls
var _rig: AssistRig
var _frames: Array[float] = []
var _last_usec := 0
var _since := 0.0
var _grip_lost := 0
var _started := false


func _ready() -> void:
	_run.call_deferred()


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_usec != 0:
		_frames.append((now - _last_usec) / 1000.0)
	_last_usec = now
	_since += delta
	if _rig != null and _since >= 0.05:
		_since = 0.0
		_publish(_started)


func _run() -> void:
	var query := _query()
	await get_tree().process_frame
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	await screen.night.ready_to_play
	_night = screen.night
	# Through the settings, as the player does: the assist re-reads them whenever one changes.
	var settings := get_tree().root.get_node("Settings")
	settings.set_value(SettingsService.TOUCH_AIM_ASSIST, float(query.get("assist", "1")) > 0.0)
	settings.set_value(SettingsService.TOUCH_AUTO_FIRE, int(query.get("auto", "0")))
	# No mouse here, as on a phone: the player asked for the lock when it entered the night, and a
	# lock given up later reads as lost (the night pauses, the touch layer goes dead, the look
	# never turns: #490). So the request is withdrawn, not only the mode set.
	_night.player().capture_mouse = false
	_night.player().grip.want(false)
	_night.player().grip_lost.connect(func() -> void: _grip_lost += 1)
	_controls = screen.find_children("*", "TouchControls", true, false)[0] as TouchControls
	_rig = AssistRig.new(_night)
	if not await _rig.start(get_tree()):
		_eval("window.__assist = {failed: 'no zombie came out'};")
		return
	await _settle_view()
	# The zombie was put beside the crosshair while the shoulder camera was still easing into
	# place: put it again, so every run starts the same distance off and the thumb has to drag.
	_rig.place()
	for _i in 30:
		await get_tree().process_frame
	_frames.clear()
	_started = true
	_publish(true)


## Waits until the shoulder camera has stopped easing (the lens is still for a while).
func _settle_view() -> void:
	var rig := _night.player().camera_rig
	var last := rig.aim_transform().origin
	var still := 0
	for _i in SETTLE_LIMIT:
		await get_tree().process_frame
		var now := rig.aim_transform().origin
		still = still + 1 if now.distance_to(last) < SETTLED_AT else 0
		last = now
		if still >= SETTLED_FRAMES:
			return


## The state of the run as the page reads it. `ready` is true once the zombie is held.
func _publish(ready: bool) -> void:
	if not OS.has_feature("web"):
		return
	var to_page := func(point: Vector2) -> Array:
		var window := get_viewport().get_final_transform() * point
		var scale := _device_ratio()
		return [window.x / scale, window.y / scale]
	var canvas := get_viewport().get_visible_rect().size
	var step := get_viewport().get_final_transform().basis_xform(_rig.thumb_step(canvas.y))
	var data := {
		"ready": ready and not _night.state.zombies.is_empty(),
		"look_from": to_page.call(canvas * LOOK_AT),
		"aim": to_page.call(_controls.button_circle(TouchLayout.AIM)["centre"]),
		"step_px": [step.x / _device_ratio(), step.y / _device_ratio()],
		"lateral": _rig.lateral(),
		"stop": AssistRig.STOP_METRES,
		"shots": _night.state.shots,
		"friction": _night.assist.friction(),
		"touch": _night.assist.is_touch(),
		"strength": _night.assist.strength,
		"auto_fire": _night.assist.auto_fire,
		"max_frame_ms": snappedf(_frames.max() if not _frames.is_empty() else 0.0, 0.1),
		"kills": _night.state.kills,
		"zombies_seen": _night.state.zombies.size(),
		"wall_m": _wall_before_the_chest(),
		"paused": _night.is_paused(),
		"grip_lost": _grip_lost,
		"yaw": snappedf(_night.player().camera_rig.yaw, 0.0001),
	}
	_eval("window.__assist = %s;" % JSON.stringify(data))


## Metres from the lens to the first wall on the way to the zombie's chest (-1 when clear): a wall
## in front of the zombie is why the assist would rightly ignore it.
func _wall_before_the_chest() -> float:
	var view := _night.player().camera_rig.aim_transform()
	var chest := _rig.zombie.position + Vector3.UP * AssistRig.CHEST
	var probe := WorldProbe.new(get_viewport().world_3d.direct_space_state)
	return snappedf(probe.distance(view.origin, chest), 0.01)


func _device_ratio() -> float:
	return maxf(float(JavaScriptBridge.eval("window.devicePixelRatio", true)), 1.0)


func _eval(script: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(script)
	else:
		print("ASSIST ", script)


## The page's query as `{name: value}`.
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
