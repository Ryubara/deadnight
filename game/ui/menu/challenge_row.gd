class_name ChallengeRow
extends Button
## One challenge as the menu shows it: the words, how far it is as a count and a punch card, and a
## line of tags. On the sheet of the Challenges tab it is a ruled line of the program; as a `stub`
## (the Play tab) it is a ticket of its own. It is focusable so a pad can walk a long list and the
## list follows, and it only reads: a row is built from one entry of the challenge board
## (`dailies()`, `orders()` or `milestones()`), never from the tracker.
##
## The text and the count share one line in a container: the text takes what is left and is cut
## with an ellipsis, the count takes what it needs, so a long goal never runs off the paper.

const PAD := 18.0
const NOTCH := 8.0

var entry: Dictionary = {}

var _title: Label
var _count: Label
var _punches: MenuLook.Punches
var _tags: Label
var _stub := false


## A row for `data`, `width` units wide. `with_tags` adds the line of tags, `stub` makes it a
## ticket.
static func make(data: Dictionary, width: float, with_tags := true, stub := false) -> ChallengeRow:
	var row := ChallengeRow.new()
	row.entry = data
	row._stub = stub
	var tall := 98.0 if with_tags else 84.0
	row.custom_minimum_size = Vector2(width, tall)
	row._build(with_tags)
	return row


## How far it is, as the board says: a count over a target.
static func counts(data: Dictionary) -> Array[int]:
	if data.has("rungs"):
		return [int(data.get("value", 0)), int(data.get("target", 0))]
	return [int(data.get("progress", 0)), int(data.get("target", 1))]


## The tags a row carries, in words.
static func tags_of(data: Dictionary) -> PackedStringArray:
	var tags := PackedStringArray()
	if data.get("done", false):
		tags.append("Done")
	if data.has("rungs"):
		var step := mini(int(data["rung"]) + 1, int(data["rungs"]))
		tags.append("Step %d of %d" % [step, int(data["rungs"])])
	if data.has("tier"):
		tags.append(String(data["tier"]).capitalize())
	if data.has("slot"):
		tags.append("Press to swap")
	return tags


func _init() -> void:
	UiSounds.wire(self)
	flat = true
	focus_mode = Control.FOCUS_ALL
	# Inside a scroll area a drag that starts here reaches it (`UIScroll`); anywhere else the button
	# stops the pointer, as a button does.
	UIScroll.pass_touch_in_scroll(self)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(queue_redraw)


## A challenge on the sheet only reads; an order can be swapped, which is a select (the menu's
## sounds).
func ui_sound_role() -> StringName:
	return &"sheet_row_swap" if entry.has("slot") else &"sheet_row"


func _build(with_tags: bool) -> void:
	var have_need := counts(entry)
	accessibility_name = String(entry.get("text", ""))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = PAD + (8.0 if _stub else 0.0)
	column.offset_right = -(PAD + (8.0 if _stub else 0.0))
	column.offset_top = 8.0
	column.offset_bottom = -10.0
	column.add_theme_constant_override(&"separation", 2)
	add_child(column)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override(&"separation", 16)
	column.add_child(line)
	var done: bool = entry.get("done", false)
	_title = MenuLook.label(
		String(entry.get("text", "")),
		MenuLook.SIZE_BODY,
		MenuLook.PAPER_MUTED if done else MenuLook.PAPER_INK
	)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(_title)
	_count = MenuLook.label(
		MenuNav.fraction_text(have_need[0], have_need[1]),
		MenuLook.SIZE_NUMBER,
		MenuLook.RED if done else MenuLook.PAPER_INK,
		&"display",
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	line.add_child(_count)
	var low := HBoxContainer.new()
	low.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(low)
	if with_tags:
		_tags = MenuLook.label(" - ".join(tags_of(entry)).to_upper(), 18, MenuLook.RED, &"wide")
		_tags.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tags.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		low.add_child(_tags)
	else:
		var gap := Control.new()
		gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		low.add_child(gap)
	_punches = MenuLook.punches(have_need[0], have_need[1])
	low.add_child(_punches)


## The words on the row.
func text() -> String:
	return _title.text


## The count on the row ("3/5").
func count_text() -> String:
	return _count.text


## The count's control, to check it lies inside the row.
func count_label() -> Label:
	return _count


## How many holes of the card are punched.
func punched() -> int:
	return _punches.have


func _on_hover() -> void:
	grab_focus()
	queue_redraw()


func _draw() -> void:
	if _stub:
		MenuLook.draw_ticket(self, size, MenuLook.PAPER, MenuLook.PAPER_SHADE, NOTCH)
	else:
		draw_rect(Rect2(0.0, size.y - 1.0, size.x, 1.0), MenuLook.PAPER_RULE)
	if has_focus() or is_hovered():
		if _stub:
			draw_rect(Rect2(Vector2.ZERO, size), MenuLook.AMBER, false, 3.0)
		else:
			draw_rect(Rect2(Vector2.ZERO, size), Color(MenuLook.RED, 0.10))
			draw_rect(Rect2(0.0, 0.0, 4.0, size.y), MenuLook.RED)
