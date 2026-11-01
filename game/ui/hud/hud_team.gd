class_name HudTeam
extends HudPart
## Teammates for a party of two to four on one ticket: a name and a state tag per line. Hidden when
## you are alone. A row is made when a player joins and freed when they leave; a name or a down
## state only changes the row's text.

## Width of a name; a longer one ends in an ellipsis rather than widening the party ticket.
const NAME_WIDTH := 268.0

## Rows as (name, state) pairs for tests: state is `UP` or `DOWN`.
var shown: Array[PackedStringArray] = []

var _ticket := HudTicket.new()
var _rows := VBoxContainer.new()
## Player id -> {"line", "name", "tag"} of the row on screen.
var _lines: Dictionary[int, Dictionary] = {}


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


func topics() -> Array[StringName]:
	return [HudState.TEAM]


func refresh() -> void:
	var ids: Array = state.team.keys()
	ids.sort()
	ids = ids.filter(func(id: int) -> bool: return id != state.local_player_id)
	for player_id: int in _lines.keys():
		if not ids.has(player_id):
			var gone: Control = _lines[player_id]["line"]
			_rows.remove_child(gone)
			gone.queue_free()
			_lines.erase(player_id)
	shown.clear()
	var any_down := false
	for i in ids.size():
		var player_id: int = ids[i]
		var member: Dictionary = state.team[player_id]
		if not _lines.has(player_id):
			_lines[player_id] = _make_row()
			_rows.add_child(_lines[player_id]["line"])
		var row: Dictionary = _lines[player_id]
		_rows.move_child(row["line"], i)
		_write(row, member)
		any_down = any_down or bool(member["downed"])
		shown.append(PackedStringArray([str(member["name"]), "DOWN" if member["downed"] else "UP"]))
	visible = not ids.is_empty()
	var lit_now := 1.0 if any_down else 0.0
	if _ticket.lit != lit_now:
		_ticket.lit = lit_now


func _make_row() -> Dictionary:
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override(&"separation", tokens.space_lg)
	var name_label := HudStyle.clip(HudStyle.label("", HudStyle.TEXT, tokens.ink))
	name_label.custom_minimum_size.x = NAME_WIDTH
	var tag := HudStyle.label(
		"", HudStyle.SMALL, tokens.accent_bright, false, HudStyle.TRACK_CAPTION
	)
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(name_label)
	line.add_child(tag)
	return {"line": line, "name": name_label, "tag": tag}


func _write(row: Dictionary, member: Dictionary) -> void:
	var downed: bool = member["downed"]
	var name_label: Label = row["name"]
	var tag: Label = row["tag"]
	HudStyle.set_text(name_label, str(member["name"]).to_upper())
	name_label.add_theme_color_override(
		&"font_color", tokens.ink_disabled if downed else tokens.ink
	)
	HudStyle.set_text(tag, "DOWN" if downed else "UP")
	tag.add_theme_color_override(&"font_color", tokens.danger if downed else tokens.accent_bright)
