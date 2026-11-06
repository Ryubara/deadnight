extends Node
## The challenge card on a phone's night, over the real HUD and the real touch controls with a full
## room (#1299): `--people` people (8 at most) and `--bots` bots on top, perks and the point gains
## up, the card up with three lines, and the picture taken of the window. Not part of the game.
##
## On the desktop, in a window of the page's size, with the kit's launcher:
##
##     gds godot -- --path game res://tests/captures/challenge_card_phone.tscn --resolution 1334x750
##         -- --out=<folder>/card.png [--scale=1.25] [--people=8] [--bots=7] [--left] [--gains]
##
## It prints one line with the card's and the players' column's rectangles and quits.
##
## In a browser (`tools/web_smoke/challenge_card_phone.py`, which exports a copy that starts on this
## scene) the flags are the URL's query (`?left=1`), the interface size runs through 0.8, 1.0 and
## 1.25, and each case is published as `window.__card = {case, index, canvas, card, parts, held}`
## (units of the canvas, `x,y,w,h`) for the probe to screenshot and measure; the scene waits for
## `window.__card_ack = index` before the next one, then publishes `{done: true}`.

const NOTCH := Vector4(96.0, 0.0, 96.0, 24.0)
const SETTLE_FRAMES := 12
## How many frames a web case waits for the probe to answer, at most.
const ACK_FRAMES := 1200
## How long the card stays up, seconds: the probe takes its time on a slow page.
const HOLD_SECONDS := 600.0
const SCALES: Array[float] = [0.8, 1.0, 1.25]
const WORDS := "Put down 50 zombies with the submachine gun"

var _hud: Hud
var _fixture: HudFixture
var _controls: TouchControls
var _web := OS.has_feature("web")
var _index := 0


func _ready() -> void:
	var args := _args()
	TouchMode.device_is_touch = true
	UIInputMode.track(InputEventScreenTouch.new())
	HudTuning.current().challenge_hold = HOLD_SECONDS
	_build(args)
	if args.has("left"):
		get_tree().root.get_node("Settings").set_value(SettingsService.LEFT_HANDED, true)
	await get_tree().process_frame
	_controls.refresh()
	_fixture.into_round_one()
	_hud.state.set_area("The Concession Stand", "Light the booth to open the back lot")
	_fixture.give_perks(_fixture.rules.tuning.economy.max_tonics)
	if _web:
		for scale in SCALES:
			await _case(scale, "ui%s" % scale, true)
		JavaScriptBridge.eval("window.__card = {done: true};")
		return
	await _case(float(args.get("scale", 1.0)), "one", args.has("gains"))
	var out := String(args.get("out", ""))
	if out != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out)
		print("SAVED ", out)
	get_tree().quit()


func _args() -> Dictionary:
	var found := {}
	for arg in OS.get_cmdline_user_args():
		var parts := String(arg).trim_prefix("--").split("=", true, 1)
		found[parts[0]] = parts[1] if parts.size() > 1 else true
	if _web:
		var query := str(JavaScriptBridge.eval("location.search"))
		for pair in query.trim_prefix("?").split("&"):
			if pair != "":
				found[pair.get_slice("=", 0)] = pair.get_slice("=", 1) if "=" in pair else true
	return found


func _build(args: Dictionary) -> void:
	get_window().content_scale_factor = float(args.get("scale", 1.0))
	var layer := CanvasLayer.new()
	add_child(layer)
	var ground := ColorRect.new()
	ground.color = Color(0.18, 0.2, 0.26)
	ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(ground)
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(host)
	var people := clampi(int(args.get("people", 8)), 1, NightHost.MAX_PLAYERS)
	_fixture = HudFixture.make(host, people, 1958, false, int(args.get("bots", 7)))
	_hud = _fixture.hud
	_controls = TouchControls.new()
	_controls.state = _hud.state
	_controls.zones = _hud.slots.touch_zones
	_controls.finger_units = func() -> float: return MenuScale.tap_units(get_window(), true)
	_controls.active_changed.connect(func(active: bool) -> void: _hud.touch_layout = active)
	_controls.mirrored_changed.connect(func(on: bool) -> void: _hud.mirrored = on)
	_controls.safe_insets_changed.connect(
		func(insets: Vector4) -> void: _hud.set_safe_insets(insets)
	)
	_controls.insets_override = NOTCH
	_controls.persist_hints = false
	host.add_child(_controls)
	_controls.set_anchors_preset(Control.PRESET_FULL_RECT)


## Sets the interface size, puts the card up (a new challenge each case, so it is shown whole),
## lets the layout settle and, on the web, publishes what a probe measures.
func _case(scale: float, label: String, gains: bool) -> void:
	get_window().content_scale_factor = scale
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	_controls.refresh()
	_index += 1
	(
		_hud
		. state
		. apply_event(
			{
				"type": HudChallenge.EVENT,
				"id": &"d",
				"family": ChallengeDef.Family.DAILY,
				"text": WORDS,
				"before": 9,
				"after": 9 + _index,
				"target": 50,
				"checkpoint": 25,
				"completed": false,
				"rung": 0,
				"rungs": 0,
			}
		)
	)
	_hud.markers.held = _controls.button_boxes()
	if gains:
		for amount in [100, 60, 130]:
			_hud.gains.add_gain(&"headshot_kill", amount)
	_fixture.advance(0.8)
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	if _web:
		JavaScriptBridge.eval("window.__card = %s;" % JSON.stringify(_report(label)))
		# The next case waits for the probe's screenshot (`window.__card_ack = index`).
		for _i in ACK_FRAMES:
			await get_tree().process_frame
			if int(JavaScriptBridge.eval("window.__card_ack || 0")) >= _index:
				break
		return
	print(
		"canvas ",
		get_viewport().get_visible_rect().size,
		" card ",
		_hud.challenge.card.get_global_rect(),
		" points ",
		_hud.points.get_global_rect(),
		" slots ",
		_hud.slots.get_global_rect()
	)


func _report(label: String) -> Dictionary:
	var parts := []
	for part in _hud.boxed_parts():
		if part != _hud.challenge and part.is_visible_in_tree() and part.size.y > 0.0:
			parts.append("%s:%s" % [part.name, _text_of(part.get_global_rect())])
	var held := []
	for box in _hud.markers.held:
		held.append(_text_of(box))
	return {
		"case": label,
		"index": _index,
		"canvas":
		(
			"%s,%s"
			% [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]
		),
		"card": _text_of(_hud.challenge.card.get_global_rect()),
		"parts": "|".join(parts),
		"held": "|".join(held),
	}


func _text_of(rect: Rect2) -> String:
	return "%s,%s,%s,%s" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
