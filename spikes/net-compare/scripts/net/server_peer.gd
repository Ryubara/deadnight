class_name ServerPeer
extends RefCounted
## What the server remembers about one connected client.

const HISTORY_LIMIT := 64

var transport_id := 0
var player_id := 0
var last_applied_seq := 0
var ack_tick := 0  # the newest snapshot tick this client says it has
var queue: Array[Array] = []  # [seq, dir] waiting to be applied, oldest first
## snapshot tick -> the state we sent, the baselines for deltas
var sent: Dictionary[int, Dictionary] = {}


func _init(transport_id_value: int, player_id_value: int) -> void:
	transport_id = transport_id_value
	player_id = player_id_value


## Queues inputs we have not seen yet (redundant resends and reordered packets are skipped).
func enqueue(first_seq: int, dirs: Array[Vector2i]) -> void:
	var newest: int = queue.back()[0] if not queue.is_empty() else last_applied_seq
	for i in dirs.size():
		var seq := first_seq + i
		if seq > newest:
			queue.append([seq, dirs[i]])
			newest = seq


func remember(tick: int, state: Dictionary[int, Vector2i]) -> void:
	sent[tick] = state
	for old_tick in sent.keys():
		if old_tick < ack_tick or sent.size() > HISTORY_LIMIT:
			sent.erase(old_tick)
