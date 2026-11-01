class_name GameServer
extends Node
## The authoritative server: a fixed-tick loop over a transport. Per tick it reads packets,
## applies every queued client input once and in order, then sends each client a snapshot (a
## delta against the last snapshot that client acknowledged, or a full one when it has no
## usable baseline). It knows nothing about sockets or scenes, so single-player runs it in-
## process over a loopback.

const MAX_INPUTS_PER_TICK := 6
const LOG_INTERVAL_TICKS := GameSim.TICK_RATE * 5

var snapshot_every := 1
var use_deltas := true

var _transport: ServerTransport
var _sim: GameSim
var _peers: Dictionary[int, ServerPeer] = {}
var _tick := 0
var _bytes_in := 0
var _bytes_out := 0
var _snapshot_bytes := 0
var _snapshots_sent := 0


func start(transport: ServerTransport, port: int, seed_value: int = 1, zombies: int = 0) -> void:
	_transport = transport
	_sim = GameSim.new(seed_value)
	_sim.add_zombies(zombies)
	var error := transport.listen(port)
	if error != OK:
		push_error("server could not listen on %d: %s" % [port, error_string(error)])
		get_tree().quit(1)
		return
	transport.peer_connected.connect(_on_peer_connected)
	transport.peer_disconnected.connect(_on_peer_disconnected)
	transport.packet_received.connect(_on_packet)
	print(
		(
			"[server] tick %d Hz, snapshot every %d tick(s), listening"
			% [GameSim.TICK_RATE, snapshot_every]
		)
	)


func _exit_tree() -> void:
	if _transport:
		_transport.close()


func _physics_process(_delta: float) -> void:
	if _transport == null:
		return
	_transport.poll()
	_tick += 1
	for peer in _peers.values():
		_apply_inputs(peer)
	_sim.step_zombies()
	if _tick % snapshot_every == 0:
		for peer in _peers.values():
			_send_snapshot(peer)
	if _tick % LOG_INTERVAL_TICKS == 0:
		_log()


func _on_peer_connected(_transport_id: int) -> void:
	pass  # a client is a player only after its HELLO


func _on_peer_disconnected(transport_id: int) -> void:
	var peer: ServerPeer = _peers.get(transport_id)
	if peer == null:
		return
	_peers.erase(transport_id)
	_sim.remove_player(peer.player_id)
	for other in _peers.values():
		# A leaver breaks every delta baseline that still contains it: force full snapshots.
		other.sent.clear()
	_broadcast(Protocol.event(Protocol.EventKind.LEFT, peer.player_id))
	print("[server] player %d left, %d in game" % [peer.player_id, _peers.size()])


func _on_packet(transport_id: int, data: PackedByteArray) -> void:
	_bytes_in += data.size()
	var message := Protocol.decode(data)
	if message.is_empty():
		return
	var peer: ServerPeer = _peers.get(transport_id)
	match message["type"]:
		Protocol.Type.HELLO:
			if peer == null:
				_on_hello(transport_id, message)
		Protocol.Type.INPUT:
			if peer:
				peer.ack_tick = maxi(peer.ack_tick, message["ack_tick"])
				peer.enqueue(message["first_seq"], message["dirs"])
		Protocol.Type.PING:
			_send(transport_id, Protocol.pong(message["client_tick"], _tick))


func _on_hello(transport_id: int, message: Dictionary) -> void:
	if message["version"] != Protocol.VERSION:
		print("[server] refusing a client speaking protocol %d" % message["version"])
		_transport.disconnect_peer(transport_id)
		return
	var player_id := _free_player_id()
	if player_id == 0:
		_transport.disconnect_peer(transport_id)
		return
	_peers[transport_id] = ServerPeer.new(transport_id, player_id)
	_sim.add_player(player_id)
	_send(transport_id, Protocol.welcome(player_id, GameSim.TICK_RATE, _tick))
	_broadcast(Protocol.event(Protocol.EventKind.JOINED, player_id))
	print("[server] player %d joined, %d in game" % [player_id, _peers.size()])


func _apply_inputs(peer: ServerPeer) -> void:
	var applied := 0
	while not peer.queue.is_empty() and applied < MAX_INPUTS_PER_TICK:
		var item: Array = peer.queue.pop_front()
		_sim.apply_input(peer.player_id, item[1])
		peer.last_applied_seq = item[0]
		applied += 1


func _send_snapshot(peer: ServerPeer) -> void:
	var state := _sim.snapshot()
	var baseline_tick := 0
	var entries := state
	if use_deltas and peer.sent.has(peer.ack_tick):
		var delta: Variant = _delta(peer.sent[peer.ack_tick], state)
		if delta != null:
			baseline_tick = peer.ack_tick
			entries = delta
	peer.remember(_tick, state)
	var packet := Protocol.snapshot(_tick, peer.last_applied_seq, baseline_tick, entries)
	_snapshot_bytes += packet.size()
	_snapshots_sent += 1
	_send(peer.transport_id, packet)


## The players that moved since `baseline`, as centimetre deltas (possibly none); null when a delta
## cannot express the change (a new player, or a move beyond one byte): then send a full snapshot.
func _delta(baseline: Dictionary, state: Dictionary[int, Vector2i]) -> Variant:
	var delta: Dictionary[int, Vector2i] = {}
	for id in state:
		if not baseline.has(id):
			return null
		var d: Vector2i = state[id] - baseline[id]
		if absi(d.x) > Protocol.DELTA_LIMIT_CM or absi(d.y) > Protocol.DELTA_LIMIT_CM:
			return null
		if d != Vector2i.ZERO:
			delta[id] = d
	return delta


func _send(transport_id: int, data: PackedByteArray) -> void:
	_bytes_out += data.size()
	_transport.send(transport_id, data)


func _broadcast(data: PackedByteArray) -> void:
	for peer in _peers.values():
		_send(peer.transport_id, data)


func _free_player_id() -> int:
	var used: Array[int] = []
	for peer in _peers.values():
		used.append(peer.player_id)
	for id in range(1, 256):
		if not used.has(id):
			return id
	return 0


func _log() -> void:
	var seconds := float(LOG_INTERVAL_TICKS) / GameSim.TICK_RATE
	var average := _snapshot_bytes / maxf(_snapshots_sent, 1.0)
	print(
		(
			"[server] tick=%d players=%d in=%.0f B/s out=%.0f B/s snapshot_avg=%.1f B"
			% [_tick, _peers.size(), _bytes_in / seconds, _bytes_out / seconds, average]
		)
	)
	_bytes_in = 0
	_bytes_out = 0
	_snapshot_bytes = 0
	_snapshots_sent = 0
