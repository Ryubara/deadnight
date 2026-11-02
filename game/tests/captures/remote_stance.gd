extends Node
## What another player's body does on this screen when they sprint, crouch and jump (#549): a game
## server of this process and two clients over a real socket. The window is player B's screen
## (the real HUD); a free camera looks at player A's drawn body from the side while A, a seat
## driven by hand, stands, sprints, crouches and jumps. Not part of the game. Run windowed:
##
##     gds godot -- --path game res://tests/captures/remote_stance.tscn --resolution 1920x1080
##         -- --out=<abs dir>
##
## Writes `standing`, `sprint` (two frames), `crouch`, `jump-up`, `jump-top` and `landed` into the
## folder, the picture being the window's.

## How far the camera stands off the body it looks at (metres) and how high.
const CAMERA_DISTANCE := 3.4
const CAMERA_HEIGHT := 1.3

var _out := ""
var _host: NightHost
var _a: Night
var _b: Night
var _hud: Hud
var _camera: Camera3D
var _command := NightCommand.new()
var _floor_y := 0.0


func _ready() -> void:
	_out = NetArgs.new().get_string("out")
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	layer.add_child(_hud)
	await _start()
	await _show_stances()
	get_tree().quit()


func _start() -> void:
	var tuning := RulesFixture.tuning()
	tuning.rounds.first_spawn_delay = 600.0
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_host.rules_tuning = tuning
	var hidden := SubViewport.new()
	hidden.own_world_3d = true
	hidden.size = Vector2i(64, 64)
	hidden.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(hidden)
	hidden.add_child(_host)
	while not _host.serving:
		await get_tree().physics_frame
	var url := "ws://127.0.0.1:%d" % _host.listener.port()
	_b = Night.new()
	_b.hud = _hud
	add_child(_b)
	await _b.start_remote(url, Night.Mode.MANUAL, 30.0)
	_a = Night.new()
	hidden.add_child(_a)
	await _a.start_remote(url, Night.Mode.MANUAL, 30.0)
	_a.ticked.connect(func() -> void: _a.link.send(_command.to_dict()))
	_host._collect(_host.server.rules.apply(RulesAction.skip_break()))
	_camera = Camera3D.new()
	_camera.fov = 50.0
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)
	await _settle(90)


func _show_stances() -> void:
	var body: Player = _b.avatars.avatar(1)
	_floor_y = body.global_position.y
	_command.motion.yaw = 0.0
	await _settle(30)
	await _save("standing")
	# A sprints; the camera runs with them from the side.
	_command.motion.sprint = true
	_command.motion.move = Vector2(0.0, -1.0)
	await _until(func() -> bool: return _pose().sprint_carry() > 0.9, 360)
	await _save("sprint")
	await _settle(8)
	await _save("sprint-2")
	_command.motion.sprint = false
	_command.motion.move = Vector2.ZERO
	await _settle(60)
	_command.motion.crouch = true
	await _until(func() -> bool: return _pose().current_state() == &"crouch", 120)
	await _settle(20)
	await _save("crouch")
	_command.motion.crouch = false
	await _settle(40)
	_command.motion.jump = true
	await _settle(1)
	_command.motion.jump = false
	await _until(func() -> bool: return _pose().current_state() == &"jump", 120)
	await _save("jump-up")
	var top := _floor_y
	for _i in 40:
		await _settle(1)
		top = maxf(top, body.global_position.y)
		if _pose().current_state() == &"fall" or _pose().current_state() == &"land":
			break
	await _save("jump-top")
	await _until(func() -> bool: return _pose().current_state() == &"land", 240)
	await _save("landed")
	print(
		(
			"STANCE top %.2f m over the floor, sprint carry %.2f"
			% [top - _floor_y, _pose().sprint_carry()]
		)
	)


func _pose() -> PlayerAnimation:
	var body: Player = _b.avatars.avatar(1)
	return body.get_node(^"AnimationTree") as PlayerAnimation


func _look_at_a() -> void:
	var body: Player = _b.avatars.avatar(1)
	if body == null:
		return
	var at := body.global_position
	var side := Basis(Vector3.UP, body.rotation.y) * Vector3.RIGHT
	_camera.global_position = at + side * CAMERA_DISTANCE + Vector3.UP * CAMERA_HEIGHT
	_camera.look_at(Vector3(at.x, _floor_y + 0.8, at.z))
	_camera.make_current()


func _until(condition: Callable, frames: int) -> void:
	for _i in frames:
		if condition.call():
			return
		await _settle(1)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
		_look_at_a()
	await get_tree().process_frame
	_look_at_a()


func _save(name: String) -> void:
	if _out == "":
		return
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [_out, name]
	get_viewport().get_texture().get_image().save_png(path)
	print("SAVED ", path)
