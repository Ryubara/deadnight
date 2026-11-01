class_name HudMarquee
extends HudTicket
## The drive-in's marquee board, up in the break before a special round: what is coming (its name
## in big flickering letters like a neon sign on the verge of failing), the round it plays in, how
## long until the lights go down, and what it brings. It stands in the top-centre column under the
## banner and takes the banner's width, so nothing around it moves; it is gone as the round starts.
## Time-driven (`advance`) so captures repeat; with reduced motion the letters burn steadily and the
## bulbs hold still.

const WIDTH := HudStyle.CARD
## The name's size; a long one shrinks to fit the board.
const TITLE_SIZE := 64
const BULB_GAP := 30.0
const BULB_RADIUS := 4.0
const CHASE := 3.0
## How bright the letters are, step by step, once every `FLICKER_STEP` seconds, round and round:
## mostly steady, with two stutters.
const FLICKER := [1.0, 1.0, 1.0, 0.55, 1.0, 1.0, 1.0, 1.0, 0.7, 0.3, 1.0, 1.0, 1.0, 1.0]
const FLICKER_STEP := 0.09
## What the board says over the name, and the word for each kind.
const CAPTION := "COMING UP"

var title_text: String:
	get:
		return _title.text
var caption_text: String:
	get:
		return _caption.text
var detail_text: String:
	get:
		return _detail.text
## How bright the name is now (0 to 1), for tests.
var letter_light := 1.0

var _caption := HudStyle.clip(
	HudStyle.label("", HudStyle.SMALL, tokens.accent, false, HudStyle.TRACK_CAPTION)
)
var _title := HudStyle.label("", TITLE_SIZE, tokens.hot, true)
var _detail := HudStyle.clip(HudStyle.label("", HudStyle.TEXT, tokens.ink))
var _clock := 0.0


func _init() -> void:
	super()
	accent = tokens.hot
	body.custom_minimum_size.x = WIDTH - float(tokens.space_md * 2 + 10)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_caption)
	body.add_child(_title)
	body.add_child(_detail)
	visible = false


func _process(delta: float) -> void:
	advance(delta)


func topics() -> Array[StringName]:
	return [HudState.ROUND, HudState.SPECIAL]


func refresh() -> void:
	var coming := state.coming_special()
	visible = state.phase == HudState.PHASE_BREAK and not coming.is_empty()
	if not visible:
		return
	var title := String(coming["title"]).to_upper()
	var room := WIDTH - float(tokens.space_md * 2 + 10)
	HudStyle.set_fitted(_title, title, TITLE_SIZE, room, HudStyle.MEDIUM)
	HudStyle.set_text(
		_caption,
		"%s  -  ROUND %d  -  IN %d" % [CAPTION, int(coming["round"]), ceili(state.break_left)]
	)
	HudStyle.set_text(_detail, state.special_brings(coming))
	queue_redraw()


## Moves the flicker and the bulbs `delta` seconds on.
func advance(delta: float) -> void:
	_clock += delta
	if not visible:
		return
	letter_light = 1.0
	if not UIMotion.reduced:
		letter_light = FLICKER[int(_clock / FLICKER_STEP) % FLICKER.size()]
	_title.modulate.a = lerpf(0.35, 1.0, letter_light)
	queue_redraw()


func _draw() -> void:
	super()
	var count := int(size.x / BULB_GAP)
	var phase := 0 if UIMotion.reduced else int(_clock * CHASE)
	for row in [8.0, size.y - 8.0]:
		for i in count:
			var lit := (i + phase) % 4 < 2
			var at := Vector2((i + 0.5) * size.x / float(count), row)
			draw_circle(at, BULB_RADIUS, tokens.accent_bright if lit else tokens.outline)
