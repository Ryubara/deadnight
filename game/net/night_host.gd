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
## A player's socket dropped and the seat is held for them; and they came back on a new one.
signal player_away(player_id: int)
signal player_resumed(player_id: int)

const MAX_PLAYERS := 4
## A TICK goes out every this many steps: 2 is 30 a second at the 60 Hz step.
const SEND_EVERY := 2
## Steps a refused client has to read why before the server closes the connection.
const REFUSAL_GRACE := 30
## Seconds between the log's stats lines.
const STATS_EVERY := 10.0
## Connections open at once, counting those that have not said hello; the next is hung up on.
const MAX_CONNECTIONS := 16
## Seconds a connection has to say hello before it is hung up on.
const HELLO_WITHIN := 10.0
## Seconds the seat of a player whose socket dropped is held, standing still in the lot, for them
## to come back with their resume token.
const RESUME_WITHIN := 30.0

## Set before the node enters the tree.
var port := NetWire.DEFAULT_PORT
## The seed of the night's dice; -1 draws one for every night.
var seed_value := -1
var rules_tuning: RulesTuning
var log_enabled := true
## Seconds a connection has to say hello (`HELLO_WITHIN`; a test sets it shorter).
var hello_within := HELLO_WITHIN
## Seconds a dropped player's seat is held (`RESUME_WITHIN`); 0 frees it at once.
var resume_within := RESUME_WITHIN
## The place to say who may join: called with `(transport_id: int, version: int)` once a client
## has said hello with a version this build takes, it returns 0 to let the client in or a
## `NetWire.Refusal` to turn it away. Unset, everyone is let in (the platform backend's ticket check
## plugs in here).
var admit: Callable

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
## Peers hung up on for breaking `PeerLimits`.
var kicked_count := 0

var _peers: Dictionary[int, HostPeer] = {}
var _by_player: Dictionary[int, HostPeer] = {}
## Players whose socket dropped, by id: their seat, kept until they come back or the time is up.
var _away: Dictionary[int, Away] = {}
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
	_close_silent()
	_expire_away()
	_stats_steps += 1
	_log_stats()
	if _peers.is_empty() and _away.is_empty() and nights > 0 and _night_began():
		_rebuild()


func player_count() -> int:
	return _by_player.size()


## Players whose seat is held while their socket is down.
func away_count() -> int:
	return _away.size()


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
	server.drawn_bodies = false
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
	if _peers.size() >= MAX_CONNECTIONS:
		_log("refused", {"reason": "CONNECTIONS"})
		listener.disconnect_peer(transport_id)
		return
	_peers[transport_id] = HostPeer.new(transport_id, _now())


func _on_disconnected(transport_id: int) -> void:
	var peer: HostPeer = _peers.get(transport_id)
	_peers.erase(transport_id)
	if peer == null or peer.player_id == 0:
		return
	_by_player.erase(peer.player_id)
	var on_purpose := listener.left_on_purpose(transport_id)
	if (
		server != null
		and resume_within > 0.0
		and not peer.kicked
		and not on_purpose
		and _night_began()
	):
		# The body stays where it is, with no commands coming (it stands still after a moment);
		# the player takes it back with the token, or the time runs out.
		_away[peer.player_id] = Away.new(peer.token, _now() + resume_within)
		_log("away", {"player": peer.player_id, "players": _by_player.size()})
		player_away.emit(peer.player_id)
		return
	_free_seat(peer.player_id)


## Frees a seat for good: the body leaves the lot and the id can be given to someone new.
func _free_seat(player_id: int) -> void:
	_away.erase(player_id)
	if server != null:
		_collect(server.apply({"type": NightServer.LEAVE, "player_id": player_id}))
	_log("left", {"player": player_id, "players": _by_player.size()})
	player_left.emit(player_id)


func _expire_away() -> void:
	var now := _now()
	for player_id in _away.keys():
		if now >= _away[player_id].until:
			_log("expired", {"player": player_id})
			_free_seat(player_id)


func _on_packet(transport_id: int, data: PackedByteArray) -> void:
	var peer: HostPeer = _peers.get(transport_id)
	if peer == null or server == null or peer.kicked:
		return
	var verdict := peer.limits.judge(data, _now())
	if verdict == PeerLimits.Verdict.DROP:
		return
	if verdict == PeerLimits.Verdict.KICK:
		_kick(peer)
		return
	if data[0] == NetWire.Type.HELLO:
		_hello(peer, data)
		return
	if peer.player_id == 0:
		_fault(peer)
		return
	match data[0]:
		NetWire.Type.COMMAND:
			var command := NetWire.read_command(data)
			if command == null:
				_fault(peer)
				return
			server.submit(peer.player_id, command)
		NetWire.Type.PING:
			if data.size() == 5:
				listener.send(transport_id, NetWire.pong(data.decode_u32(1), server.tick_count))
		LookWire.Type.LOOK:
			var action := {"type": NightServer.LOOK, "player_id": peer.player_id, "packet": data}
			_collect(server.apply(action, peer.player_id))


func _hello(peer: HostPeer, data: PackedByteArray) -> void:
	if peer.player_id != 0 or peer.refused:
		_fault(peer)
		return
	var hello := NetWire.read_hello(data)
	if not NetWire.accepts(hello["version"]):
		_refuse(peer, NetWire.Refusal.VERSION)
		return
	if admit.is_valid():
		var verdict: int = admit.call(peer.transport_id, hello["version"])
		if verdict != 0:
			_refuse(peer, verdict as NetWire.Refusal)
			return
	var resumed := _claim_seat(hello["token"])
	if resumed != 0:
		_resume(peer, resumed)
		return
	var player_id := _free_player_id()
	if player_id == 0:
		_refuse(peer, NetWire.Refusal.FULL)
		return
	peer.player_id = player_id
	peer.token = Crypto.new().generate_random_bytes(NetWire.TOKEN_SIZE)
	_by_player[player_id] = peer
	_collect(server.apply({"type": NightServer.JOIN, "player_id": player_id, "local": false}))
	if not _night_began():
		_collect(server.apply({"type": NightServer.START_NIGHT}))
	listener.send(
		peer.transport_id, NetWire.welcome(player_id, _hz(), peer.token, server.rules.to_dict())
	)
	_log("joined", {"player": player_id, "players": _by_player.size()})
	player_joined.emit(player_id)


## The id of the player this token is the seat of, taken from the held seats or (a client that
## came back before the server noticed its old socket was dead) from a live connection, which is
## hung up on; 0 when it is no one's.
func _claim_seat(token: PackedByteArray) -> int:
	if token.size() != NetWire.TOKEN_SIZE:
		return 0
	for player_id in _away:
		if _away[player_id].token == token:
			return player_id
	for player_id in _by_player:
		var old := _by_player[player_id]
		if old.token == token:
			old.player_id = 0
			_by_player.erase(player_id)
			listener.disconnect_peer(old.transport_id)
			return player_id
	return 0


## The player comes back on this connection: the same body, a new token, the rules as they are
## now and the looks again. The first frame it gets is whole (`last_frame` is empty).
func _resume(peer: HostPeer, player_id: int) -> void:
	_away.erase(player_id)
	peer.player_id = player_id
	peer.token = Crypto.new().generate_random_bytes(NetWire.TOKEN_SIZE)
	_by_player[player_id] = peer
	listener.send(
		peer.transport_id, NetWire.welcome(player_id, _hz(), peer.token, server.rules.to_dict())
	)
	_collect(server.apply({"type": NightServer.RESYNC, "player_id": player_id}))
	_log("resumed", {"player": player_id, "players": _by_player.size()})
	player_resumed.emit(player_id)


## A refused client is given a moment to read why and hang up itself; then we do.
func _refuse(peer: HostPeer, reason: NetWire.Refusal) -> void:
	listener.send(peer.transport_id, NetWire.refused(reason))
	peer.close_at = steps + REFUSAL_GRACE
	peer.refused = true
	_log("refused", {"reason": NetWire.Refusal.keys()[reason - 1]})


## The peer sent something the server cannot use (and `judge` did not catch): a strike.
func _fault(peer: HostPeer) -> void:
	if peer.limits.fault(_now()) == PeerLimits.Verdict.KICK:
		_kick(peer)


## Hangs up on a peer that kept breaking the limits; its seat is freed when the socket closes.
func _kick(peer: HostPeer) -> void:
	peer.kicked = true
	_log(
		"kicked",
		{
			"player": peer.player_id,
			"dropped": peer.limits.dropped,
			"malformed": peer.limits.malformed,
		}
	)
	listener.disconnect_peer(peer.transport_id)
	kicked_count += 1


## Connections that never said hello are not kept.
func _close_silent() -> void:
	var now := _now()
	for peer: HostPeer in _peers.values():
		if peer.player_id == 0 and not peer.kicked and now - peer.connected_at > hello_within:
			peer.kicked = true
			_log("refused", {"reason": "SILENT"})
			listener.disconnect_peer(peer.transport_id)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _close_refused() -> void:
	for peer: HostPeer in _peers.values():
		if peer.close_at >= 0 and steps >= peer.close_at:
			peer.close_at = -1
			listener.disconnect_peer(peer.transport_id)


func _free_player_id() -> int:
	for id in range(1, MAX_PLAYERS + 1):
		if not _by_player.has(id) and not _away.has(id):
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


## A seat held for a player whose socket dropped.
class Away:
	extends RefCounted
	var token: PackedByteArray
	## When the seat is given up (the host's clock, seconds).
	var until: float

	func _init(p_token: PackedByteArray, p_until: float) -> void:
		token = p_token
		until = p_until


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
	var refused := false
	var kicked := false
	## When the connection opened (seconds), for the time it has to say hello.
	var connected_at := 0.0
	var limits := PeerLimits.new()
	## What the client was given at WELCOME to take its seat back with.
	var token := PackedByteArray()

	func _init(p_transport_id: int, now: float = 0.0) -> void:
		transport_id = p_transport_id
		connected_at = now
