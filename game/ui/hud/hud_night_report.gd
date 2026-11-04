class_name HudNightReport
extends HudTicket
## The night's XP as a ticket on the end board (docs/design/progression.md#the-night-report-and-
## credits): a line for each thing that paid, the night's total, and the level bar with what the
## next level gives. It draws a `NightReport` model and adds no number of its own. A night nobody
## keeps (no account at all) shows what it would have paid and says nothing was saved, with no bar.
## The rows get less height on a short screen (`show_report`'s `room`), to a floor.

const WIDTH := 440.0
const ROW := 30.0
const MIN_ROW := 24.0
## What the ticket takes besides its lines, the heading and the total (a row each): the rule, the
## level and the bar, what is next, what was unlocked and the padding.
const CHROME := 150.0
## The most items the card names under "unlocked"; the rest is a count.
const UNLOCKED_NAMED := 2
const ICON := 32.0
const VALUE_WIDTH := 120.0

## What the ticket says, for tests and tools: the lines as `[heading, "+12"]`, the heading and
## note, the total, the level row, its progress, what is next and what the night gave.
var lines_text: Array[Array] = []
var heading_text := ""
var note_text := ""
var total_text := ""
var level_text := ""
var progress_text := ""
var next_text := ""
var unlocked_text := ""
var bar_from := 0.0
var bar_to := 0.0
## The height of a line now.
var row_height := ROW

var _tokens := UITokens.active()
var _model := {}
var _signature := ""


func _init() -> void:
	super()
	accent = _tokens.accent
	custom_minimum_size.x = WIDTH
	visible = false


## Shows `model` (`NightReport.compose`), its rows sized to fit `room` canvas units of height.
func show_report(model: Dictionary, room: float = INF) -> void:
	_model = model
	var count := maxi((model["lines"] as Array).size(), 1) + 2
	var height := ROW
	if room < INF:
		height = clampf((room - CHROME) / float(count), MIN_ROW, ROW)
	var signature := "%s|%s" % [height, JSON.stringify(model)]
	if signature == _signature:
		return
	_signature = signature
	row_height = height
	_rebuild()
	visible = true


func _rebuild() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	lines_text.clear()
	note_text = ""
	level_text = ""
	progress_text = ""
	next_text = ""
	unlocked_text = ""
	var kept: bool = _model["kept"]
	heading_text = "YOUR NIGHT" if kept else "YOUR NIGHT, UNSAVED"
	body.add_child(_heading())
	var lines: Array = _model["lines"]
	if lines.is_empty():
		body.add_child(_row("NO XP THIS NIGHT", "", _tokens.ink_muted))
	for line: Dictionary in lines:
		var heading := str(line["label"]).to_upper()
		var value := "%+d" % int(line["xp"])
		lines_text.append([heading, value])
		body.add_child(_row(heading, value, _tokens.ink))
	body.add_child(_rule())
	total_text = "%+d XP" % int(_model["xp"])
	body.add_child(_total())
	if kept:
		_add_level()
	else:
		note_text = "NO ACCOUNT: THIS NIGHT WAS NOT SAVED"
		body.add_child(_note(note_text, _tokens.danger))
	update_minimum_size()


func _heading() -> Control:
	var label := HudStyle.label(heading_text, HudStyle.SMALL, _tokens.ink_muted, false, 2.0)
	label.custom_minimum_size.y = row_height
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return HudStyle.clip(label)


func _row(heading: String, value: String, ink: Color) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 0)
	var left := HudStyle.clip(HudStyle.label(heading, HudStyle.TEXT, ink))
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.custom_minimum_size.y = row_height
	left.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(left)
	var right := HudStyle.clip(HudStyle.label(value, HudStyle.TEXT, ink, true))
	right.custom_minimum_size = Vector2(VALUE_WIDTH, row_height)
	right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(right)
	return row


func _rule() -> Control:
	var rule := ColorRect.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.color = _tokens.ink_muted
	rule.custom_minimum_size.y = 2.0
	return rule


func _total() -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 0)
	var left := HudStyle.clip(HudStyle.label("NIGHT TOTAL", HudStyle.TEXT, _tokens.ink))
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.custom_minimum_size.y = row_height + float(HudStyle.SM)
	left.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(left)
	var right := HudStyle.label(total_text, HudStyle.MEDIUM, _tokens.accent, true)
	right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(right)
	return row


## A line of small type under the bar, on one line (an ellipsis, never a taller card).
func _note(text: String, ink: Color) -> Control:
	var label := HudStyle.clip(HudStyle.label(text, HudStyle.SMALL, ink, false, 1.0))
	label.custom_minimum_size.x = WIDTH - float(HudStyle.PAD_LEFT + HudStyle.PAD)
	return label


## The level row, the bar, what is next and what the night gave.
func _add_level() -> void:
	var from: int = _model["level_from"]
	var to: int = _model["level_to"]
	level_text = "LEVEL %d" % to if from == to else "LEVEL %d TO %d" % [from, to]
	if int(_model["to_leave"]) == 0:
		progress_text = "TOP OF THE LADDER"
	else:
		progress_text = "%d / %d XP" % [_model["in_level"], _model["to_leave"]]
	bar_from = float(_model["fraction_from"])
	bar_to = float(_model["fraction_to"])
	var level := HBoxContainer.new()
	level.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level.add_theme_constant_override(&"separation", HudStyle.SM)
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = LevelIcons.texture(to)
	icon.texture_filter = LevelIcons.FILTER
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.custom_minimum_size = Vector2(ICON, ICON)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	level.add_child(icon)
	var name_label := HudStyle.label(level_text, HudStyle.TEXT, _tokens.ink, true)
	name_label.custom_minimum_size.y = ICON
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level.add_child(name_label)
	var amount := HudStyle.clip(HudStyle.label(progress_text, HudStyle.SMALL, _tokens.ink_muted))
	amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	level.add_child(amount)
	body.add_child(level)
	var bar := HudXpBar.new()
	bar.from = bar_from
	bar.to = bar_to
	body.add_child(bar)
	var next: Dictionary = _model["next"]
	if not next.is_empty():
		next_text = "NEXT: %s AT %d" % [str(next["label"]).to_upper(), int(next["level"])]
		body.add_child(_note(next_text, _tokens.ink_muted))
	var gave: Array[String] = []
	for row: Dictionary in _model["unlocked"]:
		gave.append(str(row["label"]).to_upper())
	if not gave.is_empty():
		var named := gave.slice(0, UNLOCKED_NAMED)
		unlocked_text = "UNLOCKED: %s" % ", ".join(named)
		if gave.size() > named.size():
			unlocked_text += " +%d MORE" % (gave.size() - named.size())
		body.add_child(_note(unlocked_text, _tokens.accent))
