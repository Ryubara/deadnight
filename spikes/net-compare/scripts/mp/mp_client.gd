class_name MpClient
extends Node
## The client on the built-in MultiplayerAPI. Prediction and reconciliation are still ours: the
## engine only
## delivers "the server's position and last applied input" for each entity. It carries no
## snapshot tick,
## so other entities are interpolated on local arrival time.

const PING_EVERY_TICKS := 15
const REPORT_EVERY_TICKS := GameSim.TICK_RATE * 2
const SAMPLE_LIMIT := 16
const INTERP_SECONDS := 0.1

var _world: MpWorld
var _sampler: InputSampler
var _stats := ClientStats.new()
var _me: MpEntity
var _playing := false  # true after the first authoritative update of our own entity
var _tick := 0
var _seq := 0
var _predicted := Vector2i.ZERO
var _pending: Array[Array] = []
var _pings: Dictionary[int, bool] = {}
var _remotes: Dictionary[MpEntity, Array] = {}  # entity -> [[seconds, Vector2], ...]


func start(world: MpWorld, url: String, sampler: InputSampler) -> void:
	_world = world
	_sampler = sampler
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_client(url)
	if error != OK:
		push_error("client could not connect to %s: %s" % [url, error_string(error)])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	world.entity_spawned.connect(_on_entity_spawned)
	world.pong_received.connect(_on_pong)
	print("[mp-client] connecting to %s" % url)


## Single-player: no peer to connect; the server in this process spawns our entity.
func start_offline(world: MpWorld, sampler: InputSampler) -> void:
	_world = world
	_sampler = sampler
	world.entity_spawned.connect(_on_entity_spawned)
	world.pong_received.connect(_on_pong)


func final_report() -> String:
	var line := _stats.summary(_me.id if _me else 0)
	if _me and multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		line += (
			"\nLOCAL player=%d inputs_sent=%d applied=%d pos=%s zombies=%d"
			% [_me.id, _seq, _me.ack_seq, _me.sim_pos, _world.entities.get_child_count() - 1]
		)
	return line


func _physics_process(_delta: float) -> void:
	if _world == null:
		return
	_tick += 1
	if _playing:
		_seq += 1
		var dir := _sampler.sample()
		_pending.append([_seq, dir])
		_predicted = GameSim.integrate(_predicted, dir)
		if MpEntity.client_auth:
			_me.sim_pos = _predicted  # the engine relays this to the server and, through it, to the others
		else:
			_world.submit_input.rpc_id(1, _seq, dir)
		if (
			_tick % PING_EVERY_TICKS == 0
			and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer
		):
			_pings[_tick] = true
			_world.ping.rpc_id(1, _tick)
	if _tick % REPORT_EVERY_TICKS == 0:
		_stats.roll_window()


func _process(_delta: float) -> void:
	var at := Time.get_ticks_msec() / 1000.0 - INTERP_SECONDS
	for entity in _remotes:
		_sample_remote(_remotes[entity], at)


func _on_entity_spawned(node: Node) -> void:
	var entity := node as MpEntity
	if entity == null:
		return
	if entity.owner_peer == multiplayer.get_unique_id():
		_me = entity
		# Client-owned or offline: we are the authority, so no first update will arrive.
		_playing = MpEntity.client_auth or multiplayer.multiplayer_peer is OfflineMultiplayerPeer
		_predicted = entity.sim_pos
		entity.updated.connect(_reconcile)
		return
	_remotes[entity] = []
	entity.updated.connect(func() -> void: _collect(entity))
	entity.tree_exiting.connect(func() -> void: _remotes.erase(entity))


func _reconcile() -> void:
	if not _playing:
		_playing = true  # the spawn packet can carry a stale value: start from the first real update
		_predicted = _me.sim_pos
		return
	_stats.note_update()
	_stats.snapshots += 1
	while not _pending.is_empty() and _pending[0][0] <= _me.ack_seq:
		_pending.pop_front()
	var replayed := _me.sim_pos
	for item in _pending:
		replayed = GameSim.integrate(replayed, item[1])
	_stats.add_correction_cm(Vector2(replayed - _predicted).length())
	_predicted = replayed


func _collect(entity: MpEntity) -> void:
	var samples: Array = _remotes[entity]
	samples.append([Time.get_ticks_msec() / 1000.0, Vector2(entity.sim_pos)])
	while samples.size() > SAMPLE_LIMIT:
		samples.pop_front()


func _on_pong(client_tick: int) -> void:
	if _pings.erase(client_tick):
		_stats.add_rtt_ticks(_tick - client_tick)


func _sample_remote(samples: Array, at_seconds: float) -> Vector2:
	if samples.is_empty():
		return Vector2.ZERO
	for i in range(samples.size() - 1, 0, -1):
		var a: Array = samples[i - 1]
		var b: Array = samples[i]
		if at_seconds >= a[0] and at_seconds <= b[0]:
			return a[1].lerp(b[1], (at_seconds - a[0]) / maxf(b[0] - a[0], 0.0001))
	return samples.back()[1]
