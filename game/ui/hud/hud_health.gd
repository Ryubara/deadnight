class_name HudHealth
extends HudTicket
## Health as a bar of ticks under its number, on a card as wide as the column. Down, the bar is
## replaced by a red DOWN tag and what to hope for; the bar turns hot orange under a third. The
## grenade count sits at the right of the label. The weapons are not here: the slot strip above
## the ammo card shows what is carried (`HudSlots`).

## Letter spacing of the top row: tighter than a caption, so it fits HEALTH 100 and the grenades.
const TRACKING := 1.0
const BAR_HEIGHT := 20.0
const TICKS := 10
const TICK_GAP := 4.0
const WIDTH := HudStyle.COLUMN

var shown_downed := false
var grenade_text: String:
	get:
		return _grenades.text
var down_text: String:
	get:
		return _down.text
var hint_text: String:
	get:
		return _hint.text

var _t := HudTuning.current()
var _label := HudStyle.clip(
	HudStyle.label("HEALTH", HudStyle.SMALL, tokens.accent, false, TRACKING)
)
var _bar := Control.new()
var _down := HudStyle.label("DOWN", HudStyle.MEDIUM, tokens.danger, true)
var _hint := HudStyle.label("HOLD ON FOR A REVIVE", HudStyle.SMALL, tokens.ink_muted)
var _grenades := HudStyle.label("", HudStyle.SMALL, tokens.ink, false, TRACKING)
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


func topics() -> Array[StringName]:
	return [HudState.HEALTH, HudState.TEAM, HudState.REVIVE]


func refresh() -> void:
	shown_downed = state.is_local_downed()
	_say_down()
	_top.visible = not shown_downed
	_bar.visible = not shown_downed
	_down.visible = shown_downed
	_hint.visible = shown_downed
	HudStyle.set_text(_label, "HEALTH %d" % ceili(state.health))
	HudStyle.set_text(_grenades, "GRENADES x%d" % state.grenades)
	_grenades.add_theme_color_override(
		&"font_color", tokens.ink if state.grenades > 0 else tokens.ink_disabled
	)
	var warned := shown_downed or fraction() <= _t.health_low_fraction
	accent = tokens.danger if shown_downed else (tokens.hot if warned else tokens.accent)
	_bar.queue_redraw()
	queue_redraw()


## What the card says while down: DOWN and the clock, being pulled up, or DEAD until the round ends.
func _say_down() -> void:
	var me: Dictionary = state.team.get(state.local_player_id, {})
	if me.is_empty() or not shown_downed:
		return
	if bool(me["dead"]):
		HudStyle.set_text(_down, "DEAD")
		HudStyle.set_text(_hint, "BACK NEXT ROUND")
	elif int(me["reviver"]) != 0:
		HudStyle.set_text(_down, "DOWN")
		HudStyle.set_text(_hint, "BEING PULLED UP")
	else:
		HudStyle.set_text(_down, "DOWN")
		HudStyle.set_text(_hint, "BLEEDING OUT  %d S" % ceili(float(me["bleed"])))


## The width of the card's content: the bar's.
func _bar_width() -> float:
	return WIDTH - float(HudStyle.PAD + HudStyle.PAD_LEFT)


func fraction() -> float:
	return state.health / state.max_health if state.max_health > 0.0 else 0.0


func _draw_bar() -> void:
	var colour := tokens.hot if fraction() <= _t.health_low_fraction else tokens.accent_bright
	var tick := (_bar_width() + TICK_GAP) / TICKS
	for i in TICKS:
		var filled := clampf(fraction() * TICKS - i, 0.0, 1.0)
		var rect := Rect2(Vector2(i * tick, 0.0), Vector2(tick - TICK_GAP, BAR_HEIGHT))
		_bar.draw_rect(rect, tokens.outline)
		if filled > 0.0:
			_bar.draw_rect(Rect2(rect.position, Vector2(rect.size.x * filled, rect.size.y)), colour)
