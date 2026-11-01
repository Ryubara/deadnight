class_name HudDamage
extends HudPart
## Where it hurts from, and how bad it is. A red arc swings in toward the attacker for each blow
## (`player_hurt`, direction in radians clockwise from straight ahead). Low health draws a red frame
## round the screen that pulses (steady with reduced motion); down, the frame is held. Fills the
## HUD.

const ARC_LIFE := 1.3
const ARC_SPAN := 0.55
const ARC_WIDTH := 22.0
const MAX_ARCS := 6
const FRAME_WIDTH := 28.0
const LOW_FRACTION := 0.33
const PULSE_RATE := 4.0

## Arcs alive: {"angle", "age"}.
var arcs: Array[Dictionary] = []
## 0..1, how strongly the frame shows; for tests and tools.
var frame_strength := 0.0

var _time := 0.0


func _process(delta: float) -> void:
	advance(delta)


func topics() -> Array[StringName]:
	return [HudState.HEALTH, HudState.TEAM]


func refresh() -> void:
	_update_frame()


func on_event(event: Dictionary) -> void:
	if event.get("type") != HudState.PLAYER_HURT:
		return
	if int(event.get("player_id", -1)) != state.local_player_id:
		return
	arcs.append({"angle": float(event.get("direction", 0.0)), "age": 0.0})
	while arcs.size() > MAX_ARCS:
		arcs.pop_front()
	queue_redraw()


func advance(delta: float) -> void:
	_time += delta
	for arc in arcs:
		arc["age"] = float(arc["age"]) + delta
	arcs = arcs.filter(func(a: Dictionary) -> bool: return a["age"] < ARC_LIFE)
	_update_frame()
	if not arcs.is_empty() or frame_strength > 0.0:
		queue_redraw()


func _update_frame() -> void:
	if state == null:
		return
	var before := frame_strength
	var fraction := state.health / state.max_health if state.max_health > 0.0 else 0.0
	if state.is_local_downed():
		frame_strength = 0.6
	elif fraction <= LOW_FRACTION and state.health > 0.0:
		var need := 1.0 - fraction / LOW_FRACTION
		var beat := 1.0 if UIMotion.reduced else 0.75 + 0.25 * sin(_time * PULSE_RATE)
		frame_strength = (0.25 + 0.35 * need) * beat
	else:
		frame_strength = 0.0
	if frame_strength != before:
		queue_redraw()


func _draw() -> void:
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.3
	for arc in arcs:
		var t: float = float(arc["age"]) / ARC_LIFE
		var colour := tokens.danger
		colour.a = 1.0 - t
		var middle: float = float(arc["angle"]) - PI * 0.5
		var swing := 0.0 if UIMotion.reduced else (1.0 - t) * 12.0
		draw_arc(
			centre, radius + swing, middle - ARC_SPAN, middle + ARC_SPAN, 28, colour, ARC_WIDTH
		)
	if frame_strength > 0.0:
		var edge := tokens.danger
		edge.a = frame_strength
		var inset := FRAME_WIDTH * 0.5
		draw_rect(
			Rect2(Vector2.ONE * inset, size - Vector2.ONE * inset * 2.0), edge, false, FRAME_WIDTH
		)
