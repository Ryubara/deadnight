extends Node
## The prize crane from the player's shoulder camera, for captures: the player stands at the
## crane, pays, watches the claw dig and the weapons cycle, takes the prize. With `--breakdown` the
## play breaks the crane down instead (a dud, sparks, the power goes, the crane is gone) and with
## `--beam` the camera looks along the lot to show the light beam. With `--prizes` the crane is
## played once for every weapon of its pool (it never breaks down) and `PRIZE <weapon> <movie
## frame>` is printed for the frame where each prize floats in its window. Not part of the game.
## Run it with Movie Maker: `godot --path game res://tests/captures/crane_tour.tscn --fixed-fps 10
## --write-movie out.png --quit-after 260 -- [--breakdown] [--beam]`.

## Frames are physics ticks, 60 a second.
const HOLD := 90
const SHOULDER_PITCH := 0.16
## Ticks of a play: the spin (4.5 s), a moment of the prize floating, and the weapon in hand after.
const SPIN_TICKS := 280
const FLOAT_TICKS := 60
const TAKEN_TICKS := 60
const TICKS_PER_FRAME := 6

var _night: Night
var _yaw := 0.0
var _use := false
var _args := {}
var _ticks := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		_args[arg.trim_prefix("--").get_slice("=", 0)] = (
			arg.get_slice("=", 1) if "=" in arg else "1"
		)
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	var tuning := (
		(load(GameRules.DEFAULT_TUNING_PATH) as RulesTuning).duplicate(true) as RulesTuning
	)
	if _args.has("breakdown"):
		tuning.crane.safe_plays = 0
		tuning.crane.leave_chances = PackedFloat32Array([1.0])
	if _args.has("prizes"):
		tuning.crane.leave_chances = PackedFloat32Array([0.0])
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, 7, tuning)
	# The real mouse and keys must not turn the camera or move the body in a recording.
	_night.player().local_input = false
	_night.player().capture_mouse = false
	_night.ticked.connect(_send)
	_night.state.apply_events(_night.server.rules.apply(RulesAction.grant_points(1, 5000)))
	# The concession is open, so the crane in the stand can be reached and the others can be moved to.
	_night.state.apply_events(_night.server.rules.apply(RulesAction.buy(1, &"door_concession")))
	if _args.has("beam"):
		# The crane on the open field, so the beam stands against the sky.
		_night.server.rules.crane.spot = 2
		await _hold(10)
	_night.player().camera_rig.camera().make_current()
	await _play()
	get_tree().quit()


func _play() -> void:
	await _hold(5)
	var at := _crane_marker()
	var crane_at: Vector3 = _night.view.crane.crane.global_position
	var standing := at["position"] as Vector3
	var toward := crane_at - standing
	# Back from the glass and to one side, still in reach of the spot (`spot_reach`, 1.5 m), so the
	# whole crane is in frame.
	var flat := Vector3(toward.x, 0.0, toward.z).normalized()
	var side := Vector3(flat.z, 0.0, -flat.x) * 0.9
	_night.player().teleport(standing - flat * 1.0 + side + Vector3(0.0, 0.1, 0.0))
	_yaw = atan2(-toward.x, -toward.z)
	_night.player().camera_rig.yaw = _yaw
	_night.player().camera_rig.pitch = SHOULDER_PITCH
	if _args.has("beam"):
		await _beam()
		return
	if _args.has("prizes"):
		await _prizes()
		return
	await _hold(HOLD)
	_use = true
	await _hold(1)
	_use = false
	if _args.has("breakdown"):
		# The spin, the dud, the sparks and the power-down, then the crane is gone.
		await _hold(300 + 330 + 120)
	else:
		# The spin, then the weapon floats for a moment before it is taken.
		await _hold(300 + 120)
		_use = true
		await _hold(1)
		_use = false
		await _hold(120)


## One play for every weapon of the pool: pay, the spin, the prize floating (its frame is printed),
## take it. The movie runs at `MOVIE_FPS`, so a frame is the ticks over `TICKS_PER_FRAME`.
func _prizes() -> void:
	var pool: Array[StringName] = _night.server.rules.tuning.economy.item(&"crane_play").pool
	await _hold(HOLD)
	for _i in pool.size():
		_use = true
		await _hold(1)
		_use = false
		await _hold(SPIN_TICKS + FLOAT_TICKS)
		var prize := String(_night.server.rules.crane.weapon)
		print("PRIZE %s %d" % [prize, _ticks / TICKS_PER_FRAME])
		_use = true
		await _hold(1)
		_use = false
		await _hold(TAKEN_TICKS)


## From the shoulder camera, turned to look down the lot from the stand toward the crane's beam.
func _beam() -> void:
	var rig := _night.player().camera_rig
	rig.pitch = 0.5
	await _hold(120)


func _crane_marker() -> Dictionary:
	for spot in _night.world.shop_spots():
		if spot["kind"] == &"crane" and spot["crane_spot"] == _night.server.rules.crane.spot:
			return spot
	return {}


func _send() -> void:
	var command := NightCommand.new()
	command.motion.yaw = _yaw
	command.use = _use
	_night.link.send(command.to_dict())
	var rig := _night.player().camera_rig
	rig.yaw = _yaw


func _hold(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
		_ticks += 1
