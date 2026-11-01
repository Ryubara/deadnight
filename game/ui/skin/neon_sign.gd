class_name NeonSign
extends Control
## Neon lettering: hollow glass tubes with a glow, an ignition sequence, and a steady buzz in
## which one tube fails now and then.
##
## All motion is a pure function of the accumulated time (no randomness at run time), so a
## capture repeats exactly. With reduced motion every tube is simply lit.

const IGNITE_START := 0.25
const IGNITE_GAP := 0.16
const IGNITE_STUTTER := 0.5
## The tube that fails now and then, and how often (seconds).
const FAILING_LETTER := 6
const FAIL_PERIOD := 4.7
const FAIL_BLINKS: Array[Vector2] = [Vector2(0.0, 0.07), Vector2(0.16, 0.2), Vector2(0.3, 0.33)]
const UNLIT_LEVEL := 0.1
## Glow strokes: outline width in pixels, then alpha.
const GLOW_PASSES: Array[Vector2] = [Vector2(40.0, 0.05), Vector2(24.0, 0.1), Vector2(12.0, 0.22)]
const HALO_RADIUS := 0.62
const TUBE_WIDTH := 6

@export var text := "DEADNIGHT"
@export var font_size := 150
## Letters from this index on take the second colour.
@export var split := 4
@export var tracking := 14.0
## The lettering face. Null takes the display face of the tokens in force (the engine's fallback
## font when the tokens name none); a sign that wants its own face sets this one.
@export var font: Font:
	set(value):
		font = value
		_apply_face()

var tube_a := Color("ff3d4d")
var tube_b := Color("ffb347")
## Seconds since the sign was lit; the letters ignite one after another from zero.
var clock := 0.0
var lit_from_start := false

var _font: FontVariation
var _halo: GradientTexture2D


func _init() -> void:
	_apply_face()
	_halo = GradientTexture2D.new()
	_halo.fill = GradientTexture2D.FILL_RADIAL
	_halo.fill_from = Vector2(0.5, 0.5)
	_halo.fill_to = Vector2(0.5, 0.0)
	_halo.width = 128
	_halo.height = 128
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	_halo.gradient = ramp


func _ready() -> void:
	UITokens.active_changed().connect(_apply_face.unbind(1))
	_apply_face()
	UIMotion.changed().connect(_on_reduced_changed)
	lit_from_start = UIMotion.reduced
	set_process(not UIMotion.reduced)


## Takes the lettering face from `font`, else from the display slot of the active tokens, and
## sizes the sign to it. Runs again when the tokens change.
func _apply_face() -> void:
	var tokens := UITokens.active()
	if font != null:
		_font = FontVariation.new()
		_font.base_font = font
		_font.variation_embolden = tokens.embolden_display
	else:
		_font = tokens.display_font(tokens.embolden_display)
	custom_minimum_size = _text_size() + Vector2(0.0, 40.0)
	queue_redraw()


## Starts over from dark and lights the tubes one by one.
func ignite() -> void:
	clock = 0.0
	lit_from_start = UIMotion.reduced
	set_process(not UIMotion.reduced)
	queue_redraw()


## Follows the reduced-motion setting at once: every tube lit and still, nothing redrawn per
## frame; when it is turned off again the buzz and the failing tube carry on.
func _on_reduced_changed(reduced: bool) -> void:
	lit_from_start = reduced
	if not reduced:
		# Turned off while still: carry on as a sign that has long been lit, not from dark.
		clock = maxf(clock, _ignition_end())
	set_process(not reduced)
	queue_redraw()


func _process(delta: float) -> void:
	clock += delta
	queue_redraw()


func _draw() -> void:
	var widths := _letter_widths()
	var total := 0.0
	for width in widths:
		total += width
	var baseline := (size.y + font_size * 0.7) * 0.5
	var x := (size.x - total) * 0.5
	for i in text.length():
		var colour := tube_a if i < split else tube_b
		var level := _level(i)
		var middle := Vector2(x + widths[i] * 0.5, baseline - font_size * 0.35)
		_draw_letter(text[i], i, Vector2(x, baseline), middle, widths[i], colour, level)
		x += widths[i]


func _draw_letter(
	letter: String,
	_index: int,
	at: Vector2,
	middle: Vector2,
	width: float,
	colour: Color,
	level: float
) -> void:
	var halo_size := Vector2(width * 2.4, font_size * 1.5) * HALO_RADIUS * 2.0
	draw_texture_rect(
		_halo, Rect2(middle - halo_size * 0.5, halo_size), false, Color(colour, 0.34 * level)
	)
	for pass_index in GLOW_PASSES.size():
		var glow := GLOW_PASSES[pass_index]
		draw_string_outline(
			_font,
			at,
			letter,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			font_size,
			int(glow.x),
			Color(colour, glow.y * level)
		)
	# Cold glass first, so an unlit tube still reads as a letter; the lit tube is laid over it.
	var cold := Color(colour.darkened(0.7), 0.9)
	draw_string_outline(
		_font, at, letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, TUBE_WIDTH + 3, cold
	)
	draw_string(
		_font, at, letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(colour, 0.1 * level)
	)
	draw_string_outline(
		_font,
		at,
		letter,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		TUBE_WIDTH + 3,
		Color(colour, level * 0.95)
	)
	var hot_core := colour.lerp(Color.WHITE, 0.8)
	draw_string_outline(
		_font,
		at,
		letter,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		TUBE_WIDTH - 2,
		Color(hot_core, level)
	)


## How lit tube `index` is, 0 to 1, at the current clock.
func _level(index: int) -> float:
	if UIMotion.reduced or lit_from_start:
		return 1.0
	var local := clock - (IGNITE_START + IGNITE_GAP * index)
	if local < 0.0:
		return UNLIT_LEVEL
	if local < IGNITE_STUTTER:
		# A cold tube catching: on and off at 30 steps a second, then holding.
		var step_value := _hash(floor(local * 30.0) + float(index) * 7.1)
		var catch := smoothstep(0.0, IGNITE_STUTTER, local)
		var on := 1.0 if step_value < 0.35 + 0.65 * catch else 0.0
		return lerpf(UNLIT_LEVEL, 1.0, on * (0.55 + 0.45 * catch))
	var level := 0.93 + 0.07 * sin(clock * 7.0 + float(index) * 2.3)
	# The projector's flicker dips every tube together, a hair, 12 times a second.
	if _hash(floor(clock * 12.0)) >= 0.82:
		level -= 0.06
	if index == FAILING_LETTER:
		var phase := fposmod(clock - 1.5, FAIL_PERIOD)
		for blink in FAIL_BLINKS:
			if phase >= blink.x and phase < blink.y:
				return UNLIT_LEVEL + 0.1
	return level


func _ignition_end() -> float:
	return IGNITE_START + IGNITE_GAP * text.length() + IGNITE_STUTTER


func _letter_widths() -> PackedFloat32Array:
	var widths := PackedFloat32Array()
	for i in text.length():
		widths.append(
			_font.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x + tracking
		)
	return widths


func _text_size() -> Vector2:
	var total := 0.0
	for width in _letter_widths():
		total += width
	return Vector2(total, font_size * 1.1)


static func _hash(value: float) -> float:
	return fposmod(sin(value * 127.1) * 43758.5453, 1.0)
