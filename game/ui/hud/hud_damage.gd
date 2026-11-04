class_name HudDamage
extends HudPart
## Where it hurts from, and how bad it is. A red arc swings in toward the attacker for each blow
## (`player_hurt`: its `bearing` is clockwise from -z, so it is turned by where the local player
## faces to be clockwise from straight ahead). Low health draws a red frame
## round the screen that pulses (steady with reduced motion); down, the frame is held. Fills the
## HUD.

const ARC_SPAN := 0.55
const ARC_WIDTH := 22.0
const MAX_ARCS := 6
const FRAME_WIDTH := 28.0
## How many steps the frame's strength and an arc's life are drawn in: eight levels of alpha, a
## step nobody sees in a pulse. The board is redrawn when a step changes, not every frame (#934).
const STEPS := 32

## Arcs alive: {"angle", "age"}.
var arcs: Array[Dictionary] = []
## 0..1, how strongly the frame shows; for tests and tools.
var frame_strength := 0.0

var _t := HudTuning.current()
var _time := 0.0
## What the part showed when it was last redrawn (`_look_key`).
var _drawn_key := 0


func _process(delta: float) -> void:
	advance(delta)


func topics() -> Array[StringName]:
	return [HudState.HEALTH, HudState.TEAM]


func refresh() -> void:
	_update_frame()
	_redraw_if_changed()


func on_event(event: Dictionary) -> void:
	if event.get("type") != HudState.PLAYER_HURT:
		return
	if int(event.get("player_id", -1)) != state.local_player_id:
		return
	var bearing := float(event.get("bearing", 0.0))
	arcs.append({"angle": wrapf(bearing + state.facing, -PI, PI), "age": 0.0})
	while arcs.size() > MAX_ARCS:
		arcs.pop_front()
	_redraw_if_changed()


func advance(delta: float) -> void:
	_time += delta
	for arc in arcs:
		arc["age"] = float(arc["age"]) + delta
	arcs = arcs.filter(func(a: Dictionary) -> bool: return a["age"] < _t.damage_arc_life)
	_update_frame()
	_redraw_if_changed()


func _update_frame() -> void:
	if state == null:
		return
	var fraction := state.health / state.max_health if state.max_health > 0.0 else 0.0
	if state.is_local_downed():
		frame_strength = 0.6
	elif fraction <= _t.damage_low_fraction and state.health > 0.0:
		var need := 1.0 - fraction / _t.damage_low_fraction
		var beat := 1.0 if UIMotion.reduced else 0.75 + 0.25 * sin(_time * _t.damage_pulse_rate)
		frame_strength = (0.25 + 0.35 * need) * beat
	else:
		frame_strength = 0.0


## Redraws only when what is drawn has changed by a step. A draw is a polygon per arc that the
## Compatibility renderer builds into buffers of its own, and the frame's pulse and the arcs'
## swing moved a little every frame (the web page's heap grew by it, #834).
func _redraw_if_changed() -> void:
	var key := _look_key()
	if key != _drawn_key:
		_drawn_key = key
		queue_redraw()


## A number that differs whenever the frame or an arc differs by a visible step; 0 for nothing.
func _look_key() -> int:
	var key := int(frame_strength * STEPS)
	for arc in arcs:
		key = key * (STEPS + 1) + 1 + int(float(arc["age"]) / _t.damage_arc_life * STEPS)
	return key


func _draw() -> void:
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.3
	for arc in arcs:
		var t: float = float(arc["age"]) / _t.damage_arc_life
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
