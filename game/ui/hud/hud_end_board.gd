class_name HudEndBoard
extends Control
## The end of a night, drawn over the camera's flight (docs/design/end-of-night.md): the title and
## the round reached on the left, a row for every player on a ticket at the right (name, points,
## kills, headshots, downs, revives and the rounds they stood at the end of), and under the title
## the intermission's clock with the way out. It reads a `HudState` for the standing and the whole
## seconds the server says are left; it draws no 3D.
##
## The standing is kept: a row stays when its player leaves the night, with what it last said, so
## the others' board does not change under them. Rows are in order of points, then of seat.

## The player pressed the way out (Leave, or Back alone).
signal leave_pressed

const TITLE := "YOU DID NOT MAKE IT"
## The columns after the name: the key of the player's entry in `HudState.team`, the heading and the
## width.
const COLUMNS: Array[Dictionary] = [
	{"key": "points", "heading": "POINTS", "width": 130.0},
	{"key": "kills", "heading": "KILLS", "width": 96.0},
	{"key": "headshots", "heading": "HEADSHOTS", "width": 124.0},
	{"key": "downs", "heading": "DOWNS", "width": 92.0},
	{"key": "revives", "heading": "REVIVES", "width": 108.0},
	{"key": "rounds", "heading": "ROUNDS", "width": 100.0},
]
const NAME_WIDTH := 230.0
## Size of the armband chip before the name, and the height of a row: the rows shrink to
## `MIN_ROW_HEIGHT` when the screen is short and the night is full.
const CHIP := Vector2(10.0, 34.0)
const ROW_HEIGHT := 46.0
const MIN_ROW_HEIGHT := 28.0
## Height the title, the headings and the ticket's padding take, which the rows do not get.
const CHROME_HEIGHT := 190.0
## A row of the local player is laid on a faint wash of the accent.
const LOCAL_WASH := 0.14

## What the board says, for tests and tools.
var title_text := ""
var round_text := ""
var countdown_text := ""
var headings: Array[String] = []
var rows_text: Array[Array] = []
var row_ids: Array[int] = []
## The way out: Leave online, Back alone.
var leave_button: UIButton

var _tokens := UITokens.active()
## Player id -> what the board last heard of them, kept after they leave.
var _members: Dictionary[int, Dictionary] = {}
var _local_id := 0
var _round := 0
var _clock := 0
var _signature := ""
var _margin := MarginContainer.new()
var _title := HudStyle.label(TITLE, HudStyle.BIG, _tokens.danger, true, 2.0)
var _round_label := HudStyle.label("", HudStyle.MEDIUM, _tokens.hot, true)
var _caption := HudStyle.label("", HudStyle.SMALL, _tokens.ink_muted, false, 2.0)
var _number := HudStyle.label("", HudStyle.NUMERAL, _tokens.accent, true)
var _ticket := HudTicket.new()
var _grid := VBoxContainer.new()
var _insets := Vector4.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_margin)
	_set_margins()
	var across := HBoxContainer.new()
	across.mouse_filter = Control.MOUSE_FILTER_IGNORE
	across.add_theme_constant_override(&"separation", HudStyle.LG)
	_margin.add_child(across)
	across.add_child(_build_left())
	_ticket.accent = _tokens.hot
	_ticket.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.add_theme_constant_override(&"separation", HudStyle.XS)
	_ticket.body.add_child(_grid)
	across.add_child(_ticket)
	resized.connect(_rebuild_later)


func _build_left() -> Control:
	var left := VBoxContainer.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override(&"separation", HudStyle.SM)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_title)
	_round_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_round_label)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	left.add_child(_caption)
	left.add_child(_number)
	leave_button = UIButton.new()
	leave_button.variant = UIButton.Variant.PRIMARY
	leave_button.text = "Leave"
	leave_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	leave_button.pressed.connect(func() -> void: leave_pressed.emit())
	left.add_child(leave_button)
	return left


## Shows the board for the night in `state` (the local player's row is marked), with the way out
## named `leave_text` and the clock's words `caption` (what happens when it runs out).
func show_results(state: HudState, caption: String, leave_text: String) -> void:
	_local_id = state.local_player_id
	_caption.text = caption
	leave_button.text = leave_text
	visible = true
	refresh(state)
	leave_button.grab_focus.call_deferred()


## Takes what `state` says now: new numbers replace a player's row, a player who left keeps theirs.
func refresh(state: HudState) -> void:
	for id: int in state.team:
		_members[id] = (state.team[id] as Dictionary).duplicate()
	_round = state.round_number
	_clock = state.night_clock
	title_text = TITLE
	round_text = "ROUND %d REACHED  ·  %s" % [_round, HudScoreboard.format_clock(_clock)]
	HudStyle.set_text(_round_label, round_text)
	_rebuild()


## The seconds the server says are left; the board counts the end by them. Negative (the clock has
## not come yet) shows nothing.
func set_left(seconds: int) -> void:
	countdown_text = "" if seconds < 0 else str(seconds)
	HudStyle.set_text(_number, countdown_text)


## The clock gives way to a line while the way out is found (the lobby opening).
func set_waiting(text: String) -> void:
	countdown_text = text
	HudStyle.set_text(_number, "")
	_caption.text = text


## The platform's safe area (left, top, right, bottom, canvas units) the board keeps inside.
func set_safe_insets(insets: Vector4) -> void:
	_insets = insets
	_set_margins()


## The players in the order they are drawn: most points first, then by seat.
func order() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_members.keys())
	ids.sort_custom(
		func(a: int, b: int) -> bool:
			var pa := int(_members[a]["points"])
			var pb := int(_members[b]["points"])
			return a < b if pa == pb else pa > pb
	)
	return ids


## The height one row has: all of `ROW_HEIGHT` when the screen is tall enough for the full night,
## less (to `MIN_ROW_HEIGHT`) when it is not.
func row_height() -> float:
	if size.y <= 0.0 or _members.is_empty():
		return ROW_HEIGHT
	var room := size.y - float(HudStyle.margin()) * 2.0 - CHROME_HEIGHT
	return clampf(room / float(_members.size()), MIN_ROW_HEIGHT, ROW_HEIGHT)


func _set_margins() -> void:
	var margin := HudStyle.margin()
	_margin.add_theme_constant_override(&"margin_left", margin + int(_insets.x))
	_margin.add_theme_constant_override(&"margin_top", margin + int(_insets.y))
	_margin.add_theme_constant_override(&"margin_right", margin + int(_insets.z))
	_margin.add_theme_constant_override(&"margin_bottom", margin + int(_insets.w))


func _rebuild_later() -> void:
	_signature = ""
	if visible:
		_rebuild.call_deferred()


func _rebuild() -> void:
	var ids := order()
	var height := row_height()
	var signature := "%s|%s" % [height, JSON.stringify([ids, _members.values()])]
	if signature == _signature:
		return
	_signature = signature
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	headings = ["PLAYER"]
	for column in COLUMNS:
		headings.append(column["heading"])
	_grid.add_child(_heading_row())
	rows_text.clear()
	row_ids.clear()
	for id in ids.slice(0, NightHost.MAX_PLAYERS):
		var cells := _cells(id)
		row_ids.append(id)
		rows_text.append(cells)
		_grid.add_child(_player_row(id, cells, height))
	_ticket.update_minimum_size()


func _cells(id: int) -> Array[String]:
	var member: Dictionary = _members[id]
	var cells: Array[String] = [HudState.name_of(member)]
	for column in COLUMNS:
		cells.append(str(member.get(column["key"], 0)))
	return cells


func _heading_row() -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 0)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.custom_minimum_size.x = CHIP.x + float(HudStyle.MD)
	row.add_child(spacer)
	for i in headings.size():
		var label := HudStyle.clip(
			HudStyle.label(headings[i], HudStyle.SMALL, _tokens.ink_muted, false, 1.0)
		)
		label.custom_minimum_size.x = _width(i)
		label.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		)
		row.add_child(label)
	return row


func _width(cell: int) -> float:
	return NAME_WIDTH if cell == 0 else float(COLUMNS[cell - 1]["width"])


func _player_row(id: int, cells: Array[String], height: float) -> Control:
	var member: Dictionary = _members[id]
	var wash := PanelContainer.new()
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(_tokens.accent, LOCAL_WASH) if id == _local_id else Color.TRANSPARENT
	wash.add_theme_stylebox_override(&"panel", box)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 0)
	row.custom_minimum_size.y = height
	wash.add_child(row)
	var chip_slot := CenterContainer.new()
	chip_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip_slot.custom_minimum_size.x = CHIP.x + float(HudStyle.MD)
	var chip := ColorRect.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.color = LookCatalog.armband_colour(int(member.get("seat", 0)))
	chip.custom_minimum_size = Vector2(CHIP.x, minf(CHIP.y, height - 8.0))
	chip_slot.add_child(chip)
	row.add_child(chip_slot)
	for i in cells.size():
		var label := HudStyle.clip(HudStyle.label("", HudStyle.MEDIUM, _tokens.ink, i > 0))
		label.custom_minimum_size = Vector2(_width(i), height)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		)
		HudStyle.set_fitted(label, cells[i], HudStyle.MEDIUM, _width(i) - float(HudStyle.SM))
		row.add_child(label)
	return wash
