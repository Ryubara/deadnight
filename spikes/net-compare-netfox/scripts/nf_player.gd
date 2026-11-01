class_name NfPlayer
extends Node
## A player under netfox rollback: the server, and every client for its own player, run
## `_rollback_tick`
## with the same shared movement; when the server's state for a past tick arrives, netfox
## rewinds and
## re-runs the ticks since.

## Set from the command line (`--tuned`) on every peer: send inputs to the server only.
static var tuned := false

var id := 0
var owner_peer := 0
var sim_pos := Vector2i.ZERO
var input: NfInput
var synchronizer: RollbackSynchronizer


func setup(spawn_data: Array, sampler: InputSampler, local_peer: int) -> void:
	id = spawn_data[0]
	owner_peer = spawn_data[1]
	name = "p%d" % id
	add_to_group(&"nf_players")
	sim_pos = Vector2i(spawn_data[2], spawn_data[3])
	input = NfInput.new()
	input.name = "Input"
	input.set_multiplayer_authority(owner_peer)
	if owner_peer == local_peer:
		input.sampler = sampler
	add_child(input)
	synchronizer = RollbackSynchronizer.new()
	synchronizer.name = "RollbackSynchronizer"
	synchronizer.root = self
	synchronizer.state_properties = [":sim_pos"] as Array[String]
	synchronizer.input_properties = ["Input:dir"] as Array[String]
	synchronizer.enable_prediction = true
	synchronizer.enable_input_broadcast = not tuned
	add_child(synchronizer)


func _rollback_tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
	var others: Array[Vector2i] = []
	for node in get_tree().get_nodes_in_group(&"nf_entities"):
		if node != self:
			others.append(node.sim_pos)
	sim_pos = GameSim.separate(GameSim.integrate(sim_pos, input.dir), others)
