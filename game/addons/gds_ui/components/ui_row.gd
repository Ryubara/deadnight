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
var _text_column: VBoxContainer
var _slot: HBoxContainer


func _init() -> void:
	var text := VBoxContainer.new()
	_text_column = text
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_constant_override(&"separation", 0)
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
	_value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_value_label)
	_apply_tokens()


func _ready() -> void:
	if not Engine.is_editor_hint():
		UITokens.active_changed().connect(_on_tokens_changed)


## Reads the active tokens into the row's spacing and column widths.
func _apply_tokens() -> void:
	_tokens = UITokens.active()
	add_theme_constant_override(&"separation", _tokens.space_lg)
	_text_column.custom_minimum_size.x = _tokens.control_width * 0.5
	_value_label.custom_minimum_size.x = _tokens.control_height * 1.5
	if _slot != null:
		_slot.custom_minimum_size.x = _tokens.control_width


func _on_tokens_changed(_next: UITokens) -> void:
	_apply_tokens()


## Puts `node` in the control column, `UITokens.control_width` wide. A switch keeps its own width.
func set_control(node: Control) -> void:
	control = node
	var slot := HBoxContainer.new()
	_slot = slot
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
