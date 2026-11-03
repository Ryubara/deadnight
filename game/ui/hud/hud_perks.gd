class_name HudPerks
extends HudPart
## The perks the local player has, as a block of small badges beside the health card (#707): one for
## each drink had, in the shop's order, the picture of the machine it came from. The frame's perk
## bits are all it reads (`HudState.perks`), so a purchase adds a badge and a down that takes the
## perks takes the badges, with nothing else to remember. Two badges a row, rows added upward, so
## the block is 2 badges wide at most and fits beside the card on the smallest canvas.
## `Hud` keeps it beside the health card (`Hud._place_perks`); with no perk it is hidden.

## Badges in a row.
const COLUMNS := 2
const GAP := float(HudStyle.SM)
## The width of the block with a full row.
const WIDTH := HudPerkBadge.SIDE * COLUMNS + GAP * (COLUMNS - 1)

var _badges: Array[HudPerkBadge] = []


func _init() -> void:
	super()
	visible = false


func topics() -> Array[StringName]:
	return [HudState.PERKS]


func refresh() -> void:
	var ids := state.perks
	while _badges.size() > ids.size():
		var gone: HudPerkBadge = _badges.pop_back()
		remove_child(gone)
		gone.free()
	while _badges.size() < ids.size():
		var badge := HudPerkBadge.new()
		_badges.append(badge)
		add_child(badge)
	for i in ids.size():
		_badges[i].show_tonic(ids[i])
	_arrange()
	visible = not ids.is_empty()
	update_minimum_size()
	size = get_combined_minimum_size()


## The tonic ids on show, in order.
func shown() -> Array[StringName]:
	var ids: Array[StringName] = []
	for badge in _badges:
		ids.append(badge.tonic_id)
	return ids


func badges() -> Array[HudPerkBadge]:
	return _badges


func _get_minimum_size() -> Vector2:
	if _badges.is_empty():
		return Vector2.ZERO
	var columns := mini(_badges.size(), COLUMNS)
	var rows := _rows()
	return Vector2(
		HudPerkBadge.SIDE * columns + GAP * (columns - 1),
		HudPerkBadge.SIDE * rows + GAP * (rows - 1)
	)


func _rows() -> int:
	return ceili(float(_badges.size()) / float(COLUMNS))


## The first row is the bottom one (beside the card's own bottom), the next ones go up.
func _arrange() -> void:
	var rows := _rows()
	for i in _badges.size():
		var row_from_bottom := i / COLUMNS
		_badges[i].position = Vector2(
			float(i % COLUMNS) * (HudPerkBadge.SIDE + GAP),
			float(rows - 1 - row_from_bottom) * (HudPerkBadge.SIDE + GAP)
		)
