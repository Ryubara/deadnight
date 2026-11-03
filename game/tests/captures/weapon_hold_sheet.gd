extends Node
## Scripted capture of every weapon the Soldier holds, from three views (side, the player's shoulder
## camera, the top) in idle, run, aim and fire (Deadnight, weapon hold fit). Not a test. Run with
## Movie Maker; one view lasts SHOT_SECONDS and prints `SHOT <class> <pose> <view> <frame>` for its
## last frame, the one to keep:
##
##     godot --path game --write-movie <abs>/hold.png --fixed-fps 10 --quit-after N \
##         res://tests/captures/weapon_hold_sheet.tscn
## `-- --only=grenade` films one weapon (its id) alone.
## Also prints `HOLD <class> <pose> ...` lines: the numbers the weapon hold test checks.

const MOVIE_FPS := 10.0
const SHOT_FRAMES := 8
## Every catalogue weapon, each with its own model and hold (`PlayerAnimation.equip`).
const WEAPONS: Array[StringName] = [
	&"rifle", &"shotgun", &"pistol", &"smg", &"flare_gun", &"crowbar", &"dual_pistols", &"grenade"
]
const POSES := ["idle", "run", "aim", "fire"]
## The grenade is thrown, never aimed or fired: its cooked hold, standing and running.
const GRENADE := &"grenade"
const GRENADE_POSES := ["idle", "run"]
const VIEWS := ["side", "shoulder", "rear", "top"]
## The grenade is small: its views include a close one on the hand, beside and from the front.
const GRENADE_VIEWS := ["side", "hand", "front", "top"]
## Where the close cameras stand from the grenade, in the Soldier's frame (x right, z back), metres.
const HAND_BESIDE := Vector3(0.7, 0.1, 0.1)
const HAND_FRONT := Vector3(0.1, 0.15, -0.8)

var _player: Player
var _animation: PlayerAnimation
var _side: Camera3D
var _top: Camera3D
var _rear: Camera3D
var _hand: Camera3D
var _steps: Array = []
var _step := 0
var _frame := 0


func _ready() -> void:
	var room: Node = load("res://world/test_room.tscn").instantiate()
	add_child(room)
	_player = room.get_node("Player") as Player
	_player.capture_mouse = false
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_player.teleport(Vector3(0.0, 0.05, 6.0))
	_side = _camera()
	_top = _camera()
	_rear = _camera()
	_hand = _camera()
	_hand.fov = 30.0
	var only := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):
			only = argument.trim_prefix("--only=")
	for weapon_class in WEAPONS:
		if only != "" and String(weapon_class) != only:
			continue
		for pose in GRENADE_POSES if weapon_class == GRENADE else POSES:
			for view in GRENADE_VIEWS if weapon_class == GRENADE else VIEWS:
				_steps.append([weapon_class, pose, view])
	print("FRAMES ", _steps.size() * SHOT_FRAMES + 12)


func _camera() -> Camera3D:
	var camera := Camera3D.new()
	camera.fov = 40.0
	add_child(camera)
	return camera


func _process(_delta: float) -> void:
	if _frame < 6:
		_frame += 1
		return
	var index := (_frame - 6) / SHOT_FRAMES
	var within := (_frame - 6) % SHOT_FRAMES
	_frame += 1
	if index >= _steps.size():
		get_tree().quit()
		return
	var step: Array = _steps[index]
	_follow(step)
	if within == 0:
		_begin(step, index)
	if within == SHOT_FRAMES - 1:
		print("SHOT %s %s %s %d" % [step[0], step[1], step[2], _frame - 1])
		if step[2] == "side":
			_report(step)


## The side, rear and top cameras keep their place beside the Soldier as he runs.
func _follow(step: Array) -> void:
	var centre := _player.global_position + Vector3(0.0, 1.0, 0.0)
	var yaw := Basis(Vector3.UP, _player.rotation.y)
	_side.global_position = centre + yaw * Vector3(3.2, 0.15, 0.0)
	_side.look_at(centre)
	_top.global_position = centre + Vector3(0.0, 3.4, 0.4)
	_top.look_at(centre, Vector3.FORWARD)
	_rear.global_position = centre + yaw * Vector3(1.9, 0.5, 2.3)
	_rear.look_at(centre + yaw * Vector3(0.0, 0.0, -0.4))
	var grenade := _animation.weapon_mount().get_node("Grenade") as Node3D
	var offset := HAND_FRONT if step[2] == "front" else HAND_BESIDE
	_hand.global_position = grenade.global_position + yaw * offset
	_hand.look_at(grenade.global_position)


func _begin(step: Array, index: int) -> void:
	var weapon_class: StringName = step[0]
	var pose: String = step[1]
	var first_view: bool = (
		index == 0 or _steps[index - 1][0] != weapon_class or _steps[index - 1][1] != pose
	)
	if first_view:
		for action in ["move_forward", "sprint", "aim"]:
			Input.action_release(action)
		_player.teleport(Vector3(0.0, 0.05, 6.0))
		_player.camera_rig.yaw = 0.0
		_player.camera_rig.pitch = 0.0
		if weapon_class == GRENADE:
			_animation.grenade(&"gone")
			_animation.grenade(&"cook")
		elif _animation.weapon_hold() != WeaponHoldMap.hold_for(weapon_class) or index == 0:
			_animation.grenade(&"gone")
			_animation.equip(weapon_class)
		match pose:
			"run":
				Input.action_press("move_forward")
			"aim":
				Input.action_press("aim")
			"fire":
				Input.action_press("aim")
				_animation.play_action(&"Swing" if _animation.weapon_class == &"Melee" else &"Fire")
	match step[2]:
		"side":
			_side.make_current()
		"top":
			_top.make_current()
		"rear":
			_rear.make_current()
		"hand", "front":
			_hand.make_current()
		"shoulder":
			_player.camera_rig.get_node("Camera3D").make_current()


func _report(step: Array) -> void:
	var weapon := _animation.weapon_mount().get_node("Grenade") as Node3D
	if step[0] != GRENADE:
		weapon = _animation.weapon()
	if weapon == null:
		return
	var hand := _animation.weapon_mount().global_position
	var muzzle_dir := (weapon.global_basis * Vector3.LEFT).normalized()
	print(
		(
			"HOLD %s %s grip_to_hand=%.3f visible=%s muzzle_dir=%s"
			% [
				step[0],
				step[1],
				weapon.global_position.distance_to(hand),
				weapon.visible,
				muzzle_dir
			]
		)
	)
