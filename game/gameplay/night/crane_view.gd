class_name CraneView
extends Node3D
## Draws the prize crane where the server says it stands, from each frame's `crane`. The crane is
## one prop that moves: after a breakdown it sinks where it was and rises at the next spot.

## Metres from a crane spot's marker to the crane's middle, along the marker's facing.
const SET_BACK := 1.5
const SINK_SECONDS := 0.4
const RISE_SECONDS := 0.6
const SINK_DEPTH := 3.0

var crane: PrizeCrane
var step := 1.0 / 60.0

var _spots: Dictionary[int, Transform3D] = {}
var _at := -1
var _place := Transform3D.IDENTITY
var _rest_y := 0.0
var _sink_left := 0.0
var _rise_left := 0.0


## `spots` is `NightWorld.shop_spots()`; the crane's own are the ones of kind `crane`.
func setup(
	state: ClientState, spots: Array[Dictionary], tuning: CraneTuning, pool: Array[StringName]
) -> void:
	for spot in spots:
		if spot["kind"] == &"crane":
			_spots[spot["crane_spot"]] = stand_at(spot["position"], spot["yaw"])
	crane = PrizeCrane.new()
	add_child(crane)
	crane.configure(tuning, pool)
	crane.visible = false
	state.event_received.connect(_on_event)


## The crane's place for a marker at `marker` facing `yaw`: set back along it, turned to face the
## marker.
static func stand_at(marker: Vector3, yaw: float) -> Transform3D:
	var toward := Vector3(sin(yaw), 0.0, cos(yaw))
	return Transform3D(Basis(Vector3.UP, yaw + PI), marker + toward * SET_BACK)


func _on_event(event: Dictionary) -> void:
	if event["type"] != &"frame":
		return
	var state: Dictionary = event.get("crane", {})
	if state.is_empty() or not _spots.has(state["spot"]):
		return
	if state["spot"] != _at:
		_move_to(state["spot"])
	_travel()
	crane.show_state(state, step)


## The first frame puts the crane on its spot; a later change of spot sinks it where it stood,
## then lifts it at the new one. Counted in frames, never in wall time, so a test can step it.
func _move_to(spot: int) -> void:
	var first := _at < 0
	_at = spot
	_place = _spots[spot]
	if first:
		crane.global_transform = _place
		crane.visible = true
		return
	_sink_left = SINK_SECONDS


func _travel() -> void:
	if _sink_left > 0.0:
		_sink_left -= step
		var sunk := 1.0 - clampf(_sink_left / SINK_SECONDS, 0.0, 1.0)
		crane.position.y = _rest_y - SINK_DEPTH * sunk
		if _sink_left <= 0.0:
			_rest_y = _place.origin.y
			crane.global_transform = _place
			crane.position.y = _rest_y - SINK_DEPTH
			_rise_left = RISE_SECONDS
	elif _rise_left > 0.0:
		_rise_left -= step
		var lifted := 1.0 - clampf(_rise_left / RISE_SECONDS, 0.0, 1.0)
		crane.position.y = _rest_y - SINK_DEPTH * (1.0 - smoothstep(0.0, 1.0, lifted))
