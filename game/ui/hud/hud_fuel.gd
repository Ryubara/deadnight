class_name HudFuel
extends HudTicket
## The generator: a tank of segments and one bulb per circuit. The tank turns hot orange when low
## and pulses (steady with reduced motion); with the tank dry every bulb is dark.

const SEGMENTS := 20
const SEGMENT_SIZE := Vector2(14.0, 34.0)
const SEGMENT_GAP := 4.0
const BULB_RADIUS := 11.0
const PULSE_RATE := 5.0
## Room kept between two words under the bulbs.
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
## The word under each bulb as drawn: cut with an ellipsis when the typeface makes it wider than
## the bulb's slot, so neighbouring words never run together.
var circuit_words: Dictionary[StringName, String] = {}
var status_text: String:
	get:
		return _status.text

var _caption := HudStyle.label(
	"GENERATOR", HudStyle.SMALL, tokens.accent, false, HudStyle.TRACK_CAPTION
)
var _status := HudStyle.label("", HudStyle.SMALL, tokens.ink_muted, false, HudStyle.TRACK_CAPTION)
var _gauge := Control.new()
var _time := 0.0


func _init() -> void:
	super()
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_caption)
	top.add_child(_status)
	body.add_child(top)
	_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge.custom_minimum_size = Vector2(
		SEGMENTS * (SEGMENT_SIZE.x + SEGMENT_GAP) - SEGMENT_GAP, SEGMENT_SIZE.y + 76.0
	)
	_gauge.draw.connect(_draw_gauge)
	body.add_child(_gauge)


func _process(delta: float) -> void:
	_time += delta
	if state != null and state.fuel_low and not UIMotion.reduced:
		_gauge.queue_redraw()


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
	accent = tokens.hot if state.fuel_low or state.fuel_empty else tokens.accent
	lit = 1.0 if state.fuel_empty else 0.0
	queue_redraw()
	_gauge.queue_redraw()


func _cut_circuit_words() -> void:
	circuit_words.clear()
	var count := state.circuits.size()
	if count == 0:
		return
	var font := tokens.text_font(0.0, WORD_TRACKING)
	var slot := _gauge.custom_minimum_size.x / float(count) - WORD_GAP
	for circuit_id in state.circuits:
		var word: String = CIRCUIT_NAMES.get(circuit_id, String(circuit_id).to_upper())
		circuit_words[circuit_id] = HudStyle.trimmed(font, word, HudStyle.MIN_TEXT, slot)


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
	for i in SEGMENTS:
		var at := Vector2(i * (SEGMENT_SIZE.x + SEGMENT_GAP), 0.0)
		var on := i < lit_segments
		var colour := lit_colour if on else tokens.outline
		colour.a = pulse if on else 1.0
		_gauge.draw_rect(Rect2(at, SEGMENT_SIZE), colour)
	_draw_bulbs()


func _draw_bulbs() -> void:
	var count := state.circuits.size()
	if count == 0:
		return
	var font := tokens.text_font(0.0, WORD_TRACKING)
	var column := _gauge.size.x / float(count)
	var index := 0
	for circuit_id in _ordered_circuits():
		var on := lit_circuits.has(circuit_id)
		var centre := Vector2(column * (index + 0.5), SEGMENT_SIZE.y + 28.0)
		if on:
			_gauge.draw_circle(centre, BULB_RADIUS * 2.0, Color(tokens.accent, 0.2))
		_gauge.draw_circle(centre, BULB_RADIUS, tokens.accent_bright if on else tokens.outline)
		var word: String = circuit_words.get(circuit_id, "")
		var width := HudStyle.text_width(font, word, HudStyle.MIN_TEXT)
		_gauge.draw_string(
			font,
			Vector2(centre.x - width * 0.5, centre.y + BULB_RADIUS + 28.0),
			word,
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
