extends Node
## A revive over a night on a game server of this process, for captures: the local player (a bot
## with the shoulder camera and the real HUD) and a second player in a lot with no zombies. First
## the local player goes down and the second one pulls them up (their screen: the clock, then the
## ring); then the second goes down and the local bot walks over and pulls them up (the marker over
## the body, the reviver's ring); last the scoreboard with the revives counted. Not part of the
## game.
##
##     godot --path game res://tests/captures/revive_tour.tscn --resolution 1920x1080
##         -- --out=<abs dir> [--touch [--notch]]
##
## Writes `downed-clock.png`, `downed-ring.png`, `marker.png`, `reviver-ring.png`, `scoreboard.png`
## (and `dead.png` with `--dead`) into the folder, the picture being the window's.

const NOTCH := Vector4(96.0, 0.0, 96.0, 24.0)

var _out := ""
var _touch := false
var _hud: Hud
var _controls: TouchControls
var _night: Night
var _host: NightHost
var _mate: Night
var _command := NightCommand.new()


func _ready() -> void:
	var args := NetArgs.new()
	_out = args.get_string("out")
	_touch = args.has("touch")
	TouchMode.device_is_touch = _touch
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	layer.add_child(_hud)
	if _touch:
		_controls = TouchControls.new()
		_controls.state = _hud.state
		if args.has("notch"):
			_controls.insets_override = NOTCH
		_controls.safe_insets_changed.connect(_fit_hud)
		layer.add_child(_controls)
	await _start()
	await _downed_view()
	await _reviver_view()
	await _scoreboard()
	if args.has("dead"):
		await _dead_view()
	get_tree().quit()


func _start() -> void:
	var tuning := RulesFixture.tuning()
	tuning.rounds.first_spawn_delay = 600.0
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_host.rules_tuning = tuning
	_world().add_child(_host)
	while not _host.serving:
		await get_tree().physics_frame
	var url := "ws://127.0.0.1:%d" % _host.listener.port()
	_night = Night.new()
	_night.hud = _hud
	_night.shoulder_camera = true
	add_child(_night)
	await _night.start_remote(url, Night.Mode.AUTOPILOT, 30.0)
	_mate = Night.new()
	_world().add_child(_mate)
	await _mate.start_remote(url, Night.Mode.MANUAL, 30.0)
	_mate.ticked.connect(func() -> void: _mate.link.send(_command.to_dict()))
	_act(RulesAction.skip_break())
	await _settle(60)


## The local player is down. First the clock alone (the second player stands away), then the second
## player is beside the body and holds Use: the ring over the clock.
func _downed_view() -> void:
	_act(RulesAction.blow(1, 99999.0))
	await _settle(75)
	await _save("downed-clock")
	_stand_beside(2, 1)
	_command.use_held = true
	_command.use = true
	var rules := _host.server.rules
	while rules.revive_fraction_of(1) < 0.5 and rules.players[1].downed:
		await get_tree().physics_frame
	await _settle(2)
	await _save("downed-ring")
	while rules.players[1].downed:
		await get_tree().physics_frame
	_command.use_held = false
	_command.use = false
	await _settle(45)


## The second player goes down some way in front of the local bot, which sees the marker, walks over
## and holds Use.
func _reviver_view() -> void:
	var me := _night.state.me()
	var ahead := Basis(Vector3.UP, float(me["facing"])) * Vector3(0.0, 0.0, -9.0)
	_host.server.body_of(2).teleport(_night.state.position() + ahead)
	await _settle(10)
	_act(RulesAction.blow(2, 99999.0))
	await _settle(8)
	await _save("marker")
	var rules := _host.server.rules
	while rules.revive_fraction_of(2) < 0.5 and rules.players[2].downed:
		await get_tree().physics_frame
	await _settle(2)
	await _save("reviver-ring")
	while rules.players[2].downed:
		await get_tree().physics_frame
	await _settle(30)


func _scoreboard() -> void:
	Input.action_press(Hud.SCOREBOARD_ACTION)
	await _settle(12)
	print("board rows ", _hud.scoreboard.rows_text, " headings ", _hud.scoreboard.headings)
	await _save("scoreboard")
	Input.action_release(Hud.SCOREBOARD_ACTION)


## The local player bleeds out: a lot with nobody near.
func _dead_view() -> void:
	var rules := _host.server.rules
	_host.server.body_of(2).teleport(Vector3(0.0, 0.0, 200.0))
	_act(RulesAction.blow(1, 99999.0))
	while not rules.is_dead(1):
		await get_tree().physics_frame
	await _settle(30)
	await _save("dead")


func _act(action: Dictionary) -> void:
	_host._collect(_host.server.rules.apply(action))


func _stand_beside(reviver: int, patient: int) -> void:
	var at := _host.server.body_of(patient).global_position + Vector3(1.0, 0.0, 0.0)
	_host.server.body_of(reviver).teleport(at)


func _world() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	return viewport


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
	await get_tree().process_frame


func _save(name: String) -> void:
	if _out == "":
		return
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [_out, name]
	get_viewport().get_texture().get_image().save_png(path)
	print("SAVED ", path)


func _fit_hud(insets: Vector4) -> void:
	_hud.offset_left = insets.x
	_hud.offset_top = insets.y
	_hud.offset_right = -insets.z
	_hud.offset_bottom = -insets.w
