class_name GameSim
extends RefCounted
## The shared simulation: players on a flat arena, positions in whole centimetres, one fixed
## step per input. No nodes, no engine time: the server runs it for real; a client runs
## `integrate` alone to predict. Only the server resolves player-against-player collisions,
## which is what makes prediction miss sometimes and reconciliation worth having.

const TICK_RATE := 30
const INPUT_MAX := 127
const STEP_CM := 20  # 6 m/s at 30 Hz
const ARENA_CM := 1100
const MIN_DISTANCE_CM := 80  # two capsules of radius 0.4 m

## Zombies live in the same table as players, under ids from ZOMBIE_ID_BASE up, so the protocol and
## the clients treat them as "other things that move".
const ZOMBIE_ID_BASE := 100
const ZOMBIE_STEP_CM := 8  # 2.4 m/s at 30 Hz

var players: Dictionary[int, Vector2i] = {}

var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 1) -> void:
	_rng.seed = seed_value


## One input applied to a position: the movement both sides agree on.
static func integrate(pos: Vector2i, dir: Vector2i) -> Vector2i:
	var d := Vector2(dir)
	if d.length() > INPUT_MAX:  # never trust the client to stay inside the unit circle
		d = d.normalized() * INPUT_MAX
	var step := Vector2i((d * STEP_CM / INPUT_MAX).round())
	return Vector2i(
		clampi(pos.x + step.x, -ARENA_CM, ARENA_CM), clampi(pos.y + step.y, -ARENA_CM, ARENA_CM)
	)


func add_player(id: int) -> void:
	var half := ARENA_CM * 3 / 4
	players[id] = Vector2i(_rng.randi_range(-half, half), _rng.randi_range(-half, half))


func remove_player(id: int) -> void:
	players.erase(id)


func apply_input(id: int, dir: Vector2i) -> void:
	if not players.has(id):
		return
	var others: Array[Vector2i] = []
	for other_id in players:
		if other_id != id:
			others.append(players[other_id])
	players[id] = separate(integrate(players[id], dir), others)


## Pushes a position out of every other body it overlaps, then back inside the arena.
static func separate(pos: Vector2i, others: Array[Vector2i]) -> Vector2i:
	for other in others:
		var offset := pos - other
		var distance := Vector2(offset).length()
		if distance < MIN_DISTANCE_CM:
			var away := Vector2(offset) / distance if distance > 0.0 else Vector2.RIGHT
			pos = other + Vector2i((away * MIN_DISTANCE_CM).round())
	return Vector2i(clampi(pos.x, -ARENA_CM, ARENA_CM), clampi(pos.y, -ARENA_CM, ARENA_CM))


func snapshot() -> Dictionary[int, Vector2i]:
	return players.duplicate()


func add_zombies(count: int) -> void:
	for i in count:
		players[ZOMBIE_ID_BASE + 1 + i] = Vector2i(
			_rng.randi_range(-ARENA_CM, ARENA_CM), _rng.randi_range(-ARENA_CM, ARENA_CM)
		)


## Every zombie takes one step towards the nearest player and stops at touching distance.
func step_zombies() -> void:
	var targets: Array[Vector2i] = []
	for id in players:
		if id <= ZOMBIE_ID_BASE:
			targets.append(players[id])
	for id in players:
		if id > ZOMBIE_ID_BASE:
			players[id] = zombie_next(players[id], targets)


## One zombie step from `pos` towards the nearest of `targets`.
static func zombie_next(pos: Vector2i, targets: Array[Vector2i]) -> Vector2i:
	var best := Vector2i.ZERO
	var best_distance := INF
	for target in targets:
		var distance := Vector2(target - pos).length()
		if distance < best_distance:
			best_distance = distance
			best = target
	if best_distance == INF or best_distance <= MIN_DISTANCE_CM:
		return pos
	var toward := Vector2(best - pos) / best_distance
	return pos + Vector2i((toward * minf(ZOMBIE_STEP_CM, best_distance - MIN_DISTANCE_CM)).round())
