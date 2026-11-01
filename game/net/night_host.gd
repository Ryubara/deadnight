class_name NightHost
extends Node
## The game server: one night hosted over WebSocket for up to `MAX_PLAYERS` players. It is what
## `godot --headless --path game -- --server [--port N]` runs (`Main` starts it), and what a test
## can add to a scene to have a server in the same process.
##
## Each physics step it reads what the clients sent (`NetWire`), steps the `NightServer`, and every
## `SEND_EVERY` steps tells each client the events since the last time and the frame, as a
## difference against the frame that client had (`FrameDelta`). The first player to arrive starts
## the night; when the last one leaves, the next night is built afresh (a night is not resumed).
## Players get the lowest free id of 1 to 4, which is also their seat in the lot.
##
## The server speaks plain `ws://`: on Railway the edge terminates TLS and clients use `wss://`.
## It reads its port from the command line (`--port N`) or `$PORT`, and logs one JSON object a line.

signal player_joined(player_id: int)
signal player_left(player_id: int)

const MAX_PLAYERS := 4
## A TICK goes out every this many steps: 2 is 30 a second at the 60 Hz step.
const SEND_EVERY := 2
## Steps a refused client has to read why before the server closes the connection.
const REFUSAL_GRACE := 30
## Seconds between the log's stats lines.
const STATS_EVERY := 10.0

## Set before the node enters the tree.
var port := NetWire.DEFAULT_PORT
## The seed of the night's dice; -1 draws one for every night.
var seed_value := -1
var rules_tuning: RulesTuning
var log_enabled := true

var listener := WsListener.new()
var world: NightWorld
var server: NightServer
## False while a night is being built.
var serving := false
## Steps taken, and milliseconds spent in them (the work, not the waiting), for the stats.
var steps := 0
var work_ms := 0.0
var worst_ms := 0.0
## The nights built so far.
var nights := 0

var _peers: Dictionary[int, HostPeer] = {}
var _by_player: Dictionary[int, HostPeer] = {}
var _events: Array[Dictionary] = []
var _stats_at := 0.0
var _stats_bytes := 0
var _stats_steps := 0
var _stats_work := 0.0


func _ready() -> void:
	listener.peer_connected.connect(_on_connected)
	listener.peer_disconnected.connect(_on_disconnected)
	listener.packet_received.connect(_on_packet)
	var failed := listener.listen(port)
	if failed != OK:
		_log("listen_failed", {"port": port, "error": error_string(failed)})
		get_tree().quit(1)
		return
	await _build_night()
	_log("listening", {"port": listener.port(), "players_max": MAX_PLAYERS, "tick_hz": _hz()})


func _exit_tree() -> void:
	listener.close()
	if server != null:
		server.close()


func _physics_process(_delta: float) -> void:
	if not serving:
		return
	var began := Time.get_ticks_usec()
	listener.poll()
	if server == null:
		return
	var events := server.step(Night.STEP)
	var frame: Dictionary = events.pop_back()
	_events.append_array(events)
	steps += 1
	if steps % SEND_EVERY == 0:
		_send_ticks(frame)
	var spent := (Time.get_ticks_usec() - began) / 1000.0
	work_ms += spent
	worst_ms = maxf(worst_ms, spent)
	_stats_work += spent
	_close_refused()
	_stats_steps += 1
	_log_stats()
	if _peers.is_empty() and nights > 0 and _night_began():
		_rebuild()


func player_count() -> int:
	return _by_player.size()


## Whether the first player has arrived and started the night.
func _night_began() -> bool:
	return server.rules.phase != GameRules.Phase.IDLE


func _build_night() -> void:
	serving = false
	world = NightWorld.new()
	add_child(world)
	await world.build()
	var chosen := seed_value if seed_value >= 0 else randi()
	server = NightServer.new(world, chosen, null, rules_tuning)
	_events.clear()
	nights += 1
	serving = true
	_log("night_ready", {"night": nights, "seed": chosen})


## The last player left a night that began: a new lot, new rules, a new seed.
func _rebuild() -> void:
	server.close()
	world.queue_free()
	await _build_night()


func _hz() -> int:
	return roundi(1.0 / Night.STEP)


# --- Connections ---


func _on_connected(transport_id: int) -> void:
	_peers[transport_id] = HostPeer.new(transport_id)


func _on_disconnected(transport_id: int) -> void:
	var peer: HostPeer = _peers.get(transport_id)
	_peers.erase(transport_id)
	if peer == null or peer.player_id == 0:
		return
	_by_player.erase(peer.player_id)
	if server != null:
		_collect(server.apply({"type": NightServer.LEAVE, "player_id": peer.player_id}))
	_log("left", {"player": peer.player_id, "players": _by_player.size()})
	player_left.emit(peer.player_id)


func _on_packet(transport_id: int, data: PackedByteArray) -> void:
	var peer: HostPeer = _peers.get(transport_id)
	if peer == null or data.is_empty() or server == null:
		return
	if data[0] == NetWire.Type.HELLO:
		_hello(peer, data)
		return
	if peer.player_id == 0:
		return
	match data[0]:
		NetWire.Type.COMMAND:
			var command := NetWire.read_command(data)
			if command != null:
				server.submit(peer.player_id, command)
		NetWire.Type.PING:
			if data.size() == 5:
				listener.send(transport_id, NetWire.pong(data.decode_u32(1), server.tick_count))
		LookWire.Type.LOOK:
			var action := {"type": NightServer.LOOK, "player_id": peer.player_id, "packet": data}
			_collect(server.apply(action, peer.player_id))


func _hello(peer: HostPeer, data: PackedByteArray) -> void:
	if peer.player_id != 0:
		return
	if data.size() != 2 or data[1] != NetWire.VERSION:
		_refuse(peer, NetWire.Refusal.VERSION)
		return
	var player_id := _free_player_id()
	if player_id == 0:
		_refuse(peer, NetWire.Refusal.FULL)
		return
	peer.player_id = player_id
	_by_player[player_id] = peer
	_collect(server.apply({"type": NightServer.JOIN, "player_id": player_id, "local": false}))
	if not _night_began():
		_collect(server.apply({"type": NightServer.START_NIGHT}))
	listener.send(peer.transport_id, NetWire.welcome(player_id, _hz(), server.rules.to_dict()))
	_log("joined", {"player": player_id, "players": _by_player.size()})
	player_joined.emit(player_id)


## A refused client is given a moment to read why and hang up itself; then we do.
func _refuse(peer: HostPeer, reason: NetWire.Refusal) -> void:
	listener.send(peer.transport_id, NetWire.refused(reason))
	peer.close_at = steps + REFUSAL_GRACE
	_log("refused", {"reason": NetWire.Refusal.keys()[reason - 1]})


func _close_refused() -> void:
	for peer: HostPeer in _peers.values():
		if peer.close_at >= 0 and steps >= peer.close_at:
			peer.close_at = -1
			listener.disconnect_peer(peer.transport_id)


func _free_player_id() -> int:
	for id in range(1, MAX_PLAYERS + 1):
		if not _by_player.has(id):
			return id
	return 0


# --- Ticks ---


func _collect(events: Array) -> void:
	for event: Dictionary in events:
		_events.append(event)


## Every event goes to every client, except a look packet, which is for one.
func _is_for(event: Dictionary, player_id: int) -> bool:
	return event["type"] != NightServer.LOOK_PACKET or event["to"] == player_id


func _send_ticks(frame: Dictionary) -> void:
	for peer: HostPeer in _by_player.values():
		var out: Array = _events.filter(
			func(event: Dictionary) -> bool: return _is_for(event, peer.player_id)
		)
		out.append(FrameDelta.diff(peer.last_frame, frame))
		peer.last_frame = frame
		listener.send(peer.transport_id, NetWire.tick(server.tick_count, out))
	_events.clear()


# --- Log ---


func _log_stats() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _stats_at:
		return
	if _stats_at > 0.0 and _by_player.size() > 0:
		var seconds := STATS_EVERY
		_log(
			"stats",
			{
				"players": _by_player.size(),
				"step": server.tick_count,
				"out_bytes_per_s": roundi((listener.bytes_out - _stats_bytes) / seconds),
				"work_ms_mean": snappedf(_stats_work / maxf(_stats_steps, 1), 0.01),
				"work_ms_worst": snappedf(worst_ms, 0.1),
				"zombies": server.sim.zombies.size(),
				"round": server.rules.round_number,
			}
		)
	_stats_at = now + STATS_EVERY
	_stats_bytes = listener.bytes_out
	_stats_work = 0.0
	_stats_steps = 0
	worst_ms = 0.0


func _log(event: String, fields: Dictionary = {}) -> void:
	if not log_enabled:
		return
	var line := {"event": event, "t": snappedf(Time.get_ticks_msec() / 1000.0, 0.01)}
	line.merge(fields)
	print(JSON.stringify(line))


## One connection to the server.
class HostPeer:
	extends RefCounted
	var transport_id: int
	## 0 until the client has said hello and been given a seat.
	var player_id := 0
	## The frame this client last had, the baseline of the next delta.
	var last_frame: Dictionary = {}
	## The step at which a refused client is hung up on, or -1.
	var close_at := -1

	func _init(p_transport_id: int) -> void:
		transport_id = p_transport_id
