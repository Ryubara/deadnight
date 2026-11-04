extends Node
## What the game server's XP award costs under a horde (#1059): one four-player night (an autopilot
## client over a real WebSocket and three hosted bots, all holding accounts) on a `GameServer`, at
## count multiplier 5 from a late round, with or without the award, writing one JSON line:
##   server tick ms (mean, p50, p99, worst) of the room's own work, the kills a second, the
##   `xp_gained` events and bytes a second the client heard (the peak second), the wire bytes in a
##   second, the client's cost of applying them, and the writes the backend heard (one a round
##   plus the night's).
## The two arms play the same seed; time is a physics step at `--fixed-fps 60`, headless.
##
## Arguments after `--`: `xp=1|0` (the award on or off), `seed=N`, `count=5`, `startround=8`,
## `seconds=120` of play after the round starts, `ceiling=web|desktop` (web: the bots count as
## browsers, 40 dead at most; desktop: 120), `window=N` (ticks between the times a seat is told its
## XP; 1: every tick), `grind=K` (besides the bots, K kills a second are made at the rules, spread
## over the four seats: the same events a hit makes, to see the award at rates the bots do not
## reach), `out=PATH` for the JSON. Not part of the play.

const SECRET := "bench-ticket-secret-of-32-characters!"
const SERVER_ID := "gs-bench"
const MATCH := "match-bench"
const POINTS := 20000
const START_XP := 300
const ACCOUNT_USER := "bench-%d"
const BIN := 60

var _args: NetArgs
var _server: GameServer
var _client: Night
var _room: NightHost
var _posts := 0
var _kills := 0
var _rounds_ended := 0
var _level_events := 0
var _xp_events := 0
var _xp_bytes := 0
var _bins: Array[Dictionary] = []
var _bin := {"kills": 0, "xp_events": 0, "xp_bytes": 0, "wire": 0, "alive": 0, "frames": 0}
var _xp_usec := 0
var _apply_usec := 0
var _apply_count := 0
var _wire_before := 0
var _boosted: Dictionary[int, bool] = {}
var _grind_owed := 0.0
var _grind_next := 0
var _started_frame := -1
var _done := false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_args = NetArgs.new()
	var xp_on := _args.get_int("xp", 1) == 1
	var seconds := _args.get_float("seconds", 120.0)
	var start_round := _args.get_int("startround", 8)
	PerfProbe.enabled = true
	_server = GameServer.new()
	_server.port = 0
	_server.capacity = 1
	_server.server_id = SERVER_ID
	_server.log_enabled = false
	_server.seed_value = _args.get_int("seed", 1)
	_server.xp_awards = xp_on
	_server.clock = _game_seconds
	_server.rules_tuning = AutopilotRun.tuning()
	_server.verifier = TicketVerifier.new(SECRET, SERVER_ID)
	_server.report_sender = func(_path: String, _body: Dictionary) -> int:
		_posts += 1
		return 200
	_world().add_child(_server)
	while not _server.listener.is_listening():
		await get_tree().physics_frame
	var settings := MatchSettings.new()
	settings.count_multiplier = _args.get_float("count", 5.0)
	settings.bots = 3
	var ticket := TicketMaker.make(
		SECRET,
		SERVER_ID,
		MATCH,
		ACCOUNT_USER % 1,
		"Bench",
		600,
		settings.to_dict(),
		null,
		{"xp": START_XP}
	)
	_client = Night.new()
	_world().add_child(_client)
	var link := WebSocketLink.new()
	link.clock = _game_seconds
	link.ticket = ticket
	var joined := await _client.start_remote(
		"ws://127.0.0.1:%d" % _server.listener.port(), Night.Mode.AUTOPILOT, 60.0, link
	)
	if not joined:
		push_error("XP_HORDE_BENCH the client did not join")
		get_tree().quit(1)
		return
	_room = _server.room_of_match(MATCH)
	_room.record_ticks = true
	_room.server.xp.window_ticks = _args.get_int("window", 1)
	_client.state.event_received.connect(_on_client_event)
	_room.server.rules.event_emitted.connect(_on_rules_event)
	var rules := _room.server.rules
	rules.round_number = maxi(start_round - 1, 0)
	var web_ceiling := _args.get_string("ceiling", "web") != "desktop"
	while not _done:
		await get_tree().physics_frame
		_seat_accounts(web_ceiling)
		if Engine.get_physics_frames() % 300 == 0:
			print(
				(
					"XP_HORDE_BENCH_PROGRESS frame=%d round=%d phase=%d players=%d alive=%d kills=%d"
					% [
						Engine.get_physics_frames(),
						rules.round_number,
						rules.phase,
						rules.players.size(),
						_room.server.sim.zombies.size(),
						_kills,
					]
				)
			)
		if _started_frame < 0:
			if rules.round_number >= start_round and rules.phase == GameRules.Phase.ACTIVE:
				_begin()
			continue
		_grind(rules)
		_sample()
		if (Engine.get_physics_frames() - _started_frame) >= int(seconds * 60.0):
			_done = true
	await _publish(xp_on)
	get_tree().quit()


## `grind` kills a second at the rules, a head shot each, in turn for the four seats.
func _grind(rules: GameRules) -> void:
	var rate := _args.get_float("grind", 0.0)
	if rate <= 0.0:
		return
	_grind_owed += rate / 60.0
	var ids := rules.zombie_ids()
	while _grind_owed >= 1.0 and not ids.is_empty():
		_grind_owed -= 1.0
		var seat := 1 + (_grind_next % 4)
		_grind_next += 1
		var zombie_id: int = ids.pop_back()
		rules.apply(RulesAction.hit(seat, zombie_id, RulesAction.ZONE_HEAD, 99999.0, false))
	_grind_owed = minf(_grind_owed, 4.0)


func _game_seconds() -> float:
	return Engine.get_physics_frames() / 60.0


func _world() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	return viewport


## Every seat holds an account (the bots too, only here: a game server never gives a bot one) and
## starts with the points a late round has bought its guns with.
func _seat_accounts(web_ceiling: bool) -> void:
	var rules := _room.server.rules
	for id: int in rules.players:
		if _boosted.has(id):
			continue
		_boosted[id] = true
		(rules.players[id] as PlayerState).points = POINTS
		if not web_ceiling:
			_room.server.crowd.set_platform(id, false)
		_room.register_account(id, ACCOUNT_USER % id, {"xp": START_XP})


func _begin() -> void:
	_started_frame = Engine.get_physics_frames()
	_room.tick_log = PackedFloat32Array()
	_wire_before = _client.link.bytes_in
	PerfProbe.take()
	_kills = 0
	_rounds_ended = 0
	_posts = 0


func _on_rules_event(event: Dictionary) -> void:
	if _started_frame < 0:
		return
	match event["type"]:
		&"zombie_removed":
			if event["cause"] == &"killed":
				_kills += 1
				_bin["kills"] += 1
		&"round_ended":
			_rounds_ended += 1


func _on_client_event(event: Dictionary) -> void:
	if _started_frame < 0:
		return
	match event["type"]:
		&"xp_gained":
			_xp_events += 1
			_bin["xp_events"] += 1
			var size := var_to_bytes(event).size()
			_xp_bytes += size
			_bin["xp_bytes"] += size
		&"level_up", &"tier_up", &"unlock_earned":
			_level_events += 1
			var size := var_to_bytes(event).size()
			_xp_bytes += size
			_bin["xp_bytes"] += size


## One physics frame of the measured window; a bin each second.
func _sample() -> void:
	var taken := PerfProbe.take()
	_xp_usec += int(taken["usec"].get(&"server.xp", 0))
	_apply_usec += int(taken["usec"].get(&"event.xp_gained", 0))
	_apply_count += int(taken["counts"].get(&"ev.xp_gained", 0))
	_bin["frames"] += 1
	_bin["alive"] += _room.server.sim.zombies.size()
	if _bin["frames"] >= BIN:
		var wire: int = _client.link.bytes_in
		_bin["wire"] = wire - _wire_before
		_wire_before = wire
		_bins.append(_bin)
		_bin = {"kills": 0, "xp_events": 0, "xp_bytes": 0, "wire": 0, "alive": 0, "frames": 0}


func _publish(xp_on: bool) -> void:
	var ticks := _room.tick_log.duplicate()
	ticks.sort()
	var total := 0.0
	for ms in ticks:
		total += ms
	var seconds := float(_bins.size())
	var peak := {"kills": 0, "xp_events": 0, "xp_bytes": 0, "wire": 0}
	var alive_sum := 0.0
	var wire_sum := 0
	for bin in _bins:
		for key: String in peak:
			peak[key] = maxi(peak[key], bin[key])
		alive_sum += float(bin["alive"]) / maxf(bin["frames"], 1)
		wire_sum += bin["wire"]
	var rounds_played := _rounds_ended
	# The night ends: the room reports what is left (the night's report) and the writes are counted.
	_client.link.close()
	var waited := 0
	while not _server.match_ids().is_empty() and waited < 600:
		await get_tree().physics_frame
		waited += 1
	var report := {
		"xp": xp_on,
		"seed": _args.get_int("seed", 1),
		"count": _args.get_float("count", 5.0),
		"ceiling": _args.get_string("ceiling", "web"),
		"window": _args.get_int("window", 1),
		"grind": _args.get_float("grind", 0.0),
		"start_round": _args.get_int("startround", 8),
		"seconds": seconds,
		"ticks": ticks.size(),
		"tick_ms_mean": snappedf(total / maxf(ticks.size(), 1), 0.001),
		"tick_ms_p50": snappedf(_pick(ticks, 0.5), 0.001),
		"tick_ms_p99": snappedf(_pick(ticks, 0.99), 0.001),
		"tick_ms_worst": snappedf(ticks[ticks.size() - 1] if not ticks.is_empty() else 0.0, 0.001),
		"kills": _kills,
		"kills_per_s_mean": snappedf(_kills / maxf(seconds, 1.0), 0.01),
		"kills_per_s_peak": peak["kills"],
		"alive_mean": snappedf(alive_sum / maxf(seconds, 1.0), 0.1),
		"xp_events": _xp_events,
		"xp_events_per_s_mean": snappedf(_xp_events / maxf(seconds, 1.0), 0.01),
		"xp_events_per_s_peak": peak["xp_events"],
		"xp_bytes_per_s_mean": snappedf(_xp_bytes / maxf(seconds, 1.0), 0.1),
		"xp_bytes_per_s_peak": peak["xp_bytes"],
		"progress_events_other": _level_events,
		"wire_bytes_in_per_s_mean": snappedf(wire_sum / maxf(seconds, 1.0), 1.0),
		"wire_bytes_in_per_s_peak": peak["wire"],
		"xp_server_us_total": _xp_usec,
		"xp_server_us_per_kill": snappedf(float(_xp_usec) / maxf(_kills, 1), 0.01),
		"client_apply_us_total": _apply_usec,
		"client_apply_us_per_event": snappedf(float(_apply_usec) / maxf(_apply_count, 1), 0.01),
		"rounds_ended": rounds_played,
		"backend_writes": _posts,
		"calibration_ms": PerfSampler.calibrate(),
	}
	print("XP_HORDE_BENCH ", JSON.stringify(report))
	var out := _args.get_string("out")
	if out != "":
		var file := FileAccess.open(out, FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "  "))
		file.close()


func _pick(sorted: PackedFloat32Array, share: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[mini(int(sorted.size() * share), sorted.size() - 1)]
