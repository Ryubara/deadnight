class_name ControlsSheet
extends UIScreen
## The form controls in every state, side by side: check box, text field, item list and scroll
## area. The picture the pull request's captures are taken from; hover and focus are pinned with
## `preview_state`, the rest are real states.

const CHECK_STATES := ["Off", "On", "Hover", "Focus", "Disabled", "Disabled on"]
const LIST_ITEMS := [
	"Drive-in lot", "Concession stand", "Projector booth", "Back row", "Ticket gate"
]
const LONG_LIST_ITEMS := 14
const SCROLL_LINES := 24

var check_boxes: Array[UICheckBox] = []
var fields: Array[UILineEdit] = []
var lists: Array[UIItemList] = []
var scroll: UIScroll


func _ready() -> void:
	super._ready()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, _tokens.space_xl)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", _tokens.space_md)
	margin.add_child(root)
	root.add_child(_label("Form controls", UILabel.Style.TITLE))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", _tokens.space_xl)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)
	columns.add_child(_left_column())
	columns.add_child(_right_column())


func _left_column() -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", _tokens.space_sm)
	column.add_child(_label("CHECK BOX", UILabel.Style.OVERLINE))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", _tokens.space_lg)
	for index in CHECK_STATES.size():
		var box := UICheckBox.new()
		box.text = CHECK_STATES[index]
		box.custom_minimum_size.x = 300.0
		box.button_pressed = index in [1, 2, 3, 5]
		box.disabled = index >= 4
		box.preview_state = (
			UICheckBox.Preview.HOVER
			if index == 2
			else UICheckBox.Preview.FOCUS if index == 3 else UICheckBox.Preview.NONE
		)
		check_boxes.append(box)
		grid.add_child(box)
	column.add_child(grid)
	column.add_child(_label("TEXT FIELD", UILabel.Style.OVERLINE))
	var specs := [
		["", "Your name", UILineEdit.Preview.NONE, true],
		["Ruby Calloway", "", UILineEdit.Preview.NONE, true],
		["Hovered", "", UILineEdit.Preview.HOVER, true],
		["Keyboard focus", "", UILineEdit.Preview.FOCUS, true],
		["Read only", "", UILineEdit.Preview.NONE, false],
	]
	for spec in specs:
		var field := UILineEdit.new()
		field.text = spec[0]
		field.placeholder_text = spec[1]
		field.preview_state = spec[2]
		field.editable = spec[3]
		fields.append(field)
		column.add_child(field)
	return column


func _right_column() -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", _tokens.space_sm)
	column.add_child(_label("ITEM LIST", UILabel.Style.OVERLINE))
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", _tokens.space_lg)
	column.add_child(row)
	var short := UIItemList.new()
	short.items = PackedStringArray(LIST_ITEMS)
	short.visible_rows = 0
	short.selected = 1
	short.preview_state = UIItemList.Preview.HOVER
	short.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lists.append(short)
	row.add_child(short)
	var long_items := PackedStringArray()
	for index in LONG_LIST_ITEMS:
		long_items.append("Showing %d" % (index + 1))
	var long := UIItemList.new()
	long.items = long_items
	long.visible_rows = 5
	long.selected = 8
	long.preview_state = UIItemList.Preview.FOCUS
	long.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lists.append(long)
	row.add_child(long)
	column.add_child(_label("SCROLL AREA", UILabel.Style.OVERLINE))
	var panel := UIPanel.new()
	panel.variant = UIPanel.Variant.FLAT
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(panel)
	scroll = UIScroll.new()
	scroll.keyboard_scroll = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	var lines := VBoxContainer.new()
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(lines)
	for index in SCROLL_LINES:
		lines.add_child(_label("Reel %d - the late show" % (index + 1), UILabel.Style.CAPTION))
	return column


func _label(text: String, style: UILabel.Style) -> UILabel:
	var label := UILabel.new()
	label.text = text
	label.style = style
	return label
