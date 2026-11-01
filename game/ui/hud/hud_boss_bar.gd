class_name HudBossBar
extends HudTicket
## The headliner's health: its name over a long bar that empties as the lamp-lit boss is shot,
## one bar a boss (a boss night with more players brings more than one). It shows only while a
## boss stands on the lot, under the banner in the top-centre column, and takes the width of the
## prompt and the banner so nothing around it moves.

const WIDTH := HudStyle.CARD
const BAR_HEIGHT := 16.0
const BAR_GAP := 6.0
## At most this many bars; the caption counts the rest.
const MAX_BARS := 3
## A type id to the name the bar shows; one without an entry shows its id in capitals.
const NAMES := {&"headliner": "THE PROJECTIONIST"}
## The bar turns hot under this fraction of the boss's health.
const LOW_FRACTION := 0.25

## The fractions the bars show, one per boss.
var fractions: Array[float] = []
var caption_text: String:
	get:
		return _caption.text

var _caption := HudStyle.clip(
	HudStyle.label("", HudStyle.SMALL, tokens.accent, false, HudStyle.TRACK_CAPTION)
)
var _bars := Control.new()


func _init() -> void:
	super()
	accent = tokens.hot
	body.custom_minimum_size.x = WIDTH - float(HudStyle.PAD + HudStyle.PAD_LEFT)
	body.add_child(_caption)
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars.draw.connect(_draw_bars)
	body.add_child(_bars)
	visible = false


func topics() -> Array[StringName]:
	return [HudState.BOSS]


func refresh() -> void:
	fractions.clear()
	for boss in state.bosses:
		fractions.append(clampf(boss["health"] / maxf(boss["max_health"], 1.0), 0.0, 1.0))
	visible = not fractions.is_empty()
	if visible:
		var type: StringName = state.bosses[0]["type"]
		var named: String = NAMES.get(type, String(type).to_upper())
		var extra := state.bosses.size() - 1
		HudStyle.set_text(_caption, named if extra == 0 else "%s  +%d" % [named, extra])
	var rows := mini(fractions.size(), MAX_BARS)
	_bars.custom_minimum_size.y = (
		float(rows) * (BAR_HEIGHT + BAR_GAP) - BAR_GAP if rows > 0 else 0.0
	)
	_bars.queue_redraw()
	queue_redraw()


func _draw_bars() -> void:
	for row in mini(fractions.size(), MAX_BARS):
		var at := Vector2(0.0, float(row) * (BAR_HEIGHT + BAR_GAP))
		var width := _bars.size.x
		var fraction := fractions[row]
		var colour := tokens.hot if fraction <= LOW_FRACTION else tokens.accent_bright
		_bars.draw_rect(Rect2(at, Vector2(width, BAR_HEIGHT)), tokens.outline)
		if fraction > 0.0:
			_bars.draw_rect(Rect2(at, Vector2(width * fraction, BAR_HEIGHT)), colour)
