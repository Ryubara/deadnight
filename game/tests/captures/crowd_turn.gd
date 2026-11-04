extends "res://tests/captures/zombie_chase.gd"
## The crowd seen from a player's eye as the player turns round to it (Deadnight #949): the camera
## stands at player 1's head looking away from the crowd, then turns to face it over `TURN_FRAMES`,
## and pictures are saved at the frames round the turn, so the dead the animation throttle left out
## of view (their pose not advanced) can be seen coming into it. Run with a fixed frame rate
## (`--fixed-fps 60`, the same crowd every run) and the same arguments before and after a change:
## `--zombies=99 --warmup=40 --out=<folder>` (pictures `turn_<frame>.png`), `--turn_at=N`.
## Not part of the game.

const TURN_FRAMES := 18
const EYE := Vector3(0.0, 1.7, 0.0)
## Pictures: frames before and after the turn starts.
const SHOT_OFFSETS: Array[int] = [-1, 3, 6, 10, 20, 60]

var _capture_frame := 0
var _away := 0.0
var _toward := 0.0
var _aimed := false


func _ready() -> void:
	await super._ready()
	_label.visible = false


## At the eye of player 1, looking away from the crowd, then round to it.
func _place_camera() -> void:
	super._place_camera()
	if _camera == null or _horde == null:
		return
	if not _aimed:
		_aim()
	var turn_at := int(_args.get("turn_at", 120))
	var share := clampf(float(_capture_frame - turn_at) / TURN_FRAMES, 0.0, 1.0)
	var angle := lerp_angle(_away, _toward, smoothstep(0.0, 1.0, share))
	var eye := _positions[1] + EYE
	_camera.look_at_from_position(eye, eye + Vector3(cos(angle), -0.04, sin(angle)))
	_capture_frame += 1
	if _capture_frame - turn_at in SHOT_OFFSETS:
		_shoot_picture(_capture_frame)


## Faces the middle of the dead standing at the start, and away from it before the turn.
func _aim() -> void:
	var sum := Vector3.ZERO
	var count := 0
	for zombie: ZombieBody in _horde.director.sim.zombies.values():
		sum += zombie.position
		count += 1
	if count == 0:
		return
	_aimed = true
	var to := sum / count - _positions[1]
	_toward = atan2(to.z, to.x)
	_away = _toward + PI


func _shoot_picture(frame: int) -> void:
	var folder := String(_args.get("out", ""))
	if folder.is_empty():
		return
	var path := "%s/turn_%d.png" % [folder, frame]
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)
