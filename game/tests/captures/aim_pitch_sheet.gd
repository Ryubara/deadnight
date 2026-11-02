extends Node
## Scripted capture of the Soldier's aim pitch for every weapon: the hip, aimed up and aimed down,
## from the player's own shoulder camera and from the side, so the lean of the body and the hands
## on the weapon can be judged (docs/design/weapon-hold.md, "Aim pitch"). Not a test. Run with
## Movie Maker; one view lasts SHOT_FRAMES and prints `SHOT <weapon> <pose> <view> <frame>` for its
## last frame, the one to keep:
##
##     godot --path game --write-movie <abs>/pitch.png --fixed-fps 10 --quit-after N \
##         res://tests/captures/aim_pitch_sheet.tscn [-- --off]
##
## With `--off` the spine does not lean (`PlayerTuning.spine_pitch_follow` 0): the sheet from before
## the change. Also prints `LEAN <weapon> <pose> <degrees>`: the spine's bend.

const SHOT_FRAMES := 10
## Every catalogue weapon, each with its own model and hold (`PlayerAnimation.equip`).
const WEAPONS: Array[StringName] = [
	&"rifle", &"shotgun", &"pistol", &"smg", &"flare_gun", &"crowbar"
]
## Pose name: [view pitch in degrees, whether the aim button is held].
const POSES := {
	"warm": [0.0, false], "hip": [0.0, false], "aim_up": [40.0, true], "aim_down": [-45.0, true]
}
const VIEWS := ["shoulder", "side"]

var _player: Player
var _animation: PlayerAnimation
var _side: Camera3D
var _steps: Array = []
var _frame := 0


func _ready() -> void:
	var room: Node = load("res://world/test_room.tscn").instantiate()
	add_child(room)
	_player = room.get_node("Player") as Player
	_player.capture_mouse = false
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_player.teleport(Vector3(0.0, 0.05, 6.0))
	if "--off" in OS.get_cmdline_user_args():
		_player.tuning.spine_pitch_follow = 0.0
	_side = Camera3D.new()
	_side.fov = 40.0
	add_child(_side)
	for weapon in WEAPONS:
		# The equip clip plays during the warm-up step, which is not kept.
		_steps.append([weapon, "warm", "side"])
		for pose in POSES:
			if pose != "warm":
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
	_follow()
	if index >= _steps.size():
		get_tree().quit()
		return
	var step: Array = _steps[index]
	if within == 0:
		_begin(step, index)
	if within == SHOT_FRAMES - 1 and step[1] != "warm":
		print("SHOT %s %s %s %d" % [step[0], step[1], step[2], _frame - 1])
		if step[2] == "side":
			print("LEAN %s %s %.1f" % [step[0], step[1], rad_to_deg(_animation.spine_bend())])


## The side camera keeps its place beside the Soldier.
func _follow() -> void:
	var centre := _player.global_position + Vector3(0.0, 1.0, 0.0)
	var yaw := Basis(Vector3.UP, _player.rotation.y)
	_side.global_position = centre + yaw * Vector3(3.2, 0.15, 0.0)
	_side.look_at(centre)


func _begin(step: Array, index: int) -> void:
	var weapon: StringName = step[0]
	var pose: String = step[1]
	var first_view: bool = (
		index == 0 or _steps[index - 1][0] != weapon or _steps[index - 1][1] != pose
	)
	if first_view:
		Input.action_release("aim")
		_player.camera_rig.yaw = 0.0
		_player.camera_rig.pitch = deg_to_rad(POSES[pose][0])
		if index == 0 or _steps[index - 1][0] != weapon:
			_animation.equip(weapon)
		if POSES[pose][1]:
			Input.action_press("aim")
	match step[2]:
		"side":
			_side.make_current()
		"shoulder":
			_player.camera_rig.get_node("Camera3D").make_current()
