class_name HudRevive
extends HudPart
## The ring of a revive, on both screens (docs/design/revive.md, What the player sees). Over the
## view, a little under the reticle: - the reviver, holding Use beside a downed teammate: a ring
## filling as the hold goes on, the
##    seconds left inside it and `REVIVING <NAME>` under it;
##  - a downed player: the bleed-out clock as a ring that drains in danger red with the seconds left
##    inside, and `BLEEDING OUT` under it; when a teammate is pulling them up, that teammate's ring
##    fills over the clock (`<NAME> IS PULLING YOU UP`);
##  - a downed player the revive perk is getting up alone: the perk's own count as a ring that
##    fills, the seconds left inside and `GETTING YOURSELF UP` under it (the clock stands still);
##  - a player who bled out: `YOU BLED OUT` and `BACK NEXT ROUND`.
## Nothing is drawn for a player who is up and not reviving. All of it is the server's numbers
## (`HudState.team`'s "bleed", "revive", "reviver", "dead"), so both screens show the same ring.

enum Mode { NONE, REVIVING, DOWNED, BEING_REVIVED, DEAD, SELF_REVIVING }

## Where the ring is centred, as a share of the screen, and how big it is, canvas units.
const CENTRE := Vector2(0.5, 0.66)
const RADIUS := 64.0
const RING := 12.0
const CLOCK_RING := 5.0
const SEGMENTS := 64
const NUMBER_SIZE := HudStyle.POINTS
const LINE_SIZE := HudStyle.TEXT

## What is shown, for tests and tools.
var mode := Mode.NONE
## The hold's progress, 0 to 1, and the bleed-out clock's share left, 0 to 1.
var fraction := 0.0
var clock_fraction := 0.0
## The seconds in the ring and the words under it.
var number_text := ""
var line_text := ""
var sub_text := ""


func topics() -> Array[StringName]:
	return [HudState.REVIVE, HudState.TEAM]


func refresh() -> void:
	var before := [mode, fraction, clock_fraction, number_text, line_text, sub_text]
	_read()
	if before != [mode, fraction, clock_fraction, number_text, line_text, sub_text]:
		visible = mode != Mode.NONE
		queue_redraw()


func _read() -> void:
	mode = Mode.NONE
	fraction = 0.0
	clock_fraction = 0.0
	number_text = ""
	line_text = ""
	sub_text = ""
	var me: Dictionary = state.team.get(state.local_player_id, {})
	if me.is_empty():
		return
	if bool(me["dead"]):
		mode = Mode.DEAD
		line_text = "YOU BLED OUT"
		sub_text = "BACK NEXT ROUND"
		return
	if bool(me["downed"]):
		clock_fraction = state.bleed_share(me)
		number_text = str(ceili(float(me["bleed"])))
		if float(me["self_revive"]) > 0.0:
			mode = Mode.SELF_REVIVING
			number_text = str(ceili(float(me["self_revive"])))
			fraction = 1.0 - clampf(float(me["self_revive"]) / state.self_revive_total, 0.0, 1.0)
			line_text = "GETTING YOURSELF UP"
		elif int(me["reviver"]) != 0:
			mode = Mode.BEING_REVIVED
			fraction = float(me["revive"])
			line_text = "%s IS PULLING YOU UP" % _name(int(me["reviver"]))
		else:
			mode = Mode.DOWNED
			line_text = "BLEEDING OUT"
			sub_text = "HOLD ON FOR A REVIVE"
		return
	for id: int in state.team:
		var other: Dictionary = state.team[id]
		if int(other["reviver"]) == state.local_player_id and bool(other["downed"]):
			mode = Mode.REVIVING
			fraction = float(other["revive"])
			number_text = str(ceili((1.0 - fraction) * state.revive_seconds))
			line_text = "REVIVING %s" % _name(id)
			return


func _name(player_id: int) -> String:
	return HudState.name_of(state.team.get(player_id, {}))


func _ready() -> void:
	visible = false
	resized.connect(queue_redraw)


func _draw() -> void:
	if mode == Mode.NONE:
		return
	var centre := size * CENTRE
	draw_circle(centre, RADIUS + RING, Color(tokens.shadow, 0.55))
	if mode == Mode.DEAD:
		draw_arc(centre, RADIUS, 0.0, TAU, SEGMENTS, Color(tokens.danger, 0.5), CLOCK_RING, true)
	else:
		# The clock: the whole ring dim, the part still left bright and draining.
		draw_arc(centre, RADIUS, 0.0, TAU, SEGMENTS, Color(tokens.outline, 0.8), CLOCK_RING, true)
		if mode != Mode.REVIVING and mode != Mode.SELF_REVIVING:
			_arc(centre, RADIUS, clock_fraction, tokens.danger, CLOCK_RING)
		# The hold, thicker and inside the clock, filling clockwise from the top.
		var inner := RADIUS - RING * 0.5 - CLOCK_RING
		draw_arc(centre, inner, 0.0, TAU, SEGMENTS, Color(tokens.outline, 0.8), RING, true)
		_arc(centre, inner, fraction, tokens.accent_bright, RING)
	var font := tokens.display_font(tokens.embolden_display * 0.5, 0.0)
	if number_text != "":
		_text(font, number_text, centre + Vector2(0.0, NUMBER_SIZE * 0.34), NUMBER_SIZE, tokens.ink)
	var text_font := tokens.text_font(tokens.embolden_display * 0.3, 1.0)
	var under := centre + Vector2(0.0, RADIUS + RING + LINE_SIZE + 6.0)
	var colour := (
		tokens.accent_bright
		if mode in [Mode.REVIVING, Mode.BEING_REVIVED, Mode.SELF_REVIVING]
		else tokens.danger
	)
	_text(text_font, line_text, under, LINE_SIZE, colour)
	if sub_text != "":
		_text(
			text_font,
			sub_text,
			under + Vector2(0.0, HudStyle.SMALL + 6.0),
			HudStyle.SMALL,
			tokens.ink_muted
		)


## An arc from the top, clockwise, covering `share` of the circle.
func _arc(centre: Vector2, radius: float, share: float, colour: Color, width: float) -> void:
	if share <= 0.0:
		return
	var start := -PI * 0.5
	draw_arc(
		centre, radius, start, start + TAU * clampf(share, 0.0, 1.0), SEGMENTS, colour, width, true
	)


func _text(
	font: Font, text: String, baseline_centre: Vector2, font_size: int, colour: Color
) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := baseline_centre - Vector2(width * 0.5, 0.0)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 7, tokens.shadow)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)
