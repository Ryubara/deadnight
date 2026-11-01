class_name CameraPlacement
extends RefCounted
## Where the shoulder camera's lens goes in the physics world: from the pivot a sphere is swept
## sideways to the shoulder, then back along the view from there, and the camera stops where a
## sweep hits; a last sweep straight from the pivot to the lens makes sure the head is in sight
## (the two legs can pass either side of a corner the straight line would touch). A wall beside
## the player slides the camera in toward the player's back instead of through the wall, and a
## wall behind pulls it forward. The rig and `CameraProbe` (the lot's passage tests) both use it,
## so the tests judge the camera the player really has.


## The fraction (0 to 1) of `motion` a sphere of `margin` radius can travel from `from` before it
## touches a body on `mask` other than `exclude`. 0 when it starts inside one.
static func sweep(
	space: PhysicsDirectSpaceState3D,
	exclude: Array[RID],
	mask: int,
	from: Vector3,
	motion: Vector3,
	margin: float
) -> float:
	if motion.is_zero_approx():
		return 1.0
	var sphere := SphereShape3D.new()
	sphere.radius = margin
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, from)
	query.motion = motion
	query.exclude = exclude
	query.collision_mask = mask
	var fractions := space.cast_motion(query)
	return fractions[0] if fractions.size() == 2 else 0.0


## The lens for a view `basis` (x right, z back) at `pivot`: `shoulder` metres along x (negative is
## the left shoulder) and `arm` metres back. `shoulder_cap` and `arm_cap` (0 to 1) limit how much
## of each may be used, and `line_cap` the same for the last sweep, so a caller can ease the
## camera back out after a wall.
## Returns {camera, shoulder_fraction, arm_fraction, raw_shoulder, raw_arm, raw_line}: the
## fractions applied and the fractions the sweeps alone allowed.
static func place(
	space: PhysicsDirectSpaceState3D,
	exclude: Array[RID],
	mask: int,
	pivot: Vector3,
	basis: Basis,
	shoulder: float,
	arm: float,
	margin: float,
	shoulder_cap := 1.0,
	arm_cap := 1.0,
	line_cap := 1.0
) -> Dictionary:
	var side := basis.x * shoulder
	var raw_shoulder := sweep(space, exclude, mask, pivot, side, margin)
	var shoulder_fraction := minf(raw_shoulder, shoulder_cap)
	var at_shoulder := pivot + side * shoulder_fraction
	var back := basis.z * arm
	var raw_arm := sweep(space, exclude, mask, at_shoulder, back, margin)
	var arm_fraction := minf(raw_arm, arm_cap)
	var legs := at_shoulder + back * arm_fraction
	var raw_line := sweep(space, exclude, mask, pivot, legs - pivot, margin)
	return {
		"camera": pivot.lerp(legs, minf(raw_line, line_cap)),
		"shoulder_fraction": shoulder_fraction,
		"arm_fraction": arm_fraction,
		"raw_shoulder": raw_shoulder,
		"raw_arm": raw_arm,
		"raw_line": raw_line,
	}
