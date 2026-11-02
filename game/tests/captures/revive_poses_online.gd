extends Node
## The downed pose and the reviver's kneel as two players see them over a real socket (#504), not
## through a call on the animation: a game server of this process and two players, each drawn by
## its own client. The window is the downed player's screen (the real HUD, the shoulder camera);
## the reviver's screen is a second viewport of the same process, and the three views of the
## other player's body are a free camera in that viewport. Not part of the game. Run windowed:
##
##     gds godot -- --path game res://tests/captures/revive_poses_online.tscn --resolution 1920x1080
##         -- --out=<abs dir>
##
## Writes `own-standing`, `own-downed` (the downed player looking down at themselves),
## `other-standing`, `other-downed` (the reviver's screen, the downed player lying at their feet),
## `kneel-own` (the reviver's own screen, the bot's shoulder camera), `kneel-side` and
## `kneel-seen-by-downed` (the downed player's own screen looking at the reviver) and `up-again`
## into the folder.

## The reviver's screen's size.
const OTHER_SIZE := Vector2i(1280, 720)

var _out := ""
var _hud: Hud
var _host: NightHost
var _a: Night
var _b: Night
var _b_view: SubViewport
var _free: Camera3D


func _ready() -> void:
	_out = NetArgs.new().get_string("out")
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	layer.add_child(_hud)
	await _start()
	await _poses()
	get_tree().quit()


func _start() -> void:
	var tuning := RulesFixture.tuning()
	tuning.rounds.first_spawn_delay = 600.0
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_host.rules_tuning = tuning
	_b_view = SubViewport.new()
	_b_view.own_world_3d = true
	_b_view.size = OTHER_SIZE
	_b_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_b_view)
	_b_view.add_child(_host)
	while not _host.serving:
		await get_tree().physics_frame
	var url := "ws://127.0.0.1:%d" % _host.listener.port()
	_a = Night.new()
	_a.hud = _hud
	add_child(_a)
	await _a.start_remote(url, Night.Mode.HUMAN, 30.0)
	_a.player().local_input = false  # the real mouse and keys never steer a capture
	_a.player().capture_mouse = false
	var b_hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var b_layer := CanvasLayer.new()
	b_layer.add_child(b_hud)
	_b_view.add_child(b_layer)
	_b = Night.new()
	_b.hud = b_hud
	_b.shoulder_camera = true
	_b_view.add_child(_b)
	await _b.start_remote(url, Night.Mode.AUTOPILOT, 30.0)
	_act(RulesAction.skip_break())
	await _settle(90)


func _poses() -> void:
	# The reviver stands a few metres off, facing the same way; both hold their weapon.
	await _save_own("own-standing")
	await _save_other("other-standing")
	_act(RulesAction.blow(1, 99999.0))
	await _until(func() -> bool: return _weight(_a, 1, &"downed") > 0.99)
	await _until(func() -> bool: return _weight(_b, 1, &"downed") > 0.99)
	_a.player().camera_rig.pitch = -0.5
	await _settle(30)
	await _save_own("own-downed")
	await _save_other("other-downed")
	# The reviver (a bot with a body and a camera) walks over and holds Use: it kneels beside the
	# body, on both screens.
	await _until(func() -> bool: return _weight(_a, 2, &"kneel") > 0.99)
	await _until(func() -> bool: return _weight(_b, 2, &"kneel") > 0.99)
	await _settle(20)
	await _save_other("kneel-own")
	await _save_side("kneel-side")
	await _save_own("kneel-seen-by-downed")
	var rules := _host.server.rules
	await _until(func() -> bool: return not rules.players[1].downed, 15.0)
	_a.player().camera_rig.pitch = 0.0
	await _until(func() -> bool: return _weight(_a, 1, &"downed") < 0.01)
	await _settle(30)
	await _save_own("up-again")
	print(
		"WEIGHTS A downed %.2f B kneel %.2f" % [_weight(_a, 1, &"downed"), _weight(_b, 2, &"kneel")]
	)


## Both bodies seen from the side, from the reviver's screen's world.
func _save_side(name: String) -> void:
	var at: Vector3 = _b.player().global_position
	if _free == null:
		_free = Camera3D.new()
		_free.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_b_view.add_child(_free)
	var between := at.lerp(_host.server.body_of(1).global_position, 0.5)
	# From above and to one side, over the parked cars.
	_free.global_position = between + Vector3(1.6, 2.3, 2.2)
	_free.look_at(between + Vector3.UP * 0.3)
	_free.make_current()
	await _settle(2)
	await _save_view(_b_view, name)


func _save_own(name: String) -> void:
	await _save_view(get_viewport(), name)


func _save_other(name: String) -> void:
	if _free != null:
		_free.queue_free()
		_free = null
	await _settle(2)
	await _save_view(_b_view, name)


func _weight(night: Night, player_id: int, kind: StringName) -> float:
	var animation := night._animation_of(player_id)
	if animation == null:
		return -1.0
	return animation.downed_weight() if kind == &"downed" else animation.kneel_weight()


func _until(condition: Callable, seconds := 10.0) -> void:
	var began := Time.get_ticks_msec()
	while not condition.call() and (Time.get_ticks_msec() - began) / 1000.0 < seconds:
		await get_tree().physics_frame


func _act(action: Dictionary) -> void:
	_host._collect(_host.server.rules.apply(action))


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
	await get_tree().process_frame


func _save_view(viewport: Viewport, name: String) -> void:
	if _out == "":
		return
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [_out, name]
	viewport.get_texture().get_image().save_png(path)
	print("SAVED ", path)
