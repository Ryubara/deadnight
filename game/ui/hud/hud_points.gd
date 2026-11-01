class_name HudPoints
extends HudPart
## Your points as a big amber numeral under your name. The gains are listed beside the crosshair
## (`HudGains`), where the eye already is.

var number_text: String:
	get:
		return _number.text

var _caption := HudStyle.label(
	"POINTS", HudStyle.SMALL, tokens.accent, false, HudStyle.TRACK_CAPTION
)
var _number := HudStyle.label("0", HudStyle.POINTS, tokens.accent_bright, true)
var _box := VBoxContainer.new()


func _init() -> void:
	super()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override(&"separation", 0)
	_box.add_child(_caption)
	_box.add_child(_number)
	add_child(_box)
	_box.minimum_size_changed.connect(update_minimum_size)


func _get_minimum_size() -> Vector2:
	return _box.get_combined_minimum_size()


func refresh() -> void:
	var who := state.local_name().to_upper()
	HudStyle.set_text(_caption, "%s  POINTS" % who if who != "" else "POINTS")
	HudStyle.set_text(_number, str(state.points))
