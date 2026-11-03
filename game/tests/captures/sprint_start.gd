extends Node
## The start of a sprint, from the player's camera (issue #619; not a test): the soldier stands,
## runs or holds the aim, and at `SPRINT_AT` the sprint key goes down (and the aim button up).
## The player is driven by commands, so the same script gives the same run on any build, `main`
## included, for before and after captures. Run windowed, one frame per 60th of a second:
##
##     gds godot -- --path game res://tests/captures/sprint_start.tscn \
##         --write-movie <abs>/f.png --fixed-fps 60 --quit-after 150 -- --case=idle --view=local
##
## `--case=` is `idle`, `walk` (running, sprint pressed), `aim` (aim held on the spot) or `aimwalk`
## (aim held while moving). `--view=local` is the player's own shoulder camera; `--view=puppet`
## shows the same run as another machine draws it: the true player's frames at 30 a second go
## through `RemoteAvatars` (delayed, interpolated, the speed and stance read off them) onto a
## puppet, and a camera behind it looks the way the shoulder camera does. Prints `SPRINT_AT <frame>`
## (the movie frame the sprint key goes down on).

const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 17.0)
const SPRINT_AT := 1.5
const END_AT := 2.4
const PUPPET_ID := 2
## The puppet camera: metres to the body's left (where the carried gun shows) and a little behind,
## and up, at the shoulder camera's FOV; it follows the body.
const PUPPET_CAMERA := Vector3(-2.6, 1.2, 0.6)

var _ticks := 0
var _case := "idle"
var _puppet := false
var _player: Player
var _avatars: RemoteAvatars
var _camera: Camera3D


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):
			_case = arg.trim_prefix("--case=")
		elif arg == "--view=puppet":
			_puppet = true
	var room: Node = load("res://world/test_room.tscn").instantiate()
	add_child(room)
	_player = room.get_node("Player") as Player
	_player.capture_mouse = false
	_player.local_input = false
	_player.teleport(START)
	_player.camera_rig.yaw = 0.0
	_player.camera_rig.pitch = -0.08
	(_player.get_node("AnimationTree") as PlayerAnimation).equip(&"rifle")
	if _puppet:
		_player.get_node("Model").visible = false
		_avatars = RemoteAvatars.new()
		var looks := LookRegistry.new()
		_avatars.setup(looks, 0, TICK * 2.0)
		add_child(_avatars)
		_avatars.set_process(false)  # advanced by hand below, once a frame
		_camera = Camera3D.new()
		_camera.fov = _player.tuning.fov
		_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(_camera)
		_camera.make_current()


func _process(delta: float) -> void:
	if _puppet:
		_avatars.advance(delta)
		var body := _avatars.avatar(PUPPET_ID)
		if body != null:
			_camera.global_position = body.global_position + PUPPET_CAMERA
			_camera.look_at(body.global_position + Vector3(0.0, 0.95, 0.0))


func _physics_process(_delta: float) -> void:
	var now := _ticks * TICK
	_ticks += 1
	if now >= END_AT:
		get_tree().quit()
		return
	var command := PlayerCommand.new()
	command.yaw = _player.camera_rig.yaw
	command.pitch = _player.camera_rig.pitch
	var sprinting := now >= SPRINT_AT
	match _case:
		"walk":
			command.move = Vector2(0.0, -1.0) if now >= 0.3 else Vector2.ZERO
			command.sprint = sprinting
		"idle":
			command.move = Vector2(0.0, -1.0) if sprinting else Vector2.ZERO
			command.sprint = sprinting
		"aim":
			command.aim = not sprinting and now >= 0.3
			command.move = Vector2(0.0, -1.0) if sprinting else Vector2.ZERO
			command.sprint = sprinting
		"aimwalk":
			command.aim = not sprinting and now >= 0.3
			command.move = Vector2(0.0, -1.0) if now >= 0.6 else Vector2.ZERO
			command.sprint = sprinting
	_player.submit_command(command)
	if _ticks == roundi(SPRINT_AT / TICK):
		print("SPRINT_AT %d" % _ticks)
	if _puppet and _ticks % 2 == 0:
		(
			_avatars
			. apply_frame(
				{
					"tick": _ticks / 2,
					"players":
					{
						PUPPET_ID:
						{
							"pos": _player.state.position,
							"facing": _player.state.facing,
							"downed": false,
							"aim": _player.state.aiming,
							"pitch": NightServer.pitch_step(_player.camera_rig.pitch),
							"stance": PlayerStance.pack(_player.state),
						}
					},
				}
			)
		)
