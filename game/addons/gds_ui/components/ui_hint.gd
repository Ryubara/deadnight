@tool
class_name UIHint
extends HBoxContainer
## A button prompt with its words: the glyph for an action by the device in use, and what it does
## ("Select", "Back"). A row of these is the key-hint line at the foot of a screen. It hides while
## a finger is the last input: a keycap on a phone points at nothing.

@export var action := &"":
	set(value):
		action = value
		_glyph.action = value
@export var text := "":
	set(value):
		text = value
		_label.text = value

var glyph: UIGlyph
var _glyph: UIGlyph
var _label: UILabel


func _init() -> void:
	add_theme_constant_override(&"separation", UITokens.active().space_sm)
	alignment = BoxContainer.ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glyph = UIGlyph.new()
	glyph = _glyph
	add_child(_glyph)
	_label = UILabel.new()
	_label.style = UILabel.Style.CAPTION
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	UIInputMode.changed().connect(_follow_touch)
	_follow_touch()


func _follow_touch() -> void:
	visible = not UIInputMode.touch
