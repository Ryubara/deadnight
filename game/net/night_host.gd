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
## Players get the lowest free id of 1 to `MAX_PLAYERS`, which is also their seat in the lot.
##
## The server speaks plain `ws://`: on Railway the edge terminates TLS and clients use `wss://`.
## It reads its port from the command line (`--port N`) or `$PORT`, and logs one JSON object a line.
##
## Alone it owns its listener and rebuilds the night when everyone has left. As one room of a
## `GameServer` (`embedded`) it shares the server's listener, which the `GameServer` polls and
## routes (`attach`, `receive`, `detach`), and says `emptied` instead of rebuilding.

signal player_joined(player_id: int)
signal player_left(player_id: int)
## A player's socket dropped and the seat is held for them; and they came back on a new one.
signal player_away(player_id: int)
signal player_resumed(player_id: int)
## The night is built and the room takes players.
signal built
## What the seats with an account earned, to be posted to the backend: at the end of a round
## (`final` false, `round_number` the one that ended) and once at the night's end (`final` true).
## Never once per kill. `seats` are `XpAward.take_report`'s entries. The `GameServer` queues them.
signal report_ready(round_number: int, final: bool, seats: Array)
## An embedded room's night began and everyone has gone: the `GameServer` ends and frees it.
signal emptied

## Seats in a room: people and bots together. The one place the limit is written: `NightBots.SEATS`
## and `LookServer.SEATS` are held equal to it by a test, `MatchSettings.MAX_BOTS` is one less (a
## person always holds a seat), and the backend's `MAX_PLAYERS` (spikes/backend) mirrors it.
const MAX_PLAYERS := 8
## The longest name a seat shows, as the HUD keeps it (`HudStyle.NAME_LIMIT`), so the ` (2)` of a
## duplicate is never cut off.
const NAME_MAX := 20
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
## Seconds a client has, after the night is closed, to leave by itself (it does at once); what is
## still connected then is hung up on, so the room never waits for a client that does not leave.
const CLOSE_GRACE := 3.0

## Set before the node enters the tree.
var port := NetWire.DEFAULT_PORT
## The seed of the night's dice; -1 draws one for every night.
var seed_value := -1
var rules_tuning: RulesTuning
## The rules of the match (zombie intensity, alive cap, break, map) the next night runs under.
## Set it with `configure_match`, which also changes a night nobody has started.
var match_settings := MatchSettings.new()
## The most zombies alive at once in this room's night whatever the players are on; 0 is the rules'
## own (`CrowdCeiling.limit`).
var max_alive := 0
## This room's share of its process's alive budget (`GameServer.alive_budget` over its rooms); 0 is
## no share. Set with `set_alive_share`, the smaller of it and `max_alive` caps the crowd.
var alive_share := 0
## The most bots this room may seat whatever its settings ask (`GameServer.bot_limits`; 0 is the
## kill-switch). Set with `set_bot_limit`.
var bot_limit := MatchSettings.MAX_BOTS
var log_enabled := true
## False: the room awards no XP (the measurement's arm without the tally).
var xp_awards := true
## The seconds the connection rules (a peer's rates, the hello, a seat held for a returning player)
## are timed by. Empty is the machine's clock; a soak that plays faster than real time gives the
## game's own (`Engine.get_physics_frames` over the tick rate), so a minute of play is a minute to
## the limits too.
var clock := Callable()
## Metres around a player within which the zombies are sent to their client (0: all of them).
var interest_radius := 0.0
## Seconds a connection has to say hello (`HELLO_WITHIN`; a test sets it shorter).
var hello_within := HELLO_WITHIN
## Seconds a dropped player's seat is held (`RESUME_WITHIN`); 0 frees it at once.
var resume_within := RESUME_WITHIN
## The place to say who may join: called with `(transport_id: int, version: int)` once a client
## has said hello with a version this build takes, it returns 0 to let the client in or a
## `NetWire.Refusal` to turn it away. Unset, everyone is let in (the platform backend's ticket check
## plugs in here).
var admit: Callable
## Which half of the physics frames this room's heavy ticks (the zombies' step, and the frame built
## after it) fall on: `Engine.get_physics_frames() % 2`, or -1 for whenever it started. A
## `GameServer` gives its rooms alternate halves, so four rooms in one process never all step their
## crowds in the same tick.
var heavy_parity := -1
## One room of a `GameServer`: the listener is the server's, not this node's.
var embedded := false
## What a room is called in the log (the match id of a `GameServer`'s room).
var room_id := ""

var listener := WsListener.new()
var world: NightWorld
var server: NightServer
## The bots of this night, seated beside the people (`MatchSettings.bots`).
var bots: NightBots
## False while a night is being built.
var serving := false
## Steps taken, and milliseconds spent in them (the work, not the waiting), for the stats.
var steps := 0
## 1 when `heavy_parity` moved this room's cadence by one tick (sent and stepped a tick earlier).
var phase := 0
var work_ms := 0.0
var worst_ms := 0.0
## When on, the milliseconds of every step are kept in `tick_log` (a measurement's, off in play).
var record_ticks := false
var tick_log := PackedFloat32Array()
## The nights built so far.
var nights := 0
## Peers hung up on for breaking `PeerLimits`.
var kicked_count := 0
## The night is over and its intermission ran out (`NightServer.NIGHT_CLOSED`): everyone goes back
## to the lobby they came from. `returning` is the backend's user ids of the players who were here
## at that moment (away ones included), told to the backend with the match's end so it can reopen
## the lobby for them.
var finished := false
var returning: Array[String] = []
## Reports made (`report_ready`), and whether the night's own has gone.
var reports_made := 0
var night_reported := false

var _peers: Dictionary[int, HostPeer] = {}
var _by_player: Dictionary[int, HostPeer] = {}
## Player id -> the name the seat shows (the ticket's name, made unique); players without a name
## are left out and are `PLAYER n` on every screen. Kept with the seat while it is away.
var _names: Dictionary = {}
## Players whose socket dropped, by id: their seat, kept until they come back or the time is up.
var _away: Dictionary[int, Away] = {}
var _events: Array[Dictionary] = []
## What the server said outside a step (a join, a name, a ping a bot made) that the bots have not
## heard yet: they hear it with the next step's events.
var _unheard: Array[Dictionary] = []
var _closed_at := 0.0
var _stats_at := 0.0
var _stats_bytes := 0
var _stats_steps := 0
var _stats_work := 0.0


func _ready() -> void:
	if embedded:
		await _build_night()
		_log("room_ready", {"players_max": MAX_PLAYERS})
		return
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
	if not embedded:
		listener.close()
	if server != null:
		server.close()


func _physics_process(_delta: float) -> void:
	if not serving:
		return
	var began := Time.get_ticks_usec()
	if not embedded:
		listener.poll()
	if server == null:
		return
	# Clients are sent a frame every `SEND_EVERY` steps and only the last of them counts, so the
	# steps between do not build one (it is half a millisecond or more at every step).
	if steps == 0 and heavy_parity >= 0 and (Engine.get_physics_frames() & 1) == heavy_parity:
		phase = 1
		# One tick's time for the zombies' sim without a step: its 30 Hz step falls on this tick.
		server.sim.tick(Night.STEP, {})
	var sending := (steps + phase + 1) % SEND_EVERY == 0
	# The bots decide on every step, so with bots in the night the frame is built on every step
	# (it is sent every `SEND_EVERY`).
	var framed := sending or bots.count() > 0
	var events := server.step(Night.STEP, framed)
	var frame: Dictionary = events.pop_back() if framed else {}
	_events.append_array(events)
	_report_what_is_due()
	if not finished and server.closed():
		_finish()
	_run_bots(events, frame)
	steps += 1
	if sending:
		_send_ticks(frame)
	var spent := (Time.get_ticks_usec() - began) / 1000.0
	work_ms += spent
	worst_ms = maxf(worst_ms, spent)
	if record_ticks:
		tick_log.append(spent)
	_stats_work += spent
	_close_refused()
	_close_silent()
	_expire_away()
	_stats_steps += 1
	_log_stats()
	if finished and not _peers.is_empty() and _now() - _closed_at >= CLOSE_GRACE:
		for peer: HostPeer in _peers.values():
			if not peer.kicked:
				_kick(peer)
	if _peers.is_empty() and _away.is_empty() and nights > 0 and _night_began():
		if embedded:
			serving = false
			emptied.emit()
		else:
			_rebuild()


## The night's intermission ran out: remembers who is here to go back to the lobby, and lets go of
## the seats held for dropped sockets (nobody can come back to a closed night).
func _finish() -> void:
	finished = true
	_closed_at = _now()
	returning = users()
	_away.clear()
	_log("night_closed", {"players": returning.size()})


## The backend's user ids of the people here now, those whose socket dropped included (`""` ids,
## from a server with no backend, are left out).
func users() -> Array[String]:
	var out: Array[String] = []
	for peer: HostPeer in _by_player.values():
		if peer.user != "" and not out.has(peer.user):
			out.append(peer.user)
	for away: Away in _away.values():
		if away.user != "" and not out.has(away.user):
			out.append(away.user)
	return out


func player_count() -> int:
	return _by_player.size()


## The round the night is in (0 before the first begins, and while there is no night): what the
## backend tells a latecomer's lobby screen ("Night in progress, round 4").
func round_number() -> int:
	return server.rules.round_number if server != null else 0


## Connections this room has been handed (players and those that have not said hello yet).
func peer_count() -> int:
	return _peers.size()


## Players whose seat is held while their socket is down.
func away_count() -> int:
	return _away.size()


## The one way a room's host sets the match: its settings are the server's from here, in every
## snapshot and so in every WELCOME (a late joiner or a client that came back reads them there),
## and in every night this host builds after. Applies at once to a night nobody has started and
## returns true; once the night began the settings wait for the next one and it returns false. The
## map is the room's, built when it opened: a map in `settings` that is another one is not taken
## (the next night is built on the map in `match_settings`).
func configure_match(settings: MatchSettings) -> bool:
	match_settings = settings.clamped()
	if world != null and world.map_info != null:
		match_settings.map = world.map_info.id
	if server == null or _night_began():
		return false
	server.rules.apply(RulesAction.configure(match_settings))
	return true


## Whether the night has ended: it stands still, so no bot takes a seat in it any more.
func _night_over() -> bool:
	return server.rules.phase == GameRules.Phase.OVER


## Whether the first player has arrived and started the night.
func _night_began() -> bool:
	return server.rules.phase != GameRules.Phase.IDLE


func _build_night() -> void:
	serving = false
	world = NightWorld.new()
	add_child(world)
	await world.build(MapRegistry.of(match_settings.map))
	var chosen := seed_value if seed_value >= 0 else randi()
	# A map with its own rules overlay is played by it, over the shared table (#792).
	var table := rules_tuning if rules_tuning != null else load(GameRules.DEFAULT_TUNING_PATH)
	server = NightServer.new(world, chosen, null, world.rules_for(table), match_settings)
	server.drawn_bodies = false
	bots = NightBots.new(server, world, chosen, Callable(self, &"_collect"))
	bots.limit = bot_limit
	_unheard.clear()
	server.crowd.limit = alive_limit()
	server.xp.enabled = xp_awards
	night_reported = false
	_events.clear()
	nights += 1
	serving = true
	_log("night_ready", {"night": nights, "seed": chosen})
	built.emit()


## The cap on the crowd from the operator's `max_alive` and this room's share of the process's
## budget, whichever is smaller; 0 is none.
func alive_limit() -> int:
	if max_alive > 0 and alive_share > 0:
		return mini(max_alive, alive_share)
	return maxi(max_alive, alive_share)


## The process gave this room a new share (a room opened or closed). Takes effect at once: zombies
## standing are not removed, but no more come until fewer than the new cap stand.
func set_alive_share(share: int) -> void:
	alive_share = maxi(share, 0)
	if server != null:
		server.crowd.limit = alive_limit()


## The operator's limit on bots changed (the kill-switch, a cap, this room's share of the budget):
## takes effect at once, seating bots a raised limit allows and sending away those a lowered one
## does not.
func set_bot_limit(limit: int) -> void:
	bot_limit = clampi(limit, 0, MatchSettings.MAX_BOTS)
	if bots != null:
		bots.limit = bot_limit
		_fill_bots()


## The last player left a night that began: a new lot, new rules, a new seed.
func _rebuild() -> void:
	server.close()
	world.queue_free()
	await _build_night()


func _hz() -> int:
	return roundi(1.0 / Night.STEP)


# --- Connections ---


## A `GameServer` hands this room a connection (`user` is who the backend's ticket says it is).
func attach(
	transport_id: int, user: String = "", user_name: String = "", account: Dictionary = {}
) -> void:
	_on_connected(transport_id)
	var peer: HostPeer = _peers.get(transport_id)
	if peer != null:
		peer.user = user
		peer.user_name = user_name
		peer.account = account


## What the connection sent, from a `GameServer` that routes it here.
func receive(transport_id: int, data: PackedByteArray) -> void:
	_on_packet(transport_id, data)


## The connection closed, told by the `GameServer`.
func detach(transport_id: int) -> void:
	_on_disconnected(transport_id)


## The room's `HostPeer` for a connection, or null.
func peer_of(transport_id: int) -> HostPeer:
	return _peers.get(transport_id)


## Whether this room holds the seat a resume token is for (a live one or one that is away).
func owns_token(token: PackedByteArray) -> bool:
	if token.size() != NetWire.TOKEN_SIZE:
		return false
	for away: Away in _away.values():
		if away.token == token:
			return true
	for peer: HostPeer in _by_player.values():
		if peer.token == token:
			return true
	return false


## The players in this night by the backend's user id of their ticket (`""` ids are left out).
func users_present() -> int:
	return _by_player.size()


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
	if server != null:
		server.pings.erase(peer.player_id)
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
		_away[peer.player_id] = Away.new(peer.token, _now() + resume_within, peer.user)
		_log("away", {"player": peer.player_id, "players": _by_player.size()})
		player_away.emit(peer.player_id)
		return
	_free_seat(peer.player_id)


## Frees a seat for good: the body leaves the lot and the id can be given to someone new.
func _free_seat(player_id: int) -> void:
	_away.erase(player_id)
	_names.erase(player_id)
	if server != null:
		if server.xp.has_seat(player_id):
			_collect([{"type": &"account_left", "player_id": player_id}])
		server.xp.release(player_id)
		# The seat has no account now (a bot has no level, and wears its cast look whole).
		server.player_levels.erase(player_id)
		var inherited := _bot_inherits(player_id)
		if inherited.is_empty():
			_collect(server.apply({"type": NightServer.LEAVE, "player_id": player_id}))
		else:
			_collect(inherited)
		# Seats the people leave free fill with bots while the others are still here.
		_fill_bots()
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
		# A client that was refused still sends what it queued after its hello: not a strike.
		if not peer.refused:
			_fault(peer)
		return
	_on_player_packet(peer, data)


## A message of a client that has a seat.
func _on_player_packet(peer: HostPeer, data: PackedByteArray) -> void:
	match data[0]:
		NetWire.Type.COMMAND:
			var command := NetWire.read_command(data)
			if command == null:
				_fault(peer)
				return
			server.submit(peer.player_id, command)
		NetWire.Type.PING:
			if data.size() == NetWire.PING_SIZE:
				var pong := NetWire.pong(data.decode_u32(1), server.tick_count)
				listener.send(peer.transport_id, pong)
				var rtt := NetWire.read_ping_rtt(data)
				if rtt >= 0:
					server.pings[peer.player_id] = rtt
		NetWire.Type.PLATFORM:
			var web := NetWire.read_platform(data)
			if web < 0:
				_fault(peer)
				return
			server.crowd.set_platform(peer.player_id, web == 1)
		NetWire.Type.ARRIVAL:
			var begin := NetWire.read_arrival(data)
			if begin < 0:
				_fault(peer)
				return
			_collect(
				server.apply(
					{"type": NightServer.ARRIVAL, "player_id": peer.player_id, "begin": begin == 1},
					peer.player_id
				)
			)
		NetWire.Type.MARK:
			var mark := NetWire.read_mark(data)
			if mark.is_empty():
				_fault(peer)
			else:
				_collect(server.apply(mark, peer.player_id))
		NetWire.Type.ORDER:
			var order := NetWire.read_order(data)
			if order.is_empty():
				_fault(peer)
			else:
				_collect(server.apply(order, peer.player_id))
		LookWire.Type.LOOK:
			var action := {"type": NightServer.LOOK, "player_id": peer.player_id, "packet": data}
			_collect(server.apply(action, peer.player_id))


func _hello(peer: HostPeer, data: PackedByteArray) -> void:
	if peer.player_id != 0 or peer.refused:
		_fault(peer)
		return
	if not NetWire.accepts(NetWire.hello_version(data)):
		_refuse(peer, NetWire.Refusal.VERSION)
		return
	var hello := NetWire.read_hello(data)
	if hello.is_empty():
		_fault(peer)
		return
	if admit.is_valid():
		var verdict: int = admit.call(peer.transport_id, hello["version"])
		if verdict != 0:
			_refuse(peer, verdict as NetWire.Refusal)
			return
	var resumed := _claim_seat(hello["token"], peer.user)
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
	register_account(player_id, peer.user, peer.account)
	if bots.holds(player_id):
		# The seat is a bot's: the person takes it as it stands, and the round goes on. The name
		# goes first, so the notice the others read says who, and a person without a name gets
		# the usual `PLAYER n` in the bot's place.
		_name_seat(player_id, peer.user_name)
		if not _names.has(player_id):
			_collect(
				[{"type": &"player_named", "player_id": player_id, "name": "PLAYER %d" % player_id}]
			)
		_collect(bots.hand_over(player_id))
		_collect(server.apply({"type": NightServer.RESYNC, "player_id": player_id}))
	else:
		# The name goes out before the join, so the others' notice reads "ANN JOINED", not "PLAYER 2".
		_name_seat(player_id, peer.user_name)
		_collect(server.apply({"type": NightServer.JOIN, "player_id": player_id, "local": false}))
	if not _night_began():
		_collect(server.apply({"type": NightServer.START_NIGHT}))
	_fill_bots()
	listener.send(
		peer.transport_id,
		NetWire.welcome(player_id, _hz(), peer.token, _welcome_snapshot(player_id))
	)
	_log("joined", {"player": player_id, "players": _by_player.size()})
	player_joined.emit(player_id)


## What a WELCOME carries: the rules' snapshot and the names of the seats (`names`: player id ->
## name, the bots' too), so a client that joins late, or comes back, shows everyone by name at once;
## the level of every seat with an account (`levels`: player id -> level, a bot has none); and the
## joiner's own raw XP (`account_xp`, from the ticket the server verified and what the night added),
## so its bar is right before the first `xp_gained`.
func _welcome_snapshot(for_player: int = 0) -> Dictionary:
	var snapshot := server.rules.to_dict()
	var names := bots.names()
	names.merge(_names, true)
	snapshot["names"] = names
	snapshot["levels"] = server.xp.levels()
	if server.xp.has_seat(for_player):
		snapshot["account_xp"] = server.xp.total_of(for_player)
	return snapshot


## Gives a seat the account the backend's ticket said (`user` is the ticket's `sub`; `""`, a server
## with no backend, is no account and earns nothing). The XP is the ticket's alone.
func register_account(player_id: int, user: String, account: Dictionary = {}) -> void:
	if user == "" or server == null:
		return
	var seated := server.xp.has_seat(player_id)
	server.xp.register(player_id, user, int(account.get("xp", 0)), server.rules.round_number)
	if server.xp.has_seat(player_id):
		# What the seat may wear is held to the level the ticket's XP gives (#1065).
		server.player_levels[player_id] = server.xp.levels()[player_id]
	if server.xp.has_seat(player_id) and not seated:
		# Everyone already here learns this seat's level (the joiner reads the others' in its WELCOME).
		var level: int = server.xp.levels()[player_id]
		_collect([{"type": &"account_seated", "player_id": player_id, "level": level}])


## A round ended (or the night did): what the seats earned goes out as a report, once. The night's
## report is the last and lists every seat.
func _report_what_is_due() -> void:
	if not server.xp.has_due():
		return
	for due in server.xp.take_due():
		_report(due["round"], due["final"])


func _report(round_number: int, final: bool) -> void:
	if final:
		if night_reported:
			return
		night_reported = true
	var seats := server.xp.take_report(final)
	if seats.is_empty():
		return
	reports_made += 1
	report_ready.emit(round_number, final, seats)


## The room is closing: what was earned and not yet reported (everyone left in the middle of a
## round) goes out as the night's report. `GameServer` calls it before it frees the room.
func close_reports() -> void:
	if server != null and not night_reported:
		_report(server.rules.round_number, true)


## The events of a bot taking the seat of the person who just left, as it stands (body, points,
## weapons): when the night has begun, other people are still here and the room wants one more bot.
## Empty when not (the seat is then freed).
func _bot_inherits(player_id: int) -> Array[Dictionary]:
	var people := _people()
	if not _night_began() or _night_over() or people.is_empty():
		return []
	if not bots.wants_more(server.rules.settings.bots, people.size()):
		return []
	return bots.adopt(player_id)


## The seats people hold, away or not.
func _people() -> Array:
	var ids: Array = _by_player.keys()
	ids.append_array(_away.keys())
	return ids


## Seats bots up to the setting, in the seats the people leave free. Only once the night has begun,
## and never for a night with nobody in it.
func _fill_bots() -> void:
	if not _night_began() or _night_over() or _people().is_empty():
		return
	_collect(bots.fill(server.rules.settings.bots, _people()))


## Lets the bots hear the step and decide. `frame` is this step's frame (built on every step when
## there are bots).
func _run_bots(events: Array[Dictionary], frame: Dictionary) -> void:
	if bots.count() == 0:
		_unheard.clear()
		return
	var heard: Array = _unheard.duplicate()
	heard.append_array(events)
	heard.append(frame)
	_unheard.clear()
	bots.hear(heard)
	bots.tick(Night.STEP)


## Gives the seat the name the ticket said, made unique among the seats (`Ann`, `Ann (2)`, ...), and
## tells everyone (a `player_named` event; the joiner's own WELCOME carries it too). A seat with no
## name stays without one.
func _name_seat(player_id: int, wanted: String) -> void:
	var shown := unique_name(wanted, _names, player_id)
	if shown == "":
		return
	_names[player_id] = shown
	_collect([{"type": &"player_named", "player_id": player_id, "name": shown}])


## `wanted` (edge spaces cut, at most `NAME_MAX` characters) or, when another seat of `taken`
## (player id -> name) already shows it, in any case of letters, the first of `wanted (2)`,
## `wanted (3)`, ... that is free. "" when there is no name.
static func unique_name(wanted: String, taken: Dictionary, player_id: int) -> String:
	var base := wanted.strip_edges().left(NAME_MAX)
	if base == "":
		return ""
	var used: Dictionary = {}
	for id: Variant in taken:
		if id != player_id:
			used[str(taken[id]).to_lower()] = true
	if not used.has(base.to_lower()):
		return base
	for number in range(2, MAX_PLAYERS + 2):
		var suffix := " (%d)" % number
		var candidate := base.left(NAME_MAX - suffix.length()).strip_edges() + suffix
		if not used.has(candidate.to_lower()):
			return candidate
	return base


## The id of the player this token is the seat of, taken from the held seats or (a client that
## came back before the server noticed its old socket was dead) from a live connection, which is
## hung up on; 0 when it is no one's.
func _claim_seat(token: PackedByteArray, user: String = "") -> int:
	var by_token := token.size() == NetWire.TOKEN_SIZE
	if not by_token and user == "":
		return 0
	# The seat of a ticket's user is theirs whatever token they hold: a second tab or a reload with
	# a new ticket takes the seat back instead of making a second player.
	for player_id in _away:
		var held: Away = _away[player_id]
		if (by_token and held.token == token) or (user != "" and held.user == user):
			return player_id
	for player_id in _by_player:
		var old := _by_player[player_id]
		if (by_token and old.token == token) or (user != "" and old.user == user):
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
	peer.zombie_base = {}
	_by_player[player_id] = peer
	register_account(player_id, peer.user, peer.account)
	listener.send(
		peer.transport_id,
		NetWire.welcome(player_id, _hz(), peer.token, _welcome_snapshot(player_id))
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
	if clock.is_valid():
		return clock.call()
	return Time.get_ticks_msec() / 1000.0


func _close_refused() -> void:
	for peer: HostPeer in _peers.values():
		if peer.close_at >= 0 and steps >= peer.close_at:
			peer.close_at = -1
			listener.disconnect_peer(peer.transport_id)


## The lowest seat no person holds: a seat a bot holds counts as free, since a person takes it.
func _free_player_id() -> int:
	for id in range(1, MAX_PLAYERS + 1):
		if not _by_player.has(id) and not _away.has(id):
			return id
	return 0


# --- Ticks ---


func _collect(events: Array) -> void:
	for event: Dictionary in events:
		_events.append(event)
		_unheard.append(event)


## Every event goes to every client, except a look packet, which is for one.
func _is_for(event: Dictionary, player_id: int) -> bool:
	return event["type"] != NightServer.LOOK_PACKET or event["to"] == player_id


func _send_ticks(frame: Dictionary) -> void:
	var zombies := ZombieDelta.entries_of(frame["zombies"])
	for peer: HostPeer in _by_player.values():
		var out: Array = _events.filter(
			func(event: Dictionary) -> bool: return _is_for(event, peer.player_id)
		)
		# The zombies go as what changed from the ones this client has (`ZombieDelta`), and only
		# those near enough when the host has an `interest_radius`.
		var seen := _in_interest(peer, zombies)
		var own := frame.duplicate()
		own["zombies"] = ZombieDelta.diff(peer.zombie_base, seen, peer.zombie_sequence)
		out.append(FrameDelta.diff(peer.last_frame, own))
		# A tick the peer's socket would not take (it stopped reading, a frozen client, and its buffer
		# is full) is lost, and the next delta would be against a frame it never had: the next frame
		# is whole instead, and the zombies stay a delta against the ones the client really has.
		var sent := listener.send(peer.transport_id, NetWire.tick(server.tick_count, out))
		peer.last_frame = own if sent else {}
		if sent:
			peer.zombie_base = seen
			peer.zombie_sequence = (peer.zombie_sequence + 1) & 0xFF
		_note_delivery(peer, sent)
	_events.clear()


## The zombies this player's client is told of: all of them, or the ones within `interest_radius`
## metres of their body (the lot is one screen, so a night does not set it; a bigger map would).
func _in_interest(
	peer: HostPeer, zombies: Dictionary[int, PackedByteArray]
) -> Dictionary[int, PackedByteArray]:
	if interest_radius <= 0.0 or not _by_player.has(peer.player_id):
		return zombies
	var body := server.body_of(peer.player_id)
	var from := Vector2(body.global_position.x, body.global_position.z)
	var near: Dictionary[int, PackedByteArray] = {}
	for id: int in zombies:
		var entry := zombies[id]
		var at := Vector2(entry.decode_s16(2), entry.decode_s16(6)) / 100.0
		if at.distance_to(from) <= interest_radius:
			near[id] = entry
	return near


## One line in the log when a peer stops taking ticks and one when it takes them again, with how
## many it missed: the only trace a client's freeze leaves on the server.
func _note_delivery(peer: HostPeer, sent: bool) -> void:
	if not sent:
		if peer.missed_ticks == 0:
			_log("peer_stalled", {"player": peer.player_id})
		peer.missed_ticks += 1
	elif peer.missed_ticks > 0:
		_log("peer_recovered", {"player": peer.player_id, "ticks_missed": peer.missed_ticks})
		peer.missed_ticks = 0


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
				"bots": bots.count(),
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
	if room_id != "":
		line["room"] = room_id
	line.merge(fields)
	print(JSON.stringify(line))


## A seat held for a player whose socket dropped.
class Away:
	extends RefCounted
	var token: PackedByteArray
	## When the seat is given up (the host's clock, seconds).
	var until: float
	## The backend's user id of the player (`""` without a ticket).
	var user: String

	func _init(p_token: PackedByteArray, p_until: float, p_user: String = "") -> void:
		token = p_token
		until = p_until
		user = p_user


## One connection to the server.
class HostPeer:
	extends RefCounted
	var transport_id: int
	## 0 until the client has said hello and been given a seat.
	var player_id := 0
	## The frame this client last had, the baseline of the next delta.
	var last_frame: Dictionary = {}
	## Ticks in a row the socket would not take (the client stopped reading).
	var missed_ticks := 0
	## The step at which a refused client is hung up on, or -1.
	var close_at := -1
	var refused := false
	var kicked := false
	## When the connection opened (seconds), for the time it has to say hello.
	var connected_at := 0.0
	var limits := PeerLimits.new()
	## The zombies this client has (`ZombieDelta`), and the number of the next delta to it.
	var zombie_base: Dictionary[int, PackedByteArray] = {}
	var zombie_sequence := 0
	## What the client was given at WELCOME to take its seat back with.
	var token := PackedByteArray()
	## Who the backend's ticket says this is (`""` when the server has no backend), and their name.
	var user := ""
	var user_name := ""
	## The progression the ticket carries (`TicketVerifier.account_of`).
	var account: Dictionary = {}

	func _init(p_transport_id: int, now: float = 0.0) -> void:
		transport_id = p_transport_id
		connected_at = now
