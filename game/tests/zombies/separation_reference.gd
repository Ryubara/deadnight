class_name SeparationReference
extends ZombieSim
## The separation pass as it was before #933, kept as the oracle for the flat grid
## (`SeparationGrid`):
## a `Dictionary` of cells, an `Array` made for each occupied cell on every step, the crowd copied
## with `values()`. The two must move every zombie to the same place, bit for bit. Never used by
## the game; the cost bench (`tools/bench/separation_cost.gd`) is run on the old commit to measure
## the whole old step.

var _reference_cells: Dictionary[Vector2i, Array] = {}
var _reference_empty: Array = []


func _separate(delta: float) -> void:
	var radius := tuning.separation_radius
	_reference_cells.clear()
	for zombie: ZombieBody in zombies.values():
		if zombie.is_alive():
			var cell := _reference_cell(zombie.position, radius)
			if not _reference_cells.has(cell):
				_reference_cells[cell] = []
			_reference_cells[cell].append(zombie)
	for zombie: ZombieBody in zombies.values():
		if zombie.is_alive():
			zombie.position += _reference_push_on(zombie, radius) * delta


func _reference_push_on(zombie: ZombieBody, radius: float) -> Vector3:
	var push := Vector3.ZERO
	var cell := _reference_cell(zombie.position, radius)
	var here := zombie.position
	var radius_squared := radius * radius
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for other: ZombieBody in _reference_cells.get(
				cell + Vector2i(dx, dz), _reference_empty
			):
				if other == zombie:
					continue
				var away := here - other.position
				if (
					away.x * away.x + away.z * away.z < radius_squared
					and absf(away.y) < tuning.separation_height
				):
					push += _push_from(zombie, other, radius)
	return push.limit_length(tuning.separation_max_speed)


## `crowd_around` as it was when it read the dictionary of cells.
func reference_crowd_around(zombie_id: int, radius: float) -> int:
	var zombie: ZombieBody = zombies.get(zombie_id)
	if zombie == null:
		return 0
	var count := 0
	var limit := radius * radius
	var cell := _reference_cell(zombie.position, tuning.separation_radius)
	var reach := ceili(radius / tuning.separation_radius)
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			for other: ZombieBody in _reference_cells.get(
				cell + Vector2i(dx, dz), _reference_empty
			):
				if (
					other == zombie
					or absf(other.position.y - zombie.position.y) >= tuning.separation_height
				):
					continue
				var away := other.position - zombie.position
				if away.x * away.x + away.z * away.z <= limit:
					count += 1
	return count


static func _reference_cell(position: Vector3, size: float) -> Vector2i:
	return Vector2i(floori(position.x / size), floori(position.z / size))
