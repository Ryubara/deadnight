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

## Rooms a process takes unless told otherwise: three nights of 40 zombies (a browser's ceiling)
## are the most that fit the 16.7 ms tick on the slowest Railway processor seen.
const DEFAULT_CAPACITY := 3
## Zombies alive at once, in all the rooms of a process together, unless told otherwise: the
## process runs its rooms in one thread, and this many fit the tick with room to spare on that
## processor (`docs/research/crowd-budget.md`). One room may stand all of it; with three each
## stands 40.
const DEFAULT_ALIVE_BUDGET := 120
## Seconds between heartbeats (the default of `heartbeat_every`).
const HEARTBEAT_EVERY := 5.0
## The least a room is cut to by the budget (rooms beyond the budget over this stand this many).
const MIN_SHARE := 20
## Connections that have not said hello yet; the next is hung up on.
const MAX_PENDING := 32
## Seconds a connection has to say hello, and an empty room that never began is kept.
const HELLO_WITHIN := 10.0
const IDLE_ROOM_SECONDS := 60.0
## Seconds a refused client has to read why before it is hung up on.
const REFUSAL_GRACE := 1.0
## Seconds the backend has to answer the read of a seat's challenge board; after that the night
## goes on without it (it never waits for it).
const BOARD_TIMEOUT := 3.0

var port := NetWire.DEFAULT_PORT
var capacity := DEFAULT_CAPACITY
## The most zombies alive at once in a night here (`ServerConfig.max_alive`); 0 is the rules' own.
var max_alive := 0
## The most zombies alive at once in all the rooms together (`ServerConfig.alive_budget`): each room
## is cut to its share of it, so a lone room may stand the budget and four share it. 0 is no budget.
var alive_budget := DEFAULT_ALIVE_BUDGET
## How many bots the rooms may seat (`ServerConfig`: `MAX_BOTS`, `BOTS_OFF`, `BOT_BUDGET`).
var bot_limits := BotLimits.new()
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
## The seconds the connection rules and the rooms are timed by. Empty is the machine's clock; a run
## that plays faster than real time gives the game's own (`Engine.get_physics_frames` over the tick
## rate), so a minute of play is a minute to the limits too.
var clock := Callable()

## The reports of what the seats earned, waiting for the backend (`XpReportQueue`), and how they are
## sent: a Callable taking `(path, body)` and answering the HTTP status (0: no answer). Unset, the
## backend's own address and secret are used; a test sets it to see what would be posted.
var reports := XpReportQueue.new()
var report_sender := Callable()
## How a seat's challenge board is read: a Callable taking the account's id and answering
## `{status, json}` (status 0: no answer). Unset, the backend's own address and secret are used; a
## test sets it to see what would be read.
var board_reader := Callable()
## What the players are asked and the day it is for them (see `NightHost`); unset, the shipped ones.
var challenge_catalog: ChallengeCatalog
var challenge_clock: ChallengeClock
## The poster sets a finished challenge may complete; unset, the shipped ones. Tests set it.
var poster_sets: PosterSets
## False: no room follows any challenge board (the measurement's arm without the tracker).
var challenge_awards := true
## False: no room awards XP (the measurement's arm without the tally).
var xp_awards := true

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
	server.alive_budget = config.alive_budget
	server.bot_limits = BotLimits.from_config(config)
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
	_send_reports(now)


## The match ids of the rooms this process runs.
func match_ids() -> Array[String]:
	var ids: Array[String] = []
	for match_id: String in _rooms:
		ids.append(match_id)
	return ids


func room_of_match(match_id: String) -> NightHost:
	return _rooms.get(match_id)


## People in each room (bots not counted), as a `{match id: count}` for the heartbeat.
func players_by_match() -> Dictionary:
	var out := {}
	for match_id: String in _rooms:
		out[match_id] = _rooms[match_id].people_count()
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
		if admitted.get("map_refused", "") != "":
			_log(
				"map_locked",
				{
					"match": match_id,
					"map": admitted["map_refused"],
					"host_level": admitted["host_level"]
				}
			)
		room = await _open_room(match_id, admitted.get("settings"))
	if not _pending.has(transport_id):
		return
	_hand_over(transport_id, room, admitted["user"], admitted["name"], data, admitted["account"])


func _hand_over(
	transport_id: int,
	room: NightHost,
	user: String,
	user_name: String,
	hello: PackedByteArray,
	account: Dictionary = {}
) -> void:
	_pending.erase(transport_id)
	_room_of[transport_id] = room
	room.attach(transport_id, user, user_name, account)
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
	room.xp_awards = xp_awards
	room.challenge_awards = challenge_awards
	room.challenge_catalog = challenge_catalog
	room.challenge_clock = challenge_clock
	room.poster_sets = poster_sets
	room.clock = clock
	room.report_ready.connect(_on_report.bind(match_id))
	room.board_wanted.connect(_read_board.bind(room))
	room.seed_value = seed_value
	room.rules_tuning = rules_tuning
	if settings != null:
		room.match_settings = settings
	room.max_alive = max_alive
	room.alive_share = _share(_rooms.size() + _building.size())
	room.bot_limit = bot_limits.for_room(_rooms.size() + _building.size())
	room.heavy_parity = _lighter_parity()
	room.emptied.connect(func() -> void: _end_room(match_id))
	room.user_left.connect(_on_user_left.bind(match_id))
	viewport.add_child(room)
	await room.built
	_rooms[match_id] = room
	_opened_at[match_id] = _now()
	_building.erase(match_id)
	_share_budget()
	_log("room_opened", {"match": match_id, "rooms": _rooms.size()})
	room_opened.emit(match_id)
	return room


## A room's share of the alive budget when `rooms` rooms stand: the budget over the rooms, at least
## `MIN_SHARE` (0 when there is no budget).
func _share(rooms: int) -> int:
	if alive_budget <= 0:
		return 0
	return maxi(alive_budget / maxi(rooms, 1), MIN_SHARE)


## Gives every room its share, after a room opened or closed.
func _share_budget() -> void:
	var share := _share(_rooms.size())
	var bots := bot_limits.for_room(_rooms.size())
	for room: NightHost in _rooms.values():
		room.set_alive_share(share)
		room.set_bot_limit(bots)


## The kill-switch and the caps are changed while the server runs (a test, an admin hook): every
## room takes the new limits at once and sends its extra bots away.
func set_bot_limits(limits: BotLimits) -> void:
	bot_limits = limits
	_share_budget()


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


## A person's seat is empty: the backend takes them out of the match's lobby at once, so nothing of
## the night holds them and a night with nobody left is over (`POST /internal/matches/:id/left`).
func _on_user_left(user: String, match_id: String) -> void:
	_log("user_left", {"match": match_id})
	_tell_backend("POST", "/internal/matches/%s/left" % match_id.uri_encode(), {"userId": user})


func _end_room(match_id: String) -> void:
	var room: NightHost = _rooms.get(match_id)
	if room == null:
		return
	room.close_reports()
	_rooms.erase(match_id)
	_opened_at.erase(match_id)
	_share_budget()
	for transport_id: int in _room_of.keys():
		if _room_of[transport_id] == room:
			_room_of.erase(transport_id)
	# What the backend is told: a night that ran its intermission out has finished, and its lobby
	# reopens for the people who were here; any other end (everyone left, a crash) drops the lobby.
	var told: Variant = {"finished": true, "present": room.returning} if room.finished else null
	room.get_parent().queue_free()
	_log("room_closed", {"match": match_id, "rooms": _rooms.size(), "finished": room.finished})
	room_closed.emit(match_id)
	_tell_backend("POST", "/internal/matches/%s/end" % match_id.uri_encode(), told)


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


## A room made a report: it is queued as it is and sent in order, again until the backend takes it.
## `POST /internal/matches/:id/report` with `{kind: "round" | "night", round, seats}`; the backend
## keys each seat by match, kind, round and account, so a retry pays nothing twice
## (docs/research/platform-backend.md, "Progression").
func _on_report(round_number: int, final: bool, seats: Array, match_id: String) -> void:
	var path := "/internal/matches/%s/report" % match_id.uri_encode()
	reports.push(
		path,
		{"kind": "night" if final else "round", "round": round_number, "seats": _wire_seats(seats)}
	)
	_log(
		"xp_report",
		{"match": match_id, "round": round_number, "final": final, "seats": seats.size()}
	)


## Reads a seat's challenge board from the backend, once, when the seat sits down, and hands the
## answer to the room (`GET /internal/users/:id/saves/challenges`). It is not waited for: the night
## runs, and the seat is followed from the moment the board arrives. No answer within
## `BOARD_TIMEOUT` is no board, and a seat with none is never written.
func _read_board(user: String, room: NightHost) -> void:
	var answer := await _fetch_board(user)
	if is_instance_valid(room):
		room.board_arrived(user, answer["status"], answer["json"])


func _fetch_board(user: String) -> Dictionary:
	if board_reader.is_valid():
		return await board_reader.call(user)
	if backend_url == "":
		return {"status": 0, "json": null}
	return await HttpJson.send(
		self,
		"GET",
		backend_url + "/internal/users/%s/saves/challenges" % user.uri_encode(),
		{"Authorization": "Bearer " + backend_secret},
		null,
		BOARD_TIMEOUT
	)


## The seats of a report as JSON (stat names as plain text).
func _wire_seats(seats: Array) -> Array:
	var out: Array = []
	for seat: Dictionary in seats:
		var lines := {}
		for stat: StringName in seat["night_stats"]:
			lines[String(stat)] = seat["night_stats"][stat]
		var line := {"userId": seat["user"], "xp": seat["xp"], "lines": lines}
		if seat.has("board"):
			# The challenges the seat finished and its board as the tracker holds it: the backend
			# lists the ids on the profile and stores the board over the `challenges` slot.
			line["done"] = seat["done"]
			line["board"] = seat["board"]
		if seat["finished_round"]:
			# Claims: the backend knows the profile and pays the two one-offs itself, once.
			line["openingNight"] = true
			line["bonusDay"] = seat["day"]
		out.append(line)
	return out


## Sends the oldest waiting report when it is time. One goes at a time; the answer, or the lack of
## one, decides whether it waits and is sent again.
func _send_reports(now: float) -> void:
	var report := reports.next(now)
	if report.is_empty():
		return
	var status := await _post_report(report["path"], report["body"])
	reports.answered(status, _now())
	if status in XpReportQueue.TAKEN:
		return
	_log("xp_report_failed", {"path": report["path"], "status": status, "tries": report["tries"]})


func _post_report(path: String, body: Dictionary) -> int:
	if report_sender.is_valid():
		return await report_sender.call(path, body)
	if backend_url == "":
		return 204
	var answer := await HttpJson.send(
		self, "POST", backend_url + path, {"Authorization": "Bearer " + backend_secret}, body
	)
	return answer["status"]


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
	if clock.is_valid():
		return clock.call()
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
