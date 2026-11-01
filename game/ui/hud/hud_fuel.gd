class_name HudFuel
extends HudPart
## The generator: a tank of segments and one bulb per circuit, on a ticket that is not always on.
## It shows for a moment when the night makes progress at the generator or a step of its quest
## completes (fuel added, a circuit switched, the warnings), slides down into the top-right column
## and fades in, holds `HOLD_TIME` seconds, then fades and slides back out; the lists below it
## follow its height. The tank turns hot orange when low and pulses (steady with reduced motion);
## with the tank dry every bulb is dark.
##
## Time is the caller's: `advance(delta)` moves it, so a test or a capture steps it by hand. The
## fuel the generator burns is not progress, so a `fuel_changed` that only counts the tank down
## does not show it.

const IN_TIME := 0.3
const HOLD_TIME := 4.0
const OUT_TIME := 0.5
## Events that show the panel; a `fuel_changed` shows it only when fuel was added.
const SHOW_EVENTS: Array[StringName] = [
	&"circuit_changed", &"fuel_low", &"fuel_empty", &"fuel_restored"
]
const SEGMENTS := 20
const SEGMENT_HEIGHT := 25.0
const SEGMENT_GAP := 3.0
## The width of the ticket and of the gauge in it: the same as the column's other cards.
const WIDTH := HudStyle.COLUMN
const GAUGE_WIDTH := WIDTH - float(HudStyle.PAD + HudStyle.PAD_LEFT)
const BULB_RADIUS := 8.0
## The bulbs sit in a grid, a bulb with its word beside it (not under it), so a word has half the
## gauge's width to itself instead of a quarter: "SCREEN" and "BACK LOT" are never cut.
const BULB_COLUMNS := 2
## Distance between the rows of bulbs, and from the segments to the first row's centre.
const BULB_ROW_PITCH := 26.0
const BULB_ROWS_TOP := 18.0
## Room kept between a bulb and its word, and from a cell's left edge to the bulb's centre.
const BULB_WORD_GAP := 6.0
const BULB_INSET := BULB_RADIUS + 2.0
## How far a lit bulb's glow reaches, in bulb radii.
const GLOW_REACH := 1.7
const PULSE_RATE := 5.0
## Room kept between a word and the next cell.
const WORD_GAP := 2.0
## Extra space between the letters of those words; none, so the longest still fits its slot.
const WORD_TRACKING := 0.0
## Circuit ids to the words on the lot signs.
const CIRCUIT_NAMES := {
	&"screen_lot": "SCREEN",
	&"concession": "SNACKS",
	&"booth": "BOOTH",
	&"back_lot": "BACK LOT",
}

var lit_segments := 0
var lit_circuits: Array[StringName] = []
## The word beside each bulb as drawn: cut with an ellipsis only when the typeface makes it wider
## than its slot, so neighbouring words never run together.
var circuit_words: Dictionary[StringName, String] = {}
var status_text: String:
	get:
		return _status.text
## Whether the panel is on its way in, held or on its way out.
var showing := false
## The ticket itself (it slides inside this part, which holds only the room it has revealed).
var panel := HudTicket.new()

var _caption := HudStyle.label(
	"GENERATOR", HudStyle.SMALL, tokens.accent, false, HudStyle.TRACK_CAPTION
)
var _status := HudStyle.label("", HudStyle.SMALL, tokens.ink_muted, false, HudStyle.TRACK_CAPTION)
var _gauge := Control.new()
var _time := 0.0
var _age := 0.0
## The presence the layout last took, so a held panel costs no layout.
var _applied := -1.0


func _init() -> void:
	super()
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_caption)
	top.add_child(_status)
	panel.body.add_child(top)
	_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge.custom_minimum_size = Vector2(
		GAUGE_WIDTH, SEGMENT_HEIGHT + BULB_ROWS_TOP + BULB_ROW_PITCH + 14.0
	)
	panel.custom_minimum_size.x = WIDTH
	_gauge.draw.connect(_draw_gauge)
	panel.body.add_child(_gauge)
	panel.minimum_size_changed.connect(_fit_panel)
	add_child(panel)
	panel.visible = false
	visible = false


func _process(delta: float) -> void:
	advance(delta)


## Moves the panel `delta` seconds on: in, held, out. The tank's pulse runs on the same clock.
func advance(delta: float) -> void:
	_time += delta
	if showing:
		_age += delta
		if _age >= IN_TIME + HOLD_TIME + OUT_TIME:
			showing = false
			_age = 0.0
		_apply()
	if showing and state != null and state.fuel_low and not UIMotion.reduced:
		_gauge.queue_redraw()


## How much of the panel shows, 0 to 1: in, held, out.
func presence() -> float:
	if not showing:
		return 0.0
	if _age < IN_TIME:
		return _age / IN_TIME
	if _age < IN_TIME + HOLD_TIME:
		return 1.0
	return clampf(1.0 - (_age - IN_TIME - HOLD_TIME) / OUT_TIME, 0.0, 1.0)


## Shows the panel (or keeps it up for `HOLD_TIME` more seconds when it already shows).
func peek() -> void:
	_age = minf(_age, presence() * IN_TIME) if showing else 0.0
	showing = true
	_apply()


## Whether `event` is progress at the generator: fuel added, a circuit switched, or a warning.
static func is_progress(event: Dictionary) -> bool:
	var type := StringName(event.get("type", &""))
	if type == &"fuel_changed":
		return float(event.get("delta", 0.0)) > 0.0
	return SHOW_EVENTS.has(type)


func on_event(event: Dictionary) -> void:
	if is_progress(event):
		peek()


func _get_minimum_size() -> Vector2:
	var full := panel.get_combined_minimum_size()
	return Vector2(full.x, full.y * _slide()) if panel.visible else Vector2.ZERO


## How far the panel has slid in: its presence, eased; all of it at once with reduced motion.
func _slide() -> float:
	if UIMotion.reduced:
		return 1.0
	var shown := presence()
	return shown * shown * (3.0 - 2.0 * shown)


func _apply() -> void:
	var shown := presence()
	if showing == visible and is_equal_approx(shown, _applied):
		return
	_applied = shown
	panel.visible = showing
	visible = showing
	panel.modulate.a = shown
	_fit_panel()
	update_minimum_size()


## The ticket keeps its full size and slides down out of the top of the room revealed.
func _fit_panel() -> void:
	var full := panel.get_combined_minimum_size()
	panel.size = full
	panel.position = Vector2(0.0, -full.y * (1.0 - _slide()))


func topics() -> Array[StringName]:
	return [HudState.FUEL]


func refresh() -> void:
	lit_segments = ceili(state.fuel_fraction() * SEGMENTS)
	lit_circuits.clear()
	for circuit_id in state.circuits:
		if state.circuits[circuit_id] and not state.fuel_empty:
			lit_circuits.append(circuit_id)
	_cut_circuit_words()
	HudStyle.set_text(_status, _status_word())
	panel.accent = tokens.hot if state.fuel_low or state.fuel_empty else tokens.accent
	panel.lit = 1.0 if state.fuel_empty else 0.0
	_gauge.queue_redraw()


func _cut_circuit_words() -> void:
	circuit_words.clear()
	if state.circuits.is_empty():
		return
	var font := tokens.text_font(0.0, WORD_TRACKING)
	var slot := word_slot(_gauge.custom_minimum_size.x)
	for circuit_id in state.circuits:
		var word: String = CIRCUIT_NAMES.get(circuit_id, String(circuit_id).to_upper())
		circuit_words[circuit_id] = HudStyle.trimmed(font, word, HudStyle.MIN_TEXT, slot)


## The width a word may take: its cell less the bulb, the gap after it and the gap to the next cell.
func word_slot(gauge_width: float) -> float:
	return gauge_width / float(BULB_COLUMNS) - BULB_INSET - BULB_RADIUS - BULB_WORD_GAP - WORD_GAP


func _status_word() -> String:
	if state.fuel_empty:
		return "NO POWER"
	return "LOW" if state.fuel_low else "%d%%" % roundi(state.fuel_fraction() * 100.0)


func _draw_gauge() -> void:
	var warn := state.fuel_low or state.fuel_empty
	var pulse := 1.0
	if state.fuel_low and not UIMotion.reduced:
		pulse = 0.65 + 0.35 * sin(_time * PULSE_RATE)
	var lit_colour := tokens.hot if warn else tokens.accent_bright
	var segment := Vector2((_gauge.size.x + SEGMENT_GAP) / SEGMENTS - SEGMENT_GAP, SEGMENT_HEIGHT)
	for i in SEGMENTS:
		var at := Vector2(i * (segment.x + SEGMENT_GAP), 0.0)
		var on := i < lit_segments
		var colour := lit_colour if on else tokens.outline
		colour.a = pulse if on else 1.0
		_gauge.draw_rect(Rect2(at, segment), colour)
	_draw_bulbs()


func _draw_bulbs() -> void:
	if state.circuits.is_empty():
		return
	var font := tokens.text_font(0.0, WORD_TRACKING)
	var cell_width := _gauge.size.x / float(BULB_COLUMNS)
	# Centres the capitals on the bulb: half the height between the baseline's ascent and descent.
	var lift := (font.get_ascent(HudStyle.MIN_TEXT) - font.get_descent(HudStyle.MIN_TEXT)) * 0.5
	var index := 0
	for circuit_id in _ordered_circuits():
		var on := lit_circuits.has(circuit_id)
		var centre := Vector2(
			cell_width * (index % BULB_COLUMNS) + BULB_INSET,
			SEGMENT_HEIGHT + BULB_ROWS_TOP + BULB_ROW_PITCH * (index / BULB_COLUMNS)
		)
		if on:
			_gauge.draw_circle(centre, BULB_RADIUS * GLOW_REACH, Color(tokens.accent, 0.2))
		_gauge.draw_circle(centre, BULB_RADIUS, tokens.accent_bright if on else tokens.outline)
		_gauge.draw_string(
			font,
			Vector2(centre.x + BULB_RADIUS + BULB_WORD_GAP, centre.y + lift),
			circuit_words.get(circuit_id, ""),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			HudStyle.MIN_TEXT,
			tokens.ink if on else tokens.ink_disabled
		)
		index += 1


## The circuits in the order the lot is opened (the signs' own order), unknown ones last.
func _ordered_circuits() -> Array:
	var ids := state.circuits.keys()
	var known := CIRCUIT_NAMES.keys()
	ids.sort_custom(
		func(a: Variant, b: Variant) -> bool:
			var ia := known.find(a) if known.has(a) else known.size()
			var ib := known.find(b) if known.has(b) else known.size()
			return ia < ib
	)
	return ids
