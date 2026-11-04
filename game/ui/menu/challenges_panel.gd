class_name ChallengesPanel
extends MenuPanel
## The Challenges tab: the dailies with the time to the next refresh, the Concession Orders, and
## the milestones, all read from the challenge board. A family chip narrows the list to one family
## (and shows all of it); "All" shows the first few of each. A swap on an order is free and
## unlimited (progression rule), so it needs no confirmation.

enum Family { ALL, DAILY, ORDER, MILESTONE }

const FAMILY_NAMES := {
	Family.ALL: "All",
	Family.DAILY: "Today",
	Family.ORDER: "Orders",
	Family.MILESTONE: "Milestones",
}
## How many rows of each family "All" shows, and how many a phone's does.
const ALL_SHOWN := {Family.DAILY: 3, Family.ORDER: 3, Family.MILESTONE: 4}
const ALL_SHOWN_COMPACT := {Family.DAILY: 2, Family.ORDER: 2, Family.MILESTONE: 2}

var family := Family.ALL

var _chips := {}
var _list: VBoxContainer
var _scroll: ScrollContainer


func _ready() -> void:
	# The program: one sheet of paper behind everything.
	var sheet := MenuLook.Paper.new()
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(sheet)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in [&"margin_left", &"margin_right", &"margin_top"]:
		margin.add_theme_constant_override(side, 28)
	margin.add_theme_constant_override(&"margin_bottom", 18)
	add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 10)
	margin.add_child(column)
	var kicker := MenuLook.label("The program", MenuLook.SIZE_CAPTION, MenuLook.RED, &"wide")
	column.add_child(kicker)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override(&"separation", 28)
	column.add_child(chips)
	for id: Family in FAMILY_NAMES:
		var chip := FamilyChip.new(FAMILY_NAMES[id])
		chip.pressed.connect(show_family.bind(id))
		chips.add_child(chip)
		_chips[id] = chip
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	# A margin on the right keeps the headings' notes clear of the scroll bar.
	var inset := MarginContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.add_theme_constant_override(&"margin_right", 22)
	_scroll.add_child(inset)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 6)
	inset.add_child(_list)
	refresh()


func side() -> MenuPanel.Side:
	return MenuPanel.Side.LEFT


func width(compact: bool) -> float:
	return 800.0 if compact else 1060.0


## Shows one family, or all.
func show_family(to: Family) -> void:
	family = to
	for id: Family in _chips:
		(_chips[id] as FamilyChip).active = id == to
	refresh()


func chip(id: Family) -> Button:
	return _chips[id]


## The challenge rows on show, in order.
func rows() -> Array[ChallengeRow]:
	var out: Array[ChallengeRow] = []
	for child in _list.get_children():
		if child is ChallengeRow:
			out.append(child)
	return out


func first_focus() -> Control:
	return _chips[family]


func refresh() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for id: Family in _chips:
		(_chips[id] as FamilyChip).active = id == family
	if context.board == null:
		return
	var limits: Dictionary = ALL_SHOWN_COMPACT if context.compact else ALL_SHOWN
	var inner := width(context.compact) - 56.0 - 22.0
	if family in [Family.ALL, Family.DAILY]:
		_list.add_child(
			MenuLook.heading(
				"Today", "Resets in %s" % context.board.refresh_text(), MenuLook.PAPER_MUTED, true
			)
		)
		_add_rows(
			context.board.dailies(),
			limits[Family.DAILY] if family == Family.ALL else 99,
			inner,
			false
		)
	if family in [Family.ALL, Family.ORDER]:
		_list.add_child(
			MenuLook.heading("Concession orders", "Open until done", MenuLook.PAPER_MUTED, true)
		)
		_add_rows(
			context.board.orders(),
			limits[Family.ORDER] if family == Family.ALL else 99,
			inner,
			true
		)
	if family in [Family.ALL, Family.MILESTONE]:
		_list.add_child(MenuLook.heading("Milestones", "Lifetime", MenuLook.PAPER_MUTED, true))
		_add_rows(
			context.board.milestones(),
			limits[Family.MILESTONE] if family == Family.ALL else 99,
			inner,
			false
		)


func _add_rows(entries: Array, limit: int, inner: float, swappable: bool) -> void:
	for index in mini(limit, entries.size()):
		var entry: Dictionary = entries[index]
		var row := ChallengeRow.make(entry, inner, not context.compact)
		_list.add_child(row)
		if swappable:
			row.pressed.connect(_swap.bind(int(entry.get("slot", index))))


func _swap(slot: int) -> void:
	if context.board.swap_order(slot):
		refresh()


## One family chip: its name, an amber rule under it while it is the one on show.
class FamilyChip:
	extends Button
	var active := false:
		set(value):
			active = value
			queue_redraw()
	var label_text := ""

	func _init(text_value: String) -> void:
		UiSounds.wire(self)
		label_text = text_value
		name = text_value
		accessibility_name = text_value
		flat = true
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var measured := MenuLook.wide_font().get_string_size(
			text_value.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, MenuLook.SIZE_CAPTION
		)
		custom_minimum_size = Vector2(measured.x + 8.0, MenuLook.TAP_TARGET)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func ui_sound_role() -> StringName:
		return &"chip"

	func _draw() -> void:
		var lit := active or has_focus() or is_hovered()
		draw_string(
			MenuLook.wide_font(),
			Vector2(4.0, 26.0),
			label_text.to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			MenuLook.SIZE_CAPTION,
			MenuLook.PAPER_INK if lit else MenuLook.PAPER_MUTED
		)
		if active:
			draw_rect(Rect2(4.0, 34.0, size.x - 8.0, 3.0), MenuLook.RED)
