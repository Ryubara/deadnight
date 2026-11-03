class_name ZombieBump
extends RefCounted
## The body a grenade runs into: one upright capsule around a zombie, wider than its torso (arms and
## shoulders) and as tall as its head, in plain vectors with no physics server, so the server can
## test it against the zombies where they stand this tick. A hit answers like the world's cast
## (`{"distance", "normal"}`) plus `zombie_id` and `away`, the way along the ground out from the
## body.

## The capsule in a walker's units (feet at the origin): the radius, and the heights of the two
## sphere centres. `scale` sizes the whole of it, as it sizes the hit zones (`Hitbox.shapes`).
const RADIUS := 0.4
const LOW := 0.4
const HIGH := 1.45


## The nearest zombie on the segment `from` to `to`, as `{"distance", "normal", "away",
## "zombie_id"}` (distance from `from`, like the world's), or `{}` when the segment is clear.
## `targets` is the grenade server's list, `{id: {"pos", "yaw", "scale"}}`. A segment that starts
## inside a body and leaves it hits nothing (it is already coming out); one that starts inside and
## goes deeper hits at once, out from the axis.
static func nearest(from: Vector3, to: Vector3, targets: Dictionary) -> Dictionary:
	var length := from.distance_to(to)
	if length <= 1e-7:
		return {}
	var dir := (to - from) / length
	var best := {}
	var best_distance := length
	for id: int in targets:
		var target: Dictionary = targets[id]
		var scale: float = target.get("scale", 1.0)
		var feet: Vector3 = target["pos"]
		if Vector2(feet.x - from.x, feet.z - from.z).length() > length + RADIUS * scale + 0.1:
			continue
		var a := feet + Vector3.UP * LOW * scale
		var b := feet + Vector3.UP * HIGH * scale
		var t := HitShapes.ray_capsule(from, dir, a, b, RADIUS * scale)
		if t < 0.0 or t > best_distance or (t == best_distance and not best.is_empty()):
			continue
		var point := from + dir * t
		var axis_point := _closest_on_segment(point, a, b)
		var normal := point - axis_point
		if normal.length_squared() < 1e-8:
			normal = -dir
		normal = normal.normalized()
		if t <= 0.0 and dir.dot(normal) >= 0.0:
			continue
		best_distance = t
		best = {
			"distance": t,
			"normal": normal,
			"away": _along_ground(normal, dir),
			"zombie_id": id,
		}
	return best


## `normal` flattened onto the ground; for a hit on the very top, back along the way it came.
static func _along_ground(normal: Vector3, dir: Vector3) -> Vector3:
	var flat := Vector3(normal.x, 0.0, normal.z)
	if flat.length_squared() > 1e-8:
		return flat.normalized()
	var back := Vector3(-dir.x, 0.0, -dir.z)
	return back.normalized() if back.length_squared() > 1e-8 else Vector3.RIGHT


static func _closest_on_segment(point: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := b - a
	var length_sq := ab.dot(ab)
	if length_sq <= 1e-8:
		return a
	return a + ab * clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
