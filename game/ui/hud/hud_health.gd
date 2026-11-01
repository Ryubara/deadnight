class_name HudHealth
extends HudTicket
## Health as a bar of ticks under its number, on a card as wide as the column. Down, the bar is
## replaced by a red DOWN tag and what to hope for; the bar turns hot orange under a third. Beneath
## it, the equipment (the weapon put away last, by name, cut with an ellipsis when long; its rounds
## are not shown, the ammo card says the rounds). The grenade count sits at the right of the label.

const BAR_HEIGHT := 20.0
const TICKS := 10
const TICK_GAP := 4.0
const LOW_FRACTION := 0.33
const WIDTH := HudStyle.COLUMN
## Room kept at the end of the weapon's name.
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

var _label := HudStyle.clip(
	HudStyle.label("HEALTH", HudStyle.SMALL, tokens.accent, false, HudStyle.TRACK_CAPTION)
)
var _bar := Control.new()
var _down := HudStyle.label("DOWN", HudStyle.MEDIUM, tokens.danger, true)
var _hint := HudStyle.label("HOLD ON FOR A REVIVE", HudStyle.SMALL, tokens.ink_muted)
var _equipment := HudStyle.clip(
	HudStyle.label("", HudStyle.SMALL, tokens.ink, false, HudStyle.TRACK_CAPTION)
)
var _grenades := HudStyle.label("", HudStyle.SMALL, tokens.ink, false, HudStyle.TRACK_CAPTION)
var _top := HBoxContainer.new()


func _init() -> void:
	super()
	custom_minimum_size.x = WIDTH
	body.add_theme_constant_override(&"separation", HudStyle.XS)
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grenades.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_top.add_child(_label)
	_top.add_child(_grenades)
	body.add_child(_top)
	_bar.custom_minimum_size.y = BAR_HEIGHT
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	body.add_child(_bar)
	body.add_child(_down)
	body.add_child(_hint)
	body.add_child(_equipment)


func topics() -> Array[StringName]:
	return [HudState.HEALTH, HudState.TEAM]


func refresh() -> void:
	shown_downed = state.is_local_downed()
	_top.visible = not shown_downed
	_bar.visible = not shown_downed
	_down.visible = shown_downed
	_hint.visible = shown_downed
	HudStyle.set_text(_label, "HEALTH %d" % ceili(state.health))
	HudStyle.set_text(_grenades, "GRENADES x%d" % state.grenades)
	HudStyle.set_text(_equipment, _gear_text())
	_grenades.add_theme_color_override(
		&"font_color", tokens.ink if state.grenades > 0 else tokens.ink_disabled
	)
	_equipment.visible = not shown_downed
	var warned := shown_downed or fraction() <= LOW_FRACTION
	accent = tokens.danger if shown_downed else (tokens.hot if warned else tokens.accent)
	_bar.queue_redraw()
	queue_redraw()


## The weapon put away, cut to the card's width.
func _gear_text() -> String:
	if state.equipment_name == "":
		return ""
	var font := _equipment.get_theme_font(&"font")
	return HudStyle.trimmed(
		font, state.equipment_name.to_upper(), HudStyle.SMALL, _bar_width() - JOIN_SLACK
	)


## The width of the card's content: the bar's.
func _bar_width() -> float:
	return WIDTH - float(HudStyle.PAD + HudStyle.PAD_LEFT)


func fraction() -> float:
	return state.health / state.max_health if state.max_health > 0.0 else 0.0


func _draw_bar() -> void:
	var colour := tokens.hot if fraction() <= LOW_FRACTION else tokens.accent_bright
	var tick := (_bar_width() + TICK_GAP) / TICKS
	for i in TICKS:
		var filled := clampf(fraction() * TICKS - i, 0.0, 1.0)
		var rect := Rect2(Vector2(i * tick, 0.0), Vector2(tick - TICK_GAP, BAR_HEIGHT))
		_bar.draw_rect(rect, tokens.outline)
		if filled > 0.0:
			_bar.draw_rect(Rect2(rect.position, Vector2(rect.size.x * filled, rect.size.y)), colour)
