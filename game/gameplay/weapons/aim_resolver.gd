class_name AimResolver
extends RefCounted
## Where a shot goes and what it hits, as pure functions of plain data. No physics server: the
## world is a `Callable` the caller supplies, the targets a dictionary.
##
## `world_ray(from: Vector3, to: Vector3) -> float` answers the distance from `from` to the first
## world surface on the segment, or -1.0 when it is clear. The server builds one from the physics
## space (`WorldProbe`); a test builds one from a box. An invalid Callable means an empty world.
## `targets` is `{id: {"pos": Vector3, "yaw": float, "scale": float}}` (`scale`, the size of the
## target's hit zones, may be left out for 1), the shape `LagCompensator.rewind` returns.
##
## The third-person aim correction: the camera sits over the shoulder, the muzzle does not.
## 1) a ray from the camera finds what the crosshair is on; 2) the shot then leaves the muzzle
## towards that point. If a corner stands between the muzzle and the point, the muzzle ray hits
## the corner: the shoulder camera cannot shoot around it.

## Closer than this to the muzzle, the aim point is ignored and the camera direction is used.
const MIN_AIM_DISTANCE := 0.2


## The seed of one shot's spread, the same on the client and the server for the same `seq`.
static func shot_seed(match_seed: int, shooter_id: int, seq: int) -> int:
	return (match_seed * 73856093) ^ (shooter_id * 19349663) ^ (seq * 83492791)


## One direction per pellet, scattered in a cone of `spread_deg` around `dir` (wider by
## `moving_spread_deg` for a shooter at a full run: `move` 1, standing 0).
static func spread_dirs(
	def: WeaponDef, dir: Vector3, seed_value: int, move: float = 0.0
) -> Array[Vector3]:
	var dirs: Array[Vector3] = []
	var cone := def.spread_at(move)
	if cone <= 0.0:
		for _i in def.pellets:
			dirs.append(dir)
		return dirs
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	var frame := Basis.looking_at(dir, up)
	var half := deg_to_rad(cone)
	for _i in def.pellets:
		var theta := half * sqrt(rng.randf())
		var phi := rng.randf() * TAU
		var local := Vector3(sin(theta) * cos(phi), sin(theta) * sin(phi), -cos(theta))
		dirs.append((frame * local).normalized())
	return dirs


## The direction the muzzle fires along to reach what the camera ray is on.
static func aim_direction(
	def: WeaponDef,
	origin: Vector3,
	dir: Vector3,
	muzzle: Vector3,
	targets: Dictionary,
	world_ray: Callable
) -> Vector3:
	var aim_range := def.max_range + origin.distance_to(muzzle)
	# The camera is behind the shooter: ignore what lies between it and the muzzle's depth.
	var start := origin + dir * maxf(0.0, (muzzle - origin).dot(dir))
	var aim_dist := aim_range
	var wall := _world_distance(world_ray, start, dir, aim_range)
	if wall >= 0.0:
		aim_dist = wall
	for id in targets:
		var hit := _ray(start, dir, aim_dist, targets[id], 0.0)
		if not hit.is_empty():
			aim_dist = hit["distance"]
	var to_aim := start + dir * aim_dist - muzzle
	return dir if to_aim.length() < MIN_AIM_DISTANCE else to_aim.normalized()


## Traces every pellet of one shot. Answers `{"pellets": [{"hits": [...], "end": Vector3}]}`
## where a hit is `{target_id, zone, distance, damage, point}`, nearest first.
static func trace_hitscan(
	def: WeaponDef,
	origin: Vector3,
	dir: Vector3,
	muzzle: Vector3,
	targets: Dictionary,
	world_ray: Callable,
	seed_value: int,
	move: float = 0.0
) -> Dictionary:
	var pellets: Array[Dictionary] = []
	for pellet_dir in spread_dirs(def, dir, seed_value, move):
		pellets.append(trace_one(def, origin, pellet_dir, muzzle, targets, world_ray))
	return {"pellets": pellets}


## One ray: camera aim, then the muzzle ray with the world and the targets along it.
static func trace_one(
	def: WeaponDef,
	origin: Vector3,
	dir: Vector3,
	muzzle: Vector3,
	targets: Dictionary,
	world_ray: Callable
) -> Dictionary:
	var mdir := aim_direction(def, origin, dir, muzzle, targets, world_ray)
	var wall := _world_distance(world_ray, muzzle, mdir, def.max_range)
	var limit := def.max_range if wall < 0.0 else wall
	var found := _along(muzzle, mdir, limit, targets, 0.0)
	var cap := 1 + def.penetration
	var hits: Array[Dictionary] = []
	for i in mini(found.size(), cap):
		var entry: Dictionary = found[i]
		entry["damage"] = DamageModel.damage(def, entry["distance"], entry["zone"], i)
		entry["point"] = muzzle + mdir * float(entry["distance"])
		hits.append(entry)
	var end_distance := limit
	if found.size() >= cap:
		end_distance = hits[hits.size() - 1]["distance"]
	return {"hits": hits, "end": muzzle + mdir * end_distance}


## A melee swing: a sphere of `melee_radius` swept `melee_range` along `dir` (a ray against
## shapes fattened by the radius). Answers up to `melee_max_targets` hits, nearest first.
static func sweep_melee(
	def: WeaponDef, origin: Vector3, dir: Vector3, targets: Dictionary, world_ray: Callable
) -> Array[Dictionary]:
	var wall := _world_distance(world_ray, origin, dir, def.melee_range)
	var limit := def.melee_range if wall < 0.0 else wall
	var found := _along(origin, dir, limit, targets, def.melee_radius)
	var hits: Array[Dictionary] = []
	for i in mini(found.size(), def.melee_max_targets):
		var entry: Dictionary = found[i]
		entry["damage"] = DamageModel.damage(def, entry["distance"], entry["zone"], i)
		entry["point"] = origin + dir * float(entry["distance"])
		hits.append(entry)
	return hits


## Every target the ray reaches within `limit`, nearest first, as `{target_id, zone, distance}`.
static func _along(
	origin: Vector3, dir: Vector3, limit: float, targets: Dictionary, inflate: float
) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for id in targets:
		var hit := _ray(origin, dir, limit, targets[id], inflate)
		if not hit.is_empty():
			found.append({"target_id": id, "zone": hit["zone"], "distance": hit["distance"]})
	found.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a["distance"] < b["distance"]
	)
	return found


## The ray against one target: `{"pos", "yaw"}` and, when its zones are not the walker's size or
## pose, `"scale"`, `"weak"` and `"pose"` (`Hitbox.ray_at`).
static func _ray(
	origin: Vector3, dir: Vector3, limit: float, target: Dictionary, inflate: float
) -> Dictionary:
	return Hitbox.ray_at(origin, dir, limit, target, inflate)


static func _world_distance(
	world_ray: Callable, from: Vector3, dir: Vector3, length: float
) -> float:
	if not world_ray.is_valid():
		return -1.0
	var d: float = world_ray.call(from, from + dir * length)
	return d if d >= 0.0 and d <= length else -1.0
