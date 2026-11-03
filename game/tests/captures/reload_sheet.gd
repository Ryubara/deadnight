extends Node
## Every firearm's reload (#683) in a real night, as players see it: the player's own from the
## shoulder camera, and a teammate's from the player's screen (the teammate a few metres ahead,
## turned three-quarters). Each reload is pressed through the server and filmed at a row of shares
## of its time; one contact sheet per weapon and view. Not part of the game. Run windowed (it saves
## what the window draws), off the person's desktop:
## `gds godot -- --path game res://tests/captures/reload_sheet.tscn -- --out <dir>
## [--weapon=rifle] [--frames]` (`--frames` also keeps every frame for a video).

const SECOND := 60
const MATE := 2
const GUNS: Array[StringName] = [&"pistol", &"smg", &"rifle", &"shotgun", &"flare_gun"]
## The shares of the reload the sheet shows.
const SHARES: Array[float] = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
const CELL := Vector2i(800, 450)
const COLUMNS := 4
## Where the teammate stands from the player, metres ahead, and how far he is turned from facing
## the player (degrees).
const MATE_AHEAD := 2.6
const MATE_RIGHT := 1.6
const MATE_TURN := 125.0
## Where the player stands (a lit stretch of the lot, as the tilt capture used) and faces.
const START := Vector3(0.0, 0.05, -28.0)
const START_YAW := 180.0
## Each cell keeps the frame around the filmed body: this many metres of the world across, at
## the body's chest, as the camera sees it (16:9).
const CROP_METRES := 3.0

var _night: Night
var _out := ""
var _guns: Array[StringName] = GUNS
var _frames := false
var _full := false
var _reload_me := false
var _reload_mate := false
var _mate_yaw := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--out")
	_out = args[at + 1] if at >= 0 and at + 1 < args.size() else OS.get_user_data_dir() + "/reload"
	for argument in args:
		if argument.begins_with("--weapon="):
			_guns = [StringName(argument.trim_prefix("--weapon="))]
		elif argument == "--frames":
			_frames = true
		elif argument == "--full":
			_full = true
	DirAccess.make_dir_recursive_absolute(_out)
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	var tuning := RulesFixture.tuning()
	tuning.rounds.first_spawn_delay = 600.0  # no zombies: the reload alone
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
	player.teleport(START)
	player.state.facing = deg_to_rad(START_YAW)
	player.rotation.y = player.state.facing
	rig.yaw = player.state.facing
	rig.pitch = -0.08
	var ahead := Vector3(-sin(rig.yaw), 0.0, -cos(rig.yaw))
	var right := Vector3(cos(rig.yaw), 0.0, -sin(rig.yaw))
	_night.server.body_of(MATE).teleport(START + ahead * MATE_AHEAD + right * MATE_RIGHT)
	_mate_yaw = rig.yaw + deg_to_rad(MATE_TURN)
	var mate_body := _night.server.body_of(MATE)
	mate_body.state.facing = _mate_yaw
	mate_body.rotation.y = _mate_yaw
	for weapon_id in _guns:
		await _film(weapon_id, false)
		await _film(weapon_id, true)
	get_tree().quit()


func _film(weapon_id: StringName, mate: bool) -> void:
	var who := MATE if mate else Night.PLAYER_ID
	var combat := _night.server.combat
	combat.apply(CombatAction.give_weapon(who, weapon_id))
	combat.apply(CombatAction.equip(who, weapon_id))
	await _seconds(1.2)
	combat.state_of(who, weapon_id).ammo = 0
	var seconds: float = WeaponCatalog.get_def(weapon_id).reload_time
	var view := "third" if mate else "first"
	var sheet := Image.create(
		CELL.x * COLUMNS, CELL.y * ceili(float(SHARES.size()) / COLUMNS), false, Image.FORMAT_RGB8
	)
	sheet.fill(Color(0.1, 0.1, 0.1))
	if mate:
		_reload_mate = true
	else:
		_reload_me = true
	var start := Engine.get_physics_frames()
	var frame := 0
	var next := 0
	while next < SHARES.size():
		await get_tree().physics_frame
		var now := float(Engine.get_physics_frames() - start) / SECOND
		if _frames and (Engine.get_physics_frames() - start) % 2 == 0:
			await RenderingServer.frame_post_draw
			var still := get_viewport().get_texture().get_image()
			still.save_png("%s/%s_%s_%04d.png" % [_out, weapon_id, view, frame])
			frame += 1
		if now >= SHARES[next] * seconds + 0.1:
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			if _full:
				image.save_png("%s/%s_%s_%02d.png" % [_out, weapon_id, view, next])
			# The player's own reload is the whole screen the player has; a teammate's is cropped
			# round him.
			if mate:
				image = image.get_region(_crop_around(who, image.get_size()))
			image.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
			image.convert(Image.FORMAT_RGB8)
			var cell := Vector2i(next % COLUMNS, next / COLUMNS) * CELL
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, CELL), cell)
			var body := _night.server.body_of(who) if mate else _night.player()
			var anim := body.get_node(^"AnimationTree") as PlayerAnimation
			var pose := anim.reload_pose()
			print(
				(
					"STAGE %s %s share %.1f t %.3f weight %.2f left %.2f part %.2f ammo %s turn %s %s"
					% [
						weapon_id,
						view,
						SHARES[next],
						now,
						anim.reload_weight(),
						pose.left,
						pose.part,
						pose.ammo,
						pose.weapon_turn,
						_ammo_note(anim)
					]
				)
			)
			next += 1
	sheet.save_png("%s/reload_%s_%s.png" % [_out, weapon_id, view])
	await _seconds(0.6)


func _ammo_note(anim: PlayerAnimation) -> String:
	var ammo := anim.reload_ammo()
	if ammo == null or not ammo.is_visible_in_tree():
		return ""
	var skeleton := ammo.get_parent().get_parent() as Skeleton3D
	var hand := (
		skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Index1.L"))
	)
	var mount := ammo.get_parent() as Node3D
	var solved := anim.hands().solved_left()
	return (
		"ammo %s mount %s solved left %s screen ammo %s"
		% [
			ammo.global_position,
			mount.global_position,
			solved.origin,
			get_viewport().get_camera_3d().unproject_position(ammo.global_position)
		]
	)


## The part of the frame around `who`'s chest, `CROP_METRES` wide where the body is.
func _crop_around(who: int, frame: Vector2i) -> Rect2i:
	var camera := get_viewport().get_camera_3d()
	var body := _night.server.body_of(who) if who == MATE else _night.player()
	var chest := body.global_position + Vector3(0.0, 0.9, 0.0)
	var centre := camera.unproject_position(chest)
	var across := camera.global_basis.x * CROP_METRES * 0.5
	var half := absf(camera.unproject_position(chest + across).x - centre.x)
	var size := Vector2(half * 2.0, half * 2.0 * 9.0 / 16.0)
	var rect := Rect2(centre - size * 0.5, size).intersection(Rect2(Vector2.ZERO, Vector2(frame)))
	return Rect2i(rect)


func _send() -> void:
	var command := NightCommand.new()
	command.player_id = Night.PLAYER_ID
	var rig := _night.player().camera_rig
	command.motion.yaw = rig.yaw
	command.motion.pitch = rig.pitch
	var aim := rig.aim_transform()
	command.origin = aim.origin
	command.dir = -aim.basis.z
	command.reload = _reload_me
	_reload_me = false
	_night.link.send(command.to_dict())
	var mate := NightCommand.new()
	mate.player_id = MATE
	mate.motion.yaw = _mate_yaw
	mate.motion.pitch = -0.08
	mate.reload = _reload_mate
	_reload_mate = false
	_night.server.submit(MATE, mate)


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _seconds(seconds: float) -> void:
	await _ticks(int(seconds * SECOND))
