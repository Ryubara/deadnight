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
	var pos := integrate(players[id], dir)
	for other_id in players:
		if other_id == id:
			continue
		var offset := pos - players[other_id]
		var distance := Vector2(offset).length()
		if distance < MIN_DISTANCE_CM:
			var away := Vector2(offset) / distance if distance > 0.0 else Vector2.RIGHT
			pos = players[other_id] + Vector2i((away * MIN_DISTANCE_CM).round())
	players[id] = Vector2i(clampi(pos.x, -ARENA_CM, ARENA_CM), clampi(pos.y, -ARENA_CM, ARENA_CM))


func snapshot() -> Dictionary[int, Vector2i]:
	return players.duplicate()
