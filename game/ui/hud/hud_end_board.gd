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
## How much of the screen's height the dark at the top and at the bottom takes, and how dark it
## is at its edge: the title and the clock read over any picture.
const SCRIM_SHARE := 0.3
const SCRIM_ALPHA := 0.6
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
## The level each row shows (0 for none), in row order.
var row_levels: Array[int] = []
## The way out: Leave online, Back alone.
var leave_button: UIButton
## The night report: the local player's XP lines and level bar, on a ticket under the round
## (`show_report`); hidden until a report is given.
var report_card := HudNightReport.new()
## The film credits: a crew title for every player, under the players' ticket (`show_credits`);
## hidden until given.
var credits_card := HudCredits.new()

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
var _report := {}
var _crew := {}
var _right := VBoxContainer.new()


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
	_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_right.add_theme_constant_override(&"separation", HudStyle.MD)
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.add_theme_constant_override(&"separation", HudStyle.XS)
	_ticket.body.add_child(_grid)
	_right.add_child(_ticket)
	_right.add_child(credits_card)
	across.add_child(_right)
	resized.connect(_rebuild_later)


func _draw() -> void:
	var dark := Color(0.0, 0.0, 0.0, SCRIM_ALPHA)
	var clear := Color(0.0, 0.0, 0.0, 0.0)
	var band := size.y * SCRIM_SHARE
	var top := PackedVector2Array(
		[Vector2(0.0, 0.0), Vector2(size.x, 0.0), Vector2(size.x, band), Vector2(0.0, band)]
	)
	draw_polygon(top, PackedColorArray([dark, dark, clear, clear]))
	var bottom := PackedVector2Array(
		[
			Vector2(0.0, size.y - band),
			Vector2(size.x, size.y - band),
			Vector2(size.x, size.y),
			Vector2(0.0, size.y)
		]
	)
	draw_polygon(bottom, PackedColorArray([clear, clear, dark, dark]))


func _build_left() -> Control:
	var left := VBoxContainer.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override(&"separation", HudStyle.SM)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_title)
	_round_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_round_label)
	_title.minimum_size_changed.connect(_fit_report)
	report_card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(report_card)
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
		# What the board draws is what this viewer's setting allows (and no level for a bot).
		var shown := state.level_of(state.team[id])
		_members[id]["level"] = shown.x
		_members[id]["icon"] = shown.y
		var plate := state.plate_of(state.team[id])
		_members[id]["card"] = plate["card"]
		_members[id]["emblem"] = plate["emblem"]
	_round = state.round_number
	_clock = state.night_clock
	title_text = TITLE
	round_text = "ROUND %d REACHED  ·  %s" % [_round, HudScoreboard.format_clock(_clock)]
	HudStyle.set_text(_round_label, round_text)
	_rebuild()


## Shows the night report (`NightReport.compose`) on its ticket; a later call replaces it.
func show_report(model: Dictionary) -> void:
	_report = model
	_fit_report()


## Shows the film credits (`ReportTracker.credits_input`) under the players' ticket; a later call
## replaces them, and the rows of both tickets share the height the screen leaves.
func show_credits(input: Dictionary) -> void:
	_crew = input
	_signature = ""
	_rebuild()


## The height the report's ticket has: what the screen leaves besides the rest of the left column
## (the title wraps on a narrow screen, so it is read as it is laid out).
func report_room() -> float:
	var taken := 0.0
	for part: Control in [_title, _round_label, _caption, _number, leave_button]:
		taken += part.get_combined_minimum_size().y + float(HudStyle.SM)
	var margins := float(HudStyle.margin()) * 2.0 + _insets.y + _insets.w
	return size.y - margins - taken


func _fit_report() -> void:
	if not _report.is_empty():
		report_card.show_report(_report, report_room() if size.y > 0.0 else INF)


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
	if _crew.is_empty():
		return clampf(_each(), MIN_ROW_HEIGHT, ROW_HEIGHT)
	# The credits' row is cut first; what it cannot give up (its floor) comes off the players'.
	return clampf(_each() - credits_row_height(), MIN_ROW_HEIGHT, ROW_HEIGHT)


## The height one row of the credits has, from the same room (`row_height`): its share of what each
## player gets, to a floor.
func credits_row_height() -> float:
	if size.y <= 0.0 or _members.is_empty():
		return HudCredits.ROW
	return clampf(_each() * (1.0 - _player_share()), HudCredits.MIN_ROW, HudCredits.ROW)


## What the screen leaves for each player: both tickets' rows when the credits are up.
func _each() -> float:
	var room := size.y - float(HudStyle.margin()) * 2.0 - CHROME_HEIGHT
	if not _crew.is_empty():
		room -= HudCredits.CHROME + float(HudStyle.MD)
	return room / float(_members.size())


## The part of a player's room the players' ticket takes; the credits' row has the rest.
func _player_share() -> float:
	return ROW_HEIGHT / (ROW_HEIGHT + HudCredits.ROW)


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
		_fit_report()


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
	row_levels.clear()
	for id in ids.slice(0, NightHost.MAX_PLAYERS):
		var cells := _cells(id)
		row_ids.append(id)
		row_levels.append(int(_members[id].get("level", 0)))
		rows_text.append(cells)
		_grid.add_child(_player_row(id, cells, height))
	_ticket.update_minimum_size()
	if not _crew.is_empty():
		credits_card.show_credits(_shown_members(ids), _crew, _local_id, credits_row_height())


## The members the board draws (`ids`), for the credits.
func _shown_members(ids: Array[int]) -> Dictionary:
	var shown := {}
	for id in ids.slice(0, NightHost.MAX_PLAYERS):
		shown[id] = _members[id]
	return shown


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
	PlateRow.card_behind(wash, StringName(member.get("card", &"")), height, _tokens.bg)
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
		var shown := Vector2i(int(member.get("level", 0)), int(member.get("icon", 0)))
		var emblem := StringName(member.get("emblem", &""))
		var room := _width(i) - (HudLevelCell.taken(shown, emblem, height) if i == 0 else 0.0)
		var label := HudStyle.clip(HudStyle.label("", HudStyle.MEDIUM, _tokens.ink, i > 0))
		label.custom_minimum_size = Vector2(room, height)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		)
		HudStyle.set_fitted(label, cells[i], HudStyle.MEDIUM, room - float(HudStyle.SM))
		if i == 0:
			row.add_child(HudLevelCell.wrap(label, shown, _tokens.ink, height, emblem))
		else:
			row.add_child(label)
	return wash
