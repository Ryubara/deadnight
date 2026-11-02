extends Node
## The downed pose and the reviver's kneel in the night (#504), from the player's own shoulder
## camera, from the side and from above. Not part of the game. Run windowed (never headless: it
## saves what the window draws), off the person's desktop:
## `gds godot -- --path game res://tests/captures/revive_poses.tscn --quit-after 3600
## -- --out <dir>`.
##
## Stages, one PNG each: `before_*` is what a downed player looked like until now (their own body
## standing, a teammate's avatar tipped over by `RemoteAvatars.DOWNED_TILT`); `downed_*` the own
## player down through `PlayerAnimation.set_downed`; `revive_*` the own player kneeling through
## `set_reviving` beside a teammate drawn as another player's avatar is (a dressed Soldier whose
## library gets the clips from `DownedPose.add_clips`), lying in `Downed_Idle`.
## Nothing here talks to the rules: the revive rules are another branch (#486); this drives the
## view.

## Physics ticks in a second of game time.
const SECOND := 60
## How far ahead of the kneeling Soldier his hands press (Revive_Kneel's hands at kit scale, 0.66 m
## ahead and 0.36 m up, times the game's 0.8).
const REVIVE_HANDS_AHEAD := 0.53

var _night: Night
var _out := ""
var _own_camera: Camera3D
var _camera: Camera3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--out")
	_out = (
		args[at + 1]
		if at >= 0 and at + 1 < args.size()
		else OS.get_user_data_dir() + "/revive_poses"
	)
	DirAccess.make_dir_recursive_absolute(_out)
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = 600.0  # no zombies: the poses alone
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	await _night.start(Night.Mode.HUMAN, 7, tuning)
	var player := _night.player()
	player.local_input = false  # the real mouse and keys never steer a capture
	player.capture_mouse = false
	var anim := player.get_node("AnimationTree") as PlayerAnimation
	_camera = Camera3D.new()
	_camera.fov = 45.0
	# Placed between ticks: under physics interpolation it would draw where the last tick left it.
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)
	await _hold(SECOND)
	_own_camera = get_viewport().get_camera_3d()
	var spot := player.global_position
	var facing := player.state.facing
	_face(player, facing)

	# Before: the own body standing (nothing played Downed), a teammate's avatar tipped over.
	var mate := _teammate()
	var mate_model := mate.get_child(0) as Node3D
	var mate_clips := mate_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	DownedPose.add_clips(mate_clips)
	mate.position = spot + _right(facing) * 1.4 + _ahead(facing) * 1.2
	mate.rotation = Vector3(RemoteAvatars.DOWNED_TILT, facing, 0.0)
	mate_clips.play(&"Idle")
	await _hold(SECOND)
	await _shot("before_shoulder")
	await _view_from_side(spot, facing, "before_side")

	# After: the own player down.
	mate.visible = false
	anim.set_downed(true)
	await _hold(SECOND * 2)
	_stage("downed, weight %.2f" % anim.downed_weight())
	await _shot("downed_shoulder")
	# The same camera looking down, as a downed player does with the mouse (the rig keeps its standing
	# height and its pitch while down: framing the body is the camera's, not the clip's).
	await _looking_down(player, "downed_shoulder_down")
	await _view_from_side(spot, facing, "downed_side")
	_camera.global_position = spot + Vector3.UP * 4.2 + _ahead(facing) * -0.6
	_camera.look_at(spot, _ahead(facing))
	_camera.make_current()
	await _shot("downed_top")
	_own_camera.make_current()
	anim.set_downed(false)
	await _hold(SECOND * 2)

	# The reviver: the own player kneels at a downed teammate's right side, the hands on the belly.
	mate.visible = true
	mate.rotation = Vector3(0.0, facing, 0.0)
	mate.position = spot + _ahead(facing) * 2.5
	mate_clips.play(&"Downed_Idle")
	await _hold(SECOND / 2)
	# The hands go on the belly, where the downed hand holds the wound: at the chest, the two big
	# heads meet.
	var chest := _bone_position(mate_model, "Abdomen") + _ahead(facing) * 0.2
	var kneel_facing := facing + PI / 2.0  # facing back across the body from the teammate's right
	var at_body := Vector3(chest.x, spot.y, chest.z) - _ahead(kneel_facing) * REVIVE_HANDS_AHEAD
	player.teleport(at_body)
	_face(player, kneel_facing)
	anim.set_reviving(true)
	await _hold(75)  # 1.25 s: into a press (frame 6 of the 24-frame loop)
	_stage("reviving, weight %.2f" % anim.kneel_weight())
	await _shot("revive_shoulder")
	await _looking_down(player, "revive_shoulder_down")
	# Three quarters from the front of the kneeling Soldier, back far enough to see both bodies.
	var between := at_body.lerp(Vector3(chest.x, spot.y, chest.z), 0.5)
	_camera.global_position = (
		between + _right(kneel_facing) * 3.0 + _ahead(kneel_facing) * 2.4 + Vector3.UP * 1.4
	)
	_camera.look_at(between + Vector3.UP * 0.3)
	_camera.make_current()
	await _shot("revive_side")
	_own_camera.make_current()
	anim.set_reviving(false)
	await _hold(SECOND)
	_stage("end")
	get_tree().quit()


## A Soldier dressed as another player's avatar is (the second seat's preset), at the size and the
## half turn every drawn player has (RemoteAvatars).
func _teammate() -> Node3D:
	var holder := Node3D.new()
	holder.name = "Teammate"
	holder.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # as RemoteAvatars
	var model := CharacterAssembler.assemble(CharacterLook.from_preset(1), 1)
	model.basis = (
		Basis(Vector3.UP, PI)
		* Basis.from_scale(Vector3.ONE * RemoteAvatars.PLAYER_TUNING.model_scale)
	)
	holder.add_child(model)
	add_child(holder)
	return holder


func _looking_down(player: Player, name: String) -> void:
	player.camera_rig.pitch = -0.5
	await _hold(SECOND / 2)
	await _shot(name)
	player.camera_rig.pitch = 0.0
	await _hold(SECOND / 2)


func _face(player: Player, facing: float) -> void:
	player.state.facing = facing
	player.camera_rig.yaw = facing
	player.camera_rig.snap_to(player.global_position)


## From the body's right, level with it, looking at it; then back to the player's camera.
func _view_from_side(spot: Vector3, facing: float, name: String, distance := 3.0) -> void:
	_camera.global_position = spot + _right(facing) * distance + Vector3.UP * 0.9
	_camera.look_at(spot + Vector3.UP * 0.35)
	_camera.make_current()
	await _shot(name)
	_own_camera.make_current()


func _bone_position(model: Node3D, bone_name: String) -> Vector3:
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var bone := skeleton.find_bone(bone_name)
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin


static func _ahead(facing: float) -> Vector3:
	return Vector3(-sin(facing), 0.0, -cos(facing))


static func _right(facing: float) -> Vector3:
	return Vector3(cos(facing), 0.0, -sin(facing))


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [_out, name]
	get_viewport().get_texture().get_image().save_png(path)
	_stage("%s -> %s" % [name, path])


func _stage(stage: String) -> void:
	print("STAGE %s at frame %d" % [stage, Engine.get_frames_drawn()])


func _hold(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
