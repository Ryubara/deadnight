extends Node
## The player's own shoulder camera on a body that goes down and is raised (#532): standing, just
## down, settled, looking up and down, mid-revive and up again. A real down (the rules' blow) and a
## real revive (a teammate holding use beside the body through the server), the camera the player
## really has. Not part of the game. Run windowed (never headless: it saves what the window draws),
## off the person's desktop:
## `gds godot -- --path game res://tests/captures/downed_camera.tscn --quit-after 3600
## -- --out <dir>`.
## Every stage is one PNG; the console prints the camera's numbers beside it.

const SECOND := 60
const MATE := 2
const LOOK_DOWN := -0.5
const LOOK_UP := 0.35

var _night: Night
var _out := ""
var _hold_use := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--out")
	_out = (
		args[at + 1]
		if at >= 0 and at + 1 < args.size()
		else OS.get_user_data_dir() + "/downed_camera"
	)
	DirAccess.make_dir_recursive_absolute(_out)
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	var tuning := RulesFixture.tuning()
	tuning.rounds.first_spawn_delay = 600.0  # no zombies: the camera alone
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, 7, tuning)
	_night.ticked.connect(_send)
	var player := _night.player()
	player.capture_mouse = false
	player.local_input = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_night.link.send({"type": NightServer.JOIN, "player_id": MATE, "local": false})
	await _ticks(2)
	player.camera_rig.camera().make_current()
	_night.state.apply_events(_night.server.rules.apply(RulesAction.skip_break()))
	var rig := player.camera_rig
	var spot := player.global_position
	rig.yaw = player.state.facing
	rig.pitch = -0.12
	_night.server.body_of(MATE).teleport(spot + Vector3(-4.0, 0.0, 3.0))
	await _seconds(1.5)
	await _shot("1_standing", rig)

	# Down: the rules' blow, as a zombie's would land.
	_night.state.apply_events(_night.server.rules.apply(RulesAction.blow(1, 500.0)))
	await _seconds(0.25)
	await _shot("2_down_quarter_second", rig)
	await _seconds(1.75)
	await _shot("3_down_settled", rig)
	rig.pitch = LOOK_DOWN
	await _seconds(0.6)
	await _shot("4_down_looking_down", rig)
	rig.pitch = LOOK_UP
	await _seconds(0.6)
	await _shot("5_down_looking_up", rig)
	rig.pitch = -0.12

	# Raised: the teammate beside the body holds use for the channel.
	_night.server.body_of(MATE).teleport(
		_night.server.body_of(1).global_position + Vector3(-0.9, 0.0, 0.0)
	)
	await _seconds(0.5)
	_hold_use = true
	var needed := _night.server.rules.tuning.health.revive_seconds
	await _seconds(needed * 0.5)
	await _shot("6_being_raised", rig)
	await _seconds(needed * 0.6)
	_hold_use = false
	print("revived: ", not _night.server.rules.players[1].downed)
	await _seconds(0.25)
	await _shot("7_up_quarter_second", rig)
	await _seconds(1.75)
	await _shot("8_up_settled", rig)
	get_tree().quit()


func _send() -> void:
	var command := NightCommand.new()
	command.player_id = Night.PLAYER_ID
	var rig := _night.player().camera_rig
	command.motion.yaw = rig.yaw
	command.motion.pitch = rig.pitch
	var aim := rig.aim_transform()
	command.origin = aim.origin
	command.dir = -aim.basis.z
	_night.link.send(command.to_dict())
	var mate := NightCommand.new()
	mate.player_id = MATE
	mate.use_held = _hold_use
	_night.server.submit(MATE, mate)


func _shot(name: String, rig: ThirdPersonCamera) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [_out, name]
	get_viewport().get_texture().get_image().save_png(path)
	print(
		(
			"STAGE %s frame %d pivot_y %.3f lens_y %.3f pitch %.3f"
			% [
				name,
				Engine.get_frames_drawn(),
				rig.pivot_position().y,
				rig.camera().global_position.y,
				rig.camera().global_rotation.x
			]
		)
	)


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _seconds(seconds: float) -> void:
	await _ticks(int(seconds * SECOND))
