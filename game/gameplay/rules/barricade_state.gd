class_name BarricadeState
extends RefCounted
## The boards across each breach of the fence. Pure state: `GameRules` changes it (a zombie tears a
## board off, a player puts one back) and announces what changed.

var boards: Dictionary[StringName, int] = {}

var _tuning: BarricadeTuning


func _init(p_tuning: BarricadeTuning) -> void:
	_tuning = p_tuning
	for id in _tuning.ids:
		boards[id] = _tuning.boards


func has(id: StringName) -> bool:
	return boards.has(id)


## Boards up across `id`; 0 for a breach there is none of.
func boards_of(id: StringName) -> int:
	return boards.get(id, 0)


func is_full(id: StringName) -> bool:
	return boards_of(id) >= _tuning.boards


## Takes one board off. `&""` when it did, else why not: `unknown_barricade` or `no_boards`.
func tear(id: StringName) -> StringName:
	if not has(id):
		return &"unknown_barricade"
	if boards[id] <= 0:
		return &"no_boards"
	boards[id] -= 1
	return &""


## Puts one board back. `&""` when it did, else why not: `unknown_barricade` or `barricade_full`.
func repair(id: StringName) -> StringName:
	if not has(id):
		return &"unknown_barricade"
	if is_full(id):
		return &"barricade_full"
	boards[id] += 1
	return &""


## The field of an `action_rejected` to blame for a refusal of `tear` or `repair` (`other` for the
## refusals that are not the fence's).
static func field_for(refusal: StringName, other: StringName = &"") -> StringName:
	if refusal == &"unknown_barricade" or refusal == &"no_boards" or refusal == &"barricade_full":
		return &"barricade_id"
	return other if refusal == &"unknown_zombie" else &""


func to_dict() -> Dictionary:
	return boards.duplicate()


## Puts the boards back as `to_dict` left them. Emits nothing: a restore is not a change.
func restore(data: Dictionary) -> void:
	boards.clear()
	for id: Variant in data:
		boards[StringName(id)] = data[id]


## True when `data` names only known breaches, each with a whole number of boards in range.
func fits(data: Dictionary) -> bool:
	if data.size() != _tuning.ids.size():
		return false
	for id: Variant in data:
		if not SnapshotCheck.is_name_type(typeof(id)) or not _tuning.ids.has(StringName(id)):
			return false
		var count: Variant = data[id]
		if typeof(count) != TYPE_INT or count < 0 or count > _tuning.boards:
			return false
	return true
