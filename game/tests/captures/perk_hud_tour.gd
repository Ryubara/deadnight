extends Node
## The perk badges and the DOWN card's self-revive (#707) in the real night, saved as PNGs of the
## window: no perks, one, four, down alone with the revive perk (the card counts the self-revive
## down), up again with the perks kept, and down with a teammate on their feet (the perks gone, the
## clock bleeding). `--touch` adds the phone's touch controls and layout; `--mirrored` is the left
## hand. Each stage writes `<out>/<tag>_<stage>.png` and prints what the HUD says.
##
## It uses nothing the HUD change added, so it runs on `main` for the "before" pictures.
##
## In a browser (`tools/web_smoke/perk_hud_capture.py`, which exports a copy that starts on this
## scene) the flags are the URL's query (`?touch=1&mirrored=1`) and each stage is published as
## `window.__perks = {case, index}` for the probe to screenshot, then `{done: true}`.
##
## Run through the no-focus launcher at the size to see:
## `gds godot -- --path game res://tests/captures/perk_hud_tour.tscn --resolution 1280x720 --
## --out=<folder> --tag=720p`.

const SETTLE_FRAMES := 20
const TICKS := 60
const ONE := &"tonic_double_shot"
const FOUR: Array[StringName] = [
	&"tonic_swift_rescue", &"tonic_hearty", &"tonic_double_shot", &"tonic_quick_load"
]

const HOLD_WEB := 45

var _out := ""
var _tag := "tour"
var _night: Night
var _hud: Hud
var _web := OS.has_feature("web")
var _index := 0


func _ready() -> void:
	var args := _args()
	_out = String(args.get("out", "user://"))
	_tag = String(args.get("tag", "tour"))
	DirAccess.make_dir_recursive_absolute(_out)
	await _tour(args.has("touch"), args.has("mirrored"))
	if _web:
		JavaScriptBridge.eval("window.__perks = {done: true};")
	else:
		get_tree().quit()


func _args() -> Dictionary:
	var found := {}
	for arg in OS.get_cmdline_user_args():
		var text := String(arg).trim_prefix("--")
		var parts := text.split("=", true, 1)
		found[parts[0]] = parts[1] if parts.size() > 1 else true
	if _web:
		var query := str(JavaScriptBridge.eval("location.search"))
		for pair in query.trim_prefix("?").split("&"):
			if pair != "":
				found[pair.get_slice("=", 0)] = pair.get_slice("=", 1) if "=" in pair else true
	return found


func _tour(with_touch: bool, mirrored: bool) -> void:
	_hud = (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(_hud)
	if with_touch:
		TouchMode.device_is_touch = true
		var controls := TouchControls.new()
		controls.state = _hud.state
		controls.active_changed.connect(func(active: bool) -> void: _hud.touch_layout = active)
		controls.safe_insets_changed.connect(
			func(insets: Vector4) -> void: _hud.set_safe_insets(insets)
		)
		layer.add_child(controls)
	add_child(layer)
	_hud.mirrored = mirrored
	var tuning := (
		(load(GameRules.DEFAULT_TUNING_PATH) as RulesTuning).duplicate(true) as RulesTuning
	)
	tuning.rounds.first_spawn_delay = 6000.0
	_night = Night.new()
	_night.hud = _hud
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, 7, tuning)
	_night.player().local_input = false
	_night.player().capture_mouse = false
	_night.ticked.connect(_send)
	var rules := _night.server.rules
	_night.state.apply_events(rules.apply(RulesAction.skip_break()))
	_night.state.apply_events(rules.apply(RulesAction.grant_points(1, 40000)))
	_night.player().camera_rig.camera().make_current()
	await _settle()
	await _shot("1_no_perks")
	_night.server.buy(1, ONE)
	await _settle()
	await _shot("2_one_perk")
	rules.players[1].tonics.clear()
	for id in FOUR:
		_night.server.buy(1, id)
	await _settle()
	await _shot("3_four_perks")
	# Down and alone: the revive perk gets the holder up, the card counts it.
	_night.state.apply_events(rules.apply(RulesAction.blow(1, 9999.0)))
	await _run(TICKS)
	await _settle()
	await _shot("4_down_self_revive_a")
	await _run(TICKS * 2)
	await _shot("5_down_self_revive_b")
	await _run(TICKS * 3)
	await _settle()
	await _shot("6_up_again_perks_kept")
	# A teammate on their feet: the perks go with the down, the card bleeds out.
	_night.server.apply({"type": NightServer.JOIN, "player_id": 2, "local": false})
	await _run(5)
	_night.state.apply_events(rules.apply(RulesAction.blow(1, 9999.0)))
	await _run(TICKS)
	await _settle()
	await _shot("7_down_with_a_teammate_perks_gone")


func _run(ticks: int) -> void:
	for _i in ticks:
		await get_tree().physics_frame


func _send() -> void:
	var command := NightCommand.new()
	_night.link.send(command.to_dict())


func _settle() -> void:
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame


func _shot(stage: String) -> void:
	if _web:
		_index += 1
		JavaScriptBridge.eval("window.__perks = {case: '%s', index: %d};" % [stage, _index])
		await _run(HOLD_WEB)
		return
	await RenderingServer.frame_post_draw
	var state := _hud.state
	print(
		(
			"STAGE %s perks %s down %s card '%s' / '%s'"
			% [
				stage,
				state.get("perks") if "perks" in state else "(no badges)",
				state.is_local_downed(),
				_hud.health.down_text,
				_hud.health.hint_text,
			]
		)
	)
	get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [_out, _tag, stage])
