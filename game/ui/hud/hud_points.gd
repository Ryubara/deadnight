class_name HudPoints
extends HudPart
## The party's points, a container per player: `[portrait][points in the player's colour]`
## (`HudPlayerBox`). Your own comes first and is the larger; the others follow by player id, up to
## seven, each in the colour of their seat. A row is made when a player joins and freed when they
## leave; a points change or a down state only rewrites its box. The gains are listed beside the
## crosshair (`HudGains`), where the eye already is. Past eight bodies (the people are eight at
## most, the bots come on top, #1179) the bots are a strip of chips under the boxes
## (`HudBotChips`): fifteen boxes would stand taller than the room the column has.

const WIDTH := HudStyle.COLUMN
## With more players than this the teammates' boxes are the compact size, so a party of eight
## takes about the height four did before.
const COMPACT_FROM := 4

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
## The bots' strip, made when a night reaches more than eight bodies and freed when it falls back.
var _chips: HudBotChips = null
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


## The bots drawn as chips instead of boxes: all of them once the night holds more than the eight
## people can (`NightHost.MAX_PLAYERS`) bodies, none before.
func chip_ids(ids: Array[int]) -> Array[int]:
	var out: Array[int] = []
	if ids.size() > NightHost.MAX_PLAYERS:
		for player_id in ids:
			if bool(state.team[player_id]["bot"]):
				out.append(player_id)
	return out


func refresh() -> void:
	var all := order()
	var chipped := chip_ids(all)
	var ids: Array[int] = []
	for player_id in all:
		if not chipped.has(player_id):
			ids.append(player_id)
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
		box.show_player(
			player_id,
			member,
			local,
			ids.size() > COMPACT_FROM,
			state.level_of(member),
			state.plate_of(member)
		)
		(
			shown
			. append(
				{
					"id": player_id,
					"name": str(member["name"]),
					"bot": bool(member["bot"]),
					"points": int(member["points"]),
					"seat": int(member["seat"]),
					"colour": box.colour,
					"downed": bool(member["downed"]),
					"local": local,
				}
			)
		)
	for player_id in chipped:
		var member: Dictionary = state.team[player_id]
		(
			shown
			. append(
				{
					"id": player_id,
					"name": str(member["name"]),
					"bot": true,
					"points": int(member["points"]),
					"seat": int(member["seat"]),
					"colour": LookCatalog.armband_colour(int(member["seat"])),
					"downed": bool(member["downed"]),
					"local": false,
					"chip": true,
				}
			)
		)
	_show_chips(chipped)
	visible = not all.is_empty()


## The strip of chips the bots are drawn as past eight bodies, for tests and tools; null while the
## night has eight bodies or fewer.
func chips() -> HudBotChips:
	return _chips


## Draws `ids` as chips. The strip is only built for a night past eight bodies and freed when it is
## back at eight or fewer, so a small night holds none of its nodes (the perf budget counts them).
func _show_chips(ids: Array[int]) -> void:
	if ids.is_empty():
		if _chips != null:
			_column.remove_child(_chips)
			_chips.queue_free()
			_chips = null
		return
	if _chips == null:
		_chips = HudBotChips.new()
		_column.add_child(_chips)
	_column.move_child(_chips, -1)
	_chips.show_bots(ids, state.team)


## The box of a player, for tests and tools; null when they are not shown.
func box_of(player_id: int) -> HudPlayerBox:
	return _boxes.get(player_id)


func _local_box() -> HudPlayerBox:
	return _boxes.get(state.local_player_id) if state != null else null
