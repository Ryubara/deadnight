extends Node
## The players' column on a phone's night, over the real HUD and the real touch controls with a
## full room (#1301): `--people` people (8 at most) and `--bots` bots on top, perks up, the
## objective on its two lines, and the picture taken of the window. Not part of the game.
##
## On the desktop, in a window of the page's size, with the kit's launcher:
##
##     gds godot -- --path game res://tests/captures/players_column_phone.tscn --resolution 1334x750
##         -- --out=<folder>/column.png [--scale=1.25] [--people=8] [--bots=7] [--left] [--down]
##         [--nofit]
##
## `--nofit` (`?nofit=1`) takes the column's room away once the layout has settled: the column is
## as it was before the change (one box to a row), for the Before picture.
##
## `--oldcard` (`?oldcard=1`) puts the round card back in its three lines once the layout has
## settled (#1305): the column's room as it was before the card took one row.
##
## It prints one line with the rectangles of the parts and quits.
##
## In a browser (`tools/web_smoke/players_column_phone.py`, which exports a copy that starts on
## this scene) the flags are the URL's query (`?left=1`), the interface size runs through 0.8, 1.0
## and 1.25, and each case is published as `window.__column = {case, index, canvas, parts, pairs}`
## (units of the canvas, `x,y,w,h`) for the probe to screenshot and measure; the scene waits for
## `window.__column_ack = index` before the next one, then publishes `{done: true}`.

const NOTCH := Vector4(96.0, 0.0, 96.0, 24.0)
const SETTLE_FRAMES := 12
## How many frames a web case waits for the probe to answer, at most.
const ACK_FRAMES := 1200
const SCALES: Array[float] = [0.8, 1.0, 1.25]

var _hud: Hud
var _fixture: HudFixture
var _controls: TouchControls
var _web := OS.has_feature("web")
var _index := 0


func _ready() -> void:
	var args := _args()
	TouchMode.device_is_touch = true
	if not _web:
		# A phone page at ratio 2, which a desktop window does not report: the fingertip's size.
		MenuScale.pixel_ratio = 2.0
	UIInputMode.track(InputEventScreenTouch.new())
	_build(args)
	if args.has("left"):
		get_tree().root.get_node("Settings").set_value(SettingsService.LEFT_HANDED, true)
	await get_tree().process_frame
	_controls.refresh()
	# The first-run hints stand over the column and the objective: the picture is of the HUD.
	for hint in TouchHints.ORDER:
		_controls.hints.mark_used(hint)
	_fixture.into_round_one()
	_hud.state.set_area("The Concession Stand", "Light the booth to open the back lot")
	_fixture.give_perks(_fixture.rules.tuning.economy.max_tonics)
	if args.has("down"):
		_fixture.act(RulesAction.set_downed(3, true))
		_fixture.act(RulesAction.set_downed(6, true))
	for id in range(2, 9):
		_hud.state.apply_event(
			{"type": &"points_changed", "player_id": id, "total": 125 * id * id, "delta": 0}
		)
	if _web:
		for scale in SCALES:
			await _case(scale, "ui%s" % scale)
		JavaScriptBridge.eval("window.__column = {done: true};")
		return
	await _case(float(args.get("scale", 1.0)), "one")
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


## Sets the interface size, lets the layout settle and, on the web, publishes what a probe
## measures.
func _case(scale: float, label: String) -> void:
	get_window().content_scale_factor = scale
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	_controls.refresh()
	_index += 1
	_hud.markers.held = _controls.button_boxes()
	_fixture.advance(0.8)
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	if _args().has("oldcard"):
		_hud.round_part.compact = false
		for _i in SETTLE_FRAMES:
			await get_tree().process_frame
	if _args().has("nofit"):
		_hud.points.room = INF
		for _i in SETTLE_FRAMES:
			await get_tree().process_frame
	if _web:
		JavaScriptBridge.eval("window.__column = %s;" % JSON.stringify(_report(label)))
		# The next case waits for the probe's screenshot (`window.__column_ack = index`).
		for _i in ACK_FRAMES:
			await get_tree().process_frame
			if int(JavaScriptBridge.eval("window.__column_ack || 0")) >= _index:
				break
		return
	print(
		"canvas ",
		get_viewport().get_visible_rect().size,
		" round ",
		_hud.round_part.get_global_rect(),
		" objective ",
		_hud.objective.get_global_rect(),
		" points ",
		_hud.points.get_global_rect(),
		" pairs ",
		_hud.points.pairs
	)


func _report(label: String) -> Dictionary:
	var parts := []
	for part in _hud.boxed_parts():
		if part.is_visible_in_tree() and part.size.y > 0.0:
			parts.append("%s:%s" % [part.name, _text_of(part.get_global_rect())])
	var size := get_viewport().get_visible_rect().size
	return {
		"case": label,
		"index": _index,
		"canvas": "%s,%s" % [size.x, size.y],
		"parts": "|".join(parts),
		"pairs": _hud.points.pairs,
		"mate_type": _mate_type(),
	}


## The type size of a teammate's points, canvas units (0 with no teammate).
func _mate_type() -> int:
	for id in range(2, NightHost.MAX_PLAYERS + 1):
		var box := _hud.points.box_of(id)
		if box != null:
			return box._number.get_theme_font_size(&"font_size")
	return 0


func _text_of(rect: Rect2) -> String:
	return "%s,%s,%s,%s" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
