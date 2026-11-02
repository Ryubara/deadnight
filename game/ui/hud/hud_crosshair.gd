class_name HudCrosshair
extends HudPart
## The centre of the screen: a hit marker (four ticks that flash on a hit, wider and hot on a kill,
## warm on a headshot) and the damage numbers floating at the hit point. Fills the HUD. Numbers are
## small and nudged apart so a burst stays readable, and capped.

enum Kind { HIT, HEAD, KILL }

const MARKER_LIFE := 0.22
const NUMBER_LIFE := 0.9
const MAX_NUMBERS := 8
const NUMBER_RISE := 33.0
const TICK_NEAR := 9.0
const TICK_LENGTH := 11.0
const TICK_POP := 6.0
const MARKER_WIDTH := 4.0
## Horizontal nudges, cycled, so quick hits do not print on top of each other.
const NUDGES: Array[float] = [0.0, 20.0, -20.0, 40.0, -40.0]

## Markers alive: {"kind", "age"}; numbers alive: {"text", "at", "colour", "size", "age"}, and the
## "world" point of the hit when the event named one.
var markers: Array[Dictionary] = []
var numbers: Array[Dictionary] = []
## Turns a world point into a share of the screen (`Vector2`, `Vector2.INF` when it is not in
## view): a number that has a world point is drawn there every frame, so it stays on the wound
## while the camera turns. Without one a number starts where the event said (or by the crosshair).
var projector: Callable = Callable()

var _count := 0


func _process(delta: float) -> void:
	advance(delta)


func on_event(event: Dictionary) -> void:
	var type: StringName = event.get("type", &"")
	if type == &"zombie_damaged" and int(event.get("player_id", -1)) == state.local_player_id:
		var head := str(event.get("zone", "")) == "head"
		_hit(Kind.HEAD if head else Kind.HIT, event)
	elif type == &"zombie_removed" and int(event.get("killer_id", -1)) == state.local_player_id:
		if str(event.get("cause", "killed")) == "killed":
			markers.append({"kind": Kind.KILL, "age": 0.0})
			queue_redraw()


func advance(delta: float) -> void:
	if markers.is_empty() and numbers.is_empty():
		return
	for marker in markers:
		marker["age"] = float(marker["age"]) + delta
	for number in numbers:
		number["age"] = float(number["age"]) + delta
	markers = markers.filter(func(m: Dictionary) -> bool: return m["age"] < MARKER_LIFE)
	numbers = numbers.filter(func(n: Dictionary) -> bool: return n["age"] < NUMBER_LIFE)
	queue_redraw()


func _hit(kind: Kind, event: Dictionary) -> void:
	markers.append({"kind": kind, "age": 0.0})
	var damage := float(event.get("damage", 0.0))
	var at := size * 0.5 + Vector2(NUDGES[_count % NUDGES.size()], -float(HudStyle.MARGIN))
	if event.has("screen_x") and event.has("screen_y"):
		at = Vector2(float(event["screen_x"]) * size.x, float(event["screen_y"]) * size.y)
		at.x += NUDGES[_count % NUDGES.size()]
	var head := kind == Kind.HEAD
	var number := {
		"text": str(roundi(damage)),
		"at": at,
		"nudge": NUDGES[_count % NUDGES.size()],
		"colour": tokens.accent_bright if head else tokens.ink,
		"size": HudStyle.TEXT if head else HudStyle.MIN_TEXT,
		"age": 0.0,
	}
	if event.has("world"):
		number["world"] = event["world"]
	numbers.append(number)
	_count += 1
	while numbers.size() > MAX_NUMBERS:
		numbers.pop_front()
	queue_redraw()


func _draw() -> void:
	var centre := size * 0.5
	for marker in markers:
		_draw_marker(centre, marker)
	var font := tokens.display_font(tokens.embolden_display * 0.3)
	for number in numbers:
		var t: float = float(number["age"]) / NUMBER_LIFE
		var rise := 0.0 if UIMotion.reduced else NUMBER_RISE * t
		var colour: Color = number["colour"]
		colour.a = 1.0 - maxf(t - 0.5, 0.0) * 2.0
		var at := number_at(number) + Vector2(0.0, -rise)
		if not at.is_finite():
			continue
		var px: int = number["size"]
		draw_string_outline(
			font, at, number["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, px, 6, tokens.shadow
		)
		draw_string(font, at, number["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, px, colour)


## Where a number is this frame: over its world point as the camera has it now, else where it began;
## `Vector2.INF` while the point is out of view.
func number_at(number: Dictionary) -> Vector2:
	if number.has("world") and projector.is_valid():
		var share: Vector2 = projector.call(number["world"])
		if not share.is_finite():
			return Vector2.INF
		return share * size + Vector2(float(number["nudge"]), 0.0)
	return number["at"]


func _draw_marker(centre: Vector2, marker: Dictionary) -> void:
	var kind: Kind = marker["kind"]
	var t: float = float(marker["age"]) / MARKER_LIFE
	var colour := tokens.ink
	var reach := TICK_LENGTH
	if kind == Kind.HEAD:
		colour = tokens.accent_bright
	elif kind == Kind.KILL:
		colour = tokens.hot
		reach = TICK_LENGTH * 1.6
	colour.a = 1.0 - t
	var near := TICK_NEAR + (0.0 if UIMotion.reduced else TICK_POP * t)
	for corner in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var direction: Vector2 = corner.normalized()
		var from := centre + direction * near
		var to := centre + direction * (near + reach)
		var dark := tokens.shadow
		dark.a *= colour.a
		draw_line(from, to, dark, MARKER_WIDTH + 4.0)
		draw_line(from, to, colour, MARKER_WIDTH)
