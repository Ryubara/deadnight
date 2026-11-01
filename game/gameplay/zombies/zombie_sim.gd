class_name ZombieSim
extends RefCounted
## All the zombies of a match, simulated on the server at a fixed step. No nodes, no engine time,
## no global random: a zombie's timer phase comes from the seed, its path from a `ZombiePathing`,
## time from the `delta` of `tick`. A zombie has no health here; the rules say when it dies
## (`begin_death`) and the sim only plays that out.
##
## Zombies are not physics bodies. They walk the path the navigation map gives, push each other
## apart with a cheap spatial hash, and are shot at through their hit zones (`Hitbox`), which the
## weapon code tests analytically. That keeps 40 of them well under a millisecond of script.

## The step every caller uses, so server and tests agree.
const STEP := 1.0 / 30.0

var tuning: ZombieTuning
## Used for the speed of a zombie on lit ground; without it light changes nothing.
var rounds: RoundTuning
var pathing: ZombiePathing = ZombiePathing.new()
## `Callable(position: Vector3) -> bool`: whether that ground is lit. Asked at each repath.
var lit_probe: Callable = Callable()
var zombies: Dictionary[int, ZombieState] = {}

var _rng := RandomNumberGenerator.new()
var _grid: Dictionary[Vector2i, Array] = {}


func _init(p_tuning: ZombieTuning = null, p_seed: int = 0) -> void:
	tuning = p_tuning if p_tuning != null else ZombieTuning.new()
	_rng.seed = p_seed


## Zombies that count toward the cap: the dying are on the ground and do not.
func standing_count() -> int:
	var count := 0
	for zombie: ZombieState in zombies.values():
		if zombie.is_alive():
			count += 1
	return count


func has_room() -> bool:
	return standing_count() < tuning.hard_cap


func spawn(zombie_id: int, speed: float, position: Vector3, yaw: float = 0.0) -> ZombieState:
	var zombie := ZombieState.new()
	zombie.id = zombie_id
	zombie.speed = speed
	zombie.position = position
	zombie.yaw = yaw
	zombie.repath_left = _rng.randf() * tuning.repath_interval
	zombie.retarget_left = _rng.randf() * tuning.retarget_interval
	zombie.enter(ZombieState.Mode.EMERGING)
	zombies[zombie_id] = zombie
	return zombie


## The rules killed it: it falls and is cleared after `death_seconds`.
func begin_death(zombie_id: int) -> void:
	if zombies.has(zombie_id):
		ZombieBrain.die(zombies[zombie_id])


## It left the match without dying (the rules removed it with no killer).
func despawn(zombie_id: int) -> void:
	zombies.erase(zombie_id)


## A hit the rules accepted that did not kill.
func react_to_hit(zombie_id: int) -> void:
	if zombies.has(zombie_id):
		ZombieBrain.stagger(zombies[zombie_id])


func position_of(zombie_id: int) -> Vector3:
	return zombies[zombie_id].position if zombies.has(zombie_id) else Vector3.ZERO


func yaw_of(zombie_id: int) -> float:
	return zombies[zombie_id].yaw if zombies.has(zombie_id) else 0.0


## One fixed step. `targets` maps a player id to where they stand: only players a zombie may chase
## (leave out the downed). Returns the events: `zombie_struck` (zombie_id, target_id, damage) and
## `zombie_cleared` (zombie_id).
func tick(delta: float, targets: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for zombie: ZombieState in zombies.values():
		if zombie.mode == ZombieState.Mode.DYING:
			zombie.mode_time += delta
		else:
			_think(zombie, delta, targets, events)
	_separate(delta)
	_clear_the_dead(events)
	return events


func _think(
	zombie: ZombieState, delta: float, targets: Dictionary, events: Array[Dictionary]
) -> void:
	_retarget(zombie, delta, targets)
	var has_target := targets.has(zombie.target_id)
	var target_pos: Vector3 = targets[zombie.target_id] if has_target else zombie.position
	_repath(zombie, delta, has_target, target_pos)
	var waypoint := _waypoint(zombie, target_pos)
	var strike := ZombieBrain.step(
		zombie, tuning, delta, has_target, target_pos, waypoint, _ground_speed(zombie)
	)
	if not strike.is_empty():
		strike["type"] = &"zombie_struck"
		events.append(strike)
	# Height stays where it spawned: the lot is flat. A path point sits above the floor by a baker
	# offset (twice the cell height), so using its height needs that taken off first.
	zombie.position += zombie.velocity * delta


func _ground_speed(zombie: ZombieState) -> float:
	return rounds.speed_on_ground(zombie.speed, zombie.lit) if rounds != null else zombie.speed


## Keeps the nearest target, switching only to one clearly nearer (`retarget_margin`).
func _retarget(zombie: ZombieState, delta: float, targets: Dictionary) -> void:
	zombie.retarget_left -= delta
	if zombie.retarget_left > 0.0 and targets.has(zombie.target_id):
		return
	zombie.retarget_left = tuning.retarget_interval
	var best_id := -1
	var best_dist := INF
	for player_id: int in targets:
		var d := _flat(zombie.position, targets[player_id])
		if d < best_dist:
			best_dist = d
			best_id = player_id
	var current := INF
	if targets.has(zombie.target_id):
		current = _flat(zombie.position, targets[zombie.target_id])
	if best_dist + tuning.retarget_margin < current or current == INF:
		zombie.target_id = best_id


func _repath(zombie: ZombieState, delta: float, has_target: bool, target_pos: Vector3) -> void:
	zombie.repath_left -= delta
	if zombie.repath_left > 0.0 or not has_target:
		return
	zombie.repath_left = tuning.repath_interval
	zombie.path = pathing.find_path(zombie.position, target_pos)
	zombie.path_index = 0
	if lit_probe.is_valid():
		zombie.lit = lit_probe.call(zombie.position)


## The next point of the path not yet reached; the target itself when there is no path.
func _waypoint(zombie: ZombieState, fallback: Vector3) -> Vector3:
	var path := zombie.path
	var last := path.size() - 1
	while zombie.path_index < last:
		if _flat(zombie.position, path[zombie.path_index]) >= tuning.waypoint_reach:
			break
		zombie.path_index += 1
	return path[zombie.path_index] if zombie.path_index < path.size() else fallback


## Pushes standing zombies that overlap apart, using a grid one radius wide.
func _separate(delta: float) -> void:
	var radius := tuning.separation_radius
	_grid.clear()
	for zombie: ZombieState in zombies.values():
		if zombie.is_alive():
			var cell := _cell(zombie.position, radius)
			if not _grid.has(cell):
				_grid[cell] = []
			_grid[cell].append(zombie)
	for zombie: ZombieState in zombies.values():
		if zombie.is_alive():
			zombie.position += _push_on(zombie, radius) * delta


func _push_on(zombie: ZombieState, radius: float) -> Vector3:
	var push := Vector3.ZERO
	var cell := _cell(zombie.position, radius)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for other: ZombieState in _grid.get(cell + Vector2i(dx, dz), []):
				if other != zombie:
					push += _push_from(zombie, other, radius)
	return push


func _push_from(zombie: ZombieState, other: ZombieState, radius: float) -> Vector3:
	var away := zombie.position - other.position
	away.y = 0.0
	var d := away.length()
	if d >= radius:
		return Vector3.ZERO
	if d < 0.001:  # exactly on top: split by id so the pair separates, deterministically
		away = Vector3.RIGHT if zombie.id < other.id else Vector3.LEFT
		d = 0.001
	return away / d * tuning.separation_speed * (1.0 - d / radius)


func _clear_the_dead(events: Array[Dictionary]) -> void:
	for zombie_id: int in zombies.keys():
		var zombie := zombies[zombie_id]
		if zombie.mode == ZombieState.Mode.DYING and zombie.mode_time >= tuning.death_seconds:
			zombies.erase(zombie_id)
			events.append({"type": &"zombie_cleared", "zombie_id": zombie_id})


static func _cell(position: Vector3, size: float) -> Vector2i:
	return Vector2i(floori(position.x / size), floori(position.z / size))


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
