extends Node
## Scripted capture of the Soldier's hands on every weapon (Deadnight #460): the player's shoulder
## camera, then close views of the right hand from his right (the trigger finger) and of the left
## hand on the fore-end from his left (for a one-handed weapon, the right hand from the front-left),
## at the hip and aimed. Not a test. Run with Movie Maker; each view lasts SHOT_FRAMES and prints
## `SHOT <weapon> <pose> <view> <frame>` for its last frame, the one to keep:
##
##     gds godot -- --path game --write-movie <abs>/grips.png --fixed-fps 10 --quit-after N \
##         res://tests/captures/hand_grip_sheet.tscn

const SHOT_FRAMES := 8
const WEAPONS: Array[StringName] = [
	&"pistol", &"flare_gun", &"smg", &"rifle", &"shotgun", &"crowbar", &"Melee"
]
const POSES := ["idle", "aim"]
const VIEWS := ["shoulder", "right", "front"]

var _player: Player
var _animation: PlayerAnimation
var _skeleton: Skeleton3D
var _close: Camera3D
var _steps: Array = []
var _frame := 0


func _ready() -> void:
	var room: Node = load("res://world/test_room.tscn").instantiate()
	add_child(room)
	_player = room.get_node("Player") as Player
	_player.capture_mouse = false
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_skeleton = _player.find_child("Skeleton3D", true, false) as Skeleton3D
	_player.teleport(Vector3(0.0, 0.05, 6.0))
	_close = Camera3D.new()
	_close.fov = 26.0
	_close.near = 0.02
	add_child(_close)
	for weapon in WEAPONS:
		for pose in POSES:
			for view in VIEWS:
				_steps.append([weapon, pose, view])
	print("FRAMES ", _steps.size() * SHOT_FRAMES + 12)


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
	if within == 0:
		_begin(step, index)
	_follow(step[2])
	if within == SHOT_FRAMES - 1:
		print("SHOT %s %s %s %d" % [step[0], step[1], step[2], _frame - 1])


func _bone(name: String) -> Vector3:
	return (
		_skeleton.global_transform
		* _skeleton.get_bone_global_pose(_skeleton.find_bone(name)).origin
	)


## The close camera looks at the right hand on the grip from the Soldier's right (the trigger
## finger's side), or from in front of him at the left hand on the fore-end (the right hand when
## the left holds nothing).
func _follow(view: String) -> void:
	if view == "shoulder":
		return
	var weapon := _animation.weapon()
	var right_hand := _bone("Index1.R")
	var grip := right_hand if weapon == null else right_hand.lerp(weapon.global_position, 0.5)
	var hold := _animation.weapon_hold()
	var left_on := (
		_animation.shoulder_blend() > 0.5 and hold != null and hold.support != Vector3.ZERO
	)
	var centre := grip
	var offset := Vector3(1.35, 0.18, -0.2)
	if view == "front":
		if left_on:
			# The support hand from the Soldier's left, a little ahead of it.
			centre = weapon.to_global(hold.support)
			offset = Vector3(-1.3, 0.25, -0.55)
		else:
			offset = Vector3(-0.45, 0.3, -1.3)
	var yaw := Basis(Vector3.UP, _player.rotation.y)
	_close.global_position = centre + yaw * offset
	_close.look_at(centre)


func _begin(step: Array, index: int) -> void:
	var weapon: StringName = step[0]
	var pose: String = step[1]
	var first_view: bool = (
		index == 0 or _steps[index - 1][0] != weapon or _steps[index - 1][1] != pose
	)
	if first_view:
		Input.action_release("aim")
		_player.teleport(Vector3(0.0, 0.05, 6.0))
		_player.camera_rig.yaw = 0.0
		_player.camera_rig.pitch = 0.0
		if index == 0 or _steps[index - 1][0] != weapon:
			_animation.equip(weapon)
		if pose == "aim":
			Input.action_press("aim")
	if step[2] == "shoulder":
		_player.camera_rig.get_node("Camera3D").make_current()
	else:
		_close.make_current()
