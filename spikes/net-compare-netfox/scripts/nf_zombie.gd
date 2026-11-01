class_name NfZombie
extends Node
## A zombie under netfox: simulated on the server only, its position sent by a StateSynchronizer.

var id := 0
var sim_pos := Vector2i.ZERO


func setup(spawn_data: Array) -> void:
	id = spawn_data[0]
	name = "z%d" % id
	sim_pos = Vector2i(spawn_data[2], spawn_data[3])
	var synchronizer := StateSynchronizer.new()
	synchronizer.name = "StateSynchronizer"
	synchronizer.root = self
	synchronizer.properties = [":sim_pos"] as Array[String]
	add_child(synchronizer)
	NetworkTime.on_tick.connect(_tick)


func _tick(_delta: float, _tick_number: int) -> void:
	if not multiplayer.is_server():
		return
	var targets: Array[Vector2i] = []
	for player in get_tree().get_nodes_in_group(&"nf_players"):
		targets.append(player.sim_pos)
	sim_pos = GameSim.zombie_next(sim_pos, targets)
