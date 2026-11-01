class_name WorldMirror
extends RefCounted
## Makes a client's copy of the lot look like the server's, from frames alone: the doors that stand
## open, the boards across each breach and the breaker posts and lamps of each circuit. A server's
## rules drive these on the machine that runs them (`NightWorld.bind`); a client has no rules, and a
## player who joins in the middle has heard none of the events, so every frame is enough to catch
## up.

var _world: NightWorld
var _view: NightView
var _boards: Dictionary[StringName, int] = {}
var _circuits: Dictionary[StringName, bool] = {}


func _init(world: NightWorld, view: NightView) -> void:
	_world = world
	_view = view


func follow(frame: Dictionary) -> void:
	if not is_instance_valid(_world):
		return
	for door_id: StringName in frame["doors"]:
		_world.doors.open(door_id)
	var barricades: Dictionary = frame["barricades"]
	for id: Variant in barricades:
		var key := StringName(id)
		var boards: int = barricades[id]
		var barricade := _world.barricade(key)
		if barricade != null and _boards.get(key, -1) != boards:
			barricade.set_boards(boards, _boards.has(key))
			_boards[key] = boards
	var circuits: Dictionary = frame["circuits"]
	for id: Variant in circuits:
		var key := StringName(id)
		var on: bool = circuits[id]
		if _circuits.get(key) == on:
			continue
		_circuits[key] = on
		var post := _world.switches.post(key)
		if post != null:
			post.set_on(on)
		if _view.lamps != null:
			_view.lamps.apply_event({"type": &"circuit_changed", "circuit_id": key, "on": on})
