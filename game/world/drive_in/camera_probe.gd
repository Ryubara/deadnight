class_name CameraProbe
extends RefCounted
## Sweeps the player's over-the-shoulder camera rig through the world, without a player in the
## scene.
##
## The numbers are the player's, read from `player_tuning_default.tres` (`PlayerTuning`: the pivot,
## shoulder and arm, a 0.25 m sphere swept sideways to the shoulder and back along the arm), so a
## change of tuning moves the sweep too. It is the same `CameraPlacement` the rig uses: a narrow
## place slides the camera in toward the player or pulls it forward, and the lens never ends in
## the wall.
## `docs/research/greybox-and-captures.md` has the measurements. Used by the world tests and the
## capture rig.

## Air the camera needs around it: the near plane (0.05 m) and a little more.
const CAMERA_CLEAR := 0.1
## What the camera sweeps against: the player's own collision mask (`player.tscn`).
const PLAYER_MASK := 3
const PLAYER_TUNING: PlayerTuning = preload("res://gameplay/player/player_tuning_default.tres")


## The player's tuning. Read through this function, never as `PLAYER_TUNING.x` in an expression:
## the compiler folds a property of a constant resource into the script, and a value changed after
## that (a test's, or a reloaded tuning) would not be seen.
static func tuning() -> PlayerTuning:
	return PLAYER_TUNING


## Height of the camera pivot above the feet.
static func pivot_height() -> float:
	return tuning().pivot_height


## Sideways offset of the shoulder camera.
static func shoulder_offset() -> float:
	return tuning().shoulder_offset


## Length of the arm when nothing is in the way.
static func arm_length() -> float:
	return tuning().arm_length


## Radius of the sphere swept along the arm.
static func arm_margin() -> float:
	return tuning().arm_margin


## The player's body, read from its tuning: `Player` builds its capsule from the same two numbers.
static func body_radius() -> float:
	return tuning().radius


static func body_height() -> float:
	return tuning().height


## How high a full jump lifts the feet.
static func jump_height() -> float:
	return tuning().jump_height


## The rig for a player standing at `feet` and looking along `yaw` (radians, 0 looks down -Z),
## camera over the right shoulder when `side` is 1 and the left when -1. `p_arm_length` and
## `p_shoulder_offset` below zero mean the tuning's own (pass the aim numbers to judge the aim
## zoom). Returns {arm, shoulder, camera, pivot, free}: `arm` and `shoulder` are how far the arm
## and the shoulder offset get after the sweeps (metres), `camera` where the lens sits, `free`
## whether the lens has air around it and sees the pivot.
static func rig(
	space: PhysicsDirectSpaceState3D,
	feet: Vector3,
	yaw: float,
	side: float = 1.0,
	pitch: float = 0.0,
	p_arm_length: float = -1.0,
	p_shoulder_offset: float = -1.0,
) -> Dictionary:
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var arm_max := p_arm_length if p_arm_length >= 0.0 else arm_length()
	var shoulder_max := p_shoulder_offset if p_shoulder_offset >= 0.0 else shoulder_offset()
	var pivot := feet + Vector3(0.0, pivot_height(), 0.0)
	var placed := CameraPlacement.place(
		space,
		[] as Array[RID],
		PLAYER_MASK,
		pivot,
		basis,
		shoulder_max * side,
		arm_max,
		arm_margin()
	)
	var camera: Vector3 = placed["camera"]
	return {
		"arm": arm_max * placed["arm_fraction"],
		"shoulder": shoulder_max * placed["shoulder_fraction"],
		"camera": camera,
		"pivot": pivot,
		"free": _is_free(space, camera, pivot)
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


## True when the lens, with the near plane's air around it, touches a wall or a car.
static func in_geometry(space: PhysicsDirectSpaceState3D, camera: Vector3) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = CAMERA_CLEAR
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, camera)
	return not space.intersect_shape(query, 1).is_empty()


## The camera is free when the lens is out of the geometry and still sees the player's head.
static func _is_free(space: PhysicsDirectSpaceState3D, camera: Vector3, pivot: Vector3) -> bool:
	if in_geometry(space, camera):
		return false
	var ray := PhysicsRayQueryParameters3D.create(camera, pivot)
	return space.intersect_ray(ray).is_empty()
