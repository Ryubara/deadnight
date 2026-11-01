class_name HudPoints
extends HudPart
## The party's points, a container per player: `[portrait][points in the player's colour]`
## (`HudPlayerBox`). Your own comes first and is the larger; the others follow by player id, one to
## three, each in the colour of their seat. A row is made when a player joins and freed when they
## leave; a points change or a down state only rewrites its box. The gains are listed beside the
## crosshair (`HudGains`), where the eye already is.

const WIDTH := HudStyle.COLUMN

## The boxes as {"id", "name", "points", "seat", "colour", "downed", "local"}, top to bottom, for
## tests and tools.
var shown: Array[Dictionary] = []
## Your own points as the box says them, and your own name.
var number_text: String:
	get:
		var box := _local_box()
		return box.number_text if box != null else ""
var name_text: String:
	get:
		var box := _local_box()
		return box.name_text if box != null else ""

var _column := VBoxContainer.new()
## Player id -> the box on screen.
var _boxes: Dictionary[int, HudPlayerBox] = {}


func _init() -> void:
	super()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_theme_constant_override(&"separation", HudStyle.GAP)
	_column.custom_minimum_size.x = WIDTH
	add_child(_column)
	_column.minimum_size_changed.connect(update_minimum_size)


func _get_minimum_size() -> Vector2:
	return _column.get_combined_minimum_size()


func topics() -> Array[StringName]:
	return [HudState.POINTS, HudState.TEAM]


## The player ids in the order they are shown: you, then the others by id.
func order() -> Array[int]:
	var ids: Array[int] = []
	for player_id in state.team:
		if player_id != state.local_player_id:
			ids.append(player_id)
	ids.sort()
	if state.team.has(state.local_player_id):
		ids.push_front(state.local_player_id)
	return ids


func refresh() -> void:
	var ids := order()
	for player_id in _boxes.keys():
		if not ids.has(player_id):
			var gone: Control = _boxes[player_id]
			_column.remove_child(gone)
			gone.queue_free()
			_boxes.erase(player_id)
	shown.clear()
	for i in ids.size():
		var player_id := ids[i]
		var member: Dictionary = state.team[player_id]
		if not _boxes.has(player_id):
			_boxes[player_id] = HudPlayerBox.new()
			_column.add_child(_boxes[player_id])
		var box := _boxes[player_id]
		_column.move_child(box, i)
		var local := player_id == state.local_player_id
		box.show_player(player_id, member, local)
		(
			shown
			. append(
				{
					"id": player_id,
					"name": str(member["name"]),
					"points": int(member["points"]),
					"seat": int(member["seat"]),
					"colour": box.colour,
					"downed": bool(member["downed"]),
					"local": local,
				}
			)
		)
	visible = not ids.is_empty()


## The box of a player, for tests and tools; null when they are not shown.
func box_of(player_id: int) -> HudPlayerBox:
	return _boxes.get(player_id)


func _local_box() -> HudPlayerBox:
	return _boxes.get(state.local_player_id) if state != null else null
