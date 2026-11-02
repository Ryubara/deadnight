extends Node
## The sprint carry from the shoulder camera, a weapon of every class in turn (issue #459; not a
## test): the catalogue's rifle, shotgun, revolver and crowbar, with their own models and holds:
## a standstill, a sprint, a sprint into the aim (the carry gives way), the sprint again, a
## sprint-jump with the key held through the air and the landing, a standstill. The player is driven
## by commands (no device input, the mouse never captured), so the same script gives the same run on
## any build, `main` included, for before and after captures:
##
##     gds godot -- --path game res://tests/captures/sprint_carry_tour.tscn \
##         --write-movie <abs>/f.png --fixed-fps 30 --quit-after 560
##
## Prints one `TOUR` line per weapon and one `TRACE` line per tick: the weapon, seconds into its
## turn, sprinting, on the floor, and (on a build that has it) the carry's weight and its clip's
## place against the Run's.

const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 17.0)
const WEAPONS: Array[StringName] = [&"rifle", &"shotgun", &"pistol", &"crowbar"]
## Seconds into each class's turn: the sprint starts, the aim is held, let go, the jump is pressed,
## the sprint ends, the turn ends.
const SPRINT_AT := 0.3
const AIM_AT := 1.8
const AIM_END := 2.4
const JUMP_AT := 3.2
const SPRINT_END := 4.2
const TURN := 4.6

var _ticks := 0
var _class := -1
var _player: Player
var _animation: PlayerAnimation


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var room: Node = load("res://world/test_room.tscn").instantiate()
	add_child(room)
	_player = room.get_node("Player") as Player
	_player.capture_mouse = false
	_player.local_input = false
	_animation = _player.get_node("AnimationTree") as PlayerAnimation


func _physics_process(_delta: float) -> void:
	var total := _ticks * TICK
	_ticks += 1
	var turn := int(total / TURN)
	if turn >= WEAPONS.size():
		get_tree().quit()
		return
	var now := total - turn * TURN
	if turn != _class:
		_class = turn
		_player.teleport(START)
		_player.camera_rig.yaw = 0.0
		_player.camera_rig.pitch = -0.08
		_animation.equip(WEAPONS[turn])
		print(
			(
				"TOUR %s (%s) from frame %d (30 fps)"
				% [WEAPONS[turn], _animation.weapon_class, roundi(total * 30.0)]
			)
		)
	var command := PlayerCommand.new()
	command.yaw = _player.camera_rig.yaw
	command.pitch = _player.camera_rig.pitch
	if now >= SPRINT_AT and now < SPRINT_END:
		command.move = Vector2(0.0, -1.0)
		command.sprint = true
		command.aim = now >= AIM_AT and now < AIM_END
		command.jump = absf(now - JUMP_AT) < TICK * 0.5
	_player.submit_command(command)
	var carry := ""
	if _animation.has_method(&"sprint_carry"):
		carry = (
			" %.3f %.3f %.3f"
			% [_animation.sprint_carry(), _animation.sprint_carry_time(), _animation.run_time()]
		)
	print(
		(
			"TRACE %s %.3f %d %d%s"
			% [WEAPONS[turn], now, int(_player.is_sprinting()), int(_player.state.on_floor), carry]
		)
	)
