class_name FlashWebProbe
extends Node
## A browser test's view of the muzzle flash (`tools/web_smoke/flash.py`). It does nothing unless
## the page was opened with `?probe=flash` (a visitor never meets it), and then, on the web only:
##
## - `window.deadnight.flashGive = "<weapon id>"` gives the player that weapon and puts it in the
##   hand; `window.deadnight.flashHave` says which one is in the hand now;
## - while `window.deadnight.flashRecord` is true, every frame drawn while a flash is up (and a
##   few after it) adds one JSON row to `window.deadnight.flashRows`: the page's clock, the frame
##   time, whether the flash is up, its age, and, when `window.deadnight.flashPixels` is true, what
##   it did to the picture (`FlashMeter`: size, brightness, the light's wash).
## It only reads and measures: no game code depends on it.

## Frames recorded after the last frame a flash was up, so a test sees it go.
const TAIL_FRAMES := 3

var _object: JavaScriptObject
var _rows: JavaScriptObject
var _meter := FlashMeter.new()
var _tail := 0
var _delta := 0.0


func _ready() -> void:
	set_process(false)
	if not OS.has_feature("web"):
		return
	var asked: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('probe')")
	if str(asked) != "flash":
		return
	_object = JavaScriptBridge.get_interface("window").deadnight
	_rows = JavaScriptBridge.create_object("Array")
	_object.flashRows = _rows
	_object.flashRecord = false
	_object.flashPixels = true
	_object.flashGive = ""
	_object.flashHave = ""
	# After the camera rig and the effects: the flash is where this frame draws it.
	process_priority = 1000
	set_process(true)
	RenderingServer.frame_post_draw.connect(_after_draw)


func _process(delta: float) -> void:
	_delta = delta
	var wanted := str(_object.flashGive)
	if wanted == "" or wanted == str(_object.flashHave):
		return
	var screen := UIRouter.top() as NightScreen
	if screen == null or screen.night == null or screen.night.server == null:
		return
	var id := screen.night.state.player_id
	screen.night.server.combat.apply(CombatAction.give_weapon(id, StringName(wanted)))
	screen.night.server.combat.apply(CombatAction.equip(id, StringName(wanted)))
	_object.flashHave = wanted


func _after_draw() -> void:
	if FlashMeter.busy or not _object.flashRecord:
		return
	var flash: MuzzleFlash = null
	for node in get_tree().root.find_children("*", "MuzzleFlash", true, false):
		if (node as MuzzleFlash).is_up():
			flash = node
			break
	if flash != null:
		_tail = TAIL_FRAMES
	elif _tail > 0:
		_tail -= 1
	else:
		return
	var row: Dictionary
	if flash != null and _object.flashPixels:
		row = _meter.measure(get_viewport(), flash)
	else:
		row = {"up": flash != null}
		if flash != null:
			row["age"] = flash.age
			row["light"] = flash.light.visible
	row["t"] = Time.get_ticks_usec() / 1000.0
	row["delta_ms"] = _delta * 1000.0
	row["frame"] = Engine.get_frames_drawn()
	_rows.push(JSON.stringify(row))
