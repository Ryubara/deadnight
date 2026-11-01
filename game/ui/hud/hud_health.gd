class_name HudHealth
extends HudPart
## Health as a bar of ticks under its number. Down, the bar is replaced by a red DOWN tag and what
## to hope for; the bar turns hot orange under a third.

const BAR_SIZE := Vector2(420.0, 30.0)
const TICKS := 10
const TICK_GAP := 6.0
const LOW_FRACTION := 0.33

var shown_downed := false
var equipment_text: String:
	get:
		return _equipment.text
var down_text: String:
	get:
		return _down.text

var _label := HudStyle.label("HEALTH", HudStyle.SMALL, tokens.accent, false, HudStyle.TRACK_CAPTION)
var _bar := Control.new()
var _down := HudStyle.label("DOWN", HudStyle.MEDIUM, tokens.danger, true)
var _hint := HudStyle.label("HOLD ON FOR A REVIVE", HudStyle.SMALL, tokens.ink_muted)
var _equipment := HudStyle.label("", HudStyle.SMALL, tokens.ink, false, HudStyle.TRACK_CAPTION)
var _box := VBoxContainer.new()


func _init() -> void:
	super()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override(&"separation", tokens.space_xs)
	_box.add_child(_label)
	_bar.custom_minimum_size = BAR_SIZE
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	_box.add_child(_bar)
	_box.add_child(_down)
	_box.add_child(_hint)
	_box.add_child(_equipment)
	add_child(_box)
	_box.minimum_size_changed.connect(update_minimum_size)


func _get_minimum_size() -> Vector2:
	return _box.get_combined_minimum_size()


func refresh() -> void:
	shown_downed = state.is_local_downed()
	_label.visible = not shown_downed
	_bar.visible = not shown_downed
	_down.visible = shown_downed
	_hint.visible = shown_downed
	HudStyle.set_text(_label, "HEALTH  %d" % ceili(state.health))
	var gear := ""
	if state.equipment_name != "":
		gear = "%s  x%d" % [state.equipment_name.to_upper(), state.equipment_count]
	HudStyle.set_text(_equipment, gear)
	_equipment.visible = gear != "" and not shown_downed
	_bar.queue_redraw()


func fraction() -> float:
	return state.health / state.max_health if state.max_health > 0.0 else 0.0


func _draw_bar() -> void:
	var colour := tokens.hot if fraction() <= LOW_FRACTION else tokens.accent_bright
	var tick := (BAR_SIZE.x + TICK_GAP) / TICKS
	for i in TICKS:
		var filled := clampf(fraction() * TICKS - i, 0.0, 1.0)
		var rect := Rect2(Vector2(i * tick, 0.0), Vector2(tick - TICK_GAP, BAR_SIZE.y))
		_bar.draw_rect(rect, tokens.outline)
		if filled > 0.0:
			_bar.draw_rect(Rect2(rect.position, Vector2(rect.size.x * filled, rect.size.y)), colour)
