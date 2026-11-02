class_name ClientState
extends RefCounted
## What a client knows about the night: the latest frame and the events it has heard. The
## autopilot decides from this, the debug readout prints it, and the HUD (#89) will bind to the
## same events. It reads no game object.

signal event_received(event: Dictionary)

var player_id := 1
var frame: Dictionary = {}
var zombies: Array[Dictionary] = []
var over := false
var round_reached := 0
var kills := 0
var points_earned := 0
var points_spent := 0
var doors_bought := 0
## What the local player has bought, by shop item id: how many times.
var bought: Dictionary = {}
var shots := 0
var rounds_started := 0
var damage_taken := 0.0
var last_event: Dictionary = {}
## Player id -> the name that seat shows, as the server says it (the WELCOME's `names` and the
## `player_named` events): the same on every client. A seat without a name is not in it.
var names: Dictionary = {}


## Keeps the names a WELCOME's snapshot carries (`names`: player id -> name).
func load_names(snapshot: Dictionary) -> void:
	var held: Variant = snapshot.get("names", {})
	names.clear()
	if typeof(held) != TYPE_DICTIONARY:
		return
	for id: Variant in held:
		names[int(id)] = str(held[id])


func apply_events(events: Array) -> void:
	for event: Dictionary in events:
		var began := PerfProbe.begin()
		_apply(event)
		event_received.emit(event)
		if PerfProbe.enabled:
			PerfProbe.end(StringName("event.%s" % event["type"]), began)
			PerfProbe.count(StringName("ev.%s" % event["type"]))


func _apply(event: Dictionary) -> void:
	match event["type"]:
		&"frame":
			frame = event
			zombies = ZombieCodec.decode(event["zombies"])
		&"player_named":
			names[int(event["player_id"])] = str(event["name"])
		&"round_started":
			rounds_started += 1
		&"game_over":
			over = true
			round_reached = event["round_reached"]
		&"zombie_removed":
			if event["killer_id"] == player_id:
				kills += 1
			if event["cause"] == &"killed":
				PerfProbe.count(&"kill")
		&"points_changed":
			if event["player_id"] == player_id:
				if event["delta"] > 0:
					points_earned += event["delta"]
				else:
					points_spent -= event["delta"]
		&"purchase_made":
			if event["player_id"] == player_id:
				bought[event["item_id"]] = bought.get(event["item_id"], 0) + 1
				if String(event["item_id"]).begins_with("door_"):
					doors_bought += 1
		&"shot_fired":
			if event["shooter_id"] == player_id:
				shots += 1
		&"player_damaged":
			if event["player_id"] == player_id:
				damage_taken += event["damage"]
	last_event = event


func has_frame() -> bool:
	return not frame.is_empty()


func me() -> Dictionary:
	return frame.get("players", {}).get(player_id, {})


func position() -> Vector3:
	return me().get("pos", Vector3.ZERO)


func phase() -> int:
	return frame.get("phase", GameRules.Phase.IDLE)


func round_number() -> int:
	return frame.get("round", 0)


func points() -> int:
	return me().get("points", 0)


func is_active() -> bool:
	return phase() == GameRules.Phase.ACTIVE
