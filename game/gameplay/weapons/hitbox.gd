class_name Hitbox
extends RefCounted
## The hit zones of a zombie-sized target: a head sphere, a body capsule and four limb capsules,
## placed from the target's feet position and yaw. Only these shapes are shot at, never the
## visible mesh. The test range draws them as they are.

const HEAD := &"head"
const BODY := &"body"
const LIMB := &"limb"

## Each zone: its name, two end points relative to the feet (x is the target's right, z its
## forward) and a radius. A sphere has equal end points.
const ZONES: Array[Dictionary] = [
	{"zone": &"head", "a": Vector3(0, 1.62, 0), "b": Vector3(0, 1.62, 0), "r": 0.22},
	{"zone": &"body", "a": Vector3(0, 0.95, 0), "b": Vector3(0, 1.30, 0), "r": 0.26},
	{"zone": &"limb", "a": Vector3(0.40, 0.95, 0), "b": Vector3(0.40, 1.35, 0), "r": 0.10},
	{"zone": &"limb", "a": Vector3(-0.40, 0.95, 0), "b": Vector3(-0.40, 1.35, 0), "r": 0.10},
	{"zone": &"limb", "a": Vector3(0.12, 0.15, 0), "b": Vector3(0.12, 0.65, 0), "r": 0.13},
	{"zone": &"limb", "a": Vector3(-0.12, 0.15, 0), "b": Vector3(-0.12, 0.65, 0), "r": 0.13},
]
## A sphere around the whole target; a ray that misses it skips every zone.
const BOUND_CENTRE := Vector3(0, 0.95, 0)
const BOUND_RADIUS := 1.1


## The zone shapes in the world: `[{zone, a, b, r}]`.
static func shapes(position: Vector3, yaw: float) -> Array[Dictionary]:
	var basis := Basis(Vector3.UP, yaw)
	var placed: Array[Dictionary] = []
	for zone in ZONES:
		var shape := {
			"zone": zone["zone"],
			"a": position + basis * (zone["a"] as Vector3),
			"b": position + basis * (zone["b"] as Vector3),
			"r": zone["r"],
		}
		placed.append(shape)
	return placed


## The nearest zone a ray reaches within `max_distance`, as `{zone, distance}`, or `{}`. `inflate`
## fattens every shape by that many metres, which turns the ray into a sweep of a sphere.
static func ray(
	origin: Vector3,
	dir: Vector3,
	max_distance: float,
	position: Vector3,
	yaw: float,
	inflate: float = 0.0
) -> Dictionary:
	var bound := position + BOUND_CENTRE
	var reach := BOUND_RADIUS + inflate
	if HitShapes.distance_to_segment(bound, origin, origin + dir * max_distance) > reach:
		return {}
	var best := {}
	var best_t := max_distance
	for shape in shapes(position, yaw):
		var t := HitShapes.ray_capsule(origin, dir, shape["a"], shape["b"], shape["r"] + inflate)
		if t >= 0.0 and t <= best_t:
			best_t = t
			best = {"zone": shape["zone"], "distance": t}
	return best


## Distance from a point to the nearest zone surface (0 inside): how far a blast is from a target.
static func distance_from(point: Vector3, position: Vector3, yaw: float) -> float:
	var nearest := INF
	for shape in shapes(position, yaw):
		var d := HitShapes.distance_to_segment(point, shape["a"], shape["b"]) - float(shape["r"])
		nearest = minf(nearest, d)
	return maxf(nearest, 0.0)
