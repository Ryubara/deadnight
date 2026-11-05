class_name HudMarquee
extends HudTicket
## The drive-in's marquee board, up in the break before a special round: what is coming (its name
## in big flickering letters like a neon sign on the verge of failing), the round it plays in, how
## long until the lights go down, and what it brings. It stands in the top-centre column under the
## banner and takes the banner's width, so nothing around it moves; it is gone as the round starts.
## Time-driven (`advance`) so captures repeat; with reduced motion the letters burn steadily and the
## bulbs hold still.

const WIDTH := HudStyle.CARD
## The text line of the board: the card's text grid (`PAD_LEFT` in, `PAD` in from the right).
const TEXT_WIDTH := WIDTH - float(HudStyle.PAD + HudStyle.PAD_LEFT)
## The name's size; a long one shrinks to fit the board.
const TITLE_SIZE := HudStyle.BIG
## The bulbs are the banner's, so the two boards read as one family.
const BULB_GAP := HudBanner.BULB_GAP
const BULB_RADIUS := HudBanner.BULB_RADIUS
const CHASE := 3.0
## How bright the letters are, step by step, once every `FLICKER_STEP` seconds, round and round:
## mostly steady, with two stutters.
const FLICKER := [1.0, 1.0, 1.0, 0.55, 1.0, 1.0, 1.0, 1.0, 0.7, 0.3, 1.0, 1.0, 1.0, 1.0]
const FLICKER_STEP := 0.09
## What the board says over the name, and the word for each kind.
const CAPTION := "COMING UP"

var title_text: String:
	get:
		return _title.text if _title != null else ""
var caption_text: String:
	get:
		return _caption.text if _caption != null else ""
var detail_text: String:
	get:
		return _detail.text if _detail != null else ""
## How bright the name is now (0 to 1), for tests.
var letter_light := 1.0

## The board's three lines are made the first time a special round is coming (`_build`): the part
## is hidden the whole of a night with none, and the late-round budget counts every canvas item of
## the tree.
var _caption: Label
var _title: Label
var _detail: Label
var _clock := 0.0
## The bulb step the board was last drawn at, so it is redrawn when the chase steps on.
var _drawn_phase := -1


func _init() -> void:
	super()
	accent = tokens.hot
	visible = false


func _build() -> void:
	if _title != null:
		return
	_caption = HudStyle.clip(
		HudStyle.label("", HudStyle.SMALL, tokens.accent, false, HudStyle.TRACK_CAPTION)
	)
	_title = HudStyle.label("", TITLE_SIZE, tokens.hot, true)
	_detail = HudStyle.clip(HudStyle.label("", HudStyle.TEXT, tokens.ink))
	body.custom_minimum_size.x = TEXT_WIDTH
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_caption)
	body.add_child(_title)
	body.add_child(_detail)


func _process(delta: float) -> void:
	advance(delta)


func topics() -> Array[StringName]:
	return [HudState.ROUND, HudState.SPECIAL]


func refresh() -> void:
	var coming := HudSpecials.coming(state)
	visible = state.phase == HudState.PHASE_BREAK and not coming.is_empty()
	if not visible:
		return
	_build()
	var title := String(coming["title"]).to_upper()
	HudStyle.set_fitted(_title, title, TITLE_SIZE, TEXT_WIDTH, HudStyle.MEDIUM)
	HudStyle.set_text(
		_caption,
		"%s  -  ROUND %d  -  IN %d" % [CAPTION, int(coming["round"]), ceili(state.break_left)]
	)
	HudStyle.set_text(_detail, HudSpecials.brings(coming))


## Moves the flicker and the bulbs `delta` seconds on.
func advance(delta: float) -> void:
	_clock += delta
	if not visible:
		return
	letter_light = 1.0
	if not UIMotion.reduced:
		letter_light = FLICKER[int(_clock / FLICKER_STEP) % FLICKER.size()]
	_title.modulate.a = lerpf(0.35, 1.0, letter_light)
	# Drawn when the bulbs step on, not every frame: the letters flicker through the label's own
	# `modulate`, which the board does not redraw for, and a redraw rebuilds every bulb's polygon in
	# the renderer (#834, #934).
	if _bulb_phase() != _drawn_phase:
		queue_redraw()


func _draw() -> void:
	super()
	var count := int(size.x / BULB_GAP)
	var phase := _bulb_phase()
	_drawn_phase = phase
	for row in [8.0, size.y - 8.0]:
		for i in count:
			var lit := (i + phase) % 4 < 2
			var at := Vector2((i + 0.5) * size.x / float(count), row)
			draw_circle(at, BULB_RADIUS, tokens.accent_bright if lit else tokens.outline)


## Which way the bulbs chase now: the one number `_draw` reads besides the size.
func _bulb_phase() -> int:
	return 0 if UIMotion.reduced else int(_clock * CHASE)
