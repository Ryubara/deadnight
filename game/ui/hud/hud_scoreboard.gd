class_name HudScoreboard
extends HudTicket
## The scoreboard: a ticket over the middle of the night, shown while the player holds the
## `scoreboard` action (Tab, the pad's Back button, the touch button) and gone when they let go.
## Every player in the night is a row: `[armband][name][kills][downs][revives][points][ping]`, with
## the round and the night's clock above. Ping is a column only when some player has one (a night
## over a link; alone there is nothing to measure). The numbers are the server's (`HudState.team`'s
## "kills", "downs", "revives", "ping", the points, and `night_clock`), so every screen shows the
## same ones. REVIVES counts the teammates a player pulled up by hand (`docs/design/revive.md`); a
## player who gets up when a round ends is nobody's revive. Rows are rebuilt when shown and while
## shown, not while hidden: a night's kills would otherwise rebuild a card nobody sees.

## Widths of the columns, canvas units. The name column is the one that gives: a longer name
## shrinks to fit it, then ends in an ellipsis.
const NAME_WIDTH := 300.0
const NUMBER_WIDTH := 124.0
const POINTS_WIDTH := 170.0
const PING_WIDTH := 110.0
## Which cell holds the ping, when there is one (after the name and the four counts).
const PING_CELL := 5
## Size of the armband chip before the name, and of a row's height.
const CHIP := Vector2(10.0, 34.0)
const ROW_HEIGHT := 46.0
## The most players a night holds (the rows kept).
const MAX_ROWS := NightHost.MAX_PLAYERS
## A row of the local player is laid on a faint wash of the accent.
const LOCAL_WASH := 0.14

## What the card says, for tests and tools: the column headings, each player's cells in the order
## they are drawn, and the round and clock lines.
var headings: Array[String] = []
var rows_text: Array[Array] = []
var round_text := ""
var clock_text := ""
## Whether the ping column is drawn.
var has_ping := false
## The player ids in row order.
var row_ids: Array[int] = []

var _t := HudTuning.current()
var _grid := VBoxContainer.new()
var _title_row := HBoxContainer.new()
var _round := HudStyle.label("", HudStyle.MEDIUM, tokens.hot, true)
var _clock := HudStyle.label("", HudStyle.MEDIUM, tokens.accent, true)
var _stale := true


func _init() -> void:
	super()
	accent = tokens.hot
	visible = false
	_round.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_row.add_child(_round)
	_title_row.add_child(_clock)
	body.add_theme_constant_override(&"separation", HudStyle.SM)
	body.add_child(_title_row)
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.add_theme_constant_override(&"separation", HudStyle.XS)
	body.add_child(_grid)


func topics() -> Array[StringName]:
	return [HudState.TEAM, HudState.POINTS, HudState.ROUND, HudState.STATS]


## "12:05", or "1:02:05" once the night has run an hour.
static func format_clock(seconds: int) -> String:
	var total := maxi(seconds, 0)
	if total >= 3600:
		return "%d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]
	return "%d:%02d" % [total / 60, total % 60]


## Which way a ping reads: 0 good, 1 fair, 2 bad.
static func ping_grade(ping_ms: int) -> int:
	if ping_ms <= HudTuning.current().ping_good_ms:
		return 0
	return 1 if ping_ms <= HudTuning.current().ping_fair_ms else 2


## Where the card sits, for the layout test.
func card_rect() -> Rect2:
	return get_global_rect()


func set_shown(shown: bool) -> void:
	if shown == visible:
		return
	visible = shown
	if shown and _stale:
		refresh()


## The player ids in row order: by id, which is the seat, so every screen lists them the same way.
func order() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(state.team.keys())
	ids.sort()
	return ids


func refresh() -> void:
	if not visible:
		_stale = true
		return
	_stale = false
	var ids := order()
	has_ping = ids.any(func(id: int) -> bool: return int(state.team[id]["ping"]) >= 0)
	HudStyle.set_text(_round, "ROUND %02d" % state.round_number)
	HudStyle.set_text(_clock, "TIME %s" % format_clock(state.night_clock))
	round_text = _round.text
	clock_text = _clock.text
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	headings = _headings()
	_grid.add_child(_heading_row())
	rows_text.clear()
	row_ids.clear()
	for id in ids.slice(0, MAX_ROWS):
		var cells := _cells(id)
		row_ids.append(id)
		rows_text.append(cells)
		_grid.add_child(_player_row(id, cells))
	update_minimum_size()


func _headings() -> Array[String]:
	var names: Array[String] = ["PLAYER", "KILLS", "DOWNS", "REVIVES", "POINTS"]
	if has_ping:
		names.append("PING")
	return names


func _cells(player_id: int) -> Array[String]:
	var member: Dictionary = state.team[player_id]
	var cells: Array[String] = [
		HudState.name_of(member) + _state_tag(member),
		str(member["kills"]),
		str(member["downs"]),
		str(member["revives"]),
		str(member["points"]),
	]
	if has_ping:
		var ping := int(member["ping"])
		cells.append("-" if ping < 0 else str(ping))
	return cells


## ` (DOWN)` for a player on the ground, ` (DEAD)` for one who bled out.
func _state_tag(member: Dictionary) -> String:
	if bool(member["dead"]):
		return "  (DEAD)"
	return "  (DOWN)" if bool(member["downed"]) else ""


func _widths() -> Array[float]:
	var widths: Array[float] = [NAME_WIDTH, NUMBER_WIDTH, NUMBER_WIDTH, NUMBER_WIDTH, POINTS_WIDTH]
	if has_ping:
		widths.append(PING_WIDTH)
	return widths


func _heading_row() -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 0)
	var widths := _widths()
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.custom_minimum_size.x = CHIP.x + float(HudStyle.MD)
	row.add_child(spacer)
	for i in headings.size():
		var label := HudStyle.clip(
			HudStyle.label(headings[i], HudStyle.SMALL, tokens.ink_muted, false, 2.0)
		)
		label.custom_minimum_size.x = widths[i]
		label.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		)
		row.add_child(label)
	return row


func _player_row(player_id: int, cells: Array[String]) -> Control:
	var member: Dictionary = state.team[player_id]
	var local := player_id == state.local_player_id
	var downed := bool(member["downed"])
	var seat_colour := LookCatalog.armband_colour(int(member.get("seat", 0)))
	var wash := PanelContainer.new()
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(tokens.accent, LOCAL_WASH) if local else Color.TRANSPARENT
	wash.add_theme_stylebox_override(&"panel", box)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 0)
	row.custom_minimum_size.y = ROW_HEIGHT
	wash.add_child(row)
	var chip_slot := CenterContainer.new()
	chip_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip_slot.custom_minimum_size.x = CHIP.x + float(HudStyle.MD)
	var chip := ColorRect.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.color = seat_colour.darkened(0.55) if downed else seat_colour
	chip.custom_minimum_size = CHIP
	chip_slot.add_child(chip)
	row.add_child(chip_slot)
	var widths := _widths()
	for i in cells.size():
		var ink := tokens.ink
		if i == 0 and downed:
			ink = tokens.danger
		elif i == PING_CELL:
			var grades: Array[Color] = [tokens.ink, tokens.accent, tokens.danger]
			var ping := int(member["ping"])
			ink = tokens.ink_muted if ping < 0 else grades[ping_grade(ping)]
		var label := HudStyle.clip(HudStyle.label("", HudStyle.MEDIUM, ink, i > 0))
		label.custom_minimum_size = Vector2(widths[i], ROW_HEIGHT)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		)
		HudStyle.set_fitted(label, cells[i], HudStyle.MEDIUM, widths[i] - float(HudStyle.SM))
		row.add_child(label)
	return wash
