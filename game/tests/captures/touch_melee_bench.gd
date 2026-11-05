extends Node
## The quick melee on a phone in a browser (#588): the game's own night screen with the touch layer
## forced on and one zombie held in reach of the blow, and what a browser run needs to drive it with
## real touches: where the melee button is (in page pixels), and what happened (the blows the server
## made, the zombies it hurt, whether the night paused). Not part of the game:
## `tools/web_smoke/touch_melee.py` exports a copy of the project that starts on this scene and
## reads `window.__melee`. The page's query: `?touch=1` and `left=1` for a left hand.

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"
## How far ahead of the player the zombie is held (metres): inside the blow's 1.6 m.
const REACH_AHEAD := 1.1
const BEHIND := 30.0
const SETTLED_AT := 0.0005
const SETTLED_FRAMES := 20
const SETTLE_LIMIT := 900

var _night: Night
var _controls: TouchControls
var _blows := 0
var _hurt := 0
var _grip_lost := 0
## What the server answered, with the page's clock (`performance.now()`, ms) and the server's own
## clock: `blow` or `reject:<reason>`. The browser run lines it up with the taps it sent.
var _log: Array = []
var _since := 0.0
var _started := false


func _ready() -> void:
	_run.call_deferred()


func _process(delta: float) -> void:
	_since += delta
	if _night != null and _since >= 0.05:
		_since = 0.0
		_publish()


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
	var settings := get_tree().root.get_node("Settings")
	settings.set_value(SettingsService.LEFT_HANDED, query.get("left", "0") == "1")
	# No mouse here, as on a phone: the lock asked for on entering the night is withdrawn.
	_night.player().capture_mouse = false
	_night.player().grip.want(false)
	_night.player().grip_lost.connect(func() -> void: _grip_lost += 1)
	_night.state.event_received.connect(_count)
	_controls = screen.find_children("*", "TouchControls", true, false)[0] as TouchControls
	_night.state.apply_events(_night.server.rules.apply(RulesAction.skip_break()))
	for _i in 900:
		await get_tree().process_frame
		if not _night.server.sim.zombies.is_empty() and not _night.state.zombies.is_empty():
			break
	await _settle_view()
	_night.ticked.connect(_hold)
	_started = true


func _count(event: Dictionary) -> void:
	match event["type"]:
		&"quick_melee":
			_blows += 1
			_note("blow")
		&"fire_rejected":
			_note("reject:%s" % event["reason"])
		&"damage_dealt":
			if event["melee"]:
				_hurt += 1


func _note(what: String) -> void:
	if not OS.has_feature("web"):
		return
	var page_ms := float(JavaScriptBridge.eval("performance.now()", true))
	_log.append([what, snappedf(page_ms, 0.1), snappedf(_night.server.combat.now, 0.001)])


## Every tick: the first zombie stays in reach of the blow, the others stand behind.
func _hold() -> void:
	var player := _night.player()
	var look := -player.camera_rig.aim_transform().basis.z
	var ahead := Vector3(look.x, 0.0, look.z).normalized()
	var first := true
	for body: ZombieBody in _night.server.sim.zombies.values():
		body.velocity = Vector3.ZERO
		if first:
			body.position = player.global_position + ahead * REACH_AHEAD
			first = false
		else:
			body.position = player.global_position + Vector3(0.0, 0.0, BEHIND)


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


func _publish() -> void:
	if not OS.has_feature("web"):
		return
	var ratio := maxf(float(JavaScriptBridge.eval("window.devicePixelRatio", true)), 1.0)
	var centre: Vector2 = _controls.button_circle(TouchLayout.STRIKE)[&"centre"]
	var window := get_viewport().get_final_transform() * centre
	var buttons := {}
	var zoom := get_viewport().get_final_transform().get_scale().x / ratio
	for id: StringName in TouchLayout.buttons(_controls.safe_rect(), _controls.touch_scale):
		var circle := _controls.button_circle(id)
		var at := get_viewport().get_final_transform() * (circle[&"centre"] as Vector2)
		buttons[id] = [at.x / ratio, at.y / ratio, float(circle[&"radius"]) * zoom]
	var data := {
		"buttons": buttons,
		"ready": _started,
		"melee": [window.x / ratio, window.y / ratio],
		"blows": _blows,
		"log": _log,
		"hurt": _hurt,
		"paused": _night.is_paused(),
		"grip_lost": _grip_lost,
		"mirrored": _controls.is_mirrored(),
		"touch": _night.assist.is_touch(),
		"zombies": _night.state.zombies.size(),
		"canvas": [_controls.size.x, _controls.size.y],
		"viewport":
		[get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"scale": _controls.touch_scale,
		"safe":
		[
			_controls.safe_rect().position.x,
			_controls.safe_rect().position.y,
			_controls.safe_rect().size.x,
			_controls.safe_rect().size.y
		],
		"aim": _controls.button_circle(TouchLayout.AIM)[&"centre"],
	}
	JavaScriptBridge.eval("window.__melee = %s;" % JSON.stringify(data))


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
