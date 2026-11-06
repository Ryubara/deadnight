extends Node
## Whether a page that asks for the probes plays the helicopter drop when the night is opened the
## way the benches open it (#1323): the night screen pushed on the router with no `Main`. Reads
## `NightScreen.arrival_enabled` the moment the bench runs, then follows `Night.arrival` and
## `Night.is_arriving()` for a while, and publishes them as `window.__arrival`.
## `tools/web_smoke/arrival_bench.py` exports a copy of the project that starts on this scene.

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"
## How long the night is followed, in seconds.
const FOLLOW_S := 6.0

var _data := {}
var _night: Night
var _controls: TouchControls
var _rig: AssistRig


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_data["probe_flag"] = _eval("!!window.deadnight_probe")
	_data["enabled_at_start"] = NightScreen.arrival_enabled
	_data["asked_at_start"] = WebProbe.asked()
	_publish()
	await get_tree().process_frame
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	await screen.night.ready_to_play
	var night := screen.night
	_data["night_arrival"] = night.arrival
	_data["arriving_when_ready"] = night.is_arriving()
	var seen_arriving := night.is_arriving()
	var waited := 0.0
	while waited < FOLLOW_S:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
		seen_arriving = seen_arriving or night.is_arriving()
		_data["arriving_seen"] = seen_arriving
		_publish()
	_data["done"] = true
	_publish()


func _publish() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__arrival = %s;" % JSON.stringify(_data))
	else:
		print("ARRIVAL ", JSON.stringify(_data))


func _eval(script: String) -> Variant:
	return JavaScriptBridge.eval(script, true) if OS.has_feature("web") else null
