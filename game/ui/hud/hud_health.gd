class_name HudHealth
extends HudPart
## Health as a bar of ticks under its number. Down, the bar is replaced by a red DOWN tag and what
## to hope for; the bar turns hot orange under a third. Beneath it, one row for the equipment (cut
## with an ellipsis when long) and the grenade count.

const BAR_SIZE := Vector2(420.0, 30.0)
const TICKS := 10
const TICK_GAP := 6.0
const LOW_FRACTION := 0.33
## Room kept between a trimmed name and its count, for the join the shaping adds.
const JOIN_SLACK := 6.0

var shown_downed := false
var equipment_text: String:
	get:
		return _equipment.text
var grenade_text: String:
	get:
		return _grenades.text
var down_text: String:
	get:
		return _down.text

var _label := HudStyle.label("HEALTH", HudStyle.SMALL, tokens.accent, false, HudStyle.TRACK_CAPTION)
var _bar := Control.new()
var _down := HudStyle.label("DOWN", HudStyle.MEDIUM, tokens.danger, true)
var _hint := HudStyle.label("HOLD ON FOR A REVIVE", HudStyle.SMALL, tokens.ink_muted)
var _equipment := HudStyle.clip(
	HudStyle.label("", HudStyle.SMALL, tokens.ink, false, HudStyle.TRACK_CAPTION)
)
var _grenades := HudStyle.label("", HudStyle.SMALL, tokens.ink, false, HudStyle.TRACK_CAPTION)
var _gear := HBoxContainer.new()
var _box := VBoxContainer.new()


func _init() -> void:
	super()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override(&"separation", tokens.space_xs)
	_box.custom_minimum_size.x = BAR_SIZE.x
	_box.add_child(_label)
	_bar.custom_minimum_size = BAR_SIZE
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	_box.add_child(_bar)
	_box.add_child(_down)
	_box.add_child(_hint)
	_gear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gear.add_theme_constant_override(&"separation", tokens.space_md)
	_equipment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gear.add_child(_equipment)
	_gear.add_child(_grenades)
	_box.add_child(_gear)
	add_child(_box)
	_box.minimum_size_changed.connect(update_minimum_size)


func _get_minimum_size() -> Vector2:
	return _box.get_combined_minimum_size()


func topics() -> Array[StringName]:
	return [HudState.HEALTH, HudState.TEAM]


func refresh() -> void:
	shown_downed = state.is_local_downed()
	_label.visible = not shown_downed
	_bar.visible = not shown_downed
	_down.visible = shown_downed
	_hint.visible = shown_downed
	HudStyle.set_text(_label, "HEALTH  %d" % ceili(state.health))
	HudStyle.set_text(_grenades, "GRENADES  x%d" % state.grenades)
	HudStyle.set_text(_equipment, _gear_text())
	_grenades.add_theme_color_override(
		&"font_color", tokens.ink if state.grenades > 0 else tokens.ink_disabled
	)
	_gear.visible = not shown_downed
	_bar.queue_redraw()


## The equipment and its count, the name cut to the room the grenade count leaves (the count stays).
## The whole text is measured, not its two halves: shaping the pair is a little wider than the
## parts added up, and the count must not be the part that is cut.
func _gear_text() -> String:
	if state.equipment_name == "":
		return ""
	var font := _equipment.get_theme_font(&"font")
	var count := "" if state.equipment_count < 0 else " x%d" % state.equipment_count
	var title := state.equipment_name.to_upper()
	var room := (
		BAR_SIZE.x
		- float(tokens.space_md)
		- HudStyle.text_width(font, _grenades.text, HudStyle.SMALL)
	)
	if HudStyle.text_width(font, title + count, HudStyle.SMALL) <= room:
		return title + count
	var name_room := room - HudStyle.text_width(font, count, HudStyle.SMALL) - JOIN_SLACK
	return HudStyle.trimmed(font, title, HudStyle.SMALL, name_room) + count


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
