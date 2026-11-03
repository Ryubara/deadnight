class_name Hitbox
extends RefCounted
## The hit zones of a zombie-sized target: a head sphere, a body capsule and four limb capsules,
## placed from the target's feet position and yaw. Only these shapes are shot at, never the
## visible mesh. The test range draws them as they are.

const HEAD := &"head"
const BODY := &"body"
const LIMB := &"limb"
## The boss's lamp (the `WeakSpot` of the headliner model, a lit lens on its belly): a sphere that
## only a zombie with a weak spot has. In a walker's units like the rest, so `scale` sizes it with
## the body: at the headliner's 1.45 it is a 0.22 m ball 1.68 m up and 0.42 m ahead of its feet,
## where the lens sits in the model's walk (measured at game scale; docs/research/zombies.md).
const WEAK := &"weak"
const WEAK_ZONE := {
	"zone": &"weak", "a": Vector3(0, 1.16, 0.29), "b": Vector3(0, 1.16, 0.29), "r": 0.15
}

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
## The id of the simple upright set above (`ZONES`): what the blast model weighs and the tests that
## need a plain standing target use. The bodies the game shoots have fitted sets (`HitPoseData`).
const STANDING := &"standing"

## The set a target has when it names none: a walker's, moving.
const DEFAULT_SET := &"walker.move"
## How far (m) behind the first surface a ray may reach a more valuable zone and count it: a limb
## is the cover the body and head show through, never the part a ray was aimed at (a swinging arm
## in front of the chest, a hand beside the face).
const SLACK := 0.2
## The same for the boss's lamp: a lens on its belly that its jaw hangs over from the front, so a
## ray that reaches the lamp this far (m) behind the first surface counts the lamp.
const WEAK_SLACK := 0.45


## The zone shapes of one set in the world: `[{zone, a, b, r}]`. `set_id` names the fitted body and
## pose (`HitPoseData`), or `STANDING` (the default, what the blast model weighs). `scale` sizes the
## whole set about the feet: a tall zombie's zones are larger. `weak` adds the weak spot, last, so
## the indices of the other zones stay.
static func shapes(
	position: Vector3,
	yaw: float,
	scale: float = 1.0,
	weak: bool = false,
	set_id: StringName = STANDING
) -> Array[Dictionary]:
	var basis := Basis(Vector3.UP, yaw)
	var placed: Array[Dictionary] = []
	var zones: Array = fitted(set_id)["shapes"]
	if weak:
		zones = zones + [WEAK_ZONE]
	for zone in zones:
		(
			placed
			. append(
				{
					"zone": zone["zone"],
					"a": position + basis * (zone["a"] as Vector3) * scale,
					"b": position + basis * (zone["b"] as Vector3) * scale,
					"r": zone["r"] * scale,
				}
			)
		)
	return placed


## The fitted set called `set_id` (`{shapes, bound_centre, bound_radius}`): the same body's moving
## set when it has no set of that pose, the default set when it has none of that body.
static func fitted(set_id: StringName) -> Dictionary:
	if set_id == STANDING:
		return {"shapes": ZONES, "bound_centre": BOUND_CENTRE, "bound_radius": BOUND_RADIUS}
	var sets := HitPoseData.sets()
	if sets.has(set_id):
		return sets[set_id]
	var body := String(set_id).get_slice(".", 0)
	return sets.get(StringName(body + ".move"), sets[DEFAULT_SET])


## The nearest zone a ray reaches within `max_distance`, as `{zone, distance}`, or `{}`. `inflate`
## fattens every shape by that many metres, which turns the ray into a sweep of a sphere; `scale`
## sizes the zombie's zones, `weak` adds its weak spot and `set_id` picks the body's pose
## (`shapes`). A limb the ray meets first gives way to a body or head zone within `SLACK` behind it.
static func ray(
	origin: Vector3,
	dir: Vector3,
	max_distance: float,
	position: Vector3,
	yaw: float,
	inflate: float = 0.0,
	scale: float = 1.0,
	weak: bool = false,
	set_id: StringName = DEFAULT_SET
) -> Dictionary:
	return ray_in(fitted(set_id), origin, dir, max_distance, position, yaw, inflate, scale, weak)


## `ray` against a set given as it is (`fitted`'s answer): what the fitting tool checks a candidate
## set with.
static func ray_in(
	fit: Dictionary,
	origin: Vector3,
	dir: Vector3,
	max_distance: float,
	position: Vector3,
	yaw: float,
	inflate: float = 0.0,
	scale: float = 1.0,
	weak: bool = false
) -> Dictionary:
	var basis := Basis(Vector3.UP, yaw)
	var bound := position + basis * (fit["bound_centre"] as Vector3) * scale
	var reach: float = fit["bound_radius"] * scale + inflate
	if HitShapes.distance_to_segment(bound, origin, origin + dir * max_distance) > reach:
		return {}
	var nearest := max_distance
	var nearest_zone := &""
	var head_t := INF
	var body_t := INF
	for zone: Dictionary in fit["shapes"]:
		var t := _zone_distance(zone, origin, dir, position, basis, scale, inflate)
		if t < 0.0 or t > max_distance:
			continue
		if t <= nearest:
			nearest = t
			nearest_zone = zone["zone"]
		if zone["zone"] == HEAD:
			head_t = minf(head_t, t)
		elif zone["zone"] == BODY:
			body_t = minf(body_t, t)
	if weak:
		var lamp := _zone_distance(WEAK_ZONE, origin, dir, position, basis, scale, inflate)
		if lamp >= 0.0 and lamp <= nearest + WEAK_SLACK:
			return {"zone": WEAK, "distance": lamp}
	if nearest_zone == &"":
		return {}
	var zone_hit := nearest_zone
	if zone_hit == LIMB:
		if head_t <= nearest + SLACK:
			zone_hit = HEAD
		elif body_t <= nearest + SLACK:
			zone_hit = BODY
	return {"zone": zone_hit, "distance": nearest}


## The ray against a target as the weapons hold it (`{pos, yaw}` and, when they differ from a
## walker's, `scale`, `weak` and `pose`: the set id).
static func ray_at(
	origin: Vector3, dir: Vector3, max_distance: float, target: Dictionary, inflate: float = 0.0
) -> Dictionary:
	return ray(
		origin,
		dir,
		max_distance,
		target["pos"],
		target["yaw"],
		inflate,
		target.get("scale", 1.0),
		target.get("weak", false),
		target.get("pose", DEFAULT_SET)
	)


static func _zone_distance(
	zone: Dictionary,
	origin: Vector3,
	dir: Vector3,
	position: Vector3,
	basis: Basis,
	scale: float,
	inflate: float
) -> float:
	var a := position + basis * (zone["a"] as Vector3) * scale
	var b := position + basis * (zone["b"] as Vector3) * scale
	return HitShapes.ray_capsule(origin, dir, a, b, zone["r"] * scale + inflate)


## Distance from a point to the nearest zone surface (0 inside): how far a blast is from a target.
static func distance_from(point: Vector3, position: Vector3, yaw: float) -> float:
	var nearest := INF
	for shape in shapes(position, yaw):
		var d := HitShapes.distance_to_segment(point, shape["a"], shape["b"]) - float(shape["r"])
		nearest = minf(nearest, d)
	return maxf(nearest, 0.0)
