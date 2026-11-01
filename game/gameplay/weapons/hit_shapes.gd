class_name HitShapes
extends RefCounted
## Ray against sphere and capsule, in plain vectors: no physics server, no nodes. Hit zones are
## these shapes, so the server can test any past moment of a target, which a physics body cannot.

const EPSILON := 1e-6


## Distance along the ray (unit `dir`) to the first surface of the sphere, or -1.0.
static func ray_sphere(origin: Vector3, dir: Vector3, centre: Vector3, radius: float) -> float:
	var oc := origin - centre
	var b := oc.dot(dir)
	var c := oc.dot(oc) - radius * radius
	var h := b * b - c
	if h < 0.0:
		return -1.0
	var t := -b - sqrt(h)
	return t if t >= 0.0 else -1.0


## Distance along the ray (unit `dir`) to the first surface of the capsule from `a` to `b` (a
## sphere when they match), or -1.0. A ray that starts inside answers 0.0.
static func ray_capsule(
	origin: Vector3, dir: Vector3, a: Vector3, b: Vector3, radius: float
) -> float:
	var best := INF
	var ba := b - a
	var baba := ba.dot(ba)
	if baba > EPSILON:
		var oa := origin - a
		var bard := ba.dot(dir)
		var baoa := ba.dot(oa)
		var rdoa := dir.dot(oa)
		var qa := baba - bard * bard
		if qa > EPSILON * baba:
			var qb := baba * rdoa - baoa * bard
			var qc := baba * oa.dot(oa) - baoa * baoa - radius * radius * baba
			var h := qb * qb - qa * qc
			if h >= 0.0:
				var t := (-qb - sqrt(h)) / qa
				var along := baoa + t * bard
				if t >= 0.0 and along > 0.0 and along < baba:
					best = t
	for end: Vector3 in [a, b]:
		var t_end := ray_sphere(origin, dir, end, radius)
		if t_end >= 0.0:
			best = minf(best, t_end)
	if best < INF:
		return best
	return 0.0 if distance_to_segment(origin, a, b) < radius else -1.0


## Shortest distance from a point to the segment `a`-`b`.
static func distance_to_segment(point: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var length_sq := ab.dot(ab)
	if length_sq <= EPSILON:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)
