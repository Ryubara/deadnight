class_name ClientState
extends RefCounted
## What a client knows about the night: the latest frame and the events it has heard. The
## autopilot decides from this, the debug readout prints it, and the HUD (#89) will bind to the
## same events. It reads no game object.

signal event_received(event: Dictionary)

var player_id := 1
var frame: Dictionary = {}
## The dead of the latest frame, decoded once for the process (`ZombieCodec.decode_shared`): the
## list and its entries are shared with every other client, so a reader never changes them.
var zombies: Array[Dictionary] = []
var over := false
## The server closed the night after its intermission (`night_closed`): everyone goes back.
var closed := false
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
## Player id -> the level of each seat that holds an account, as the server says it (the WELCOME's
## `levels`, `account_seated`, `account_left` and `level_up`). A bot has none. Read the level over a
## head and the scoreboard from it.
var levels: Dictionary = {}
## This player's XP as the server counts it: the account's raw total (the WELCOME's `account_xp`,
## then every `xp_gained`), and the XP of this night so far.
var account_xp := 0
var night_xp := 0
## The `xp_gained` events heard.
var xp_events := 0


## Keeps the names a WELCOME's snapshot carries (`names`: player id -> name).
func load_names(snapshot: Dictionary) -> void:
	var held: Variant = snapshot.get("names", {})
	names.clear()
	if typeof(held) != TYPE_DICTIONARY:
		return
	for id: Variant in held:
		names[int(id)] = str(held[id])


## Keeps the levels and this player's raw XP a WELCOME's snapshot carries.
func load_levels(snapshot: Dictionary) -> void:
	levels.clear()
	var held: Variant = snapshot.get("levels", {})
	if typeof(held) == TYPE_DICTIONARY:
		for id: Variant in held:
			levels[int(id)] = int(held[id])
	account_xp = int(snapshot.get("account_xp", 0))


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
			zombies = ZombieCodec.decode_shared(event["zombies"])
		&"player_named":
			names[int(event["player_id"])] = str(event["name"])
		&"round_started":
			rounds_started += 1
		&"xp_gained":
			xp_events += 1
			if event["player_id"] == player_id:
				account_xp = event["total"]
				night_xp = event["xp"]
		&"level_up":
			levels[int(event["player_id"])] = int(event["level"])
		&"account_seated":
			levels[int(event["player_id"])] = int(event["level"])
		&"account_left":
			levels.erase(int(event["player_id"]))
		&"game_over":
			over = true
			round_reached = event["round_reached"]
		&"night_closed":
			closed = true
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


## Whole seconds of the end-of-night intermission left, as the server's last frame says (-1 while
## the night is on). Every client counts the end by it, so they stay in step with the server.
func over_left() -> int:
	return int(frame.get("over_left", -1))


func points() -> int:
	return me().get("points", 0)


func is_active() -> bool:
	return phase() == GameRules.Phase.ACTIVE
