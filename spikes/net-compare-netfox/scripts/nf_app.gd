extends Node
## Entry for the netfox comparison: `--server` or `--client`, `--url=`, `--port=`, `--zombies=`,
## `--bot-seed=`,
## `--run-seconds=`. WebSocketMultiplayerPeer underneath (netfox is transport-agnostic);
## rollback for the
## players, StateSynchronizer for the zombies, a MultiplayerSpawner to create both on every peer.

var _args: NetArgs
var _spawner := MultiplayerSpawner.new()
var _entities := Node.new()
var _sim := GameSim.new(1)
var _sampler: InputSampler
var _next_player_id := 1
var _stats := ClientStats.new()
var _me: NfPlayer
var _last_pos := Vector2i.ZERO
var _last_tick := 0
var _have_last := false


func _ready() -> void:
	_args = NetArgs.new()
	Engine.max_fps = 60
	NfPlayer.tuned = _args.has("tuned")
	_entities.name = "Entities"
	add_child(_entities)
	_spawner.name = "Spawner"
	_spawner.spawn_path = NodePath("../Entities")
	_spawner.spawn_function = _spawn
	add_child(_spawner)
	if _args.has("run-seconds"):
		get_tree().create_timer(_args.get_float("run-seconds")).timeout.connect(_finish)
	if _args.has("server"):
		_start_server()
	else:
		_start_client()


func _spawn(spawn_data: Array) -> Node:
	if spawn_data[1] == 0:
		var zombie := NfZombie.new()
		zombie.setup(spawn_data)
		zombie.add_to_group(&"nf_entities")
		return zombie
	var player := NfPlayer.new()
	player.setup(spawn_data, _sampler, multiplayer.get_unique_id())
	player.add_to_group(&"nf_entities")
	return player


func _start_server() -> void:
	var peer := WebSocketMultiplayerPeer.new()
	var port := _args.get_int("port", NetArgs.DEFAULT_PORT)
	if peer.create_server(port) != OK:
		push_error("server could not listen on %d" % port)
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	_sim = GameSim.new(_args.get_int("seed", 1))
	_sim.add_zombies(_args.get_int("zombies"))
	for id in _sim.players.keys():
		_spawn_entity(id, 0)
	multiplayer.peer_connected.connect(_on_peer_connected)
	print("[nf-server] tick %d Hz, listening on %d" % [NetworkTime.tickrate, port])


func _on_peer_connected(peer: int) -> void:
	var id := _next_player_id
	_next_player_id += 1
	_sim.add_player(id)
	_spawn_entity(id, peer)
	print("[nf-server] player %d joined (peer %d)" % [id, peer])


func _spawn_entity(id: int, peer: int) -> void:
	_spawner.spawn([id, peer, _sim.players[id].x, _sim.players[id].y])


func _start_client() -> void:
	_sampler = InputSampler.new(_args.get_int("bot-seed", 0))
	var peer := WebSocketMultiplayerPeer.new()
	var url := _args.get_string("url", "ws://127.0.0.1:%d" % NetArgs.DEFAULT_PORT)
	if peer.create_client(url) != OK:
		push_error("client could not connect to %s" % url)
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	NetworkTime.after_tick_loop.connect(_after_ticks)
	print("[nf-client] connecting to %s" % url)


## How far did the last tick(s) move our own player from what its own input explains: the visible
## correction when netfox rewinds and replays. Comparable to the own-protocol client's correction.
func _after_ticks() -> void:
	if _me == null:
		for node in get_tree().get_nodes_in_group(&"nf_players"):
			if node.owner_peer == multiplayer.get_unique_id():
				_me = node
		return
	if _have_last and NetworkTime.tick - _last_tick == 1:  # a frame that ran exactly one tick
		var expected := GameSim.integrate(_last_pos, _me.input.dir)
		_stats.add_correction_cm(Vector2(_me.sim_pos - expected).length())
		_stats.snapshots += 1
	_last_pos = _me.sim_pos
	_last_tick = NetworkTime.tick
	_have_last = true


func _finish() -> void:
	if not _args.has("server"):
		_stats.add_rtt_ticks(roundi(NetworkTimeSynchronizer.rtt * GameSim.TICK_RATE))
		print(_stats.summary(_me.id if _me else 0))
	get_tree().quit()
