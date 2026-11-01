class_name BlastModel
extends RefCounted
## What one blast does to one body, as pure functions of a `GrenadeDef`, numbers and a `world_ray`.
##
## A zombie is its six hit parts (`Hitbox`: head, body, two arms, two legs). Each part takes its
## share of the damage by how far the blast is from it and whether anything solid stands between
## the two, so a zombie half behind a barrier is half hurt and one fully behind it is not hurt.
## The legs' share is reported apart: it is what the rules weigh to decide a crawler.

## The share of the damage each part of `Hitbox.ZONES` carries (they add up to one):
## head, body, right arm, left arm, right leg, left leg.
const PART_WEIGHTS: Array[float] = [0.10, 0.35, 0.125, 0.125, 0.15, 0.15]
## Indexes into the parts that are legs.
const LEG_PARTS: Array[int] = [4, 5]


## What a blast at `point` does to a zombie standing at `position` facing `yaw`. Answers
## `{"damage": float, "leg_damage": float, "exposure": float, "distance": float}`: the damage
## (cover and falloff applied), the part of it that hit the legs, the fraction of the body in
## sight (0 to 1) and the distance to the nearest part. `world_ray` is the weapons' (distance to
## the first solid thing on a segment, or -1.0), and may be invalid for open ground.
static func against_zombie(
	def: GrenadeDef, point: Vector3, position: Vector3, yaw: float, world_ray: Callable
) -> Dictionary:
	var result := {"damage": 0.0, "leg_damage": 0.0, "exposure": 0.0, "distance": INF}
	var shapes := Hitbox.shapes(position, yaw)
	for index in shapes.size():
		var shape: Dictionary = shapes[index]
		var a: Vector3 = shape["a"]
		var b: Vector3 = shape["b"]
		var distance := maxf(HitShapes.distance_to_segment(point, a, b) - float(shape["r"]), 0.0)
		result["distance"] = minf(result["distance"], distance)
		var reach := def.falloff(distance)
		if reach <= 0.0:
			continue
		if not sees(def, point, (a + b) * 0.5, world_ray):
			continue
		var weight := PART_WEIGHTS[index]
		var part_damage := def.damage * reach * weight
		result["damage"] += part_damage
		result["exposure"] += weight
		if LEG_PARTS.has(index):
			result["leg_damage"] += part_damage
	return result


## What a blast does to a player: a chest-high point, one line check. `{"damage", "distance"}`
## with the damage before the thrower's reduction.
static func against_point(
	def: GrenadeDef, point: Vector3, target: Vector3, world_ray: Callable
) -> Dictionary:
	var distance := point.distance_to(target)
	var damage := 0.0
	if def.falloff(distance) > 0.0 and sees(def, point, target, world_ray):
		damage = def.damage * def.falloff(distance)
	return {"damage": damage, "distance": distance}


## Whether nothing solid stands between the blast and `target` (the line check of the cover rule).
static func sees(def: GrenadeDef, point: Vector3, target: Vector3, world_ray: Callable) -> bool:
	if not world_ray.is_valid():
		return true
	var length := point.distance_to(target)
	if length <= 1e-4:
		return true
	var wall: float = world_ray.call(point, target)
	return wall < 0.0 or wall >= length - def.cover_slack


## The push a body takes: away from the blast along the ground, and up, both scaled by how much
## of the blast reached it (`reach`, 0 to 1).
static func impulse(def: GrenadeDef, point: Vector3, body: Vector3, reach: float) -> Vector3:
	var away := Vector3(body.x - point.x, 0.0, body.z - point.z)
	away = away.normalized() if away.length_squared() > 1e-8 else Vector3.ZERO
	return (away * def.knockback_speed + Vector3.UP * def.knockback_lift) * reach
