class_name GameServer
extends Node
## The game-server process of the rooms: one WebSocket listener and several nights, one for each
## match the platform backend has given tickets for (`docs/research/platform-backend.md`).
##
## A night is a `NightHost` (a room), each in a `SubViewport` of its own so it has its own physics
## and navigation, sharing this node's listener. This node polls the listener once a step and
## routes: a new connection's first message is a HELLO, and its ticket (checked by
## `TicketVerifier`: signature, expiry, this server, used once) says which match it is for; the
## room of that match is built on the first ticket and freed when its night has begun and
## everyone has left. A HELLO with a resume token goes to the room that holds the seat, no ticket
## needed. Every few seconds the server tells the backend which matches it runs and how many
## players each has (`heartbeat`), and tells it when a match is over.
##
## The nights run one after the other in one thread, so their costs add up in one 16.7 ms tick:
## `capacity` (rooms a process takes) and `max_alive` are sized from that
## (`docs/research/crowd-budget.md`, "Rooms in one process"). Rooms put their heavy ticks on
## alternate halves of the frames (`_lighter_parity`).

signal room_opened(match_id: String)
signal room_closed(match_id: String)

## Rooms a process takes unless told otherwise.
const DEFAULT_CAPACITY := 4
## Seconds between heartbeats (the default of `heartbeat_every`).
const HEARTBEAT_EVERY := 5.0
## Connections that have not said hello yet; the next is hung up on.
const MAX_PENDING := 32
## Seconds a connection has to say hello, and an empty room that never began is kept.
const HELLO_WITHIN := 10.0
const IDLE_ROOM_SECONDS := 60.0
## Seconds a refused client has to read why before it is hung up on.
const REFUSAL_GRACE := 1.0

var port := NetWire.DEFAULT_PORT
var capacity := DEFAULT_CAPACITY
## The most zombies alive at once in a night here (`ServerConfig.max_alive`); 0 is the rules' own.
var max_alive := 0
var log_enabled := true
var rules_tuning: RulesTuning
## The seed of every room's dice; -1 draws one for each.
var seed_value := -1
## Who this server is to the backend: its id, the address players connect to and the path the
## Discord proxy maps to it.
var server_id := "gs-local"
var public_url := ""
var activity_path := "/server"
## The backend's address and the secret its game servers call with (empty: no heartbeat).
var backend_url := ""
var backend_secret := ""
var verifier: TicketVerifier
## Seconds a connection may take to say hello (a test sets it shorter).
var hello_within := HELLO_WITHIN
var idle_room_seconds := IDLE_ROOM_SECONDS
## Seconds between heartbeats (a test sets it shorter).
var heartbeat_every := HEARTBEAT_EVERY

var listener := WsListener.new()
var heartbeats_sent := 0
var refused_count := 0

var _rooms: Dictionary[String, NightHost] = {}
var _opened_at: Dictionary[String, float] = {}
var _building: Dictionary[String, bool] = {}
var _room_of: Dictionary[int, NightHost] = {}
var _pending: Dictionary[int, Pending] = {}
var _beat_at := 0.0


## A server set up from its environment (`ServerConfig`).
static func make(config: ServerConfig, p_port: int, p_seed: int = -1) -> GameServer:
	var server := GameServer.new()
	server.port = p_port
	server.seed_value = p_seed
	server.capacity = config.capacity
	server.max_alive = config.max_alive
	server.server_id = config.server_id
	server.public_url = config.public_url
	server.activity_path = config.activity_path
	server.backend_url = config.backend_url
	server.backend_secret = config.game_server_secret
	server.verifier = TicketVerifier.new(config.ticket_secret, config.server_id)
	return server


func _ready() -> void:
	listener.peer_connected.connect(_on_connected)
	listener.peer_disconnected.connect(_on_disconnected)
	listener.packet_received.connect(_on_packet)
	var failed := listener.listen(port)
	if failed != OK:
		_log("listen_failed", {"port": port, "error": error_string(failed)})
		get_tree().quit(1)
		return
	_log("listening", {"port": listener.port(), "capacity": capacity, "id": server_id})
	_heartbeat()


func _exit_tree() -> void:
	listener.close()


func _physics_process(_delta: float) -> void:
	listener.poll()
	var now := _now()
	for id: int in _pending.keys():
		var pending: Pending = _pending[id]
		if pending.close_at > 0.0 and now >= pending.close_at:
			pending.close_at = 0.0
			listener.disconnect_peer(id)
		elif pending.close_at == 0.0 and not pending.refused and now - pending.since > hello_within:
			pending.refused = true
			_log("refused", {"reason": "SILENT"})
			listener.disconnect_peer(id)
	for match_id: String in _rooms.keys():
		_close_if_done(match_id, now)
	if now >= _beat_at:
		_heartbeat()


## The match ids of the rooms this process runs.
func match_ids() -> Array[String]:
	var ids: Array[String] = []
	for match_id: String in _rooms:
		ids.append(match_id)
	return ids


func room_of_match(match_id: String) -> NightHost:
	return _rooms.get(match_id)


## Players in each room, as a `{match id: count}` for the heartbeat.
func players_by_match() -> Dictionary:
	var out := {}
	for match_id: String in _rooms:
		out[match_id] = _rooms[match_id].player_count()
	return out


## The round of each room, as a `{match id: round}` for the heartbeat.
func rounds_by_match() -> Dictionary:
	var out := {}
	for match_id: String in _rooms:
		out[match_id] = _rooms[match_id].round_number()
	return out


# --- Routing ---


func _on_connected(transport_id: int) -> void:
	if _pending.size() >= MAX_PENDING:
		listener.disconnect_peer(transport_id)
		return
	_pending[transport_id] = Pending.new(_now())


func _on_disconnected(transport_id: int) -> void:
	var room: NightHost = _room_of.get(transport_id)
	_room_of.erase(transport_id)
	_pending.erase(transport_id)
	if room != null and is_instance_valid(room):
		room.detach(transport_id)


func _on_packet(transport_id: int, data: PackedByteArray) -> void:
	var room: NightHost = _room_of.get(transport_id)
	if room != null:
		if is_instance_valid(room):
			room.receive(transport_id, data)
		return
	var pending: Pending = _pending.get(transport_id)
	if pending == null or pending.refused or pending.routing:
		return
	var verdict := pending.limits.judge(data, _now())
	if verdict == PeerLimits.Verdict.DROP:
		return
	if verdict == PeerLimits.Verdict.KICK or data[0] != NetWire.Type.HELLO:
		if verdict != PeerLimits.Verdict.KICK:
			verdict = pending.limits.fault(_now())
		if verdict == PeerLimits.Verdict.KICK:
			pending.refused = true
			listener.disconnect_peer(transport_id)
		return
	await _route(transport_id, pending, data)


## The first message of a connection: which room is this client for?
func _route(transport_id: int, pending: Pending, data: PackedByteArray) -> void:
	if not NetWire.accepts(NetWire.hello_version(data)):
		_refuse(transport_id, pending, NetWire.Refusal.VERSION, "VERSION")
		return
	var hello := NetWire.read_hello(data)
	if hello.is_empty():
		pending.limits.fault(_now())
		return
	for room: NightHost in _rooms.values():
		if room.owns_token(hello["token"]):
			_hand_over(transport_id, room, "", "", data)
			return
	var ticket: String = hello["ticket"]
	var admitted := (
		verifier.admit(ticket, int(Time.get_unix_time_from_system()))
		if verifier != null and not ticket.is_empty()
		else {"ok": false, "reason": "no ticket"}
	)
	if not admitted["ok"]:
		_refuse(transport_id, pending, NetWire.Refusal.DENIED, admitted["reason"])
		return
	var match_id: String = admitted["match"]
	pending.routing = true
	var room: NightHost = _rooms.get(match_id)
	if room == null:
		if _rooms.size() + _building.size() >= capacity and not _building.has(match_id):
			pending.routing = false
			_refuse(transport_id, pending, NetWire.Refusal.FULL, "ROOMS")
			return
		room = await _open_room(match_id, admitted.get("settings"))
	if not _pending.has(transport_id):
		return
	_hand_over(transport_id, room, admitted["user"], admitted["name"], data)


func _hand_over(
	transport_id: int, room: NightHost, user: String, user_name: String, hello: PackedByteArray
) -> void:
	_pending.erase(transport_id)
	_room_of[transport_id] = room
	room.attach(transport_id, user, user_name)
	room.receive(transport_id, hello)


func _refuse(transport_id: int, pending: Pending, reason: NetWire.Refusal, why: String) -> void:
	refused_count += 1
	listener.send(transport_id, NetWire.refused(reason))
	pending.refused = true
	pending.close_at = _now() + REFUSAL_GRACE
	_log("refused", {"reason": NetWire.Refusal.keys()[reason - 1], "why": why})


# --- Rooms ---


## Builds the night of a match (once: a second ticket of the same match waits for the first). The
## first ticket's `settings` (the host's rules, null for the usual ones) are the room's: every
## ticket of a match carries the same.
func _open_room(match_id: String, settings: MatchSettings = null) -> NightHost:
	if _rooms.has(match_id):
		return _rooms[match_id]
	if _building.has(match_id):
		while _building.has(match_id):
			await get_tree().physics_frame
		return _rooms[match_id]
	_building[match_id] = true
	var viewport := SubViewport.new()
	viewport.name = "Room_%s" % match_id.left(8)
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var room := NightHost.new()
	room.embedded = true
	room.listener = listener
	room.room_id = match_id
	room.log_enabled = log_enabled
	room.seed_value = seed_value
	room.rules_tuning = rules_tuning
	if settings != null:
		room.match_settings = settings
	room.max_alive = max_alive
	room.heavy_parity = _lighter_parity()
	room.emptied.connect(func() -> void: _end_room(match_id))
	viewport.add_child(room)
	await room.built
	_rooms[match_id] = room
	_opened_at[match_id] = _now()
	_building.erase(match_id)
	_log("room_opened", {"match": match_id, "rooms": _rooms.size()})
	room_opened.emit(match_id)
	return room


## The half of the physics frames (`NightHost.heavy_parity`) that fewer of the open rooms put their
## heavy tick on, so the rooms' crowds step on alternate ticks and the process's worst tick is about
## half its rooms' sum, not all of it.
func _lighter_parity() -> int:
	var on_even := 0
	for room: NightHost in _rooms.values():
		on_even += 1 if room.heavy_parity == 0 else -1
	return 1 if on_even > 0 else 0


## A room whose night began and is empty is over; one that nobody ever came to is let go.
func _close_if_done(match_id: String, now: float) -> void:
	var room: NightHost = _rooms[match_id]
	if room.users_present() == 0 and room.away_count() == 0 and room.peer_count() == 0:
		if now - _opened_at[match_id] > idle_room_seconds:
			_end_room(match_id)


func _end_room(match_id: String) -> void:
	var room: NightHost = _rooms.get(match_id)
	if room == null:
		return
	_rooms.erase(match_id)
	_opened_at.erase(match_id)
	for transport_id: int in _room_of.keys():
		if _room_of[transport_id] == room:
			_room_of.erase(transport_id)
	room.get_parent().queue_free()
	_log("room_closed", {"match": match_id, "rooms": _rooms.size()})
	room_closed.emit(match_id)
	_tell_backend("POST", "/internal/matches/%s/end" % match_id.uri_encode(), null)


# --- The backend ---


func _heartbeat() -> void:
	_beat_at = _now() + heartbeat_every
	heartbeats_sent += 1
	_tell_backend(
		"POST",
		"/internal/servers/heartbeat",
		{
			"id": server_id,
			"url": public_url,
			"activityPath": activity_path,
			"capacity": capacity,
			"matchIds": match_ids(),
			"players": players_by_match(),
			"rounds": rounds_by_match(),
		}
	)


func _tell_backend(method: String, path: String, body: Variant) -> void:
	if backend_url == "":
		return
	var answer := await HttpJson.send(
		self, method, backend_url + path, {"Authorization": "Bearer " + backend_secret}, body
	)
	if answer["status"] != 204 and answer["status"] != 200:
		_log(
			"backend_failed",
			{
				"path": path,
				"status": answer["status"],
				"said": answer["json"],
				"sent": JSON.stringify(body)
			}
		)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _log(event: String, fields: Dictionary = {}) -> void:
	if not log_enabled:
		return
	var line := {"event": event, "t": snappedf(_now(), 0.01)}
	line.merge(fields)
	print(JSON.stringify(line))


## A connection that has not been given a room yet.
class Pending:
	extends RefCounted
	var since: float
	var limits := PeerLimits.new()
	var refused := false
	## The hello is being routed (a room is being built for it).
	var routing := false
	## When a refused connection is hung up on (0: not at all).
	var close_at := 0.0

	func _init(p_since: float) -> void:
		since = p_since
