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
		_hint_label.visible = value != "" and _stack == null

var control: Control

## The widths a tight column asks for instead of the tokens' (`set_widths`); 0 keeps the tokens'.
var _title_width := 0.0
var _control_width := 0.0
## The title above the control instead of beside it (`set_stacked`): the column that holds them.
var _stack: VBoxContainer
## The gaps between the title, the control and the value are `space_md` instead of `space_lg`.
var _tight := false

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
	add_theme_constant_override(&"separation", _tokens.space_md if _tight else _tokens.space_lg)
	_text_column.custom_minimum_size.x = (
		0.0
		if _stack != null
		else (_title_width if _title_width > 0.0 else _tokens.control_width * 0.5)
	)
	_value_label.custom_minimum_size.x = _tokens.control_height * 1.5
	if _slot != null:
		_slot.custom_minimum_size.x = (
			_control_width if _control_width > 0.0 else _tokens.control_width
		)


func _on_tokens_changed(_next: UITokens) -> void:
	_apply_tokens()


## Puts `node` in the control column, `UITokens.control_width` wide. A switch keeps its own width.
func set_control(node: Control) -> void:
	control = node
	var slot := HBoxContainer.new()
	_slot = slot
	slot.custom_minimum_size.x = _control_width if _control_width > 0.0 else _tokens.control_width
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	node.size_flags_horizontal = (
		Control.SIZE_SHRINK_BEGIN if node is UIToggle else Control.SIZE_EXPAND_FILL
	)
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.add_child(node)
	if _stack != null:
		_stack.add_child(slot)
	else:
		add_child(slot)
		move_child(slot, 1)


## The whole title, never cut to "Break between ro...": the title's column grows to its text. For a
## row whose card has the room (a phone's form), where the tokens' column is narrower than a title.
func show_whole_title(on: bool) -> void:
	_title_label.text_overrun_behavior = (
		TextServer.OVERRUN_NO_TRIMMING if on else TextServer.OVERRUN_TRIM_ELLIPSIS
	)


## The gaps between the title, the control and the value one step smaller (`space_md`, 16 units
## for 24), which gives a card that has no room to spare its 16 units back on every gap of a row.
func set_tight(on: bool) -> void:
	_tight = on
	_apply_tokens()


## Whether the title is cut short ("Break between ro...") as the row is laid out now.
func title_cut() -> bool:
	var font := _title_label.get_theme_font(&"font")
	var font_size := _title_label.get_theme_font_size(&"font_size")
	var wanted := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	return wanted > _title_label.size.x + 0.5


## Whether the hint is cut short ("How faint the buttons are when your thumb i...") as the row is
## laid out now. A row with no hint, or one that is not shown, is not cut.
func hint_cut() -> bool:
	if not _hint_label.visible or hint == "":
		return false
	var font := _hint_label.get_theme_font(&"font")
	var font_size := _hint_label.get_theme_font_size(&"font_size")
	var wanted := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	return wanted > _hint_label.size.x + 0.5


## A row for a column narrower than the tokens' form: the title's and the control's least widths,
## and no value column (a row with no number beside it), so a card that cannot be wider than its
## area still holds the row (#980).
func set_widths(title_width: float, control_width: float, with_value_column := false) -> void:
	_title_width = title_width
	_control_width = control_width
	_value_label.visible = with_value_column
	_apply_tokens()


## The title above the control, so the row needs only the control's width: for a column too narrow
## to hold both side by side. The hint goes (it would only add height).
func set_stacked(on: bool) -> void:
	if (_stack != null) == on:
		return
	if on:
		_stack = VBoxContainer.new()
		_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_stack.add_theme_constant_override(&"separation", 0)
		add_child(_stack)
		move_child(_stack, 0)
		_text_column.reparent(_stack, false)
		if _slot != null:
			_slot.reparent(_stack, false)
	else:
		_text_column.reparent(self, false)
		move_child(_text_column, 0)
		if _slot != null:
			_slot.reparent(self, false)
			move_child(_slot, 1)
		_stack.queue_free()
		_stack = null
	_hint_label.visible = hint != "" and _stack == null
	_apply_tokens()


## Shows a value beside the control (a slider's number). The column is reserved on every row, so
## all the controls line up.
func set_value_text(text: String) -> void:
	_value_label.text = text
