class_name HudTeam
extends HudPart
## Teammates for a party of two to four on one ticket: a name and a state tag per line. Hidden when
## you are alone.

## Rows as (name, state) pairs for tests: state is `UP` or `DOWN`.
var shown: Array[PackedStringArray] = []

var _ticket := HudTicket.new()
var _rows := VBoxContainer.new()


func _init() -> void:
	super()
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_theme_constant_override(&"separation", tokens.space_xs)
	_ticket.body.add_child(_rows)
	add_child(_ticket)
	_ticket.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ticket.minimum_size_changed.connect(update_minimum_size)


func _get_minimum_size() -> Vector2:
	return _ticket.get_combined_minimum_size()


func refresh() -> void:
	shown.clear()
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var ids := state.team.keys()
	ids.sort()
	for player_id in ids:
		if player_id != state.local_player_id:
			_rows.add_child(_row(state.team[player_id]))
	visible = _rows.get_child_count() > 0
	_ticket.lit = (
		1.0 if shown.any(func(row: PackedStringArray) -> bool: return row[1] == "DOWN") else 0.0
	)
	_ticket.queue_redraw()


func _row(member: Dictionary) -> HBoxContainer:
	var downed: bool = member["downed"]
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override(&"separation", tokens.space_lg)
	var name_label := HudStyle.label(
		str(member["name"]).to_upper(), HudStyle.TEXT, tokens.ink_disabled if downed else tokens.ink
	)
	name_label.custom_minimum_size.x = 180.0
	var tag := HudStyle.label(
		"DOWN" if downed else "UP",
		HudStyle.SMALL,
		tokens.danger if downed else tokens.accent_bright,
		false,
		HudStyle.TRACK_CAPTION
	)
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(name_label)
	line.add_child(tag)
	shown.append(PackedStringArray([str(member["name"]), "DOWN" if downed else "UP"]))
	return line
