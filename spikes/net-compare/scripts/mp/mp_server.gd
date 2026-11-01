class_name MpServer
extends Node
## The authoritative server on the built-in MultiplayerAPI: the same GameSim as the own-protocol
## server,
## but replication, spawning and transport are the engine's. This code only moves state into the
## entity
## nodes once per tick.

const MAX_INPUTS_PER_TICK := 6

var _world: MpWorld
var _sim: GameSim
var _entities: Dictionary[int, MpEntity] = {}  # sim id -> entity
var _by_peer: Dictionary[int, Array] = {}  # peer -> [sim id, queue of [seq, dir], last applied seq]
var _next_player_id := 1


## Single-player: the default OfflineMultiplayerPeer is the server (id 1) and the only player.
func start_offline(world: MpWorld, seed_value: int, zombies: int) -> void:
	_start_common(world, seed_value, zombies)
	_on_peer_connected(multiplayer.get_unique_id())


func start(world: MpWorld, port: int, seed_value: int, zombies: int) -> void:
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_server(port)
	if error != OK:
		push_error("server could not listen on %d: %s" % [port, error_string(error)])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_start_common(world, seed_value, zombies)
	print("[mp-server] tick %d Hz, listening on %d" % [GameSim.TICK_RATE, port])


func _start_common(world: MpWorld, seed_value: int, zombies: int) -> void:
	_world = world
	_sim = GameSim.new(seed_value)
	world.input_received.connect(_on_input)
	_sim.add_zombies(zombies)
	for i in zombies:
		var id := GameSim.ZOMBIE_ID_BASE + 1 + i
		_entities[id] = world.spawn_entity([id, 0])


func _physics_process(_delta: float) -> void:
	if _world == null:
		return
	for state: Array in _by_peer.values():
		var applied := 0
		var queue: Array = state[1]
		while not queue.is_empty() and applied < MAX_INPUTS_PER_TICK:
			var item: Array = queue.pop_front()
			_sim.apply_input(state[0], item[1])
			state[2] = item[0]
			applied += 1
	_sim.step_zombies()
	for id in _entities:
		if not (MpEntity.client_auth and id < GameSim.ZOMBIE_ID_BASE):
			_entities[id].sim_pos = _sim.players[id]
	if MpEntity.client_auth:
		return  # the clients own their players: nothing to send back
	for state: Array in _by_peer.values():
		_entities[state[0]].ack_seq = state[2]


func _on_peer_connected(peer: int) -> void:
	var id := _next_player_id
	_next_player_id += 1
	_sim.add_player(id)
	_by_peer[peer] = [id, [], 0]
	_entities[id] = _world.spawn_entity([id, peer])
	_entities[id].sim_pos = _sim.players[id]
	print("[mp-server] player %d joined (peer %d), %d in game" % [id, peer, _by_peer.size()])


func _on_peer_disconnected(peer: int) -> void:
	var state: Array = _by_peer.get(peer, [])
	if state.is_empty():
		return
	_by_peer.erase(peer)
	_sim.remove_player(state[0])
	_entities[state[0]].queue_free()
	_entities.erase(state[0])


func _on_input(peer: int, seq: int, dir: Vector2i) -> void:
	var state: Array = _by_peer.get(peer, [])
	if state.is_empty():
		return
	var queue: Array = state[1]
	var newest: int = queue.back()[0] if not queue.is_empty() else state[2]
	if seq > newest:
		queue.append([seq, dir])
