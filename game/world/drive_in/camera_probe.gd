class_name CameraProbe
extends RefCounted
## Sweeps the player's over-the-shoulder camera rig through the world, without a player in the
## scene.
##
## The numbers are the player's (`PlayerTuning`: pivot 1.55 m up, shoulder 0.75 m, arm 2.8 m, a 0.25
## m sphere on the arm). The rig sweeps the arm straight back from the pivot, then moves the camera
## sideways by the shoulder offset WITHOUT a second sweep, so a narrow place is not only about the
## arm: the shoulder camera can end up inside the wall. `docs/research/greybox-and-captures.md` has
## the measurements. Used by the world tests and the capture rig.

const PIVOT_HEIGHT := 1.55
const SHOULDER := 0.75
const ARM_LENGTH := 2.8
const ARM_MARGIN := 0.25
## Air the camera needs around it: the near plane (0.05 m) and a little more.
const CAMERA_CLEAR := 0.1
const PLAYER_TUNING: PlayerTuning = preload("res://gameplay/player/player_tuning_default.tres")


## The player's body, read from its tuning: `Player` builds its capsule from the same two numbers.
static func body_radius() -> float:
	return PLAYER_TUNING.radius


static func body_height() -> float:
	return PLAYER_TUNING.height


## How high a full jump lifts the feet.
static func jump_height() -> float:
	return PLAYER_TUNING.jump_height


## The rig for a player standing at `feet` and looking along `yaw` (radians, 0 looks down -Z),
## camera over the right shoulder when `side` is 1 and the left when -1. Returns {arm, camera,
## pivot, free}: `arm` is the arm's length after the sweep, `camera` where the camera sits, `free`
## whether the camera has air around it and sees the pivot.
static func rig(
	space: PhysicsDirectSpaceState3D,
	feet: Vector3,
	yaw: float,
	side: float = 1.0,
	pitch: float = 0.0,
	arm_length: float = ARM_LENGTH,
) -> Dictionary:
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var pivot := feet + Vector3(0.0, PIVOT_HEIGHT, 0.0)
	var sphere := SphereShape3D.new()
	sphere.radius = ARM_MARGIN
	var sweep := PhysicsShapeQueryParameters3D.new()
	sweep.shape = sphere
	sweep.transform = Transform3D(Basis.IDENTITY, pivot)
	sweep.motion = basis.z * arm_length
	var fractions := space.cast_motion(sweep)
	var arm := arm_length * (fractions[0] if fractions.size() == 2 else 0.0)
	var arm_end := pivot + basis.z * arm
	var camera := arm_end + basis.x * (SHOULDER * side)
	return {
		"arm": arm,
		"camera": camera,
		"pivot": pivot,
		"free": _is_free(space, arm_end, camera, pivot)
	}


## True when a standing body (the player or a zombie) can stand at `feet`.
static func body_fits(
	space: PhysicsDirectSpaceState3D, feet: Vector3, radius: float = -1.0
) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = body_radius() if radius < 0.0 else radius
	capsule.height = body_height()
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	# Lifted a little so the capsule does not graze the ground slab.
	query.transform = Transform3D(
		Basis.IDENTITY, feet + Vector3(0.0, body_height() / 2.0 + 0.05, 0.0)
	)
	return space.intersect_shape(query, 1).is_empty()


## The camera is free when a small sphere can travel from the arm's end to the camera (the shoulder
## offset does not go through a wall: the physics server ignores a shape whose centre is already
## inside a mesh, so the sweep starts from the arm's end, which is clear) and the camera still sees
## the player's head.
static func _is_free(
	space: PhysicsDirectSpaceState3D, arm_end: Vector3, camera: Vector3, pivot: Vector3
) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = CAMERA_CLEAR
	var sweep := PhysicsShapeQueryParameters3D.new()
	sweep.shape = sphere
	sweep.transform = Transform3D(Basis.IDENTITY, arm_end)
	sweep.motion = camera - arm_end
	var fractions := space.cast_motion(sweep)
	if fractions.size() != 2 or fractions[0] < 1.0:
		return false
	var ray := PhysicsRayQueryParameters3D.create(camera, pivot)
	return space.intersect_ray(ray).is_empty()
