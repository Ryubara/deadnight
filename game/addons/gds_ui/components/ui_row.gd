@tool
class_name UIRow
extends HBoxContainer
## A form row: a title (and optional hint) on the left, a control on the right, and for a slider a
## value read-out beside it. Add the control with `set_control`.

@export var title := "":
	set(value):
		title = value
		_title_label.text = value
@export var hint := "":
	set(value):
		hint = value
		_hint_label.text = value
		_hint_label.visible = value != ""

var control: Control

var _tokens := UITokens.active()
var _title_label := UILabel.new()
var _hint_label := UILabel.new()
var _value_label := UILabel.new()


func _init() -> void:
	add_theme_constant_override(&"separation", _tokens.space_lg)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_constant_override(&"separation", 0)
	text.custom_minimum_size.x = _tokens.control_width * 0.5
	_title_label.style = UILabel.Style.BODY
	_hint_label.style = UILabel.Style.CAPTION
	# Wrapping labels report a tall minimum while a container is still sizing them, which can leave
	# a whole screen stretched after a resize; a long hint is trimmed instead.
	for label in [_title_label, _hint_label]:
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hint_label.hide()
	text.add_child(_title_label)
	text.add_child(_hint_label)
	add_child(text)
	_value_label.style = UILabel.Style.BODY
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_value_label.custom_minimum_size.x = _tokens.control_height * 1.5
	_value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_value_label)


## Puts `node` in the control column, `UITokens.control_width` wide. A switch keeps its own width.
func set_control(node: Control) -> void:
	control = node
	var slot := HBoxContainer.new()
	slot.custom_minimum_size.x = _tokens.control_width
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	node.size_flags_horizontal = (
		Control.SIZE_SHRINK_BEGIN if node is UIToggle else Control.SIZE_EXPAND_FILL
	)
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.add_child(node)
	add_child(slot)
	move_child(slot, 1)


## Shows a value beside the control (a slider's number). The column is reserved on every row, so
## all the controls line up.
func set_value_text(text: String) -> void:
	_value_label.text = text
