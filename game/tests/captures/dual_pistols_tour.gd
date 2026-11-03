extends Node
## The dual pistols from the player's shoulder camera and from the side, front and behind (issue
## #789; not a test): a pistol in each hand, holding at the hip, aiming, firing (the hands
## alternate, each gun with its own flash and kick), a reload (both cylinders open), a sprint, a
## sprint into the aim and the quick melee. The player is driven by commands, no device input, so
## the same script gives the same run on any build. One run films one view:
##
##     gds godot -- --path game res://tests/captures/dual_pistols_tour.tscn \
##         --write-movie <abs>/f.png --fixed-fps 30 --quit-after 270 [-- --view=side|front|rear|top]
##
## Without `--view` the shoulder camera (the player's own) films. Prints one `BEAT` line per beat
## with the frame (30 fps) it starts at.

const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 17.0)
const WEAPON := &"dual_pistols"
## Seconds into the turn: each beat starts at the time it names.
const HOLD_AT := 0.9
const AIM_AT := 1.6
const FIRE_AT := 2.2
const FIRE_END := 3.4
const RELOAD_AT := 3.8
const SPRINT_AT := 6.2
const SPRINT_AIM_AT := 7.4
const SPRINT_END := 8.0
const STRIKE_AT := 8.4
const TURN := 9.4
## The reload's length, as the catalogue gives it, and the shots' interval.
const RELOAD_SECONDS := 1.6
const SHOT_INTERVAL := 0.15
## The cameras beside the player, in his frame (x right, y up, z back), and the point they look at.
const VIEWS := {
	"side": Vector3(3.0, 1.1, 0.0),
	"front": Vector3(1.2, 1.2, -3.0),
	"rear": Vector3(0.0, 1.5, 3.0),
	"top": Vector3(0.2, 3.6, 0.6),
}
const LOOK := Vector3(0.0, 0.95, 0.0)

var _ticks := 0
var _player: Player
var _animation: PlayerAnimation
var _camera: Camera3D
var _view := ""
var _hand := 0
var _next_shot := 0.0
var _beats := {}


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var room: Node = load("res://world/test_room.tscn").instantiate()
	add_child(room)
	_player = room.get_node("Player") as Player
	_player.capture_mouse = false
	_player.local_input = false
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--view="):
			_view = argument.trim_prefix("--view=")
	if VIEWS.has(_view):
		_camera = Camera3D.new()
		_camera.fov = 40.0
		add_child(_camera)
		_camera.make_current()
	_player.teleport(START)
	_player.camera_rig.yaw = 0.0
	_player.camera_rig.pitch = -0.08
	_animation.equip(WEAPON)


func _process(_delta: float) -> void:
	if _camera == null:
		return
	var at := _player.global_position
	var yaw := Basis(Vector3.UP, _player.rotation.y)
	if _view == "front":
		# Looks at the player from ahead and to his right: both hands and both guns face the lens.
		_camera.look_at_from_position(at + yaw * VIEWS[_view], at + LOOK)
	else:
		_camera.look_at_from_position(at + yaw * VIEWS[_view], at + LOOK, Vector3.UP)


func _physics_process(_delta: float) -> void:
	var total := _ticks * TICK
	_ticks += 1
	if total >= TURN:
		get_tree().quit()
		return
	_beat("hold", total, HOLD_AT)
	_beat("aim", total, AIM_AT)
	_beat("fire", total, FIRE_AT)
	_beat("reload", total, RELOAD_AT)
	_beat("sprint", total, SPRINT_AT)
	_beat("sprint_aim", total, SPRINT_AIM_AT)
	_beat("strike", total, STRIKE_AT)
	var command := PlayerCommand.new()
	command.yaw = _player.camera_rig.yaw
	command.pitch = _player.camera_rig.pitch
	command.aim = (
		(total >= AIM_AT and total < RELOAD_AT + 0.3)
		or (total >= SPRINT_AIM_AT and total < SPRINT_END)
	)
	if total >= SPRINT_AT and total < SPRINT_END:
		command.move = Vector2(0.0, -1.0)
		command.sprint = true
	_player.submit_command(command)
	if total >= FIRE_AT and total < FIRE_END and total >= _next_shot:
		_shoot()
		_next_shot = total + SHOT_INTERVAL
	if absf(total - RELOAD_AT) < TICK * 0.5:
		_animation.reload(RELOAD_SECONDS)
		_animation.play_action(&"Reload")
	if absf(total - STRIKE_AT) < TICK * 0.5:
		_animation.strike()


## One shot of the next hand: its clip and kick, and the flash on its own muzzle.
func _shoot() -> void:
	_animation.play_action(&"Fire", _hand)
	var muzzle := _animation.muzzle_point(_hand)
	if muzzle != null:
		MuzzleFlash.on(muzzle).fire(0.3, -muzzle.global_basis.z)
	_hand = 1 - _hand


func _beat(name: String, total: float, at: float) -> void:
	if _beats.has(name) or total < at:
		return
	_beats[name] = true
	print("BEAT %s frame %d (30 fps)" % [name, roundi(total * 30.0)])
