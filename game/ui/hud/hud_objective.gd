class_name HudObjective
extends HudTicket
## A small card under the round: the area you are in (small caps) and what to do next, two lines
## at most. Its text starts where the round card's does.

const WIDTH := HudStyle.COLUMN

var area_text: String:
	get:
		return _area.text
var objective_text: String:
	get:
		return _objective.text

var _area := HudStyle.label("", HudStyle.SMALL, tokens.accent, false, HudStyle.TRACK_CAPTION)
var _objective := HudStyle.label("", HudStyle.TEXT, tokens.ink)


func _init() -> void:
	super()
	(_objective as HudLabel).wrap_words(TextServer.AUTOWRAP_WORD_SMART)
	_objective.custom_minimum_size.x = WIDTH - float(HudStyle.PAD + HudStyle.PAD_LEFT)
	_objective.max_lines_visible = 2
	_objective.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	body.add_child(_area)
	body.add_child(_objective)
	visible = false


## The height the card takes with its area and two lines of words, the most it ever takes: what a
## column under it keeps clear (`Hud`), so the column does not move when the words change.
func max_height() -> float:
	var lines := _objective.max_lines_visible
	return (
		float(HudStyle.PAD * 2)
		+ _area.get_line_height()
		+ float(lines * _objective.get_line_height())
		+ float((lines - 1) * _objective.get_theme_constant(&"line_spacing"))
	)


func topics() -> Array[StringName]:
	return [HudState.OBJECTIVE]


func refresh() -> void:
	HudStyle.set_text(_area, state.area_name.to_upper())
	HudStyle.set_text(_objective, state.objective)
	_area.visible = state.area_name != ""
	_objective.visible = state.objective != ""
	visible = _area.visible or _objective.visible
