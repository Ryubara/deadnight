class_name HudPoints
extends HudPart
## Your points as a big amber numeral under your name. The gains are listed beside the crosshair
## (`HudGains`), where the eye already is. It never grows past the column: a long name is cut with
## an ellipsis (the word POINTS stays) and a big number gets a smaller type.

const WIDTH := HudStyle.COLUMN
## The numeral shrinks to this before it is cut.
const SMALLEST_NUMERAL := HudStyle.MEDIUM
const SUFFIX := "  POINTS"

var number_text: String:
	get:
		return _number.text
var caption_text: String:
	get:
		return _caption.text

var _caption := HudStyle.clip(
	HudStyle.label("POINTS", HudStyle.SMALL, tokens.accent, false, HudStyle.TRACK_CAPTION)
)
var _number := HudStyle.clip(HudStyle.label("0", HudStyle.POINTS, tokens.accent_bright, true))
var _box := VBoxContainer.new()


func _init() -> void:
	super()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override(&"separation", 0)
	_box.custom_minimum_size.x = WIDTH
	_box.add_child(_caption)
	_box.add_child(_number)
	add_child(_box)
	_box.minimum_size_changed.connect(update_minimum_size)


func _get_minimum_size() -> Vector2:
	return _box.get_combined_minimum_size()


func topics() -> Array[StringName]:
	return [HudState.POINTS, HudState.TEAM]


func refresh() -> void:
	var who := state.local_name().to_upper()
	var caption := "POINTS"
	if who != "":
		var font := _caption.get_theme_font(&"font")
		var room := WIDTH - HudStyle.text_width(font, SUFFIX, HudStyle.SMALL)
		caption = HudStyle.trimmed(font, who, HudStyle.SMALL, room) + SUFFIX
	HudStyle.set_text(_caption, caption)
	HudStyle.set_fitted(_number, str(state.points), HudStyle.POINTS, WIDTH, SMALLEST_NUMERAL)
