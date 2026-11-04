class_name ElementPlay
extends RefCounted
## The element of a re-cut weapon at work, on the server: which zombies a hit's blast and arc reach
## and for how much (`blast_victims`, `arc_victims`, pure functions of the definition and the
## targets), and the fire patches a burst leaves behind (`start_patch`, `step`). It decides who is
## hurt and when; `CombatServer` makes every damage a `hit` for the rules and tells the clients.
## Pure data stepped by the combat clock: no node, no engine time, no random draw.

## How far above its feet an arc is drawn to a zombie.
const ARC_LIFT := 1.0


## One fire patch on the ground: where, how wide, whose, and how long it still burns.
class Patch:
	var id: int = 0
	var shooter_id: int = 0
	var weapon_id: StringName = &""
	var element: ElementDef
	var point: Vector3 = Vector3.ZERO
	var left: float = 0.0
	## Seconds until the next hit on the zombies in it.
	var next_tick: float = 0.0

	func radius() -> float:
		return element.ground_radius

	## The damage a zombie takes each time the patch ticks.
	func tick_damage() -> float:
		return element.ground_dps * element.tick_seconds


## One zombie set burning (`ElementDef.burn_dps`): whose it is, by which weapon and element, and the
## seconds until the next hit it takes. The seconds the fire lasts are the status's.
class Burn:
	var shooter_id: int = 0
	var weapon_id: StringName = &""
	var element: ElementDef
	var next_tick: float = 0.0


var _patches: Array[Patch] = []


## The zombies a blast of `def.element` bursting at `point` reaches, as `[{target_id, damage,
## distance}]` in the order of their ids: the other zombies within the radius, each for the weapon's
## hit times `blast_fraction` at the centre sliding to `blast_edge_fraction` of that at the edge.
## `alive` is the targets map of `AimResolver`; `hit_id` is the zombie the hit landed on, which
## takes
## the hit alone.
static func blast_victims(
	def: WeaponDef, point: Vector3, alive: Dictionary, hit_id: int
) -> Array[Dictionary]:
	var victims: Array[Dictionary] = []
	var element := def.element
	if element == null or not element.has_blast():
		return victims
	var centre := def.damage * element.blast_fraction
	for id: int in _sorted(alive):
		if id == hit_id:
			continue
		var reach := Hitbox.distance_from(point, alive[id]["pos"], alive[id]["yaw"])
		if reach > element.blast_radius:
			continue
		var share := lerpf(1.0, element.blast_edge_fraction, reach / element.blast_radius)
		victims.append({"target_id": id, "damage": centre * share, "distance": reach})
	return victims


## The zombies a hit's arc jumps to, as `[{target_id, damage, distance}]`, nearest first (ties by
## id): up to `arc_targets` others within `arc_radius` of the point, each for the weapon's hit times
## `arc_fraction`. `skip` holds the ids that are not jumped to (the zombies the shot itself hit).
static func arc_victims(
	def: WeaponDef, point: Vector3, alive: Dictionary, skip: Array
) -> Array[Dictionary]:
	var victims: Array[Dictionary] = []
	var element := def.element
	if element == null or not element.has_arc():
		return victims
	for id: int in _sorted(alive):
		if skip.has(id):
			continue
		var reach := Hitbox.distance_from(point, alive[id]["pos"], alive[id]["yaw"])
		if reach <= element.arc_radius:
			victims.append(
				{"target_id": id, "damage": def.damage * element.arc_fraction, "distance": reach}
			)
	victims.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a["distance"] != b["distance"]:
				return a["distance"] < b["distance"]
			return a["target_id"] < b["target_id"]
	)
	return victims.slice(0, element.arc_targets)


## Where an arc is drawn to on a zombie: its chest, a little above its feet.
static func arc_end(target: Dictionary) -> Vector3:
	return (target["pos"] as Vector3) + Vector3.UP * ARC_LIFT


## A burst of a weapon whose element burns the ground leaves a patch for `seconds`. Returns it, or
## null when the weapon's element does not.
func start_patch(id: int, shooter_id: int, def: WeaponDef, point: Vector3, seconds: float) -> Patch:
	if def.element == null or not def.element.has_ground() or seconds <= 0.0:
		return null
	var patch := Patch.new()
	patch.id = id
	patch.shooter_id = shooter_id
	patch.weapon_id = def.id
	patch.element = def.element
	patch.point = point
	patch.left = seconds
	patch.next_tick = def.element.tick_seconds
	_patches.append(patch)
	return patch


## One combat step: every patch burns down, and each one whose time has come hurts the zombies in
## it. Returns `[{patch, target_id, damage}]`, one entry for each zombie each tick reaches; a patch
## whose seconds are up is gone after its last tick.
func step(delta: float, alive: Dictionary) -> Array[Dictionary]:
	var ticks: Array[Dictionary] = []
	var burning: Array[Patch] = []
	for patch in _patches:
		patch.left -= delta
		patch.next_tick -= delta
		while patch.next_tick <= WeaponState.READY_EPSILON:
			patch.next_tick += patch.element.tick_seconds
			ticks.append_array(_tick_of(patch, alive))
		if patch.left > 0.0:
			burning.append(patch)
	_patches = burning
	return ticks


func patch_count() -> int:
	return _patches.size()


func _tick_of(patch: Patch, alive: Dictionary) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	for id: int in _sorted(alive):
		var reach := Hitbox.distance_from(patch.point, alive[id]["pos"], alive[id]["yaw"])
		if reach <= patch.radius():
			hits.append({"patch": patch, "target_id": id, "damage": patch.tick_damage()})
	return hits


static func _sorted(alive: Dictionary) -> Array:
	var ids := alive.keys()
	ids.sort()
	return ids
