extends Node
## A standstill, a sprint, a sprint-jump with the sprint key held through the air, and a landing
## with the key still held, for before and after captures of the sprint camera (not a test; issue
## #405). The player is driven by commands (no device input), so the same script gives the same run
## whatever the camera does, and it never touches the mouse of the person at the machine:
##
##     gds godot -- --path game res://tests/captures/sprint_camera_tune.tscn \
##         --write-movie <abs>/s.png --fixed-fps 30 --quit-after 150
##     godot --headless --path game res://tests/captures/sprint_camera_tune.tscn --quit-after 300
##
## Prints one `TRACE` line per physics tick: seconds, ground speed, sprinting, on the floor, the
## lens FOV, and the turn of the lens against the aim in degrees (pitch, yaw, roll). Reads only
## what the rig has always had (`camera()` and `aim_transform()`), so it runs on `main` too.
## From `AIM_FROM` seconds on the player aims (the aim FOV in the trace).

const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 17.0)
## Seconds: the sprint starts, the jump is pressed (one tick), the sprint ends, the run ends.
const SPRINT_AT := 0.5
const JUMP_AT := 2.5
const SPRINT_END := 4.5
const AIM_FROM := 5.0
const END_AT := 6.0

var _ticks := 0
var _player: Player


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var room: Node = load("res://world/test_room.tscn").instantiate()
	add_child(room)
	_player = room.get_node("Player") as Player
	_player.capture_mouse = false
	_player.local_input = false
	_player.teleport(START)
	_player.camera_rig.yaw = 0.0
	_player.camera_rig.pitch = 0.0


func _physics_process(_delta: float) -> void:
	var now := _ticks * TICK
	_ticks += 1
	var command := PlayerCommand.new()
	if now >= SPRINT_AT and now < SPRINT_END:
		command.move = Vector2(0.0, -1.0)
		command.sprint = true
		command.jump = absf(now - JUMP_AT) < TICK * 0.5
	command.aim = now >= AIM_FROM
	_player.submit_command(command)
	var rig := _player.camera_rig
	var turn := rig.aim_transform().basis.inverse() * rig.camera().global_transform.basis
	var euler := turn.get_euler() * (180.0 / PI)
	print(
		(
			"TRACE %.4f %.3f %d %d %.3f %.4f %.4f %.4f"
			% [
				now,
				_player.ground_speed(),
				int(_player.is_sprinting()),
				int(_player.state.on_floor),
				rig.camera().fov,
				euler.x,
				euler.y,
				euler.z
			]
		)
	)
	if now >= END_AT:
		get_tree().quit()
