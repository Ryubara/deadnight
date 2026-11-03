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

## The step the sim advances by, whatever deltas its caller passes: server and tests agree.
const STEP := 1.0 / 30.0
## After a stall the sim runs at most this many steps to catch up and drops the rest of the time
## (a long hitch must not freeze the server in a burst of ticks, nor throw zombies about).
const MAX_CATCH_UP_STEPS := 8
## Float sums of caller deltas land a hair under a whole step; this much counts as whole.
const STEP_EPSILON := 1e-6
## Two zombies closer than this (metres) have no direction between them to push along.
const COINCIDENT_DISTANCE := 0.001
## Multipliers of the golden-ratio family that spread a pair of ids evenly round a circle.
const _PAIR_ANGLE_A := 0.7548776662
const _PAIR_ANGLE_B := 0.5698402910
## How far above the floor the navigation map's path points run (the baker's walkable surface sits
## a cell and a bit over the geometry's top), for a pathing that does not say (`ground_offset`):
## taken off a path point to get the ground a zombie stands on. Measured on the second map, whose
## floors are at 0 and 3.4 m.
const NAV_LIFT := 0.35
## Metres over the feet at which a swing is judged to have a clear way to its target: over the
## second map's racks (1.2 m), under its ceiling. The hall's counter is higher (1.5 m) and stops
## it, but no swing crosses a counter 3.5 m deep.
const SWING_HEIGHT := 1.3
## Metres past the longest swing within which the way to a target is looked at.
const SWING_SLACK := 0.5
## Metres of walking a step up or down one storey counts for when a zombie picks its target: a
## player on another floor is as far as this many metres of floor for each metre of height.
const STOREY_WEIGHT := 3.0

## A zombie that is chasing, is `STRAND_FAR` metres or more from its target and whose path from the
## map stops `STRAND_GAP` metres or more short of it, for `STRAND_SECONDS`, is stranded: the crowd
## shoved it through a wall into a pocket of the walking mesh and it stands at the end of a path
## that goes nowhere (the soak's rounds that went on for eight minutes, #770). The sim says so
## (`zombie_stranded`) and the director puts it back on a spawn point (`relocate`).
const STRAND_GAP := 3.0
const STRAND_FAR := 12.0
const STRAND_SECONDS := 12.0

var tuning: ZombieTuning
## Used for the speed of a zombie off lit ground; without it light changes nothing.
var rounds: RoundTuning
var pathing: ZombiePathing = ZombiePathing.new()
## `Callable(position: Vector3) -> bool`: whether that ground is lit. Asked at each repath.
var lit_probe: Callable = Callable()
## The fence's breaches by id. A zombie spawned for one (`spawn`'s `gate_id`) stops at its boards.
var gates: Dictionary[StringName, ZombieGate] = {}
## The boards across each breach: the rules' own state, read here and never changed. (A `Callable`
## to its method crashed Godot at exit, so the sim holds the object.) Without it none stand.
var barricades: BarricadeState
## Seconds of work one board takes a walker (a type's `barrier_speed` makes it quicker).
var board_seconds: float = 1.2
## The height of one storey of the map, or 0 for a flat map (the lot). A map with floors above one
## another (the second map) sets it: the dead then follow the walking mesh up and down its stairs,
## are as far from a player on another floor as the stair makes them, and neither start nor land a
## swing across a floor. On a map without it (the lot) the dead still follow the floor of a path
## from the navigation map (its ramps) and swing only within `tuning.reach_height`.
var storey := 0.0
## `Callable(from: Vector3, to: Vector3) -> float`: metres to the first wall on the way, or -1.0
## when clear (a `WorldProbe`). On a map with storeys a zombie swings only at a target it has a
## clear way to, so the dead on a stair do not hit a player beside it through the wall.
var sight: Callable = Callable()
var zombies: Dictionary[int, ZombieBody] = {}
## The lures burning now (`add_lure`, `ZombieLure`).
var lures: Array[ZombieLure] = []

var _rng := RandomNumberGenerator.new()
var _grid: Dictionary[Vector2i, Array] = {}
## What a cell nobody stands in answers, so a lookup makes no array.
var _no_zombies: Array = []
## Time handed to `tick` that has not made a whole step yet.
var _pending: float = 0.0


func _init(p_tuning: ZombieTuning = null, p_seed: int = 0) -> void:
	tuning = p_tuning if p_tuning != null else ZombieTuning.shipped()
	_rng.seed = p_seed


## Zombies that count toward the cap: the dying are on the ground and do not.
## A lure starts burning at `position`: for `seconds` the zombies within `radius` go to it (the
## tuning says which may stay on what they are doing). A lure with the same id is replaced.
func add_lure(lure_id: int, position: Vector3, radius: float, seconds: float) -> void:
	for i in lures.size():
		if lures[i].id == lure_id:
			lures.remove_at(i)
			break
	lures.append(ZombieLure.new(lure_id, position, radius, seconds))


func standing_count() -> int:
	var count := 0
	for zombie: ZombieBody in zombies.values():
		if zombie.is_alive():
			count += 1
	return count


func has_room() -> bool:
	return standing_count() < tuning.hard_cap


## `profile` is what the rules made of the zombie's type; without one it is a plain zombie.
## `gate_id` names the breach it came to get through, or none.
func spawn(
	zombie_id: int,
	speed: float,
	position: Vector3,
	yaw: float = 0.0,
	profile: ZombieProfile = null,
	gate_id: StringName = &""
) -> ZombieBody:
	var zombie := ZombieBody.new()
	zombie.id = zombie_id
	zombie.profile = profile if profile != null else ZombieProfile.plain(tuning)
	zombie.speed = speed
	zombie.position = position
	zombie.yaw = yaw
	zombie.gate_id = gate_id
	zombie.repath_left = _rng.randf() * tuning.repath_interval
	zombie.retarget_left = _rng.randf() * tuning.retarget_interval
	zombie.enter(ZombieBody.Mode.EMERGING)
	zombies[zombie_id] = zombie
	return zombie


## The rules killed it: it falls and is cleared after `death_seconds`.
func begin_death(zombie_id: int) -> void:
	if zombies.has(zombie_id):
		ZombieBrain.die(zombies[zombie_id])


## It left the match without dying (the rules removed it with no killer).
func despawn(zombie_id: int) -> void:
	zombies.erase(zombie_id)


## A blast took its legs: it is what `profile` says now (a crawler), at `speed_scale` of the speed
## it had, and it drops. Once only: its speed is not scaled again.
func cripple(zombie_id: int, profile: ZombieProfile, speed_scale: float) -> void:
	if not zombies.has(zombie_id):
		return
	var zombie := zombies[zombie_id]
	if zombie.crippled or not zombie.is_alive():
		return
	zombie.crippled = true
	zombie.profile = profile
	zombie.speed *= speed_scale
	ZombieBrain.stagger(zombie)


## A hit on a weak spot that did not kill: staggers a zombie that has one (a boss), unless it was
## staggered lately. Every other zombie shrugs it off.
func weak_hit(zombie_id: int) -> void:
	if not zombies.has(zombie_id):
		return
	var zombie := zombies[zombie_id]
	if not zombie.profile.weak or zombie.stagger_cooldown_left > 0.0:
		return
	if zombie.mode == ZombieBody.Mode.CHASE or zombie.mode == ZombieBody.Mode.ATTACK:
		ZombieBrain.stagger(zombie)
		zombie.stagger_cooldown_left = zombie.profile.stagger_cooldown


## A hit the rules accepted that did not kill.
func react_to_hit(zombie_id: int) -> void:
	if zombies.has(zombie_id):
		ZombieBrain.stagger(zombies[zombie_id])


## A blast reached it (`blast_hit`): it is thrown along the ground by `impulse` (the push slows
## down at `ZombieTuning.push_decay`) and held for `stun` seconds. Its height is not moved: the lot
## is flat.
func blast(zombie_id: int, impulse: Vector3, stun: float) -> void:
	if not zombies.has(zombie_id):
		return
	var zombie := zombies[zombie_id]
	if not zombie.is_alive():
		return
	ZombieBrain.stun(zombie, stun)
	zombie.push = Vector3(impulse.x, 0.0, impulse.z).limit_length(tuning.push_max_speed)


## A status effect changed what the zombie is under (`CombatServer`'s `status_applied` and
## `status_ended`): `wire` is the id the snapshot carries (0 for none), `halts` whether it stands
## still and does not attack, `speed_scale` the share of its speed it keeps.
func set_status(zombie_id: int, wire: int, halts: bool, speed_scale: float) -> void:
	if not zombies.has(zombie_id):
		return
	var zombie := zombies[zombie_id]
	zombie.status = wire
	zombie.halted = halts
	zombie.slow = speed_scale
	if halts:
		ZombieBrain.hold(zombie)


## A zombie the rules killed while it was frozen breaks apart: it is gone at once, with no corpse
## and no fall. The answer is the `zombie_shattered` event the clients draw the pieces from (where
## it stood, how it faced, its look and how tall its body was against a walker's), or `{}` for a
## zombie the sim does not hold.
func shatter(zombie_id: int) -> Dictionary:
	if not zombies.has(zombie_id):
		return {}
	var zombie := zombies[zombie_id]
	zombies.erase(zombie_id)
	return {
		"type": &"zombie_shattered",
		"zombie_id": zombie_id,
		"position": zombie.position,
		"yaw": zombie.yaw,
		"look": zombie.look(),
		"scale": ZombieModels.aim_scale(zombie.look()),
	}


func position_of(zombie_id: int) -> Vector3:
	return zombies[zombie_id].position if zombies.has(zombie_id) else Vector3.ZERO


func yaw_of(zombie_id: int) -> float:
	return zombies[zombie_id].yaw if zombies.has(zombie_id) else 0.0


## Advances the zombies by `delta` seconds in whole `STEP`s: the sim only ever steps by `STEP`, so
## the caller's frame rate cannot change what happens (a 60 Hz caller steps every second call, a
## 20 Hz one steps twice some calls). Time that is not a positive number is ignored, and a stall
## is caught up by at most `MAX_CATCH_UP_STEPS`. `targets` maps a player id to where they stand:
## only players a zombie may chase (leave out the downed). Returns the events of all the steps
## taken: `zombie_struck` (zombie_id, target_id, damage, knockback), `zombie_tore` (zombie_id,
## gate_id: it finished pulling a board off) and `zombie_cleared` (zombie_id).
func tick(delta: float, targets: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not is_finite(delta) or delta <= 0.0:
		return events
	_pending = minf(_pending + delta, MAX_CATCH_UP_STEPS * STEP)
	while _pending >= STEP - STEP_EPSILON:
		_pending = maxf(_pending - STEP, 0.0)
		events.append_array(_step(targets))
	return events


## One fixed step.
func _step(targets: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for lure in lures:
		lure.left -= STEP
	lures = lures.filter(func(lure: ZombieLure) -> bool: return lure.left > 0.0)
	var began := PerfProbe.begin()
	for zombie: ZombieBody in zombies.values():
		zombie.stagger_cooldown_left = maxf(zombie.stagger_cooldown_left - STEP, 0.0)
		if zombie.mode == ZombieBody.Mode.DYING:
			zombie.mode_time += STEP
		elif zombie.halted:
			ZombieBrain.hold(zombie)
		else:
			_think(zombie, STEP, targets, events)
	PerfProbe.end(&"sim.think", began)
	began = PerfProbe.begin()
	_separate(STEP)
	PerfProbe.end(&"sim.separate", began)
	began = PerfProbe.begin()
	_keep_outside_the_boards()
	_clear_the_dead(events)
	PerfProbe.end(&"sim.boards_and_clear", began)
	return events


func _think(
	zombie: ZombieBody, delta: float, targets: Dictionary, events: Array[Dictionary]
) -> void:
	var lure := _lure_for(zombie)
	var lure_id := lure.id if lure != null else 0
	if lure_id != zombie.lure_id:
		zombie.lure_id = lure_id
		zombie.repath_left = 0.0
	if lure == null:
		_retarget(zombie, delta, targets)
	var has_target := lure != null or targets.has(zombie.target_id)
	var target_pos := zombie.position
	if lure != null:
		target_pos = lure.position
	elif has_target:
		target_pos = targets[zombie.target_id]
	_repath(zombie, delta, has_target, target_pos)
	_watch_strand(zombie, delta, has_target and lure == null, target_pos, events)
	var waypoint := _waypoint(zombie, target_pos)
	# At a lure a zombie stands about it, facing it: no target to walk to and none to swing at.
	var gathered := (
		lure != null and _flat(zombie.position, lure.position) <= tuning.lure_gather_distance
	)
	if gathered and zombie.mode == ZombieBody.Mode.CHASE:
		ZombieBrain.face(zombie, tuning, delta, lure.position)
	var strike := ZombieBrain.step(
		zombie,
		tuning,
		delta,
		has_target and not gathered,
		target_pos,
		waypoint,
		_ground_speed(zombie),
		_can_swing(zombie.position, target_pos)
	)
	if not strike.is_empty():
		strike["type"] = &"zombie_struck"
		events.append(strike)
	zombie.tearing = false
	if zombie.gate_id != &"":
		_work_the_boards(zombie, delta, events)
	zombie.position += (zombie.velocity + zombie.push) * delta
	_settle_on_ground(zombie, delta)
	zombie.push = zombie.push.move_toward(Vector3.ZERO, tuning.push_decay * delta)


## Counts the seconds a chasing zombie has had no way to a far target; says `zombie_stranded` when
## they reach `STRAND_SECONDS` (and counts again from nothing). One at its boards, at a lure, near
## its target or with a way to it is not stranded.
func _watch_strand(
	zombie: ZombieBody, delta: float, chasing: bool, target_pos: Vector3, events: Array[Dictionary]
) -> void:
	var stranded := (
		chasing
		and zombie.mode == ZombieBody.Mode.CHASE
		and not _is_at_its_gate(zombie)
		and zombie.path_gap >= STRAND_GAP
		and _flat(zombie.position, target_pos) >= STRAND_FAR
	)
	if not stranded:
		zombie.stranded_for = 0.0
		return
	zombie.stranded_for += delta
	if zombie.stranded_for >= STRAND_SECONDS:
		zombie.stranded_for = 0.0
		events.append({"type": &"zombie_stranded", "zombie_id": zombie.id})


## Whether the zombie has a gate and is in front of its gap: at its boards, or walking through.
func _is_at_its_gate(zombie: ZombieBody) -> bool:
	var gate: ZombieGate = gates.get(zombie.gate_id)
	return gate != null and gate.spans(zombie.position)


## Puts a stranded zombie back on `point` (a spawn point; `gate_id` the breach it comes in by, or
## none), rising as a new one does, with no path and no memory of the pocket.
func relocate(zombie_id: int, point: Vector3, gate_id: StringName = &"") -> void:
	var zombie: ZombieBody = zombies.get(zombie_id)
	if zombie == null or not zombie.is_alive():
		return
	zombie.position = point
	zombie.gate_id = gate_id
	zombie.path = PackedVector3Array()
	zombie.path_index = 0
	zombie.path_gap = 0.0
	zombie.stranded_for = 0.0
	zombie.repath_left = 0.0
	zombie.tear_progress = 0.0
	zombie.push = Vector3.ZERO
	zombie.enter(ZombieBody.Mode.EMERGING)


## Lifts or lowers the zombie to the floor its path runs on, at most `tuning.climb_speed` a second.
## The path lies on the navigation mesh, above the floor by `pathing.ground_offset()` (on a map with
## storeys and a pathing that does not say, `NAV_LIFT`); the height is read off the segment of the
## path the zombie is on, so a ramp or a stair is a ramp. A zombie that kept the height it spawned
## at walked the booth's ramp under it: the next repath snapped its ground-level position to the
## floor beside the ramp, and that path led back to the ramp's foot. A path that is a straight line
## to a target (no ground offset) carries no floor, and the zombie keeps its height.
func _settle_on_ground(zombie: ZombieBody, delta: float) -> void:
	var offset := pathing.ground_offset()
	if is_nan(offset) and storey > 0.0:
		offset = NAV_LIFT
	if is_nan(offset) or zombie.path.is_empty() or not zombie.is_alive():
		return
	var ground := _ground_under(zombie) - offset
	zombie.position.y = move_toward(zombie.position.y, ground, tuning.climb_speed * delta)


## The height of the path under the zombie: the segment it walks is the one that ends at its
## waypoint, and the height is where the zombie's shadow falls along it.
func _ground_under(zombie: ZombieBody) -> float:
	var path := zombie.path
	var to_index := mini(zombie.path_index, path.size() - 1)
	if to_index == 0:
		return path[0].y
	var from := path[to_index - 1]
	var to := path[to_index]
	var along := Vector2(to.x - from.x, to.z - from.z)
	var length_squared := along.length_squared()
	if length_squared < COINCIDENT_DISTANCE * COINCIDENT_DISTANCE:
		return to.y
	var here := Vector2(zombie.position.x - from.x, zombie.position.z - from.z)
	return lerpf(from.y, to.y, clampf(here.dot(along) / length_squared, 0.0, 1.0))


## The nearest lure that calls this zombie, or null: one within its radius, unless the zombie is
## tearing boards, is a boss or is in a swing and the tuning leaves those alone. A zombie that is
## not up yet or is dying hears nothing.
func _lure_for(zombie: ZombieBody) -> ZombieLure:
	if lures.is_empty() or zombie.mode == ZombieBody.Mode.EMERGING or not zombie.is_alive():
		return null
	if zombie.gate_id != &"" and not tuning.lure_pulls_gate_zombies:
		return null
	if zombie.profile.boss and not tuning.lure_pulls_bosses:
		return null
	if zombie.mode == ZombieBody.Mode.ATTACK and not tuning.lure_breaks_swings:
		return null
	var best: ZombieLure
	var best_distance := INF
	for lure in lures:
		if not lure.reaches(zombie.position):
			continue
		var distance := _flat(zombie.position, lure.position)
		if distance < best_distance:
			best_distance = distance
			best = lure
	return best


## A zombie that came for a breach stops short of its boards while any stand, and once at them
## pulls them off: a swing at a time, the work of a board adding up at its `barrier_speed`. A type
## that cannot tear (a crawler) is not held; it goes under. Through the line, the gate is behind it.
func _work_the_boards(zombie: ZombieBody, delta: float, events: Array[Dictionary]) -> void:
	var gate := _gate_in_front_of(zombie)
	if gate == null:
		# Beside the wall, in front of no gap: nothing to tear here (#810). A breach nobody told
		# the sim about is behind the zombie.
		zombie.tear_progress = 0.0
		if not gates.has(zombie.gate_id):
			zombie.gate_id = &""
		return
	var depth := gate.depth_of(zombie.position)
	if depth >= 0.0:
		zombie.gate_id = &""
		zombie.tear_progress = 0.0
		return
	if not _boards_hold(zombie, gate):
		zombie.tear_progress = 0.0
		return
	var stop := -tuning.board_stop
	var inward_speed := zombie.velocity.dot(gate.inward)
	if inward_speed > 0.0 and depth + inward_speed * delta > stop:
		var allowed := maxf(stop - depth, 0.0) / delta
		zombie.velocity -= gate.inward * (inward_speed - allowed)
	zombie.move_speed = zombie.velocity.length()
	if depth < stop - tuning.board_slack:
		return
	if zombie.mode == ZombieBody.Mode.CHASE:
		zombie.enter(ZombieBody.Mode.ATTACK)
	if zombie.mode != ZombieBody.Mode.ATTACK:
		return
	zombie.tearing = true
	zombie.tear_progress += delta * zombie.profile.barrier_speed
	if zombie.tear_progress >= board_seconds:
		zombie.tear_progress -= board_seconds
		events.append({"type": &"zombie_tore", "zombie_id": zombie.id, "gate_id": zombie.gate_id})


## The gate this zombie is in front of: its own while it is within that gap's width, otherwise the
## one whose gap it has come up to (outside the line, in front of the gap, within
## `ZombieGate.REACH`), which becomes its own, or null beside the wall. A gate is a line with the
## width of its gap: as the whole wall's line, a dead on its way along the wall to another window
## stopped out of sight at its first gate's line and tore that gate's boards from there for ever
## (#810).
func _gate_in_front_of(zombie: ZombieBody) -> ZombieGate:
	var own: ZombieGate = gates.get(zombie.gate_id)
	if own != null and own.spans(zombie.position):
		return own
	var best: ZombieGate
	var best_along := INF
	for gate: ZombieGate in gates.values():
		if gate == own or not gate.is_at(zombie.position):
			continue
		var along := absf(gate.along_of(zombie.position))
		if along < best_along:
			best_along = along
			best = gate
	if best != null:
		zombie.gate_id = best.id
		zombie.tear_progress = 0.0
	return best


## Whether boards stand across `gate` that this zombie has to tear down.
func _boards_hold(zombie: ZombieBody, gate: ZombieGate) -> bool:
	if zombie.profile.barrier_speed <= 0.0 or barricades == null:
		return false
	return barricades.boards_of(gate.id) > 0


## What the separation push moved across the line goes back: the crowd cannot shove a zombie
## through boards that stand.
func _keep_outside_the_boards() -> void:
	for zombie: ZombieBody in zombies.values():
		if zombie.gate_id == &"" or not zombie.is_alive():
			continue
		var gate: ZombieGate = gates.get(zombie.gate_id)
		if gate == null or not gate.spans(zombie.position) or not _boards_hold(zombie, gate):
			continue
		var depth := gate.depth_of(zombie.position)
		var stop := -tuning.board_stop
		if depth < 0.0 and depth > stop:
			zombie.position += gate.inward * (stop - depth)


func _ground_speed(zombie: ZombieBody) -> float:
	var speed := zombie.speed * zombie.slow
	return rounds.speed_on_ground(speed, zombie.lit) if rounds != null else speed


## Puts the sim on a map with storeys (`storey`, 0 for none) and the way it sees walls (`sight`).
func set_floors(height: float, probe: Callable) -> void:
	storey = height
	sight = probe


## Whether a zombie at `a` may swing at a target at `b`: on a flat map, within `reach_height` (the
## lot's roost floor is over the heads of the dead under it); else within half a storey in height
## and, when the target is near enough to be struck, with no wall between them.
func _can_swing(a: Vector3, b: Vector3) -> bool:
	if storey <= 0.0:
		return absf(a.y - b.y) <= tuning.reach_height
	if absf(a.y - b.y) > storey * 0.5:
		return false
	if not sight.is_valid() or _flat(a, b) > tuning.reach + tuning.strike_slack + SWING_SLACK:
		return true
	var lift := Vector3(0.0, SWING_HEIGHT, 0.0)
	return float(sight.call(a + lift, b + lift)) < 0.0


## The distance a zombie weighs a player by: the flat distance, and on a map with storeys more for
## every metre of height between them (the stair is a long way round).
func _target_distance(a: Vector3, b: Vector3) -> float:
	var flat := _flat(a, b)
	return flat + STOREY_WEIGHT * absf(a.y - b.y) if storey > 0.0 else flat


## Keeps the nearest target, switching only to one clearly nearer (`retarget_margin`).
func _retarget(zombie: ZombieBody, delta: float, targets: Dictionary) -> void:
	zombie.retarget_left -= delta
	if zombie.retarget_left > 0.0 and targets.has(zombie.target_id):
		return
	zombie.retarget_left = tuning.retarget_interval
	var best_id := -1
	var best_dist := INF
	for player_id: int in targets:
		var d := _target_distance(zombie.position, targets[player_id])
		if d < best_dist:
			best_dist = d
			best_id = player_id
	var current := INF
	if targets.has(zombie.target_id):
		current = _target_distance(zombie.position, targets[zombie.target_id])
	if best_dist + tuning.retarget_margin < current or current == INF:
		zombie.target_id = best_id


func _repath(zombie: ZombieBody, delta: float, has_target: bool, target_pos: Vector3) -> void:
	zombie.repath_left -= delta
	if zombie.repath_left > 0.0 or not has_target:
		return
	# Only a zombie on the move follows a path: one that is swinging, rising, staggered or held
	# keeps its timer at zero and asks the moment it walks again (a crowd at the players' feet is
	# mostly swinging, and every path it asked for was thrown away).
	if zombie.mode != ZombieBody.Mode.CHASE:
		return
	var interval := tuning.repath_interval
	if _flat(zombie.position, target_pos) > tuning.repath_far_distance:
		interval *= tuning.repath_far_factor
	zombie.repath_left = interval
	var began := PerfProbe.begin()
	zombie.path = pathing.find_path(zombie.position, target_pos)
	PerfProbe.end(&"sim.path", began)
	zombie.path_index = 0
	zombie.path_gap = _flat(zombie.path[-1], target_pos) if not zombie.path.is_empty() else INF
	if lit_probe.is_valid():
		zombie.lit = lit_probe.call(zombie.position)


## The next point of the path not yet reached; the target itself when there is no path.
func _waypoint(zombie: ZombieBody, fallback: Vector3) -> Vector3:
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
	for zombie: ZombieBody in zombies.values():
		if zombie.is_alive():
			var cell := _cell(zombie.position, radius)
			if not _grid.has(cell):
				_grid[cell] = []
			_grid[cell].append(zombie)
	for zombie: ZombieBody in zombies.values():
		if zombie.is_alive():
			zombie.position += _push_on(zombie, radius) * delta


func _push_on(zombie: ZombieBody, radius: float) -> Vector3:
	var push := Vector3.ZERO
	var cell := _cell(zombie.position, radius)
	var here := zombie.position
	var radius_squared := radius * radius
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for other: ZombieBody in _grid.get(cell + Vector2i(dx, dz), _no_zombies):
				if other == zombie:
					continue
				# Most of the neighbours in the nine cells are farther than the radius: no square
				# root for them.
				var away := here - other.position
				# One above the other (the ramp over the floor beside it) do not touch.
				if (
					away.x * away.x + away.z * away.z < radius_squared
					and absf(away.y) < tuning.separation_height
				):
					push += _push_from(zombie, other, radius)
	# A pile of coincident zombies adds up a push from each; the sum is bounded so no tick throws one.
	return push.limit_length(tuning.separation_max_speed)


## The push on `zombie` from `other`, at most `separation_speed`, along the line between them.
func _push_from(zombie: ZombieBody, other: ZombieBody, radius: float) -> Vector3:
	var away := zombie.position - other.position
	away.y = 0.0
	var d := away.length()
	if d >= radius:
		return Vector3.ZERO
	if d < COINCIDENT_DISTANCE:
		return _apart_direction(zombie.id, other.id) * tuning.separation_speed
	return away / d * tuning.separation_speed * (1.0 - d / radius)


## The way the lower id of a pair pushes off the higher when they stand on one point; the higher
## goes the opposite way. A function of the two ids alone (no clock, no random draw), spread
## round the circle so a pile does not part along one line.
static func _apart_direction(id: int, other_id: int) -> Vector3:
	var low := mini(id, other_id)
	var high := maxi(id, other_id)
	var angle := fposmod(low * _PAIR_ANGLE_A + high * _PAIR_ANGLE_B, 1.0) * TAU
	var direction := Vector3(cos(angle), 0.0, sin(angle))
	return direction if id < other_id else -direction


func _clear_the_dead(events: Array[Dictionary]) -> void:
	for zombie_id: int in zombies.keys():
		var zombie := zombies[zombie_id]
		if zombie.mode == ZombieBody.Mode.DYING and zombie.mode_time >= tuning.death_seconds:
			zombies.erase(zombie_id)
			events.append({"type": &"zombie_cleared", "zombie_id": zombie_id})


static func _cell(position: Vector3, size: float) -> Vector2i:
	return Vector2i(floori(position.x / size), floori(position.z / size))


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
