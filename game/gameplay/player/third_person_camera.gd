class_name ThirdPersonCamera
extends Node3D
## Over-the-shoulder camera rig: look (mouse and stick), shoulder swap, aim zoom, wall collision.
##
## The rig follows its target but does not rotate with it (it is a top-level node), so the player
## turns to face the camera instead of the camera swinging with the player. A SpringArm3D sweeps a
## sphere from the pivot to the camera and pulls the camera in when a wall is in the way. The
## shoulder offset is applied after the arm, so the arm's start is never inside a crate the player
## leans on.

## Yaw in radians; the player's body follows this while aiming.
var yaw := 0.0
## Pitch in radians; positive looks up.
var pitch := 0.0
var invert_y := false
var sensitivity := 1.0
## +1 camera over the right shoulder, -1 over the left. Set from the player's state.
var side := 1.0
var aiming := false

var _tuning: PlayerTuning
var _target: Node3D
var _shoulder_pos := 0.0
var _aim := 0.0
var _look_input := Vector2.ZERO

@onready var _pitch_node: Node3D = $Pitch
@onready var _arm: SpringArm3D = $Pitch/SpringArm3D
@onready var _shoulder: Node3D = $Pitch/SpringArm3D/Shoulder
@onready var _camera: Camera3D = $Pitch/SpringArm3D/Shoulder/Camera3D


## Called by the player once: which node to follow, and the numbers.
func setup(target: CharacterBody3D, tuning: PlayerTuning) -> void:
	_target = target
	_tuning = tuning
	top_level = true
	_arm.add_excluded_object(target.get_rid())
	var sphere := SphereShape3D.new()
	sphere.radius = tuning.arm_margin
	_arm.shape = sphere
	_arm.spring_length = tuning.arm_length
	_camera.fov = tuning.fov
	_shoulder_pos = side * tuning.shoulder_offset
	_shoulder.position.x = _shoulder_pos
	_follow()


## Turn the view by radians: yaw to the right, pitch down (mouse convention). Honours invert Y.
func apply_look(yaw_right: float, pitch_down: float) -> void:
	yaw = wrapf(yaw - yaw_right, -PI, PI)
	var direction := 1.0 if invert_y else -1.0
	pitch = clampf(
		pitch + direction * pitch_down,
		deg_to_rad(_tuning.pitch_min_degrees),
		deg_to_rad(_tuning.pitch_max_degrees)
	)


## Mouse motion in pixels.
func look_mouse(relative: Vector2) -> void:
	var scale_factor := _tuning.mouse_radians_per_pixel * sensitivity * _look_scale()
	apply_look(relative.x * scale_factor, relative.y * scale_factor)


## Right stick, x right and y down, -1..1; held until set again and applied every frame.
func set_stick(stick: Vector2) -> void:
	_look_input = stick


func is_aim_zoomed() -> bool:
	return _aim > 0.5


## How far the aim zoom has eased in, 0 to 1.
func aim_amount() -> float:
	return _aim


func camera() -> Camera3D:
	return _camera


## Current distance from pivot to camera after wall collision.
func arm_hit_length() -> float:
	return _arm.get_hit_length()


func _process(delta: float) -> void:
	if _tuning == null:
		return
	if _look_input != Vector2.ZERO:
		var stick := _look_input * _look_input.length()
		var rate := (
			deg_to_rad(_tuning.stick_degrees_per_second) * sensitivity * _look_scale() * delta
		)
		apply_look(stick.x * rate, stick.y * rate)
	_ease(delta)
	_follow()


func _look_scale() -> float:
	return lerpf(1.0, _tuning.aim_sensitivity_scale, _aim)


func _ease(delta: float) -> void:
	_aim = lerpf(_aim, 1.0 if aiming else 0.0, 1.0 - exp(-_tuning.aim_rate * delta))
	var swap_t := 1.0 - exp(-_tuning.swap_rate * delta)
	var offset := lerpf(_tuning.shoulder_offset, _tuning.shoulder_offset_aim, _aim)
	_shoulder_pos = lerpf(_shoulder_pos, side * offset, swap_t)
	_shoulder.position.x = _shoulder_pos
	_arm.spring_length = lerpf(_tuning.arm_length, _tuning.arm_length_aim, _aim)
	_camera.fov = lerpf(_tuning.fov, _tuning.fov_aim, _aim)


func _follow() -> void:
	# Between physics ticks the body is a fraction of a tick ahead of where it was last placed.
	var ahead: Vector3 = (
		_target.velocity
		* (Engine.get_physics_interpolation_fraction() / Engine.physics_ticks_per_second)
	)
	global_position = _target.global_position + Vector3(0.0, _tuning.pivot_height, 0.0) + ahead
	rotation = Vector3(0.0, yaw, 0.0)
	_pitch_node.rotation.x = pitch
