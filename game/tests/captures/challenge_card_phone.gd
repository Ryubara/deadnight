extends Node
## The challenge card on a phone's night, over the real HUD and the real touch controls with a full
## room (#1299): `--people` people (8 at most) and `--bots` bots on top, the card up with three
## lines, and the picture taken of the window. Not part of the game. Run in a window of the page's
## size with the kit's launcher:
##
##     gds godot -- --path game res://tests/captures/challenge_card_phone.tscn --resolution 1334x750
##         -- --out=<folder>/card.png [--scale=1.25] [--people=8] [--bots=7] [--left] [--tag]
##
## It prints one line with the card's and the players' column's rectangles and quits.

const NOTCH := Vector4(96.0, 0.0, 96.0, 24.0)
const SETTLE_FRAMES := 12
const WORDS := "Put down 50 zombies with the submachine gun"

var _hud: Hud
var _controls: TouchControls


func _ready() -> void:
	var args := NetArgs.new()
	TouchMode.device_is_touch = true
	UIInputMode.track(InputEventScreenTouch.new())
	get_window().content_scale_factor = args.get_float("scale", 1.0)
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
	var fixture := HudFixture.make(
		host, clampi(args.get_int("people", 8), 1, 8), 1958, false, args.get_int("bots", 7)
	)
	_hud = fixture.hud
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
	if args.has("left"):
		get_tree().root.get_node("Settings").set_value(SettingsService.LEFT_HANDED, true)
	await get_tree().process_frame
	_controls.refresh()
	fixture.into_round_one()
	_hud.state.set_area("The Concession Stand", "Light the booth to open the back lot")
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
				"after": 10,
				"target": 50,
				"checkpoint": 25,
				"completed": false,
				"rung": 0,
				"rungs": 0,
			}
		)
	)
	_hud.markers.held = _controls.button_boxes()
	fixture.give_perks(fixture.rules.tuning.economy.max_tonics)
	if args.has("gains"):
		for amount in [100, 60, 130, 60]:
			_hud.gains.add_gain(&"headshot_kill", amount)
	fixture.advance(0.8)
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	var card := _hud.challenge.card.get_global_rect()
	var column := _hud.points.get_global_rect()
	print(
		"canvas ",
		get_viewport().get_visible_rect().size,
		" card ",
		card,
		" points ",
		column,
		" slots ",
		_hud.slots.get_global_rect(),
		" objective ",
		_hud.objective.get_global_rect()
	)
	if args.has("gains"):
		print("GAINS box ", _hud.gains.get_global_rect())
		for row in _hud.gains.rows:
			print("GAIN ", (row["label"] as Label).get_global_rect())
	if args.has("debug"):
		for box in _hud._challenge_avoid(_hud.get_global_rect().position, float(HudStyle.GAP)):
			print("AVOID ", box)
	var out := args.get_string("out")
	if out != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out)
		print("SAVED ", out)
	get_tree().quit()
