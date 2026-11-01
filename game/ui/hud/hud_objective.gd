class_name HudObjective
extends HudPart
## Two plain lines under the round: the area you are in (small caps) and what to do next.

## Width of the two lines; a longer objective wraps.
const WIDTH := 300.0

var area_text: String:
	get:
		return _area.text
var objective_text: String:
	get:
		return _objective.text

var _area := HudStyle.label("", HudStyle.SMALL, tokens.accent, false, HudStyle.TRACK_CAPTION)
var _objective := HudStyle.label("", HudStyle.TEXT, tokens.ink)
var _box := VBoxContainer.new()


func _init() -> void:
	super()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override(&"separation", 0)
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.custom_minimum_size.x = WIDTH
	_objective.max_lines_visible = 2
	_objective.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_box.add_child(_area)
	_box.add_child(_objective)
	add_child(_box)
	_box.minimum_size_changed.connect(update_minimum_size)


func _get_minimum_size() -> Vector2:
	return _box.get_combined_minimum_size()


func topics() -> Array[StringName]:
	return [HudState.OBJECTIVE]


func refresh() -> void:
	HudStyle.set_text(_area, state.area_name.to_upper())
	HudStyle.set_text(_objective, state.objective)
	_area.visible = state.area_name != ""
	_objective.visible = state.objective != ""
	visible = _area.visible or _objective.visible
