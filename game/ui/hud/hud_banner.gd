class_name HudBanner
extends HudTicket
## The big announcements, one at a time, as a marquee board with a row of bulbs: the round
## starting, the round survived, the lights going out for good, and the name of an area you walk
## into. A round or game-over banner is never replaced by an area one. Time-driven (`advance`), so
## captures repeat; with reduced motion the board fades but does not grow and the bulbs hold still.

enum Rank { AREA, ROUND, END }

## Fixed width: a long title shrinks to fit instead of widening the board into the readouts.
const WIDTH := HudStyle.CARD
## Title size of a round banner ("ROUND 12" must fit the width).
const ROUND_SIZE := 72
const BULB_GAP := 27.0
const BULB_RADIUS := 4.0
const CHASE := 5.0

var title := ""
var subtitle := ""
var showing := false
## How wide the line under the title is as drawn, and the room it has, for tests.
var subtitle_width: float:
	get:
		return HudStyle.text_width(
			_subtitle.get_theme_font(&"font"), subtitle, _subtitle.get_theme_font_size(&"font_size")
		)
var subtitle_room: float:
	get:
		return WIDTH - float(HudStyle.PAD + HudStyle.PAD_LEFT)

var _t := HudTuning.current()
var _title := HudStyle.label("", ROUND_SIZE, tokens.accent_bright, true)
var _subtitle := HudStyle.label("", HudStyle.MEDIUM, tokens.ink, false)
var _age := 0.0
var _hold := _t.banner_hold
var _rank := Rank.AREA
var _clock := 0.0
## The bulbs' chase step the board was last drawn at (-1: draw at the next frame).
var _drawn_phase := -1
## The last restore of a special round the banner showed (`HudState.special_restored`).
var _restored_shown := 0


func _init() -> void:
	super()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_title)
	body.add_child(_subtitle)
	custom_minimum_size.x = WIDTH
	(_subtitle as HudLabel).wrap_words(TextServer.AUTOWRAP_WORD_SMART)
	visible = false


func _process(delta: float) -> void:
	advance(delta)


func on_event(event: Dictionary) -> void:
	match StringName(event.get("type", &"")):
		&"round_started":
			var count := int(event["zombie_count"])
			if StringName(event.get("special_id", &"")) != &"":
				_show_special(count)
				return
			show_banner(
				"ROUND %d" % int(event["round"]),
				"THE NIGHT BEGINS" if int(event["round"]) == 1 else "%d COMING" % count,
				Rank.ROUND
			)
		&"round_ended":
			show_banner(
				"ROUND %d SURVIVED" % int(event["round"]),
				_cleared_line() if not state.special_cleared.is_empty() else "CATCH YOUR BREATH",
				Rank.ROUND
			)
		&"game_over":
			var reached := int(event.get("round_reached", state.round_number))
			show_banner("THE LIGHTS GO OUT", "YOU LASTED TO ROUND %d" % reached, Rank.END, INF)
		&"area_entered":
			show_banner(str(event["area"]).to_upper(), "NOW ENTERING", Rank.AREA, 1.6)


func topics() -> Array[StringName]:
	return [HudState.SPECIAL]


## A special round restored from a snapshot (a late joiner, a reconnect) shows its banner once,
## the one the others saw when it began.
func refresh() -> void:
	if state.special_restored != _restored_shown:
		_restored_shown = state.special_restored
		if state.special_id != &"":
			_show_special(state.zombies_total)


## The banner of a special round: its name, then what it brings (the round is on the round part).
func _show_special(count: int) -> void:
	var info := HudSpecials.running(state)
	var title := HudSpecials.title(state, state.special_id)
	var brings := HudSpecials.brings(info) if not info.is_empty() else "%d COMING" % count
	show_banner(title.to_upper(), brings, Rank.ROUND)


## What the special round just cleared paid, as the line under the round survived.
func _cleared_line() -> String:
	var cleared := state.special_cleared
	var title := HudSpecials.title(state, cleared["special_id"])
	return "%s CLEARED  +%d" % [title.to_upper(), int(cleared["reward"])]


## Shows a banner; `hold` is how long it holds, or -1 for `HudTuning.banner_hold`.
func show_banner(main: String, sub: String, rank: Rank, hold := -1.0) -> void:
	if showing and rank < _rank and _age < _t.banner_in + _hold + _t.banner_out:
		return
	title = main
	subtitle = sub
	_rank = rank
	_hold = hold if hold >= 0.0 else _t.banner_hold
	_age = 0.0
	showing = true
	_drawn_phase = -1
	var wanted := ROUND_SIZE if rank == Rank.ROUND else HudStyle.BIG
	_title.add_theme_font_size_override(&"font_size", _fit_size(main, wanted))
	_title.add_theme_color_override(
		&"font_color", tokens.hot if rank == Rank.END else tokens.accent_bright
	)
	HudStyle.set_text(_title, main)
	# The line under the title shrinks to stay on one line ("THE HEADLINER ARRIVES"), down to a
	# small size; beyond that it wraps.
	HudStyle.set_fitted(_subtitle, sub, HudStyle.MEDIUM, subtitle_room, HudStyle.SMALL)
	visible = true
	_apply()


## The largest size, at most `wanted`, at which `text` fits the board on one line.
func _fit_size(text: String, wanted: int) -> int:
	var font := tokens.display_font(tokens.embolden_display * 0.5)
	var room := WIDTH - float(HudStyle.PAD + HudStyle.PAD_LEFT)
	return HudStyle.fit_size(font, text, wanted, room, HudStyle.MEDIUM)


## Moves the banner `delta` seconds on.
func advance(delta: float) -> void:
	_clock += delta
	if not showing:
		return
	_age += delta
	if _age >= _t.banner_in + _hold + _t.banner_out:
		showing = false
		visible = false
		return
	_apply()
	# The board is redrawn when the bulbs step on, not every frame: a redraw rebuilds every bulb's
	# polygon in the renderer (#834).
	var phase := 0 if UIMotion.reduced else int(_clock * CHASE)
	if phase != _drawn_phase:
		_drawn_phase = phase
		queue_redraw()


## 0 to 1 how much of the banner shows: in, held, out.
func presence() -> float:
	if not showing:
		return 0.0
	if _age < _t.banner_in:
		return _age / _t.banner_in
	if _age < _t.banner_in + _hold:
		return 1.0
	return 1.0 - (_age - _t.banner_in - _hold) / _t.banner_out


func _apply() -> void:
	var shown := presence()
	modulate.a = shown
	pivot_offset = size * 0.5
	scale = Vector2.ONE * (1.0 if UIMotion.reduced else lerpf(_t.banner_pop_from, 1.0, shown))


func _draw() -> void:
	# The card and its bulbs are one command (`HudShapes`).
	var shapes := HudShapes.new()
	HudStyle.add_ticket(shapes, Rect2(Vector2.ZERO, size), accent, lit)
	var count := int(size.x / BULB_GAP)
	var phase := 0 if UIMotion.reduced else int(_clock * CHASE)
	for row in [8.0, size.y - 8.0]:
		for i in count:
			var lit := (i + phase) % 3 == 0
			var at := Vector2((i + 0.5) * size.x / float(count), row)
			if lit:
				shapes.circle(at, BULB_RADIUS * 2.2, Color(tokens.accent, 0.2))
			shapes.circle(at, BULB_RADIUS, tokens.accent_bright if lit else tokens.outline)
	shapes.flush(self)
